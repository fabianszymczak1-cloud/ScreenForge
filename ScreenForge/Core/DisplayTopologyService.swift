import Foundation
import AppKit
import CoreGraphics

struct DisplayInfo: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let geometry: DisplayGeometry
    let localizedName: String
    let isMain: Bool
}

@MainActor
final class DisplayTopologyService: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    let coordinates = CoordinateConverter()

    func refresh() {
        displays = NSScreen.screens.map { screen in
            let geo = coordinates.geometry(for: screen)
            return DisplayInfo(
                id: geo.displayID,
                geometry: geo,
                localizedName: screen.localizedName,
                isMain: screen == NSScreen.main
            )
        }
        DiagnosticLog.shared.info("displays.count=\(displays.count)")
    }

    func display(containingPoint point: CGPoint) -> DisplayInfo? {
        displays.first { $0.geometry.framePoints.contains(point) }
            ?? displays.first { $0.isMain }
    }

    func display(id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    func activeDisplay(preferCursor: Bool) -> DisplayInfo? {
        if preferCursor {
            return display(containingPoint: NSEvent.mouseLocation)
        }
        if let screen = NSScreen.main {
            return displays.first { $0.id == screen.displayID }
        }
        return displays.first
    }

    var layoutSignature: String {
        displays
            .map { "\($0.id):\($0.geometry.framePoints.debugDescription):\($0.geometry.scale)" }
            .sorted()
            .joined(separator: "|")
    }
}
