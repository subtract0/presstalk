# PressTalk acquisition: a $500 decision, spent in stages

Prepared 6 September 2026. Executable drafts and decision rules; no campaigns are
live. Target German-speaking people in Germany who want to dictate into their
Mac apps. Every paid click goes to `/de`: **Gedacht. Gesagt. Geschrieben.**

## Before the first dollar

Ship and personally verify the notarized install, German page, real demonstration,
proposed 3-day local trial, offline purchase entitlement, and Lemon Squeezy
checkout. The trial is a launch requirement, not a feature this document establishes
as shipped. Start it on first successful dictation; require no account or card.
Do not run the trial ad until it is true.

Set the $20 price to include applicable tax in Lemon Squeezy. Advertise the currency
explicitly: **20 US-Dollar**. Check the actual checkout total. The later $39 price
is a plan, not a crossed-out historical price or an invented deadline.

## The maximum budget

Amounts below are US-dollar allocations. At setup, convert each cap to the ad
account's billing currency at the actual rate, record it, and reserve any
nonrecoverable billing tax within the cap. Never round the total upward. This
is a maximum, not a requirement to spend all $500.

| Allocation | Maximum | Release condition |
| --- | ---: | --- |
| Five first-use research sessions | $100 | Five unrelated consenting Apple Silicon Mac owners, $20 each for their time |
| Google Search, first tranche | $100 | First-use and checkout gates pass |
| Google Search, second tranche | $100 | First tranche produces at least ceil(actual spend / $8) source-supported, nonrefunded orders after its evaluation window; 13 if all $100 was spent |
| Reddit demonstration test | $100 | Unrelated buyers and source evidence exist; demonstration and trial work |
| Repeat the strongest passing campaign | $100 | Observed CAC at most $8 after refund reconciliation |
| **Maximum** | **$500** | Unreleased money remains unspent |

Run one paid campaign at a time. Do not release a second tranche while waiting
for the first one's buyers. Do not move failed Search money into Reddit automatically.

## First-use research: $100

Recruit five unrelated German-speaking Apple Silicon Mac owners. First prepare one
paid usability request for `r/SampleSize`, checking its current rules and required
flair/demographic format. Cap setup and replies at 30 minutes. After 72 hours, if
still short of five, prepare one moderator-approved research request in the current
`r/macapps` App Pile, with another 15-minute effort cap. Do not cold-DM members.

An [existing paid usability post](https://www.reddit.com/r/SampleSize/comments/1uov8ix/paid_usability_study_for_an_email_management_app/)
and the [September App Pile](https://www.reddit.com/r/macapps/comments/1w4brkd/megathread_the_app_pile_september_2026/)
show possible routes, not permission or account eligibility. Recheck before use.
These are draft execution instructions, not authorization to send today. If
permission or volunteers remain unavailable, complete any sessions arranged,
retain unused money and name the result **recruitment failure**, not product
failure. Advertising remains paused until five sessions are completed.

Offer $20 for a 15-minute observed setup session, regardless of success or opinion.
Explain the research, get consent, and let people decline recording. Observation
can happen without storing audio. Their purchases never count as market demand.
Never require a testimonial.

Ask each person to install, finish setup, and dictate their own real sentence into
Mail or another app they use. Give no rescue instructions during the attempt. At
least four of five must complete a first dictation without help. Record where each
stops and whether the result is usable. Lost text or a broken install must be fixed
before ads. Five sessions find obstacles; they do not establish a population-wide
activation rate.

Invite one optional follow-up on a different day: did the person choose to use
PressTalk again for a real task? Seek at least three of five voluntary repeat-use
reports before buying clicks. This is an observation gate, not telemetry or a
purchase metric. Declining or reporting no repeat use does not affect payment.

## Google Search: two separate $100 decisions

Create the first campaign with a **$100-equivalent campaign total budget**, start
and end dates seven days apart. Create a separate second campaign only if the first
passes. Google supports total budgets for new Search campaigns; an average daily
budget is not a hard seven-day cap.

- Google Search only. Disable Search partners and Display expansion.
- Germany; choose people present in or regularly in Germany, excluding interest-only
  location targeting. German language.
- Computers only; exclude mobile and tablet. This does not identify macOS or Apple
  Silicon. Qualify with search terms, ad copy and the page.
- Manual CPC, maximum $0.60 equivalent per click. If unavailable, use Maximize Clicks
  with that bid ceiling. Do not raise bids to force delivery.
- One ad group, one responsive search ad. Disable automatic application of
  recommendations and automatically created text assets for this test. No broad
  match, Performance Max, remarketing or customer lists.
- First source: `/de?source=google_de_fn_01`; second: `google_de_fn_02`.
  Keep the rest of the page unchanged between tranches.

Exact-match keywords:

```text
[diktier app mac]
[sprache zu text mac]
[offline diktieren mac]
[diktieren mac deutsch]
```

Initial negative terms:

```text
kostenlos
gratis
free
windows
android
iphone
ipad
jobs
stellenangebot
audiodatei
datei transkribieren
video transkribieren
transkriptionsdienst
```

Exact match can still serve close variants. Review actual search terms at two
scheduled checkpoints during the week; exclude unrelated intent. Do not exclude
all uses of `transkription`, which can describe the intended job.

### The ad, exactly

| Asset | Copy | Characters |
| --- | --- | ---: |
| Headline 1 | Sprich statt zu tippen | 22 / 30 |
| Headline 2 | Diktieren am Mac | 16 / 30 |
| Headline 3 | 20 US-Dollar. Einmalig. | 23 / 30 |
| Description 1 | Fn halten, sprechen, loslassen. Dein Text steht in deiner App. Für Macs mit Apple Silicon. | 90 / 90 |
| Description 2 | Nach der Einrichtung offline diktieren. 3 Tage testen, ohne Konto und ohne Karte. | 81 / 90 |

Final path `/de`; display path `mac/diktieren`. Pin the Mac headline where supported
so every served combination describes a Mac product. Do not add an accuracy
guarantee or speed number.

### When the answer arrives

Delivery lasts seven days. Read paid sales **21 days after the last campaign
click**, then reconcile each purchase again **14 days after its purchase date**.
Do not release another tranche on purchases whose refund window has not been
reconciled. Late trial starts and orders are later evidence; the 21-day cutoff
is a practical decision date, not complete lifetime attribution.

Required supported orders are **ceil(actual campaign spend / $8)**, after refunds.
At a fully spent $100 tranche, that is **13 orders**, or CAC of $7.69. At $48 it
is six. Passing earns a repeat, not a declaration of proven scale; a handful of
sales is weak evidence even when it passes the arithmetic.

If the bid cap yields fewer than 50 clicks in a week, report **insufficient
affordable search volume**, not **no product demand**. Keep the unspent money.
Evaluate reach separately from CAC: a few cheap sales can justify one equally
small repeat while still showing that Search is unlikely to deliver meaningful
volume at this bid ceiling.

## Reddit: $100 only after buyers exist

Use Reddit Ads, website-traffic objective, one ad group, Germany, German creative
and `/de?source=reddit_de_fn_01`. Select community audiences for `r/macapps` and
`r/mac` if available. These are associated audiences, not guaranteed placements
inside those subreddits. Use desktop-only delivery if offered. Disable automated
audience expansion; do not layer broad interests into this test.

Set a five-day lifetime budget and campaign cap of at most $100 equivalent. Use a
$0.35-equivalent CPC ceiling if the current manager supports it. If those controls
cannot be set, retain the money; do not substitute uncapped automation. The narrow
German audience may fail to deliver enough traffic. That is an acceptable result.

### The creative, exactly

Promoted video title:

> Die Antwort ist schon im Kopf. Sprich sie aus.

Body:

> Fn halten. Sprechen. Loslassen. Dein Text steht in deiner App. PressTalk für Macs
> mit Apple Silicon. Nach der Einrichtung offline. 3 Tage testen, ohne Konto und
> ohne Karte. 20 US-Dollar, einmalig.

CTA: **Download**, or the available platform equivalent.

Use a genuine 10–12 second continuous German screen recording: empty Mail draft,
visible Fn indicator held, this spoken sentence, release, actual insertion:

> Hallo Anna, Donnerstag um zehn passt. Ich schicke dir die Unterlagen heute.

Captions, in order: **Gedacht.** / **Gesagt.** / **Geschrieben.** End with
**PressTalk · 20 US-Dollar einmalig**. Capture at normal speed and leave the result
readable. Audio contains the spoken sentence; captions communicate the action when
muted. Trim idle time outside the action if needed; never accelerate recognition
or substitute animated output. Do not buy traffic to an illustrated placeholder.

Use the same sales and refund windows as Search and the same actual-spend formula.
Thirteen supported, nonrefunded orders is the threshold only if all $100 was spent.
Video views and downloads alone earn no more budget.

## Arithmetic and stop rules

Illustrative German card order at $20 including 19% VAT:

```text
($20 / 1.19 - ($20 * 6.5% + $0.50)) * 99% = $14.86
```

This uses Lemon Squeezy's published base fee, international surcharge and non-US
bank payout fee. PayPal can cost more. It excludes refunds, support, income tax
and other costs. At $39, the same illustration gives $29.44. Recalculate from
actual settled order fees when sales arrive.

Founder **target CAC: $8**. At $0.50 CPC that requires 6.25% click-to-purchase
conversion; at $1 CPC it requires 12.5%. These are arithmetic hurdles, not forecasts.

| Mature observed result | Decision |
| --- | --- |
| CAC at most $8, supported orders at least ceil(actual spend / $8) | Repeat once using the next allocation; no open-ended daily budget |
| CAC above $8 and below $15 | Pause, inspect objections and checkout friction once; do not scale or release the next Search tranche |
| CAC at least $15, or no orders after the evaluation window | Stop, subject to the source-uncertainty rule below |
| Attribution range spans passing and failing CAC | Keep paused; report uncertainty, not a win or loss |

At $20, broad cold advertising is not a credible default business model. These tests
give a narrow channel a chance to prove otherwise. If it cannot, stop buying traffic.
Use the durable demonstration, a useful German workflow page, permitted community
participation and selective editorial or commission-only creator outreach. None
guarantees traffic. Allocate $0 initially to Meta, TikTok, LinkedIn, display, paid
launch directories and sponsorships. An affiliate signup page alone recruits nobody.

## Measurement without anything inside the app

Record spend and billed clicks, aggregate web download requests, checkout orders
and refunds. Requests include retries and bots; they are not unique people,
installations or successful dictations. First-use success comes only from consenting
observations and voluntary feedback.

Carry a coarse campaign source through links on the current page into
`checkout[custom][campaign]`. Lemon Squeezy returns this data in order webhooks.
This website/checkout implementation is required: ordinary UTM parameters do not
magically become an order export field. Retain the order's campaign label for
reconciliation and publish aggregate results.

No campaign markers in the binary, local preferences, trial state or license. No
app calls, pixels, identifiers or activation events. No fingerprinting or
cross-session browser tracking. Returning direct buyers have an unknown source.
Ask optionally on purchase confirmation: **Wie hast du PressTalk gefunden?**
Choices: **Google-Suche**, **Reddit**, **Empfehlung**, **Anderswo**, **Weiß ich nicht**.
Keep self-reported sources separate from supplied campaign labels.
Broad answers such as Google-Suche do not establish that an ad caused an order;
supporting paid attribution requires a campaign label or an explicit voluntary
report of seeing that ad. Otherwise keep the order unknown for paid CAC.

Report a range: source-supported orders are the lower bound; those plus all
otherwise-unknown eligible orders are the generous upper bound for the only active
campaign. Exclude research participants, tests, owner orders and refunds from both.
Continuing needs the lower bound to pass. A firm economic stop needs even the upper
bound to fail; otherwise remain paused with uncertainty. Do not call this an exact
trial-to-purchase funnel.

## Owner time

- Initial launch/research: 5–6 owner hours for recruitment, sessions, creative reuse,
  campaign setup and checkout/source checks.
- Separate one-time product implementation estimate: 12–20 hours for the missing
  trial, website and checkout work. This is an estimate to verify during build,
  not work hidden inside the launch allowance.
- Ongoing: **two hours a week total**. Thirty minutes for acquisition/order review
  (two 15-minute checkpoints in paid weeks), 45 minutes support/refunds, 30 minutes
  for one distribution batch or extra test reconciliation, 15 minutes reserve.
- If support or reconciliation exceeds that allowance, pause the next campaign.
  No daily posting schedule or always-on community duty.

Fixed budgets and end dates make scheduled reviews possible. Do not create a daily
operational job to sustain a $20 product.

## Sources checked for this draft

- [Lemon Squeezy fees](https://docs.lemonsqueezy.com/help/getting-started/fees): base,
  international, PayPal and payout fees used above.
- [Tax-inclusive pricing](https://docs.lemonsqueezy.com/help/payments/sales-tax-vat):
  the displayed price can include applicable tax.
- [Checkout custom data](https://docs.lemonsqueezy.com/help/checkout/passing-custom-data):
  explicit custom fields and webhook delivery.
- [Google campaign total budgets](https://support.google.com/google-ads/answer/10486938?hl=en-GB):
  Search support, three-day minimum duration and fixed total cap.
- [Google device targeting](https://support.google.com/google-ads/answer/1722028?hl=en-AU):
  computers targeting does not establish an Apple Silicon audience.
- [Reddit targeting](https://www.business.reddit.com/learning-hub/articles/how-reddit-ads-targeting-works-for-smbs):
  community audiences.
- [Reddit budgets](https://www.business.reddit.com/learning-hub/articles/reddit-advertising-costs):
  lifetime budgets and campaign caps. No unverified platform minimum is claimed.
