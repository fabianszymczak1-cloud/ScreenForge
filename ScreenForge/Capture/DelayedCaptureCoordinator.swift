import Foundation
import AppKit

@MainActor
final class DelayedCaptureCoordinator {
    private var timer: Timer?
    private var panel: NSPanel?
    private var remaining = 0

    func start(seconds: Int, fire: @escaping @MainActor () -> Void) {
        cancel()
        remaining = max(1, seconds)
        let label = NSTextField(labelWithString: "\(remaining)")
        label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        label.alignment = .center
        label.textColor = .white
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 72))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        container.layer?.cornerRadius = 16
        label.frame = container.bounds
        container.addSubview(label)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 36, y: f.maxY - 100))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remaining -= 1
                label.stringValue = "\(self.remaining)"
                if self.remaining <= 0 {
                    self.cancel()
                    fire()
                }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
    }
}
