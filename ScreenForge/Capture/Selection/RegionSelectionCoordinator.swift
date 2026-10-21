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
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var failsafeTask: Task<Void, Never>?

    init(capture: ScreenCaptureService, displays: DisplayTopologyService, coordinates: CoordinateConverter, settings: SettingsStore, lastRegion: LastRegionStore) {
        self.capture = capture
        self.displays = displays
        self.coordinates = coordinates
        self.settings = settings
        self.lastRegion = lastRegion
    }

    func beginSelection() async -> CaptureResult? {
        // Never stack overlays — re-entry used to leave undismissable .screenSaver windows.
        if continuation != nil {
            regionSelectionDidCancel()
        }

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
            if self.overlays.isEmpty {
                self.continuation = nil
                cont.resume(returning: nil)
                return
            }
            overlays.forEach { $0.show() }
            installKeyMonitors()
            scheduleFailsafeCancel()
            _ = PerformanceMonitor.shared.end("region.overlay")
            let mouse = NSEvent.mouseLocation
            if let preferred = overlays.first(where: { $0.displayInfo.geometry.framePoints.contains(mouse) })
                ?? overlays.first {
                preferred.window?.makeKeyAndOrderFront(nil)
                preferred.window?.makeFirstResponder(preferred.selectionView)
            }
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        // Global monitor: accessory apps often lose key focus under fullscreen overlays.
        // Observe-only — still lets us cancel when Esc would otherwise be swallowed.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .mouseMoved {
                    self.overlays.forEach { $0.selectionView.needsDisplay = true }
                    return
                }
                switch event.keyCode {
                case 53:
                    self.regionSelectionDidCancel()
                case 36, 76:
                    if let oc = self.overlays.first(where: { $0.window?.isKeyWindow == true }) ?? self.overlays.first {
                        oc.selectionView.confirmIfPossible()
                    }
                case 49:
                    self.regionSelectionRequestWindowMode()
                default:
                    break
                }
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53:
            regionSelectionDidCancel()
            return nil
        case 36, 76:
            if let oc = overlays.first(where: { $0.window?.isKeyWindow == true }) ?? overlays.first {
                oc.selectionView.confirmIfPossible()
            }
            return nil
        default:
            return event
        }
    }

    private func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func scheduleFailsafeCancel() {
        failsafeTask?.cancel()
        failsafeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
            guard !Task.isCancelled, continuation != nil else { return }
            DiagnosticLog.shared.warn("region.selection.failsafeCancel")
            regionSelectionDidCancel()
        }
    }

    func captureLastRegion() async -> CaptureResult? {
        displays.refresh()
        guard let resolved = lastRegion.resolve(using: displays, coordinates: coordinates) else {
            return nil
        }
        do {
            var result = try await capture.captureRegionPixels(resolved.pixelRect, displayID: resolved.displayID)
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
        guard let continuation else { return }
        self.continuation = nil
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
                continuation.resume(returning: result)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Number of overlays currently on screen — lets the smoke suite drive a real selection.
    var overlayCount: Int { overlays.count }

    func regionSelectionDidCancel() {
        guard let continuation else { return }
        self.continuation = nil
        tearDown()
        continuation.resume(returning: nil)
    }

    func regionSelectionRequestWindowMode() {
        guard let continuation else { return }
        self.continuation = nil
        tearDown()
        continuation.resume(returning: nil)
        Task {
            _ = await AppServices.shared.captureWindow(destination: .editor)
        }
    }

    private func tearDown() {
        failsafeTask?.cancel()
        failsafeTask = nil
        removeKeyMonitors()
        overlays.forEach {
            $0.window?.orderOut(nil)
            $0.close()
        }
        overlays = []
        frozen = [:]
        AppActivation.resignAfterTransientUI()
    }
}
