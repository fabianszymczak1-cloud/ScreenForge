import Foundation

/// Repairs macOS Tahoe Control Center "Allow in the Menu Bar" state for ScreenForge.
///
/// State lives in `group.com.apple.controlcenter` → `trackedApplications`.
/// A poisoned / missing entry means the app never appears in System Settings
/// even though `NSStatusItem` was created successfully.
enum MenuBarAllowListRepair {
    private static let groupPrefsURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter")
            .appendingPathComponent("Library/Preferences/group.com.apple.controlcenter.plist")
    }()

    private static let currentBundleID = "app.screenforge.mac"
    private static let legacyBundleIDs: Set<String> = [
        "app.screenforge.studio",
        "app.screenforge.bar",
        "app.screenforge.capture",
        "app.screenforge.macos",
        "com.screenforge.macos",
        "com.screenforge.app",
        "com.local.ScreenForge"
    ]

    /// Best-effort repair. No-ops when the Group Container is unreadable (TCC).
    @discardableResult
    static func runIfPossible() -> Bool {
        let url = groupPrefsURL
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            // Normal case: the Control Center group container is TCC-protected. Editing the list
            // is impossible, so all we can do is make Control Center re-read it.
            DiagnosticLog.shared.info("menubar.allowlist.unreadable")
            reloadControlCenter()
            return false
        }
        do {
            let data = try Data(contentsOf: url)
            guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return false
            }
            guard let trackedBlob = root["trackedApplications"] else {
                DiagnosticLog.shared.info("menubar.allowlist.noTrackedApplications")
                return false
            }

            let trackedData: Data
            if let d = trackedBlob as? Data {
                trackedData = d
            } else {
                trackedData = try PropertyListSerialization.data(fromPropertyList: trackedBlob, format: .binary, options: 0)
            }

            guard var list = try PropertyListSerialization.propertyList(
                from: trackedData,
                options: [.mutableContainers],
                format: nil
            ) as? [Any] else {
                return false
            }

            let changed = mutateTrackedList(&list)
            guard changed else {
                DiagnosticLog.shared.info("menubar.allowlist.unchanged")
                reloadControlCenter()
                return false
            }

            let newTracked = try PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
            root["trackedApplications"] = newTracked
            let out = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            try out.write(to: url, options: .atomic)

            reloadControlCenter()
            DiagnosticLog.shared.info("menubar.allowlist.repaired")
            return true
        } catch {
            DiagnosticLog.shared.error("menubar.allowlist.repairFailed \(error.localizedDescription)")
            reloadControlCenter()
            return false
        }
    }

    /// Makes Control Center re-read the allow list. Fixes a binding left stale by an app update;
    /// it cannot fix a bundle ID the list has poisoned — only Reset Control Center does that.
    static func reloadControlCenter() {
        // Order matters: preferences daemon first, then Control Center — see CodexBar #1440.
        for arguments in [["cfprefsd"], ["-9", "ControlCenter"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = arguments
            try? process.run()
            process.waitUntilExit()
        }
        DiagnosticLog.shared.info("menubar.controlCenter.reloaded")
    }

    /// Returns true when the list was modified.
    private static func mutateTrackedList(_ list: inout [Any]) -> Bool {
        var changed = false
        var foundCurrent = false
        var i = 0
        while i < list.count {
            guard let loc = list[i] as? [String: Any] else {
                i += 1
                continue
            }
            let bid = bundleID(from: loc)
            let hasState = i + 1 < list.count && list[i + 1] is [String: Any]
            guard let bid, hasState, var state = list[i + 1] as? [String: Any] else {
                i += 1
                continue
            }

            if bid == currentBundleID {
                foundCurrent = true
                if state["isAllowed"] as? Bool != true {
                    state["isAllowed"] = true
                    changed = true
                }
                // Ensure our own menuItemLocations include ourselves.
                var locs = (state["menuItemLocations"] as? [[String: Any]]) ?? []
                let hasSelf = locs.contains { bundleID(from: $0) == currentBundleID }
                if !hasSelf {
                    locs.append(["bundle": ["_0": currentBundleID]])
                    state["menuItemLocations"] = locs
                    changed = true
                }
                list[i + 1] = state
                i += 2
                continue
            }

            if legacyBundleIDs.contains(bid) {
                list.remove(at: i + 1)
                list.remove(at: i)
                changed = true
                continue
            }

            // CodexBar orphan pattern: another app's menuItemLocations lists ScreenForge.
            if var locs = state["menuItemLocations"] as? [[String: Any]] {
                let before = locs.count
                locs.removeAll { entry in
                    guard let id = bundleID(from: entry) else { return false }
                    return id == currentBundleID || legacyBundleIDs.contains(id)
                }
                if locs.count != before {
                    state["menuItemLocations"] = locs
                    list[i + 1] = state
                    changed = true
                }
            }
            i += 2
        }

        if !foundCurrent {
            let location: [String: Any] = ["bundle": ["_0": currentBundleID]]
            let state: [String: Any] = [
                "isAllowed": true,
                "location": location,
                "menuItemLocations": [location]
            ]
            list.append(location)
            list.append(state)
            changed = true
        }
        return changed
    }

    private static func bundleID(from location: [String: Any]) -> String? {
        if let bundle = location["bundle"] as? [String: Any], let id = bundle["_0"] as? String {
            return id
        }
        if let nested = location["location"] as? [String: Any] {
            return bundleID(from: nested)
        }
        return nil
    }
}
