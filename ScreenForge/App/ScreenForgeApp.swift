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
    /// Strong ref — PasteRush pattern; must outlive the status bar.
    private var statusItem: NSStatusItem?

    func lifecycleRegisterHotkeysAfterOnboarding() {
        lifecycle?.registerHotkeysAfterOnboarding()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared

        NSApp.setActivationPolicy(.accessory)

        // Always keep menu-bar icon on for agent apps. Never persist a "removed" state
        // from Control Center — that previously spun MenuBarExtra(isInserted:) at 100% CPU.
        services.settings.showMenuBarIcon = true
        if services.settings.showDockIcon {
            services.settings.showDockIcon = false
        }

        // Drop poisoned StatusKit autosave keys from older builds (ScreenForgeMain / VisibleCC=0).
        Self.clearLegacyStatusItemAutosaveDefaults()

        setupStatusItem()
        UpdateController.shared.start()

        if services.settings.launchAtLogin {
            _ = services.launchAtLogin.applyPreference(true)
        }

        let args = ProcessInfo.processInfo.arguments
        let isSmoke = args.contains("--smoke-test")
        let isDocs = args.contains("--docs-screenshots")
        if isSmoke || isDocs {
            services.settings.hasCompletedOnboarding = true
        }

        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

        if isSmoke {
            Task { @MainActor in
                await SmokeTestRunner.run(services: services)
            }
        }

        if isDocs {
            Task { @MainActor in
                await DocsScreenshotRunner.run(services: services)
            }
        }
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

    /// Ensure a stable status item exists so System Settings → Menu Bar can list ScreenForge.
    /// Match PasteRush: no activation-policy flip, no autosaveName (Tahoe StatusKit poison).
    func reRegisterStatusItemForMenuBarAllowList() {
        AppServices.shared.settings.showMenuBarIcon = true
        Self.clearLegacyStatusItemAutosaveDefaults()
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem(forceRecreate: true)
        statusItem?.isVisible = true
        DiagnosticLog.shared.info("menubar.statusItem.reregistered visible=\(statusItem?.isVisible == true)")
    }

    private func setupStatusItem(forceRecreate: Bool = false) {
        if forceRecreate, let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
        if statusItem != nil {
            statusItem?.isVisible = true
            return
        }

        // PasteRush pattern: no autosaveName. Named autosave ("ScreenForgeMain") let
        // Control Center persist VisibleCC=0 across relaunches; recreate could not recover.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenForge"
        }
        item.menu = buildMenu(services: AppServices.shared)
        statusItem = item
        DiagnosticLog.shared.info("menubar.statusItem.created length=\(item.length) visible=\(item.isVisible)")
    }

    /// Older builds used autosaveName "ScreenForgeMain"; clear any leftover visibility prefs.
    private static func clearLegacyStatusItemAutosaveDefaults() {
        let d = UserDefaults.standard
        let keys = [
            "NSStatusItem Preferred Position ScreenForgeMain",
            "NSStatusItem Visible ScreenForgeMain",
            "NSStatusItem VisibleCC ScreenForgeMain"
        ]
        for key in keys {
            if d.object(forKey: key) != nil {
                d.removeObject(forKey: key)
                DiagnosticLog.shared.info("menubar.clearedAutosave key=\(key)")
            }
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
        lifecycle?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let screenForgeMenuBarPreferenceChanged = Notification.Name("screenForgeMenuBarPreferenceChanged")
}
