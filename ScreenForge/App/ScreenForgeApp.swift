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
    private var statusItem: NSStatusItem?
    private var repositionTask: Task<Void, Never>?

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

        for key in [
            "NSStatusItem Preferred Position ScreenForgeMain",
            "NSStatusItem Visible ScreenForgeMain",
            "NSStatusItem VisibleCC ScreenForgeMain",
            "NSStatusItem Preferred Position ScreenForgeStatus20",
            "NSStatusItem Visible ScreenForgeStatus20",
            "NSStatusItem VisibleCC ScreenForgeStatus20"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        setupStatusItem()
        scheduleRepositionUntilVisible()
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
        guard AppServices.shared.settings.showMenuBarIcon else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            return
        }
        if statusItem == nil {
            setupStatusItem()
        } else {
            statusItem?.isVisible = true
        }
        scheduleRepositionUntilVisible()
    }

    func reRegisterStatusItemForMenuBarAllowList() {
        AppServices.shared.settings.showMenuBarIcon = true
        NSApp.setActivationPolicy(.accessory)
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
        setupStatusItem()
        scheduleRepositionUntilVisible()
        DiagnosticLog.shared.info("menubar.reregistered")
    }

    private func setupStatusItem() {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ScreenForge"
        }
        item.menu = buildMenu(services: AppServices.shared)
        statusItem = item
        DiagnosticLog.shared.info("menubar.created frame=\(String(describing: item.button?.window?.frame))")
    }

    /// Tahoe parks new items at x≈screenMax (clipped) or y=-17. Drag the status window
    /// into the visible cluster (same zone as PasteRush ~540pt from the trailing system icons).
    private func scheduleRepositionUntilVisible() {
        guard !isAutomatedRun else { return }
        repositionTask?.cancel()
        repositionTask = Task { @MainActor in
            for attempt in 1...8 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                guard let item = statusItem, let button = item.button else { continue }
                item.isVisible = true

                // Force layout
                button.needsDisplay = true
                button.window?.displayIfNeeded()

                guard let window = button.window, let screen = window.screen ?? NSScreen.main else {
                    DiagnosticLog.shared.info("menubar.reposition#\(attempt) no window yet")
                    continue
                }

                var f = window.frame
                let before = f
                // Place ~280pt left of the trailing screen edge (left of clock/battery cluster).
                let targetX = screen.frame.maxX - 280
                let targetY = screen.frame.maxY - max(f.height, 22)
                f.size.width = max(f.size.width, 22)
                f.size.height = max(f.size.height, 22)
                f.origin.x = targetX
                f.origin.y = targetY
                window.setFrame(f, display: true)

                let after = window.frame
                DiagnosticLog.shared.info(
                    "menubar.reposition#\(attempt) before=\(before) after=\(after) targetX=\(targetX)"
                )

                if after.origin.y >= 0, after.height >= 16,
                   after.origin.x + after.width < screen.frame.maxX - 4,
                   after.origin.x < screen.frame.maxX - 40 {
                    DiagnosticLog.shared.info("menubar.visible")
                    return
                }
            }
            DiagnosticLog.shared.error("menubar.reposition.failed")
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

    func applicationDidBecomeActive(_ notification: Notification) {
        guard AppServices.shared.settings.showMenuBarIcon else { return }
        scheduleRepositionUntilVisible()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        repositionTask?.cancel()
        lifecycle?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let screenForgeMenuBarPreferenceChanged = Notification.Name("screenForgeMenuBarPreferenceChanged")
}
