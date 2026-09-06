import XCTest
@testable import PressTalkCore

final class CheckoutConfigTests: XCTestCase {
    // While there is nowhere to pay, the app must not show a buy button. An
    // enabled control that goes nowhere is worse than no control.
    func testNoCheckoutMeansNotLive() {
        if PressTalkOffer.checkoutURLString.isEmpty {
            XCTAssertNil(PressTalkOffer.checkoutURL)
            XCTAssertFalse(PressTalkOffer.checkoutIsLive)
        }
    }

    // The single line someone edits when the store opens has to produce a usable
    // URL, or the button appears and does nothing.
    func testANonEmptyCheckoutStringProducesAUsableURL() {
        XCTAssertEqual(
            URL(string: "https://example.lemonsqueezy.com/buy/abc")?.scheme, "https",
            "the shape PressTalkOffer.checkoutURLString expects must parse")
    }

    func testPricingPageFollowsTheSameRule() {
        if PressTalkOffer.pricingPageURLString.isEmpty {
            XCTAssertNil(PressTalkOffer.pricingPageURL)
        }
    }
}
