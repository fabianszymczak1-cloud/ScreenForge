import Foundation
import AppKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class FileExportService {
    private let settings: SettingsStore
    private let filenames: FilenameTemplateService

    init(settings: SettingsStore, filenames: FilenameTemplateService) {
        self.settings = settings
        self.filenames = filenames
    }

    var saveDirectory: URL {
        let url = URL(fileURLWithPath: settings.saveDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func save(image: CGImage, result: CaptureResult?, format: String? = nil) throws -> URL {
        let url = filenames.nextURL(in: saveDirectory, result: result)
        try write(image: image, to: url, format: format ?? url.pathExtension)
        return url
    }

    func saveAs(image: CGImage, window: NSWindow?) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = filenames.render(result: nil)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        try write(image: image, to: url, format: url.pathExtension)
        return url
    }

    func write(image: CGImage, to url: URL, format: String) throws {
        PerformanceMonitor.shared.begin("export.write")
        defer { _ = PerformanceMonitor.shared.end("export.write") }
        let ext = format.lowercased()
        switch ext {
        case "jpg", "jpeg":
            try writeBitmap(image, to: url, type: .jpeg, props: [.compressionFactor: settings.jpegQuality])
        case "tif", "tiff":
            try writeBitmap(image, to: url, type: .tiff, props: [:])
        case "pdf":
            try writePDF(image, to: url)
        case "heic":
            try writeHEIC(image, to: url)
        default:
            try writeBitmap(image, to: url, type: .png, props: [:])
        }
    }

    private func writeBitmap(_ image: CGImage, to url: URL, type: NSBitmapImageRep.FileType, props: [NSBitmapImageRep.PropertyKey: Any]) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: type, properties: props) else {
            throw CaptureError.captureFailed("Eksport nieudany")
        }
        try data.write(to: url, options: .atomic)
    }

    private func writePDF(_ image: CGImage, to url: URL) throws {
        let size = CGSize(width: image.width, height: image.height)
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CaptureError.captureFailed("PDF nieudany")
        }
        ctx.beginPage(mediaBox: &mediaBox)
        ctx.draw(image, in: mediaBox)
        ctx.endPage()
        ctx.closePDF()
    }

    private func writeHEIC(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw CaptureError.captureFailed("HEIC unavailable")
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw CaptureError.captureFailed("HEIC zapis nieudany")
        }
    }
}
