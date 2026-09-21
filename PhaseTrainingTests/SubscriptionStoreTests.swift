// SubscriptionStoreTests.swift — the pure entitlement decision lifted out of
// refreshEntitlement(). SKTestSession purchase-flow tests are flaky headless;
// this exercises the verified/revoked/expired/foreign-product matrix directly
// with no live StoreKit, which is where the actual decision lives.

import StoreKit
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
