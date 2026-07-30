import Foundation
import AppKit
import SwiftUI

enum PostCaptureAction: String, CaseIterable, Codable, Identifiable {
    case openEditor, copyClipboard, saveAuto, showActionMenu, copyAndSave, copyAndEdit, saveAndNotify, share
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openEditor: return String(localized: "Open in editor")
        case .copyClipboard: return String(localized: "Copy to clipboard")
        case .saveAuto: return String(localized: "Save automatically")
        case .showActionMenu: return String(localized: "Show action menu")
        case .copyAndSave: return String(localized: "Copy and save")
        case .copyAndEdit: return String(localized: "Copy and open editor")
        case .saveAndNotify: return String(localized: "Save and notify")
        case .share: return String(localized: "Share")
        }
    }
}

enum AllDisplaysMode: String, Codable, CaseIterable {
    case separateFiles, combinedImage
}

enum ActiveDisplaySource: String, Codable, CaseIterable {
    case cursor, activeWindow
}

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark
}

enum AppLanguage: String, Codable, CaseIterable {
    case system, pl, en
}

@MainActor
final class SettingsStore: ObservableObject {
    private let d = UserDefaults.standard
    private let prefix = "sf."

    @Published var hasCompletedOnboarding: Bool {
        didSet { d.set(hasCompletedOnboarding, forKey: prefix + "onboarding") }
    }
    @Published var showDockIcon: Bool {
        didSet {
            d.set(showDockIcon, forKey: prefix + "dock")
            // Keep .accessory while LSUIElement is set. Do not flip Regular↔Accessory.
            applyActivationPolicy()
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet {
            d.set(showMenuBarIcon, forKey: prefix + "menubar")
            AppDelegate.shared?.applyMenuBarIconPreference()
        }
    }
    /// Desired launch-at-login preference (persisted). Actual SMAppService state may lag
    /// until the user approves Login Items in System Settings.
    @Published var launchAtLogin: Bool {
        didSet { d.set(launchAtLogin, forKey: prefix + "launchAtLogin") }
    }
    @Published var theme: AppTheme {
        didSet { d.set(theme.rawValue, forKey: prefix + "theme") }
    }
    @Published var language: AppLanguage {
        didSet { d.set(language.rawValue, forKey: prefix + "lang") }
    }
    @Published var playShutterSound: Bool {
        didSet { d.set(playShutterSound, forKey: prefix + "sound") }
    }
    @Published var showNotifications: Bool {
        didSet { d.set(showNotifications, forKey: prefix + "notif") }
    }
    @Published var checkPermissionsOnLaunch: Bool {
        didSet { d.set(checkPermissionsOnLaunch, forKey: prefix + "permCheck") }
    }
    @Published var captureCursor: Bool {
        didSet { d.set(captureCursor, forKey: prefix + "cursor") }
    }
    @Published var showMagnifier: Bool {
        didSet { d.set(showMagnifier, forKey: prefix + "magnifier") }
    }
    @Published var magnifierZoom: Double {
        didSet { d.set(magnifierZoom, forKey: prefix + "magZoom") }
    }
    @Published var selectionBorderColor: String {
        didSet { d.set(selectionBorderColor, forKey: prefix + "selColor") }
    }
    @Published var dimOpacity: Double {
        didSet { d.set(dimOpacity, forKey: prefix + "dim") }
    }
    @Published var freezeScreens: Bool {
        didSet { d.set(freezeScreens, forKey: prefix + "freeze") }
    }
    /// When true, ScreenForge windows are omitted from captures (cleaner shots of other apps).
    @Published var hideSelfDuringCapture: Bool {
        didSet { d.set(hideSelfDuringCapture, forKey: prefix + "hideSelf") }
    }
    @Published var showDimensions: Bool {
        didSet { d.set(showDimensions, forKey: prefix + "dims") }
    }
    @Published var showCoordinates: Bool {
        didSet { d.set(showCoordinates, forKey: prefix + "coords") }
    }
    @Published var windowIncludeShadow: Bool {
        didSet { d.set(windowIncludeShadow, forKey: prefix + "winShadow") }
    }
    @Published var windowMargin: Double {
        didSet { d.set(windowMargin, forKey: prefix + "winMargin") }
    }
    @Published var defaultDelaySeconds: Int {
        didSet { d.set(defaultDelaySeconds, forKey: prefix + "delay") }
    }
    @Published var activeDisplaySource: ActiveDisplaySource {
        didSet { d.set(activeDisplaySource.rawValue, forKey: prefix + "activeDisp") }
    }
    @Published var allDisplaysMode: AllDisplaysMode {
        didSet { d.set(allDisplaysMode.rawValue, forKey: prefix + "allMode") }
    }
    @Published var saveDirectoryPath: String {
        didSet { d.set(saveDirectoryPath, forKey: prefix + "saveDir") }
    }
    @Published var filenameTemplate: String {
        didSet { d.set(filenameTemplate, forKey: prefix + "fileTpl") }
    }
    @Published var defaultImageFormat: String {
        didSet { d.set(defaultImageFormat, forKey: prefix + "fmt") }
    }
    @Published var jpegQuality: Double {
        didSet { d.set(jpegQuality, forKey: prefix + "jpegQ") }
    }
    @Published var historyLimitCount: Int {
        didSet { d.set(historyLimitCount, forKey: prefix + "histCount") }
    }
    @Published var historyLimitDays: Int {
        didSet { d.set(historyLimitDays, forKey: prefix + "histDays") }
    }
    @Published var historyUnlimited: Bool {
        didSet { d.set(historyUnlimited, forKey: prefix + "histUnlim") }
    }
    @Published var storeSourceMetadata: Bool {
        didSet { d.set(storeSourceMetadata, forKey: prefix + "meta") }
    }
    @Published var stripExportMetadata: Bool {
        didSet { d.set(stripExportMetadata, forKey: prefix + "stripMeta") }
    }
    @Published var autoPasteAfterCopy: Bool {
        didSet { d.set(autoPasteAfterCopy, forKey: prefix + "autoPaste") }
    }
    @Published var copyPNGAndTIFF: Bool {
        didSet { d.set(copyPNGAndTIFF, forKey: prefix + "copyBoth") }
    }
    @Published var editorFitOnOpen: Bool {
        didSet { d.set(editorFitOnOpen, forKey: prefix + "fit") }
    }
    @Published var showGrid: Bool {
        didSet { d.set(showGrid, forKey: prefix + "grid") }
    }
    @Published var snappingEnabled: Bool {
        didSet { d.set(snappingEnabled, forKey: prefix + "snap") }
    }
    @Published var undoLimit: Int {
        didSet { d.set(undoLimit, forKey: prefix + "undo") }
    }
    @Published var autosaveEnabled: Bool {
        didSet { d.set(autosaveEnabled, forKey: prefix + "autosave") }
    }
    @Published var confirmCloseUnsaved: Bool {
        didSet { d.set(confirmCloseUnsaved, forKey: prefix + "confirmClose") }
    }
    @Published var experimentalScrolling: Bool {
        didSet { d.set(experimentalScrolling, forKey: prefix + "scrollCap") }
    }
    @Published var developerMode: Bool {
        didSet {
            d.set(developerMode, forKey: prefix + "dev")
            PerformanceMonitor.shared.isEnabled = developerMode
        }
    }

    // Per-mode default actions
    @Published var actionRegion: PostCaptureAction {
        didSet { d.set(actionRegion.rawValue, forKey: prefix + "act.region") }
    }
    @Published var actionWindow: PostCaptureAction {
        didSet { d.set(actionWindow.rawValue, forKey: prefix + "act.window") }
    }
    @Published var actionDisplay: PostCaptureAction {
        didSet { d.set(actionDisplay.rawValue, forKey: prefix + "act.display") }
    }
    @Published var actionAllDisplays: PostCaptureAction {
        didSet { d.set(actionAllDisplays.rawValue, forKey: prefix + "act.all") }
    }

    // Hotkey storage as dictionary of keyCode+modifiers
    @Published var hotkeyBindings: [String: HotkeyBinding] {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeyBindings) {
                d.set(data, forKey: prefix + "hotkeys")
            }
        }
    }

    init() {
        Self.migrateLegacyPreferencesIfNeeded()

        let defaults = UserDefaults.standard
        let p = "sf."
        func b(_ k: String, _ def: Bool) -> Bool { defaults.object(forKey: p + k) as? Bool ?? def }
        func i(_ k: String, _ def: Int) -> Int { defaults.object(forKey: p + k) as? Int ?? def }
        func dbl(_ k: String, _ def: Double) -> Double { defaults.object(forKey: p + k) as? Double ?? def }
        func s(_ k: String, _ def: String) -> String { defaults.string(forKey: p + k) ?? def }

        hasCompletedOnboarding = b("onboarding", false)
        // LSUIElement app — never leave a persisted dock preference from docs/tools.
        showDockIcon = false
        d.set(false, forKey: p + "dock")
        showMenuBarIcon = b("menubar", true)
        launchAtLogin = b("launchAtLogin", false)
        theme = AppTheme(rawValue: s("theme", "system")) ?? .system
        language = AppLanguage(rawValue: s("lang", "system")) ?? .system
        playShutterSound = b("sound", false)
        showNotifications = b("notif", true)
        checkPermissionsOnLaunch = b("permCheck", true)
        captureCursor = b("cursor", false)
        showMagnifier = b("magnifier", true)
        magnifierZoom = dbl("magZoom", 8)
        selectionBorderColor = s("selColor", "#00C7BE")
        dimOpacity = dbl("dim", 0.45)
        freezeScreens = b("freeze", true)
        hideSelfDuringCapture = b("hideSelf", true)
        showDimensions = b("dims", true)
        showCoordinates = b("coords", true)
        windowIncludeShadow = b("winShadow", false)
        windowMargin = dbl("winMargin", 0)
        defaultDelaySeconds = i("delay", 3)
        activeDisplaySource = ActiveDisplaySource(rawValue: s("activeDisp", "cursor")) ?? .cursor
        allDisplaysMode = AllDisplaysMode(rawValue: s("allMode", "combinedImage")) ?? .combinedImage
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        saveDirectoryPath = s("saveDir", pictures.appendingPathComponent("ScreenForge").path)
        filenameTemplate = s("fileTpl", "Screenshot_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}_{app}_{counter}.png")
        defaultImageFormat = s("fmt", "png")
        jpegQuality = dbl("jpegQ", 0.9)
        historyLimitCount = i("histCount", 200)
        historyLimitDays = i("histDays", 30)
        historyUnlimited = b("histUnlim", false)
        storeSourceMetadata = b("meta", true)
        stripExportMetadata = b("stripMeta", false)
        autoPasteAfterCopy = b("autoPaste", false)
        copyPNGAndTIFF = b("copyBoth", true)
        editorFitOnOpen = b("fit", true)
        showGrid = b("grid", false)
        snappingEnabled = b("snap", true)
        undoLimit = i("undo", 100)
        autosaveEnabled = b("autosave", true)
        confirmCloseUnsaved = b("confirmClose", true)
        experimentalScrolling = b("scrollCap", false)
        developerMode = b("dev", false)
        actionRegion = PostCaptureAction(rawValue: s("act.region", "openEditor")) ?? .openEditor
        actionWindow = PostCaptureAction(rawValue: s("act.window", "openEditor")) ?? .openEditor
        actionDisplay = PostCaptureAction(rawValue: s("act.display", "openEditor")) ?? .openEditor
        actionAllDisplays = PostCaptureAction(rawValue: s("act.all", "openEditor")) ?? .openEditor

        if let data = defaults.data(forKey: p + "hotkeys"),
           let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) {
            hotkeyBindings = decoded
        } else {
            hotkeyBindings = HotkeyBinding.defaults
        }
        PerformanceMonitor.shared.isEnabled = developerMode
    }

    /// Copy `sf.*` keys from older bundle IDs (Tahoe Control Center can poison an ID).
    private static func migrateLegacyPreferencesIfNeeded() {
        let current = UserDefaults.standard
        if current.object(forKey: "sf.prefsMigratedToAppScreenforge") as? Bool == true { return }
        let needsSeed = current.object(forKey: "sf.onboarding") == nil
        let legacyIDs = ["com.screenforge.macos", "com.screenforge.app", "com.local.ScreenForge"]
        // Never import onboarding completion — a fresh/reinstalled identity must see welcome.
        let skipKeys: Set<String> = [
            "sf.onboarding",
            "sf.onboardingResumeStep",
            "sf.prefsMigratedToAppScreenforge"
        ]
        if needsSeed {
            for id in legacyIDs {
                guard let legacy = UserDefaults(suiteName: id) else { continue }
                let dict = legacy.dictionaryRepresentation()
                var copied = false
                for (key, value) in dict where key.hasPrefix("sf.") && !skipKeys.contains(key) {
                    current.set(value, forKey: key)
                    copied = true
                }
                if copied { break }
            }
        }
        current.set(true, forKey: "sf.prefsMigratedToAppScreenforge")
    }

    /// Safe to call before NSApp exists (no-op). Always accessory with LSUIElement.
    func applyActivationPolicy() {
        guard NSApp != nil else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func resetDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        d.removePersistentDomain(forName: domain)
        hotkeyBindings = HotkeyBinding.defaults
        hasCompletedOnboarding = false
    }

    func defaultAction(for kind: CaptureKind) -> PostCaptureAction {
        switch kind {
        case .region, .lastRegion: return actionRegion
        case .window: return actionWindow
        case .fullDisplay: return actionDisplay
        case .allDisplays: return actionAllDisplays
        }
    }
}
