import Foundation

final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    private let queue = DispatchQueue(label: "com.screenforge.app.log")
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ScreenForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("screenforge.log")
    }

    func info(_ message: String) { write("INFO", message) }
    func error(_ message: String) { write("ERROR", message) }
    func warn(_ message: String) { write("WARN", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                        defer { try? handle.close() }
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
    }
}
