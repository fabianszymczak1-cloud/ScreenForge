import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class EditorWindowManager {
    private var controllers: [UUID: EditorWindowController] = [:]

    func openCapture(_ result: CaptureResult) {
        let doc = EditorDocument(baseImage: result.image)
        open(document: doc)
    }

    func openHistoryEntry(_ entry: CaptureHistoryEntry, history: CaptureHistoryRepository) {
        guard let image = history.image(for: entry) else { return }
        let doc = EditorDocument(baseImage: image)
        open(document: doc)
    }

    func openProject(url: URL) {
        do {
            let doc = try ProjectDocumentSerializer.load(from: url)
            open(document: doc)
        } catch {
            AppServices.shared.notifications.showError(error.localizedDescription)
        }
    }

    func openImage(url: URL) {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        open(document: EditorDocument(baseImage: image))
    }

    func openClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        open(document: EditorDocument(baseImage: cg))
    }

    func open(document: EditorDocument) {
        if let existing = controllers[document.id] {
            existing.showWindow(nil)
            return
        }
        let wc = EditorWindowController(document: document)
        wc.onClose = { [weak self] id in
            self?.controllers.removeValue(forKey: id)
            ProjectDocumentSerializer.clearRecovery(for: document)
        }
        controllers[document.id] = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if AppServices.shared.settings.editorFitOnOpen {
            wc.canvasView.fitToWindow()
        }
    }

    func flushAutosaves() {
        for (_, wc) in controllers {
            wc.autosave()
        }
    }
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let documentModel: EditorDocument
    let canvasView = CanvasView()
    private let renderer = CanvasRenderer()
    private var toolbarView: EditorToolbarBackgroundView!
    private var toolButtons: [EditorTool: NSButton] = [:]
    private var statusLabel: NSTextField!
    private var autosaveTimer: Timer?
    private var toolCancellable: AnyCancellable?
    private var keyMonitor: Any?
    var onClose: ((UUID) -> Void)?
    private var previousApp: NSRunningApplication?

    init(document: EditorDocument) {
        self.documentModel = document
        self.previousApp = NSWorkspace.shared.frontmostApplication
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenForge"
        window.center()
        window.minSize = NSSize(width: 700, height: 480)
        super.init(window: window)
        window.delegate = self
        setupUI()
        canvasView.document = document
        canvasView.onChange = { [weak self] in
            self?.refreshStatus()
            self?.updateToolbarHighlight()
        }
        toolCancellable = document.$currentTool.sink { [weak self] _ in
            self?.updateToolbarHighlight()
        }
        updateToolbarHighlight()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if self.handleEditorCommandShortcut(event) { return nil }
            return event
        }
        if AppServices.shared.settings.autosaveEnabled {
            autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.autosave() }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let window else { return }
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]

        let toolbar = buildToolbar()
        toolbarView = toolbar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = canvasView
        canvasView.frame = NSRect(x: 0, y: 0, width: 2000, height: 2000)
        root.addSubview(scroll)

        let props = buildProperties()
        props.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(props)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: 64),

            props.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            props.topAnchor.constraint(equalTo: root.topAnchor),
            props.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),
            props.widthAnchor.constraint(equalToConstant: 240),

            scroll.leadingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: props.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
            statusLabel.heightAnchor.constraint(equalToConstant: 18),
        ])

        window.contentView = root
        refreshStatus()
        window.makeFirstResponder(canvasView)
    }

    private func buildToolbar() -> EditorToolbarBackgroundView {
        let container = EditorToolbarBackgroundView()
        container.onAppearanceChange = { [weak self] in
            self?.updateToolbarHighlight()
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.distribution = .fillEqually
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let tools: [(String, EditorTool)] = [
            ("cursorarrow", .select),
            ("rectangle", .rectangle),
            ("circle", .ellipse),
            ("line.diagonal", .line),
            ("arrow.right", .arrow),
            ("scribble", .freehand),
            ("textformat", .text),
            ("list.number", .step),
            ("paintbrush.pointed.fill", .highlight),
            ("circle.lefthalf.filled", .focusArea),
            ("plus.magnifyingglass", .magnify),
            ("aqi.medium", .blur),
            ("square.grid.3x3", .pixelate),
            ("square.fill", .solidRedact),
            ("crop", .crop),
            ("photo", .image),
        ]
        toolButtons.removeAll()
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        for (symbol, tool) in tools {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tool.displayName)?
                .withSymbolConfiguration(cfg) ?? NSImage()
            let btn = NSButton(image: image, target: self, action: #selector(selectTool(_:)))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.setButtonType(.momentaryChange)
            btn.imagePosition = .imageOnly
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.toolTip = tool.tooltip
            btn.setAccessibilityLabel(tool.displayName)
            btn.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
            btn.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            btn.setContentHuggingPriority(.defaultLow, for: .vertical)
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }
        let copyBtn = NSButton(title: "⌘↩", target: self, action: #selector(copyAndClose))
        copyBtn.bezelStyle = .rounded
        copyBtn.toolTip = String(localized: "Copy and close (⌘↩)")
        copyBtn.setAccessibilityLabel(String(localized: "Copy and close"))
        copyBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        copyBtn.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(copyBtn)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func updateToolbarHighlight() {
        let active = documentModel.currentTool
        let appearance = toolbarView?.effectiveAppearance ?? NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            for (tool, btn) in toolButtons {
                let on = tool == active
                btn.layer?.backgroundColor = on
                    ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
                    : NSColor.clear.cgColor
                btn.layer?.borderWidth = on ? 1.5 : 0
                btn.layer?.borderColor = on ? NSColor.controlAccentColor.cgColor : nil
                btn.contentTintColor = on ? .controlAccentColor : .labelColor
            }
        }
    }

    private func buildProperties() -> NSView {
        let hosting = NSHostingView(rootView: EditorPropertiesView(document: documentModel, controller: self))
        return hosting
    }

    @objc private func selectTool(_ sender: NSButton) {
        if let tool = EditorTool(rawValue: sender.identifier?.rawValue ?? "") {
            documentModel.currentTool = tool
            updateToolbarHighlight()
            if tool == .image {
                insertImageFromPanel()
            }
        }
        window?.makeFirstResponder(canvasView)
    }

    @objc func copyAndClose() {
        guard let image = renderer.render(documentModel, quality: .full) else { return }
        AppServices.shared.clipboard.copy(image, includeTIFF: AppServices.shared.settings.copyPNGAndTIFF)
        AppServices.shared.notifications.show(title: String(localized: "Capture copied"), body: nil)
        documentModel.isDirty = false
        close()
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        if AppServices.shared.settings.autoPasteAfterCopy {
            // handled in router typically
        }
    }

    @objc func copyKeepOpen() {
        guard let image = renderer.render(documentModel, quality: .full) else { return }
        AppServices.shared.clipboard.copy(image, includeTIFF: true)
        AppServices.shared.notifications.show(title: String(localized: "Capture copied"), body: nil)
    }

    func save() {
        if let url = documentModel.fileURL {
            try? ProjectDocumentSerializer.save(document: documentModel, to: url)
            documentModel.isDirty = false
            ProjectDocumentSerializer.clearRecovery(for: documentModel)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "screenforge") ?? .data, .png, .jpeg, .pdf]
        panel.nameFieldStringValue = "Capture.screenforge"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension.lowercased() == "screenforge" {
            try? ProjectDocumentSerializer.save(document: documentModel, to: url)
            documentModel.fileURL = url
            documentModel.isDirty = false
        } else if let image = renderer.render(documentModel, quality: .full) {
            try? AppServices.shared.files.write(image: image, to: url, format: url.pathExtension)
        }
    }

    func exportPNG() {
        guard let image = renderer.render(documentModel, quality: .full) else { return }
        if let url = try? AppServices.shared.files.save(image: image, result: nil, format: "png") {
            AppServices.shared.notifications.show(title: String(localized: "Saved"), body: url.lastPathComponent, fileURL: url)
        }
    }

    func openExportFolder() {
        AppServices.shared.files.openSaveDirectory()
    }

    func runOCR(selectionOnly: Bool) {
        Task {
            guard let image = renderer.render(documentModel, quality: .full) else { return }
            let text: String
            if selectionOnly, let obj = documentModel.selectedObjects.first {
                if let cropped = image.cropping(to: obj.frame.integral) {
                    text = (try? await AppServices.shared.ocr.recognize(cropped)) ?? ""
                } else { text = "" }
            } else {
                text = (try? await AppServices.shared.ocr.recognize(image)) ?? ""
            }
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = String(localized: "OCR")
                alert.informativeText = text.isEmpty ? String(localized: "No text recognized") : text
                alert.addButton(withTitle: String(localized: "Copy"))
                alert.addButton(withTitle: String(localized: "Create text"))
                alert.addButton(withTitle: String(localized: "Close"))
                let r = alert.runModal()
                if r == .alertFirstButtonReturn {
                    AppServices.shared.clipboard.copyText(text)
                } else if r == .alertSecondButtonReturn {
                    var obj = CanvasObject(type: .textBox, frame: CGRect(x: 40, y: 40, width: 300, height: 120), style: documentModel.style(for: .text))
                    obj.text = text
                    documentModel.addObject(obj)
                    canvasView.needsDisplay = true
                }
            }
        }
    }

    func detectSensitive() {
        Task {
            // Prefer raw capture so annotations don't confuse OCR / boxes
            guard let image = documentModel.baseImage ?? renderer.render(documentModel, quality: .full) else { return }
            let regions: [SensitiveRegion]
            do {
                regions = try await AppServices.shared.ocr.detectSensitiveRegions(
                    in: image,
                    detector: AppServices.shared.sensitive
                )
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Sensitive data")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
                return
            }

            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = String(localized: "Sensitive data")
                if regions.isEmpty {
                    alert.informativeText = String(localized: "No typical sensitive data found (email, phone, IP, PESEL, IBAN, card, token…).")
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    return
                }

                let summary = regions
                    .map { region in
                        let title = SensitiveFinding(kind: region.kind, value: region.value, range: nil).titlePL
                        return "• \(title): \(region.value)"
                    }
                    .joined(separator: "\n")
                alert.informativeText = summary
                    + "\n\n"
                    + String(localized: "Cover detected areas with irreversible Solid redact (recommended).")
                alert.addButton(withTitle: String(localized: "Solid redact"))
                alert.addButton(withTitle: String(localized: "Pixelate"))
                alert.addButton(withTitle: String(localized: "Show only"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                let response = alert.runModal()

                switch response {
                case .alertFirstButtonReturn:
                    applySensitiveRegions(regions, mode: .solid)
                case .alertSecondButtonReturn:
                    applySensitiveRegions(regions, mode: .pixelate)
                case .alertThirdButtonReturn:
                    applySensitiveRegions(regions, mode: .highlight)
                default:
                    break
                }
            }
        }
    }

    private enum SensitiveCoverMode { case solid, pixelate, highlight }

    private func applySensitiveRegions(_ regions: [SensitiveRegion], mode: SensitiveCoverMode) {
        var newSelection: Set<UUID> = []
        for region in regions {
            var style = ObjectStyle()
            var obj: CanvasObject
            switch mode {
            case .solid:
                style.fillColor = .black
                style.strokeColor = .clear
                style.strokeWidth = 0
                obj = CanvasObject(type: .solidRedact, frame: region.rect, style: style)
                obj.filterKind = .solidRedact
                obj.filterAmount = 1
            case .pixelate:
                style.fillColor = NSColor.gray.withAlphaComponent(0.15)
                style.strokeColor = NSColor.systemOrange.withAlphaComponent(0.8)
                style.strokeWidth = 1
                obj = CanvasObject(type: .pixelate, frame: region.rect, style: style)
                obj.filterKind = .pixelate
                obj.filterAmount = 14
            case .highlight:
                style.fillColor = NSColor.systemOrange.withAlphaComponent(0.35)
                style.strokeColor = NSColor.systemOrange
                style.strokeWidth = 2
                obj = CanvasObject(type: .highlight, frame: region.rect, style: style)
                obj.filterKind = .highlight
                obj.filterAmount = 1
            }
            // Tag for user clarity
            obj.text = "\(region.kind): \(region.value)"
            documentModel.addObject(obj, recordUndo: true)
            newSelection.insert(obj.id)
        }
        documentModel.selection = newSelection
        canvasView.needsDisplay = true
        refreshStatus()
    }

    private func insertImageFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        guard panel.runModal() == .OK, let url = panel.url,
              let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var obj = CanvasObject(type: .image, frame: CGRect(x: 40, y: 40, width: min(CGFloat(img.width), 400), height: min(CGFloat(img.height), 300)))
        obj.embeddedImage = img
        documentModel.addObject(obj)
        canvasView.needsDisplay = true
    }

    func autosave() {
        guard documentModel.isDirty else { return }
        ProjectDocumentSerializer.autosave(documentModel)
    }

    private func refreshStatus() {
        let z = Int((documentModel.zoom * 100).rounded())
        statusLabel.stringValue = "\(Int(documentModel.canvasSize.width))×\(Int(documentModel.canvasSize.height))  •  \(z)%  •  \(documentModel.objects.count) objects"
        canvasView.invalidateIntrinsicContentSize()
        canvasView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        autosaveTimer?.invalidate()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onClose?(documentModel.id)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if documentModel.isDirty && AppServices.shared.settings.confirmCloseUnsaved {
            let alert = NSAlert()
            alert.messageText = String(localized: "Unsaved changes")
            alert.informativeText = String(localized: "Save the document before closing?")
            alert.addButton(withTitle: String(localized: "Save"))
            alert.addButton(withTitle: String(localized: "Don’t save"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: save(); return true
            case .alertSecondButtonReturn: return true
            default: return false
            }
        }
        return true
    }

    /// Handles ⌘Z / ⌘⇧Z / ⌘Y / ⌘V even when focus is on the properties panel.
    @discardableResult
    private func handleEditorCommandShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        // Let NSTextView keep its own undo / paste while editing text on canvas.
        if window?.firstResponder is NSTextView { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z" where flags.contains(.shift):
            performRedo(); return true
        case "y":
            performRedo(); return true
        case "z":
            performUndo(); return true
        case "v":
            return canvasView.pasteImageFromClipboard()
        case "s":
            if flags.contains(.shift) { saveAs() } else { save() }
            return true
        default:
            return false
        }
    }

    private func performUndo() {
        documentModel.undoCoordinator.undo()
        canvasView.needsDisplay = true
        refreshStatus()
    }

    private func performRedo() {
        documentModel.undoCoordinator.redo()
        canvasView.needsDisplay = true
        refreshStatus()
    }

    override func keyDown(with event: NSEvent) {
        if handleEditorCommandShortcut(event) { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76) {
            if flags.contains(.shift) { copyKeepOpen() } else { copyAndClose() }
            return
        }
        super.keyDown(with: event)
    }
}

/// Sidebar fill that follows Light/Dark — `CALayer.backgroundColor` freezes dynamic NSColors.
private final class EditorToolbarBackgroundView: NSView {
    var onAppearanceChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }
}

struct EditorPropertiesView: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject private var presetStore = AppServices.shared.presets
    weak var controller: EditorWindowController?
    @State private var newStyleName = ""
    @State private var newObjectPresetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Properties").font(.headline)
                if let obj = document.selectedObjects.first {
                    Text(obj.type.rawValue).foregroundStyle(.secondary)
                    if obj.type.showsTextColor {
                        ColorPicker("Text color", selection: bindingColor(obj, \.textColor))
                    }
                    if obj.type.showsStrokeColor {
                        ColorPicker("Line", selection: bindingColor(obj, \.strokeColor))
                    }
                    if obj.type.showsFillColor {
                        ColorPicker("Fill", selection: bindingColor(obj, \.fillColor))
                    }
                    if obj.type.showsStrokeWidth {
                        Slider(value: bindingWidth(obj), in: 0...20) { Text("Stroke width") }
                    }
                    if obj.type.showsFilterAmount {
                        Slider(value: bindingAmount(obj), in: 1...40) { Text("Effect strength") }
                    }
                } else {
                    Text("Nothing selected").foregroundStyle(.secondary)
                    Text("Style presets set colors for the next drawings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("Style presets").font(.subheadline.weight(.semibold))
                ForEach(StylePreset.allCases) { p in
                    Button {
                        document.applyPreset(p)
                        controller?.canvasView.needsDisplay = true
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(nsColor: p.style.strokeColor))
                                .frame(width: 10, height: 10)
                            Text(p.title)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .help(String(localized: "Apply style preset \(p.title)"))
                }
                ForEach(presetStore.stylePresets) { preset in
                    HStack {
                        Button {
                            presetStore.applyStylePreset(preset, to: document)
                            controller?.canvasView.needsDisplay = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: preset.style.strokeColor) ?? .systemRed))
                                    .frame(width: 10, height: 10)
                                Text(preset.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .help(String(localized: "Apply saved style \(preset.name)"))
                        Button(role: .destructive) {
                            presetStore.deleteStyle(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Delete style preset"))
                    }
                }
                HStack {
                    TextField(String(localized: "Style name"), text: $newStyleName)
                    Button("Save style") {
                        presetStore.saveStyle(from: document, name: newStyleName)
                        newStyleName = ""
                    }
                    .disabled(newStyleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(String(localized: "Save selection style (or active tool) as a preset"))
                }
                Divider()
                Text("Object presets").font(.subheadline.weight(.semibold))
                HStack {
                    TextField(String(localized: "Name"), text: $newObjectPresetName)
                    Button("Save") {
                        presetStore.saveSelected(from: document, name: newObjectPresetName)
                        newObjectPresetName = ""
                    }
                    .disabled(document.selection.isEmpty || newObjectPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(String(localized: "Save selected objects as a preset"))
                }
                if presetStore.presets.isEmpty {
                    Text("No saved objects").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(presetStore.presets) { preset in
                        HStack {
                            Button(preset.name) {
                                presetStore.insert(preset: preset, into: document)
                                controller?.canvasView.needsDisplay = true
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Insert objects at canvas center"))
                            Spacer()
                            Button(role: .destructive) {
                                presetStore.delete(preset.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(String(localized: "Delete object preset"))
                        }
                    }
                }
                Divider()
                Button("OCR entire image") { controller?.runOCR(selectionOnly: false) }
                    .help(String(localized: "OCR entire image"))
                Button("OCR selection") { controller?.runOCR(selectionOnly: true) }
                    .help(String(localized: "OCR selection"))
                Button("Detect sensitive data") { controller?.detectSensitive() }
                    .help(String(localized: "Detect emails, phones, PESEL, cards and redact them"))
                Button("Export PNG") { controller?.exportPNG() }
                    .help(String(localized: "Export current image as PNG"))
                Button(String(localized: "Open export folder")) { controller?.openExportFolder() }
                    .help(String(localized: "Open the folder with exported PNG files in Finder"))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func bindingColor(_ obj: CanvasObject, _ keyPath: WritableKeyPath<ObjectStyle, NSColor>) -> Binding<Color> {
        Binding(
            get: {
                if let o = document.objects.first(where: { $0.id == obj.id }) {
                    return Color(nsColor: o.style[keyPath: keyPath])
                }
                return Color.red
            },
            set: { newValue in
                guard let i = document.objects.firstIndex(where: { $0.id == obj.id }) else { return }
                document.objects[i].style[keyPath: keyPath] = NSColor(newValue)
                document.isDirty = true
                controller?.canvasView.needsDisplay = true
            }
        )
    }

    private func bindingWidth(_ obj: CanvasObject) -> Binding<Double> {
        Binding(
            get: { Double(document.objects.first(where: { $0.id == obj.id })?.style.strokeWidth ?? 3) },
            set: { v in
                guard let i = document.objects.firstIndex(where: { $0.id == obj.id }) else { return }
                document.objects[i].style.strokeWidth = CGFloat(v)
                document.isDirty = true
                controller?.canvasView.needsDisplay = true
            }
        )
    }

    private func bindingAmount(_ obj: CanvasObject) -> Binding<Double> {
        Binding(
            get: { Double(document.objects.first(where: { $0.id == obj.id })?.filterAmount ?? 8) },
            set: { v in
                guard let i = document.objects.firstIndex(where: { $0.id == obj.id }) else { return }
                document.objects[i].filterAmount = CGFloat(v)
                document.isDirty = true
                controller?.canvasView.needsDisplay = true
            }
        )
    }
}
