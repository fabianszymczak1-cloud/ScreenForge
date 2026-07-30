import Foundation
import AppKit
import SwiftUI

@MainActor
final class PermissionManager: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isRefreshing = false
    private var onboardingWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    func refresh() {
        Task { await refreshAsync() }
    }

    @discardableResult
    func refreshAsync() async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }
        hasAccessibility = AXIsProcessTrusted()

        // Only use CGPreflight for automatic checks.
        // SCShareableContent.excludingDesktopWindows prompts for TCC and can
        // disrupt menu-bar hosting on macOS Tahoe — never call it on launch.
        var granted = CGPreflightScreenCaptureAccess()
        if !granted {
            // Brief retry for TCC lag after re-sign / relaunch (no prompt).
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if CGPreflightScreenCaptureAccess() {
                    granted = true
                    break
                }
            }
        }
        hasScreenRecording = granted
        return granted
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        Task { await refreshAsync() }
    }

    func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMenuBarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock?menuBar"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        Task { await refreshAsync() }
    }

    /// First launch: show full wizard only when onboarding is incomplete.
    func showOnboardingIfNeeded() {
        Task { @MainActor in
            guard !AppServices.shared.settings.hasCompletedOnboarding else { return }
            _ = await refreshAsync()
            presentOnboarding()
        }
    }

    /// After onboarding: show the compact gate only when Screen Recording is missing.
    func showPermissionsGateIfNeeded() {
        Task { @MainActor in
            let granted = await refreshAsync()
            guard !granted else { return }
            presentPermissionsGate()
        }
    }

    /// Menu “Check permissions”: always open the compact gate.
    func openPermissionsPanel() {
        Task { @MainActor in
            _ = await refreshAsync()
            presentPermissionsGate()
        }
    }

    /// Full onboarding wizard (first launch or Settings → Open onboarding).
    func presentOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        closePermissionsWindow()
        let view = OnboardingView(permissions: self) { [weak self] in
            AppServices.shared.settings.hasCompletedOnboarding = true
            AppDelegate.shared?.lifecycleRegisterHotkeysAfterOnboarding()
            self?.onboardingWindow?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenForge"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Bring welcome above any leftover capture UI after relaunch.
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    /// Compact Screen Recording panel (post-onboarding / menu check).
    func presentPermissionsGate() {
        // Never displace the first-run wizard — PasteRush keeps onboarding until finish.
        if !AppServices.shared.settings.hasCompletedOnboarding {
            presentOnboarding()
            return
        }
        if let existing = permissionsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        closeOnboardingWindow()
        let view = PermissionsGateView(permissions: self) { [weak self] in
            self?.permissionsWindow?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenForge"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 360))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            onboardingWindow = nil
        }
        if window === permissionsWindow {
            permissionsWindow = nil
        }
    }

    func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func closeOnboardingWindow() {
        onboardingWindow?.delegate = nil
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func closePermissionsWindow() {
        permissionsWindow?.delegate = nil
        permissionsWindow?.close()
        permissionsWindow = nil
    }
}
