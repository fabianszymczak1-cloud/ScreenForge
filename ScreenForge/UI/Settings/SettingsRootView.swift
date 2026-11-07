import SwiftUI
import AppKit
import Carbon.HIToolbox

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, capture, afterCapture, editor, files, history, privacy, permissions, advanced, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .shortcuts: return String(localized: "Shortcuts")
        case .capture: return String(localized: "Capture")
        case .afterCapture: return String(localized: "After capture")
        case .editor: return String(localized: "Editor")
        case .files: return String(localized: "Files")
        case .history: return String(localized: "History")
        case .privacy: return String(localized: "Privacy")
        case .permissions: return String(localized: "Permissions")
        case .advanced: return String(localized: "Advanced")
        case .about: return String(localized: "About")
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selected: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selected) { section in
                Text(section.title).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                Group {
                    switch selected {
                    case .general: GeneralSettingsView()
                    case .shortcuts: HotkeysSettingsView()
                    case .capture: CaptureSettingsView()
                    case .afterCapture: PostCaptureSettingsView()
                    case .editor: EditorSettingsView()
                    case .files: FilesSettingsView()
                    case .history: HistorySettingsView()
                    case .privacy: PrivacySettingsView()
                    case .permissions: PermissionsSettingsView()
                    case .advanced: AdvancedSettingsView()
                    case .about: AboutSettingsView()
                    }
                }
                .padding()
                .frame(maxWidth: 640, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var launchAtLogin = AppServices.shared.launchAtLogin

    var body: some View {
        Form {
            Toggle(String(localized: "Dock icon"), isOn: $settings.showDockIcon)
                .disabled(true)
            Text(String(localized: "Dock icon is unavailable while ScreenForge runs as a menu-bar app."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "Menu bar icon"), isOn: $settings.showMenuBarIcon)
            Toggle(String(localized: "Shutter sound"), isOn: $settings.playShutterSound)
            Toggle(String(localized: "Notifications"), isOn: $settings.showNotifications)
            Toggle(String(localized: "Check permissions on launch"), isOn: $settings.checkPermissionsOnLaunch)
            Picker(String(localized: "Appearance"), selection: $settings.theme) {
                Text(String(localized: "System")).tag(AppTheme.system)
                Text(String(localized: "Light")).tag(AppTheme.light)
                Text(String(localized: "Dark")).tag(AppTheme.dark)
            }
            Toggle(String(localized: "Launch at login"), isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    settings.launchAtLogin = newValue
                    _ = launchAtLogin.applyPreference(newValue)
                }
            ))
            if launchAtLogin.requiresApproval && settings.launchAtLogin {
                Text(String(localized: "macOS needs your approval for login items."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(String(localized: "Open Login Items settings")) {
                    launchAtLogin.openLoginItemsSettings()
                }
            }
            Button(String(localized: "Open onboarding")) {
                AppServices.shared.permissions.presentOnboarding()
            }
            Button(String(localized: "Restore defaults"), role: .destructive) {
                settings.resetDefaults()
            }
        }
    }
}

struct HotkeysSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        List {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    HotkeyRow(action: action)
                }
            } footer: {
                Text(String(localized: "Click a shortcut, then press the new combination with ⌃, ⌥ or ⌘. Esc cancels."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(String(localized: "Restore default shortcuts")) {
                    HotkeyRecorder.shared.stop()
                    settings.hotkeyBindings = HotkeyBinding.defaults
                    AppServices.shared.hotkeys.registerAll()
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 360)
        .onDisappear { HotkeyRecorder.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            HotkeyRecorder.shared.stop()
        }
    }
}

/// Captures the next key press for a shortcut row.
///
/// A local event monitor sees the key before SwiftUI, so recording does not depend on which view
/// holds keyboard focus. The global hotkeys are unregistered meanwhile, otherwise pressing an
/// existing combination would fire a capture instead of being recorded.
@MainActor
final class HotkeyRecorder: ObservableObject {
    static let shared = HotkeyRecorder()

    @Published private(set) var recordingAction: HotkeyAction?
    private var monitor: Any?

    func toggle(_ action: HotkeyAction) {
        if recordingAction == action { stop() } else { start(action) }
    }

    func start(_ action: HotkeyAction) {
        stop()
        recordingAction = action
        AppServices.shared.hotkeys.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recordingAction != nil else { return event }
            self.record(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard recordingAction != nil else { return }
        recordingAction = nil
        AppServices.shared.hotkeys.registerAll()
    }

    private func record(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = UInt32(event.keyCode)
        let modifiers = Self.carbonModifiers(flags)

        if keyCode == UInt32(kVK_Escape) && modifiers == 0 {
            stop()
            return
        }
        let commandish = modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
        guard commandish || HotkeyBinding.functionKeyCodes.contains(keyCode) else {
            NSSound.beep()
            return
        }

        let binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers, isEnabled: true)
        let settings = AppServices.shared.settings
        let conflicts = AppServices.shared.hotkeys.conflicts(for: binding, excluding: action)
        settings.hotkeyBindings[action.rawValue] = binding
        stop()
        if !conflicts.isEmpty {
            AppServices.shared.notifications.show(
                title: String(localized: "Shortcut conflict"),
                body: conflicts.map(\.title).joined(separator: ", ")
            )
        }
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

struct HotkeyRow: View {
    let action: HotkeyAction
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var recorder = HotkeyRecorder.shared

    private var isRecording: Bool { recorder.recordingAction == action }

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            Button {
                recorder.toggle(action)
            } label: {
                Text(isRecording
                     ? String(localized: "Type shortcut…")
                     : (settings.hotkeyBindings[action.rawValue]?.displayString ?? "—"))
                    .font(.body.monospaced())
                    .frame(minWidth: 96)
                    .padding(6)
                    .background(isRecording ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { settings.hotkeyBindings[action.rawValue]?.isEnabled ?? false },
                set: { enabled in
                    var b = settings.hotkeyBindings[action.rawValue] ?? HotkeyBinding(keyCode: 18, modifiers: 0, isEnabled: true)
                    b.isEnabled = enabled
                    settings.hotkeyBindings[action.rawValue] = b
                    AppServices.shared.hotkeys.registerAll()
                }
            ))
            .labelsHidden()
        }
    }
}

struct CaptureSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle(String(localized: "Include cursor"), isOn: $settings.captureCursor)
            Toggle(String(localized: "Magnifier while selecting"), isOn: $settings.showMagnifier)
            Slider(value: $settings.magnifierZoom, in: 4...16) { Text(String(localized: "Magnifier zoom")) }
            Slider(value: $settings.dimOpacity, in: 0.1...0.8) { Text(String(localized: "Dim")) }
            Toggle(String(localized: "Freeze displays"), isOn: $settings.freezeScreens)
            Toggle(String(localized: "Hide ScreenForge during capture"), isOn: $settings.hideSelfDuringCapture)
            Text(String(localized: "Turn off if you need to capture the ScreenForge editor or settings window."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(String(localized: "Show dimensions"), isOn: $settings.showDimensions)
            Toggle(String(localized: "Show coordinates"), isOn: $settings.showCoordinates)
            Toggle(String(localized: "Window shadow"), isOn: $settings.windowIncludeShadow)
            Text(String(localized: "Shadow adds transparent edges around the capture (checkerboard in the editor)."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: $settings.defaultDelaySeconds, in: 1...30) {
                Text(String(localized: "Default delay: \(settings.defaultDelaySeconds)s"))
            }
            Picker(String(localized: "Active display"), selection: $settings.activeDisplaySource) {
                Text(String(localized: "Cursor")).tag(ActiveDisplaySource.cursor)
                Text(String(localized: "Active window")).tag(ActiveDisplaySource.activeWindow)
            }
            Picker(String(localized: "All displays"), selection: $settings.allDisplaysMode) {
                Text(String(localized: "Combined image")).tag(AllDisplaysMode.combinedImage)
                Text(String(localized: "Separate files")).tag(AllDisplaysMode.separateFiles)
            }
        }
    }
}

struct PostCaptureSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            actionPicker(String(localized: "Region"), $settings.actionRegion)
            actionPicker(String(localized: "Window"), $settings.actionWindow)
            actionPicker(String(localized: "Display"), $settings.actionDisplay)
            actionPicker(String(localized: "All displays"), $settings.actionAllDisplays)
            Toggle(String(localized: "Copy PNG and TIFF"), isOn: $settings.copyPNGAndTIFF)
            Toggle(String(localized: "After copy, send ⌘V (requires Accessibility)"), isOn: $settings.autoPasteAfterCopy)
        }
    }

    func actionPicker(_ title: String, _ binding: Binding<PostCaptureAction>) -> some View {
        Picker(title, selection: binding) {
            ForEach(PostCaptureAction.allCases) { a in
                Text(a.title).tag(a)
            }
        }
    }
}

struct EditorSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle(String(localized: "Fit to window on open"), isOn: $settings.editorFitOnOpen)
            Toggle(String(localized: "Grid"), isOn: $settings.showGrid)
            Toggle(String(localized: "Snapping"), isOn: $settings.snappingEnabled)
            Stepper(value: $settings.undoLimit, in: 10...500) {
                Text(String(localized: "Undo limit: \(settings.undoLimit)"))
            }
            Toggle(String(localized: "Autosave"), isOn: $settings.autosaveEnabled)
            Toggle(String(localized: "Confirm closing unsaved"), isOn: $settings.confirmCloseUnsaved)
        }
    }
}

struct FilesSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            TextField(String(localized: "Save folder"), text: $settings.saveDirectoryPath)
            Button(String(localized: "Open export folder")) {
                AppServices.shared.files.openSaveDirectory()
            }
            TextField(String(localized: "Filename template"), text: $settings.filenameTemplate)
            Text(String(localized: "Preview: \(AppServices.shared.filenames.preview())"))
                .font(.caption).foregroundStyle(.secondary)
            Picker(String(localized: "Format"), selection: $settings.defaultImageFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
                Text("TIFF").tag("tiff")
                Text("HEIC").tag("heic")
                Text("PDF").tag("pdf")
            }
            Slider(value: $settings.jpegQuality, in: 0.1...1) { Text("JPEG") }
        }
    }
}

struct HistorySettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle(String(localized: "No limit"), isOn: $settings.historyUnlimited)
            Stepper(value: $settings.historyLimitCount, in: 10...2000) {
                Text(String(localized: "Count limit: \(settings.historyLimitCount)"))
            }
            Stepper(value: $settings.historyLimitDays, in: 1...365) {
                Text(String(localized: "Days limit: \(settings.historyLimitDays)"))
            }
        }
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Text(String(localized: "ScreenForge does not send data to the internet. No account, telemetry, or cloud."))
            Toggle(String(localized: "Remember app and window name"), isOn: $settings.storeSourceMetadata)
            Toggle(String(localized: "Strip metadata on export"), isOn: $settings.stripExportMetadata)
            Button(String(localized: "Support ScreenForge")) { TipPresenter.show() }
        }
    }
}

struct PermissionsSettingsView: View {
    var body: some View {
        Form {
            Button(String(localized: "Refresh status")) { AppServices.shared.permissions.refresh() }
            Button(String(localized: "Open Screen Recording")) { AppServices.shared.permissions.openScreenRecordingSettings() }
            Button(String(localized: "Open Accessibility (optional)")) { AppServices.shared.permissions.openAccessibilitySettings() }
            Button(String(localized: "Request Accessibility")) { AppServices.shared.permissions.requestAccessibility() }
        }
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle(String(localized: "Developer mode (timings)"), isOn: $settings.developerMode)
            Toggle(String(localized: "Experimental scrolling capture"), isOn: $settings.experimentalScrolling)
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenForge").font(.title.bold())
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                .foregroundStyle(.secondary)
            Text(String(localized: "A native screenshot tool for macOS. Fully local."))
            Button(String(localized: "Support ScreenForge")) { TipPresenter.show() }
            Link(String(localized: "GitHub"), destination: SupportLinks.githubRepo)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
