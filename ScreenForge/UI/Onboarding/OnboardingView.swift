import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionManager
    var onFinish: () -> Void
    @State private var step = 0
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ScreenForge").font(.largeTitle.bold())
            Group {
                switch step {
                case 0:
                    Text(String(localized: "ScreenForge stays fully local. Screenshots never leave your Mac."))
                case 1:
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
                        Button(String(localized: "Open Screen Recording settings")) {
                            permissions.openScreenRecordingSettings()
                        }
                        Button(String(localized: "Check again")) {
                            permissions.requestScreenRecording()
                        }
                        .disabled(permissions.isRefreshing)
                        if permissions.hasScreenRecording {
                            Text(String(localized: "If macOS requires restarting the app after granting permission, use the button below."))
                            Button(String(localized: "Relaunch ScreenForge")) {
                                permissions.restartApp()
                            }
                        }
                    }
                case 2:
                    Text(String(localized: "Region capture shortcut: ⌃⇧1 — select an area to open the editor."))
                case 3:
                    Text(String(localized: "Quick copy: ⌃⌥1 — select a region; the image goes straight to the clipboard."))
                default:
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                        Text(String(localized: "You can change this later in the menu."))
                        if !permissions.hasScreenRecording {
                            Text(String(localized: "Note: without Screen Recording, captures will not work. You can go back and check permissions."))
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                        Link(String(localized: "Buy Me a Coffee"), destination: SupportLinks.buyMeACoffee)
                            .font(.caption.weight(.semibold))
                        Text(String(localized: "If ScreenForge helps you, you can buy me a coffee."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if step > 0 {
                    Button(String(localized: "Back")) { step -= 1 }
                }
                Spacer()
                if step < 4 {
                    Button(String(localized: "Continue")) {
                        Task { await permissions.refreshAsync() }
                        step += 1
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "Get started")) {
                        if launchAtLogin {
                            try? AppServices.shared.launchAtLogin.setEnabled(true)
                        }
                        AppServices.shared.settings.hasCompletedOnboarding = true
                        // Close only — do NOT start a capture (that re-opened onboarding in a loop).
                        onFinish()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 400)
        .task { await permissions.refreshAsync() }
    }
}
