import Foundation

@MainActor
final class FilenameTemplateService {
    private let settings: SettingsStore
    private var counter = 1

    init(settings: SettingsStore) {
        self.settings = settings
        counter = UserDefaults.standard.integer(forKey: "sf.fileCounter")
        if counter <= 0 { counter = 1 }
    }

    func render(template: String? = nil, result: CaptureResult?, date: Date = Date()) -> String {
        let tpl = template ?? settings.filenameTemplate
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let M = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let H = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        var out = tpl
        out = out.replacingOccurrences(of: "{yyyy}", with: String(format: "%04d", y))
        out = out.replacingOccurrences(of: "{MM}", with: String(format: "%02d", M))
        out = out.replacingOccurrences(of: "{dd}", with: String(format: "%02d", d))
        out = out.replacingOccurrences(of: "{HH}", with: String(format: "%02d", H))
        out = out.replacingOccurrences(of: "{mm}", with: String(format: "%02d", m))
        out = out.replacingOccurrences(of: "{ss}", with: String(format: "%02d", s))
        out = out.replacingOccurrences(of: "{counter}", with: String(format: "%03d", counter))
        out = out.replacingOccurrences(of: "{app}", with: sanitize(result?.sourceAppName ?? "Screen"))
        out = out.replacingOccurrences(of: "{window}", with: sanitize(result?.sourceWindowTitle ?? "Window"))
        out = out.replacingOccurrences(of: "{type}", with: result?.kind.rawValue ?? "capture")
        out = out.replacingOccurrences(of: "{width}", with: "\(result?.image.width ?? 0)")
        out = out.replacingOccurrences(of: "{height}", with: "\(result?.image.height ?? 0)")
        return sanitizeFilename(out)
    }

    func nextURL(in directory: URL, result: CaptureResult?) -> URL {
        var name = render(result: result)
        if !name.lowercased().hasSuffix(".png") && !name.lowercased().hasSuffix(".jpg") && !name.lowercased().hasSuffix(".jpeg") && !name.lowercased().hasSuffix(".tiff") && !name.lowercased().hasSuffix(".pdf") && !name.lowercased().hasSuffix(".heic") {
            name += ".\(settings.defaultImageFormat)"
        }
        var url = directory.appendingPathComponent(name)
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            url = directory.appendingPathComponent("\(base)-\(i).\(ext)")
            i += 1
        }
        counter += 1
        UserDefaults.standard.set(counter, forKey: "sf.fileCounter")
        return url
    }

    func preview() -> String {
        render(result: nil)
    }

    private func sanitize(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }

    private func sanitizeFilename(_ s: String) -> String {
        sanitize(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
