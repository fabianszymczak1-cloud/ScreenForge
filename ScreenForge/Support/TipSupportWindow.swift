import AppKit
import SwiftUI

@MainActor
enum TipPresenter {
    static func show() {
        TipStore.shared.start()
        TipSupportWindowController.shared.show()
    }
}

@MainActor
final class TipSupportWindowController: NSWindowController {
    static let shared = TipSupportWindowController()

    private init() {
        let hosting = NSHostingController(rootView: TipSupportView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Support ScreenForge")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 320))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        AppActivation.activateForDocumentWindow()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct TipSupportView: View {
    @ObservedObject private var store = TipStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Support ScreenForge"))
                .font(.title2.bold())
            Text(String(localized: "The app stays free. A tip is optional and does not unlock any feature. Payment is handled by Apple."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.products.isEmpty {
                Text(String(localized: "Tips are unavailable right now."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.products, id: \.id) { product in
                    Button(product.displayName + " · " + product.displayPrice) {
                        Task { await store.purchase(product) }
                    }
                    .disabled(store.purchasing)
                    .buttonStyle(.borderedProminent)
                }
            }
            if let message = store.message {
                Text(message)
                    .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 440, alignment: .topLeading)
        .task { await store.load() }
    }
}
