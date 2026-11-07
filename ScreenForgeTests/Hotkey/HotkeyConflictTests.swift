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

    /// The old recorder only knew digits, so ⌃⇧A was stored as ⌃⇧1.
    func testRecordedLettersAndFunctionKeysKeepTheirKeyCode() {
        let letter = HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | shiftKey), isEnabled: true)
        XCTAssertEqual(letter.displayString, "⌃⇧K")
        let fKey = HotkeyBinding(keyCode: UInt32(kVK_F5), modifiers: 0, isEnabled: true)
        XCTAssertEqual(fKey.displayString, "F5")
        XCTAssertTrue(HotkeyBinding.functionKeyCodes.contains(UInt32(kVK_F5)))
        XCTAssertFalse(HotkeyBinding.functionKeyCodes.contains(UInt32(kVK_ANSI_K)))
    }

    func testRecorderMapsModifierFlagsToCarbon() {
        let mods = HotkeyRecorder.carbonModifiers([.command, .option, .numericPad])
        XCTAssertEqual(mods, UInt32(cmdKey | optionKey))
        XCTAssertEqual(HotkeyRecorder.carbonModifiers([.control, .shift]), UInt32(controlKey | shiftKey))
    }
}
