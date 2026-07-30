import SwiftUI
import AppKit
import CoreGraphics

@main
struct ScreenForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppServices.shared.settings

    var body: some Scene {
        MenuBarExtra(
            "ScreenForge",
            systemImage: "camera.viewfinder",
            isInserted: $settings.showMenuBarIcon
        ) {
            MenuBarExtraContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environmentObject(settings)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var lifecycle: AppLifecycleController?
    private var menuBarVisibilityCheckTask: Task<Void, Never>?

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

        migrateStaleMenuBarDefaultsIfNeeded()

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

    /// One-shot: clear Tahoe/Control Center leftovers from NSStatusItem + old bundle ID.
    private func migrateStaleMenuBarDefaultsIfNeeded() {
        let flagKey = "sf.menubarMigrationTahoe"
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: flagKey) == false else { return }

        let domains = ["com.screenforge.app", "com.local.ScreenForge"]
        for domain in domains {
            guard let persistent = UserDefaults(suiteName: domain) else { continue }
            let dict = persistent.dictionaryRepresentation()
            for key in dict.keys where key.hasPrefix("NSStatusItem ") {
                persistent.removeObject(forKey: key)
                DiagnosticLog.shared.info("menubar.migrate removed \(domain).\(key)")
            }
            persistent.synchronize()
        }

        // Also scrub current standard defaults (same as com.screenforge.app when running).
        let std = defaults.dictionaryRepresentation()
        for key in std.keys where key.hasPrefix("NSStatusItem ") {
            defaults.removeObject(forKey: key)
            DiagnosticLog.shared.info("menubar.migrate removed standard.\(key)")
        }

        defaults.set(true, forKey: flagKey)
        DiagnosticLog.shared.info("menubar.migrate done")
    }

    private func scheduleMenuBarVisibilityCheck() {
        menuBarVisibilityCheckTask?.cancel()
        menuBarVisibilityCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            guard AppServices.shared.settings.showMenuBarIcon else { return }
            if hasOnScreenMenuBarPresence() {
                DiagnosticLog.shared.info("menubar.visible.onScreen=true")
                return
            }
            DiagnosticLog.shared.warn("menubar.visible.onScreen=false — prompting Menu Bar settings")
            presentMenuBarAllowAlertIfNeeded()
        }
    }

    /// Best-effort: MenuBarExtra may be hosted by Control Center; still detect off-screen proxies.
    private func hasOnScreenMenuBarPresence() -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let infoList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= 24 else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any] {
                let y = (bounds["Y"] as? CGFloat) ?? (bounds["Y"] as? Double).map { CGFloat($0) } ?? -1
                if y >= 0 { return true }
            }
        }

        // Fallback: any NSStatusItem-style button window with a real screen.
        for window in NSApp.windows {
            guard window.level.rawValue >= NSWindow.Level.statusBar.rawValue - 1 else { continue }
            if window.screen != nil, window.frame.origin.y >= 0 { return true }
        }
        return false
    }

    private func presentMenuBarAllowAlertIfNeeded() {
        let key = "sf.menubarBlockedAlertShown"
        guard UserDefaults.standard.bool(forKey: key) == false else { return }
        UserDefaults.standard.set(true, forKey: key)

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
