import AppKit

@MainActor
protocol RegionSelectionViewDelegate: AnyObject {
    func regionSelectionDidComplete(displayID: CGDirectDisplayID, pixelRect: CGRect, pointRect: CGRect)
    func regionSelectionDidCancel()
    func regionSelectionRequestWindowMode()
}

@MainActor
final class RegionSelectionView: NSView {
    weak var delegate: RegionSelectionViewDelegate?
    let frozenImage: CGImage
    let displayInfo: DisplayInfo
    let settings: SettingsStore
    private let coordinates = CoordinateConverter()

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect?
    private var isMoving = false
    private var isResizing = false
    private var resizeHandle: ResizeHandle = .none
    private var dragOffset: CGPoint = .zero
    private var magnifierEnabled: Bool
    private var aspectLocked = false
    private var fromCenter = false
    private var sizeField: NSTextField?

    enum ResizeHandle { case none, n, s, e, w, ne, nw, se, sw }

    init(frozenImage: CGImage, displayInfo: DisplayInfo, settings: SettingsStore) {
        self.frozenImage = frozenImage
        self.displayInfo = displayInfo
        self.settings = settings
        self.magnifierEnabled = settings.showMagnifier
        super.init(frame: .zero)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        // ScreenCaptureKit frames are upright — draw via CGContext like the editor.
        ctx.interpolationQuality = .high
        ctx.draw(frozenImage, in: bounds)

        // Dim overlay
        let dim = CGFloat(settings.dimOpacity)
        ctx.setFillColor(NSColor.black.withAlphaComponent(dim).cgColor)
        if let sel = selectionRect, sel.width > 0, sel.height > 0 {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(sel)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            // Border
            let color = NSColor(hex: settings.selectionBorderColor) ?? NSColor.systemTeal
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(sel)
            drawHandles(sel, in: ctx)
            if settings.showDimensions {
                drawDimensionLabel(sel, in: ctx)
            }
        } else {
            ctx.setFillColor(NSColor.black.withAlphaComponent(dim).cgColor)
            ctx.fill(bounds)
            // Crosshair
            let mouse = mouseInView()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: mouse.x, y: 0)); ctx.addLine(to: CGPoint(x: mouse.x, y: bounds.height)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 0, y: mouse.y)); ctx.addLine(to: CGPoint(x: bounds.width, y: mouse.y)); ctx.strokePath()
        }

        if magnifierEnabled {
            drawMagnifier(in: ctx)
        }
    }

    private func drawHandles(_ rect: CGRect, in ctx: CGContext) {
        let size: CGFloat = 8
        let points = handlePoints(rect)
        ctx.setFillColor(NSColor.white.cgColor)
        for p in points {
            ctx.fill(CGRect(x: p.x - size/2, y: p.y - size/2, width: size, height: size))
        }
    }

    private func handlePoints(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
    }

    private func drawDimensionLabel(_ rect: CGRect, in ctx: CGContext) {
        let w = Int((rect.width * imageScaleX).rounded())
        let h = Int((rect.height * imageScaleY).rounded())
        let text = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width/2, y: rect.minY - size.height - 8)
        let bg = CGRect(x: origin.x - 6, y: origin.y - 2, width: size.width + 12, height: size.height + 4)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.fill(bg)
        text.draw(at: origin, withAttributes: attrs)
    }

    /// Scale from view points to frozen CGImage pixels (authoritative — not NSScreen.backingScaleFactor).
    private var imageScaleX: CGFloat { CGFloat(frozenImage.width) / max(bounds.width, 1) }
    private var imageScaleY: CGFloat { CGFloat(frozenImage.height) / max(bounds.height, 1) }

    private func mouseInView() -> CGPoint {
        guard let window else { return .zero }
        let screen = NSEvent.mouseLocation
        let winP = window.convertPoint(fromScreen: screen)
        return convert(winP, from: nil)
    }

    private func viewRectToImagePixels(_ rect: CGRect) -> CGRect {
        // Non-flipped view: origin bottom-left. CGImage crop: origin top-left.
        var r = CGRect(
            x: rect.origin.x * imageScaleX,
            y: (bounds.height - rect.maxY) * imageScaleY,
            width: rect.width * imageScaleX,
            height: rect.height * imageScaleY
        ).integral
        let maxW = CGFloat(frozenImage.width)
        let maxH = CGFloat(frozenImage.height)
        r.origin.x = max(0, min(r.origin.x, maxW - 1))
        r.origin.y = max(0, min(r.origin.y, maxH - 1))
        r.size.width = max(1, min(r.size.width, maxW - r.origin.x))
        r.size.height = max(1, min(r.size.height, maxH - r.origin.y))
        return r
    }

    private func drawMagnifier(in ctx: CGContext) {
        let mouse = mouseInView()
        let samplePts: CGFloat = 28
        let zoom = max(CGFloat(settings.magnifierZoom), 4)
        let magSize: CGFloat = max(180, samplePts * zoom)
        var magOrigin = CGPoint(x: mouse.x + 32, y: mouse.y + 32)
        if magOrigin.x + magSize + 12 > bounds.width { magOrigin.x = mouse.x - magSize - 32 }
        if magOrigin.y + magSize + 48 > bounds.height { magOrigin.y = mouse.y - magSize - 48 }

        let sample = CGRect(x: mouse.x - samplePts/2, y: mouse.y - samplePts/2, width: samplePts, height: samplePts)
        let localSrc = viewRectToImagePixels(sample)
        let border = CGRect(x: magOrigin.x - 3, y: magOrigin.y - 3, width: magSize + 6, height: magSize + 6)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        ctx.fill(border)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(border)

        let dest = CGRect(x: magOrigin.x, y: magOrigin.y, width: magSize, height: magSize)
        if let cropped = frozenImage.cropping(to: localSrc) {
            // Same upright CGImage path as CanvasRenderer (no Y flip).
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.draw(cropped, in: dest)
            ctx.restoreGState()
        }

        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1)
        let cx = magOrigin.x + magSize/2
        let cy = magOrigin.y + magSize/2
        ctx.move(to: CGPoint(x: cx, y: magOrigin.y)); ctx.addLine(to: CGPoint(x: cx, y: magOrigin.y + magSize)); ctx.strokePath()
        ctx.move(to: CGPoint(x: magOrigin.x, y: cy)); ctx.addLine(to: CGPoint(x: magOrigin.x + magSize, y: cy)); ctx.strokePath()

        if settings.showCoordinates {
            let px = Int((mouse.x * imageScaleX).rounded())
            let py = Int(((bounds.height - mouse.y) * imageScaleY).rounded())
            var label = "\(px), \(py)"
            if let sel = selectionRect {
                label += "  \(Int((sel.width*imageScaleX).rounded()))×\(Int((sel.height*imageScaleY).rounded()))"
            }
            let ns = label as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
            ns.draw(at: CGPoint(x: magOrigin.x, y: magOrigin.y - 18), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let sel = selectionRect {
            let handle = hitHandle(p, in: sel)
            if handle != .none {
                isResizing = true
                resizeHandle = handle
                return
            }
            if sel.contains(p) {
                isMoving = true
                dragOffset = CGPoint(x: p.x - sel.origin.x, y: p.y - sel.origin.y)
                return
            }
        }
        startPoint = p
        currentPoint = p
        selectionRect = nil
        aspectLocked = event.modifierFlags.contains(.shift)
        fromCenter = event.modifierFlags.contains(.option)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        aspectLocked = event.modifierFlags.contains(.shift)
        fromCenter = event.modifierFlags.contains(.option)
        if isMoving, var sel = selectionRect {
            sel.origin = CGPoint(x: p.x - dragOffset.x, y: p.y - dragOffset.y)
            selectionRect = clamp(sel)
        } else if isResizing, var sel = selectionRect {
            sel = resize(sel, to: p, handle: resizeHandle)
            selectionRect = clamp(sel)
        } else if let start = startPoint {
            currentPoint = p
            selectionRect = makeRect(from: start, to: p)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isMoving || isResizing {
            isMoving = false
            isResizing = false
            resizeHandle = .none
            needsDisplay = true
            return
        }
        if let sel = selectionRect, sel.width > 2, sel.height > 2 {
            // Keep selection for fine-tuning; double-check: single click-drag completes on mouse up for speed
            completeSelection()
        } else {
            startPoint = nil
            selectionRect = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        needsDisplay = true
        NSCursor.crosshair.set()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Escape
            delegate?.regionSelectionDidCancel()
        case 36, 76: // Return
            completeSelection()
        case 49: // Space
            delegate?.regionSelectionRequestWindowMode()
        case 6: // Z
            magnifierEnabled.toggle()
            needsDisplay = true
        case 123, 124, 125, 126: // arrows
            handleArrow(event.keyCode, flags: flags)
        default:
            super.keyDown(with: event)
        }
    }

    private func handleArrow(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let step: CGFloat = flags.contains(.shift) ? 10 : 1
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = -step
        case 126: dy = step
        default: break
        }
        if flags.contains(.command), var sel = selectionRect {
            sel.size.width += dx
            sel.size.height += dy
            selectionRect = clamp(sel)
        } else if var sel = selectionRect {
            sel.origin.x += dx
            sel.origin.y += dy
            selectionRect = clamp(sel)
        } else {
            // move virtual cursor via CGWarpMouseCursorPosition would need conversion
        }
        needsDisplay = true
    }

    private func completeSelection() {
        guard let sel = selectionRect, sel.width > 2, sel.height > 2 else { return }
        let pixels = viewRectToImagePixels(sel)
        // View is display-local AppKit points (bottom-left); map to global screen points.
        let global = CGRect(
            x: sel.origin.x + displayInfo.geometry.framePoints.origin.x,
            y: sel.origin.y + displayInfo.geometry.framePoints.origin.y,
            width: sel.width,
            height: sel.height
        )
        delegate?.regionSelectionDidComplete(displayID: displayInfo.id, pixelRect: pixels, pointRect: global)
    }

    /// Called from the coordinator key monitor (Return).
    func confirmIfPossible() {
        completeSelection()
    }

    private func makeRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        var rect: CGRect
        if fromCenter {
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            rect = CGRect(x: a.x - dx, y: a.y - dy, width: dx * 2, height: dy * 2)
        } else {
            rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        }
        if aspectLocked {
            let side = max(rect.width, rect.height)
            if fromCenter {
                rect = CGRect(x: a.x - side, y: a.y - side, width: side * 2, height: side * 2)
            } else {
                rect.size = CGSize(width: side, height: side)
            }
        }
        return clamp(rect)
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(0, min(r.origin.x, bounds.width - 1))
        r.origin.y = max(0, min(r.origin.y, bounds.height - 1))
        r.size.width = max(1, min(r.size.width, bounds.width - r.origin.x))
        r.size.height = max(1, min(r.size.height, bounds.height - r.origin.y))
        return r
    }

    private func hitHandle(_ p: CGPoint, in rect: CGRect) -> ResizeHandle {
        let handles: [(ResizeHandle, CGPoint)] = [
            (.n, CGPoint(x: rect.midX, y: rect.maxY)),
            (.s, CGPoint(x: rect.midX, y: rect.minY)),
            (.e, CGPoint(x: rect.maxX, y: rect.midY)),
            (.w, CGPoint(x: rect.minX, y: rect.midY)),
            (.ne, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.nw, CGPoint(x: rect.minX, y: rect.maxY)),
            (.se, CGPoint(x: rect.maxX, y: rect.minY)),
            (.sw, CGPoint(x: rect.minX, y: rect.minY)),
        ]
        for (h, pt) in handles {
            if abs(p.x - pt.x) < 8 && abs(p.y - pt.y) < 8 { return h }
        }
        return .none
    }

    private func resize(_ rect: CGRect, to p: CGPoint, handle: ResizeHandle) -> CGRect {
        var r = rect
        switch handle {
        case .n: r.size.height = max(1, p.y - r.minY)
        case .s: let maxY = r.maxY; r.origin.y = p.y; r.size.height = max(1, maxY - p.y)
        case .e: r.size.width = max(1, p.x - r.minX)
        case .w: let maxX = r.maxX; r.origin.x = p.x; r.size.width = max(1, maxX - p.x)
        case .ne: r.size.width = max(1, p.x - r.minX); r.size.height = max(1, p.y - r.minY)
        case .nw: let maxX = r.maxX; r.origin.x = p.x; r.size.width = max(1, maxX - p.x); r.size.height = max(1, p.y - r.minY)
        case .se: r.size.width = max(1, p.x - r.minX); let maxY = r.maxY; r.origin.y = min(p.y, maxY); r.size.height = max(1, maxY - r.origin.y)
        case .sw: let maxX = r.maxX; let maxY = r.maxY; r.origin.x = p.x; r.origin.y = min(p.y, maxY); r.size.width = max(1, maxX - p.x); r.size.height = max(1, maxY - r.origin.y)
        case .none: break
        }
        return r
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xff)/255, green: CGFloat((v >> 8) & 0xff)/255, blue: CGFloat(v & 0xff)/255, alpha: 1)
    }
}
