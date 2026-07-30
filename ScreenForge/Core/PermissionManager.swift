import Foundation
import AppKit
import SwiftUI

@MainActor
final class PermissionManager: NSObject, ObservableObject, NSWindowDelegate {
    static let restoreOnboardingAfterTCCKey = "sf.restoreOnboardingAfterTCC"
    static let onboardingResumeStepKey = "sf.onboardingResumeStep"

    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isRefreshing = false
    private var onboardingWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    /// Persist before TCC can force-quit the process (Screen Recording grant).
    func markRestoreOnboardingAfterTCC(resumeStep: Int? = nil) {
        let d = UserDefaults.standard
        d.set(true, forKey: Self.restoreOnboardingAfterTCCKey)
        AppServices.shared.settings.hasCompletedOnboarding = false
        if let resumeStep {
            d.set(resumeStep, forKey: Self.onboardingResumeStepKey)
        }
        d.synchronize()
    }

    func clearRestoreOnboardingAfterTCC() {
        UserDefaults.standard.removeObject(forKey: Self.restoreOnboardingAfterTCCKey)
    }

    static var shouldRestoreOnboardingAfterTCC: Bool {
        UserDefaults.standard.bool(forKey: restoreOnboardingAfterTCCKey)
            || UserDefaults.standard.object(forKey: onboardingResumeStepKey) != nil
    }

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
        markRestoreOnboardingAfterTCC()
        _ = CGRequestScreenCaptureAccess()
        Task { await refreshAsync() }
    }

    func openScreenRecordingSettings() {
        markRestoreOnboardingAfterTCC()
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
        // Ensure Control Center / Menu Bar allow-list can see this running agent.
        AppDelegate.shared?.reRegisterStatusItemForMenuBarAllowList()

        let urls = [
            "x-apple.systempreferences:com.apple.MenuBarSettings",
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

    func showOnboardingIfNeeded() {
        Task { @MainActor in
            guard !AppServices.shared.settings.hasCompletedOnboarding else { return }
            _ = await refreshAsync()
            presentOnboarding()
        }
    }

    func showPermissionsGateIfNeeded() {
        Task { @MainActor in
            let granted = await refreshAsync()
            guard !granted else { return }
            presentPermissionsGate()
        }
    }

    func openPermissionsPanel() {
        Task { @MainActor in
            _ = await refreshAsync()
            presentPermissionsGate()
        }
    }

    /// Full onboarding wizard (first launch, Settings, or restore after TCC kill).
    func presentOnboarding() {
        if let existing = onboardingWindow {
            NSApp.setActivationPolicy(.regular)
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            clearRestoreOnboardingAfterTCC()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.setActivationPolicy(.accessory)
            }
            return
        }
        closePermissionsWindow()
        let view = OnboardingView(permissions: self) { [weak self] in
            UserDefaults.standard.removeObject(forKey: Self.onboardingResumeStepKey)
            self?.clearRestoreOnboardingAfterTCC()
            AppServices.shared.settings.hasCompletedOnboarding = true
            AppDelegate.shared?.lifecycleRegisterHotkeysAfterOnboarding()
            self?.onboardingWindow?.close()
            NSApp.setActivationPolicy(.accessory)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ScreenForge"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        // Brief .regular so accessory/agent apps reliably surface the welcome window.
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
        clearRestoreOnboardingAfterTCC()
        DiagnosticLog.shared.info("onboarding.presented resumeStep=\(UserDefaults.standard.integer(forKey: Self.onboardingResumeStepKey))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Stay accessory while the window remains open (LSUIElement agent).
            NSApp.setActivationPolicy(.accessory)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func presentPermissionsGate() {
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
            NSApp.setActivationPolicy(.accessory)
        }
        if window === permissionsWindow {
            permissionsWindow = nil
        }
    }

    func restartApp() {
        markRestoreOnboardingAfterTCC()
        // Same binary only — jumping to /Applications can break TCC identity mid-grant.
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                DiagnosticLog.shared.error("restart.open.failed \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        }
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
