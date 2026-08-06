import Foundation
import AppKit
import CoreGraphics

/// Converts between AppKit points, Core Graphics pixels, and ScreenCaptureKit coordinates.
struct DisplayGeometry: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let framePoints: CGRect      // AppKit global points (bottom-left origin)
    let framePixels: CGRect      // CG global pixels (bottom-left origin)
    let scale: CGFloat

    var boundsPixels: CGSize {
        framePixels.size
    }
}

struct CoordinateConverter: Sendable {
    func geometry(for screen: NSScreen) -> DisplayGeometry {
        let id = screen.displayID
        let scale = screen.backingScaleFactor
        let framePoints = screen.frame
        let framePixels = CGRect(
            x: framePoints.origin.x * scale,
            y: framePoints.origin.y * scale,
            width: framePoints.width * scale,
            height: framePoints.height * scale
        )
        // CGDisplayBounds looks like the authoritative source but reports points in a top-left
        // space, so using it here silently halved every pixel rect on a Retina display.
        return DisplayGeometry(
            displayID: id,
            framePoints: framePoints,
            framePixels: framePixels,
            scale: scale
        )
    }

    func pointToPixel(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    func pixelToPoint(_ pixel: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale != 0 else { return pixel }
        return CGPoint(x: pixel.x / scale, y: pixel.y / scale)
    }

    func rectPointsToPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    func rectPixelsToPoints(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale != 0 else { return rect }
        return CGRect(
            x: rect.origin.x / scale,
            y: rect.origin.y / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    /// Convert AppKit global rect (bottom-left origin) to display-local pixels (top-left image coords).
    func appKitGlobalRectToImagePixels(_ rect: CGRect, geometry: DisplayGeometry) -> CGRect {
        let localPoints = CGRect(
            x: rect.origin.x - geometry.framePoints.origin.x,
            y: rect.origin.y - geometry.framePoints.origin.y,
            width: rect.width,
            height: rect.height
        )
        // Flip Y: AppKit bottom-left local -> image top-left
        let flippedY = geometry.framePoints.height - localPoints.origin.y - localPoints.height
        return CGRect(
            x: (localPoints.origin.x * geometry.scale).rounded(.towardZero),
            y: (flippedY * geometry.scale).rounded(.towardZero),
            width: (localPoints.width * geometry.scale).rounded(.towardZero),
            height: (localPoints.height * geometry.scale).rounded(.towardZero)
        )
    }

    /// Convert display-local image pixels (top-left) to AppKit global points.
    func imagePixelsToAppKitGlobal(_ rect: CGRect, geometry: DisplayGeometry) -> CGRect {
        let points = rectPixelsToPoints(rect, scale: geometry.scale)
        let flippedY = geometry.framePoints.height - points.origin.y - points.height
        return CGRect(
            x: points.origin.x + geometry.framePoints.origin.x,
            y: flippedY + geometry.framePoints.origin.y,
            width: points.width,
            height: points.height
        )
    }

    func clampRectToDisplay(_ rect: CGRect, displayFrame: CGRect) -> CGRect {
        let intersection = rect.intersection(displayFrame)
        return intersection.isNull ? .null : intersection
    }

    func unionPixelSize(of geometries: [DisplayGeometry]) -> CGSize {
        guard !geometries.isEmpty else { return .zero }
        var union = geometries[0].framePixels
        for g in geometries.dropFirst() {
            union = union.union(g.framePixels)
        }
        return union.size
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        if let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(num.uint32Value)
        }
        return CGMainDisplayID()
    }
}
