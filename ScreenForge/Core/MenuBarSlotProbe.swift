import AppKit

/// Answers one question: is our status item actually rendered in the menu bar?
///
/// `NSStatusItem.isVisible` lies — it stays true while StatusKit refuses the item, and the
/// button window then keeps a 22 pt frame parked below the origin. A granted slot is full menu
/// bar height and is backed by a Control Center window at the same position, because Tahoe draws
/// third-party items through Control Center rather than the owning process.
@MainActor
enum MenuBarSlotProbe {
    enum State {
        case rendered(NSRect)
        case refused(NSRect)
        /// A fullscreen app hides the whole menu bar; no item can hold a slot right now.
        case menuBarHidden
    }

    static func state(of item: NSStatusItem?) -> State {
        guard let window = item?.button?.window, let screen = window.screen ?? NSScreen.main else {
            return .refused(.zero)
        }
        let frame = window.frame
        let rendered = menuBarItemWindows()
        if rendered.isEmpty { return .menuBarHidden }

        let fillsMenuBar = frame.height >= screen.frame.maxY - screen.visibleFrame.maxY - 2
        let atTop = frame.maxY >= screen.frame.maxY - 2
        let hasWindow = rendered.contains { abs($0.minX - frame.minX) <= 4 && abs($0.width - frame.width) <= 12 }
        return fillsMenuBar && atTop && hasWindow ? .rendered(frame) : .refused(frame)
    }

    /// Waits for the window server to assign a slot, which takes a few runloop turns after launch.
    static func resolve(_ item: @autoclosure @escaping () -> NSStatusItem?, timeout: TimeInterval) async -> State {
        var last = State.refused(.zero)
        for _ in 0..<Int(timeout * 10) {
            last = state(of: item())
            if case .rendered = last { return last }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return last
    }

    /// Menu bar item windows, matched by layer and geometry. Owner names are useless: Control
    /// Center's name is localized ("Centrum sterowania") and it owns other apps' items too.
    static func menuBarItemWindows() -> [CGRect] {
        guard let screen = NSScreen.main,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return windows.compactMap { window in
            // Exactly status level: the cursor window matches the same geometry from far above,
            // and 26/27 are fullscreen menu bar overlays and notch apps.
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                return nil
            }
            let rect = CGRect(
                x: bounds["X"] ?? .greatestFiniteMagnitude,
                y: bounds["Y"] ?? .greatestFiniteMagnitude,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard rect.minY >= 0, rect.minY < 4,
                  rect.height >= 16, rect.height <= menuBarHeight + 4,
                  rect.width < screen.frame.width / 2 else {
                return nil
            }
            return rect
        }
    }
}
