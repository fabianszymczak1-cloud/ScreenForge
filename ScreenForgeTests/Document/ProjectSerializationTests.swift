import XCTest
@testable import ScreenForge

@MainActor
final class ProjectSerializationTests: XCTestCase {
    func testRoundTrip() throws {
        let doc = EditorDocument(baseImage: nil, canvasSize: CGSize(width: 200, height: 100))
        var obj = CanvasObject(type: .arrow, frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        obj.text = "test ąćę"
        doc.addObject(obj)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).screenforge")
        try ProjectDocumentSerializer.save(document: doc, to: url)
        let loaded = try ProjectDocumentSerializer.load(from: url)
        XCTAssertEqual(loaded.canvasSize.width, 200)
        XCTAssertEqual(loaded.objects.count, 1)
        XCTAssertEqual(loaded.objects.first?.text, "test ąćę")
        try? FileManager.default.removeItem(at: url)
    }
}
