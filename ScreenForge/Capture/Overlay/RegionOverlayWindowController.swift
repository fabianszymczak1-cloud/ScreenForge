import AppKit

/// Borderless fullscreen overlay that can still become key (needed for Esc / Return).
final class RegionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class RegionOverlayWindowController: NSWindowController {
    let displayInfo: DisplayInfo
    let frozenImage: CGImage
    private(set) var selectionView: RegionSelectionView

    init(displayInfo: DisplayInfo, frozenImage: CGImage, settings: SettingsStore) {
        self.displayInfo = displayInfo
        self.frozenImage = frozenImage
        let view = RegionSelectionView(frozenImage: frozenImage, displayInfo: displayInfo, settings: settings)
        self.selectionView = view
        let window = RegionOverlayWindow(
            contentRect: displayInfo.geometry.framePoints,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: NSScreen.screens.first { $0.displayID == displayInfo.id }
        )
        window.setFrame(displayInfo.geometry.framePoints, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.hasShadow = false
        view.frame = window.contentRect(forFrameRect: window.frame)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.acceptsMouseMovedEvents = true
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(selectionView)
    }
}
