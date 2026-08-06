import Foundation
import CoreGraphics

/// Pure geometry helpers for rotating frame-based canvas objects (rectangle / ellipse).
/// Angles are clockwise degrees in flipped (top-left) document space — same convention as rendering.
enum ShapeRotationMath {
    static func supportsRotation(_ type: CanvasObjectType) -> Bool {
        [.rectangle, .roundedRectangle, .ellipse].contains(type)
    }

    static func rotatePoint(_ point: CGPoint, around center: CGPoint, degrees: CGFloat) -> CGPoint {
        guard degrees != 0 else { return point }
        let rad = degrees * .pi / 180
        let cosA = cos(rad), sinA = sin(rad)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cosA - dy * sinA,
            y: center.y + dx * sinA + dy * cosA
        )
    }

    /// 0° = straight up (smaller y); positive = clockwise.
    static func rotationDegrees(from center: CGPoint, to point: CGPoint) -> CGFloat {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return atan2(dx, -dy) * 180 / .pi
    }
}
