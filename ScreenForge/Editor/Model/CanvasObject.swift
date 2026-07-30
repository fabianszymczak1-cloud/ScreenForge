import Foundation
import AppKit

enum CanvasObjectType: String, Codable, CaseIterable {
    case rectangle, roundedRectangle, ellipse, line, arrow, doubleArrow, polyline
    case freehand, marker, text, textBox, callout, step
    case warning, checkmark, crossmark
    case highlight, focusArea, magnify
    case blur, pixelate, solidRedact
    case image, watermark, border, shadow
    case cursor

    var showsStrokeColor: Bool {
        switch self {
        case .rectangle, .roundedRectangle, .ellipse, .callout,
             .line, .arrow, .doubleArrow, .polyline, .freehand, .marker,
             .text, .textBox, .step, .warning, .checkmark, .crossmark, .border:
            return true
        default:
            return false
        }
    }

    var showsFillColor: Bool {
        switch self {
        case .rectangle, .roundedRectangle, .ellipse, .callout,
             .text, .textBox, .step, .warning, .checkmark, .crossmark,
             .highlight, .solidRedact:
            return true
        default:
            return false
        }
    }

    var showsStrokeWidth: Bool {
        switch self {
        case .rectangle, .roundedRectangle, .ellipse, .callout,
             .line, .arrow, .doubleArrow, .polyline, .freehand, .marker,
             .text, .textBox, .border:
            return true
        default:
            return false
        }
    }

    var showsTextColor: Bool {
        switch self {
        case .text, .textBox, .callout, .step:
            return true
        default:
            return false
        }
    }

    var showsFilterAmount: Bool {
        switch self {
        case .blur, .pixelate, .focusArea, .magnify:
            return true
        default:
            return false
        }
    }
}

enum FilterKind: String, Codable {
    case blur, pixelate, solidRedact, highlight, focusDim, focusBlur, focusGray, magnify
}

struct ObjectStyle: Equatable {
    var strokeColor: NSColor = .systemRed
    var fillColor: NSColor = .clear
    var strokeWidth: CGFloat = 3
    var opacity: CGFloat = 1
    var cornerRadius: CGFloat = 8
    var fontName: String = "Helvetica Neue"
    var fontSize: CGFloat = 18
    var textColor: NSColor = .white
    var shadow: Bool = false
    var lineDash: [CGFloat] = []
    var arrowHeadSize: CGFloat = 14
}

struct CanvasObject: Identifiable, Equatable {
    var id: UUID = UUID()
    var type: CanvasObjectType
    var frame: CGRect
    var rotation: CGFloat = 0
    var zIndex: Int = 0
    var isVisible: Bool = true
    var isLocked: Bool = false
    var style: ObjectStyle = ObjectStyle()
    var text: String? = nil
    var points: [CGPoint]? = nil
    var numberValue: Int? = nil
    var filterKind: FilterKind? = nil
    var filterAmount: CGFloat = 10
    var embeddedImage: CGImage? = nil
    var groupID: UUID? = nil

    static func == (lhs: CanvasObject, rhs: CanvasObject) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.frame == rhs.frame && lhs.rotation == rhs.rotation
            && lhs.zIndex == rhs.zIndex && lhs.isVisible == rhs.isVisible && lhs.isLocked == rhs.isLocked
            && lhs.text == rhs.text && lhs.numberValue == rhs.numberValue && lhs.filterKind == rhs.filterKind
            && lhs.filterAmount == rhs.filterAmount && lhs.style == rhs.style
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case select, rectangle, roundedRectangle, ellipse, line, arrow, doubleArrow, polyline
    case freehand, marker, text, textBox, callout, step
    case warning, checkmark, crossmark
    case highlight, focusArea, magnify
    case blur, pixelate, solidRedact
    case crop, image

    var id: String { rawValue }

    var shortcut: String {
        switch self {
        case .select: return "V"
        case .rectangle, .roundedRectangle: return "R"
        case .ellipse: return "E"
        case .line: return "L"
        case .arrow, .doubleArrow: return "A"
        case .freehand, .marker: return "F"
        case .text, .textBox, .callout: return "T"
        case .step: return "N"
        case .highlight: return "H"
        case .blur, .solidRedact: return "O"
        case .pixelate: return "P"
        case .crop: return "C"
        case .magnify: return "M"
        case .image: return "I"
        case .focusArea, .polyline, .warning, .checkmark, .crossmark: return ""
        }
    }

    var displayName: String {
        switch self {
        case .select: return String(localized: "Select")
        case .rectangle, .roundedRectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .line: return String(localized: "Line")
        case .arrow, .doubleArrow: return String(localized: "Arrow")
        case .polyline: return String(localized: "Polyline")
        case .freehand, .marker: return String(localized: "Pencil")
        case .text, .textBox, .callout: return String(localized: "Text")
        case .step: return String(localized: "Step number")
        case .warning: return String(localized: "Warning")
        case .checkmark: return String(localized: "Checkmark")
        case .crossmark: return String(localized: "Cross")
        case .highlight: return String(localized: "Highlight")
        case .focusArea: return String(localized: "Focus")
        case .magnify: return String(localized: "Magnify")
        case .blur: return String(localized: "Blur")
        case .pixelate: return String(localized: "Pixelate")
        case .solidRedact: return String(localized: "Solid redact / black box")
        case .crop: return String(localized: "Crop")
        case .image: return String(localized: "Insert image")
        }
    }

    var tooltip: String {
        let sc = shortcut
        return sc.isEmpty ? displayName : "\(displayName) (\(sc))"
    }

    var objectType: CanvasObjectType? {
        switch self {
        case .select, .crop: return nil
        case .rectangle: return .rectangle
        case .roundedRectangle: return .roundedRectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .doubleArrow: return .doubleArrow
        case .polyline: return .polyline
        case .freehand: return .freehand
        case .marker: return .marker
        case .text: return .text
        case .textBox: return .textBox
        case .callout: return .callout
        case .step: return .step
        case .warning: return .warning
        case .checkmark: return .checkmark
        case .crossmark: return .crossmark
        case .highlight: return .highlight
        case .focusArea: return .focusArea
        case .magnify: return .magnify
        case .blur: return .blur
        case .pixelate: return .pixelate
        case .solidRedact: return .solidRedact
        case .image: return .image
        }
    }
}
