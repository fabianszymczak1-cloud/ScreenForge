import AppKit
import Foundation

func makeImage(w: Int, h: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.gray.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func time(_ name: String, _ block: () -> Void) {
    let t0 = CFAbsoluteTimeGetCurrent()
    block()
    let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    print(String(format: "%@: %.1f ms", name, ms))
}

let sizes = [(1920,1080),(2560,1440),(3840,2160),(3024,1964)]
for (w,h) in sizes {
    let img = makeImage(w: w, h: h)
    time("crop \(w)x\(h)") {
        _ = img.cropping(to: CGRect(x: 100, y: 100, width: 800, height: 600))
    }
    time("png \(w)x\(h)") {
        let rep = NSBitmapImageRep(cgImage: img)
        _ = rep.representation(using: .png, properties: [:])
    }
    time("pixelate-sim \(w)x\(h)") {
        let block = 12
        let sw = max(1, w/block); let sh = max(1, h/block)
        let cs = CGColorSpaceCreateDeviceRGB()
        let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .none
        small.draw(img, in: CGRect(x:0,y:0,width:sw,height:sh))
        _ = small.makeImage()
    }
}
