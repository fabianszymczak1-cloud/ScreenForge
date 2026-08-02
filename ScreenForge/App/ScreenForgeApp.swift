import SwiftUI
import AppKit

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

    private(set) var lifecycle: AppLifecycleController?
    /// Strong ref — must outlive the status bar.
    private var statusItem: NSStatusItem?
    private var menuBarVisibilityCheckTask: Task<Void, Never>?

    func lifecycleRegisterHotkeysAfterOnboarding() {
        lifecycle?.registerHotkeysAfterOnboarding()
    }

    private var isAutomatedRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--smoke-test") || args.contains("--docs-screenshots")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared

        NSApp.setActivationPolicy(.accessory)

        services.settings.showMenuBarIcon = true
        if services.settings.showDockIcon {
            services.settings.showDockIcon = false
        }

        Self.clearLegacyStatusItemAutosaveDefaults()
        setupStatusItem(forceRecreate: true)
        scheduleMenuBarVisibilityCheck()
        UpdateController.shared.start()

        if services.settings.launchAtLogin {
            _ = services.launchAtLogin.applyPreference(true)
        }

        if isAutomatedRun {
            services.settings.hasCompletedOnboarding = true
        }

        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            Task { @MainActor in
                await SmokeTestRunner.run(services: services)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--docs-screenshots") {
            Task { @MainActor in
                await DocsScreenshotRunner.run(services: services)
            }
        }
    }

    func applyMenuBarIconPreference() {
        if AppServices.shared.settings.showMenuBarIcon {
            if statusItem == nil || !isStatusItemOnScreen() {
                setupStatusItem(forceRecreate: true)
                scheduleMenuBarVisibilityCheck()
            } else {
                statusItem?.isVisible = true
            }
        } else if let item = statusItem {
            menuBarVisibilityCheckTask?.cancel()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Recreate status item + re-run Tahoe off-screen recovery.
    func reRegisterStatusItemForMenuBarAllowList() {
        AppServices.shared.settings.showMenuBarIcon = true
        Self.clearLegacyStatusItemAutosaveDefaults()
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem(forceRecreate: true)
        scheduleMenuBarVisibilityCheck()
        DiagnosticLog.shared.info("menubar.statusItem.reregistered visible=\(statusItem?.isVisible == true)")
    }

    private func setupStatusItem(forceRecreate: Bool = false) {
        if forceRecreate || statusItem != nil {
            if let existing = statusItem {
                NSStatusBar.system.removeStatusItem(existing)
                statusItem = nil
            }
        }
        if statusItem != nil {
            statusItem?.isVisible = true
            return
        }

        seedStatusItemVisibilityDefaults()

        // squareLength: Tahoe often parks variableLength items with a zero-size window.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // No autosaveName — named autosave let Control Center persist VisibleCC=0 forever.
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenForge"
            DiagnosticLog.shared.info(
                "menubar.statusItem.ready image=\(image != nil) visible=\(item.isVisible) screen=\(button.window?.screen != nil) frame=\(String(describing: button.window?.frame))"
            )
        } else {
            DiagnosticLog.shared.error("menubar.statusItem.buttonNil")
        }
        item.menu = buildMenu(services: AppServices.shared)
        statusItem = item
    }

    /// Pre-seed Item-0 visibility so StatusKit does not create a hidden slot.
    private func seedStatusItemVisibilityDefaults() {
        let d = UserDefaults.standard
        d.set(true, forKey: "NSStatusItem Visible Item-0")
        d.set(true, forKey: "NSStatusItem VisibleCC Item-0")
        // Also clear any leftover named autosave poison.
        for key in [
            "NSStatusItem Visible ScreenForgeMain",
            "NSStatusItem VisibleCC ScreenForgeMain"
        ] {
            d.removeObject(forKey: key)
        }
    }

    private static func clearLegacyStatusItemAutosaveDefaults() {
        let d = UserDefaults.standard
        for key in [
            "NSStatusItem Preferred Position ScreenForgeMain",
            "NSStatusItem Visible ScreenForgeMain",
            "NSStatusItem VisibleCC ScreenForgeMain"
        ] {
            if d.object(forKey: key) != nil {
                d.removeObject(forKey: key)
                DiagnosticLog.shared.info("menubar.clearedAutosave key=\(key)")
            }
        }
    }

    private func isStatusItemOnScreen() -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let f = window.frame
        // Tahoe briefly reports y=0 height=0, then parks at y=-22.
        return window.screen != nil && f.origin.y >= 0 && f.height >= 16 && f.width >= 8
    }

    private func scheduleMenuBarVisibilityCheck() {
        guard !isAutomatedRun else { return }
        menuBarVisibilityCheckTask?.cancel()
        menuBarVisibilityCheckTask = Task { @MainActor in
            for attempt in 1...5 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                guard AppServices.shared.settings.showMenuBarIcon else { return }

                let frame = String(describing: statusItem?.button?.window?.frame)
                let onScreen = isStatusItemOnScreen()
                DiagnosticLog.shared.info("menubar.check#\(attempt) onScreen=\(onScreen) frame=\(frame)")
                if onScreen { return }

                DiagnosticLog.shared.warn("menubar.recreate attempt=\(attempt)")
                setupStatusItem(forceRecreate: true)
            }

            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            if isStatusItemOnScreen() {
                DiagnosticLog.shared.info("menubar.recovered")
                return
            }

            // Last resort: briefly surface in Dock so the app is findable, then restore accessory.
            DiagnosticLog.shared.error("menubar.stillHidden — Dock fallback + alert")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            presentMenuBarHiddenAlert()
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem(forceRecreate: true)
        }
    }

    private func presentMenuBarHiddenAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar icon is hidden")
        alert.informativeText = String(localized: "ScreenForge is allowed in Menu Bar settings but macOS parked the icon off-screen. Click OK, then use “Re-register in Menu Bar list” in onboarding, or toggle ScreenForge OFF→ON in System Settings → Menu Bar.")
        alert.addButton(withTitle: String(localized: "Open Menu Bar settings"))
        alert.addButton(withTitle: String(localized: "OK"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AppServices.shared.permissions.openMenuBarSettings()
        }
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

    func applicationDidBecomeActive(_ notification: Notification) {
        guard AppServices.shared.settings.showMenuBarIcon else { return }
        if !isStatusItemOnScreen() {
            setupStatusItem(forceRecreate: true)
            scheduleMenuBarVisibilityCheck()
        }
    }
}

extension Notification.Name {
    static let screenForgeMenuBarPreferenceChanged = Notification.Name("screenForgeMenuBarPreferenceChanged")
}
