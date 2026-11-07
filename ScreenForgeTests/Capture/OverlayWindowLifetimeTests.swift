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
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.isRestorable)
    }

    /// Activating the app from a fullscreen space after each capture is what left Mission Control and
    /// Dock clicks bouncing back to the fullscreen app. The editor must take keys without activating.
    func testEditorTakesKeysWithoutActivatingTheApp() {
        let panel = EditorPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(panel.isRestorable)
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
