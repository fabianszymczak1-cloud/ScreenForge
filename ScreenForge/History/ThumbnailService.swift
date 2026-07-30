import Foundation
import AppKit

actor ThumbnailService {
    func thumbnail(from image: CGImage, maxSize: CGFloat = 240) async -> URL? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let scale = min(maxSize / max(w, 1), maxSize / max(h, 1), 1)
        let tw = max(1, Int(w * scale))
        let th = max(1, Int(h * scale))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let out = ctx.makeImage() else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenForge/History/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(cgImage: out)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }
}
