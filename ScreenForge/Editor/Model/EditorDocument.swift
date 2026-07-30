import Foundation
import AppKit

@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    let id: UUID
    @Published var baseImage: CGImage?
    @Published var objects: [CanvasObject] = []
    @Published var canvasSize: CGSize
    @Published var selection: Set<UUID> = []
    @Published var currentTool: EditorTool = .select
    @Published var isDirty = false
    @Published var fileURL: URL?
    @Published var zoom: CGFloat = 1
    @Published var nextStepNumber: Int = 1
    @Published var toolStyles: [EditorTool: ObjectStyle] = [:]

    let undoCoordinator = UndoCoordinator()

    init(baseImage: CGImage?, canvasSize: CGSize? = nil) {
        self.id = UUID()
        var image = baseImage
        var size = canvasSize
        if let img = image, let trimmed = ImageAlphaTrimmer.trimTransparentEdges(img) {
            image = trimmed
            // Always sync canvas to trimmed pixels when caller didn't force a size,
            // or when forced size matched the untrimmed image (typical openCapture path).
            if size == nil || (Int(size!.width) == img.width && Int(size!.height) == img.height) {
                size = CGSize(width: trimmed.width, height: trimmed.height)
            }
        }
        self.baseImage = image
        if let size {
            self.canvasSize = size
        } else if let image {
            self.canvasSize = CGSize(width: image.width, height: image.height)
        } else {
            self.canvasSize = CGSize(width: 800, height: 600)
        }
    }

    var selectedObjects: [CanvasObject] {
        objects.filter { selection.contains($0.id) }
    }

    func addObject(_ object: CanvasObject, recordUndo: Bool = true) {
        var obj = object
        obj.zIndex = (objects.map(\.zIndex).max() ?? 0) + 1
        if recordUndo {
            let id = obj.id
            undoCoordinator.register(UndoCommand(
                undo: { [weak self] in self?.objects.removeAll { $0.id == id }; self?.isDirty = true },
                redo: { [weak self] in self?.objects.append(obj); self?.isDirty = true }
            ))
        }
        objects.append(obj)
        selection = [obj.id]
        isDirty = true
    }

    func updateObject(_ object: CanvasObject, recordUndo: Bool = true) {
        guard let idx = objects.firstIndex(where: { $0.id == object.id }) else { return }
        let old = objects[idx]
        if recordUndo {
            undoCoordinator.register(UndoCommand(
                undo: { [weak self] in self?.objects[idx] = old; self?.isDirty = true },
                redo: { [weak self] in self?.objects[idx] = object; self?.isDirty = true }
            ))
        }
        objects[idx] = object
        isDirty = true
    }

    func deleteSelected() {
        let ids = selection
        let removed = objects.filter { ids.contains($0.id) }
        undoCoordinator.register(UndoCommand(
            undo: { [weak self] in self?.objects.append(contentsOf: removed); self?.isDirty = true },
            redo: { [weak self] in self?.objects.removeAll { ids.contains($0.id) }; self?.isDirty = true }
        ))
        objects.removeAll { ids.contains($0.id) }
        selection.removeAll()
        isDirty = true
    }

    func duplicateSelected() {
        let copies = selectedObjects.map { obj -> CanvasObject in
            var c = obj
            c.id = UUID()
            c.frame = c.frame.offsetBy(dx: 12, dy: -12)
            return c
        }
        for c in copies { addObject(c) }
    }

    func bringToFront() {
        let maxZ = (objects.map(\.zIndex).max() ?? 0) + 1
        for id in selection {
            if let i = objects.firstIndex(where: { $0.id == id }) {
                objects[i].zIndex = maxZ + i
            }
        }
        isDirty = true
    }

    func sendToBack() {
        let minZ = (objects.map(\.zIndex).min() ?? 0) - selection.count
        var z = minZ
        for id in selection {
            if let i = objects.firstIndex(where: { $0.id == id }) {
                objects[i].zIndex = z
                z += 1
            }
        }
        isDirty = true
    }

    func style(for tool: EditorTool) -> ObjectStyle {
        toolStyles[tool] ?? defaultStyle(for: tool)
    }

    func setStyle(_ style: ObjectStyle, for tool: EditorTool) {
        toolStyles[tool] = style
    }

    private func defaultStyle(for tool: EditorTool) -> ObjectStyle {
        var s = ObjectStyle()
        switch tool {
        case .highlight:
            s.fillColor = NSColor.systemYellow.withAlphaComponent(0.35)
            s.strokeColor = .clear
            s.strokeWidth = 0
        case .solidRedact:
            s.fillColor = .black
            s.strokeColor = .clear
        case .blur, .pixelate:
            s.fillColor = NSColor.gray.withAlphaComponent(0.2)
            s.strokeColor = NSColor.white.withAlphaComponent(0.5)
        case .step:
            s.fillColor = .systemRed
            s.strokeColor = .white
            s.textColor = .white
        case .text, .textBox:
            s.fillColor = .clear
            s.strokeColor = .clear
            s.textColor = .systemRed
            s.fontSize = 20
        case .arrow, .doubleArrow, .line:
            s.strokeColor = .systemRed
            s.fillColor = .clear
        default:
            s.strokeColor = .systemRed
            s.fillColor = .clear
        }
        return s
    }

    func applyPreset(_ name: StylePreset) {
        applyStyle(name.style)
    }

    func applyStyle(_ style: ObjectStyle) {
        toolStyles[currentTool] = style
        // Also seed common drawing tools so switching tools keeps the look
        for tool in [EditorTool.rectangle, .ellipse, .line, .arrow, .doubleArrow, .freehand, .text, .step, .highlight] {
            var adapted = style
            if tool == .highlight {
                adapted.fillColor = style.strokeColor.withAlphaComponent(0.35)
                adapted.strokeColor = .clear
                adapted.strokeWidth = 0
            } else if tool == .text || tool == .textBox {
                adapted.textColor = style.strokeColor
                adapted.fillColor = .clear
                adapted.strokeColor = .clear
            } else if tool == .step {
                adapted.fillColor = style.strokeColor
                adapted.strokeColor = .white
                adapted.textColor = .white
            }
            toolStyles[tool] = adapted
        }
        if !selection.isEmpty {
            var next = objects
            for id in selection {
                if let i = next.firstIndex(where: { $0.id == id }) {
                    var obj = next[i]
                    var applied = style
                    if obj.type == .text || obj.type == .textBox {
                        applied.textColor = style.strokeColor
                        applied.fillColor = .clear
                        applied.strokeColor = .clear
                    } else if obj.type == .step {
                        applied.fillColor = style.strokeColor
                        applied.strokeColor = .white
                        applied.textColor = .white
                    } else if obj.type == .arrow || obj.type == .doubleArrow {
                        applied.arrowHeadSize = max(style.arrowHeadSize, style.strokeWidth * 3.2 + 6)
                    }
                    obj.style = applied
                    next[i] = obj
                }
            }
            objects = next
        }
        isDirty = true
    }
}

enum StylePreset: String, CaseIterable, Identifiable {
    case bugRed, instructionBlue, warningYellow, successGreen, subtle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bugRed: return String(localized: "Error report")
        case .instructionBlue: return String(localized: "Guide")
        case .warningYellow: return String(localized: "Warning")
        case .successGreen: return String(localized: "Confirmation")
        case .subtle: return String(localized: "Subtle")
        }
    }
    var style: ObjectStyle {
        var s = ObjectStyle()
        switch self {
        case .bugRed:
            s.strokeColor = NSColor(srgbRed: 0.85, green: 0.15, blue: 0.15, alpha: 1)
            s.fillColor = s.strokeColor.withAlphaComponent(0.08)
            s.strokeWidth = 3
            s.arrowHeadSize = 16
            s.textColor = s.strokeColor
        case .instructionBlue:
            s.strokeColor = NSColor(srgbRed: 0.15, green: 0.45, blue: 0.85, alpha: 1)
            s.fillColor = s.strokeColor.withAlphaComponent(0.08)
            s.strokeWidth = 3
            s.arrowHeadSize = 16
            s.textColor = s.strokeColor
        case .warningYellow:
            s.strokeColor = NSColor(srgbRed: 0.9, green: 0.65, blue: 0.1, alpha: 1)
            s.fillColor = s.strokeColor.withAlphaComponent(0.25)
            s.strokeWidth = 4
            s.arrowHeadSize = 18
            s.textColor = s.strokeColor
        case .successGreen:
            s.strokeColor = NSColor(srgbRed: 0.15, green: 0.65, blue: 0.35, alpha: 1)
            s.fillColor = s.strokeColor.withAlphaComponent(0.08)
            s.strokeWidth = 3
            s.arrowHeadSize = 16
            s.textColor = s.strokeColor
        case .subtle:
            s.strokeColor = NSColor.secondaryLabelColor
            s.fillColor = .clear
            s.strokeWidth = 1.5
            s.arrowHeadSize = 12
            s.textColor = .labelColor
        }
        return s
    }
}
