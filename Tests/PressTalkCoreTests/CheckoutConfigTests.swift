import XCTest
@testable import PressTalkCore

final class CheckoutConfigTests: XCTestCase {
    // While there is nowhere to pay, the app must not show a buy button. An
    // enabled control that goes nowhere is worse than no control.
    //
    // "Nowhere to pay" means EVERY rail is empty. This asserted that an empty
    // Stripe URL alone made the product non-live, which stopped being true when
    // a second rail existed: a build with only PayPal configured would have
    // been declared unsellable by this test while the app happily sold through
    // it.
    func testNoCheckoutMeansNotLive() {
        let anyConfigured = PressTalkOffer.CheckoutRail.allCases.contains {
            !PressTalkOffer.checkoutURLString(for: $0).isEmpty
        }
        if !anyConfigured {
            XCTAssertNil(PressTalkOffer.checkoutURL)
            XCTAssertFalse(PressTalkOffer.checkoutIsLive)
        }
        if PressTalkOffer.checkoutURLString.isEmpty {
            XCTAssertNil(PressTalkOffer.checkoutURL,
                         "the Stripe-named property must stay Stripe-specific")
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

    // MARK: - Two rails

    /// An empty rail must be ABSENT, not broken. PayPal is empty today because
    /// only the account holder can create the button, and until then nothing
    /// may claim PressTalk accepts PayPal.
    func testAnEmptyRailIsAbsentRatherThanBroken() {
        for rail in PressTalkOffer.CheckoutRail.allCases
        where PressTalkOffer.checkoutURLString(for: rail).isEmpty {
            XCTAssertNil(PressTalkOffer.checkoutURL(for: rail))
            XCTAssertFalse(PressTalkOffer.liveCheckoutRails.contains(rail),
                           "\(rail) has no URL but is being offered")
        }
    }

    /// Every rail that IS configured has to produce a usable URL, or a button
    /// appears and goes nowhere.
    func testEveryConfiguredRailParses() {
        for rail in PressTalkOffer.liveCheckoutRails {
            let url = try! XCTUnwrap(PressTalkOffer.checkoutURL(for: rail))
            XCTAssertEqual(url.scheme, "https", "\(rail) must be https")
            XCTAssertNotNil(url.host, "\(rail) has no host")
        }
    }

    /// Trial enforcement is gated on "could this person pay if they wanted to".
    /// Asking only about Stripe would lock out someone whose only working
    /// checkout was PayPal.
    func testCheckoutIsLiveMeansAnyRailNotStripeSpecifically() {
        XCTAssertEqual(PressTalkOffer.checkoutIsLive,
                       !PressTalkOffer.liveCheckoutRails.isEmpty)
    }

    /// Who accounts for VAT, which is the one thing the rail determines.
    /// Stripe Managed Payments is deemed supplier for indirect tax; a direct
    /// PayPal checkout leaves that with the seller. This deliberately does NOT
    /// assert who the contracting seller is -- Stripe's terms say it is "not
    /// the seller of record", so the tax fiction cannot settle that.
    func testWhoAccountsForTaxIsRecordedPerRail() {
        XCTAssertTrue(PressTalkOffer.CheckoutRail.stripe.isDeemedSupplierForTax)
        XCTAssertFalse(PressTalkOffer.CheckoutRail.paypal.isDeemedSupplierForTax)
    }

    /// Rails are named in the buy prompt so someone sees which company they
    /// are buying from before pressing, not after.
    func testEveryRailHasAHumanName() {
        for rail in PressTalkOffer.CheckoutRail.allCases {
            XCTAssertFalse(rail.displayName.isEmpty)
        }
    }

}
