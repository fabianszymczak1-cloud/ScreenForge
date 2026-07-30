import XCTest
@testable import ScreenForge

@MainActor
final class LastRegionTests: XCTestCase {
    func testSaveAndResolve() {
        let store = LastRegionStore()
        store.save(
            displayID: CGMainDisplayID(),
            pixelRect: CGRect(x: 10, y: 10, width: 100, height: 50),
            pointRect: CGRect(x: 5, y: 5, width: 50, height: 25),
            layoutSignature: "test",
            scale: 2,
            kind: .region
        )
        XCTAssertNotNil(store.last)
        XCTAssertEqual(store.last?.pixelRect.w, 100)
    }
}
