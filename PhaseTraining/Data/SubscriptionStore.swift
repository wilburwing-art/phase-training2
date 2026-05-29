// SubscriptionStore.swift — StoreKit 2 wrapper for the Pro subscription
// that gates the AI coach.
//
// Status: SCAFFOLD. Product IDs below are placeholders. Until they're
// created in App Store Connect (Subscriptions → Auto-Renewable group) and
// a matching `.storekit` configuration file is added to the Xcode scheme,
// `Product.products(for:)` returns an empty array, `isPro` stays false,
// and PaywallView renders its "not configured" state. The scaffold ships
// intentionally non-functional so a forgetting-to-configure release can't
// accidentally bill anyone.
//
// To enable:
//   1. Create the Pro product in App Store Connect.
//   2. Update `Self.allProductIDs` if you change the IDs / add tiers.
//   3. Add a StoreKit Configuration File in Xcode for local previews.
//   4. Wire the entitlement check (`subStore.isPro`) at the gate sites
//      (CoachBubble, CoachConsent toggle, etc.). Deliberately NOT wired
//      yet — that's a product decision the team needs to make explicitly.

import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    /// TODO: replace with the product IDs from App Store Connect.
    /// Suggested naming (mirrors the bundle id):
    ///   com.phasetraining.app.pro_monthly
    ///   com.phasetraining.app.pro_yearly  (if you add an annual tier)
    static let proMonthlyProductID = "com.phasetraining.app.pro_monthly"
    static let allProductIDs: Set<String> = [SubscriptionStore.proMonthlyProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published var purchaseInFlight: Bool = false
    @Published var lastError: String? = nil

    private var transactionListener: Task<Void, Never>?

    init() {
        // Start listening for transactions queued outside the app (a
        // family-shared sub auto-syncs, Ask-to-Buy approvals, etc.) before
        // the first user-initiated purchase.
        transactionListener = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    deinit { transactionListener?.cancel() }

    /// Fetch the Pro product(s) from App Store Connect + sync the
    /// entitlement state. Safe to call on every app launch; cheap. Errors
    /// fall to `lastError` so the paywall can surface them.
    func refresh() async {
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            self.products = fetched.sorted { $0.price < $1.price }
        } catch {
            self.lastError = "Couldn't load subscription options: \(error.localizedDescription)"
        }
        await refreshEntitlement()
    }

    /// Trigger the StoreKit purchase flow for the supplied product.
    /// Returns true on a successful, verified purchase.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    /// "Restore Purchases" button entry point — asks the App Store to
    /// resync the receipt and re-checks entitlements.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Internal

    /// Walk the user's currently-entitled transactions. Pro is on iff at
    /// least one transaction matches our product set, is verified, not
    /// revoked, and not expired.
    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               Self.allProductIDs.contains(txn.productID),
               txn.revocationDate == nil,
               (txn.expirationDate ?? .distantFuture) > Date() {
                self.isPro = true
                return
            }
        }
        self.isPro = false
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let txn) = transactionResult else { return }
        await txn.finish()
        await refreshEntitlement()
    }
}
