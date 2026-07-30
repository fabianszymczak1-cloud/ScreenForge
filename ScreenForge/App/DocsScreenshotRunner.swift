import AppKit
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

/// Opens real UI windows and writes PNG screenshots into `docs/screenshots/` for the README.
@MainActor
enum DocsScreenshotRunner {
    static func run(services: AppServices) async {
        services.settings.hasCompletedOnboarding = true
        services.settings.showDockIcon = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let outDir = resolveOutputDirectory()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // --- Editor ---
        let base = makeDemoDesktopImage(width: 1440, height: 900)
        let doc = EditorDocument(baseImage: base)
        // Sample annotations
        var arrow = CanvasObject(
            type: .arrow,
            frame: CGRect(x: 180, y: 220, width: 320, height: 80),
            style: ObjectStyle(strokeColor: .systemRed, fillColor: .clear, strokeWidth: 4)
        )
        arrow.points = [CGPoint(x: 200, y: 280), CGPoint(x: 480, y: 240)]
        doc.addObject(arrow, recordUndo: false)

        var rect = CanvasObject(
            type: .rectangle,
            frame: CGRect(x: 520, y: 360, width: 280, height: 160),
            style: ObjectStyle(
                strokeColor: .systemTeal,
                fillColor: NSColor.systemTeal.withAlphaComponent(0.15),
                strokeWidth: 3
            )
        )
        doc.addObject(rect, recordUndo: false)

        var text = CanvasObject(
            type: .textBox,
            frame: CGRect(x: 560, y: 400, width: 220, height: 80),
            style: ObjectStyle(strokeColor: .clear, fillColor: .clear, fontSize: 28, textColor: .systemRed)
        )
        text.text = "Annotate here"
        doc.addObject(text, recordUndo: false)

        var blur = CanvasObject(
            type: .blur,
            frame: CGRect(x: 80, y: 620, width: 220, height: 60),
            style: ObjectStyle()
        )
        blur.filterKind = .blur
        blur.filterAmount = 12
        doc.addObject(blur, recordUndo: false)

        services.editorWindows.open(document: doc)
        await settle(0.9)
        if let win = NSApp.windows.first(where: { $0.title.contains("ScreenForge") && $0.contentViewController == nil || $0.frame.width > 700 }) {
            // Prefer largest editor-ish window
            _ = win
        }
        let editorWin = NSApp.windows
            .filter { $0.isVisible && $0.frame.width > 600 && $0.frame.height > 400 }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .first
        if let editorWin, let img = captureWindow(editorWin) {
            writePNG(img, to: outDir.appendingPathComponent("editor.png"))
            print("Wrote editor.png")
        } else {
            print("WARN: editor window not captured")
        }

        // --- Settings (dedicated window — SwiftUI Settings scene is unreliable to find) ---
        let settingsHost = NSHostingController(rootView: SettingsRootView().environmentObject(services.settings))
        let settingsWindow = NSWindow(contentViewController: settingsHost)
        settingsWindow.title = "ScreenForge Settings"
        settingsWindow.setContentSize(NSSize(width: 560, height: 480))
        settingsWindow.styleMask = [.titled, .closable, .resizable]
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        await settle(0.7)
        if let img = captureWindow(settingsWindow) {
            writePNG(img, to: outDir.appendingPathComponent("settings.png"))
            print("Wrote settings.png")
        } else {
            print("WARN: settings window not captured")
        }
        settingsWindow.close()

        // --- History ---
        if let demo = makeDemoDesktopImage(width: 800, height: 500) as CGImage? {
            let id = UUID()
            let file = services.history.storeFullImage(demo, id: id)
            let thumb = await services.thumbnails.thumbnail(from: demo)
            services.history.insert(CaptureHistoryEntry(
                id: id,
                createdAt: Date(),
                kind: .region,
                sourceApp: "Safari",
                sourceWindow: "Documentation",
                displayID: nil,
                width: demo.width,
                height: demo.height,
                filePath: file?.path,
                thumbnailPath: thumb?.path,
                wasCopied: false,
                wasEdited: true,
                pinned: false,
                title: "Region capture",
                tags: []
            ))
        }
        services.menuBar.showHistory()
        await settle(0.8)
        if let hist = NSApp.windows.first(where: {
            $0.isVisible && ($0.title.localizedCaseInsensitiveContains("History")
                || $0.title.localizedCaseInsensitiveContains("Historia")
                || ($0.frame.width >= 680 && $0.frame.width <= 800))
        }), let img = captureWindow(hist) {
            writePNG(img, to: outDir.appendingPathComponent("history.png"))
            print("Wrote history.png")
        }

        // --- Menu bar popup (composite): capture menu after posting
        // Without Accessibility we approximate with a branded menu mock from the status item area.
        if let menuImg = makeMenuBarShowcaseImage() {
            writePNG(menuImg, to: outDir.appendingPathComponent("menu.png"))
            print("Wrote menu.png")
        }

        print("Docs screenshots → \(outDir.path)")
        exit(0)
    }

    private static func resolveOutputDirectory() -> URL {
        // Prefer repo docs/screenshots next to the project when running from a local build.
        let candidates = [
            URL(fileURLWithPath: "/Users/fabian/Desktop/Projekty/Greenshot copy/ScreenForge/docs/screenshots"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/screenshots"),
            FileManager.default.temporaryDirectory.appendingPathComponent("ScreenForge-docs-screenshots"),
        ]
        for url in candidates {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                return url
            }
        }
        return candidates[0]
    }

    private static func settle(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func captureWindow(_ window: NSWindow) -> CGImage? {
        window.appearance = NSAppearance(named: .aqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // Prefer `screencapture -l` (includes chrome); fall back to view cache.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sf-win-\(window.windowNumber).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-l", "\(window.windowNumber)", tmp.path]
        try? proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0,
           let ns = NSImage(contentsOf: tmp),
           let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try? FileManager.default.removeItem(at: tmp)
            return cg
        }
        try? FileManager.default.removeItem(at: tmp)

        if let view = window.contentView {
            let bounds = view.bounds
            guard bounds.width > 1, bounds.height > 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
            view.cacheDisplay(in: bounds, to: rep)
            return rep.cgImage
        }
        return nil
    }

    private static func captureLargestWindow(excludingTitles: [String]) -> CGImage? {
        let wins = NSApp.windows.filter { win in
            win.isVisible && !excludingTitles.contains(where: { win.title.localizedCaseInsensitiveContains($0) })
        }
        guard let win = wins.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
        return captureWindow(win)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func makeDemoDesktopImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Wallpaper gradient
        let colors = [NSColor.systemBlue.cgColor, NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])

        // Fake window chrome
        let card = CGRect(x: width / 6, y: height / 5, width: width * 2 / 3, height: height * 3 / 5)
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(card)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(CGRect(x: card.minX, y: card.maxY - 36, width: card.width, height: 36))
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 12, y: card.maxY - 24, width: 10, height: 10))
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 28, y: card.maxY - 24, width: 10, height: 10))
        ctx.setFillColor(NSColor.systemGreen.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 44, y: card.maxY - 24, width: 10, height: 10))

        // Content lines
        ctx.setFillColor(NSColor.secondaryLabelColor.cgColor)
        for i in 0..<8 {
            let y = card.minY + 40 + CGFloat(i) * 28
            ctx.fill(CGRect(x: card.minX + 24, y: y, width: card.width * (i % 2 == 0 ? 0.72 : 0.45), height: 10))
        }

        return ctx.makeImage()!
    }

    /// Menu-bar style showcase for README (status item + open capture menu).
    private static func makeMenuBarShowcaseImage() -> CGImage? {
        let width = 920, height = 560
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor(calibratedWhite: 0.78, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Fake desktop blur card behind
        let desk = makeDemoDesktopImage(width: width, height: height)
        ctx.setAlpha(0.35)
        ctx.draw(desk, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setAlpha(1)

        // Menu bar strip
        ctx.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 0.92).cgColor)
        ctx.fill(CGRect(x: 0, y: height - 28, width: width, height: 28))
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("􀎼 ScreenForge" as NSString).draw(at: CGPoint(x: width - 160, y: height - 22), withAttributes: iconAttrs)

        // Dropdown menu
        let menu = CGRect(x: width - 340, y: height - 28 - 340, width: 300, height: 340)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        let path = CGPath(roundedRect: menu, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        let items = [
            "Capture region",
            "Capture window",
            "Capture active display",
            "Capture all displays",
            "Capture last region",
            "Capture with delay",
            "—",
            "Open history",
            "Open image from clipboard",
            "Settings…",
            "Check for Updates…",
            "Quit"
        ]
        let itemFont = NSFont.systemFont(ofSize: 13)
        var y = menu.maxY - 28
        for item in items {
            if item == "—" {
                ctx.setStrokeColor(NSColor.separatorColor.cgColor)
                ctx.move(to: CGPoint(x: menu.minX + 12, y: y + 8))
                ctx.addLine(to: CGPoint(x: menu.maxX - 12, y: y + 8))
                ctx.strokePath()
                y -= 14
                continue
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: itemFont, .foregroundColor: NSColor.labelColor]
            (item as NSString).draw(at: CGPoint(x: menu.minX + 16, y: y), withAttributes: attrs)
            y -= 26
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
