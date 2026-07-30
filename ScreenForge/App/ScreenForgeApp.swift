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
    private var lifecycle: AppLifecycleController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PerformanceMonitor.shared.log("app.launch")
        NSApp.setActivationPolicy(.accessory)
        let services = AppServices.shared
        lifecycle = AppLifecycleController(services: services)
        lifecycle?.start()

        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            services.settings.hasCompletedOnboarding = true
            Task { @MainActor in
                await SmokeTestRunner.run(services: services)
            }
        }
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
