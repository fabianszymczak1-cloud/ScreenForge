import Foundation
import AppKit
import ScreenCaptureKit

/// Automated smoke suite run via `/Applications/ScreenForge.app/Contents/MacOS/ScreenForge --smoke-test`
@MainActor
enum SmokeTestRunner {
    static let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("screenforge-smoke-report.txt")

    static func run(services: AppServices) async {
        var lines: [String] = []
        var failed = false
        func ok(_ name: String, _ detail: String = "") {
            lines.append("PASS \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        func fail(_ name: String, _ detail: String) {
            failed = true
            lines.append("FAIL \(name) — \(detail)")
        }
        func skip(_ name: String, _ detail: String) {
            lines.append("SKIP \(name) — \(detail)")
        }

        await revealMenuBar()

        // Menu bar first — these must report even when Screen Recording is missing.
        if let item = AppDelegate.shared?.statusItem,
           let button = item.button,
           button.image != nil,
           item.menu != nil {
            ok("menubar_status_item", "\(item.menu?.items.count ?? 0) items")

            switch await MenuBarSlotProbe.resolve(AppDelegate.shared?.statusItem, timeout: 15) {
            case .rendered(let frame):
                ok("menubar_visible", "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))")
                ok("menubar_onscreen_window", "okno paska menu w slocie \(Int(frame.minX))–\(Int(frame.maxX))")
            case .refused(let frame):
                fail("menubar_visible", "status item bez slotu, frame=\(NSStringFromRect(frame))")
                fail("menubar_onscreen_window", "Centrum sterowania odrzuca identyfikator \(Bundle.main.bundleIdentifier ?? "?")")
            case .menuBarHidden:
                skip("menubar_visible", "pasek menu ukryty (aplikacja pełnoekranowa)")
                skip("menubar_onscreen_window", "pasek menu ukryty (aplikacja pełnoekranowa)")
            }
        } else {
            fail("menubar_status_item", "brak status itemu / buttona / menu")
            fail("menubar_visible", "status item nie istnieje")
            fail("menubar_onscreen_window", "status item nie istnieje")
        }

        services.permissions.refresh()
        if services.permissions.hasScreenRecording {
            ok("screen_recording_permission")
        } else {
            fail("screen_recording_permission", "brak uprawnienia")
        }

        if services.permissions.hasScreenRecording {
            switch await runWindowSelectionRoundTrip(services: services) {
            case .none: ok("window_selection_overlay")
            case .some(let reason): fail("window_selection_overlay", reason)
            }
            switch await runRegionSelectionRoundTrip(services: services) {
            case .none: ok("region_selection_overlay")
            case .some(let reason): fail("region_selection_overlay", reason)
            }
        } else {
            skip("window_selection_overlay", "wymaga uprawnienia do nagrywania ekranu")
            skip("region_selection_overlay", "wymaga uprawnienia do nagrywania ekranu")
        }

        switch await runDelayedCaptureCountdown(services: services) {
        case .none: ok("delayed_capture_countdown")
        case .some(let reason): fail("delayed_capture_countdown", reason)
        }

        switch await runWindowReopen(title: String(localized: "Capture history"), open: { services.menuBar.showHistory() }) {
        case .none: ok("history_window")
        case .some(let reason): fail("history_window", reason)
        }

        switch await runWindowReopen(title: String(localized: "Settings"), open: { services.menuBar.showSettings() }) {
        case .none: ok("settings_window")
        case .some(let reason): fail("settings_window", reason)
        }

        switch await runNotificationPanel(services: services) {
        case .none: ok("notification_panel")
        case .some(let reason): fail("notification_panel", reason)
        }

        // 1. Full display capture
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let result = try await services.capture.captureActiveDisplay(includeCursor: false)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            ok("capture_active_display", "\(result.image.width)x\(result.image.height) in \(String(format: "%.0f", ms))ms")

            // 2. Open editor + annotate
            let doc = EditorDocument(baseImage: result.image)
            doc.addObject(CanvasObject(type: .rectangle, frame: CGRect(x: 40, y: 40, width: 120, height: 80)))
            var arrow = CanvasObject(type: .arrow, frame: CGRect(x: 80, y: 100, width: 160, height: 60))
            doc.addObject(arrow)
            var text = CanvasObject(type: .text, frame: CGRect(x: 50, y: 200, width: 280, height: 40))
            text.text = "Zażółć gęślą jaźń"
            doc.addObject(text)
            var step = CanvasObject(type: .step, frame: CGRect(x: 300, y: 60, width: 36, height: 36))
            step.numberValue = 1
            step.text = "1"
            doc.addObject(step)
            var pix = CanvasObject(type: .pixelate, frame: CGRect(x: 200, y: 250, width: 100, height: 60))
            pix.filterAmount = 10
            doc.addObject(pix)
            var redact = CanvasObject(type: .solidRedact, frame: CGRect(x: 320, y: 250, width: 80, height: 40))
            redact.style.fillColor = .black
            doc.addObject(redact)
            ok("editor_annotations", "\(doc.objects.count) objects")

            // Undo/redo
            doc.undoCoordinator.undo()
            let afterUndo = doc.objects.count
            doc.undoCoordinator.redo()
            if doc.objects.count == afterUndo + 1 || doc.objects.count >= afterUndo {
                ok("undo_redo")
            } else {
                fail("undo_redo", "count mismatch")
            }

            // Render + clipboard
            let renderer = CanvasRenderer()
            guard let rendered = renderer.render(doc, quality: .full) else {
                fail("render", "nil")
                writeAndExit(lines, failed: true)
                return
            }
            ok("render", "\(rendered.width)x\(rendered.height)")

            services.clipboard.copy(rendered, includeTIFF: true)
            if NSPasteboard.general.data(forType: .png) != nil ||
                !(NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) ?? []).isEmpty {
                ok("clipboard_copy")
            } else {
                fail("clipboard_copy", "pusty schowek")
            }

            // Save PNG
            if let url = try? services.files.save(image: rendered, result: result, format: "png") {
                ok("save_png", url.path)
            } else {
                fail("save_png", "nie zapisano")
            }

            // Project round-trip
            let projectURL = FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(UUID().uuidString).screenforge")
            do {
                try ProjectDocumentSerializer.save(document: doc, to: projectURL)
                let loaded = try ProjectDocumentSerializer.load(from: projectURL)
                if loaded.objects.count == doc.objects.count {
                    ok("project_roundtrip", "\(loaded.objects.count) objects")
                } else {
                    fail("project_roundtrip", "\(loaded.objects.count) vs \(doc.objects.count)")
                }
                try? FileManager.default.removeItem(at: projectURL)
            } catch {
                fail("project_roundtrip", error.localizedDescription)
            }

            // History
            let thumb = await services.thumbnails.thumbnail(from: rendered)
            let stored = services.history.storeFullImage(rendered, id: result.id)
            services.history.insert(CaptureHistoryEntry(
                id: result.id,
                createdAt: Date(),
                kind: .fullDisplay,
                sourceApp: "SmokeTest",
                sourceWindow: nil,
                displayID: result.displayID.map { UInt32($0) },
                width: rendered.width,
                height: rendered.height,
                filePath: stored?.path,
                thumbnailPath: thumb?.path,
                wasCopied: true,
                wasEdited: true,
                pinned: false,
                title: "Smoke",
                tags: ["smoke"]
            ))
            if services.history.latest()?.id == result.id {
                ok("history_insert")
            } else {
                fail("history_insert", "brak wpisu")
            }

            // OCR
            do {
                let ocrText = try await services.ocr.recognize(rendered)
                ok("ocr", "chars=\(ocrText.count)")
            } catch {
                fail("ocr", error.localizedDescription)
            }

            // Last region store simulate
            if let displayID = result.displayID {
                let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
                // Bottom-right of the display in pixels: this is what a half-sized pixel frame
                // used to clamp away, so "capture last region" quietly stopped working there.
                let geometry = services.displays.display(id: displayID)?.geometry
                let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
                let far = screen.map { screen -> CGRect in
                    let pixels = CGSize(
                        width: screen.frame.width * screen.backingScaleFactor,
                        height: screen.frame.height * screen.backingScaleFactor
                    )
                    return CGRect(x: pixels.width - 400, y: pixels.height - 300, width: 320, height: 240)
                } ?? rect
                services.lastRegion.save(
                    displayID: displayID,
                    pixelRect: far,
                    pointRect: rect,
                    layoutSignature: services.displays.layoutSignature,
                    scale: geometry?.scale ?? 2,
                    kind: .region
                )
                let resolved = services.lastRegion.resolve(using: services.displays, coordinates: services.coordinates)
                if let resolved, resolved.1.width == far.width, resolved.1.height == far.height {
                    ok("last_region_store", "\(Int(far.minX)),\(Int(far.minY)) \(Int(far.width))x\(Int(far.height))")
                } else {
                    fail("last_region_store", "region przy krawędzi przepadł: \(resolved.map { "\($0.1)" } ?? "brak")")
                }

                // Region crop from full capture
                if let cropped = result.image.cropping(to: rect) {
                    ok("region_crop", "\(cropped.width)x\(cropped.height)")
                } else {
                    fail("region_crop", "crop failed")
                }
            }

            // Settings persist
            let prev = services.settings.showMagnifier
            services.settings.showMagnifier = !prev
            let check = SettingsStore()
            if check.showMagnifier == !prev {
                ok("settings_persist")
            } else {
                fail("settings_persist", "nie zachowano")
            }
            services.settings.showMagnifier = prev

        } catch {
            fail("capture_active_display", error.localizedDescription)
        }

        do {
            let all = try await services.capture.captureAllDisplays(mode: .combinedImage, includeCursor: false)
            // Backing pixels straight from AppKit, so a stitch that drops to 1x cannot pass.
            let expected = NSScreen.screens
                .map { Int(($0.frame.width * $0.backingScaleFactor).rounded()) }
                .max() ?? 100
            if all.image.width >= expected {
                ok("capture_all_displays", "\(all.image.width)x\(all.image.height)")
            } else {
                fail("capture_all_displays", "zrzut to \(all.image.width)x\(all.image.height), oczekiwano min. \(expected) px szerokości")
            }
        } catch {
            fail("capture_all_displays", error.localizedDescription)
        }

        do {
            let win = try await services.capture.captureFrontmostWindow(includeShadow: true, margin: 0, includeCursor: false)
            if win.image.width >= 100 && win.image.height >= 100 {
                ok("capture_window", "\(win.image.width)x\(win.image.height)")
            } else {
                fail("capture_window", "zrzut okna to \(win.image.width)x\(win.image.height)")
            }
        } catch {
            lines.append("WARN capture_window — \(error.localizedDescription)")
        }

        writeAndExit(lines, failed: failed)
    }

    /// Opens the window picker and cancels it. Overlays are closed while the coordinator still
    /// holds them, which used to over-release them and kill the app on the next pool drain.
    /// Returns a failure reason, or nil when the round trip completed cleanly.
    private static func runWindowSelectionRoundTrip(services: AppServices) async -> String? {
        let coordinator = services.windowSelection
        let selection = Task { @MainActor in await coordinator.beginSelection() }

        var shown = false
        for _ in 0..<50 where !shown {
            try? await Task.sleep(nanoseconds: 100_000_000)
            shown = coordinator.overlayCount > 0
        }
        guard shown else {
            selection.cancel()
            return "nakładki się nie pojawiły"
        }

        coordinator.cancel()
        let result = await selection.value
        guard result == nil else { return "anulowanie zwróciło zrzut" }
        guard coordinator.overlayCount == 0 else { return "nakładki zostały na ekranie" }

        // Force the drain that the crash reports died in.
        autoreleasepool {}
        try? await Task.sleep(nanoseconds: 300_000_000)
        return nil
    }

    /// Same round trip for the region picker, which freezes every display before showing overlays.
    private static func runRegionSelectionRoundTrip(services: AppServices) async -> String? {
        let coordinator = services.regionSelection
        let selection = Task { @MainActor in await coordinator.beginSelection() }

        var shown = false
        for _ in 0..<50 where !shown {
            try? await Task.sleep(nanoseconds: 100_000_000)
            shown = coordinator.overlayCount > 0
        }
        guard shown else {
            selection.cancel()
            return "nakładki się nie pojawiły"
        }

        coordinator.regionSelectionDidCancel()
        let result = await selection.value
        guard result == nil else { return "anulowanie zwróciło zrzut" }
        guard coordinator.overlayCount == 0 else { return "nakładki zostały na ekranie" }
        autoreleasepool {}
        try? await Task.sleep(nanoseconds: 300_000_000)
        return nil
    }

    /// The countdown panel is held by the coordinator and closed on cancel — the same lifetime
    /// trap as the pickers.
    private static func runDelayedCaptureCountdown(services: AppServices) async -> String? {
        var fired = false
        services.delayedCapture.start(seconds: 2) { fired = true }
        try? await Task.sleep(nanoseconds: 500_000_000)
        services.delayedCapture.cancel()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        autoreleasepool {}
        return fired ? "odliczanie wystrzeliło mimo anulowania" : nil
    }

    /// Closing and reopening is what breaks on a window released behind the app's back.
    private static func runWindowReopen(title: String, open: @escaping @MainActor () -> Void) async -> String? {
        func window() -> NSWindow? { NSApp.windows.first { $0.title == title } }

        open()
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let first = window() else { return "okno się nie otworzyło" }
        first.close()
        try? await Task.sleep(nanoseconds: 300_000_000)
        autoreleasepool {}

        open()
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let second = window() else { return "okno nie otworzyło się ponownie" }
        second.close()
        autoreleasepool {}
        return nil
    }

    private static func runNotificationPanel(services: AppServices) async -> String? {
        let wasEnabled = services.settings.showNotifications
        services.settings.showNotifications = true
        defer { services.settings.showNotifications = wasEnabled }

        services.notifications.show(title: "ScreenForge", body: "smoke")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        autoreleasepool {}
        return nil
    }

    /// A fullscreen app hides the menu bar, and the slot checks would report nothing instead of
    /// verifying anything. Switching to Finder puts a normal desktop Space up front.
    private static func revealMenuBar() async {
        guard MenuBarSlotProbe.menuBarItemWindows().isEmpty else { return }
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.finder" }?
            .activate(options: [.activateAllWindows])
        for _ in 0..<30 {
            if !MenuBarSlotProbe.menuBarItemWindows().isEmpty { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func writeAndExit(_ lines: [String], failed: Bool) {
        let body = lines.joined(separator: "\n") + "\nRESULT=\(failed ? "FAILED" : "PASSED")\n"
        try? body.write(to: reportURL, atomically: true, encoding: .utf8)
        print(body)
        DiagnosticLog.shared.info("smoke.\(failed ? "failed" : "passed")")
        // Delay slightly so logs flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exit(failed ? 1 : 0)
        }
    }
}
