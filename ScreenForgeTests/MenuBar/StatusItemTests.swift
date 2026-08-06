import XCTest
import AppKit
@testable import ScreenForge

/// Locks in the PasteRush-shaped status item that made the icon appear again in 1.0.23.
@MainActor
final class StatusItemTests: XCTestCase {
    private func delegate() throws -> AppDelegate {
        try XCTUnwrap(AppDelegate.shared, "AppDelegate must be live — tests run inside ScreenForge.app")
    }

    func testStatusItemExistsWithTemplateImageAndMenu() throws {
        let item = try XCTUnwrap(delegate().statusItem)
        XCTAssertEqual(item.length, NSStatusItem.variableLength)

        let button = try XCTUnwrap(item.button)
        let image = try XCTUnwrap(button.image)
        XCTAssertTrue(image.isTemplate)

        let menu = try XCTUnwrap(item.menu)
        XCTAssertGreaterThanOrEqual(menu.items.count, 15)
        XCTAssertTrue(menu.items.contains { $0.action == #selector(MenuBarController.quit) })
    }

    /// A custom autosaveName let Tahoe persist a hidden state under
    /// `NSStatusItem Visible ScreenForgeMain`, which is what kept the icon invisible before 1.0.18.
    func testStatusItemDoesNotUseTheRetiredAutosaveName() throws {
        let item = try XCTUnwrap(delegate().statusItem)
        XCTAssertNotEqual(item.autosaveName as String?, "ScreenForgeMain")
    }

    func testReRegisterKeepsExactlyOneConfiguredItem() throws {
        let appDelegate = try delegate()
        let before = try XCTUnwrap(appDelegate.statusItem)

        appDelegate.reRegisterStatusItemForMenuBarAllowList()

        let after = try XCTUnwrap(appDelegate.statusItem)
        XCTAssertFalse(after === before, "re-register must build a fresh item")
        XCTAssertEqual(after.length, NSStatusItem.variableLength)
        XCTAssertNotNil(after.button?.image)
        XCTAssertNotNil(after.menu)
    }
}
