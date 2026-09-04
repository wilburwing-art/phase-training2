import XCTest
@testable import PhaseTraining

/// CoachConsent carries the Guideline 5.1.2(i) disclosure and had no tests.
/// The two strings are the ONLY consent surfaces a user sees, and the code
/// comment on `shortDisclosure` says it "must stay consistent with
/// `modalBody`". These pin that, and pin the four free-text blocks T0-5 added.
@MainActor
final class CoachConsentTests: XCTestCase {

    func test_modalNamesEveryCategoryThatIsActuallySent() {
        let body = CoachConsent.modalBody.lowercased()
        for term in ["plan", "workout history", "logged sets",
                     "height", "weight", "age", "gender",
                     "injuries", "soreness",
                     "dislikes", "constraints", "sport logs", "post-workout feedback",
                     "strength"] {
            XCTAssertTrue(body.contains(term), "modalBody must disclose '\(term)'")
        }
    }

    func test_modalNamesTheProviderAndTheRoute() {
        XCTAssertTrue(CoachConsent.modalBody.contains(CoachConsent.providerName))
        XCTAssertTrue(CoachConsent.modalBody.contains(CoachConsent.routedVia))
        XCTAssertTrue(CoachConsent.shortDisclosure.contains(CoachConsent.providerName))
    }

    func test_modalSaysWhatIsNotSent() {
        let body = CoachConsent.modalBody.lowercased()
        XCTAssertTrue(body.contains("name"), "must say the name is not sent")
        XCTAssertTrue(body.contains("email"))
        XCTAssertTrue(body.contains("device identifier"))
    }

    func test_shortDisclosureIsNotVaguerThanTheModal() {
        // The onboarding row has no room for the list, but it is the only
        // consent surface a fresh install sees, so it cannot omit a category
        // class the modal names.
        let short = CoachConsent.shortDisclosure.lowercased()
        for term in ["plan", "workouts", "body metrics", "injury"] {
            XCTAssertTrue(short.contains(term), "shortDisclosure must mention '\(term)'")
        }
        XCTAssertTrue(short.contains("never your name"))
    }

    func test_privacyPolicyLinkIsHTTPSAndPointsAtThePublishedPolicy() {
        let url = CoachConsent.privacyPolicyURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(url.absoluteString.hasSuffix("/privacy.html"))
        XCTAssertTrue(CoachConsent.modalBody.contains(url.absoluteString),
                      "the modal must name the policy URL it promises")
    }
}
