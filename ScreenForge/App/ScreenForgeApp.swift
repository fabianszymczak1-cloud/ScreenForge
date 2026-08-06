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

    private(set) var lifecycle: AppLifecycleController?
    /// Exposed for tests — the app itself is the XCTest host, so the live item is inspectable.
    private(set) var statusItem: NSStatusItem?
    private var didRetryStatusItemSlot = false
    /// False once every recovery step has failed, which means the menu bar allow list has the
    /// bundle ID poisoned and only Reset Control Center in System Settings can clear it.
    private(set) var hasMenuBarSlot = true

    func lifecycleRegisterHotkeysAfterOnboarding() {
        lifecycle?.registerHotkeysAfterOnboarding()
    }

    private var isAutomatedRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--smoke-test") || args.contains("--docs-screenshots")
    }

    /// Answers the parent process's Screen Recording question and exits before any app state is
    /// touched — this instance exists only to get an uncached answer out of tccd.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains(PermissionManager.preflightProbeArgument) {
            exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
        }
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

        // Do not pre-seed VisibleCC — PasteRush lets Control Center write those keys.
        // Pre-seeding can leave the app domain "visible" while StatusKit never tracks the host.

        setupStatusItem()
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
        }
    }

    func reRegisterStatusItemForMenuBarAllowList() {
        AppServices.shared.settings.showMenuBarIcon = true
        NSApp.setActivationPolicy(.accessory)
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
        setupStatusItem()
        // Best-effort: repair Tahoe Control Center allow-list for this bundle ID.
        MenuBarAllowListRepair.runIfPossible()
        DiagnosticLog.shared.info("menubar.reregistered")
    }

    /// PasteRush-identical status item setup (variableLength, template image, strong ref).
    func setupStatusItem() {
        if statusItem != nil { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            button.image?.isTemplate = true
            button.toolTip = "ScreenForge"
        }
        statusItem?.menu = buildMenu(services: AppServices.shared)
        DiagnosticLog.shared.info("menubar.created")
        verifyStatusItemSlot()
    }

    /// StatusKit can refuse the item silently: `isVisible` stays true while the button window sits
    /// parked below the menu bar. Escalate once per launch, cheapest step first.
    private func verifyStatusItemSlot() {
        guard !didRetryStatusItemSlot else { return }
        Task { @MainActor in
            switch await MenuBarSlotProbe.resolve(self.statusItem, timeout: 4) {
            case .rendered(let frame):
                DiagnosticLog.shared.info("menubar.slot.rendered frame=\(NSStringFromRect(frame))")
                return
            case .menuBarHidden:
                DiagnosticLog.shared.info("menubar.slot.menuBarHidden")
                return
            case .refused(let frame):
                DiagnosticLog.shared.info("menubar.slot.refused frame=\(NSStringFromRect(frame))")
            }

            didRetryStatusItemSlot = true
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            setupStatusItem()
            DiagnosticLog.shared.info("menubar.slot.recreated")

            if case .rendered = await MenuBarSlotProbe.resolve(self.statusItem, timeout: 4) {
                DiagnosticLog.shared.info("menubar.slot.recoveredByRecreate")
                return
            }

            // An update swapped the bundle under a running Control Center: it still holds the
            // binding from the previous copy and only re-reads the list after a restart.
            MenuBarAllowListRepair.reloadControlCenter()
            if case .rendered = await MenuBarSlotProbe.resolve(self.statusItem, timeout: 8) {
                DiagnosticLog.shared.info("menubar.slot.recoveredByControlCenterReload")
                return
            }
            hasMenuBarSlot = false
            DiagnosticLog.shared.warn("menubar.slot.unavailable needsControlCenterReset")
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
