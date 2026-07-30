import Foundation

final class PerformanceMonitor: @unchecked Sendable {
    static let shared = PerformanceMonitor()
    private let lock = NSLock()
    private var marks: [String: CFAbsoluteTime] = [:]
    var isEnabled: Bool = false

    func begin(_ name: String) {
        guard isEnabled else { return }
        lock.lock(); marks[name] = CFAbsoluteTimeGetCurrent(); lock.unlock()
    }

    func end(_ name: String) -> Double? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let start = marks.removeValue(forKey: name) else { return nil }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        DiagnosticLog.shared.info("perf.\(name)=\(String(format: "%.1f", ms))ms")
        return ms
    }

    func log(_ event: String) {
        guard isEnabled else { return }
        DiagnosticLog.shared.info(event)
    }

    func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        begin(name)
        defer { _ = end(name) }
        return try block()
    }
}
