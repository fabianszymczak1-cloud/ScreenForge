import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private var services: AppServices { AppServices.shared }
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var aboutWindow: NSWindow?

    init() {}

    func install() {
        guard services.settings.showMenuBarIcon else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenForge")
            button.image?.isTemplate = true
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, action: HotkeyAction?, selector: Selector) {
            let binding = action.flatMap { services.settings.hotkeyBindings[$0.rawValue] }
            let key = binding?.isEnabled == true ? Self.menuKey(binding!) : ""
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            if let binding, binding.isEnabled {
                item.keyEquivalentModifierMask = Self.modifierMask(binding)
            }
            menu.addItem(item)
        }
        add(String(localized: "Capture region"), action: .captureRegionEdit, selector: #selector(captureRegion))
        add(String(localized: "Capture window"), action: .captureWindowEdit, selector: #selector(captureWindow))
        add(String(localized: "Capture active display"), action: .captureActiveDisplay, selector: #selector(captureDisplay))
        add(String(localized: "Capture all displays"), action: .captureAllDisplays, selector: #selector(captureAll))
        add(String(localized: "Capture last region"), action: .captureLastRegionEdit, selector: #selector(captureLast))
        add(String(localized: "Capture with delay"), action: .captureDelayed, selector: #selector(captureDelayed))
        if services.settings.experimentalScrolling {
            let scroll = NSMenuItem(title: String(localized: "Scrolling capture (experimental)"), action: #selector(captureScrolling), keyEquivalent: "")
            scroll.target = self
            menu.addItem(scroll)
        }
        menu.addItem(.separator())
        add(String(localized: "Open history"), action: .openHistory, selector: #selector(showHistory))
        let openFile = NSMenuItem(title: String(localized: "Open image from file…"), action: #selector(openFile), keyEquivalent: "o")
        openFile.keyEquivalentModifierMask = [.command]
        openFile.target = self
        menu.addItem(openFile)
        let openClip = NSMenuItem(title: String(localized: "Open image from clipboard"), action: #selector(openClipboard), keyEquivalent: "")
        openClip.target = self
        menu.addItem(openClip)
        add(String(localized: "Last capture"), action: .openLastInEditor, selector: #selector(openLast))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: String(localized: "Launch at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = services.launchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        let perms = NSMenuItem(title: String(localized: "Check permissions"), action: #selector(checkPermissions), keyEquivalent: "")
        perms.target = self
        menu.addItem(perms)
        let about = NSMenuItem(title: String(localized: "About"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let updates = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let support = NSMenuItem(title: String(localized: "Buy Me a Coffee"), action: #selector(openSupport), keyEquivalent: "")
        support.target = self
        menu.addItem(support)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private static func menuKey(_ b: HotkeyBinding) -> String {
        // Map keycodes 18-28 to 1-8 roughly
        let map: [UInt32: String] = [18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8"]
        return map[b.keyCode] ?? ""
    }

    private static func modifierMask(_ b: HotkeyBinding) -> NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if b.modifiers & UInt32(controlKey) != 0 { m.insert(.control) }
        if b.modifiers & UInt32(optionKey) != 0 { m.insert(.option) }
        if b.modifiers & UInt32(shiftKey) != 0 { m.insert(.shift) }
        if b.modifiers & UInt32(cmdKey) != 0 { m.insert(.command) }
        return m
    }

    @objc func captureRegion() { Task { await services.captureRegion(destination: .editor) } }
    @objc func captureWindow() { Task { await services.captureWindow(destination: .editor) } }
    @objc func captureDisplay() { Task { await services.captureActiveDisplay(destination: .editor) } }
    @objc func captureAll() { Task { await services.captureAllDisplays(destination: .editor) } }
    @objc func captureLast() { Task { await services.captureLastRegion(destination: .editor) } }
    @objc func captureDelayed() {
        services.delayedCapture.start(seconds: services.settings.defaultDelaySeconds) { [weak self] in
            Task { await self?.services.captureRegion(destination: .editor) }
        }
    }
    @objc func captureScrolling() {
        Task { _ = await services.scrolling.captureScrollingRegion() }
    }
    @objc func showHistory() {
        if historyWindow == nil {
            let view = HistoryView()
                .environmentObject(services.history)
                .environmentObject(services.settings)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Capture history")
            window.setContentSize(NSSize(width: 720, height: 480))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.center()
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url {
            services.editorWindows.openImage(url: url)
        }
    }
    @objc func openClipboard() { services.editorWindows.openClipboard() }
    @objc func openLast() {
        if let e = services.history.latest() {
            services.editorWindows.openHistoryEntry(e, history: services.history)
        }
    }
    @objc func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleLogin() {
        try? services.launchAtLogin.setEnabled(!services.launchAtLogin.isEnabled)
        rebuildMenu()
    }
    @objc func checkPermissions() {
        services.permissions.refresh()
        services.permissions.showOnboardingIfNeeded(force: true)
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ScreenForge"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        alert.informativeText = String(localized: "Version \(version). Local screenshots for macOS. No telemetry, no cloud.")
        alert.addButton(withTitle: String(localized: "Buy Me a Coffee"))
        alert.addButton(withTitle: String(localized: "Close"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(SupportLinks.buyMeACoffee)
        }
    }
    @objc func checkForUpdates() { UpdateController.shared.checkForUpdates() }
    @objc func openSupport() { NSWorkspace.shared.open(SupportLinks.buyMeACoffee) }
    @objc func quit() { NSApp.terminate(nil) }
}

import Carbon.HIToolbox
