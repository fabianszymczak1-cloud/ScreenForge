import XCTest
@testable import ScreenForge

final class ShapeRotationTests: XCTestCase {
    func testClockwiseAngleFromTop() {
        let center = CGPoint(x: 100, y: 100)
        XCTAssertEqual(ShapeRotationMath.rotationDegrees(from: center, to: CGPoint(x: 100, y: 40)), 0, accuracy: 0.01)
        XCTAssertEqual(ShapeRotationMath.rotationDegrees(from: center, to: CGPoint(x: 160, y: 100)), 90, accuracy: 0.01)
        XCTAssertEqual(ShapeRotationMath.rotationDegrees(from: center, to: CGPoint(x: 100, y: 160)), 180, accuracy: 0.01)
        XCTAssertEqual(ShapeRotationMath.rotationDegrees(from: center, to: CGPoint(x: 40, y: 100)), -90, accuracy: 0.01)
    }

    func testRotatePointRoundTrip() {
        let center = CGPoint(x: 50, y: 50)
        let point = CGPoint(x: 50, y: 10)
        let rotated = ShapeRotationMath.rotatePoint(point, around: center, degrees: 45)
        let back = ShapeRotationMath.rotatePoint(rotated, around: center, degrees: -45)
        XCTAssertEqual(back.x, point.x, accuracy: 0.01)
        XCTAssertEqual(back.y, point.y, accuracy: 0.01)
    }

    func testSupportsRotationTypes() {
        for type in [CanvasObjectType.rectangle, .roundedRectangle, .ellipse] {
            XCTAssertTrue(ShapeRotationMath.supportsRotation(type))
        }
        XCTAssertFalse(ShapeRotationMath.supportsRotation(.line))
        XCTAssertFalse(ShapeRotationMath.supportsRotation(.textBox))
    }
}
