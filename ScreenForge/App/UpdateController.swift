import AppKit
import Sparkle

@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private var updaterController: SPUStandardUpdaterController?

    private init() {}

    /// Call after the menu-bar status item is installed (PasteRush order).
    func start() {
        guard updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        DiagnosticLog.shared.info("sparkle.started")
    }

    func checkForUpdates() {
        start()
        updaterController?.checkForUpdates(nil)
    }
}
