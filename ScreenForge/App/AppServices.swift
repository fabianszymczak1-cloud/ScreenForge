import Foundation
import AppKit

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let settings: SettingsStore
    let permissions: PermissionManager
    let displays: DisplayTopologyService
    let coordinates: CoordinateConverter
    let capture: ScreenCaptureService
    let lastRegion: LastRegionStore
    let hotkeys: GlobalHotkeyManager
    let router: CaptureResultRouter
    let clipboard: ClipboardExportService
    let files: FileExportService
    let filenames: FilenameTemplateService
    let sharing: SharingService
    let history: CaptureHistoryRepository
    let thumbnails: ThumbnailService
    let ocr: OCRService
    let sensitive: SensitiveDataDetectionService
    let launchAtLogin: LaunchAtLoginService
    let notifications: NotificationService
    let menuBar: MenuBarController
    let regionSelection: RegionSelectionCoordinator
    let windowSelection: WindowSelectionCoordinator
    let delayedCapture: DelayedCaptureCoordinator
    let editorWindows: EditorWindowManager
    let presets: PresetStore
    let scrolling: ScrollingCaptureCoordinator

    private init() {
        settings = SettingsStore()
        permissions = PermissionManager()
        displays = DisplayTopologyService()
        coordinates = CoordinateConverter()
        capture = ScreenCaptureService(displays: displays, coordinates: coordinates)
        lastRegion = LastRegionStore()
        clipboard = ClipboardExportService()
        filenames = FilenameTemplateService(settings: settings)
        files = FileExportService(settings: settings, filenames: filenames)
        sharing = SharingService()
        history = CaptureHistoryRepository()
        thumbnails = ThumbnailService()
        ocr = OCRService()
        sensitive = SensitiveDataDetectionService()
        launchAtLogin = LaunchAtLoginService()
        notifications = NotificationService(settings: settings)
        editorWindows = EditorWindowManager()
        presets = PresetStore()
        hotkeys = GlobalHotkeyManager(settings: settings)
        regionSelection = RegionSelectionCoordinator(
            capture: capture,
            displays: displays,
            coordinates: coordinates,
            settings: settings,
            lastRegion: lastRegion
        )
        windowSelection = WindowSelectionCoordinator(
            capture: capture,
            displays: displays,
            settings: settings
        )
        delayedCapture = DelayedCaptureCoordinator()
        scrolling = ScrollingCaptureCoordinator(capture: capture)
        router = CaptureResultRouter(
            settings: settings,
            clipboard: clipboard,
            files: files,
            history: history,
            thumbnails: thumbnails,
            notifications: notifications,
            editorWindows: editorWindows
        )
        menuBar = MenuBarController()
        configureHotkeys()
    }

    private func configureHotkeys() {
        hotkeys.onAction = { [weak self] action in
            Task { @MainActor in
                await self?.handleHotkey(action)
            }
        }
    }

    func handleHotkey(_ action: HotkeyAction) async {
        guard settings.hasCompletedOnboarding else { return }
        switch action {
        case .captureRegionEdit:
            await captureRegion(destination: .editor)
        case .captureWindowEdit:
            await captureWindow(destination: .editor)
        case .captureActiveDisplay:
            await captureActiveDisplay(destination: .settingsDefault(for: .fullDisplay))
        case .captureAllDisplays:
            await captureAllDisplays(destination: .settingsDefault(for: .allDisplays))
        case .captureLastRegionEdit:
            await captureLastRegion(destination: .editor)
        case .captureRegionCopy:
            await captureRegion(destination: .clipboard)
        case .captureWindowCopy:
            await captureWindow(destination: .clipboard)
        case .captureActiveDisplayCopy:
            await captureActiveDisplay(destination: .clipboard)
        case .captureLastRegionCopy:
            await captureLastRegion(destination: .clipboard)
        case .captureDelayed:
            delayedCapture.start(seconds: settings.defaultDelaySeconds) { [weak self] in
                Task { @MainActor in
                    await self?.captureRegion(destination: .editor)
                }
            }
        case .openHistory:
            menuBar.showHistory()
        case .openLastInEditor:
            if let entry = history.latest() {
                editorWindows.openHistoryEntry(entry, history: history)
            }
        }
    }

    private func ensureScreenRecording() async -> Bool {
        if permissions.hasScreenRecording { return true }
        if await permissions.refreshAsync() { return true }
        // Compact gate when access is still missing after retries (not full onboarding).
        permissions.showPermissionsGateIfNeeded()
        return false
    }

    func captureRegion(destination: CaptureDestination) async {
        guard await ensureScreenRecording() else { return }
        if let result = await regionSelection.beginSelection() {
            await router.route(result, destination: destination)
        }
    }

    func captureWindow(destination: CaptureDestination) async {
        guard await ensureScreenRecording() else { return }
        if let result = await windowSelection.beginSelection() {
            await router.route(result, destination: destination)
        }
    }

    func captureActiveDisplay(destination: CaptureDestination) async {
        guard await ensureScreenRecording() else { return }
        do {
            let result = try await capture.captureActiveDisplay(includeCursor: settings.captureCursor)
            await router.route(result, destination: destination)
        } catch {
            notifications.showError(error.localizedDescription)
        }
    }

    func captureAllDisplays(destination: CaptureDestination) async {
        guard await ensureScreenRecording() else { return }
        do {
            let result = try await capture.captureAllDisplays(
                mode: settings.allDisplaysMode,
                includeCursor: settings.captureCursor
            )
            await router.route(result, destination: destination)
        } catch {
            notifications.showError(error.localizedDescription)
        }
    }

    func captureLastRegion(destination: CaptureDestination) async {
        guard await ensureScreenRecording() else { return }
        if let result = await regionSelection.captureLastRegion() {
            await router.route(result, destination: destination)
        } else {
            await captureRegion(destination: destination)
        }
    }

    func captureActiveWindow(destination: CaptureDestination) async {
        do {
            let result = try await capture.captureFrontmostWindow(
                includeShadow: settings.windowIncludeShadow,
                margin: settings.windowMargin,
                includeCursor: settings.captureCursor
            )
            await router.route(result, destination: destination)
        } catch {
            notifications.showError(error.localizedDescription)
        }
    }
}
