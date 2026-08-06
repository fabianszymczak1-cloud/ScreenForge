import Foundation
import AppKit

@MainActor
final class AppLifecycleController {
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        services.history.open()
        services.displays.refresh()
        services.menuBar.install()

        // macOS force-quits after Screen Recording grant — restore flag must reopen welcome.
        if PermissionManager.shouldRestoreOnboardingAfterTCC {
            services.settings.hasCompletedOnboarding = false
        }

        if services.settings.hasCompletedOnboarding {
            services.hotkeys.registerAll()
            Task {
                let granted = await services.permissions.refreshAsync()
                if services.settings.checkPermissionsOnLaunch && !granted {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    let grantedLater = await services.permissions.refreshAsync()
                    if !grantedLater {
                        services.permissions.presentPermissionsGate()
                    }
                }
            }
            recoverAutosavesIfNeeded()
        } else {
            DispatchQueue.main.async {
                self.services.permissions.presentOnboarding()
            }
            Task { _ = await services.permissions.refreshAsync() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.services.displays.refresh()
            }
        }
    }

    func registerHotkeysAfterOnboarding() {
        guard services.settings.hasCompletedOnboarding else { return }
        services.hotkeys.registerAll()
    }

    func prepareForTermination() {
        services.editorWindows.flushAutosaves()
        services.hotkeys.unregisterAll()
        services.history.close()
    }

    private func recoverAutosavesIfNeeded() {
        let urls = ProjectDocumentSerializer.recoveryURLs()
        guard !urls.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Document recovery")
        alert.informativeText = String(localized: "Found \(urls.count) unsaved documents. Open them?")
        alert.addButton(withTitle: String(localized: "Recover"))
        alert.addButton(withTitle: String(localized: "Discard"))
        if alert.runModal() == .alertFirstButtonReturn {
            for url in urls {
                services.editorWindows.openProject(url: url)
            }
        } else {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
