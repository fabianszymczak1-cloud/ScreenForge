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

    private var lifecycle: AppLifecycleController?
    /// Strong ref — exact PasteRush pattern; must outlive the status bar.
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared

        // PasteRush order: accessory → status item → everything else.
        NSApp.setActivationPolicy(.accessory)

        // Menu-bar-only app: never keep a persisted dock preference.
        if services.settings.showDockIcon {
            services.settings.showDockIcon = false
        }
        if !services.settings.showMenuBarIcon {
            services.settings.showMenuBarIcon = true
        }

        setupStatusItem()

        if services.settings.launchAtLogin {
            _ = services.launchAtLogin.applyPreference(true)
        }

        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

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

    /// Settings toggle: show/hide. Launch always calls `setupStatusItem()` directly.
    func applyMenuBarIconPreference() {
        if AppServices.shared.settings.showMenuBarIcon {
            if statusItem == nil {
                setupStatusItem()
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Mirror PasteRushApp.setupStatusItem() as closely as possible.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            button.image?.isTemplate = true
            button.toolTip = "ScreenForge"
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
