import Foundation
import AppKit
import ScreenCaptureKit

@MainActor
final class WindowSelectionCoordinator {
    private let capture: ScreenCaptureService
    private let displays: DisplayTopologyService
    private let settings: SettingsStore
    private var overlayWindows: [NSWindow] = []
    private var highlightView: WindowHighlightView?
    private var continuation: CheckedContinuation<CaptureResult?, Never>?
    private var windows: [SCWindow] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var failsafeTask: Task<Void, Never>?

    init(capture: ScreenCaptureService, displays: DisplayTopologyService, settings: SettingsStore) {
        self.capture = capture
        self.displays = displays
        self.settings = settings
    }

    func beginSelection() async -> CaptureResult? {
        if continuation != nil {
            cancel()
        }
        do {
            windows = try await capture.provider.availableWindows().filter { win in
                let bid = win.owningApplication?.bundleIdentifier
                return bid != Bundle.main.bundleIdentifier
            }
        } catch {
            AppServices.shared.notifications.showError(error.localizedDescription)
            return nil
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.showOverlays()
        }
    }

    private func showOverlays() {
        displays.refresh()
        for info in displays.displays {
            let view = WindowHighlightView()
            view.onSelect = { [weak self] in self?.confirm() }
            view.onCancel = { [weak self] in self?.cancel() }
            let window = RegionOverlayWindow(
                contentRect: info.geometry.framePoints,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(info.geometry.framePoints, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.contentView = view
            window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless()
            // Nonactivating panel: key for Esc/Return, but this does not activate the app or the space.
            window.makeKey()
            overlayWindows.append(window)
            highlightView = view
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown]) { [weak self] event in
            self?.handle(event)
            if event.type == .keyDown && (event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76) {
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch event.type {
                case .keyDown where event.keyCode == 53:
                    self.cancel()
                case .keyDown where event.keyCode == 36 || event.keyCode == 76:
                    self.confirm()
                case .mouseMoved:
                    self.updateHighlight()
                case .leftMouseDown:
                    self.updateHighlight()
                    self.confirm()
                default:
                    break
                }
            }
        }
        scheduleFailsafeCancel()
        updateHighlight()
    }

    private func scheduleFailsafeCancel() {
        failsafeTask?.cancel()
        failsafeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            guard !Task.isCancelled, continuation != nil else { return }
            DiagnosticLog.shared.warn("window.selection.failsafeCancel")
            cancel()
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 {
            cancel(); return
        }
        if event.type == .keyDown && (event.keyCode == 36 || event.keyCode == 76) {
            confirm(); return
        }
        updateHighlight()
        if event.type == .leftMouseDown {
            confirm()
        }
    }

    private func updateHighlight() {
        let mouse = NSEvent.mouseLocation
        let hit = windows.first { $0.frame.contains(mouse) }
        for window in overlayWindows {
            if let hit {
                let screenRect = hit.frame
                let localOrigin = window.convertPoint(fromScreen: screenRect.origin)
                (window.contentView as? WindowHighlightView)?.highlightedFrame = CGRect(x: localOrigin.x, y: localOrigin.y, width: screenRect.width, height: screenRect.height)
            } else {
                (window.contentView as? WindowHighlightView)?.highlightedFrame = nil
            }
            window.contentView?.needsDisplay = true
        }
        currentWindow = hit
    }

    private var currentWindow: SCWindow?

    private func confirm() {
        guard let continuation else { return }
        self.continuation = nil
        guard let win = currentWindow else {
            tearDown()
            continuation.resume(returning: nil)
            return
        }
        let includeShadow = settings.windowIncludeShadow
        let margin = settings.windowMargin
        tearDown()
        Task {
            do {
                let result = try await capture.captureSCWindow(win, includeShadow: includeShadow, margin: margin)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Number of overlays currently on screen — lets the smoke suite drive a real selection.
    var overlayCount: Int { overlayWindows.count }

    func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        tearDown()
        continuation.resume(returning: nil)
    }

    private func tearDown() {
        failsafeTask?.cancel()
        failsafeTask = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        overlayWindows.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        overlayWindows = []
        highlightView = nil
        windows = []
        AppActivation.resignAfterTransientUI()
    }
}

@MainActor
final class WindowHighlightView: NSView {
    var highlightedFrame: CGRect?
    var onSelect: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        if let frame = highlightedFrame {
            NSColor.systemTeal.setStroke()
            let path = NSBezierPath(rect: frame)
            path.lineWidth = 3
            path.stroke()
            NSColor.systemTeal.withAlphaComponent(0.15).setFill()
            path.fill()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else if event.keyCode == 36 { onSelect?() }
        else { super.keyDown(with: event) }
    }
}
