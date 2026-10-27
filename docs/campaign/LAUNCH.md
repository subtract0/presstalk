# PressTalk: worldwide Apple Silicon acquisition pilot

Prepared 27 October 2026. This is a seven-day paid acquisition experiment for
the existing PressTalk product, not a new pricing or licensing system.

The yellow-green design now also serves at `https://presstalk.app/`. The
original campaign URL remains available. The main homepage publication passed
at commit `1699451fc62c2d4455cc1dd841abd12e56501fb5`, Actions run `40509729010`,
and was verified at the root URL in the browser. `homepage-live.jpg` records
that result. Existing homepage fragment links remain supported.

## Offer and audience

- Product: PressTalk 0.1.25; Apple Silicon M1 or later; macOS 14 or later.
- Current release notes say macOS 27 has not yet been verified. Preserve that
  disclosure until the actual Mac check is completed.
- Worldwide audience wherever the existing checkout can accept the purchase.
  No arbitrary country exclusions. Use English creative. Product compatibility
  and language fit are different from the buyer's location.
- 4chan board: `/g/`. Start with desktop placement. Use macOS targeting if the
  dashboard offers it; desktop alone does not identify a Mac. Banners qualify
  M1+ themselves. Mobile exports are prepared but need a separate decision
  because a phone visitor cannot install the Mac app immediately.
- Preserve the existing three-day trial, starting with first successful
  dictation, with no card or account for the trial.
- Preserve the existing founder price: EUR20 / USD20 / CAD28 in the offer
  source, with the final localized price and taxes shown in checkout. The live
  checkout was independently opened on 27 October and showed PressTalk Founder
  USD20. Do not change prices or invent a count of remaining founder licences.
- Preserve the existing one-time licence, included future Mac releases actually
  published, best-effort support, and 14-day refund policy.

## Creative and destinations

Use the PNG exports, not SVG files, for the 4chan upload. The SVG originals are
editable production assets. See `creative-notes.md` for the design rationale.

| Creative | File | Destination |
| --- | --- | --- |
| A: Speak your next prompt | `site/ads/presstalk-prompts-728x90.png` | https://presstalk.app/voice-to-text.html?utm_source=4chan&utm_medium=display&utm_campaign=presstalk_g_v1&utm_content=prompt_desktop |
| B: Your voice. Your Mac. | `site/ads/presstalk-privacy-728x90.png` | https://presstalk.app/voice-to-text.html?utm_source=4chan&utm_medium=display&utm_campaign=presstalk_g_v1&utm_content=privacy_desktop |
| A mobile export (reserve) | `site/ads/presstalk-prompts-300x250.png` | https://presstalk.app/voice-to-text.html?utm_source=4chan&utm_medium=display&utm_campaign=presstalk_g_v1&utm_content=prompt_mobile |
| B mobile export (reserve) | `site/ads/presstalk-privacy-300x250.png` | https://presstalk.app/voice-to-text.html?utm_source=4chan&utm_medium=display&utm_campaign=presstalk_g_v1&utm_content=privacy_mobile |

The page has one illustrative product demo, trial and purchase actions, the
existing offer, compatibility, setup, privacy and refund information. It makes
no speed, accuracy superiority, user-count or open-source licensing claims.

## Budget and timing

Proposed spend only; no advertisement has been bought or funded by this work.

- Initial tranche: EUR100 maximum, including any mandatory platform fees.
- Optional reserve: EUR50, released manually after reviewing actual evidence.
- Total ceiling: EUR150. No automated budget increases or recurring commitment.
- Duration: seven days after actual launch, not seven days from this document.
- Two creatives; do not fragment this budget across multiple boards/products.
- Use a modest frequency cap; three exposures per user per day is a starting
  proposal only if the dashboard supports that unit and window.
- Read purchase results after the ad flight and again approximately three days
  later. The trial begins on first use, so delayed activations can buy later.
- Review refunds after each relevant purchase has passed the 14-day window.

The public ad page does not publish a verified current minimum deposit or CPM
floor. Confirm these, placement controls, macOS targeting, currency, fees and
unused-balance terms in the actual advertiser account before funding. Do not
present 2013 rates as a current quote.

## Measurement, with explicit limits

`site/campaign.js` accepts only the four public labels above and decorates
same-site navigation and the existing purchase-service `/buy` link. It sends
no request of its own, stores nothing in the browser and does not modify the
Mac app. Binary download URLs, receipt/recovery links and external source links
are not tagged.

`commerce/lib/campaign.js` preserves accepted campaign labels on the already
verified Stripe Payment Link, after the usual sales/database/link checks. It
adds a shared `client_reference_id`, such as
`presstalk_g_v1_prompt_desktop`. Stripe includes this in Checkout Sessions.
Test-mode links and any pre-existing reconciliation reference are untouched.
The patch does not change prices, the accepted Payment Link, product validation,
licence issuance, customer emails, refunds or signing keys.

The commerce Worker must be deployed separately from GitHub Pages. Until that
deployment is verified, the production Worker continues dropping campaign
parameters. Do not call attribution live just because the static page is live.

Count successful paid Checkout Sessions by the exact reference, excluding
test-mode activity and subsequently refunded/disputed orders. UTM codes alone
are not a paid-order database. The existing local order schema is unchanged;
the shared campaign reference is available from Stripe's Session record.

This is intentionally partial attribution. It follows tagged browser journeys,
not people. If someone tries PressTalk and later purchases through the app's
untagged Buy link or another device, the campaign reference may be absent.
Neither activation nor retention is automatically measured. Ad-platform clicks
are not independently verified unique visitors. Report these limits alongside
paid results; never treat missing attribution as proof that no ad-driven sale
occurred. Optional customer feedback can supplement it without adding app
telemetry.

## Economics and decisions

Use actual contribution after taxes collected, processor/platform deductions,
refunds and incremental support. Do not equate a EUR20 receipt with EUR20
available for acquisition.

An initial target is EUR8–10 per paying customer, subject to actual net
contribution. If an order contributes EUR15, ten orders recover EUR150 of ad
spend before additional owner time. This is a scenario, not a verified payout.
Stop early for incompatible traffic, broken customer journeys or an operational
cost problem. Do not declare profitability after one sale, and do not treat a
small sample with no sales as a definitive statistical result.

The seller reports impressions/clicks. Stripe reports purchases. Keep raw
customer emails, receipt links and licence keys out of campaign reports.

## Remaining production step: existing Cloudflare Worker

The current workspace can update GitHub and the static site, but its Wrangler
session is not authenticated. No credentials were copied from customer data,
and no new infrastructure was provisioned. The existing Worker is live and
accepting sales; this step adds campaign attribution only.

Give the following task to the agent on a Mac already authorized for the
PressTalk Cloudflare account:

> In the existing `subtract0/presstalk` checkout, fetch and inspect the launch
> commit/branch supplied with this handoff. Preserve uncommitted local work;
> use an isolated worktree if necessary. Review the only purchase behavior
> change in `commerce/lib/handler.js` and `commerce/lib/campaign.js` plus its
> tests. Use the existing Cloudflare account, `presstalk-licenses` Worker,
> database, private monitoring binding, Stripe product/price/link and secrets.
> Do not rotate keys, migrate/delete orders, change prices, or create a paid
> service. From `commerce`, run `npm ci`, `npm test`, `npm run build:worker`,
> and `npm run test:worker`. If they pass, deploy the existing Worker using
> `npx wrangler deploy`. Check `/api/health` remains live with sales enabled.
> GET `/buy` with each of the four campaign URLs and verify its 303 Location
> remains the same Stripe Payment Link and now contains the expected shared
> client reference. An ordinary untagged GET must remain unchanged. Verify
> unknown/duplicated campaign values do not propagate. Do not submit a paid
> transaction or start/fund the 4chan campaign. Report deployment ID, commit,
> tests and redacted redirect evidence; never print credentials, customer
> details, receipt links or licence keys.

## Verification commands

```sh
bash scripts/presstalk_claims_gate.sh
python3 scripts/presstalk_site_privacy_gate.py
python3 scripts/presstalk_offer_consistency_gate.py
python3 scripts/presstalk_download_link_gate.py
python3 scripts/test_presstalk_site_privacy_gate.py
```

Run the commerce commands in the handoff above for the redirect change. Browser
QA must also follow landing → download → buy and inspect the resulting link.
No local test is a live customer purchase or proof of current email delivery.

### Checks completed on 27 October 2026

- The public checkout was opened read-only and showed a live USD20 PressTalk
  Founder purchase. No payment was submitted.
- The public health endpoint reported live mode and sales enabled. Download,
  checkout and recovery links resolved.
- All commerce test files passed, including the campaign navigation/redirect
  regression tests. The compiled Worker built successfully and all five
  isolated Worker tests passed with simulated payment and email services.
- Claims, privacy, offer-consistency and download-link gates passed. The
  privacy gate regression detected 19 planted defects and accepted 10 valid
  patterns.
- Browser review covered the desktop page, a 390-pixel mobile view, and
  landing → download → buy navigation with campaign labels preserved. The
  temporary mobile QA page was removed from the deployment directory.
- `landing-preview.jpg` records the published page on `presstalk.app`. Both
  PNG banner sizes were inspected at their native dimensions.
- GitHub Pages publication passed at commit
  `087ebc67ac6ed627f19b190bb7e9abd611f6b30a`, Actions run `40507948098`.
  The public `https://presstalk.app/voice-to-text.html` page was opened and
  its live content verified in the browser after deployment.
- Production Worker deployment remains outstanding. Static-site publication
  and the Worker deployment are independent operations.

## References

- Current source of offer: `Sources/PressTalkCore/EntitlementPolicy.swift`.
- Actual release: https://github.com/subtract0/presstalk/releases/tag/v0.1.25
- Previous acceptance: `docs/purchases/2026-09-09-public-release.md`.
- Ad specifications and official purchase route: https://4chan.org/advertise
- Stripe campaign references: https://docs.stripe.com/payment-links/url-parameters
