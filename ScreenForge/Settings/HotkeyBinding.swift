import Foundation
import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case captureRegionEdit
    case captureWindowEdit
    case captureActiveDisplay
    case captureAllDisplays
    case captureLastRegionEdit
    case captureRegionCopy
    case captureWindowCopy
    case captureActiveDisplayCopy
    case captureLastRegionCopy
    case captureDelayed
    case openHistory
    case openLastInEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureRegionEdit: return String(localized: "Capture region → editor")
        case .captureWindowEdit: return String(localized: "Capture window → editor")
        case .captureActiveDisplay: return String(localized: "Capture active display")
        case .captureAllDisplays: return String(localized: "Capture all displays")
        case .captureLastRegionEdit: return String(localized: "Last region → editor")
        case .captureRegionCopy: return String(localized: "Capture region → clipboard")
        case .captureWindowCopy: return String(localized: "Capture window → clipboard")
        case .captureActiveDisplayCopy: return String(localized: "Display → clipboard")
        case .captureLastRegionCopy: return String(localized: "Last region → clipboard")
        case .captureDelayed: return String(localized: "Delayed capture")
        case .openHistory: return String(localized: "Open history")
        case .openLastInEditor: return String(localized: "Last capture in editor")
        }
    }
}

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // carbon modifiers
    var isEnabled: Bool

    var displayString: String {
        guard isEnabled else { return String(localized: "Off") }
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ code: UInt32) -> String {
        keyNames[code] ?? "Key\(code)"
    }

    /// F-keys are the only keys allowed without ⌃, ⌥ or ⌘ — a bare letter would swallow typing system-wide.
    static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5),
        UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10),
        UInt32(kVK_F11), UInt32(kVK_F12), UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15),
        UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]", UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    static var defaults: [String: HotkeyBinding] {
        let ctrlShift = UInt32(controlKey | shiftKey)
        let ctrlOpt = UInt32(controlKey | optionKey)
        return [
            HotkeyAction.captureRegionEdit.rawValue: HotkeyBinding(keyCode: 18, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureWindowEdit.rawValue: HotkeyBinding(keyCode: 19, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureActiveDisplay.rawValue: HotkeyBinding(keyCode: 20, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureAllDisplays.rawValue: HotkeyBinding(keyCode: 21, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureLastRegionEdit.rawValue: HotkeyBinding(keyCode: 23, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureDelayed.rawValue: HotkeyBinding(keyCode: 22, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.openHistory.rawValue: HotkeyBinding(keyCode: 26, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.openLastInEditor.rawValue: HotkeyBinding(keyCode: 28, modifiers: ctrlShift, isEnabled: true),
            HotkeyAction.captureRegionCopy.rawValue: HotkeyBinding(keyCode: 18, modifiers: ctrlOpt, isEnabled: true),
            HotkeyAction.captureWindowCopy.rawValue: HotkeyBinding(keyCode: 19, modifiers: ctrlOpt, isEnabled: true),
            HotkeyAction.captureActiveDisplayCopy.rawValue: HotkeyBinding(keyCode: 20, modifiers: ctrlOpt, isEnabled: true),
            HotkeyAction.captureLastRegionCopy.rawValue: HotkeyBinding(keyCode: 21, modifiers: ctrlOpt, isEnabled: true),
        ]
    }
}
