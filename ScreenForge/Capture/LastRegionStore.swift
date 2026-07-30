import Foundation
import CoreGraphics

struct StoredRegion: Codable, Equatable {
    var displayID: UInt32
    var pixelRect: CGRectCodable
    var pointRect: CGRectCodable
    var layoutSignature: String
    var scale: Double
    var kind: String
}

struct CGRectCodable: Codable, Equatable {
    var x: Double; var y: Double; var w: Double; var h: Double
    init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; w = r.width; h = r.height }
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

@MainActor
final class LastRegionStore {
    private let key = "sf.lastRegion"
    private(set) var last: StoredRegion?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(StoredRegion.self, from: data) {
            last = decoded
        }
    }

    func save(displayID: CGDirectDisplayID, pixelRect: CGRect, pointRect: CGRect, layoutSignature: String, scale: CGFloat, kind: CaptureKind) {
        let stored = StoredRegion(
            displayID: displayID,
            pixelRect: CGRectCodable(pixelRect),
            pointRect: CGRectCodable(pointRect),
            layoutSignature: layoutSignature,
            scale: Double(scale),
            kind: kind.rawValue
        )
        last = stored
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func resolve(using displays: DisplayTopologyService, coordinates: CoordinateConverter) -> (displayID: CGDirectDisplayID, pixelRect: CGRect)? {
        guard let last else { return nil }
        let id = CGDirectDisplayID(last.displayID)
        guard let info = displays.display(id: id) else {
            // Try remapping by relative position if layout changed
            return remap(last, displays: displays, coordinates: coordinates)
        }
        if last.layoutSignature != displays.layoutSignature {
            let clamped = coordinates.clampRectToDisplay(last.pointRect.cgRect, displayFrame: info.geometry.framePoints)
            guard !clamped.isNull, clamped.width > 2, clamped.height > 2 else { return nil }
            let pixels = coordinates.appKitGlobalRectToImagePixels(clamped, geometry: info.geometry)
            return (id, pixels)
        }
        let pixels = last.pixelRect.cgRect
        let maxW = info.geometry.framePixels.width
        let maxH = info.geometry.framePixels.height
        let clamped = pixels.intersection(CGRect(x: 0, y: 0, width: maxW, height: maxH))
        guard !clamped.isNull, clamped.width > 2, clamped.height > 2 else { return nil }
        return (id, clamped)
    }

    private func remap(_ last: StoredRegion, displays: DisplayTopologyService, coordinates: CoordinateConverter) -> (CGDirectDisplayID, CGRect)? {
        guard let main = displays.displays.first(where: \.isMain) ?? displays.displays.first else { return nil }
        let points = last.pointRect.cgRect
        let clamped = coordinates.clampRectToDisplay(points, displayFrame: main.geometry.framePoints)
        guard !clamped.isNull, clamped.width > 2, clamped.height > 2 else { return nil }
        let pixels = coordinates.appKitGlobalRectToImagePixels(clamped, geometry: main.geometry)
        return (main.id, pixels)
    }
}
