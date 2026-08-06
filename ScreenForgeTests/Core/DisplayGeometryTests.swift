import XCTest
import AppKit
@testable import ScreenForge

/// `framePixels` used to come from `CGDisplayBounds`, which reports points. On a Retina display
/// every pixel rect was half size: the all-displays stitch rendered at 1x and "capture last region"
/// dropped any region in the right or bottom half of the screen.
final class DisplayGeometryTests: XCTestCase {
    func testFramePixelsIsPointsTimesBackingScale() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let geometry = CoordinateConverter().geometry(for: screen)

        XCTAssertEqual(geometry.scale, screen.backingScaleFactor)
        XCTAssertEqual(geometry.framePixels.width, screen.frame.width * screen.backingScaleFactor, accuracy: 0.5)
        XCTAssertEqual(geometry.framePixels.height, screen.frame.height * screen.backingScaleFactor, accuracy: 0.5)
    }

    func testFramePixelsMatchesTheCapturedImageSize() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let geometry = CoordinateConverter().geometry(for: screen)

        // The capture path sizes its stream with exactly these numbers, so a mismatch here means
        // the stitched image and the frame disagree about how big the display is.
        XCTAssertEqual(
            Int(geometry.framePixels.width.rounded()),
            Int((screen.frame.width * screen.backingScaleFactor).rounded())
        )
    }
}
