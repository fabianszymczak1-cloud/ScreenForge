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
    private var monitor: Any?

    init(capture: ScreenCaptureService, displays: DisplayTopologyService, settings: SettingsStore) {
        self.capture = capture
        self.displays = displays
        self.settings = settings
    }

    func beginSelection() async -> CaptureResult? {
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
            let window = NSWindow(
                contentRect: info.geometry.framePoints,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(info.geometry.framePoints, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless()
            overlayWindows.append(window)
            highlightView = view
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
        updateHighlight()
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

    private func convertFromScreen(_ rect: CGRect, to window: NSWindow) -> CGRect {
        window.convertFromScreen(rect)
    }

    private func confirm() {
        guard let win = currentWindow else { cancel(); return }
        let includeShadow = settings.windowIncludeShadow
        let margin = settings.windowMargin
        tearDown()
        Task {
            do {
                let result = try await capture.captureSCWindow(win, includeShadow: includeShadow, margin: margin)
                continuation?.resume(returning: result)
                continuation = nil
            } catch {
                continuation?.resume(returning: nil)
                continuation = nil
            }
        }
    }

    private func cancel() {
        tearDown()
        continuation?.resume(returning: nil)
        continuation = nil
    }

    private func tearDown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        overlayWindows.forEach { $0.close() }
        overlayWindows = []
        highlightView = nil
        windows = []
    }
}

private extension NSWindow {
    func convertFromScreen(_ rect: CGRect) -> CGRect {
        let origin = convertPoint(fromScreen: rect.origin)
        // frame is in screen coords bottom-left; content view uses bottom-left
        return CGRect(x: origin.x, y: origin.y, width: rect.width, height: rect.height)
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
            NSColor.clear.setFill()
            // punch hole visually by not filling
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
