import XCTest
@testable import ScreenForge

@MainActor
final class EditorDocumentTests: XCTestCase {
    func testAddAndUndo() {
        let doc = EditorDocument(baseImage: nil, canvasSize: CGSize(width: 100, height: 100))
        let obj = CanvasObject(type: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.addObject(obj)
        XCTAssertEqual(doc.objects.count, 1)
        doc.undoCoordinator.undo()
        XCTAssertEqual(doc.objects.count, 0)
        doc.undoCoordinator.redo()
        XCTAssertEqual(doc.objects.count, 1)
    }

    func testLayerOrder() {
        let doc = EditorDocument(baseImage: nil, canvasSize: CGSize(width: 100, height: 100))
        let a = CanvasObject(type: .rectangle, frame: .zero)
        let b = CanvasObject(type: .ellipse, frame: .zero)
        doc.addObject(a)
        doc.addObject(b)
        doc.selection = [a.id]
        doc.bringToFront()
        let az = doc.objects.first { $0.id == a.id }!.zIndex
        let bz = doc.objects.first { $0.id == b.id }!.zIndex
        XCTAssertGreaterThan(az, bz)
    }

    func testDuplicate() {
        let doc = EditorDocument(baseImage: nil, canvasSize: CGSize(width: 100, height: 100))
        let a = CanvasObject(type: .rectangle, frame: CGRect(x: 1, y: 1, width: 5, height: 5))
        doc.addObject(a)
        doc.selection = [a.id]
        doc.duplicateSelected()
        XCTAssertEqual(doc.objects.count, 2)
    }

    func testDelete() {
        let doc = EditorDocument(baseImage: nil, canvasSize: CGSize(width: 100, height: 100))
        let a = CanvasObject(type: .rectangle, frame: .zero)
        doc.addObject(a)
        doc.selection = [a.id]
        doc.deleteSelected()
        XCTAssertTrue(doc.objects.isEmpty)
    }
}
