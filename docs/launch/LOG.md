# Sales log

Operator record. What was tried, what it cost, what came back, what was
concluded. Dates on everything. Actions, observations and inferences kept
apart, with inferences labelled as such.

## 2026-09-07 — dated campaign commitment and baseline correction

The standing brief in `ASTRA_OPERATOR_BRIEF.md` governs this campaign. Day 1
is **7 September 2026**, Europe/Berlin. Older channel bans, targets and
schedules are historical; existing customer promises and the recorded USD 50
spending cap below remain. Access delays do not restart or extend the clock.

| Gate | Deadline (end of local day) | Required evidence |
|---|---|---|
| Day 21 | **2026-09-27** | At least five unrelated, unsubsidized paying customers, supported by successful transactions. Owner, favour, reimbursed, free and test purchases excluded. |
| Day 35 | **2026-10-11** | At least five of those purchases retained after their individual 14-day refund windows; actual acquisition cost and support burden recorded. |
| Day 56 | **2026-11-01** | Cohort 2 matured: positive contribution exceeding cohort 1 under identical accounting, with a repeatable acquisition method inside the budget and owner-time limits. |

Cohort 1: purchases 7–27 September. Cohort 2: purchases 28 September–18 October.
Treat each purchase as provisional until 14 complete days after its payment
timestamp; later refunds and disputes restate the originating cohort. Missing
transaction evidence cannot establish a passed gate. A missed gate ends this
campaign's discretionary work and spending immediately; support, fulfilment,
refunds and necessary maintenance continue. A further attempt needs Alex's
explicit bounded authorization with this result visible.

**Money:** existing recorded acquisition authority is USD 50 total; this turn
has committed and spent USD 0. No new subscription or contractual commitment.
Historical payments, retained sales contribution, payouts, unsettled balance,
refunds, tax, fees and operating expenditure are **unverified**, not zero.
Incremental agent execution cost is unknown; do not describe this operation as
cost-free. Count existing business expenses in the ledger when invoices are
available even when they do not consume the discretionary cap.

Use transaction-level net proceeds after withheld tax, fees, refunds and
chargebacks, less acquisition and incremental operating costs, for contribution.
When starting from merchant-of-record net proceeds, do not subtract withheld
tax and fees again. Record actual paid payouts separately, reconciling pending,
available and reserved balances and payout timing. Keep currencies separate
until an actual settlement conversion is known. No lifetime-value assumptions.

**Time:** Alex has 180 minutes per week; reserve 60 for customer obligations
before launch requests. Owner time actually used this turn: none observed;
earlier week use is unknown. Operator time and any billable execution costs
must be reported separately. Engineering limit: one working day per bounded
repair and 20% of operator effort over a fortnight unless selling is paused
for a customer-blocking defect.

**Correction to the handover below:** “zero customers” and “nobody outside the
owner has installed” were not backed by transaction or installation evidence.
There is no app telemetry. Live GitHub release metadata showed eight ZIP
downloads before this operator's artifact check; downloads are not people or
installations. The website and Stripe URL returning HTTP 200 do not establish
payment, licence delivery or unlocking. No completed sale is verified yet.

**First buyer hypothesis:** German-speaking Apple Silicon Mac users who already
dictate frequently; task: the next German email reply they actually need to send.
Try their own sentences and compare correction effort with their existing tool,
then ask them to buy only if the result earns its price. No numerical superiority
claim, invented scarcity, tracking identifier or mailing-list prerequisite.

**Before editing — bounded customer-path repair R1:** the live German download
page says Apple signed PressTalk and promises no security warning; linked support
says it is not notarized and advises a bypass. Blocked action: deciding whether
the downloaded app is authentic and safe to open normally. Acceptance: verify
the public 0.1.11 artifact's signature/notarization; make both languages and
support agree with that evidence, retain normal macOS confirmation guidance,
pass the established site gates, deploy and reread live copy. No app feature work.

**Before editing — customer-path containment R2:** stored Stripe credentials
failed on read-only requests (live: HTTP 401 invalid key; test: HTTP 401 expired
key), no delegated support mailbox is available, and public sales pages have no
business-disclosure/withdrawal-information link. Blocked action: verify payment,
lawful terms and delivery before asking another stranger to pay. Acceptance:
pause website purchase calls to action, preserve downloads and existing customer
rights/support, clearly identify the live app's embedded checkout as outside this
containment, and queue account/disclosure/mail access once. Promotion and spend
pause immediately. The existing payment link cannot be deactivated with invalid
credentials; A1 requests that action. This is an operational dependency failure,
not evidence of lack of demand.

## 2026-09-07 — first-day result, 01:10 Europe/Berlin

**Commercial finding:** the handover's “live and sellable” claim is not yet
established. Account access, fulfilment evidence and public business details
prevent a responsible new purchase ask. This is a sales-readiness/distribution
dependency failure under the current access constraints, not a demand test.
The first-day stranger placement is **not achieved**. E1 is prepared and unsent;
do not count it as reach, interest or a failed buyer response. No gate extension.

**Executed:** website purchase calls to action are paused on all four English/
German landing/download pages. Downloads and existing licence/update/refund
promises remain. Corrected “signed by Apple” and “no security warning” claims,
obsolete support bypass instructions and the promise that the developer always
answers. Removed the unverified website assertion that Stripe is this offer's
merchant of record. App source and release binaries were not changed.

The normal Pages workflow deployed the changes in a concurrent owner commit
`2a2db95290c8cb9d958e87ffa4afb1460a186169`. The operator's isolated-checkout push
was rejected because that commit advanced main; a fetch and byte comparison
confirmed it already contained all five intended public files. No overwrite or
force push. [Successful deployment](https://github.com/subtract0/presstalk/actions/runs/34065952885);
[four live page checks](receipts/2026-09-07/storefront-live.json).

**Scope of the pause:** the shipped app still links directly to Stripe. The
payment link was not deactivated because the credentials failed. A1 includes
deactivating new payments while retaining access to past orders and refunds.
Do not describe the entire checkout as disabled.

| Customer step | Evidence / current limit |
|---|---|
| Find and read offer | Live pages HTTP 200. Compatible hardware, model download, three-day trial and advertised €20/$20 appear. No stranger exposure or search-reach measurement. Current purchase pause is visible. |
| Download | Public 0.1.11 ZIP hash matches published SHA-256; Homebrew cask names the same version/hash. Operator checks themselves add download requests. No independent installation count inferred. |
| Authenticity / opening | Deep/strict Developer ID signature passes; attached notarization ticket reported. `spctl` returns an internal signing-subsystem error and `stapler` a LaunchServices error in this environment. These are neither a clean-Mac pass nor proof of a product defect. [Artifact receipt](receipts/2026-09-07/public-artifact.json). |
| Permissions / model / first insertion | Not physically exercised here; A4 pending. Approximate model size and offline recognition remain documented/source-supported claims, not a measured clean download/offline session. Website demo is an explicitly labelled illustration; no real recording exists in the inspected project. |
| Trial / grandfathering | 37 existing tests for entitlement, trial anchor and licensing pass using copies of the unchanged core sources in an isolated package. Those core files and relevant app files match the v0.1.11 tag. [Tests](receipts/2026-09-07/core-tests.txt), [source hashes](receipts/2026-09-07/storefront-source-snapshot.json). Not a GUI expiry test. |
| First-use trial nuance | `recordDelivery` starts the trial even when `reachedTargetApp` is false (clipboard recovery). This is source evidence of a delivery distinction; reproduce during A4 before an app repair. Do not call clipboard recovery successful insertion. |
| Actual checkout / total / MoR | Unverified. Both configured API credentials fail. No browser backend is available. A checkout URL or code comment is not transaction evidence. EUR/USD price/tax and first-25 restriction must be checked in A1 before reopening. |
| Licence issuance | Existing private key matches the public key in the downloaded binary. In-memory test issuance/verification accepts future major versions and rejects tampering. No licence was sold or sent. [Key check](receipts/2026-09-07/license-key-check.txt). |
| Payment → email → app unlock / refund | No test payment made. No authenticated mailbox, delivered licence or app-UI unlock receipt. A1/A2/A4 pending. Existing customer obligations have priority once the inbox/orders are available. |
| Public commercial disclosures | No Impressum/withdrawal-information link found on the fetched sales pages. A3 requests designated public business details; A1 determines the actual checkout seller. No compliance pass claimed. |

**Verification:** existing claims, site privacy, offer-copy, download-link,
privacy regression and offer regression gates passed; Pages CI also passed.
All local HTML pause anchors and support routes checked. These gates do not
verify actual checkout prices, merchant status or customer experience. No browser
visual check was possible. No telemetry or acquisition tracking was introduced.

**Cash and effort:** new discretionary commitments/spend **USD 0**; the recorded
USD 50 cap remains unspent by this turn. Verified independent paying customers:
**unknown**; gross payments, retained contribution, payouts, unsettled balances,
refunds, taxes, fees, historical business expenditure and paid agent execution
cost: **unknown**. [Access/money receipt](receipts/2026-09-07/access-and-money.json).
Operator elapsed time at the 01:10 snapshot: approximately 13 minutes since goal
creation, excluding earlier setup; this is elapsed time, not a billable-cost
estimate. No owner action completed in this session was observed. Owner time
spent in the concurrent working session is unknown and must also be counted.

**Next decision:** restore designated Stripe/mail access, inspect existing
customer obligations, publish supplied business details, and close the physical
and transaction/delivery checks. Then reopen the offer and send one invited
ifun.de submission for German email dictation, using
[the prepared E1 packet](DAY1_CHECKS.md#e1--invited-ifunde-editorial-submission-prepared-not-sent).
Its cash ceiling is zero; review response on 14 September and purchases at the
27 September gate. No new discretionary spending or promotional sends while
these dependencies remain unresolved. Highest-value owner request: **A1**, then
A2 for any existing paid-customer obligations. All requests are in
[ASKS.md](ASKS.md), a 60–80 minute batch after the customer-support reserve.

First weekly review: **14 September 2026**, including actual money and owner
time once accessible. The campaign cannot be called successful from this
turn's repairs, tests or documents. Updated handover text in `GOAL.txt` repeats
some earlier unverified starting claims; this dated evidence takes precedence.

## 2026-09-07 — handover

PressTalk is live and sellable: notarized 0.1.11, presstalk.app indexed, Stripe
checkout at €20 taking money, three-day trial enforced, Homebrew serving the
current build.

Customers: zero. Nobody outside the owner has installed it.

Astra takes over sales from here.

## 2026-09-07 — spending authority granted

Alex: "go, run the first turn you can have 50 dollars budget"

**Discretionary acquisition budget: 50 USD. Hard cap, not a target.**

- Covers what this mandate calls new discretionary expenditure: paid placements,
  tools bought to run an experiment, anything you choose to spend to test a
  route to profit.
- Does not cover and is not reduced by things already paid for: the Apple
  Developer Program, presstalk.app, GitHub, Stripe's fees on real sales.
- Unspent money stays unspent. Spending the cap is not evidence of anything.
- Beyond 50 USD needs a fresh grant. Ask through ASKS.md with the offer,
  placement, cost and stopping rule, and keep working while you wait.

Record every euro or dollar committed here as it is committed, with what it
bought and what it was supposed to establish.

## 2026-09-07 — operator turn 1

Astra takes over under `docs/launch/ASTRA_OPERATOR_BRIEF.md`, the version it
rewrote for itself. Session persists via `scripts/astra_sales_loop.sh`.

Starting position: notarized 0.1.11 downloadable, presstalk.app live and
indexed, Stripe checkout at EUR 20 taking money, three-day trial enforced,
Homebrew serving the current build, zero customers, zero known independent
installations.

## 2026-09-07 01:12 CEST — Hermes takeover verification

**Action:** read the mandate, current log/asks, entitlement source and prior
receipts. Rechecked all four public English/German landing/download pages over
HTTP. Ran `codesign --verify --deep --strict`, `spctl --assess --type execute
--verbose=2` and `xcrun stapler validate` against the previously downloaded
0.1.11 artifact on studio1, without changing or launching the app.

**Observed:** all four pages return HTTP 200, display the purchase pause and
contain no Stripe anchor links. Support links point to the GitHub support guide
and help@presstalk.app; `/support.html` was an assumed path, not the site's
actual support route. All three artifact checks now exit 0. Gatekeeper reports
`accepted`, `source=Notarized Developer ID`; stapler reports validation worked.
This supersedes the earlier environment-error results for these command-line
checks, not the pending clean-Mac/physical insertion test. No extra artifact
download, test purchase, licence send, release or promotion was performed.

Chrome browser automation could not connect without owner remote-debugging
approval. HTTP extraction is not a rendered-browser or checkout verification.
No fresh account access, public seller details, mailbox designation or clean-Mac
result has been supplied. Earlier Stripe 401 results were read, not retested;
no credential files were accessed in this turn.

The old `astra_sales_loop.sh` shell (PID 8064) and its Codex child (PID 8071)
were still present during takeover; the log also changed concurrently. No
process was stopped, background job created, commit made or deployment repeated.
Coordinate a single operator before resuming commercial mutations.

**Inference / decision:** signature/notarization is no longer an unresolved
command-line check. The gating problems remain lawful offer, transaction access,
support and end-to-end delivery, not evidence of failed demand. Preserve the
existing promotion/spend pause; do not multiply channel drafts or engineer
features around unavailable dependencies. A1/A2 have first priority for existing
customer obligations. E1 remains prepared, not sent. Campaign dates unchanged.

**Money / time:** this turn committed and spent USD 0 in discretionary funds;
paid agent execution cost and actual customer money remain unknown. No completed
owner action observed. Receipt:
[hermes-takeover-verification.json](receipts/2026-09-07/hermes-takeover-verification.json).
