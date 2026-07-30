import Foundation
import ServiceManagement
import AppKit

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var requiresApproval: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        refresh()
    }

    func openLoginItemsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?LoginItems"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    /// Apply a user preference without snapping UI back on `.requiresApproval`.
    @discardableResult
    func applyPreference(_ desired: Bool) -> Bool {
        do {
            try setEnabled(desired)
            return isEnabled || (desired && requiresApproval)
        } catch {
            refresh()
            return false
        }
    }
}
