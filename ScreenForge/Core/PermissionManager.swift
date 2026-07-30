import Foundation
import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isRefreshing = false
    private var onboardingWindow: NSWindow?

    func refresh() {
        let preflight = CGPreflightScreenCaptureAccess()
        hasAccessibility = AXIsProcessTrusted()
        if preflight {
            hasScreenRecording = true
            return
        }
        // Sync path: keep previous SC-probed true if we already know; otherwise start async probe
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let preflight = CGPreflightScreenCaptureAccess()
        hasAccessibility = AXIsProcessTrusted()
        if preflight {
            hasScreenRecording = true
            return
        }
        hasScreenRecording = await Self.canAccessShareableContent()
    }

    /// ScreenCaptureKit can succeed even when CGPreflight briefly reports false (TCC lag / binary path).
    nonisolated private static func canAccessShareableContent() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
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

    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        Task { await refreshAsync() }
    }

    /// - Parameter force: show even if onboarding already completed (e.g. menu “Sprawdź uprawnienia”).
    func showOnboardingIfNeeded(force: Bool) {
        Task { await refreshAsync() }
        if !force && AppServices.shared.settings.hasCompletedOnboarding {
            return
        }
        if onboardingWindow != nil { return }
        let view = OnboardingView(permissions: self) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            AppServices.shared.settings.hasCompletedOnboarding = true
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenForge"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
