import Foundation
import CoreGraphics

struct SensitiveFinding: Identifiable, Sendable {
    let id: UUID
    let kind: String
    let value: String
    let range: Range<String.Index>?

    init(kind: String, value: String, range: Range<String.Index>?) {
        self.id = UUID()
        self.kind = kind
        self.value = value
        self.range = range
    }

    var titlePL: String {
        switch kind {
        case "email": return "E-mail"
        case "phone": return "Telefon"
        case "ip": return "Adres IP"
        case "api_token": return "Token API"
        case "uuid": return "UUID"
        case "card": return "Payment card"
        case "pesel": return "PESEL"
        case "iban": return "IBAN"
        case "secret_param": return "Sekret w URL"
        case "custom": return "Custom pattern"
        default: return kind
        }
    }
}

struct SensitiveRegion: Identifiable, Sendable {
    let id: UUID
    let kind: String
    let value: String
    /// Document / image pixels, top-left origin.
    let rect: CGRect

    init(kind: String, value: String, rect: CGRect) {
        self.id = UUID()
        self.kind = kind
        self.value = value
        self.rect = rect
    }
}

final class SensitiveDataDetectionService: Sendable {
    func detect(in text: String, customRegexes: [String] = []) -> [SensitiveFinding] {
        var findings: [SensitiveFinding] = []
        var covered = IndexSet()

        let patterns: [(String, String)] = [
            ("email", #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#),
            ("iban", #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]){11,30}\b"#),
            ("card", #"\b(?:\d[ \-]*){13,19}\b"#),
            ("pesel", #"\b\d{11}\b"#),
            ("uuid", #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#),
            ("api_token", #"\b(?:sk|pk|rk|api)[_-][A-Za-z0-9_\-]{16,}\b"#),
            ("secret_param", #"(?i)(?:password|passwd|pwd|token|secret|api[_-]?key|access[_-]?key)\s*[=:]\s*\S+"#),
            ("ip", #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#),
            ("phone", #"(?:\+\d{1,3}[\s\-]?)?(?:\(?\d{2,4}\)?[\s\-]?)?\d{3}[\s\-]?\d{2,4}[\s\-]?\d{2,4}"#),
        ]

        for (kind, pattern) in patterns + customRegexes.map({ ("custom", $0) }) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let full = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match, let r = Range(match.range, in: text) else { return }
                let ns = match.range
                // Skip overlaps with higher-priority matches already recorded
                if covered.intersects(integersIn: ns.location..<(ns.location + ns.length)) { return }

                let value = String(text[r])
                switch kind {
                case "card":
                    guard luhn(value.filter(\.isNumber)) else { return }
                case "pesel":
                    guard isValidPESEL(value) else { return }
                case "phone":
                    let digits = value.filter(\.isNumber)
                    guard digits.count >= 9, digits.count <= 15 else { return }
                    // Avoid dimensions / versions like 3024x1964, 1.2.3
                    if value.contains("x") || value.contains("×") { return }
                case "ip":
                    let parts = value.split(separator: ".").compactMap { Int($0) }
                    guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return }
                default:
                    break
                }

                covered.insert(integersIn: ns.location..<(ns.location + ns.length))
                findings.append(SensitiveFinding(kind: kind, value: value, range: r))
            }
        }
        return findings
    }

    private func luhn(_ digits: String) -> Bool {
        guard digits.count >= 13, digits.count <= 19 else { return false }
        var sum = 0
        let reversed = digits.reversed().map { Int(String($0)) ?? 0 }
        for (i, d) in reversed.enumerated() {
            if i % 2 == 1 {
                let v = d * 2
                sum += v > 9 ? v - 9 : v
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    private func isValidPESEL(_ value: String) -> Bool {
        guard value.count == 11, value.allSatisfy(\.isNumber) else { return false }
        let w = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]
        let digits = value.compactMap { Int(String($0)) }
        guard digits.count == 11 else { return false }
        let sum = zip(digits.prefix(10), w).reduce(0) { $0 + $1.0 * $1.1 }
        let check = (10 - (sum % 10)) % 10
        return check == digits[10]
    }
}
