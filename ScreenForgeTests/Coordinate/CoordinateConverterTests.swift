import XCTest
@testable import ScreenForge

final class CoordinateConverterTests: XCTestCase {
    let converter = CoordinateConverter()

    func testPointToPixelAndBack() {
        let scale: CGFloat = 2
        let p = CGPoint(x: 100, y: 50)
        let pix = converter.pointToPixel(p, scale: scale)
        XCTAssertEqual(pix.x, 200)
        XCTAssertEqual(pix.y, 100)
        let back = converter.pixelToPoint(pix, scale: scale)
        XCTAssertEqual(back.x, 100)
        XCTAssertEqual(back.y, 50)
    }

    func testRectScale() {
        let r = CGRect(x: 10, y: 20, width: 30, height: 40)
        let pix = converter.rectPointsToPixels(r, scale: 2)
        XCTAssertEqual(pix, CGRect(x: 20, y: 40, width: 60, height: 80))
        let back = converter.rectPixelsToPoints(pix, scale: 2)
        XCTAssertEqual(back, r)
    }

    func testAppKitToImagePixelsFlip() {
        let geo = DisplayGeometry(
            displayID: 1,
            framePoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            framePixels: CGRect(x: 0, y: 0, width: 200, height: 200),
            scale: 2
        )
        // Top-left 10x10 point rect in AppKit: y near top means high y in AppKit
        let appKitRect = CGRect(x: 0, y: 90, width: 10, height: 10) // near top
        let pixels = converter.appKitGlobalRectToImagePixels(appKitRect, geometry: geo)
        XCTAssertEqual(pixels.origin.x, 0)
        XCTAssertEqual(pixels.origin.y, 0, accuracy: 0.1)
        XCTAssertEqual(pixels.width, 20, accuracy: 0.1)
        XCTAssertEqual(pixels.height, 20, accuracy: 0.1)
    }

    func testNegativeDisplayOrigin() {
        let geo = DisplayGeometry(
            displayID: 2,
            framePoints: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            framePixels: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            scale: 1
        )
        let rect = CGRect(x: -100, y: 100, width: 50, height: 50)
        let local = converter.appKitGlobalRectToImagePixels(rect, geometry: geo)
        XCTAssertEqual(local.origin.x, 1820, accuracy: 0.1)
    }

    func testClamp() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r = CGRect(x: 80, y: 80, width: 50, height: 50)
        let c = converter.clampRectToDisplay(r, displayFrame: display)
        XCTAssertEqual(c, CGRect(x: 80, y: 80, width: 20, height: 20))
    }
}
