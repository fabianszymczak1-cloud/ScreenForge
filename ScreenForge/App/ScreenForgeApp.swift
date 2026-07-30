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
    private let statusAutosaveName = "ScreenForgeMainStatusItem"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared

        NSApp.setActivationPolicy(.accessory)

        if services.settings.showDockIcon {
            services.settings.showDockIcon = false
        }
        if !services.settings.showMenuBarIcon {
            services.settings.showMenuBarIcon = true
        }

        seedStatusItemVisibilityDefaults()
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

    /// Pre-seed Control Center visibility so Tahoe does not create an ephemeral/hidden item.
    private func seedStatusItemVisibilityDefaults() {
        let d = UserDefaults.standard
        d.set(true, forKey: "NSStatusItem Visible \(statusAutosaveName)")
        d.set(true, forKey: "NSStatusItem VisibleCC \(statusAutosaveName)")
        d.set(true, forKey: "NSStatusItem Visible Item-0")
        d.set(true, forKey: "NSStatusItem VisibleCC Item-0")
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

    private func setupStatusItem() {
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }

        seedStatusItemVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = statusAutosaveName
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenForge"
            DiagnosticLog.shared.info(
                "statusItem.ready image=\(image != nil) visible=\(item.isVisible) screen=\(button.window?.screen != nil) frame=\(String(describing: button.window?.frame))"
            )
        } else {
            DiagnosticLog.shared.error("statusItem.button is nil")
        }
        item.menu = buildMenu(services: AppServices.shared)
        statusItem = item
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

    private func isStatusItemOnScreen() -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let f = window.frame
        // Tahoe briefly reports y=0 with height 0, then parks at y=-22.
        return window.screen != nil && f.origin.y >= 0 && f.height >= 16 && f.width >= 8
    }

    private func scheduleMenuBarVisibilityCheck() {
        guard !isAutomatedRun else { return }
        menuBarVisibilityCheckTask?.cancel()
        menuBarVisibilityCheckTask = Task { @MainActor in
            for attempt in 1...4 {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                guard AppServices.shared.settings.showMenuBarIcon else { return }

                let onScreen = isStatusItemOnScreen()
                DiagnosticLog.shared.info(
                    "menubar.check#\(attempt) onScreen=\(onScreen) frame=\(String(describing: statusItem?.button?.window?.frame))"
                )
                if onScreen { return }

                DiagnosticLog.shared.warn("menubar.recreate attempt \(attempt)")
                setupStatusItem()
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            if isStatusItemOnScreen() {
                DiagnosticLog.shared.info("menubar.recovered")
                return
            }

            DiagnosticLog.shared.error("menubar.stillHidden — enabling Dock fallback")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            presentMenuBarAllowAlert()
        }
    }

    private func presentMenuBarAllowAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar icon is hidden")
        alert.informativeText = String(localized: "macOS may be blocking ScreenForge in System Settings → Menu Bar. Set ScreenForge to Allow, then relaunch the app.")
        alert.addButton(withTitle: String(localized: "Open Menu Bar settings"))
        alert.addButton(withTitle: String(localized: "Later"))
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
