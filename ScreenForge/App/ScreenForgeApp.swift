import SwiftUI
import AppKit

@main
struct ScreenForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppServices.shared.settings

    var body: some Scene {
        // Tahoe-native menu bar hosting (Control Center). Prefer this over AppKit NSStatusItem
        // when a bundle ID's status-item slot is poisoned (Allow=ON but icon stays off-screen).
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarExtraContent()
        } label: {
            Image(systemName: "camera.viewfinder")
                .symbolRenderingMode(.monochrome)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environmentObject(settings)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarIcon },
            set: { settings.showMenuBarIcon = $0 }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private(set) var lifecycle: AppLifecycleController?

    func lifecycleRegisterHotkeysAfterOnboarding() {
        lifecycle?.registerHotkeysAfterOnboarding()
    }

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

    /// Menu bar visibility is owned by SwiftUI `MenuBarExtra(isInserted:)`.
    func applyMenuBarIconPreference() {
        // No-op: `showMenuBarIcon` drives MenuBarExtra via binding.
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
