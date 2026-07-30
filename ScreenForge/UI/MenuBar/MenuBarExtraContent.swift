import SwiftUI

/// Menu content for SwiftUI `MenuBarExtra` (Tahoe-friendly; hosted by Control Center).
struct MenuBarExtraContent: View {
    private var menuBar: MenuBarController { AppServices.shared.menuBar }
    private var settings: SettingsStore { AppServices.shared.settings }

    var body: some View {
        Group {
            Button(String(localized: "Capture region")) { menuBar.captureRegion() }
            Button(String(localized: "Capture window")) { menuBar.captureWindow() }
            Button(String(localized: "Capture active display")) { menuBar.captureDisplay() }
            Button(String(localized: "Capture all displays")) { menuBar.captureAll() }
            Button(String(localized: "Capture last region")) { menuBar.captureLast() }
            Button(String(localized: "Capture with delay")) { menuBar.captureDelayed() }
            if settings.experimentalScrolling {
                Button(String(localized: "Scrolling capture (experimental)")) { menuBar.captureScrolling() }
            }
            Divider()
            Button(String(localized: "Open history")) { menuBar.showHistory() }
            Button(String(localized: "Open image from file…")) { menuBar.openFile() }
            Button(String(localized: "Open image from clipboard")) { menuBar.openClipboard() }
            Button(String(localized: "Last capture")) { menuBar.openLast() }
            Divider()
            Button(String(localized: "Settings…")) { menuBar.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button(String(localized: "Launch at login")) { menuBar.toggleLogin() }
            Button(String(localized: "Check permissions")) { menuBar.checkPermissions() }
            Button(String(localized: "About")) { menuBar.showAbout() }
            Button(String(localized: "Check for Updates…")) { menuBar.checkForUpdates() }
            Button(String(localized: "Buy Me a Coffee")) { menuBar.openSupport() }
            Divider()
            Button(String(localized: "Quit")) { menuBar.quit() }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
