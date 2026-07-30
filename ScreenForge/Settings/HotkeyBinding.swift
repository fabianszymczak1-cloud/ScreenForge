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
        let map: [UInt32: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            12: "Q", 13: "W", 14: "E", 15: "R", 17: "T", 16: "Y",
            105: "F13", // often Print Screen on external keyboards mapped differently
        ]
        return map[code] ?? "Key\(code)"
    }

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
