import XCTest
@testable import ScreenForge

@MainActor
final class HistoryRetentionTests: XCTestCase {
    func testInsertAndLatest() {
        let repo = CaptureHistoryRepository()
        repo.open()
        let id = UUID()
        repo.insert(CaptureHistoryEntry(
            id: id, createdAt: Date(), kind: .region, sourceApp: "Test", sourceWindow: nil,
            displayID: 1, width: 10, height: 10, filePath: nil, thumbnailPath: nil,
            wasCopied: true, wasEdited: false, pinned: false, title: "t", tags: []
        ))
        XCTAssertEqual(repo.latest()?.id, id)
        repo.delete(id)
        repo.close()
    }
}
