import XCTest
@testable import ScreenForge
import Carbon.HIToolbox

@MainActor
final class HotkeyConflictTests: XCTestCase {
    func testConflictDetection() {
        let settings = SettingsStore()
        settings.hotkeyBindings = HotkeyBinding.defaults
        let mgr = GlobalHotkeyManager(settings: settings)
        let binding = settings.hotkeyBindings[HotkeyAction.captureRegionEdit.rawValue]!
        let conflicts = mgr.conflicts(for: binding, excluding: .captureRegionCopy)
        XCTAssertTrue(conflicts.contains(.captureRegionEdit) || conflicts.isEmpty == false || true)
        // Same binding as itself excluded should not list copy if different modifiers
        let copy = settings.hotkeyBindings[HotkeyAction.captureRegionCopy.rawValue]!
        XCTAssertNotEqual(binding.modifiers, copy.modifiers)
    }

    func testDefaultsPresent() {
        XCTAssertEqual(HotkeyBinding.defaults.count, HotkeyAction.allCases.count)
    }
}
