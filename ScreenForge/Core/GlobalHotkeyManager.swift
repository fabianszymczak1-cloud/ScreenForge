import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotkeyManager {
    private let settings: SettingsStore
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actionByID: [UInt32: HotkeyAction] = [:]
    private var handlerRef: EventHandlerRef?
    var onAction: ((HotkeyAction) -> Void)?
    private static var shared: GlobalHotkeyManager?

    init(settings: SettingsStore) {
        self.settings = settings
        GlobalHotkeyManager.shared = self
    }

    func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()
        var nextID: UInt32 = 1
        for action in HotkeyAction.allCases {
            guard let binding = settings.hotkeyBindings[action.rawValue], binding.isEnabled else { continue }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x53467267), /* 'SFrg' */ id: nextID)
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                hotKeys[nextID] = hotKeyRef
                actionByID[nextID] = action
                nextID += 1
            } else {
                DiagnosticLog.shared.warn("hotkey.register.failed action=\(action.rawValue) status=\(status)")
            }
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
        actionByID.removeAll()
    }

    func conflicts(for binding: HotkeyBinding, excluding: HotkeyAction?) -> [HotkeyAction] {
        settings.hotkeyBindings.compactMap { key, value in
            guard value.isEnabled, value == binding, let action = HotkeyAction(rawValue: key) else { return nil }
            if action == excluding { return nil }
            return action
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                Task { @MainActor in
                    if let action = GlobalHotkeyManager.shared?.actionByID[hotKeyID.id] {
                        GlobalHotkeyManager.shared?.onAction?(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            DiagnosticLog.shared.error("hotkey.handler.failed \(status)")
        }
    }
}
