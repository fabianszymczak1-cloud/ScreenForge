import XCTest
import AppKit
@testable import ScreenForge

/// Window selection keeps its overlays in an array and closes them by hand. With AppKit's default
/// the close would release them a second time, and the app died in `objc_release` on the next
/// autorelease pool drain — crash reports from 1.0.25.
@MainActor
final class OverlayWindowLifetimeTests: XCTestCase {
    func testOverlayIsNotReleasedByClose() {
        let window = RegionOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        XCTAssertFalse(window.isReleasedWhenClosed)
    }

    func testClosingHeldOverlaysLeavesThemUsable() {
        var overlays: [NSWindow] = []
        for _ in 0..<3 {
            overlays.append(RegionOverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            ))
        }
        overlays.forEach { $0.close() }
        // Reading the closed windows would touch freed memory if close had released them.
        XCTAssertTrue(overlays.allSatisfy { !$0.isVisible })
    }
}
