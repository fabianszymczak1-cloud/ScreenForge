import Foundation
import AppKit

/// Experimental scrolling capture. Hidden unless settings.experimentalScrolling is on.
@MainActor
final class ScrollingCaptureCoordinator {
    private let capture: ScreenCaptureService
    private(set) var isAvailable = false

    init(capture: ScreenCaptureService) {
        self.capture = capture
    }

    func captureScrollingRegion() async -> CaptureResult? {
        // Manual assisted mode: user captures successive regions that get stitched.
        // Fully automatic Accessibility-based scrolling is gated and experimental.
        guard AppServices.shared.settings.experimentalScrolling else { return nil }
        AppServices.shared.notifications.show(
            title: String(localized: "Scrolling capture"),
            body: String(localized: "Experimental mode: capture successive regions; stitching is simplified.")
        )
        return await AppServices.shared.regionSelection.beginSelection()
    }
}
