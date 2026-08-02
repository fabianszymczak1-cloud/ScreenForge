import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionManager
    @ObservedObject private var settings = AppServices.shared.settings
    @ObservedObject private var launchAtLogin = AppServices.shared.launchAtLogin
    var onFinish: () -> Void
    @State private var step = 0

    private let lastStep = 5

    init(permissions: PermissionManager, onFinish: @escaping () -> Void) {
        _permissions = ObservedObject(wrappedValue: permissions)
        self.onFinish = onFinish
        let resumed = UserDefaults.standard.integer(forKey: PermissionManager.onboardingResumeStepKey)
        _step = State(initialValue: max(0, min(resumed, 5)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ScreenForge").font(.largeTitle.bold())
            Group {
                switch step {
                case 0:
                    Text(String(localized: "ScreenForge stays fully local. Screenshots never leave your Mac."))
                case 1:
                    screenRecordingStep
                case 2:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Allow ScreenForge in Menu Bar so the camera icon stays visible."))
                        Text(String(localized: "In System Settings open Menu Bar, then scroll to “Allow in the Menu Bar” (Zezwalaj w pasku menu). ScreenForge appears only while the app is running."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Open Menu Bar settings")) {
                            permissions.openMenuBarSettings()
                        }
                        Button(String(localized: "Register again in Menu Bar list")) {
                            AppDelegate.shared?.reRegisterStatusItemForMenuBarAllowList()
                            permissions.openMenuBarSettings()
                        }
                        Text(String(localized: "If ScreenForge is still missing: quit ScreenForge completely, eject any ScreenForge DMG, open only /Applications/ScreenForge.app from Finder (not from Terminal or Cursor), then open Menu Bar settings again. You may also need Screen Recording again after a fresh install."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case 3:
                    Text(String(localized: "Region capture shortcut: ⌃⇧1 — select an area to open the editor."))
                case 4:
                    Text(String(localized: "Quick copy: ⌃⌥1 — select a region; the image goes straight to the clipboard."))
                default:
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(String(localized: "Launch at login"), isOn: launchAtLoginBinding)
                        Text(String(localized: "You can change this later in the menu."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if launchAtLogin.requiresApproval && settings.launchAtLogin {
                            Text(String(localized: "macOS needs your approval for login items."))
                                .font(.callout)
                                .foregroundStyle(.orange)
                            Button(String(localized: "Open Login Items settings")) {
                                launchAtLogin.openLoginItemsSettings()
                            }
                        }
                        if !permissions.hasScreenRecording {
                            Text(String(localized: "Note: without Screen Recording, captures will not work. You can go back and check permissions."))
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "If ScreenForge helps you, you can buy me a coffee."))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Link(destination: SupportLinks.buyMeACoffee) {
                                Text(String(localized: "Buy Me a Coffee"))
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if step > 0 {
                    Button(String(localized: "Back")) { step -= 1 }
                }
                Spacer()
                if step < lastStep {
                    Button(String(localized: "Continue")) {
                        Task { await permissions.refreshAsync() }
                        step += 1
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Get started")) {
                        if settings.launchAtLogin {
                            _ = launchAtLogin.applyPreference(true)
                        }
                        UserDefaults.standard.removeObject(forKey: PermissionManager.onboardingResumeStepKey)
                        permissions.clearRestoreOnboardingAfterTCC()
                        settings.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 580)
        .task {
            await permissions.refreshAsync(probeCapture: true)
            launchAtLogin.refresh()
        }
    }

    @ViewBuilder
    private var screenRecordingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Grant Screen Recording — required only to take screenshots."))
            HStack {
                Circle()
                    .fill(permissions.hasScreenRecording ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                if permissions.isRefreshing {
                    Text(String(localized: "Checking…"))
                } else {
                    Text(permissions.hasScreenRecording
                          ? String(localized: "Permission granted")
                          : String(localized: "Permission missing"))
                }
            }

            if !permissions.isCanonicalInstall {
                Text(String(localized: "This copy is not /Applications/ScreenForge.app. Quit, eject any ScreenForge DMG, and open only the app in Applications — otherwise Screen Recording will not stick."))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Button(String(localized: "Request permission")) {
                permissions.requestScreenRecording()
            }
            .disabled(permissions.isRefreshing)
            .keyboardShortcut(.defaultAction)

            Text(String(localized: "Use Request permission — macOS shows a system sheet. Do not add ScreenForge with the + button in Settings; that often does nothing. After you allow access, use Check again. macOS may quit the app — reopen and this screen returns."))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(String(localized: "Check again")) {
                Task { await permissions.refreshAsync(probeCapture: true) }
            }
            .disabled(permissions.isRefreshing)

            Button(String(localized: "Open Screen Recording settings")) {
                permissions.openScreenRecordingSettings()
            }

            Text(String(localized: "Settings is only to turn an existing ScreenForge row ON — not to add the app with +."))
                .font(.callout)
                .foregroundStyle(.secondary)

            if permissions.screenRecordingNeedsRelaunch {
                Text(String(localized: "Permission registered in this process, but capture needs a relaunch."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Relaunch ScreenForge")) {
                    settings.hasCompletedOnboarding = false
                    permissions.markRestoreOnboardingAfterTCC(resumeStep: step)
                    permissions.restartApp()
                }
            } else if !permissions.hasScreenRecording && !permissions.isRefreshing {
                DisclosureGroup(String(localized: "Still missing after Request permission?")) {
                    Text(String(localized: "If Settings already lists ScreenForge but this screen still says missing, that row is for an old install. Last resort: clear stale grants, then tap Request permission again (not +)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Button(String(localized: "Clear stale Screen Recording grants")) {
                        permissions.resetStaleScreenRecordingGrants()
                    }
                    Button(String(localized: "Relaunch ScreenForge")) {
                        settings.hasCompletedOnboarding = false
                        permissions.markRestoreOnboardingAfterTCC(resumeStep: step)
                        permissions.restartApp()
                    }
                }
            }

            if permissions.hasScreenRecording {
                Text(String(localized: "Permission is on. Continue, or relaunch if capture still fails."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                settings.launchAtLogin = newValue
                _ = launchAtLogin.applyPreference(newValue)
            }
        )
    }
}
