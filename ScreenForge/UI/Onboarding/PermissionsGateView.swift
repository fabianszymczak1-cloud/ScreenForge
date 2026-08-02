import SwiftUI

struct PermissionsGateView: View {
    @ObservedObject var permissions: PermissionManager
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ScreenForge").font(.largeTitle.bold())
            Text(String(localized: "Screen Recording is required to capture."))
                .foregroundStyle(.secondary)

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
                    permissions.markRestoreOnboardingAfterTCC()
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
                        permissions.markRestoreOnboardingAfterTCC()
                        permissions.restartApp()
                    }
                }
            }

            if permissions.hasScreenRecording {
                Text(String(localized: "Permission is on. Continue, or relaunch if capture still fails."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Close")) {
                    onClose()
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 500)
        .task {
            await permissions.refreshAsync(probeCapture: true)
        }
    }
}
