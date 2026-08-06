import Foundation
import AppKit
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(title: String, body: String?, image: NSImage? = nil, fileURL: URL? = nil) {
        guard settings.showNotifications else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        // The dismissal closure keeps the panel alive, so close must not release it as well.
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.frame = NSRect(x: 16, y: 30, width: 250, height: 18)
        container.addSubview(titleField)
        if let body {
            let bodyField = NSTextField(labelWithString: body)
            bodyField.font = .systemFont(ofSize: 11)
            bodyField.textColor = .secondaryLabelColor
            bodyField.frame = NSRect(x: 16, y: 12, width: 250, height: 16)
            container.addSubview(bodyField)
        }
        panel.contentView = container
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.maxY - 90))
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            panel.close()
        }
        _ = fileURL
        _ = image
    }

    func showError(_ message: String) {
        show(title: String(localized: "Error"), body: message)
    }
}
