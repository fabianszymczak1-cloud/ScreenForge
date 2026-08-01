import Foundation
import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
final class PermissionManager: NSObject, ObservableObject, NSWindowDelegate {
    static let restoreOnboardingAfterTCCKey = "sf.restoreOnboardingAfterTCC"
    static let onboardingResumeStepKey = "sf.onboardingResumeStep"

    @Published private(set) var hasScreenRecording = false
    /// Preflight/settings look granted, but ScreenCaptureKit still needs a fresh process.
    @Published private(set) var screenRecordingNeedsRelaunch = false
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
    func refreshAsync(probeCapture: Bool = false) async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }
        hasAccessibility = AXIsProcessTrusted()

        // CGPreflight alone is unreliable on Tahoe (especially with ad-hoc signing /
        // rebuilt cdhashes): System Settings can show ON while preflight stays false.
        // Keep preflight-only for silent launch checks; user-facing "Check again" probes
        // ScreenCaptureKit for the real capability.
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

        var needsRelaunch = false
        if probeCapture {
            let probe = await Self.probeScreenCaptureAccess()
            if probe {
                granted = true
                needsRelaunch = false
            } else if granted {
                // Preflight flipped on in this process — SCK often needs a relaunch.
                needsRelaunch = true
                granted = false
            } else {
                needsRelaunch = false
            }
            DiagnosticLog.shared.info(
                "screen.permission preflight=\(CGPreflightScreenCaptureAccess()) probe=\(probe) granted=\(granted) needsRelaunch=\(needsRelaunch)"
            )
        }

        screenRecordingNeedsRelaunch = needsRelaunch
        hasScreenRecording = granted
        return granted
    }

    /// Actual capture capability — may prompt if never asked. Avoid on cold launch.
    private static func probeScreenCaptureAccess() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            DiagnosticLog.shared.warn("screen.permission.probe.failed \(error.localizedDescription)")
            return false
        }
    }

    func requestScreenRecording() {
        markRestoreOnboardingAfterTCC()
        _ = CGRequestScreenCaptureAccess()
        Task { await refreshAsync(probeCapture: true) }
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
        // Keep a stable status item visible; do not recreate on every Settings open.
        AppServices.shared.settings.showMenuBarIcon = true
        AppDelegate.shared?.applyMenuBarIconPreference()
        NSApp.setActivationPolicy(.accessory)

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
        window.setContentSize(NSSize(width: 520, height: 540))
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
        window.setContentSize(NSSize(width: 520, height: 420))
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
