// SubscriptionStoreTests.swift — the pure entitlement decision lifted out of
// refreshEntitlement(). SKTestSession purchase-flow tests are flaky headless;
// this exercises the verified/revoked/expired/foreign-product matrix directly
// with no live StoreKit, which is where the actual decision lives.

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
