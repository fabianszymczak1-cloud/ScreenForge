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

        // --- Editor (rich demo capture under annotations) ---
        let base = makeBugReportDemoImage(width: 1440, height: 900)
        let doc = EditorDocument(baseImage: base)

        var arrow = CanvasObject(
            type: .arrow,
            frame: CGRect(x: 780, y: 250, width: 280, height: 90),
            style: ObjectStyle(strokeColor: .systemRed, fillColor: .clear, strokeWidth: 4)
        )
        arrow.points = [CGPoint(x: 1020, y: 260), CGPoint(x: 820, y: 320)]
        doc.addObject(arrow, recordUndo: false)

        var highlight = CanvasObject(
            type: .highlight,
            frame: CGRect(x: 300, y: 300, width: 420, height: 44),
            style: ObjectStyle(
                strokeColor: .systemYellow,
                fillColor: NSColor.systemYellow.withAlphaComponent(0.35),
                strokeWidth: 1
            )
        )
        doc.addObject(highlight, recordUndo: false)

        var callout = CanvasObject(
            type: .rectangle,
            frame: CGRect(x: 980, y: 340, width: 320, height: 92),
            style: ObjectStyle(
                strokeColor: .systemRed,
                fillColor: NSColor.systemRed.withAlphaComponent(0.12),
                strokeWidth: 3
            )
        )
        doc.addObject(callout, recordUndo: false)

        var text = CanvasObject(
            type: .textBox,
            frame: CGRect(x: 996, y: 356, width: 288, height: 64),
            style: ObjectStyle(strokeColor: .clear, fillColor: .clear, fontSize: 22, textColor: .systemRed)
        )
        text.text = "Wrong total — should be $48"
        doc.addObject(text, recordUndo: false)

        var blur = CanvasObject(
            type: .blur,
            frame: CGRect(x: 300, y: 470, width: 360, height: 36),
            style: ObjectStyle()
        )
        blur.filterKind = .blur
        blur.filterAmount = 14
        doc.addObject(blur, recordUndo: false)

        services.editorWindows.open(document: doc)
        await settle(0.9)
        let editorWin = NSApp.windows
            .filter { $0.isVisible && $0.frame.width > 600 && $0.frame.height > 400 }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .first
        if let editorWin, let img = captureWindow(editorWin) {
            writePNG(img, to: outDir.appendingPathComponent("editor-hero.png"))
            print("Wrote editor.png")
        } else {
            print("WARN: editor window not captured")
        }

        // --- Settings ---
        let settingsHost = NSHostingController(rootView: SettingsRootView().environmentObject(services.settings))
        let settingsWindow = NSWindow(contentViewController: settingsHost)
        settingsWindow.title = "ScreenForge Settings"
        settingsWindow.setContentSize(NSSize(width: 560, height: 480))
        settingsWindow.styleMask = [.titled, .closable, .resizable]
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        await settle(0.7)
        if let img = captureWindow(settingsWindow) {
            writePNG(img, to: outDir.appendingPathComponent("settings-general.png"))
            print("Wrote settings.png")
        } else {
            print("WARN: settings window not captured")
        }
        settingsWindow.close()

        // --- History: synthetic entries only (never show real local captures) ---
        let demoEntries = await seedSyntheticHistory(services: services)
        services.history.replaceEntriesForDocs(demoEntries)
        services.menuBar.showHistory()
        await settle(0.8)
        if let hist = NSApp.windows.first(where: {
            $0.isVisible && ($0.title.localizedCaseInsensitiveContains("History")
                || $0.title.localizedCaseInsensitiveContains("Historia")
                || ($0.frame.width >= 680 && $0.frame.width <= 800))
        }), let img = captureWindow(hist) {
            writePNG(img, to: outDir.appendingPathComponent("history-list.png"))
            print("Wrote history.png")
        }
        services.history.reloadFromDisk()

        if let menuImg = makeMenuBarShowcaseImage() {
            writePNG(menuImg, to: outDir.appendingPathComponent("menu-bar.png"))
            print("Wrote menu.png")
        }

        print("Docs screenshots → \(outDir.path)")
        exit(0)
    }

    private static func seedSyntheticHistory(services: AppServices) async -> [CaptureHistoryEntry] {
        let specs: [(String, String, String, CaptureKind, Int, Int, Bool)] = [
            ("Checkout bug", "Safari", "Checkout — Acme Store", .region, 1280, 800, true),
            ("API error toast", "Terminal", "zsh — screenforge", .window, 900, 560, false),
            ("Settings panel", "ScreenForge", "ScreenForge Settings", .window, 780, 520, false),
            ("Full desktop", "Finder", "Desktop", .fullDisplay, 1512, 982, false),
            ("Selection redo", "Xcode", "AppServices.swift", .lastRegion, 1100, 640, false),
        ]
        var result: [CaptureHistoryEntry] = []
        for (index, spec) in specs.enumerated() {
            let (title, app, window, kind, w, h, pinned) = spec
            let image: CGImage
            switch index {
            case 0: image = makeBugReportDemoImage(width: w, height: h)
            case 1: image = makeTerminalDemoImage(width: w, height: h)
            case 2: image = makeSettingsCardDemoImage(width: w, height: h)
            case 3: image = makeDesktopGradientDemo(width: w, height: h)
            default: image = makeCodeEditorDemoImage(width: w, height: h)
            }
            let id = UUID()
            let file = services.history.storeFullImage(image, id: id)
            let thumb = await services.thumbnails.thumbnail(from: image)
            result.append(CaptureHistoryEntry(
                id: id,
                createdAt: Date().addingTimeInterval(Double(-index) * 3600),
                kind: kind,
                sourceApp: app,
                sourceWindow: window,
                displayID: nil,
                width: image.width,
                height: image.height,
                filePath: file?.path,
                thumbnailPath: thumb?.path,
                wasCopied: index % 2 == 0,
                wasEdited: index < 2,
                pinned: pinned,
                title: title,
                tags: []
            ))
        }
        return result
    }

    private static func resolveOutputDirectory() -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        // …/ScreenForge/ScreenForge/App/DocsScreenshotRunner.swift → repo root docs/screenshots
        let repoRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fromSource = repoRoot.appendingPathComponent("docs/screenshots")
        let candidates = [
            fromSource,
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

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Demo canvases

    private static func makeBugReportDemoImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        drawWallpaper(ctx, width: width, height: height)

        let card = CGRect(x: CGFloat(width) * 0.12, y: CGFloat(height) * 0.1,
                          width: CGFloat(width) * 0.76, height: CGFloat(height) * 0.78)
        drawWindowChrome(ctx, card: card, title: "Acme Store — Checkout")

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        let titleFont = NSFont.systemFont(ofSize: 28, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 16)
        let mono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let labelColor = NSColor.labelColor
        let secondary = NSColor.secondaryLabelColor

        ("Order summary" as NSString).draw(
            at: CGPoint(x: card.minX + 36, y: card.maxY - 100),
            withAttributes: [.font: titleFont, .foregroundColor: labelColor]
        )

        let rows: [(String, String)] = [
            ("Plan", "Pro — annual"),
            ("Seats", "3× $16 / month"),
            ("Tax", "$4.80"),
            ("Total due today", "$52.80"),
        ]
        var y = card.maxY - 150
        for (label, value) in rows {
            (label as NSString).draw(
                at: CGPoint(x: card.minX + 36, y: y),
                withAttributes: [.font: bodyFont, .foregroundColor: secondary]
            )
            (value as NSString).draw(
                at: CGPoint(x: card.minX + 280, y: y),
                withAttributes: [.font: bodyFont, .foregroundColor: labelColor]
            )
            y -= 40
        }

        ("Customer email" as NSString).draw(
            at: CGPoint(x: card.minX + 36, y: y - 20),
            withAttributes: [.font: bodyFont, .foregroundColor: secondary]
        )
        ("alex.morgan@example.com" as NSString).draw(
            at: CGPoint(x: card.minX + 36, y: y - 48),
            withAttributes: [.font: mono, .foregroundColor: labelColor]
        )

        // Primary button
        let btn = CGRect(x: card.minX + 36, y: card.minY + 48, width: 180, height: 40)
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.beginPath()
        ctx.addPath(CGPath(roundedRect: btn, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
        ("Pay now" as NSString).draw(
            at: CGPoint(x: btn.minX + 54, y: btn.minY + 11),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
        )

        // Side note card
        let note = CGRect(x: card.maxX - 340, y: card.minY + 120, width: 280, height: 160)
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.beginPath()
        ctx.addPath(CGPath(roundedRect: note, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
        ("Promo applied" as NSString).draw(
            at: CGPoint(x: note.minX + 16, y: note.maxY - 36),
            withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: labelColor]
        )
        ("SAVE10 · 10% off seats\nBilling cycle: yearly\nNext renewal: Aug 2027" as NSString).draw(
            in: CGRect(x: note.minX + 16, y: note.minY + 16, width: 248, height: 100),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: secondary]
        )

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func makeTerminalDemoImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let green = NSColor.systemGreen
        let lines = [
            "$ curl https://api.acme.test/v1/orders/4821",
            "HTTP/1.1 500 Internal Server Error",
            "{\"error\":\"total_mismatch\",\"expected\":48.00,\"got\":52.80}",
            "$ screenforge --capture-region",
        ]
        var y = CGFloat(height) - 40
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: [.font: font, .foregroundColor: green])
            y -= 28
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func makeSettingsCardDemoImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("ScreenForge Settings" as NSString).draw(
            at: CGPoint(x: 28, y: CGFloat(height) - 48),
            withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.labelColor]
        )
        let items = ["Menu bar icon", "Check permissions on launch", "Launch at login", "Notifications"]
        var y = CGFloat(height) - 100
        for item in items {
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            ctx.fillEllipse(in: CGRect(x: 32, y: y + 4, width: 14, height: 14))
            (item as NSString).draw(
                at: CGPoint(x: 58, y: y),
                withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor]
            )
            y -= 36
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func makeCodeEditorDemoImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lines = [
            "func ensureScreenRecording() async -> Bool {",
            "    if permissions.hasScreenRecording { return true }",
            "    permissions.showPermissionsGateIfNeeded()",
            "    return false",
            "}",
        ]
        var y = CGFloat(height) - 48
        for (i, line) in lines.enumerated() {
            let color: NSColor = i == 2 ? .systemOrange : .systemGray
            ("\(i + 12)  \(line)" as NSString).draw(
                at: CGPoint(x: 20, y: y),
                withAttributes: [.font: font, .foregroundColor: color]
            )
            y -= 26
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func makeDesktopGradientDemo(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        drawWallpaper(ctx, width: width, height: height)
        return ctx.makeImage()!
    }

    private static func drawWallpaper(_ ctx: CGContext, width: Int, height: Int) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.78, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.72, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.62, alpha: 1).cgColor,
        ] as CFArray
        let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    }

    private static func drawWindowChrome(_ ctx: CGContext, card: CGRect, title: String) {
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.beginPath()
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.fillPath()

        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(CGRect(x: card.minX, y: card.maxY - 40, width: card.width, height: 40))

        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 14, y: card.maxY - 26, width: 10, height: 10))
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 30, y: card.maxY - 26, width: 10, height: 10))
        ctx.setFillColor(NSColor.systemGreen.cgColor)
        ctx.fillEllipse(in: CGRect(x: card.minX + 46, y: card.maxY - 26, width: 10, height: 10))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (title as NSString).draw(
            at: CGPoint(x: card.midX - 90, y: card.maxY - 28),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
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
        let desk = makeBugReportDemoImage(width: width, height: height)
        ctx.setAlpha(0.45)
        ctx.draw(desk, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setAlpha(1)

        ctx.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 0.92).cgColor)
        ctx.fill(CGRect(x: 0, y: height - 28, width: width, height: 28))
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("􀎼 ScreenForge" as NSString).draw(at: CGPoint(x: width - 160, y: height - 22), withAttributes: iconAttrs)

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
            "Quit",
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
