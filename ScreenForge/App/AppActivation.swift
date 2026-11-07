import AppKit

/// Activation helpers that do not pin ScreenForge to a fullscreen or Split View space.
///
/// `activate(ignoringOtherApps: true)` records a space switch. WindowServer then replays it:
/// clicking another desktop in Mission Control or the Dock returns to the fullscreen app,
/// while a three-finger swipe still works. Nothing in the app may call it.
enum AppActivation {
    /// Foreground a real document window (settings, history) without forcing a space change.
    static func activateForDocumentWindow() {
        NSApp.activate()
    }

    /// Editor after a capture. The editor is a nonactivating panel, so making it key is enough for
    /// ⌘↩ to arrive and the frontmost app keeps its activation.
    static func focusEditor(_ window: NSWindow?) {
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    /// Leave the foreground after transient UI so this process is no longer the space owner.
    static func resignAfterTransientUI() {
        let hasDocument = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !(window is RegionOverlayWindow)
        }
        guard !hasDocument, NSApp.isActive else { return }
        NSApp.deactivate()
    }

    /// Hand activation back without `activateIgnoringOtherApps`, which is what sticks the space.
    static func yield(to application: NSRunningApplication?) {
        guard NSApp.isActive else { return }
        guard let application,
              !application.isTerminated,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            NSApp.deactivate()
            return
        }
        NSApp.yieldActivation(to: application)
    }
}
