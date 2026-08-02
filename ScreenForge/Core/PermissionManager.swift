import Foundation
import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
final class PermissionManager: NSObject, ObservableObject, NSWindowDelegate {
    static let restoreOnboardingAfterTCCKey = "sf.restoreOnboardingAfterTCC"
    static let onboardingResumeStepKey = "sf.onboardingResumeStep"
    static let canonicalInstallPath = "/Applications/ScreenForge.app"

    /// Bundle IDs used by older ScreenForge builds — stale TCC rows can linger under these.
    static let legacyScreenCaptureBundleIDs = [
        "app.screenforge.macos",
        "com.local.ScreenForge"
    ]

    @Published private(set) var hasScreenRecording = false
    /// Preflight true in this process, but ScreenCaptureKit still needs a fresh process.
    @Published private(set) var screenRecordingNeedsRelaunch = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isRefreshing = false
    /// False when running from a DMG, DerivedData, or any path other than /Applications.
    @Published private(set) var isCanonicalInstall = true
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
        isCanonicalInstall = (Bundle.main.bundlePath as NSString).standardizingPath == Self.canonicalInstallPath

        // CGPreflight is the process-truth for this binary's code identity.
        // System Settings can still show an ON row for a *previous* CDHash / path under the
        // same display name — that is not a preflight false-negative.
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
        if probeCapture && granted {
            // Only touch ScreenCaptureKit when preflight already passed. Probing while
            // denied re-triggers the system TCC sheet and does not fix a stale Settings row.
            let probe = await Self.probeScreenCaptureAccess()
            if !probe {
                needsRelaunch = true
                granted = false
            }
            DiagnosticLog.shared.info(
                "screen.permission preflight=true probe=\(probe) granted=\(granted) needsRelaunch=\(needsRelaunch) path=\(Bundle.main.bundlePath)"
            )
        } else {
            DiagnosticLog.shared.info(
                "screen.permission preflight=\(granted) probeSkipped=\(probeCapture && !granted) path=\(Bundle.main.bundlePath) canonical=\(isCanonicalInstall)"
            )
        }

        screenRecordingNeedsRelaunch = needsRelaunch
        hasScreenRecording = granted
        return granted
    }

    /// Actual capture capability — may prompt if never asked. Avoid unless preflight is true.
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
        // Do not call SCShareableContent here — it races the system sheet / TCC quit.
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let granted = await refreshAsync(probeCapture: false)
            // If the sheet did not grant yet, open Settings only as a place to flip an
            // existing row ON — do not rely on the Settings “+” picker (unreliable on Tahoe).
            if !granted {
                openScreenRecordingSettingsForReview()
            }
        }
    }

    /// Clears Screen Recording TCC for current + legacy bundle IDs, then opens Settings.
    /// Last resort only — after reset, Settings “+” will not re-add the app; use Request permission.
    func resetStaleScreenRecordingGrants() {
        markRestoreOnboardingAfterTCC()
        var ids = Self.legacyScreenCaptureBundleIDs
        if let current = Bundle.main.bundleIdentifier {
            ids.insert(current, at: 0)
        }
        for id in ids {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", "ScreenCapture", id]
            do {
                try proc.run()
                proc.waitUntilExit()
                DiagnosticLog.shared.info("screen.permission.tccutil.reset id=\(id) status=\(proc.terminationStatus)")
            } catch {
                DiagnosticLog.shared.warn("screen.permission.tccutil.failed id=\(id) \(error.localizedDescription)")
            }
        }
        hasScreenRecording = false
        screenRecordingNeedsRelaunch = false
        openScreenRecordingSettingsForReview()
    }

    func openScreenRecordingSettings() {
        markRestoreOnboardingAfterTCC()
        openScreenRecordingSettingsForReview()
    }

    /// Opens Privacy → Screen Recording for review/toggle. Adding via “+” is unreliable.
    private func openScreenRecordingSettingsForReview() {
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
        window.setContentSize(NSSize(width: 520, height: 560))
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
        window.setContentSize(NSSize(width: 520, height: 460))
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
