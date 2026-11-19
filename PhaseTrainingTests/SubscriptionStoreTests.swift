// SubscriptionStoreTests.swift — the pure entitlement decision lifted out of
// refreshEntitlement() (verified/revoked/expired/foreign-product matrix, no
// StoreKit), the paywall terms wording, and the live purchase / restore /
// refund flow against an SKTestSession on PhaseTraining.storekit.

import StoreKit
import StoreKitTest
import XCTest
@testable import PhaseTraining

final class SubscriptionStoreTests: XCTestCase {

    private let pid = SubscriptionStore.proMonthlyProductID
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func candidate(
        productID: String? = nil,
        verified: Bool = true,
        revoked: Date? = nil,
        expires: Date?? = nil
    ) -> SubscriptionStore.EntitlementCandidate {
        SubscriptionStore.EntitlementCandidate(
            productID: productID ?? pid,
            isVerified: verified,
            revocationDate: revoked,
            // default: a year out (active); pass expires: .some(nil) for non-expiring
            expirationDate: expires == nil ? now.addingTimeInterval(365 * 86_400) : expires!
        )
    }

    func test_verifiedActive_entitles() {
        XCTAssertTrue(SubscriptionStore.isEntitled(by: [candidate()], now: now))
    }

    func test_nonExpiring_entitles() {
        XCTAssertTrue(SubscriptionStore.isEntitled(by: [candidate(expires: .some(nil))], now: now))
    }

    func test_expired_doesNotEntitle() {
        let c = candidate(expires: now.addingTimeInterval(-1))
        XCTAssertFalse(SubscriptionStore.isEntitled(by: [c], now: now))
    }

    func test_revoked_doesNotEntitle() {
        let c = candidate(revoked: now.addingTimeInterval(-3600))
        XCTAssertFalse(SubscriptionStore.isEntitled(by: [c], now: now))
    }

    func test_unverified_doesNotEntitle() {
        XCTAssertFalse(SubscriptionStore.isEntitled(by: [candidate(verified: false)], now: now))
    }

    func test_foreignProductID_doesNotEntitle() {
        let c = candidate(productID: "com.someone.else.pro")
        XCTAssertFalse(SubscriptionStore.isEntitled(by: [c], now: now))
    }

    func test_noEntitlements_doesNotEntitle() {
        XCTAssertFalse(SubscriptionStore.isEntitled(by: [], now: now))
    }

    func test_mixedCandidates_oneValid_entitles() {
        let expired = candidate(expires: now.addingTimeInterval(-1))
        let valid = candidate()
        XCTAssertTrue(SubscriptionStore.isEntitled(by: [expired, valid], now: now))
    }
}

// MARK: - Subscription terms (guideline 3.1.2 wording)

final class SubscriptionTermsTests: XCTestCase {

    private typealias Period = SubscriptionStore.Terms.Period

    func test_monthly_noTrial_readsPricePerMonth() {
        let t = SubscriptionStore.Terms(displayPrice: "$6.99", period: Period(value: 1, unit: .month), freeTrial: nil)
        XCTAssertEqual(t.line, "$6.99 / month")
    }

    func test_yearly_withTrial_readsTrialThenPrice() {
        let t = SubscriptionStore.Terms(displayPrice: "$49.99", period: Period(value: 1, unit: .year), freeTrial: Period(value: 1, unit: .week))
        XCTAssertEqual(t.line, "1 week free, then $49.99 / year")
    }

    func test_pluralPeriods() {
        XCTAssertEqual(Period(value: 3, unit: .month).phrase, "3 months")
        XCTAssertEqual(Period(value: 14, unit: .day).phrase, "14 days")
    }

    func test_ineligibleBuyer_seesNoTrial() {
        let t = SubscriptionStore.terms(displayPrice: "$6.99", period: .monthly, trial: .weekly, introEligible: false)
        XCTAssertEqual(t?.line, "$6.99 / month")
    }

    func test_eligibleBuyer_seesTrial() {
        let t = SubscriptionStore.terms(displayPrice: "$6.99", period: .monthly, trial: .weekly, introEligible: true)
        XCTAssertEqual(t?.line, "1 week free, then $6.99 / month")
    }

    func test_noPeriod_isNotASubscription() {
        XCTAssertNil(SubscriptionStore.terms(displayPrice: "$6.99", period: nil, trial: nil, introEligible: true))
    }

    func test_renewalTerms_nameTheThreeFacts() {
        let s = PaywallView.renewalTerms
        XCTAssertTrue(s.contains("Apple ID"))
        XCTAssertTrue(s.contains("renews automatically"))
        XCTAssertTrue(s.contains("cancel"))
    }
}

// MARK: - Purchase, restore and refund (SKTestSession)

/// Drives the real StoreKit calls in `SubscriptionStore` against the local
/// `PhaseTraining.storekit` configuration. No App Store Connect product is
/// needed and `CoachEntitlement.proRequired` is left alone; the store's
/// `isPro` and its UserDefaults mirror are what these assert.
///
/// Needs a simulator whose storekitd accepts SKTestSession. iOS 26.3 to 26.5
/// simulators reject every session call (SKInternalErrorDomain Code=3,
/// FB22237318) and answer from the sandbox App Store instead, so `setUp`
/// checks the session is serving this file and skips the class when it is not.
@MainActor
final class SubscriptionStoreFlowTests: XCTestCase {

    private var session: SKTestSession!
    private var store: SubscriptionStore!
    private var savedProFlag: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedProFlag = UserDefaults.standard.object(forKey: CoachEntitlement.proKey)
        session = try SKTestSession(configurationFileNamed: "PhaseTraining")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        store = SubscriptionStore()
        // Bounded load: a storekitd that never answers skips the class
        // instead of hanging the suite.
        let loaded = expectation(description: "products load")
        let s = store!
        Task { @MainActor in await s.refresh(); loaded.fulfill() }
        let outcome = await XCTWaiter().fulfillment(of: [loaded], timeout: 20)
        guard outcome == .completed else {
            throw XCTSkip("StoreKit test session unavailable: refresh timed out (FB22237318)")
        }
        // Only this file has both tiers with a trial; anything else means the
        // session fell through to the sandbox App Store and a purchase would
        // wait on a real sheet.
        let ids = Set(store.products.map(\.id))
        guard ids == SubscriptionStore.allProductIDs,
              store.introOfferEligible[SubscriptionStore.proMonthlyProductID] == true else {
            throw XCTSkip("StoreKit test session is not serving PhaseTraining.storekit (got \(ids.sorted()), eligibility \(store.introOfferEligible)); FB22237318")
        }
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        store = nil
        if let savedProFlag {
            UserDefaults.standard.set(savedProFlag, forKey: CoachEntitlement.proKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CoachEntitlement.proKey)
        }
        try await super.tearDown()
    }

    private func product(_ id: String) throws -> Product {
        try XCTUnwrap(store.products.first { $0.id == id })
    }

    private func transactionID(for id: String) throws -> UInt {
        try XCTUnwrap(session.allTransactions().last { $0.productIdentifier == id }).identifier
    }

    func test_refresh_loadsBothProductsCheapestFirst_notPro() {
        XCTAssertEqual(store.products.map(\.id),
                       [SubscriptionStore.proMonthlyProductID, SubscriptionStore.proYearlyProductID])
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CoachEntitlement.proKey))
    }

    func test_purchase_grantsPro_andMirrorsFlag() async throws {
        let ok = await store.purchase(try product(SubscriptionStore.proMonthlyProductID))
        XCTAssertTrue(ok)
        XCTAssertTrue(store.isPro)
        XCTAssertFalse(store.purchaseInFlight)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: CoachEntitlement.proKey))
    }

    func test_restore_withActiveSubscription_grantsProToFreshStore() async throws {
        await store.purchase(try product(SubscriptionStore.proYearlyProductID))
        let fresh = SubscriptionStore()
        XCTAssertFalse(fresh.isPro)
        await fresh.restore()
        XCTAssertTrue(fresh.isPro)
        XCTAssertNil(fresh.lastError)
    }

    func test_restore_afterExpiry_revokesPro() async throws {
        let id = SubscriptionStore.proMonthlyProductID
        await store.purchase(try product(id))
        XCTAssertTrue(store.isPro)
        try session.expireSubscription(productIdentifier: id)
        await store.restore()
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CoachEntitlement.proKey))
    }

    func test_refund_revokesPro() async throws {
        let id = SubscriptionStore.proMonthlyProductID
        await store.purchase(try product(id))
        XCTAssertTrue(store.isPro)
        let txnID = try transactionID(for: id)
        try session.refundTransaction(identifier: txnID)
        // The refund reaches currentEntitlements about 0.6 s later on the
        // iOS 26.2 simulator; poll refresh() for up to 10 s.
        let start = Date()
        await store.refresh()
        while store.isPro, Date().timeIntervalSince(start) < 10 {
            try await Task.sleep(nanoseconds: 250_000_000)
            await store.refresh()
        }
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CoachEntitlement.proKey))
    }

    func test_termsForProduct_newBuyerSeesTrial() throws {
        XCTAssertEqual(store.terms(for: try product(SubscriptionStore.proMonthlyProductID))?.line,
                       "1 week free, then $2.99 / month")
        XCTAssertEqual(store.terms(for: try product(SubscriptionStore.proYearlyProductID))?.line,
                       "1 week free, then $24.99 / year")
    }

    func test_termsForProduct_lapsedSubscriberSeesNoTrial() async throws {
        let id = SubscriptionStore.proMonthlyProductID
        await store.purchase(try product(id))
        try session.expireSubscription(productIdentifier: id)
        await store.refresh()
        XCTAssertEqual(store.introOfferEligible[id], false)
        XCTAssertEqual(store.terms(for: try product(id))?.line, "$2.99 / month")
    }
}
