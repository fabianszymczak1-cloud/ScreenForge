import Foundation
import AppKit
import CoreImage

@MainActor
final class CanvasRenderer {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func render(_ document: EditorDocument, quality: RenderQuality = .full) -> CGImage? {
        let w = Int(document.canvasSize.width)
        let h = Int(document.canvasSize.height)
        guard w > 0, h > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Opaque page — avoids transparent fringe showing as editor checkerboard / export holes.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        if let base = document.baseImage {
            // ScreenCaptureKit CGImages are upright — draw without Y flip.
            ctx.interpolationQuality = .none
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Apply region filters first (as effects on base), then vector objects
        let filters = document.objects.filter { $0.isVisible && isFilter($0.type) }.sorted { $0.zIndex < $1.zIndex }
        let vectors = document.objects.filter { $0.isVisible && !isFilter($0.type) }.sorted { $0.zIndex < $1.zIndex }

        if !filters.isEmpty, let current = ctx.makeImage() {
            var working = current
            for f in filters {
                if let applied = applyFilter(f, to: working, canvasSize: document.canvasSize, quality: quality) {
                    working = applied
                }
            }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(working, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        for obj in vectors {
            drawObject(obj, in: ctx, canvasHeight: CGFloat(h))
        }
        return ctx.makeImage()
    }

    func renderThumbnail(_ document: EditorDocument, maxSide: CGFloat = 200) -> CGImage? {
        guard let full = render(document, quality: .preview) else { return nil }
        let scale = Swift.min(maxSide / CGFloat(full.width), maxSide / CGFloat(full.height), 1)
        let tw = Swift.max(1, Int(CGFloat(full.width) * scale))
        let th = Swift.max(1, Int(CGFloat(full.height) * scale))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = CGInterpolationQuality.medium
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    private func isFilter(_ type: CanvasObjectType) -> Bool {
        [.blur, .pixelate, .solidRedact, .highlight, .focusArea, .magnify].contains(type)
    }

    private func drawObject(_ obj: CanvasObject, in ctx: CGContext, canvasHeight: CGFloat) {
        ctx.saveGState()
        ctx.setAlpha(obj.style.opacity)
        let frame = obj.frame
        // Document coords are top-left; CGContext is bottom-left
        let cgFrame = CGRect(x: frame.origin.x, y: canvasHeight - frame.origin.y - frame.height, width: frame.width, height: frame.height)
        if obj.rotation != 0 {
            ctx.translateBy(x: cgFrame.midX, y: cgFrame.midY)
            ctx.rotate(by: -obj.rotation * .pi / 180)
            ctx.translateBy(x: -cgFrame.midX, y: -cgFrame.midY)
        }

        switch obj.type {
        case .rectangle:
            strokeFill(rect: cgFrame, style: obj.style, corner: 0, in: ctx)
        case .roundedRectangle:
            strokeFill(rect: cgFrame, style: obj.style, corner: obj.style.cornerRadius, in: ctx)
        case .ellipse:
            ctx.setStrokeColor(obj.style.strokeColor.cgColor)
            ctx.setFillColor(obj.style.fillColor.cgColor)
            ctx.setLineWidth(obj.style.strokeWidth)
            ctx.fillEllipse(in: cgFrame)
            ctx.strokeEllipse(in: cgFrame)
        case .line, .arrow, .doubleArrow:
            drawLine(obj, canvasHeight: canvasHeight, in: ctx)
        case .freehand, .marker, .polyline:
            drawPolyline(obj, canvasHeight: canvasHeight, in: ctx)
        case .text, .textBox:
            drawText(obj, cgFrame: cgFrame, in: ctx)
        case .callout:
            strokeFill(rect: cgFrame, style: obj.style, corner: 8, in: ctx)
            drawText(obj, cgFrame: cgFrame.insetBy(dx: 8, dy: 8), in: ctx)
        case .step:
            drawStep(obj, cgFrame: cgFrame, in: ctx)
        case .warning, .checkmark, .crossmark:
            drawSymbol(obj, cgFrame: cgFrame, in: ctx)
        case .image, .cursor, .watermark:
            if let img = obj.embeddedImage {
                ctx.draw(img, in: cgFrame)
            }
        case .border:
            ctx.setStrokeColor(obj.style.strokeColor.cgColor)
            ctx.setLineWidth(obj.style.strokeWidth)
            ctx.stroke(cgFrame)
        default:
            break
        }
        ctx.restoreGState()
    }

    private func strokeFill(rect: CGRect, style: ObjectStyle, corner: CGFloat, in ctx: CGContext) {
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.setFillColor(style.fillColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(style.strokeColor.cgColor)
        ctx.setLineWidth(style.strokeWidth)
        if !style.lineDash.isEmpty { ctx.setLineDash(phase: 0, lengths: style.lineDash) }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private func drawLine(_ obj: CanvasObject, canvasHeight: CGFloat, in ctx: CGContext) {
        let p0: CGPoint
        let p1: CGPoint
        if let pts = obj.points, pts.count >= 2 {
            let a = pts[0]
            let b = pts[pts.count - 1]
            p0 = CGPoint(x: a.x, y: canvasHeight - a.y)
            p1 = CGPoint(x: b.x, y: canvasHeight - b.y)
        } else {
            let frame = obj.frame
            p0 = CGPoint(x: frame.minX, y: canvasHeight - frame.midY)
            p1 = CGPoint(x: frame.maxX, y: canvasHeight - frame.midY)
        }

        let stroke = max(1, obj.style.strokeWidth)
        // Arrowhead grows with stroke so it stays visible and sharp
        let headSize = max(obj.style.arrowHeadSize, stroke * 3.2 + 6)
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)

        ctx.setStrokeColor(obj.style.strokeColor.cgColor)
        ctx.setFillColor(obj.style.strokeColor.cgColor)
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.miter)

        // Shorten shaft so thick stroke doesn't swallow the head
        var shaftEnd = p1
        if obj.type == .arrow || obj.type == .doubleArrow {
            let shorten = headSize * 0.72
            shaftEnd = CGPoint(x: p1.x - cos(angle) * shorten, y: p1.y - sin(angle) * shorten)
        }
        var shaftStart = p0
        if obj.type == .doubleArrow {
            let shorten = headSize * 0.72
            shaftStart = CGPoint(x: p0.x + cos(angle) * shorten, y: p0.y + sin(angle) * shorten)
        }

        ctx.beginPath()
        ctx.move(to: shaftStart)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        if obj.type == .arrow || obj.type == .doubleArrow {
            drawArrowHead(from: p0, to: p1, size: headSize, in: ctx)
        }
        if obj.type == .doubleArrow {
            drawArrowHead(from: p1, to: p0, size: headSize, in: ctx)
        }
    }

    private func drawArrowHead(from: CGPoint, to: CGPoint, size: CGFloat, in ctx: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let wing: CGFloat = .pi / 6.5
        let p1 = CGPoint(x: to.x - size * cos(angle - wing), y: to.y - size * sin(angle - wing))
        let p2 = CGPoint(x: to.x - size * cos(angle + wing), y: to.y - size * sin(angle + wing))
        ctx.beginPath()
        ctx.move(to: to)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawPolyline(_ obj: CanvasObject, canvasHeight: CGFloat, in ctx: CGContext) {
        guard let points = obj.points, points.count > 1 else { return }
        ctx.setStrokeColor(obj.style.strokeColor.withAlphaComponent(obj.type == .marker ? 0.4 : 1).cgColor)
        ctx.setLineWidth(obj.type == .marker ? obj.style.strokeWidth * 3 : obj.style.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let mapped = points.map { CGPoint(x: $0.x, y: canvasHeight - $0.y) }
        ctx.move(to: mapped[0])
        for p in mapped.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    private func drawText(_ obj: CanvasObject, cgFrame: CGRect, in ctx: CGContext) {
        if obj.style.fillColor.alphaComponent > 0.01 {
            ctx.setFillColor(obj.style.fillColor.cgColor)
            ctx.fill(cgFrame)
        }
        if obj.style.strokeWidth > 0, obj.style.strokeColor.alphaComponent > 0.01 {
            ctx.setStrokeColor(obj.style.strokeColor.cgColor)
            ctx.setLineWidth(obj.style.strokeWidth)
            ctx.stroke(cgFrame)
        }

        let text = obj.text ?? ""
        guard !text.isEmpty else { return }
        let font = NSFont(name: obj.style.fontName, size: obj.style.fontSize) ?? .systemFont(ofSize: obj.style.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: obj.style.textColor,
            .paragraphStyle: paragraph
        ]
        // Flip locally so AppKit text (top-left layout) matches CG bottom-left cgFrame.
        ctx.saveGState()
        ctx.translateBy(x: cgFrame.minX, y: cgFrame.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let local = CGRect(origin: .zero, size: cgFrame.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (text as NSString).draw(in: local, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    private func drawStep(_ obj: CanvasObject, cgFrame: CGRect, in ctx: CGContext) {
        // Always draw a circle from the shorter side so stretched frames don't become squares.
        let side = min(cgFrame.width, cgFrame.height)
        let circle = CGRect(
            x: cgFrame.midX - side / 2,
            y: cgFrame.midY - side / 2,
            width: side,
            height: side
        )
        let fill = obj.style.fillColor.alphaComponent > 0.05 ? obj.style.fillColor : NSColor.systemRed
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(2, min(3, side * 0.08)))
        ctx.strokeEllipse(in: circle)
        let label = obj.text ?? "\(obj.numberValue ?? 1)"
        let font = NSFont.boldSystemFont(ofSize: max(11, side * 0.45))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: obj.style.textColor.alphaComponent > 0.05 ? obj.style.textColor : NSColor.white,
        ]
        let ns = label as NSString
        let size = ns.size(withAttributes: attrs)
        ctx.saveGState()
        ctx.translateBy(x: circle.midX - size.width / 2, y: circle.midY + size.height / 2)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ns.draw(at: .zero, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    private func drawSymbol(_ obj: CanvasObject, cgFrame: CGRect, in ctx: CGContext) {
        let symbol: String
        switch obj.type {
        case .warning: symbol = "!"
        case .checkmark: symbol = "✓"
        case .crossmark: symbol = "✕"
        default: symbol = "?"
        }
        var copy = obj
        copy.text = symbol
        drawStep(copy, cgFrame: cgFrame, in: ctx)
    }

    private func applyFilter(_ obj: CanvasObject, to image: CGImage, canvasSize: CGSize, quality: RenderQuality) -> CGImage? {
        let rect = obj.frame.integral
        switch obj.type {
        case .solidRedact:
            return solidRedact(image, rect: rect, color: obj.style.fillColor)
        case .pixelate:
            return pixelate(image, rect: rect, block: max(2, Int(obj.filterAmount)), preview: quality == .preview)
        case .blur:
            return blur(image, rect: rect, radius: obj.filterAmount, preview: quality == .preview)
        case .highlight:
            return highlight(image, rect: rect, color: obj.style.fillColor)
        case .focusArea:
            return focusArea(image, rect: rect, amount: obj.filterAmount)
        case .magnify:
            return magnify(image, rect: rect, factor: max(1.5, obj.filterAmount / 5))
        default:
            return image
        }
    }

    private func solidRedact(_ image: CGImage, rect: CGRect, color: NSColor) -> CGImage? {
        let w = image.width, h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // document top-left -> CG bottom-left
        let cgRect = CGRect(x: rect.origin.x, y: CGFloat(h) - rect.origin.y - rect.height, width: rect.width, height: rect.height)
        ctx.setFillColor(color.cgColor)
        ctx.fill(cgRect)
        // Irreversible: no original pixels retained under redact
        return ctx.makeImage()
    }

    private func pixelate(_ image: CGImage, rect: CGRect, block: Int, preview: Bool) -> CGImage? {
        let b = preview ? max(block, 8) : block
        guard let cropped = image.cropping(to: CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height).integral) else { return image }
        // Note: CGImage cropping uses top-left origin
        let cw = cropped.width, ch = cropped.height
        let sw = max(1, cw / b), sh = max(1, ch / b)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        small.interpolationQuality = .none
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let smallImg = small.makeImage() else { return image }
        guard let big = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        big.interpolationQuality = .none
        big.draw(smallImg, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        guard let pix = big.makeImage() else { return image }
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(pix, in: CGRect(x: rect.origin.x, y: CGFloat(image.height) - rect.origin.y - rect.height, width: rect.width, height: rect.height))
        return ctx.makeImage()
    }

    private func blur(_ image: CGImage, rect: CGRect, radius: CGFloat, preview: Bool) -> CGImage? {
        let r = preview ? min(radius, 8) : radius
        let ciImage = CIImage(cgImage: image)
        // CIImage coords bottom-left
        let cgRect = CGRect(x: rect.origin.x, y: CGFloat(image.height) - rect.origin.y - rect.height, width: rect.width, height: rect.height)
        let cropped = ciImage.cropped(to: cgRect)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(cropped, forKey: kCIInputImageKey)
        filter.setValue(r, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: cgRect) else { return image }
        guard let blurred = ciContext.createCGImage(output, from: cgRect) else { return image }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(blurred, in: cgRect)
        return ctx.makeImage()
    }

    private func highlight(_ image: CGImage, rect: CGRect, color: NSColor) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let cgRect = CGRect(x: rect.origin.x, y: CGFloat(image.height) - rect.origin.y - rect.height, width: rect.width, height: rect.height)
        ctx.setFillColor(color.cgColor)
        ctx.setBlendMode(.multiply)
        ctx.fill(cgRect)
        return ctx.makeImage()
    }

    private func focusArea(_ image: CGImage, rect: CGRect, amount: CGFloat) -> CGImage? {
        // Dim outside selection
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let cgRect = CGRect(x: rect.origin.x, y: CGFloat(image.height) - rect.origin.y - rect.height, width: rect.width, height: rect.height)
        ctx.setFillColor(NSColor.black.withAlphaComponent(min(0.75, amount / 20)).cgColor)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        path.addRect(cgRect)
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
        return ctx.makeImage()
    }

    private func magnify(_ image: CGImage, rect: CGRect, factor: CGFloat) -> CGImage? {
        guard let cropped = image.cropping(to: rect.integral) else { return image }
        let cw = Int(CGFloat(cropped.width) * factor)
        let ch = Int(CGFloat(cropped.height) * factor)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let scaledCtx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        scaledCtx.interpolationQuality = .high
        scaledCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        guard let scaled = scaledCtx.makeImage() else { return image }
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let dest = CGRect(
            x: rect.midX - CGFloat(cw)/2,
            y: CGFloat(image.height) - rect.midY - CGFloat(ch)/2,
            width: CGFloat(cw),
            height: CGFloat(ch)
        )
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8)
        ctx.draw(scaled, in: dest)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(dest)
        return ctx.makeImage()
    }
}

enum RenderQuality {
    case preview, full
}
