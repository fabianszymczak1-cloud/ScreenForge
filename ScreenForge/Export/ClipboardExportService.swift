import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardExportService {
    func copy(_ image: CGImage, includeTIFF: Bool) {
        PerformanceMonitor.shared.begin("clipboard.copy")
        defer { _ = PerformanceMonitor.shared.end("clipboard.copy") }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        var items: [NSPasteboardWriting] = [nsImage]
        if let png = pngData(image) {
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if includeTIFF, let tiff = nsImage.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            items = [item]
        }
        pasteboard.writeObjects(items)
    }

    func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
        pb.writeObjects([url as NSURL])
    }

    func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
