import AppKit

/// App Store builds update through the Mac App Store. Sparkle is not allowed there.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private init() {}

    func start() {
        DiagnosticLog.shared.info("updates.appStore")
    }

    func checkForUpdates() {}
}
