import XCTest
@testable import ScreenForge

/// Tahoe keys the Menu Bar allow list to the bundle ID, and an entry it stopped matching stays
/// broken — measured on `app.screenforge.bar` and `app.screenforge.studio`, which no reset,
/// toggle or reinstall revived. Changing this string is a breaking change, not a rename.
final class BundleIdentityTests: XCTestCase {
    func testBundleIdentifierIsTheOneRegisteredInMenuBarAllowList() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.screenforge.mac")
    }

    func testBurnedIdentitiesStayOnTheTCCResetList() {
        XCTAssertTrue(PermissionManager.legacyScreenCaptureBundleIDs.contains("app.screenforge.bar"))
        XCTAssertTrue(PermissionManager.legacyScreenCaptureBundleIDs.contains("app.screenforge.studio"))
    }

    func testRunsAsAgentApp() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testShortVersionIsPresent() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertNotNil(version)
        XCTAssertFalse(version?.isEmpty ?? true)
    }
}
