import SwiftUI
import Carbon.HIToolbox

struct SettingsRootView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            HotkeysSettingsView().tabItem { Label(String(localized: "Shortcuts"), systemImage: "keyboard") }
            CaptureSettingsView().tabItem { Label(String(localized: "Capture"), systemImage: "camera") }
            PostCaptureSettingsView().tabItem { Label(String(localized: "After capture"), systemImage: "arrow.right.circle") }
            EditorSettingsView().tabItem { Label(String(localized: "Editor"), systemImage: "paintbrush") }
            FilesSettingsView().tabItem { Label(String(localized: "Files"), systemImage: "folder") }
            HistorySettingsView().tabItem { Label(String(localized: "History"), systemImage: "clock") }
            PrivacySettingsView().tabItem { Label(String(localized: "Privacy"), systemImage: "lock") }
            PermissionsSettingsView().tabItem { Label(String(localized: "Permissions"), systemImage: "checkmark.shield") }
            AdvancedSettingsView().tabItem { Label(String(localized: "Advanced"), systemImage: "wrench") }
            AboutSettingsView().tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launch = false
    var body: some View {
        Form {
            Toggle(String(localized: "Dock icon"), isOn: $settings.showDockIcon)
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
                get: { AppServices.shared.launchAtLogin.isEnabled },
                set: { try? AppServices.shared.launchAtLogin.setEnabled($0) }
            ))
            Button(String(localized: "Open onboarding")) {
                AppServices.shared.permissions.showOnboardingIfNeeded(force: true)
            }
            Button(String(localized: "Restore defaults"), role: .destructive) {
                settings.resetDefaults()
            }
        }
        .padding()
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
            }
            Section {
                Button(String(localized: "Restore default shortcuts")) {
                    settings.hotkeyBindings = HotkeyBinding.defaults
                    AppServices.shared.hotkeys.registerAll()
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct HotkeyRow: View {
    let action: HotkeyAction
    @EnvironmentObject var settings: SettingsStore
    @State private var recording = false

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            let binding = settings.hotkeyBindings[action.rawValue]
            Text(binding?.displayString ?? "—")
                .font(.body.monospaced())
                .padding(6)
                .background(recording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .onTapGesture { recording = true }
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
        .focusable()
        .onKeyPress { press in
            guard recording else { return .ignored }
            var mods: UInt32 = 0
            if press.modifiers.contains(.control) { mods |= UInt32(controlKey) }
            if press.modifiers.contains(.option) { mods |= UInt32(optionKey) }
            if press.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
            if press.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
            // Approximate keycode from character
            let keyCode = Self.keyCode(for: press.key)
            let newBinding = HotkeyBinding(keyCode: keyCode, modifiers: mods, isEnabled: true)
            let conflicts = AppServices.shared.hotkeys.conflicts(for: newBinding, excluding: action)
            settings.hotkeyBindings[action.rawValue] = newBinding
            AppServices.shared.hotkeys.registerAll()
            recording = false
            if !conflicts.isEmpty {
                AppServices.shared.notifications.show(
                    title: String(localized: "Shortcut conflict"),
                    body: conflicts.map(\.title).joined(separator: ", ")
                )
            }
            return .handled
        }
    }

    static func keyCode(for key: KeyEquivalent) -> UInt32 {
        let map: [String: UInt32] = [
            "1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,"0":29
        ]
        return map[key.character.lowercased()] ?? 18
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
        }.padding()
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
        }.padding()
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
        }.padding()
    }
}

struct FilesSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            TextField(String(localized: "Save folder"), text: $settings.saveDirectoryPath)
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
        }.padding()
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
        }.padding()
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Text(String(localized: "ScreenForge does not send data to the internet. No account, telemetry, or cloud."))
            Toggle(String(localized: "Remember app and window name"), isOn: $settings.storeSourceMetadata)
            Toggle(String(localized: "Strip metadata on export"), isOn: $settings.stripExportMetadata)
        }.padding()
    }
}

struct PermissionsSettingsView: View {
    var body: some View {
        Form {
            Button(String(localized: "Refresh status")) { AppServices.shared.permissions.refresh() }
            Button(String(localized: "Open Screen Recording")) { AppServices.shared.permissions.openScreenRecordingSettings() }
            Button(String(localized: "Open Accessibility (optional)")) { AppServices.shared.permissions.openAccessibilitySettings() }
            Button(String(localized: "Request Accessibility")) { AppServices.shared.permissions.requestAccessibility() }
        }.padding()
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Toggle(String(localized: "Developer mode (timings)"), isOn: $settings.developerMode)
            Toggle(String(localized: "Experimental scrolling capture"), isOn: $settings.experimentalScrolling)
        }.padding()
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ScreenForge").font(.title.bold())
            Text("1.0.0")
            Text(String(localized: "A native screenshot tool for macOS. Fully local."))
            Text("© lokalny projekt")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
