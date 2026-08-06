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
                    menuBarStep
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
    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "The camera icon should appear in the menu bar automatically."))

            if AppDelegate.shared?.hasMenuBarSlot == false {
                Text(String(localized: "macOS is refusing the icon. Open Menu Bar settings and switch ScreenForge off and on again under “Allow in the Menu Bar”. If that changes nothing, the entry is broken on this Mac and only a new ScreenForge build with a fresh identity can fix it — the details are in the diagnostics log."))
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text(String(localized: "If it is missing, check System Settings → Menu Bar → Allow in the Menu Bar and make sure ScreenForge is on."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(String(localized: "Open Menu Bar settings")) {
                permissions.openMenuBarSettings()
            }
            Button(String(localized: "Register again in Menu Bar list")) {
                AppDelegate.shared?.reRegisterStatusItemForMenuBarAllowList()
                permissions.openMenuBarSettings()
            }
        }
    }

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

            Text(String(localized: "Use Request permission — macOS shows a system sheet. If Settings still lists ScreenForge from an older build, that dead entry is cleared automatically and the sheet is shown again. Do not add the app with +. macOS may quit the app — reopen and this screen returns."))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(String(localized: "Check again")) {
                Task { await permissions.refreshAsync(probeCapture: true) }
            }
            .disabled(permissions.isRefreshing)

            Button(String(localized: "Open Screen Recording settings")) {
                permissions.openScreenRecordingSettings()
            }

            Text(String(localized: "Settings is for review only. A row left by an older build cannot be fixed by toggling it off and on."))
                .font(.callout)
                .foregroundStyle(.secondary)

            if permissions.screenRecordingNeedsRelaunch {
                Text(String(localized: "macOS has the permission, but this instance started before it was granted and cannot use it. Relaunch to finish."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Relaunch ScreenForge")) {
                    settings.hasCompletedOnboarding = false
                    permissions.markRestoreOnboardingAfterTCC(resumeStep: step)
                    permissions.restartApp()
                }
            } else if !permissions.hasScreenRecording && !permissions.isRefreshing {
                DisclosureGroup(String(localized: "Still missing after Request permission?")) {
                    Text(String(localized: "Automatic repair runs once per launch. If this screen still says missing, clear stale grants manually and tap Request permission again (not +)."))
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
