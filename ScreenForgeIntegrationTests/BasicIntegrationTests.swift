import XCTest
@testable import ScreenForge

@MainActor
final class BasicIntegrationTests: XCTestCase {
    func testSettingsPersist() {
        let s = SettingsStore()
        s.showMagnifier = false
        let s2 = SettingsStore()
        XCTAssertEqual(s2.showMagnifier, false)
        s.showMagnifier = true
    }

    func testPermissionRefreshDoesNotCrash() {
        let p = PermissionManager()
        p.refresh()
        // Value depends on system; just ensure callable
        _ = p.hasScreenRecording
    }

    func testClipboardCopy() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let img = ctx.makeImage()!
        ClipboardExportService().copy(img, includeTIFF: true)
        XCTAssertNotNil(NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil))
    }
}
