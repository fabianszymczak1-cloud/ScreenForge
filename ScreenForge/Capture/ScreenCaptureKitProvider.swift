import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

protocol ScreenCaptureProviding: Sendable {
    func captureDisplay(_ displayID: CGDirectDisplayID, excludeWindowIDs: [CGWindowID]) async throws -> CGImage
    func captureRect(_ rect: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage
    func availableWindows() async throws -> [SCWindow]
    func availableDisplays() async throws -> [SCDisplay]
}

final class ScreenCaptureKitProvider: ScreenCaptureProviding, @unchecked Sendable {
    func contentFilter() async throws -> (SCShareableContent, [SCDisplay], [SCWindow]) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return (content, content.displays, content.windows)
    }

    func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }

    func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.filter { $0.isOnScreen && $0.frame.width > 1 && $0.frame.height > 1 }
    }

    func captureDisplay(_ displayID: CGDirectDisplayID, excludeWindowIDs: [CGWindowID] = []) async throws -> CGImage {
        PerformanceMonitor.shared.begin("capture.display")
        defer { _ = PerformanceMonitor.shared.end("capture.display") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let excluded = content.windows.filter { excludeWindowIDs.contains(CGWindowID($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        // Prefer full Retina pixel size from NSScreen when available
        if let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            config.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
            config.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        } else {
            config.width = display.width
            config.height = display.height
        }
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 14.0, *) {
            // Prefer SCScreenshotManager on modern systems
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image
        } else {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image
        }
    }

    func captureRect(_ rect: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage {
        let full = try await captureDisplay(displayID, excludeWindowIDs: [])
        guard let cropped = full.cropping(to: rect.integral) else {
            throw CaptureError.captureFailed("Failed to crop region")
        }
        return cropped
    }

    func captureWindow(_ window: SCWindow, includeShadow: Bool) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Use SCContentFilter's content rect + scale — matches the real drawable bounds
        // better than window.frame * NSScreen.scale (avoids transparent padding).
        let scale = CGFloat(filter.pointPixelScale > 0 ? filter.pointPixelScale : 2)
        let content = filter.contentRect
        let w = max(1, Int((content.width * scale).rounded()))
        let h = max(1, Int((content.height * scale).rounded()))
        config.width = w
        config.height = h
        config.showsCursor = false
        config.capturesAudio = false
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.ignoreShadowsSingleWindow = !includeShadow
        // Keep window on-screen framing tight when possible
        config.ignoreGlobalClipSingleWindow = false
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        image = ImageAlphaTrimmer.trimTransparentEdges(image) ?? image
        return image
    }
}

/// Trims fully/nearly transparent margins from CGImages (window shadows, scaled padding).
enum ImageAlphaTrimmer {
    /// Returns a tightly cropped opaque image, or `nil` if nothing was trimmed.
    static func trimTransparentEdges(_ image: CGImage, alphaThreshold: UInt8 = 32) -> CGImage? {
        // Normalize to RGBA (alpha last) so we don't mis-read BGRA byte order.
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bpr = width * 4
        var pixels = [UInt8](repeating: 0, count: bpr * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func alpha(x: Int, y: Int) -> UInt8 {
            // CGContext buffer is bottom-left; y=0 is the bottom row. Bounds scan is fine either way.
            pixels[y * bpr + x * 4 + 3]
        }

        func columnOpaque(_ x: Int) -> Bool {
            for y in 0..<height where alpha(x: x, y: y) > alphaThreshold { return true }
            return false
        }
        func rowOpaque(_ y: Int) -> Bool {
            for x in 0..<width where alpha(x: x, y: y) > alphaThreshold { return true }
            return false
        }
        /// Soft window-shadow rows: most pixels below a higher bar even if a few AA pixels pass.
        func rowMostlyClear(_ y: Int, thr: UInt8 = 64, fraction: Double = 0.85) -> Bool {
            var clear = 0
            for x in 0..<width where alpha(x: x, y: y) <= thr { clear += 1 }
            return Double(clear) / Double(width) >= fraction
        }
        func columnMostlyClear(_ x: Int, thr: UInt8 = 64, fraction: Double = 0.85) -> Bool {
            var clear = 0
            for y in 0..<height where alpha(x: x, y: y) <= thr { clear += 1 }
            return Double(clear) / Double(height) >= fraction
        }

        var minX = 0
        while minX < width && !columnOpaque(minX) { minX += 1 }
        var maxX = width - 1
        while maxX >= minX && !columnOpaque(maxX) { maxX -= 1 }
        var minY = 0
        while minY < height && !rowOpaque(minY) { minY += 1 }
        var maxY = height - 1
        while maxY >= minY && !rowOpaque(maxY) { maxY -= 1 }

        while minX < maxX && columnMostlyClear(minX) { minX += 1 }
        while maxX > minX && columnMostlyClear(maxX) { maxX -= 1 }
        while minY < maxY && rowMostlyClear(minY) { minY += 1 }
        while maxY > minY && rowMostlyClear(maxY) { maxY -= 1 }

        guard minX <= maxX, minY <= maxY else { return nil }
        let cropW = maxX - minX + 1
        let cropH = maxY - minY + 1
        // Only skip when there is literally nothing to trim (including 1px margins).
        if cropW == width && cropH == height { return nil }

        guard let normalized = ctx.makeImage() else { return nil }

        // Rebuild via draw instead of CGImage.cropping — more reliable for SC bitmaps.
        // Buffer/context are bottom-left; shift so opaque (minX,minY) lands at (0,0).
        guard let out = CGContext(
            data: nil,
            width: cropW,
            height: cropH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        out.interpolationQuality = .none
        out.draw(
            normalized,
            in: CGRect(x: -minX, y: -minY, width: width, height: height)
        )
        return out.makeImage()
    }
}
