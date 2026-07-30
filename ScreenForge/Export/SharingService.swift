import AppKit

@MainActor
final class SharingService {
    func presentShare(image: NSImage, relativeTo view: NSView) {
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func openInOtherApp(url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func printImage(_ image: NSImage) {
        let op = NSPrintOperation(view: NSImageView(image: image))
        op.run()
    }
}
