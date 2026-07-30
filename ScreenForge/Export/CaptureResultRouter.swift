import Foundation
import AppKit

@MainActor
final class CaptureResultRouter {
    private let settings: SettingsStore
    private let clipboard: ClipboardExportService
    private let files: FileExportService
    private let history: CaptureHistoryRepository
    private let thumbnails: ThumbnailService
    private let notifications: NotificationService
    private let editorWindows: EditorWindowManager

    init(
        settings: SettingsStore,
        clipboard: ClipboardExportService,
        files: FileExportService,
        history: CaptureHistoryRepository,
        thumbnails: ThumbnailService,
        notifications: NotificationService,
        editorWindows: EditorWindowManager
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.files = files
        self.history = history
        self.thumbnails = thumbnails
        self.notifications = notifications
        self.editorWindows = editorWindows
    }

    func route(_ result: CaptureResult, destination: CaptureDestination) async {
        let action: PostCaptureAction
        switch destination {
        case .editor: action = .openEditor
        case .clipboard: action = .copyClipboard
        case .save: action = .saveAuto
        case .settingsDefault(let kind): action = settings.defaultAction(for: kind)
        case .action(let a): action = a
        }

        if settings.playShutterSound {
            NSSound(named: "Tink")?.play()
        }

        switch action {
        case .openEditor:
            editorWindows.openCapture(result)
            await recordHistory(result, copied: false, savedURL: nil, edited: false)
        case .copyClipboard:
            clipboard.copy(result.image, includeTIFF: settings.copyPNGAndTIFF)
            notifications.show(title: String(localized: "Capture copied"), body: nil, image: result.nsImage)
            await recordHistory(result, copied: true, savedURL: nil, edited: false)
            maybeAutoPaste()
        case .saveAuto:
            if let url = try? files.save(image: result.image, result: result) {
                notifications.show(title: String(localized: "Saved"), body: url.lastPathComponent, image: result.nsImage, fileURL: url)
                await recordHistory(result, copied: false, savedURL: url, edited: false)
            }
        case .showActionMenu:
            showActionMenu(for: result)
        case .copyAndSave:
            clipboard.copy(result.image, includeTIFF: settings.copyPNGAndTIFF)
            let url = try? files.save(image: result.image, result: result)
            notifications.show(title: String(localized: "Copied and saved"), body: url?.lastPathComponent, image: result.nsImage, fileURL: url)
            await recordHistory(result, copied: true, savedURL: url, edited: false)
        case .copyAndEdit:
            clipboard.copy(result.image, includeTIFF: settings.copyPNGAndTIFF)
            editorWindows.openCapture(result)
            await recordHistory(result, copied: true, savedURL: nil, edited: false)
        case .saveAndNotify:
            if let url = try? files.save(image: result.image, result: result) {
                notifications.show(title: String(localized: "Saved"), body: url.path, image: result.nsImage, fileURL: url)
                await recordHistory(result, copied: false, savedURL: url, edited: false)
            }
        case .share:
            editorWindows.openCapture(result)
            // Share from editor; also record
            await recordHistory(result, copied: false, savedURL: nil, edited: false)
        }
    }

    private func showActionMenu(for result: CaptureResult) {
        let menu = NSMenu()
        func item(_ title: String, _ action: PostCaptureAction) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(ActionProxy.invoke(_:)), keyEquivalent: "")
            i.representedObject = ActionPayload(result: result, action: action)
            i.target = ActionProxy.shared
            return i
        }
        menu.addItem(item(String(localized: "Open in editor"), .openEditor))
        menu.addItem(item(String(localized: "Copy image"), .copyClipboard))
        menu.addItem(item(String(localized: "Save"), .saveAuto))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(String(localized: "Cancel"), .openEditor)) // cancel handled by not routing again if needed
        let point = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: point, in: nil)
        ActionProxy.shared.router = self
    }

    fileprivate func performMenuAction(_ action: PostCaptureAction, result: CaptureResult) {
        Task { await route(result, destination: .action(action)) }
    }

    private func recordHistory(_ result: CaptureResult, copied: Bool, savedURL: URL?, edited: Bool) async {
        let thumb = await thumbnails.thumbnail(from: result.image)
        let storedURL = savedURL ?? history.storeFullImage(result.image, id: result.id)
        history.insert(
            CaptureHistoryEntry(
                id: result.id,
                createdAt: result.capturedAt,
                kind: result.kind,
                sourceApp: settings.storeSourceMetadata ? result.sourceAppName : nil,
                sourceWindow: settings.storeSourceMetadata ? result.sourceWindowTitle : nil,
                displayID: result.displayID.map { UInt32($0) },
                width: result.image.width,
                height: result.image.height,
                filePath: storedURL?.path,
                thumbnailPath: thumb?.path,
                wasCopied: copied,
                wasEdited: edited,
                pinned: false,
                title: nil,
                tags: []
            )
        )
        history.enforceRetention(
            unlimited: settings.historyUnlimited,
            maxCount: settings.historyLimitCount,
            maxDays: settings.historyLimitDays
        )
    }

    private func maybeAutoPaste() {
        guard settings.autoPasteAfterCopy, AppServices.shared.permissions.hasAccessibility else { return }
        // Synthetic Cmd+V
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

private final class ActionPayload: NSObject {
    let result: CaptureResult
    let action: PostCaptureAction
    init(result: CaptureResult, action: PostCaptureAction) {
        self.result = result
        self.action = action
    }
}

@MainActor
private final class ActionProxy: NSObject {
    static let shared = ActionProxy()
    weak var router: CaptureResultRouter?
    @objc func invoke(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ActionPayload else { return }
        router?.performMenuAction(payload.action, result: payload.result)
    }
}
