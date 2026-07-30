import Foundation
import AppKit

@MainActor
final class RegionSelectionCoordinator: RegionSelectionViewDelegate {
    private let capture: ScreenCaptureService
    private let displays: DisplayTopologyService
    private let coordinates: CoordinateConverter
    private let settings: SettingsStore
    private let lastRegion: LastRegionStore

    private var overlays: [RegionOverlayWindowController] = []
    private var frozen: [CGDirectDisplayID: CGImage] = [:]
    private var continuation: CheckedContinuation<CaptureResult?, Never>?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

    init(capture: ScreenCaptureService, displays: DisplayTopologyService, coordinates: CoordinateConverter, settings: SettingsStore, lastRegion: LastRegionStore) {
        self.capture = capture
        self.displays = displays
        self.coordinates = coordinates
        self.settings = settings
        self.lastRegion = lastRegion
    }

    func beginSelection() async -> CaptureResult? {
        previousApp = NSWorkspace.shared.frontmostApplication
        PerformanceMonitor.shared.begin("region.overlay")
        displays.refresh()
        do {
            frozen = try await capture.freezeAllDisplays(excludeWindowIDs: capture.ownWindowIDs())
        } catch {
            AppServices.shared.notifications.showError(error.localizedDescription)
            return nil
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.overlays = displays.displays.compactMap { info in
                guard let image = frozen[info.id] else { return nil }
                let oc = RegionOverlayWindowController(displayInfo: info, frozenImage: image, settings: settings)
                oc.selectionView.delegate = self
                return oc
            }
            overlays.forEach { $0.show() }
            installKeyMonitor()
            _ = PerformanceMonitor.shared.end("region.overlay")
            NSApp.activate(ignoringOtherApps: true)
            // Prefer overlay under the cursor as key
            let mouse = NSEvent.mouseLocation
            if let preferred = overlays.first(where: { $0.displayInfo.geometry.framePoints.contains(mouse) })
                ?? overlays.first {
                preferred.window?.makeKeyAndOrderFront(nil)
                preferred.window?.makeFirstResponder(preferred.selectionView)
            }
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape — leave region selection entirely
                self.regionSelectionDidCancel()
                return nil
            case 36, 76: // Return — confirm if there is a selection on the key overlay
                if let oc = self.overlays.first(where: { $0.window?.isKeyWindow == true }) ?? self.overlays.first {
                    oc.selectionView.confirmIfPossible()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func captureLastRegion() async -> CaptureResult? {
        displays.refresh()
        guard let resolved = lastRegion.resolve(using: displays, coordinates: coordinates) else {
            return nil
        }
        do {
            var result = try await capture.captureRegionPixels(resolved.pixelRect, displayID: resolved.displayID)
            // Mark as lastRegion kind
            result = CaptureResult(
                image: result.image,
                kind: .lastRegion,
                displayID: result.displayID,
                regionPoints: result.regionPoints,
                regionPixels: result.regionPixels,
                sourceAppName: result.sourceAppName,
                layoutSignature: displays.layoutSignature
            )
            return result
        } catch {
            return nil
        }
    }

    func regionSelectionDidComplete(displayID: CGDirectDisplayID, pixelRect: CGRect, pointRect: CGRect) {
        guard continuation != nil else { return }
        let image = frozen[displayID]
        tearDown()
        Task {
            do {
                let result = try await capture.captureRegionPixels(pixelRect, displayID: displayID, frozen: image)
                if let geo = displays.display(id: displayID)?.geometry {
                    lastRegion.save(
                        displayID: displayID,
                        pixelRect: pixelRect,
                        pointRect: pointRect,
                        layoutSignature: displays.layoutSignature,
                        scale: geo.scale,
                        kind: .region
                    )
                }
                continuation?.resume(returning: result)
                continuation = nil
            } catch {
                continuation?.resume(returning: nil)
                continuation = nil
            }
        }
    }

    func regionSelectionDidCancel() {
        guard continuation != nil else { return }
        tearDown()
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func regionSelectionRequestWindowMode() {
        guard continuation != nil else { return }
        tearDown()
        continuation?.resume(returning: nil)
        continuation = nil
        Task {
            _ = await AppServices.shared.captureWindow(destination: .editor)
        }
    }

    private func tearDown() {
        removeKeyMonitor()
        overlays.forEach { $0.close() }
        overlays = []
        frozen = [:]
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }
}
