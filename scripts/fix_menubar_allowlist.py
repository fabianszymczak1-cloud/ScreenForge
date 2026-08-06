#!/usr/bin/env python3
"""Repair Tahoe Menu Bar allow-list entry for ScreenForge (app.screenforge.studio).

Reads/writes:
  ~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist
  key: trackedApplications

Run from Terminal (Full Disk Access helps). Then relaunch ScreenForge from /Applications.
"""
from __future__ import annotations

import os
import plistlib
import subprocess
import sys
from pathlib import Path

CURRENT = "app.screenforge.mac"
LEGACY = {
    "app.screenforge.studio",
    "app.screenforge.bar",
    "app.screenforge.capture",
    "app.screenforge.macos",
    "com.screenforge.macos",
    "com.screenforge.app",
    "com.local.ScreenForge",
}

PREFS = (
    Path.home()
    / "Library/Group Containers/group.com.apple.controlcenter"
    / "Library/Preferences/group.com.apple.controlcenter.plist"
)


def bundle_id(obj):
    if not isinstance(obj, dict):
        return None
    b = obj.get("bundle")
    if isinstance(b, dict) and "_0" in b:
        return b["_0"]
    if isinstance(b, str):
        return b
    if "location" in obj:
        return bundle_id(obj["location"])
    return None


def mutate(tracked: list) -> bool:
    changed = False
    found = False
    i = 0
    while i < len(tracked):
        loc = tracked[i]
        bid = bundle_id(loc) if isinstance(loc, dict) else None
        has_state = i + 1 < len(tracked) and isinstance(tracked[i + 1], dict)
        if not (bid and has_state):
            i += 1
            continue
        state = tracked[i + 1]

        if bid == CURRENT:
            found = True
            if state.get("isAllowed") is not True:
                state["isAllowed"] = True
                changed = True
            locs = state.get("menuItemLocations") or []
            if not any(bundle_id(x) == CURRENT for x in locs if isinstance(x, dict)):
                locs.append({"bundle": {"_0": CURRENT}})
                state["menuItemLocations"] = locs
                changed = True
            tracked[i + 1] = state
            i += 2
            continue

        if bid in LEGACY:
            del tracked[i + 1]
            del tracked[i]
            changed = True
            continue

        locs = state.get("menuItemLocations")
        if isinstance(locs, list):
            new_locs = [
                x
                for x in locs
                if not (
                    isinstance(x, dict)
                    and (bid2 := bundle_id(x))
                    and (bid2 == CURRENT or bid2 in LEGACY)
                )
            ]
            if len(new_locs) != len(locs):
                state["menuItemLocations"] = new_locs
                tracked[i + 1] = state
                changed = True
        i += 2

    if not found:
        location = {"bundle": {"_0": CURRENT}}
        tracked.append(location)
        tracked.append(
            {
                "isAllowed": True,
                "location": location,
                "menuItemLocations": [location],
            }
        )
        changed = True
    return changed


def main() -> int:
    if not PREFS.exists():
        print(f"Missing: {PREFS}", file=sys.stderr)
        return 1
    backup = Path("/tmp/cc-group-backup.plist")
    backup.write_bytes(PREFS.read_bytes())
    print(f"Backup: {backup}")

    with PREFS.open("rb") as f:
        root = plistlib.load(f)

    tracked_blob = root.get("trackedApplications")
    if tracked_blob is None:
        print("No trackedApplications key", file=sys.stderr)
        return 1
    if isinstance(tracked_blob, (bytes, bytearray)):
        tracked = plistlib.loads(tracked_blob)
    else:
        tracked = tracked_blob
    if not isinstance(tracked, list):
        print(f"Unexpected trackedApplications type: {type(tracked)}", file=sys.stderr)
        return 1

    if not mutate(tracked):
        print("No changes needed.")
        return 0

    root["trackedApplications"] = plistlib.dumps(tracked, fmt=plistlib.FMT_BINARY)
    with PREFS.open("wb") as f:
        plistlib.dump(root, f, fmt=plistlib.FMT_BINARY)
    print(f"Updated allow-list for {CURRENT}")

    subprocess.run(["killall", "cfprefsd"], check=False)
    subprocess.run(["killall", "-9", "ControlCenter"], check=False)
    print("Restarted Control Center. Quit and reopen /Applications/ScreenForge.app")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PermissionError:
        print(
            "Permission denied reading Control Center prefs.\n"
            "Grant Terminal Full Disk Access (System Settings → Privacy → Full Disk Access),\n"
            "or click Reset Control Center… in System Settings → Menu Bar, then relaunch ScreenForge.",
            file=sys.stderr,
        )
        raise SystemExit(2)
