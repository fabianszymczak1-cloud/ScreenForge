import XCTest
@testable import ScreenForge

final class SensitiveDetectionTests: XCTestCase {
    func testEmailAndIP() {
        let svc = SensitiveDataDetectionService()
        let findings = svc.detect(in: "Kontakt: jan@example.com serwer 192.168.0.1")
        XCTAssertTrue(findings.contains { $0.kind == "email" && $0.value.contains("jan@") })
        XCTAssertTrue(findings.contains { $0.kind == "ip" && $0.value == "192.168.0.1" })
    }

    func testCardLuhn() {
        let svc = SensitiveDataDetectionService()
        // Visa test number that passes Luhn
        let findings = svc.detect(in: "Karta: 4111 1111 1111 1111")
        XCTAssertTrue(findings.contains { $0.kind == "card" })
    }

    func testRejectInvalidCard() {
        let svc = SensitiveDataDetectionService()
        let findings = svc.detect(in: "Numer: 1234 5678 9012 3456")
        XCTAssertFalse(findings.contains { $0.kind == "card" })
    }

    func testPESEL() {
        let svc = SensitiveDataDetectionService()
        // Valid PESEL (known test): 44051401359
        let findings = svc.detect(in: "PESEL 44051401359")
        XCTAssertTrue(findings.contains { $0.kind == "pesel" })
    }

    func testVisionRectConversion() {
        let size = CGSize(width: 1000, height: 500)
        // Vision box at top of image: origin.y near 1
        let vision = CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)
        let doc = OCRService.visionNormalizedToTopLeft(vision, imageSize: size)
        XCTAssertEqual(doc.origin.x, 100, accuracy: 0.1)
        XCTAssertEqual(doc.origin.y, 50, accuracy: 0.1) // (1 - 0.8 - 0.1) * 500 = 50
        XCTAssertEqual(doc.width, 200, accuracy: 0.1)
        XCTAssertEqual(doc.height, 50, accuracy: 0.1)
    }
}
