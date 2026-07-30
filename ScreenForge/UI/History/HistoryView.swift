import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: CaptureHistoryRepository
    @EnvironmentObject var settings: SettingsStore
    @State private var query = ""
    @State private var kindFilter: CaptureKind? = nil

    var filtered: [CaptureHistoryEntry] {
        history.entries.filter { e in
            if let kindFilter, e.kind != kindFilter { return false }
            if query.isEmpty { return true }
            let q = query.lowercased()
            return (e.title?.lowercased().contains(q) ?? false)
                || (e.sourceApp?.lowercased().contains(q) ?? false)
                || (e.sourceWindow?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack {
            HStack {
                TextField(String(localized: "Search"), text: $query)
                Picker(String(localized: "Type"), selection: $kindFilter) {
                    Text(String(localized: "All")).tag(CaptureKind?.none)
                    ForEach([CaptureKind.region, .window, .fullDisplay, .allDisplays, .lastRegion], id: \.self) { k in
                        Text(k.rawValue).tag(Optional(k))
                    }
                }
                .frame(width: 160)
            }
            .padding()
            List(filtered) { entry in
                HStack {
                    if let path = entry.thumbnailPath, let img = NSImage(contentsOfFile: path) {
                        Image(nsImage: img).resizable().frame(width: 64, height: 40).cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.2)).frame(width: 64, height: 40)
                    }
                    VStack(alignment: .leading) {
                        Text(entry.title ?? entry.sourceApp ?? entry.kind.rawValue).font(.headline)
                        Text("\(entry.width)×\(entry.height) • \(entry.createdAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.pinned { Image(systemName: "pin.fill") }
                    Button(String(localized: "Open")) {
                        AppServices.shared.editorWindows.openHistoryEntry(entry, history: history)
                    }
                    Button(String(localized: "Copy")) {
                        if let img = history.image(for: entry) {
                            AppServices.shared.clipboard.copy(img, includeTIFF: true)
                        }
                    }
                    Button(String(localized: "Delete"), role: .destructive) {
                        history.delete(entry.id)
                    }
                    Button(entry.pinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                        history.setPinned(entry.id, pinned: !entry.pinned)
                    }
                }
            }
        }
    }
}
