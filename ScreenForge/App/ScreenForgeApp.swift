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
    /// Strong ref — must outlive the status bar (PasteRush pattern).
    private var statusItem: NSStatusItem?
    private var menuBarObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        PerformanceMonitor.shared.log("app.launch")
        let services = AppServices.shared
        NSApp.setActivationPolicy(.accessory)
        applyMenuBarIconPreference()

        menuBarObserver = NotificationCenter.default.addObserver(
            forName: .screenForgeMenuBarPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyMenuBarIconPreference() }
        }

        if services.settings.launchAtLogin {
            _ = services.launchAtLogin.applyPreference(true)
        }

        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

        // Re-assert after lifecycle (onboarding / permission windows can race status item on Tahoe).
        DispatchQueue.main.async { [weak self] in
            self?.applyMenuBarIconPreference()
        }

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

    func applyMenuBarIconPreference() {
        let show = AppServices.shared.settings.showMenuBarIcon
        if show {
            if statusItem == nil {
                setupStatusItem(services: AppServices.shared)
            }
            statusItem?.isVisible = true
            // Tahoe sometimes drops the image after activation-policy churn.
            if statusItem?.button?.image == nil {
                statusItem?.button?.image = Self.statusImage()
                statusItem?.button?.image?.isTemplate = true
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private static func statusImage() -> NSImage? {
        if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge") {
            return img
        }
        // Fallback if SF Symbol missing
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14))
        path.lineWidth = 1.5
        path.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func setupStatusItem(services: AppServices) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.statusImage()
            button.image?.isTemplate = true
            button.toolTip = "ScreenForge"
        }
        item.menu = buildMenu(services: services)
        item.isVisible = true
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = menuBarObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycle?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// After editor / settings windows, keep accessory + status item alive.
    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        applyMenuBarIconPreference()
    }
}

extension Notification.Name {
    static let screenForgeMenuBarPreferenceChanged = Notification.Name("screenForgeMenuBarPreferenceChanged")
}
