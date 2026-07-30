import Foundation
import AppKit
import Compression

struct ProjectManifest: Codable {
    var version: Int
    var canvasWidth: Int
    var canvasHeight: Int
    var objects: [CanvasObjectDTO]
    var metadata: [String: String]
}

struct CanvasObjectDTO: Codable {
    var id: UUID
    var type: String
    var frame: CGRectCodable
    var rotation: Double
    var zIndex: Int
    var isVisible: Bool
    var isLocked: Bool
    var style: ObjectStyleDTO
    var text: String?
    var points: [CGPointCodable]?
    var numberValue: Int?
    var imageAsset: String?
    var filterKind: String?
    var filterAmount: Double?
}

struct ObjectStyleDTO: Codable {
    var strokeColor: String
    var fillColor: String
    var strokeWidth: Double
    var opacity: Double
    var cornerRadius: Double
    var fontName: String
    var fontSize: Double
    var textColor: String
    var arrowHeadSize: Double?

    init(
        strokeColor: String, fillColor: String, strokeWidth: Double, opacity: Double,
        cornerRadius: Double, fontName: String, fontSize: Double, textColor: String,
        arrowHeadSize: Double? = nil
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.arrowHeadSize = arrowHeadSize
    }
}

struct CGPointCodable: Codable {
    var x: Double; var y: Double
    init(_ p: CGPoint) { x = p.x; y = p.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

@MainActor
enum ProjectDocumentSerializer {
    static var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var recoveryDir: URL {
        let u = supportDir.appendingPathComponent("Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func recoveryURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)) ?? []
    }

    static func save(document: EditorDocument, to url: URL) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let baseName = "base.png"
        if let base = document.baseImage {
            let rep = NSBitmapImageRep(cgImage: base)
            if let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: temp.appendingPathComponent(baseName))
            }
        }
        var dtos: [CanvasObjectDTO] = []
        for obj in document.objects.sorted(by: { $0.zIndex < $1.zIndex }) {
            var dto = CanvasObjectDTO(
                id: obj.id,
                type: obj.type.rawValue,
                frame: CGRectCodable(obj.frame),
                rotation: obj.rotation,
                zIndex: obj.zIndex,
                isVisible: obj.isVisible,
                isLocked: obj.isLocked,
                style: ObjectStyleDTO(
                    strokeColor: obj.style.strokeColor.hexString,
                    fillColor: obj.style.fillColor.hexString,
                    strokeWidth: obj.style.strokeWidth,
                    opacity: obj.style.opacity,
                    cornerRadius: obj.style.cornerRadius,
                    fontName: obj.style.fontName,
                    fontSize: obj.style.fontSize,
                    textColor: obj.style.textColor.hexString
                ),
                text: obj.text,
                points: obj.points?.map(CGPointCodable.init),
                numberValue: obj.numberValue,
                imageAsset: nil,
                filterKind: obj.filterKind?.rawValue,
                filterAmount: obj.filterAmount
            )
            if let img = obj.embeddedImage {
                let asset = "\(obj.id.uuidString).png"
                let rep = NSBitmapImageRep(cgImage: img)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try data.write(to: temp.appendingPathComponent(asset))
                }
                dto.imageAsset = asset
            }
            dtos.append(dto)
        }
        let manifest = ProjectManifest(
            version: 1,
            canvasWidth: Int(document.canvasSize.width),
            canvasHeight: Int(document.canvasSize.height),
            objects: dtos,
            metadata: ["base": baseName]
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(manifest).write(to: temp.appendingPathComponent("manifest.json"))
        // Package as directory bundle .screenforge
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: temp, to: url)
        try? FileManager.default.removeItem(at: temp)
    }

    static func load(from url: URL) throws -> EditorDocument {
        let manifestURL = url.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ProjectManifest.self, from: data)
        var base: CGImage?
        if let baseName = manifest.metadata["base"] {
            let baseURL = url.appendingPathComponent(baseName)
            if let img = NSImage(contentsOf: baseURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                base = img
            }
        }
        let doc = EditorDocument(baseImage: base, canvasSize: CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight))
        for dto in manifest.objects {
            var obj = CanvasObject(
                id: dto.id,
                type: CanvasObjectType(rawValue: dto.type) ?? .rectangle,
                frame: dto.frame.cgRect,
                rotation: dto.rotation,
                zIndex: dto.zIndex,
                isVisible: dto.isVisible,
                isLocked: dto.isLocked,
                style: ObjectStyle(
                    strokeColor: NSColor(hex: dto.style.strokeColor) ?? .systemRed,
                    fillColor: NSColor(hex: dto.style.fillColor) ?? .clear,
                    strokeWidth: dto.style.strokeWidth,
                    opacity: dto.style.opacity,
                    cornerRadius: dto.style.cornerRadius,
                    fontName: dto.style.fontName,
                    fontSize: dto.style.fontSize,
                    textColor: NSColor(hex: dto.style.textColor) ?? .white
                ),
                text: dto.text,
                points: dto.points?.map(\.cgPoint),
                numberValue: dto.numberValue,
                filterKind: dto.filterKind.flatMap(FilterKind.init(rawValue:)),
                filterAmount: dto.filterAmount ?? 10
            )
            if let asset = dto.imageAsset {
                let assetURL = url.appendingPathComponent(asset)
                obj.embeddedImage = NSImage(contentsOf: assetURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            doc.objects.append(obj)
        }
        doc.fileURL = url
        doc.isDirty = false
        return doc
    }

    static func autosave(_ document: EditorDocument) {
        let url = recoveryDir.appendingPathComponent("\(document.id.uuidString).screenforge")
        try? save(document: document, to: url)
    }

    static func clearRecovery(for document: EditorDocument) {
        let url = recoveryDir.appendingPathComponent("\(document.id.uuidString).screenforge")
        try? FileManager.default.removeItem(at: url)
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
