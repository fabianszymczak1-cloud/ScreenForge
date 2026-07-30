import AppKit

@MainActor
final class CanvasView: NSView {
    var document: EditorDocument!
    var onChange: (() -> Void)?
    private let renderer = CanvasRenderer()
    private var dragStart: CGPoint?
    private var creatingObject: CanvasObject?
    private var movingIDs: Set<UUID> = []
    private var moveOriginFrames: [UUID: CGRect] = [:]
    private var moveOriginPoints: [UUID: [CGPoint]] = [:]
    private var spacePanning = false
    private var panStart: CGPoint?
    private var scrollOrigin: CGPoint = .zero
    private var cachedPreview: CGImage?
    private var isEditingText = false
    private var textEditorHost: NSView?
    private var textView: NSTextView?
    private var editingObjectID: UUID?
    private var textKeyMonitor: Any?
    /// Marquee selection while dragging on empty canvas in select tool.
    private var isMarqueeSelecting = false
    private var marqueeCurrent: CGPoint?

    private enum ResizeHandle: Equatable {
        case none, n, s, e, w, ne, nw, se, sw
        case lineStart, lineEnd
    }
    private var activeResizeHandle: ResizeHandle = .none
    private var resizingID: UUID?
    private var resizeOriginFrame: CGRect = .zero
    private var resizeOriginPoints: [CGPoint]?

    private static let canvasMargin: CGFloat = 16

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let document else { return }
        // Editor chrome — slightly cooler so the capture “page” stands out
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        }
        bounds.fill()

        let zoom = document.zoom
        let m = Self.canvasMargin
        // Pixel-align workspace — fractional zoom otherwise leaves a 1px fringe over the page backdrop.
        let canvas = CGRect(
            x: m,
            y: m,
            width: (document.canvasSize.width * zoom).rounded(.toNearestOrAwayFromZero),
            height: (document.canvasSize.height * zoom).rounded(.toNearestOrAwayFromZero)
        )

        // Opaque page (not checkerboard): subpixel/AA gaps used to show as “szachownica” stripes.
        NSColor.white.setFill()
        NSBezierPath(rect: canvas).fill()

        if let img = renderer.render(document, quality: .preview) {
            let ns = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
            ns.draw(
                in: canvas,
                from: NSRect(origin: .zero, size: ns.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
            )
        }

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: canvas.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        // Selection handles
        for obj in document.selectedObjects {
            if [.line, .arrow, .doubleArrow].contains(obj.type), let pts = obj.points, pts.count >= 2 {
                let a = docToView(CGRect(origin: pts[0], size: .zero)).origin
                let b = docToView(CGRect(origin: pts[pts.count - 1], size: .zero)).origin
                NSColor.systemTeal.setStroke()
                let path = NSBezierPath()
                path.move(to: a)
                path.line(to: b)
                path.lineWidth = 1.5
                path.stroke()
                drawHandle(at: a)
                drawHandle(at: b)
            } else {
                let r = docToView(obj.frame)
                NSColor.systemTeal.setStroke()
                let path = NSBezierPath(rect: r)
                path.lineWidth = 1.5
                path.stroke()
                drawHandles(r)
            }
        }

        // Crop overlay if needed
        if document.currentTool == .crop, let start = dragStart, let current = creatingObject {
            let r = docToView(current.frame)
            NSColor.black.withAlphaComponent(0.4).setFill()
            bounds.fill()
            NSColor.clear.set()
            // redraw image in crop? simplified: just stroke
            NSColor.white.setStroke()
            NSBezierPath(rect: r).stroke()
            _ = start
        }

        // Marquee rubber-band
        if isMarqueeSelecting, let start = dragStart, let cur = marqueeCurrent {
            let docRect = Self.normalizedRect(from: start, to: cur)
            let r = docToView(docRect)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: r).fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 1
            path.stroke()
        }
    }

    private static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func drawHandles(_ r: CGRect) {
        let pts = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ]
        for p in pts { drawHandle(at: p) }
    }

    private func drawHandle(at p: CGPoint) {
        NSColor.white.setFill()
        NSColor.systemTeal.setStroke()
        let h = NSBezierPath(rect: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        h.fill(); h.stroke()
    }

    /// Hit-test selection handles in view coordinates (larger than drawn for easier grabbing).
    private func hitSelectionHandle(at viewP: CGPoint) -> (UUID, ResizeHandle)? {
        let hitRadius: CGFloat = 10
        for obj in document.selectedObjects.reversed() {
            if [.line, .arrow, .doubleArrow].contains(obj.type), let pts = obj.points, pts.count >= 2 {
                let a = docToView(CGRect(origin: pts[0], size: .zero)).origin
                let b = docToView(CGRect(origin: pts[pts.count - 1], size: .zero)).origin
                if hypot(viewP.x - a.x, viewP.y - a.y) <= hitRadius { return (obj.id, .lineStart) }
                if hypot(viewP.x - b.x, viewP.y - b.y) <= hitRadius { return (obj.id, .lineEnd) }
                continue
            }
            let r = docToView(obj.frame)
            let handles: [(ResizeHandle, CGPoint)] = [
                (.nw, CGPoint(x: r.minX, y: r.minY)),
                (.n,  CGPoint(x: r.midX, y: r.minY)),
                (.ne, CGPoint(x: r.maxX, y: r.minY)),
                (.w,  CGPoint(x: r.minX, y: r.midY)),
                (.e,  CGPoint(x: r.maxX, y: r.midY)),
                (.sw, CGPoint(x: r.minX, y: r.maxY)),
                (.s,  CGPoint(x: r.midX, y: r.maxY)),
                (.se, CGPoint(x: r.maxX, y: r.maxY)),
            ]
            for (h, pt) in handles {
                if abs(viewP.x - pt.x) <= hitRadius && abs(viewP.y - pt.y) <= hitRadius {
                    return (obj.id, h)
                }
            }
        }
        return nil
    }

    private func resizedFrame(origin: CGRect, to docP: CGPoint, handle: ResizeHandle, lockAspect: Bool) -> CGRect {
        var r = origin
        let minSize: CGFloat = 4
        switch handle {
        case .n:
            let maxY = r.maxY
            r.origin.y = min(docP.y, maxY - minSize)
            r.size.height = maxY - r.origin.y
        case .s:
            r.size.height = max(minSize, docP.y - r.minY)
        case .e:
            r.size.width = max(minSize, docP.x - r.minX)
        case .w:
            let maxX = r.maxX
            r.origin.x = min(docP.x, maxX - minSize)
            r.size.width = maxX - r.origin.x
        case .ne:
            r.size.width = max(minSize, docP.x - r.minX)
            let maxY = r.maxY
            r.origin.y = min(docP.y, maxY - minSize)
            r.size.height = maxY - r.origin.y
        case .nw:
            let maxX = r.maxX
            let maxY = r.maxY
            r.origin.x = min(docP.x, maxX - minSize)
            r.origin.y = min(docP.y, maxY - minSize)
            r.size.width = maxX - r.origin.x
            r.size.height = maxY - r.origin.y
        case .se:
            r.size.width = max(minSize, docP.x - r.minX)
            r.size.height = max(minSize, docP.y - r.minY)
        case .sw:
            let maxX = r.maxX
            r.origin.x = min(docP.x, maxX - minSize)
            r.size.width = maxX - r.origin.x
            r.size.height = max(minSize, docP.y - r.minY)
        default:
            break
        }
        if lockAspect, origin.height > 0 {
            let aspect = origin.width / origin.height
            switch handle {
            case .n, .s:
                let newW = r.height * aspect
                r.origin.x = origin.midX - newW / 2
                r.size.width = newW
            case .e, .w:
                let newH = r.width / aspect
                r.origin.y = origin.midY - newH / 2
                r.size.height = newH
            case .ne, .nw, .se, .sw:
                let side = max(r.width, r.height)
                let newW = side
                let newH = side / aspect
                // Keep the opposite corner fixed
                let fixed: CGPoint
                switch handle {
                case .se: fixed = CGPoint(x: origin.minX, y: origin.minY)
                case .sw: fixed = CGPoint(x: origin.maxX, y: origin.minY)
                case .ne: fixed = CGPoint(x: origin.minX, y: origin.maxY)
                case .nw: fixed = CGPoint(x: origin.maxX, y: origin.maxY)
                default: fixed = origin.origin
                }
                switch handle {
                case .se:
                    r = CGRect(x: fixed.x, y: fixed.y, width: newW, height: newH)
                case .sw:
                    r = CGRect(x: fixed.x - newW, y: fixed.y, width: newW, height: newH)
                case .ne:
                    r = CGRect(x: fixed.x, y: fixed.y - newH, width: newW, height: newH)
                case .nw:
                    r = CGRect(x: fixed.x - newW, y: fixed.y - newH, width: newW, height: newH)
                default: break
                }
            default: break
            }
        }
        return r
    }

    private func applyProportionalPoints(from oldFrame: CGRect, to newFrame: CGRect, points: [CGPoint]) -> [CGPoint] {
        guard oldFrame.width > 0, oldFrame.height > 0 else { return points }
        let sx = newFrame.width / oldFrame.width
        let sy = newFrame.height / oldFrame.height
        return points.map { p in
            CGPoint(
                x: newFrame.minX + (p.x - oldFrame.minX) * sx,
                y: newFrame.minY + (p.y - oldFrame.minY) * sy
            )
        }
    }

    func docToView(_ r: CGRect) -> CGRect {
        let z = document.zoom
        let m = Self.canvasMargin
        return CGRect(x: m + r.origin.x * z, y: m + r.origin.y * z, width: r.width * z, height: r.height * z)
    }

    func viewToDoc(_ p: CGPoint) -> CGPoint {
        let z = document.zoom
        let m = Self.canvasMargin
        return CGPoint(x: (p.x - m) / z, y: (p.y - m) / z)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let docP = viewToDoc(p)

        // Finish text edit when clicking outside the editor
        if isEditingText {
            if let host = textEditorHost, host.frame.contains(p) {
                return
            }
            finishText(commit: true)
            // Fall through so the click also selects / starts a tool
        }

        if spacePanning {
            panStart = p
            return
        }
        let tool = document.currentTool
        if tool == .select {
            // Double-click text → edit
            if event.clickCount >= 2, let hit = hitTestObject(docP), [.text, .textBox, .callout].contains(hit.type) {
                document.selection = [hit.id]
                beginEditingText(objectID: hit.id)
                needsDisplay = true
                return
            }
            // Prefer resize handles over move when a selection exists
            if let (id, handle) = hitSelectionHandle(at: p),
               let obj = document.objects.first(where: { $0.id == id }) {
                document.selection = [id]
                activeResizeHandle = handle
                resizingID = id
                resizeOriginFrame = obj.frame
                resizeOriginPoints = obj.points
                dragStart = docP
                document.undoCoordinator.beginGroup()
                needsDisplay = true
                return
            }
            if let hit = hitTestObject(docP) {
                if event.modifierFlags.contains(.shift) {
                    if document.selection.contains(hit.id) { document.selection.remove(hit.id) }
                    else { document.selection.insert(hit.id) }
                } else if !document.selection.contains(hit.id) {
                    document.selection = [hit.id]
                }
                movingIDs = document.selection
                moveOriginFrames = Dictionary(uniqueKeysWithValues: document.selectedObjects.map { ($0.id, $0.frame) })
                moveOriginPoints = Dictionary(uniqueKeysWithValues: document.selectedObjects.compactMap { obj in
                    guard let pts = obj.points else { return nil }
                    return (obj.id, pts)
                })
                dragStart = docP
                document.undoCoordinator.beginGroup()
            } else {
                document.selection = []
                dragStart = docP
                isMarqueeSelecting = true
                marqueeCurrent = docP
            }
        } else if tool == .step {
            let style = document.style(for: .step)
            let size: CGFloat = 36
            var obj = CanvasObject(type: .step, frame: CGRect(x: docP.x - size/2, y: docP.y - size/2, width: size, height: size), style: style)
            obj.numberValue = document.nextStepNumber
            obj.text = "\(document.nextStepNumber)"
            document.nextStepNumber += 1
            document.addObject(obj)
            onChange?()
            needsDisplay = true
        } else if [.warning, .checkmark, .crossmark].contains(tool), let type = tool.objectType {
            let style = document.style(for: tool)
            let size: CGFloat = 36
            document.addObject(CanvasObject(type: type, frame: CGRect(x: docP.x - size/2, y: docP.y - size/2, width: size, height: size), style: style))
            onChange?()
            needsDisplay = true
        } else {
            // rectangle, ellipse, line, arrow, text, blur, pixelate, etc. — drag to define area
            dragStart = docP
            let type: CanvasObjectType
            if tool == .text {
                type = .textBox
            } else {
                type = tool.objectType ?? .rectangle
            }
            var style = document.style(for: tool)
            var obj = CanvasObject(type: type, frame: CGRect(origin: docP, size: .zero), style: style)
            if tool == .text {
                obj.text = ""
                style.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.15)
                style.strokeColor = NSColor.systemTeal.withAlphaComponent(0.6)
                style.strokeWidth = 1
                obj.style = style
            }
            if let fk: FilterKind = {
                switch tool {
                case .blur: return .blur
                case .pixelate: return .pixelate
                case .solidRedact: return .solidRedact
                case .highlight: return .highlight
                case .focusArea: return .focusDim
                case .magnify: return .magnify
                default: return nil
                }
            }() {
                obj.filterKind = fk
                obj.filterAmount = tool == .pixelate ? 12 : (tool == .magnify ? 10 : 8)
            }
            creatingObject = obj
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let docP = viewToDoc(p)
        if spacePanning, let start = panStart, let sv = enclosingScrollView {
            let dx = p.x - start.x
            let dy = p.y - start.y
            var origin = sv.contentView.bounds.origin
            origin.x -= dx; origin.y -= dy
            sv.contentView.setBoundsOrigin(origin)
            panStart = p
            return
        }
        if let id = resizingID, activeResizeHandle != .none,
           let i = document.objects.firstIndex(where: { $0.id == id }) {
            let lockAspect = event.modifierFlags.contains(.shift)
            if activeResizeHandle == .lineStart || activeResizeHandle == .lineEnd {
                var pts = resizeOriginPoints ?? document.objects[i].points ?? []
                guard pts.count >= 2 else { return }
                if activeResizeHandle == .lineStart {
                    pts[0] = docP
                } else {
                    pts[pts.count - 1] = docP
                }
                document.objects[i].points = pts
                let xs = pts.map(\.x), ys = pts.map(\.y)
                document.objects[i].frame = CGRect(
                    x: xs.min()!, y: ys.min()!,
                    width: max(xs.max()! - xs.min()!, 1),
                    height: max(ys.max()! - ys.min()!, 1)
                )
            } else {
                let newFrame = resizedFrame(
                    origin: resizeOriginFrame,
                    to: docP,
                    handle: activeResizeHandle,
                    lockAspect: lockAspect
                )
                document.objects[i].frame = newFrame
                if let opts = resizeOriginPoints, !opts.isEmpty {
                    document.objects[i].points = applyProportionalPoints(
                        from: resizeOriginFrame, to: newFrame, points: opts
                    )
                }
            }
            needsDisplay = true
            return
        }
        if !movingIDs.isEmpty, let originFrames = Optional(moveOriginFrames), !originFrames.isEmpty {
            guard let start = dragStart else { return }
            let dx = docP.x - start.x
            let dy = docP.y - start.y
            for id in movingIDs {
                if let i = document.objects.firstIndex(where: { $0.id == id }), let orig = originFrames[id] {
                    document.objects[i].frame = orig.offsetBy(dx: dx, dy: dy)
                    if let opts = moveOriginPoints[id] {
                        document.objects[i].points = opts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                    }
                }
            }
            needsDisplay = true
            return
        }
        if isMarqueeSelecting, let start = dragStart {
            marqueeCurrent = docP
            let rect = Self.normalizedRect(from: start, to: docP)
            document.selection = Set(
                document.objects.filter { $0.isVisible && !$0.isLocked && $0.frame.intersects(rect) }.map(\.id)
            )
            needsDisplay = true
            return
        }
        if var obj = creatingObject, let start = dragStart {
            var rect = CGRect(x: min(start.x, docP.x), y: min(start.y, docP.y), width: abs(docP.x - start.x), height: abs(docP.y - start.y))
            if event.modifierFlags.contains(.shift) {
                let side = max(rect.width, rect.height)
                rect.size = CGSize(width: side, height: side)
            }
            obj.frame = rect
            if [.arrow, .line, .doubleArrow].contains(obj.type) {
                obj.points = [start, docP]
                obj.frame = CGRect(x: min(start.x, docP.x), y: min(start.y, docP.y), width: max(abs(docP.x - start.x), 1), height: max(abs(docP.y - start.y), 1))
            }
            if [.freehand, .marker].contains(obj.type) {
                var pts = obj.points ?? [start]
                pts.append(docP)
                obj.points = pts
                let xs = pts.map(\.x), ys = pts.map(\.y)
                obj.frame = CGRect(x: xs.min()!, y: ys.min()!, width: max(xs.max()! - xs.min()!, 1), height: max(ys.max()! - ys.min()!, 1))
            }
            creatingObject = obj
            needsDisplay = true
            previewCreating(obj)
        }
    }

    private var previewID: UUID?

    private func previewCreating(_ obj: CanvasObject) {
        if let pid = previewID, let i = document.objects.firstIndex(where: { $0.id == pid }) {
            document.objects[i] = obj
        } else {
            var o = obj
            // don't use addObject to avoid undo spam
            o.zIndex = 99999
            document.objects.append(o)
            previewID = o.id
            creatingObject = o
        }
    }

    override func mouseUp(with event: NSEvent) {
        if resizingID != nil {
            registerResizeUndoIfNeeded()
            document.undoCoordinator.endGroup()
            document.isDirty = true
            resizingID = nil
            activeResizeHandle = .none
            resizeOriginPoints = nil
            resizeOriginFrame = .zero
            dragStart = nil
            onChange?()
            needsDisplay = true
            return
        }
        if !movingIDs.isEmpty {
            registerMoveUndoIfNeeded()
            document.undoCoordinator.endGroup()
            document.isDirty = true
            movingIDs = []
            moveOriginFrames = [:]
            moveOriginPoints = [:]
            dragStart = nil
            onChange?()
            needsDisplay = true
            return
        }
        if isMarqueeSelecting {
            if let start = dragStart, let cur = marqueeCurrent {
                let rect = Self.normalizedRect(from: start, to: cur)
                if rect.width > 2 || rect.height > 2 {
                    document.selection = Set(
                        document.objects.filter { $0.isVisible && !$0.isLocked && $0.frame.intersects(rect) }.map(\.id)
                    )
                }
            }
            isMarqueeSelecting = false
            marqueeCurrent = nil
            dragStart = nil
            onChange?()
            needsDisplay = true
            return
        }
        if let obj = creatingObject {
            if let pid = previewID {
                document.objects.removeAll { $0.id == pid }
            }
            previewID = nil
            let created = obj.frame.width > 2 || obj.frame.height > 2 || obj.points?.count ?? 0 > 2
            if created {
                if document.currentTool == .crop {
                    applyCrop(obj.frame)
                } else if document.currentTool == .text || obj.type == .textBox {
                    var box = obj
                    // Restore drawing style for the committed text box (no guide chrome)
                    box.style = document.style(for: .text)
                    box.text = ""
                    document.addObject(box)
                    beginEditingText(objectID: box.id)
                } else {
                    document.addObject(obj)
                }
            } else {
                // Empty click (no drag) — switch to select so the next click can pick objects
                document.currentTool = .select
            }
            creatingObject = nil
            dragStart = nil
            onChange?()
            needsDisplay = true
        }
    }

    private func registerMoveUndoIfNeeded() {
        let ids = movingIDs
        let beforeFrames = moveOriginFrames
        let beforePoints = moveOriginPoints
        var afterFrames: [UUID: CGRect] = [:]
        var afterPoints: [UUID: [CGPoint]] = [:]
        var changed = false
        for id in ids {
            guard let obj = document.objects.first(where: { $0.id == id }) else { continue }
            afterFrames[id] = obj.frame
            if let pts = obj.points { afterPoints[id] = pts }
            if let bf = beforeFrames[id], bf != obj.frame { changed = true }
            if let bp = beforePoints[id], bp != obj.points { changed = true }
        }
        guard changed else { return }
        document.undoCoordinator.register(UndoCommand(
            undo: { [weak document] in
                guard let document else { return }
                for id in ids {
                    guard let i = document.objects.firstIndex(where: { $0.id == id }) else { continue }
                    if let f = beforeFrames[id] { document.objects[i].frame = f }
                    if let p = beforePoints[id] { document.objects[i].points = p }
                }
            },
            redo: { [weak document] in
                guard let document else { return }
                for id in ids {
                    guard let i = document.objects.firstIndex(where: { $0.id == id }) else { continue }
                    if let f = afterFrames[id] { document.objects[i].frame = f }
                    if let p = afterPoints[id] { document.objects[i].points = p }
                }
            }
        ))
    }

    private func registerResizeUndoIfNeeded() {
        guard let id = resizingID,
              let obj = document.objects.first(where: { $0.id == id }) else { return }
        let beforeFrame = resizeOriginFrame
        let beforePoints = resizeOriginPoints
        let afterFrame = obj.frame
        let afterPoints = obj.points
        guard beforeFrame != afterFrame || beforePoints != afterPoints else { return }
        document.undoCoordinator.register(UndoCommand(
            undo: { [weak document] in
                guard let document, let i = document.objects.firstIndex(where: { $0.id == id }) else { return }
                document.objects[i].frame = beforeFrame
                document.objects[i].points = beforePoints
            },
            redo: { [weak document] in
                guard let document, let i = document.objects.firstIndex(where: { $0.id == id }) else { return }
                document.objects[i].frame = afterFrame
                document.objects[i].points = afterPoints
            }
        ))
    }

    private func applyCrop(_ rect: CGRect) {
        guard let base = document.baseImage else { return }
        let integral = rect.integral
        guard let cropped = base.cropping(to: integral) else { return }
        let oldBase = base
        let oldSize = document.canvasSize
        let oldObjects = document.objects
        document.undoCoordinator.register(UndoCommand(
            undo: { [weak document] in
                document?.baseImage = oldBase
                document?.canvasSize = oldSize
                document?.objects = oldObjects
            },
            redo: { [weak document] in
                document?.baseImage = cropped
                document?.canvasSize = CGSize(width: cropped.width, height: cropped.height)
                document?.objects = []
            }
        ))
        document.baseImage = cropped
        document.canvasSize = CGSize(width: cropped.width, height: cropped.height)
        document.objects = []
        document.currentTool = .select
        document.isDirty = true
        invalidateIntrinsicContentSize()
    }

    private func beginEditingText(objectID: UUID) {
        guard let obj = document.objects.first(where: { $0.id == objectID }) else { return }
        finishText(commit: false)

        let frame = docToView(obj.frame)
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.wantsLayer = true
        scroll.layer?.borderColor = NSColor.controlAccentColor.cgColor
        scroll.layer?.borderWidth = 1.5

        let tv = NSTextView(frame: scroll.contentView.bounds)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.string = obj.text ?? ""
        let style = obj.style
        tv.font = NSFont(name: style.fontName, size: style.fontSize) ?? .systemFont(ofSize: style.fontSize)
        tv.textColor = style.textColor
        tv.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92)
        tv.drawsBackground = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.delegate = self

        scroll.documentView = tv
        addSubview(scroll)
        window?.makeFirstResponder(tv)

        textEditorHost = scroll
        textView = tv
        editingObjectID = objectID
        isEditingText = true
        if let i = document.objects.firstIndex(where: { $0.id == objectID }) {
            document.objects[i].isVisible = false
        }
        textKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEditingText else { return event }
            if event.keyCode == 53 { // Escape
                self.finishText(commit: true)
                return nil
            }
            return event
        }
        needsDisplay = true
    }

    func finishText(commit: Bool = true) {
        guard isEditingText else { return }
        let text = textView?.string ?? ""
        let id = editingObjectID
        if let textKeyMonitor {
            NSEvent.removeMonitor(textKeyMonitor)
            self.textKeyMonitor = nil
        }
        isEditingText = false
        editingObjectID = nil
        textEditorHost?.removeFromSuperview()
        textEditorHost = nil
        textView = nil

        if let id, let i = document.objects.firstIndex(where: { $0.id == id }) {
            document.objects[i].isVisible = true
            if commit {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    document.objects.remove(at: i)
                    document.selection.remove(id)
                } else {
                    document.objects[i].text = text
                    document.selection = [id]
                    document.isDirty = true
                }
            }
        }
        document.currentTool = .select
        onChange?()
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func hitTestObject(_ p: CGPoint) -> CanvasObject? {
        document.objects.sorted { $0.zIndex > $1.zIndex }.first { $0.isVisible && !$0.isLocked && $0.frame.insetBy(dx: -4, dy: -4).contains(p) }
    }

    override func keyDown(with event: NSEvent) {
        if isEditingText { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z" where flags.contains(.shift):
                document.undoCoordinator.redo(); needsDisplay = true; onChange?(); return
            case "y":
                document.undoCoordinator.redo(); needsDisplay = true; onChange?(); return
            case "z":
                document.undoCoordinator.undo(); needsDisplay = true; onChange?(); return
            case "v":
                if pasteImageFromClipboard() { return }
            case "a":
                document.selection = Set(document.objects.map(\.id)); needsDisplay = true; return
            case "d":
                document.duplicateSelected(); needsDisplay = true; onChange?(); return
            case "c":
                copySelectionOrImage(); return
            case "+", "=":
                document.zoom = min(8, document.zoom * 1.1); invalidateIntrinsicContentSize(); needsDisplay = true; return
            case "-":
                document.zoom = max(0.1, document.zoom / 1.1); invalidateIntrinsicContentSize(); needsDisplay = true; return
            case "0":
                document.zoom = 1; invalidateIntrinsicContentSize(); needsDisplay = true; return
            case "1":
                fitToWindow(); return
            default: break
            }
        }
        if event.keyCode == 51 || event.keyCode == 117 { // delete
            document.deleteSelected(); needsDisplay = true; onChange?(); return
        }
        if event.keyCode == 49 { // space
            spacePanning = true; NSCursor.openHand.set(); return
        }
        if event.keyCode == 53 { // escape
            if isEditingText {
                finishText(commit: true)
                return
            }
            if document.currentTool != .select {
                document.currentTool = .select
            } else {
                document.selection = []
            }
            needsDisplay = true
            return
        }
        // Tool shortcuts
        if let chars = event.charactersIgnoringModifiers?.uppercased() {
            let map: [String: EditorTool] = [
                "V": .select, "R": .rectangle, "E": .ellipse, "L": .line, "A": .arrow,
                "F": .freehand, "T": .text, "N": .step, "H": .highlight, "B": .blur,
                "P": .pixelate, "C": .crop, "M": .magnify, "I": .image, "O": .solidRedact
            ]
            if let tool = map[chars] {
                document.currentTool = tool
                onChange?()
                return
            }
        }
        // Arrow nudge
        if [123,124,125,126].contains(event.keyCode) {
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch event.keyCode {
            case 123: dx = -step
            case 124: dx = step
            case 125: dy = step
            case 126: dy = -step
            default: break
            }
            for id in document.selection {
                if let i = document.objects.firstIndex(where: { $0.id == id }) {
                    document.objects[i].frame = document.objects[i].frame.offsetBy(dx: dx, dy: dy)
                }
            }
            document.isDirty = true
            needsDisplay = true
            onChange?()
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spacePanning = false
            NSCursor.arrow.set()
        }
        super.keyUp(with: event)
    }

    override func magnify(with event: NSEvent) {
        document.zoom = max(0.1, min(8, document.zoom * (1 + event.magnification)))
        invalidateIntrinsicContentSize()
        needsDisplay = true
        onChange?()
    }

    private func copySelectionOrImage() {
        if let img = renderer.render(document, quality: .full) {
            AppServices.shared.clipboard.copy(img, includeTIFF: true)
        }
    }

    @discardableResult
    func pasteImageFromClipboard() -> Bool {
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / CGFloat(max(img.width, img.height)))
        let w = max(1, CGFloat(img.width) * scale)
        let h = max(1, CGFloat(img.height) * scale)
        let origin = CGPoint(
            x: max(0, (document.canvasSize.width - w) / 2),
            y: max(0, (document.canvasSize.height - h) / 2)
        )
        var obj = CanvasObject(type: .image, frame: CGRect(origin: origin, size: CGSize(width: w, height: h)))
        obj.embeddedImage = img
        document.addObject(obj)
        document.selection = [obj.id]
        document.currentTool = .select
        needsDisplay = true
        onChange?()
        return true
    }

    func fitToWindow() {
        guard let sv = enclosingScrollView else { return }
        let avail = sv.contentView.bounds.size
        let pad = Self.canvasMargin * 2 + 8
        let zw = (avail.width - pad) / max(document.canvasSize.width, 1)
        let zh = (avail.height - pad) / max(document.canvasSize.height, 1)
        document.zoom = max(0.1, min(zw, zh, 1))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        guard let document else { return .zero }
        let pad = Self.canvasMargin * 2 + 8
        return NSSize(
            width: document.canvasSize.width * document.zoom + pad,
            height: document.canvasSize.height * document.zoom + pad
        )
    }
}

extension CanvasView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        // Commit when focus leaves the text view (e.g. Tab), but not during our own finishText teardown
        if isEditingText {
            finishText(commit: true)
        }
    }
}
