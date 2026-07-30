import Foundation
import AppKit
import CoreGraphics

enum CaptureKind: String, Codable, Sendable {
    case region, window, fullDisplay, allDisplays, lastRegion
}

enum CaptureDestination: Sendable {
    case editor
    case clipboard
    case save
    case settingsDefault(for: CaptureKind)
    case action(PostCaptureAction)
}

struct CaptureResult: @unchecked Sendable {
    let id: UUID
    let image: CGImage
    let kind: CaptureKind
    let displayID: CGDirectDisplayID?
    let regionPoints: CGRect?
    let regionPixels: CGRect?
    let sourceAppName: String?
    let sourceWindowTitle: String?
    let capturedAt: Date
    let layoutSignature: String?

    init(
        image: CGImage,
        kind: CaptureKind,
        displayID: CGDirectDisplayID? = nil,
        regionPoints: CGRect? = nil,
        regionPixels: CGRect? = nil,
        sourceAppName: String? = nil,
        sourceWindowTitle: String? = nil,
        layoutSignature: String? = nil
    ) {
        self.id = UUID()
        self.image = image
        self.kind = kind
        self.displayID = displayID
        self.regionPoints = regionPoints
        self.regionPixels = regionPixels
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
        self.capturedAt = Date()
        self.layoutSignature = layoutSignature
    }

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case noWindow
    case captureFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return String(localized: "Screen Recording permission missing")
        case .noDisplay: return String(localized: "Display not found")
        case .noWindow: return String(localized: "Window not found")
        case .captureFailed(let s): return s
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}
