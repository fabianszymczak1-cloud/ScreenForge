import Foundation
import Vision
import CoreGraphics
import AppKit

struct OCRLineResult: Sendable {
    let text: String
    /// Image pixels, top-left origin.
    let boundingBox: CGRect
}

actor OCRService {
    func recognize(_ image: CGImage, languages: [String] = ["pl-PL", "en-US"]) async throws -> String {
        let lines = try await recognizeLines(image, languages: languages)
        return lines.map(\.text).joined(separator: "\n")
    }

    func recognizeLines(_ image: CGImage, languages: [String] = ["pl-PL", "en-US"]) async throws -> [OCRLineResult] {
        PerformanceMonitor.shared.begin("ocr")
        defer { _ = PerformanceMonitor.shared.end("ocr") }
        let size = CGSize(width: image.width, height: image.height)
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLineResult] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return OCRLineResult(
                        text: candidate.string,
                        boundingBox: Self.visionNormalizedToTopLeft(obs.boundingBox, imageSize: size)
                    )
                }
                cont.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// OCR + regex detection with per-match Vision boxes (falls back to whole line box).
    func detectSensitiveRegions(
        in image: CGImage,
        detector: SensitiveDataDetectionService,
        customRegexes: [String] = [],
        languages: [String] = ["pl-PL", "en-US"]
    ) async throws -> [SensitiveRegion] {
        PerformanceMonitor.shared.begin("ocr.sensitive")
        defer { _ = PerformanceMonitor.shared.end("ocr.sensitive") }
        let size = CGSize(width: image.width, height: image.height)
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var regions: [SensitiveRegion] = []
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let findings = detector.detect(in: candidate.string, customRegexes: customRegexes)
                    for finding in findings {
                        var rect = Self.visionNormalizedToTopLeft(obs.boundingBox, imageSize: size)
                        if let range = finding.range {
                            if let boxObs = try? candidate.boundingBox(for: range) {
                                rect = Self.visionNormalizedToTopLeft(boxObs.boundingBox, imageSize: size)
                            }
                        }
                        // Padding so redact fully covers glyphs
                        rect = rect.insetBy(dx: -6, dy: -4)
                        rect = rect.intersection(CGRect(origin: .zero, size: size))
                        guard rect.width > 2, rect.height > 2 else { continue }
                        regions.append(SensitiveRegion(kind: finding.kind, value: finding.value, rect: rect))
                    }
                }
                cont.resume(returning: regions)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    func detectBarcodes(_ image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNDetectBarcodesRequest { request, error in
                if let error { cont.resume(throwing: error); return }
                let payloads = ((request.results as? [VNBarcodeObservation]) ?? []).compactMap(\.payloadStringValue)
                cont.resume(returning: payloads)
            }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
        }
    }

    /// Vision normalized rect (origin bottom-left) → image pixels (origin top-left).
    nonisolated static func visionNormalizedToTopLeft(_ box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.origin.x * imageSize.width,
            y: (1 - box.origin.y - box.height) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }
}
