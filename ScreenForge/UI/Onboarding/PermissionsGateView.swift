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

            Button(String(localized: "Open Screen Recording settings")) {
                permissions.openScreenRecordingSettings()
            }
            Button(String(localized: "Check again")) {
                permissions.requestScreenRecording()
            }
            .disabled(permissions.isRefreshing)

            if permissions.hasScreenRecording {
                Text(String(localized: "If macOS requires restarting the app after granting permission, use the button below."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Relaunch ScreenForge")) {
                    permissions.restartApp()
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Close")) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 360)
        .task {
            await permissions.refreshAsync()
        }
    }
}
