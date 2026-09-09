# PressTalk 0.1.23 public release — 2026-09-09

PressTalk 0.1.23/build 23.4 and the matching English and German purchase pages
are public. The owner approved release with the known first-attempt AirPods
retry; that limitation is disclosed on both download pages, in the release
notes and in the support guide. This record supersedes the earlier candidate,
provider-payment and paused-cutover status snapshots.

## Published app and pages

- [Public release](https://github.com/subtract0/presstalk/releases/tag/v0.1.23):
  published at 09:32:31 UTC, marked latest, target
  `e6e28bf6e16372d2a59d1662f47050d54d7b9390`.
- A new unauthenticated public download matched the exact notarized ZIP:
  `4e810986242f962dbd7ddfeaa71163d409cd091194a2f8fa1db926dc393c490b`.
  Native source, Developer ID and Apple notarization are recorded in the
  [candidate evidence](2026-09-09-candidate-and-site-cutover.md).
- [PR #1](https://github.com/subtract0/presstalk/pull/1) merged at 09:38:27 UTC.
  Production site commit: `2309001731e0ab959825713f093164b290d306f5`.
- [Pages run 34335844017](https://github.com/subtract0/presstalk/actions/runs/34335844017)
  passed all seven gates, including their planted-defect checks, and deployed.
- All six live home, download and purchase pages returned 200 and matched their
  source bytes. Twelve live browser previews at 390 and 1,280 pixels passed
  checks for horizontal overflow and automatic external requests. Screenshots
  were saved; the mobile homepage and rendered live checkout were inspected.
- Following the actual purchase button reached Stripe and rendered PressTalk
  Founder, EUR 20 and the payment controls. No payment was submitted. Early
  loading-state screenshots were excluded from rendered checkout acceptance.

## Live purchase service

The production Stripe webhook is enabled for completed checkout, successful
asynchronous payment, refund and dispute events. The existing active Payment
Link now redirects completed payments to the service receipt with Stripe's
checkout-session placeholder. Both settings were read back and verified.
The runtime's restricted Stripe key was preserved; the expired operator login
was refreshed through Stripe's authenticated live-account authorization flow.

Production `/api/health` returns 200, `mode: live`, `salesEnabled: true` and key
`commerce-2026`. `/buy` reaches the existing active Stripe checkout and `/recover`
returns 200. The release's actual download, checkout and recovery link gate
passed before merge and again on GitHub's deployment runner.

A paid sandbox order previously proved signed licence issuance, immediate
receipt access and automatic email recovery after an injected provider outage.
The same original licence was delivered without manual retry. That is distinct
from this release's live configuration and checkout verification: no new live
purchase or customer email delivery is claimed by this cutover record.

Cloudflare Workers Paid is active. Resend remains Free for initial automated
mail; the owner confirmed that the existing Tuta support forwarding and sending
work. No paid Resend upgrade or Porkbun reauthorization was required.

## Accepted limitation and capacity boundary

The first AirPods recording after connection can stop with a retry message.
The owner repeated the dictation successfully and explicitly accepted shipping
while the underlying transition is investigated. Interrupted recordings insert
nothing. The timestamp evidence and unresolved mechanism are preserved in the
[release acceptance](2026-09-09-release-acceptance.md). The guard was not weakened.

This is an initial customer release. The earlier indexed queue measurement with
500,000 stored orders does not establish 500,000 simultaneous buyers or email
capacity. Increase email capacity before volume exceeds the provider's current
allowance. Existing compatible activated Mac copies work offline without licence
expiry or periodic server checks.

Private evidence is under `.local/commerce/`: `public-release-verification/`,
`public-release-pages-run.json`, `production-cutover-stripe-cli.json`,
`production-health-enabled.json`, and `release-0.1.23-draft/public-download.zip`.
The owner's easy-to-open status page is `~/Downloads/Finish PressTalk Release.html`.
