import AppKit

/// Borderless fullscreen overlay that can still become key (needed for Esc / Return).
final class RegionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // Callers hold the overlay themselves and close it explicitly. The AppKit default would
        // release it a second time on close, crashing the next autorelease pool drain.
        isReleasedWhenClosed = false
    }
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
        // Below Mission Control / Force Quit — .screenSaver can lock an accessory app's Esc path.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 8)
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
