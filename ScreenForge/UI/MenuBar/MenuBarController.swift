import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Window/actions helper. Status item is owned by `AppDelegate` (PasteRush-style).
@MainActor
final class MenuBarController: NSObject {
    private var services: AppServices { AppServices.shared }
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    override init() {
        super.init()
    }

    func install() {
        // Status item is owned by AppDelegate (created at launch, PasteRush-style).
    }

    func applyMenuBarIconVisibility() {
        AppDelegate.shared?.applyMenuBarIconPreference()
    }

    func rebuildMenu() {
        AppDelegate.shared?.applyMenuBarIconPreference()
    }

    @objc func captureRegion() { Task { await services.captureRegion(destination: .editor) } }
    @objc func captureWindow() { Task { await services.captureWindow(destination: .editor) } }
    @objc func captureDisplay() { Task { await services.captureActiveDisplay(destination: .editor) } }
    @objc func captureAll() { Task { await services.captureAllDisplays(destination: .editor) } }
    @objc func captureLast() { Task { await services.captureLastRegion(destination: .editor) } }
    @objc func captureDelayed() {
        services.delayedCapture.start(seconds: services.settings.defaultDelaySeconds) { [weak self] in
            Task { await self?.services.captureRegion(destination: .editor) }
        }
    }
    @objc func captureScrolling() {
        Task { _ = await services.scrolling.captureScrollingRegion() }
    }
    @objc func showHistory() {
        if historyWindow == nil {
            let view = HistoryView()
                .environmentObject(services.history)
                .environmentObject(services.settings)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Capture history")
            window.setContentSize(NSSize(width: 720, height: 480))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.center()
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url {
            services.editorWindows.openImage(url: url)
        }
    }
    @objc func openClipboard() { services.editorWindows.openClipboard() }
    @objc func openLast() {
        if let e = services.history.latest() {
            services.editorWindows.openHistoryEntry(e, history: services.history)
        }
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsRootView().environmentObject(services.settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Settings")
            window.setContentSize(NSSize(width: 780, height: 520))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func toggleLogin() {
        let next = !services.settings.launchAtLogin
        services.settings.launchAtLogin = next
        _ = services.launchAtLogin.applyPreference(next)
        if services.launchAtLogin.requiresApproval && next {
            services.launchAtLogin.openLoginItemsSettings()
        }
    }
    @objc func checkPermissions() {
        services.permissions.openPermissionsPanel()
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ScreenForge"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        alert.informativeText = String(localized: "Version \(version). Local screenshots for macOS. No telemetry, no cloud.")
        alert.addButton(withTitle: String(localized: "Buy Me a Coffee"))
        alert.addButton(withTitle: String(localized: "Close"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(SupportLinks.buyMeACoffee)
        }
    }
    @objc func checkForUpdates() { UpdateController.shared.checkForUpdates() }
    @objc func openSupport() { NSWorkspace.shared.open(SupportLinks.buyMeACoffee) }
    @objc func quit() { NSApp.terminate(nil) }
}
