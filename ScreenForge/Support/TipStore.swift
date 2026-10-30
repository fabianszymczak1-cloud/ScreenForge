import Foundation
import StoreKit

enum TipProductID {
    static let all = [
        "com.itszymczak.screenforge.tip.small",
        "com.itszymczak.screenforge.tip.medium",
        "com.itszymczak.screenforge.tip.large",
    ]
}

@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    private init() {}

    func start() {
        guard updates == nil else { return }
        updates = Task { await observeTransactions() }
        Task { await load() }
    }

    func load() async {
        do {
            let loaded = try await Product.products(for: TipProductID.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                message = String(localized: "Thank you. This tip does not unlock anything.")
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard let transaction = try? verified(update) else { continue }
            await transaction.finish()
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipStoreError.unverified
        case .verified(let value):
            return value
        }
    }
}

enum TipStoreError: Error {
    case unverified
}
