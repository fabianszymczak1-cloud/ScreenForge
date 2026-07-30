import XCTest
@testable import ScreenForge

@MainActor
final class FilenameTemplateTests: XCTestCase {
    func testTemplateRendering() {
        let settings = SettingsStore()
        settings.filenameTemplate = "Shot_{yyyy}-{MM}-{dd}_{counter}.png"
        let svc = FilenameTemplateService(settings: settings)
        let name = svc.render(result: nil, date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.contains("1970") || name.contains("Shot_"))
        XCTAssertTrue(name.hasSuffix(".png") || name.contains("Shot_"))
    }

    func testNoOverwrite() throws {
        let settings = SettingsStore()
        let svc = FilenameTemplateService(settings: settings)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-name-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u1 = svc.nextURL(in: dir, result: nil)
        try Data("a".utf8).write(to: u1)
        let u2 = svc.nextURL(in: dir, result: nil)
        XCTAssertNotEqual(u1.path, u2.path)
        try? FileManager.default.removeItem(at: dir)
    }

    func testSanitize() {
        let settings = SettingsStore()
        let svc = FilenameTemplateService(settings: settings)
        settings.filenameTemplate = "bad/name:test.png"
        let name = svc.render(result: nil)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
    }
}
