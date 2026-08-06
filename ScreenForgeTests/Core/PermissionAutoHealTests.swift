import XCTest
@testable import ScreenForge

/// Auto-heal decides whether macOS silently skipped the system sheet because a dead TCC row
/// (older CDHash, same bundle ID) already holds a decision.
@MainActor
final class PermissionAutoHealTests: XCTestCase {
    func testHealsWhenSheetNeverAppeared() {
        XCTAssertTrue(PermissionManager.shouldAutoHealTCC(
            requestResult: false,
            preflightAfterRequest: false,
            alreadyHealedThisLaunch: false
        ))
    }

    func testHealsOnlyOncePerLaunch() {
        XCTAssertFalse(PermissionManager.shouldAutoHealTCC(
            requestResult: false,
            preflightAfterRequest: false,
            alreadyHealedThisLaunch: true
        ))
    }

    func testDoesNotHealWhenRequestSucceeded() {
        XCTAssertFalse(PermissionManager.shouldAutoHealTCC(
            requestResult: true,
            preflightAfterRequest: false,
            alreadyHealedThisLaunch: false
        ))
    }

    func testDoesNotHealWhenAlreadyGranted() {
        XCTAssertFalse(PermissionManager.shouldAutoHealTCC(
            requestResult: false,
            preflightAfterRequest: true,
            alreadyHealedThisLaunch: false
        ))
    }

    func testLegacyIdsCoverEveryRetiredBundleIdentifier() {
        let legacy = PermissionManager.legacyScreenCaptureBundleIDs
        XCTAssertTrue(legacy.contains("app.screenforge.bar"))
        XCTAssertTrue(legacy.contains("app.screenforge.capture"))
        XCTAssertTrue(legacy.contains("app.screenforge.macos"))
        XCTAssertTrue(legacy.contains("com.local.ScreenForge"))
        XCTAssertFalse(legacy.contains(Bundle.main.bundleIdentifier ?? ""))
    }
}
