import Foundation
import AppKit

struct ObjectPreset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var objects: [CanvasObjectDTO]
}

struct SavedStylePreset: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var style: ObjectStyleDTO
}

private struct PresetFile: Codable {
    var objectPresets: [ObjectPreset]
    var stylePresets: [SavedStylePreset]
}

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [ObjectPreset] = []
    @Published var stylePresets: [SavedStylePreset] = []
    private let url: URL

    init() {
        url = ProjectDocumentSerializer.supportDir.appendingPathComponent("presets.json")
        load()
    }

    // MARK: - Style presets

    func saveStyle(from document: EditorDocument, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let style = document.selectedObjects.first?.style ?? document.style(for: document.currentTool)
        stylePresets.append(SavedStylePreset(name: trimmed, style: Self.encodeStyle(style)))
        persist()
    }

    func applyStylePreset(_ preset: SavedStylePreset, to document: EditorDocument) {
        document.applyStyle(Self.decodeStyle(preset.style))
    }

    func deleteStyle(_ id: UUID) {
        stylePresets.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Object presets

    func saveSelected(from document: EditorDocument, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let selected = document.selectedObjects
        guard !selected.isEmpty else { return }
        let dtos: [CanvasObjectDTO] = selected.map { obj in
            CanvasObjectDTO(
                id: obj.id, type: obj.type.rawValue, frame: CGRectCodable(obj.frame),
                rotation: obj.rotation, zIndex: obj.zIndex, isVisible: obj.isVisible, isLocked: obj.isLocked,
                style: Self.encodeStyle(obj.style),
                text: obj.text, points: obj.points?.map(CGPointCodable.init),
                numberValue: obj.numberValue, imageAsset: nil,
                filterKind: obj.filterKind?.rawValue, filterAmount: obj.filterAmount
            )
        }
        presets.append(ObjectPreset(name: trimmed, objects: dtos))
        persist()
    }

    /// Inserts preset objects centered on the document canvas (keeps relative layout).
    func insert(preset: ObjectPreset, into document: EditorDocument) {
        guard !preset.objects.isEmpty else { return }

        let frames = preset.objects.map(\.frame.cgRect)
        var union = frames[0]
        for f in frames.dropFirst() { union = union.union(f) }

        let targetCenter = CGPoint(x: document.canvasSize.width / 2, y: document.canvasSize.height / 2)
        let sourceCenter = CGPoint(x: union.midX, y: union.midY)
        let dx = targetCenter.x - sourceCenter.x
        let dy = targetCenter.y - sourceCenter.y

        var newSelection: Set<UUID> = []
        for dto in preset.objects {
            let frame = dto.frame.cgRect.offsetBy(dx: dx, dy: dy)
            let points = dto.points?.map { p in
                CGPoint(x: p.cgPoint.x + dx, y: p.cgPoint.y + dy)
            }
            var obj = CanvasObject(
                type: CanvasObjectType(rawValue: dto.type) ?? .rectangle,
                frame: frame,
                rotation: dto.rotation,
                style: Self.decodeStyle(dto.style),
                text: dto.text,
                points: points,
                numberValue: dto.numberValue,
                filterKind: dto.filterKind.flatMap(FilterKind.init(rawValue:)),
                filterAmount: dto.filterAmount ?? 10
            )
            document.addObject(obj)
            newSelection.insert(obj.id)
        }
        document.selection = newSelection
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let file = PresetFile(objectPresets: presets, stylePresets: stylePresets)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        // New format
        if let file = try? JSONDecoder().decode(PresetFile.self, from: data) {
            presets = file.objectPresets
            stylePresets = file.stylePresets
            return
        }
        // Legacy: array of ObjectPreset only
        if let legacy = try? JSONDecoder().decode([ObjectPreset].self, from: data) {
            presets = legacy
            stylePresets = []
            persist()
        }
    }

    static func encodeStyle(_ style: ObjectStyle) -> ObjectStyleDTO {
        ObjectStyleDTO(
            strokeColor: style.strokeColor.hexString,
            fillColor: style.fillColor.hexString,
            strokeWidth: style.strokeWidth,
            opacity: style.opacity,
            cornerRadius: style.cornerRadius,
            fontName: style.fontName,
            fontSize: style.fontSize,
            textColor: style.textColor.hexString,
            arrowHeadSize: style.arrowHeadSize
        )
    }

    static func decodeStyle(_ dto: ObjectStyleDTO) -> ObjectStyle {
        ObjectStyle(
            strokeColor: NSColor(hex: dto.strokeColor) ?? .systemRed,
            fillColor: NSColor(hex: dto.fillColor) ?? .clear,
            strokeWidth: dto.strokeWidth,
            opacity: dto.opacity,
            cornerRadius: dto.cornerRadius,
            fontName: dto.fontName,
            fontSize: dto.fontSize,
            textColor: NSColor(hex: dto.textColor) ?? .white,
            arrowHeadSize: dto.arrowHeadSize ?? 14
        )
    }
}
