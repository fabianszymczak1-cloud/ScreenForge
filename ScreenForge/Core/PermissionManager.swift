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
        "app.screenforge.studio",
        "app.screenforge.bar",
        "app.screenforge.capture",
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
    /// Auto-heal clears a real grant too, so it may run only once per launch.
    private var didAutoHealTCCThisLaunch = false

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
    func refreshAsync(probeCapture: Bool = false, silent: Bool = false) async -> Bool {
        if !silent {
            isRefreshing = true
        }
        defer { if !silent { isRefreshing = false } }
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
        if probeCapture, !granted, await Self.grantVisibleToFreshProcess() {
            // Granted while we were running: only a new process can act on it.
            DiagnosticLog.shared.info("screen.permission.grantedButProcessIsStale")
            screenRecordingNeedsRelaunch = true
            hasScreenRecording = false
            return false
        }
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

    /// Ad-hoc signing pins the TCC identity to a CDHash, so every build looks like a new app.
    /// A leftover row for this bundle ID makes macOS treat the decision as already made:
    /// `CGRequestScreenCaptureAccess()` returns false without ever showing the system sheet.
    /// That dead row must be cleared before asking again.
    static func shouldAutoHealTCC(
        requestResult: Bool,
        preflightAfterRequest: Bool,
        alreadyHealedThisLaunch: Bool
    ) -> Bool {
        !requestResult && !preflightAfterRequest && !alreadyHealedThisLaunch
    }

    func requestScreenRecording() {
        // Resume welcome on Screen Recording step after macOS force-quits on grant.
        markRestoreOnboardingAfterTCC(resumeStep: 1)
        Task { await performScreenRecordingRequest() }
    }

    private func performScreenRecordingRequest() async {
        // Do not call SCShareableContent here — it races the system sheet / TCC quit.
        // Do not auto-open Settings — that steals focus from the sheet and pushes users to “+”.
        let prompted = CGRequestScreenCaptureAccess()
        DiagnosticLog.shared.info("screen.permission.requestCG result=\(prompted)")

        // A displayed sheet also returns false, and it stays up until answered. Wait it out
        // before concluding that macOS never showed one — resetting TCC under a live sheet
        // would tear down the very prompt the user is about to accept.
        if await pollForScreenRecording(seconds: 30) { return }

        guard Self.shouldAutoHealTCC(
            requestResult: prompted,
            preflightAfterRequest: CGPreflightScreenCaptureAccess(),
            alreadyHealedThisLaunch: didAutoHealTCCThisLaunch
        ) else {
            DiagnosticLog.shared.info("screen.permission.requestCG.stillDenied afterPoll")
            return
        }

        didAutoHealTCCThisLaunch = true
        DiagnosticLog.shared.info("screen.permission.autoheal.reset")
        resetScreenRecordingTCCEntries()
        let reRequested = CGRequestScreenCaptureAccess()
        DiagnosticLog.shared.info("screen.permission.autoheal.reRequest result=\(reRequested)")

        if await pollForScreenRecording(seconds: 60) { return }
        DiagnosticLog.shared.info("screen.permission.requestCG.stillDenied afterAutoHeal")
    }

    private func pollForScreenRecording(seconds: Int) async -> Bool {
        for attempt in 1...(seconds * 2) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Silent: a spinner toggling twice a second reads as a hang, not as progress.
            if await refreshAsync(probeCapture: false, silent: true) {
                DiagnosticLog.shared.info("screen.permission.requestCG.granted attempt=\(attempt)")
                return true
            }
            guard attempt % 4 == 0, await Self.grantVisibleToFreshProcess() else { continue }
            DiagnosticLog.shared.info("screen.permission.grantedButProcessIsStale restarting")
            screenRecordingNeedsRelaunch = true
            restartApp()
            return true
        }
        return false
    }

    /// The TCC answer is decided once per process: after a denial at launch,
    /// `CGPreflightScreenCaptureAccess()` keeps returning false here no matter what the user
    /// grants afterwards. A short-lived child of this app asks again under the same identity,
    /// which is the only way to notice the grant without quitting first.
    static func grantVisibleToFreshProcess() async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = [Self.preflightProbeArgument]
        do {
            try process.run()
        } catch {
            DiagnosticLog.shared.warn("screen.permission.freshProcess.failed \(error.localizedDescription)")
            return false
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    static let preflightProbeArgument = "--preflight-screen-recording"

    /// Clears Screen Recording TCC for current + legacy bundle IDs.
    /// Manual fallback — after reset, Settings “+” will not re-add the app; use Request permission.
    func resetStaleScreenRecordingGrants() {
        markRestoreOnboardingAfterTCC()
        resetScreenRecordingTCCEntries()
        hasScreenRecording = false
        screenRecordingNeedsRelaunch = false
        // Do not open Settings after reset — next step is Request permission (system sheet), not “+”.
        DiagnosticLog.shared.info("screen.permission.tccutil.done tapRequestNext")
    }

    private func resetScreenRecordingTCCEntries() {
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
            // Stay .accessory (PasteRush) — flipping Regular↔Accessory hides the status item on Tahoe.
            NSApp.activate(ignoringOtherApps: true)
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            clearRestoreOnboardingAfterTCC()
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
        window.setContentSize(NSSize(width: 520, height: 580))
        window.isReleasedWhenClosed = false
        window.delegate = self

        // PasteRush-style: titled window only — no floating / fullScreenAuxiliary.
        onboardingWindow = window
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        clearRestoreOnboardingAfterTCC()
        DiagnosticLog.shared.info("onboarding.presented resumeStep=\(UserDefaults.standard.integer(forKey: Self.onboardingResumeStepKey))")
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
