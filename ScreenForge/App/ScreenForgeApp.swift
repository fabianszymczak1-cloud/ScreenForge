import SwiftUI
import AppKit
import CoreGraphics

@main
struct ScreenForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environmentObject(AppServices.shared.settings)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var lifecycle: AppLifecycleController?
    /// Strong ref — PasteRush pattern; must outlive the status bar.
    private var statusItem: NSStatusItem?
    private var menuBarVisibilityCheckTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared

        // Exact PasteRush order: accessory → status item → Sparkle → rest.
        NSApp.setActivationPolicy(.accessory)

        if services.settings.showDockIcon {
            services.settings.showDockIcon = false
        }
        if !services.settings.showMenuBarIcon {
            services.settings.showMenuBarIcon = true
        }

        setupStatusItem()
        UpdateController.shared.start()

        if services.settings.launchAtLogin {
            _ = services.launchAtLogin.applyPreference(true)
        }

        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

        scheduleMenuBarVisibilityCheck()

        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            services.settings.hasCompletedOnboarding = true
            Task { @MainActor in
                await SmokeTestRunner.run(services: services)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--docs-screenshots") {
            services.settings.hasCompletedOnboarding = true
            Task { @MainActor in
                await DocsScreenshotRunner.run(services: services)
            }
        }
    }

    private var isAutomatedRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--smoke-test") || args.contains("--docs-screenshots")
    }

    func applyMenuBarIconPreference() {
        if AppServices.shared.settings.showMenuBarIcon {
            if statusItem == nil {
                setupStatusItem()
            } else {
                statusItem?.isVisible = true
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Mirror PasteRushApp.setupStatusItem() closely; new autosaveName escapes Tahoe ghosts.
    private func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // Fresh identity so Control Center does not reuse a blocked Item-0 mapping.
            statusItem?.autosaveName = "ScreenForgeMainStatusItem"
        }
        statusItem?.isVisible = true
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenForge"
            DiagnosticLog.shared.info(
                "statusItem.ready image=\(image != nil) visible=\(statusItem?.isVisible == true) screen=\(String(describing: button.window?.screen != nil))"
            )
        } else {
            DiagnosticLog.shared.error("statusItem.button is nil")
        }
        statusItem?.menu = buildMenu(services: AppServices.shared)
    }

    private func buildMenu(services: AppServices) -> NSMenu {
        let menu = NSMenu()
        let mb = services.menuBar
        func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.target = mb
            return i
        }
        menu.addItem(item(String(localized: "Capture region"), #selector(MenuBarController.captureRegion)))
        menu.addItem(item(String(localized: "Capture window"), #selector(MenuBarController.captureWindow)))
        menu.addItem(item(String(localized: "Capture active display"), #selector(MenuBarController.captureDisplay)))
        menu.addItem(item(String(localized: "Capture all displays"), #selector(MenuBarController.captureAll)))
        menu.addItem(item(String(localized: "Capture last region"), #selector(MenuBarController.captureLast)))
        menu.addItem(item(String(localized: "Capture with delay"), #selector(MenuBarController.captureDelayed)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open history"), #selector(MenuBarController.showHistory)))
        let openFile = item(String(localized: "Open image from file…"), #selector(MenuBarController.openFile), key: "o")
        openFile.keyEquivalentModifierMask = [.command]
        menu.addItem(openFile)
        menu.addItem(item(String(localized: "Open image from clipboard"), #selector(MenuBarController.openClipboard)))
        menu.addItem(item(String(localized: "Last capture"), #selector(MenuBarController.openLast)))
        menu.addItem(.separator())
        let settings = item(String(localized: "Settings…"), #selector(MenuBarController.showSettings), key: ",")
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)
        menu.addItem(item(String(localized: "Launch at login"), #selector(MenuBarController.toggleLogin)))
        menu.addItem(item(String(localized: "Check permissions"), #selector(MenuBarController.checkPermissions)))
        menu.addItem(item(String(localized: "About"), #selector(MenuBarController.showAbout)))
        menu.addItem(item(String(localized: "Check for Updates…"), #selector(MenuBarController.checkForUpdates)))
        menu.addItem(item(String(localized: "Buy Me a Coffee"), #selector(MenuBarController.openSupport)))
        menu.addItem(.separator())
        let quit = item(String(localized: "Quit"), #selector(MenuBarController.quit), key: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return menu
    }

    private func scheduleMenuBarVisibilityCheck() {
        guard !isAutomatedRun else { return }
        menuBarVisibilityCheckTask?.cancel()
        menuBarVisibilityCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard AppServices.shared.settings.showMenuBarIcon else { return }

            let button = statusItem?.button
            let onScreen = button?.window?.screen != nil
                && (button?.window?.frame.origin.y ?? -1) >= 0
            DiagnosticLog.shared.info(
                "menubar.check visible=\(statusItem?.isVisible == true) onScreen=\(onScreen) frame=\(String(describing: button?.window?.frame))"
            )
            if onScreen { return }
            presentMenuBarAllowAlertIfNeeded()
        }
    }

    private func presentMenuBarAllowAlertIfNeeded() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar icon is hidden")
        alert.informativeText = String(localized: "macOS may be blocking ScreenForge in System Settings → Menu Bar. Set ScreenForge to Allow, then relaunch the app.")
        alert.addButton(withTitle: String(localized: "Open Menu Bar settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openMenuBarSettings()
        }
    }

    func openMenuBarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock?menuBar"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarVisibilityCheckTask?.cancel()
        lifecycle?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let screenForgeMenuBarPreferenceChanged = Notification.Name("screenForgeMenuBarPreferenceChanged")
}
