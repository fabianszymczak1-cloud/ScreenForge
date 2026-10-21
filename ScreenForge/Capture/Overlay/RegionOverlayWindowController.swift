import AppKit

/// Borderless fullscreen overlay that can take the keyboard without becoming the app's main window.
///
/// A normal `NSWindow` that `canBecomeMain` and is ordered in with `activate(ignoringOtherApps:)`
/// joins the active fullscreen or Split View space. After it closes, WindowServer still treats
/// ScreenForge as the owner of that space, so Mission Control and Dock clicks bounce back to it.
/// Trackpad swipes still work because they bypass that affinity. A nonactivating panel that cannot
/// become main, marked `.transient`, is ignored by space switching.
final class RegionOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        var mask = style
        mask.insert(.borderless)
        mask.insert(.nonactivatingPanel)
        super.init(contentRect: contentRect, styleMask: mask, backing: backingStoreType, defer: flag)
        // Callers hold the overlay themselves and close it explicitly. The AppKit default would
        // release it a second time on close, crashing the next autorelease pool drain.
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        animationBehavior = .none
        isRestorable = false
        isExcludedFromWindowsMenu = true
        // Above document windows, below Mission Control / the screen saver.
        level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 8)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
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
        window?.makeKey()
        window?.makeFirstResponder(selectionView)
    }
}
