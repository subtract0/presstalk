# Asks

One queue, maintained by the PressTalk operator. Unanswered requests are
unavailable capacity, never consent. Access, lawful sales and physical testing
can have real blockers. Campaign deadlines in [LOG.md](LOG.md) do not move.

## Current owner status — A1–A4 closed by Alex

Alex's latest instruction: "consider a1-a4 done". A1–A4 are closed as owner
requests on that confirmation; older pending/partial labels below are history.
The operator owns verification and must not repeat the original setup batch.
This records owner-reported completion, not invented test measurements or a
claim that every customer-path check has independently passed.

In particular, the preceding entry recorded a missing service address and an
Impressum deployment guard. Locate the completed disclosure and any supplied
test evidence before relying on them; preserve the guard if the address is
still a placeholder. Escalate only a specific remaining blocker that cannot
be resolved from available access and artifacts. Campaign gates are unchanged.

## 2026-09-07 — one owner session, 60–80 minutes estimated

Reserve **60 of the 180 weekly minutes for existing customer obligations first**.
This batch plus that reserve totals 120–140 minutes; earlier owner time this week
is unknown. Stop the optional recording if customer work needs the time.

| ID / priority | Exact action | Alex time estimate | Commercial consequence | Best available alternative / material |
|---|---|---|---|---|
| A1 / customer obligations, pending | Reauthenticate the **PressTalk-designated** Stripe account with `stripe login` in your normal terminal, or provide scoped live read/refund and test access via a secure local credential location. Confirm the account is designated for PressTalk. Inspect the existing payment link and temporarily deactivate new payments while fulfilment and seller terms remain unverified; keep historical orders/refunds available. Do not change payout details. | 10–15 min | Existing live key returns HTTP 401 invalid; test key returns HTTP 401 expired. Without records the operator cannot find outstanding deliveries/refunds, count customers, reconcile money, or verify the actual payment arrangement. The shipped app still contains the Stripe URL even after the website pause. | Export PressTalk orders, refunds/disputes, balance transactions, payouts and the payment-link/product configuration to a private local file, identifying the location here; do not commit customer data. Dashboard checks and exact fields: [DAY1_CHECKS.md](DAY1_CHECKS.md). |
| A2 / customer obligations, pending | Identify and provide delegated read/send access to **help@presstalk.app**, including its inbound route. Name an existing authenticated mailbox/tool or secure credential location; do not paste secrets into chat. | 5–10 min | Enables checking undelivered licences, support and refunds, testing delivery, and sending the one invited editorial submission. A mailbox name or DNS record alone does not prove delivery. | Alex checks the inbox and sends the prepared licence/support messages in the same session, then records sent/delivered evidence. This consumes recurring owner capacity, so delegation is preferred. No mail connector is callable here; local sendmail is not a verified PressTalk sender. |
| A3 / lawful offer, pending | Supply the business name/legal form, public service address and applicable register/VAT details designated for PressTalk's Impressum. Confirm the public contact details. Do not substitute a private Stripe billing address. | 5–10 min | Current storefront has no Impressum or withdrawal-information link. These details are needed for the commercial page; the actual merchant-of-record arrangement determines the checkout seller/withdrawal information. | Supply an existing approved public business-disclosure URL to reuse. The operator will prepare and publish the page and reconcile checkout terms once facts/access exist. Required fields and links are in [DAY1_CHECKS.md](DAY1_CHECKS.md). |
| A4 / delivery evidence, pending | On an Apple Silicon Mac that has never run PressTalk (or a clearly labelled clean test environment), follow the **customer download**, permissions, model setup, physical Fn and insertion sequence in the packet. Record actual Mac/macOS/app versions, steps and failures. Optionally record the same useful German email reply at actual speed, with invented recipient details. | 35–45 min, including a 5–10 min recording if setup passes | Establishes whether strangers can get their first useful text. Current signature check does not establish physical Fn, permission prompts or insertion. The website currently contains a labelled illustration, no real demo. | An authorized clean-Mac tester can perform it; free/test licences and favours are excluded from demand counts. Without the human check, first-run delivery and a genuine demonstration remain unverified. Do not ask for a daily appearance. |

No owner time has been observed completing these actions. Questions about the
public business details and designated mailbox were raised in this session;
keep their status pending until answered. Independent work: artifact checks,
bounded copy repair, policy verification, exact accounting setup and one invited
submission packet. New paid promotion and discretionary spending are paused.

## 2026-09-07 01:12 CEST — takeover-specific dependencies

Existing A1–A4 remain pending; no repeat credential request or extra campaign.

| ID / priority | Exact action | Alex time estimate | Commercial consequence | Best available alternative / material |
|---|---|---|---|---|
| A5 / browser verification, pending | In Chrome, approve the “Allow remote debugging?” prompt opened by the operator. If no prompt appears, untick and re-tick the checkbox at `chrome://inspect/#remote-debugging`. Confirm here when approved; expect one additional Allow prompt when the tool connects. | 1–2 min | Enables rendered stranger-path and checkout inspection, but does not replace A1 or a test payment/delivery. | Continue public HTTP checks; already completed on four pages. Or perform the checkout inspection in DAY1_CHECKS.md during A1 and return observations. No browser retry until approval. |
| A6 / single-operator handoff, pending | Confirm the previous Codex sales turn has finished and its parent loop will not launch another turn. If still running, stop it from its original controlling terminal after its receipt is written, then designate this Hermes session as the sole operator. Observed at takeover: shell PID 8064, Codex PID 8071; recheck identities before any stop. | 1–2 min | Avoids duplicate spending, outreach or conflicting edits; the prior turn was still writing this log while Hermes inspected it. | Let the previous turn finish and report here; Hermes stays read-only on commercial systems in the meantime. No process-kill action is assumed authorized. |

Gatekeeper and stapler checks now pass on studio1; this removes their earlier
command-line uncertainty, not the human A4 requirement. Evidence is in
`receipts/2026-09-07/hermes-takeover-verification.json`.

## A2 update — designated operator mailbox

Alex designated `appsias@tuta.io` as the account created for the operator and
said he will forward email to it. The supplied Tuta screenshot confirms the
address, not completed forwarding or operator access. A2 is partially supplied:
mailbox identified; inbound forwarding, authenticated access and reply delivery
remain unverified. No QR code or key fingerprint is retained here.

Remaining owner action: identify where this mailbox is already signed in
(browser or Tuta desktop app), or sign in personally and name that surface.
Estimate: 1–3 minutes if credentials are at hand. Do not send passwords in chat.
Commercial consequence: the operator can then test the designated support route
and determine the actual reply identity before handling customer messages.
Alternative: owner forwards relevant messages into this conversation temporarily;
this is not a scalable support route and does not establish sending access.

### A2 follow-up — forwarding configured, Brave session identified

Alex's next screenshot shows `help@presstalk.app` forwarding to both
`appsias@tuta.io` and `mail@alexmonas.com`. Alex identified the logged-in
Brave tab; a live desktop capture confirms Tuta settings for `appsias@tuta.io`.
Mailbox designation and signed-in surface are supplied; no further login
request is needed now. Delivery and sending remain untested. An attempted
background navigation click was refused for out-of-window coordinates; no
message was sent. A subsequent capture showed Alex had moved to Stripe, so
operator interaction stopped rather than competing with his active session.

### A1 follow-up — CLI access restored

After Alex completed `stripe login`, `stripe get /v1/account` succeeded:
account `acct_1RNuHyJpvh3XLeRl`, charges and payouts enabled. A live-mode
payment-link lookup found the exact shipped PressTalk URL, link
`plink_1UCjsiJpvh3XLeRlvwQnSfDk`: active, EUR, `managed_payments.enabled=true`,
automatic tax enabled with liability assigned to Stripe. The lookup was a
partial account-wide page, not a complete sales inventory. No customer count
or successful payment-to-licence delivery is established by these checks.
The login portion of A1 is complete; no further authentication action is
requested now. Remaining order, fulfilment and offer checks are operator work.
No payment link, payout setting or credential was changed by the operator.

## 2026-09-07 — answered by Alex

- **A1 Stripe access — DONE.** Alex reauthenticated the PressTalk Stripe
  account. Retest before relying on it: the earlier 401s were read from a
  previous turn, not re-run.
- **A2 support mailbox — DONE.** `help@presstalk.app` forwards to
  `appsias@tuta.io`, which Astra has access to. Inbound only via the forward;
  confirm what sending as help@presstalk.app actually requires before promising
  a reply address to a customer.
- **A3 Impressum — PARTIALLY ANSWERED.** Alexander Monas / Unpolished
  Consulting (Geschäftsbezeichnung, not a legal form) / Freiberufler, Finanzamt
  Dortmund-Hörde / USt-IdNr DE315582692 / help@presstalk.app.
  `site/impressum.html` is written and linked from both homepages, discreetly,
  in the footer.
  **Still missing: the ladungsfähige Anschrift** — a real street address where
  post can be served. § 5 DDG does not accept a PO box or an email address
  alone, and it is the one field nobody but Alex can supply. The offer gate now
  refuses to deploy the site while the placeholder is present, so an Impressum
  that looks complete but is not cannot reach production.
  alexmonas.com has no Impressum to copy from — checked.
- **A4 clean-Mac delivery test — still open.**
