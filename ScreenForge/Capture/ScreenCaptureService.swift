import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import ImageIO

@MainActor
final class ScreenCaptureService {
    let displays: DisplayTopologyService
    let coordinates: CoordinateConverter
    let provider: ScreenCaptureKitProvider

    init(displays: DisplayTopologyService, coordinates: CoordinateConverter, provider: ScreenCaptureKitProvider = ScreenCaptureKitProvider()) {
        self.displays = displays
        self.coordinates = coordinates
        self.provider = provider
    }

    func freezeAllDisplays(excludeWindowIDs: [CGWindowID] = []) async throws -> [CGDirectDisplayID: CGImage] {
        displays.refresh()
        var result: [CGDirectDisplayID: CGImage] = [:]
        for info in displays.displays {
            let image = try await provider.captureDisplay(info.id, excludeWindowIDs: excludeWindowIDs)
            result[info.id] = image
        }
        return result
    }

    func captureActiveDisplay(includeCursor: Bool) async throws -> CaptureResult {
        displays.refresh()
        let preferCursor = AppServices.shared.settings.activeDisplaySource == .cursor
        guard let info = displays.activeDisplay(preferCursor: preferCursor) else {
            throw CaptureError.noDisplay
        }
        var image = try await provider.captureDisplay(info.id, excludeWindowIDs: ownWindowIDs())
        if includeCursor, let withCursor = compositeCursor(on: image, display: info) {
            image = withCursor
        }
        return CaptureResult(image: image, kind: .fullDisplay, displayID: info.id, sourceAppName: frontmostAppName())
    }

    func captureAllDisplays(mode: AllDisplaysMode, includeCursor: Bool) async throws -> CaptureResult {
        displays.refresh()
        let frozen = try await freezeAllDisplays(excludeWindowIDs: ownWindowIDs())
        switch mode {
        case .separateFiles:
            // Return combined for routing; separate files handled in router when needed
            fallthrough
        case .combinedImage:
            guard let combined = combineDisplays(frozen) else {
                throw CaptureError.captureFailed("Failed to stitch displays")
            }
            return CaptureResult(image: combined, kind: .allDisplays, sourceAppName: frontmostAppName(), layoutSignature: displays.layoutSignature)
        }
    }

    func captureRegionPixels(_ pixelRect: CGRect, displayID: CGDirectDisplayID, frozen: CGImage? = nil) async throws -> CaptureResult {
        let source: CGImage
        if let frozen {
            source = frozen
        } else {
            source = try await provider.captureDisplay(displayID, excludeWindowIDs: ownWindowIDs())
        }
        let integral = pixelRect.integral
        guard var cropped = source.cropping(to: integral) else {
            throw CaptureError.captureFailed("Pusty region")
        }
        cropped = ImageAlphaTrimmer.trimTransparentEdges(cropped) ?? cropped
        let geo = displays.display(id: displayID)?.geometry
        let points = geo.map { coordinates.imagePixelsToAppKitGlobal(integral, geometry: $0) }
        return CaptureResult(
            image: cropped,
            kind: .region,
            displayID: displayID,
            regionPoints: points,
            regionPixels: integral,
            sourceAppName: frontmostAppName(),
            layoutSignature: displays.layoutSignature
        )
    }

    func captureFrontmostWindow(includeShadow: Bool, margin: Double, includeCursor: Bool) async throws -> CaptureResult {
        let windows = try await provider.availableWindows()
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        guard let scWindow = windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID && $0.isOnScreen })
                ?? windows.first else {
            throw CaptureError.noWindow
        }
        let appName = scWindow.owningApplication?.applicationName ?? front?.localizedName
        let title = scWindow.title
        nonisolated(unsafe) let windowRef = scWindow
        var image = try await provider.captureWindow(windowRef, includeShadow: includeShadow)
        if margin > 0, let padded = padImage(image, margin: Int(margin)) {
            image = padded
        }
        image = ImageAlphaTrimmer.trimTransparentEdges(image) ?? image
        return CaptureResult(
            image: image,
            kind: .window,
            sourceAppName: appName,
            sourceWindowTitle: title
        )
    }

    func captureSCWindow(_ window: SCWindow, includeShadow: Bool, margin: Double) async throws -> CaptureResult {
        let appName = window.owningApplication?.applicationName
        let title = window.title
        nonisolated(unsafe) let windowRef = window
        var image = try await provider.captureWindow(windowRef, includeShadow: includeShadow)
        if margin > 0, let padded = padImage(image, margin: Int(margin)) {
            image = padded
        }
        image = ImageAlphaTrimmer.trimTransparentEdges(image) ?? image
        return CaptureResult(
            image: image,
            kind: .window,
            sourceAppName: appName,
            sourceWindowTitle: title
        )
    }

    func ownWindowIDs() -> [CGWindowID] {
        // Optional: keep ScreenForge (editor, settings) out of the shot so other apps look clean.
        guard AppServices.shared.settings.hideSelfDuringCapture else { return [] }
        return NSApp.windows.compactMap { win -> CGWindowID? in
            let number = win.windowNumber
            guard number > 0, number <= Int(UInt32.max) else { return nil }
            return CGWindowID(UInt32(number))
        }
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func combineDisplays(_ images: [CGDirectDisplayID: CGImage]) -> CGImage? {
        let geos = displays.displays.map(\.geometry)
        guard !geos.isEmpty else { return nil }
        var union = geos[0].framePixels
        for g in geos.dropFirst() { union = union.union(g.framePixels) }
        let width = Int(union.width.rounded(.up))
        let height = Int(union.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // CGContext has bottom-left origin matching framePixels
        for info in displays.displays {
            guard let img = images[info.id] else { continue }
            let dest = CGRect(
                x: info.geometry.framePixels.origin.x - union.origin.x,
                y: info.geometry.framePixels.origin.y - union.origin.y,
                width: info.geometry.framePixels.width,
                height: info.geometry.framePixels.height
            )
            ctx.draw(img, in: dest)
        }
        return ctx.makeImage()
    }

    private func padImage(_ image: CGImage, margin: Int) -> CGImage? {
        let w = image.width + margin * 2
        let h = image.height + margin * 2
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: margin, y: margin, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    private func compositeCursor(on image: CGImage, display: DisplayInfo) -> CGImage? {
        // Best-effort: draw current system cursor at mouse location
        let mouse = NSEvent.mouseLocation
        guard display.geometry.framePoints.contains(mouse) else { return image }
        let local = coordinates.appKitGlobalRectToImagePixels(
            CGRect(origin: mouse, size: CGSize(width: 1, height: 1)),
            geometry: display.geometry
        )
        guard let cursorImage = NSCursor.current.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // image coords top-left; CGContext bottom-left — flip
        let hot = NSCursor.current.hotSpot
        let scale = display.geometry.scale
        let cw = CGFloat(cursorImage.width)
        let ch = CGFloat(cursorImage.height)
        let x = local.origin.x - hot.x * scale
        let y = CGFloat(image.height) - local.origin.y - ch + hot.y * scale
        ctx.draw(cursorImage, in: CGRect(x: x, y: y, width: cw, height: ch))
        return ctx.makeImage()
    }
}
