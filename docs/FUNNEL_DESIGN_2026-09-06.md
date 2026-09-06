# PressTalk: discovery to a repeated useful action

Design proposal for reconciliation, 6 September 2026. This document does not authorize publication, change prices or existing licence rights, or assert that proposed features have shipped. Product figures supplied in the brief are accepted as supplied, rather than independently remeasured. Channel and provider references were checked during this review.

The decision is to sell a small, repeatable relief: dictate the reply you were about to type, in the app you were already using. Start with German-speaking Mac users who already dictate regularly and dislike paying a subscription. Give them a signed, direct download and a 14-day trial with no account or card. Ask for $20 after they have experienced the result. Do not make people learn to dictate, trust an unsigned binary, and buy unfamiliar software in the same visit.

Nothing makes discovery or purchase inevitable. The most likely commercial failure is that someone gets a successful transcript, then never reaches for Fn again. The present installation barrier is earlier and immediately actionable. Three downloads and no replies tell us neither which people installed nor why they stopped.

## 1. The page

The diagnosis is substantially right, with an important addition: the page teaches a mechanism before establishing a reason to change, and then makes trying or buying feel unresolved.

Specific findings in `site/index.html`:

- The existing headline has good rhythm, but the visitor must supply the use case. Keep that rhythm in the demonstration.
- The hero has no immediate action or price. The main action is a mailto near the bottom.
- A pretend demonstration needs a paragraph explaining that it is pretend. It consumes the attention a real demonstration would earn.
- The first table shows 11.25% WER; a later table shows the default 12.71%. `docs/MEASUREMENTS.md` identifies 11.25% as forced quality-fallback performance. The reader should not have to reconcile configurations.
- The table, illustration, and newer supplied measurements tell different timing stories. The animation waits 618 ms and then types characters out; that extra animation is not the measured paste behaviour.
- “Not benchmarked against any other dictation app” sits immediately before an Apple-engine comparison. There is a technical distinction, but the page makes readers untangle it.
- “Read these honestly,” “Three honest limits,” “not a finished proof,” “What's the catch?” and “not going to pretend otherwise” repeatedly call attention to the seller's caution. Replace them with the actual limitation.
- “Rising to $39 at general release,” the first-25 offer in monetization documentation, and “Prices and availability are not final” leave three different impressions of the offer. Keep $20 as the current offer and reconcile the future-price rule before publishing. Do not use a countdown or invent scarcity.
- Homebrew is a useful secondary install route. It is a poor default introduction for an ordinary Mac buyer.

**Proposed headline**

> Stop typing every word.

**Subhead**

> Hold Fn, speak, let go. PressTalk puts your words in the Mac app you're already using. Speech recognition runs on your Mac. $20 once, no subscription.

**The first 100 words of body copy**

> The reply is already in your head. Getting it into an email should be the easy part. With PressTalk, hold Fn, say it, and let go. Your spoken words appear in the app you were using.
>
> Recognition runs on your Mac, without uploading your voice or dictated text. After the initial model download, it works offline.
>
> I built PressTalk for my own work. I use it daily and cancelled the $15/month Wispr Flow subscription it replaced.
>
> Try it on a reply you actually need to write. If it earns a place on your Mac, it costs $20 once. No subscription.

Attribute the first-person paragraph to Alex, the developer. His cancelled subscription is his history, not a statement of Wispr Flow's current pricing or a claim of feature parity.

**Public-release CTAs, after the trial and signed release work**

> Try PressTalk free for 14 days
>
> No account. No card. Then $20 once if you keep it.
>
> Apple Silicon · macOS 14+ · About 460 MB downloaded during setup

Secondary text link: **Buy PressTalk — $20 once**. Repeat the trial CTA after the demonstration and at the bottom. Never require an email to download. Do not advertise a working trial until the actual commercial build has passed expiry and offline-unlock checks. The current `EntitlementPolicy.swift` explicitly marks expiry advisory.

**Current, unsigned state**

> Get the signed download by email
>
> The public release is waiting for Apple signing and notarization. Leave your email for one release notification. No newsletter.

Use a mailto initially, with a prefilled subject such as “Send me the signed PressTalk download.” This is an explicit email request, not an inferred marketing subscription. Keep the developer preview separately labelled, with the warning next to its download. Do not send a broad launch campaign to this holding state.

**German entry page**

> Sag's, statt alles zu tippen.
>
> Fn gedrückt halten, sprechen, loslassen. Dein Text erscheint in der App, in der du gerade arbeitest. Die Spracherkennung läuft auf deinem Mac. Einmal 20 US-Dollar, kein Abo.
>
> 14 Tage kostenlos testen
>
> Kein Konto. Keine Kreditkarte. Apple Silicon und macOS 14 oder neuer.

Keep currency and the checkout total consistent; do not silently relabel $20 as €20. The German page is a real translated sales page, including download guidance and support expectations, not just a language badge.

**The new scroll order**

1. Pain, mechanism, price, trial CTA, compatibility.
2. One genuine 25–35-second German demonstration.
3. Three ordinary jobs: “The email reply you already know how to phrase”; “The note you want to capture before it disappears”; “The instruction that's easier to say than type.”
4. Alex's replacement story and a compact evidence block.
5. “Will it work for your words?” with the Apple-engine result and a three-sentence personal comparison.
6. Privacy, the actual offer, refund and update terms.
7. Short setup/support FAQ and the final CTA. Homebrew and full measurements are secondary links.

**Demonstration script**

- Show an actual Mail draft, cursor already in the body. Use harmless sample content and the shipped default configuration.
- Hold Fn and say: “Hallo Nina, Donnerstag um zehn passt mir. Ich schicke dir die Notizen vorher.” Release. Show the actual wait and the delivered text without speeding up or substituting a transcript.
- Switch to a local note and dictate one short real sentence. Show that no transcription window or copy step is needed on the normal path.
- Display: “Fn halten. Sprechen. Loslassen. Einmal 20 US-Dollar.”
- Caption with the tested Mac, macOS and PressTalk version. Caption “Recorded on a Mac; dictation shown at actual speed.” Use accurate German and English captions, a poster image, and a self-hosted video. No third-party player on the landing page.
- Make an additional short offline clip in a local note if useful; switch off Wi-Fi visibly after setup. This demonstrates offline operation, not a comprehensive security audit. Do not spend an owner afternoon polishing it.

**Evidence copy**

> I replaced my $15/month dictation subscription with PressTalk.
>
> In my recorded use: 174 dictations across 26 days, with no recorded failures, lost text or crashes.

Label this as the developer's own use. It is stronger than “battle-tested,” and it does not impersonate customer evidence.

> In the measured default-configuration run, text appeared a median 0.618 seconds after key release. The slowest measured result was 0.629 seconds.

Keep the device, version, sample size, date and method with the linked receipt. Those details for the newer run are not established by the supplied brief or the current measurements document; attach them before publishing that claim. “Slowest measured” must never become a universal maximum. Omit the latency tile if the receipt cannot be reconciled yet; the real-speed video can carry the speed impression.

> On our German test set, PressTalk produced about a third fewer word errors than Apple's on-device speech engine: 12.71% versus 19.38%, using the same vocabulary correction on both.
>
> This uses synthetic speech in three voices. It compares recognition engines and does not establish how either product will perform with your voice. The test vocabulary overlaps the correction dictionary. Full method and results →

Put that qualification directly beside the comparison. Do not turn the claim into “33% better German,” “better than Apple Dictation,” or a result about real speakers. Remove the old 11.25% tile and recognition-throughput multipliers from the sales page; preserve historical results with their configurations in the measurement document.

**Copy that connects evidence to a decision**

> Try three things you actually write: a reply, a name or technical term, and a short note. Try the same sentences with Apple Dictation. Include the corrections. Keep PressTalk if it makes that work easier for you.

Honesty persuades when it reduces the reader's uncertainty: a witnessed result, a bounded claim, a precise price, and a reversible personal test. The page over-hedges when it supplies the seller's emotional commentary instead of useful scope. Compress the scope; do not remove it. Lead with the useful result and put the exact limit next to the claim it qualifies.

**Offer copy**

> $20 once. Keep PressTalk on your compatible Macs.
>
> No subscription. No account or activation server. Every future Mac version of PressTalk we release is included, including major versions.
>
> Future development, indefinite support and compatibility with future macOS versions aren't guaranteed.
>
> Not right for you? Email within 14 days of purchase for a refund. No explanation required.

Retain existing pre-paid users' promised free core dictation. They are not expiring trial users, and voluntary contributions from them must be counted separately from normal new-customer conversions.

**Privacy copy**

> Your voice doesn't need a server.
>
> PressTalk does not upload your recordings or dictated text. After the initial model download, dictation and licence verification work offline. There is no app analytics service, crash reporter or telemetry endpoint.
>
> Text passes through the macOS clipboard before it is pasted. Handoff can sync clipboard contents, and the app you paste into handles the text under its own rules. Read the exact privacy details →

Keep the existing explanation of the experimental, explicitly configured assistant mode in the detailed privacy page. Do not advertise its behaviour as the default dictation product. Avoid “nothing ever leaves your Mac” or “zero network activity.” The current privacy document explicitly describes model downloads, clipboard behaviour, destination apps and payment handling. Self-host fonts or use system fonts; the present page loads Google Fonts, an avoidable third-party request even though it is not itself proof of analytics.

## 2. Objections in the order they appear

| Buyer thought | Where it is resolved | Answer or action |
|---|---|---|
| Why would I change what I already do? | Hero and real demonstration | “Dictate the reply you were about to type.” Show text arriving in the original app. |
| Will it understand my German, names and normal voice? | Demo, bounded comparison, free trial | Three personal sentences; compare time including corrections. Do not lead with laboratory WER. |
| My Mac already has Dictation. Why pay? | Immediately below the demo/evidence | Apple Dictation is free. Try both on the same work. Pay for PressTalk if the overall experience earns it; make no blanket superiority claim. |
| Can I trust this developer and download? | Developer attribution, download area, privacy block | Identified developer, public source, signed and notarized build; explain permissions at their prompts. |
| Will setup work on my Mac? | Beside CTA, then setup | Apple Silicon, macOS 14+, approximately 460 MB model download. Direct download; guided permissions; clear ready state. |
| Am I entering another subscription? | Hero, price, checkout | “$20 once. No subscription.” Say exactly what updates cover. |
| What if I pay and it is wrong for me? | Price and checkout | 14-day refund, straightforward email route, same visible terms in both places. |
| What happens if the developer stops? | Offer, before payment | Offline licence, compatible-Mac use, all released Mac updates included, bounded future-development statement. |

Gatekeeper is a release problem, not a wording challenge. Wait for a Developer ID-signed, notarized and stapled release and test the exact downloaded artifact on an unfamiliar Mac before taking strangers through the commercial funnel. Apple signing and notarization are distinct; do not say Apple endorses or has reviewed the app as an App Store app. A normal first-open confirmation can remain after notarization. Apple's current instructions for a deliberately chosen unsigned preview use System Settings → Privacy & Security → Open Anyway; do not publish right-click → Open as a universal modern fix. [Apple's explanation](https://support.apple.com/en-us/102445).

For a separately offered preview, use: “Developer preview — not notarized. macOS will display a security warning. The signed public release is pending.” This belongs immediately next to that preview download, before it is downloaded. Moving the warning below a payment button would not solve the underlying problem.

## 3. Discovery, in priority order

German is the recruitment and demonstration wedge. It is not an established accuracy moat or an empty market. Current products already market German, offline use and a one-time price; for example [AngelWrite](https://www.angelwrite.app/) and [Dictato](https://dicta.to/de/). These pages establish competing offers, not their measured quality. PressTalk's defensible present story is narrow: this developer uses it, replaced a paid subscription, shows it working, and exposes its evidence. Start with existing frequent dictators rather than a general productivity audience.

Hours below are estimates of incremental owner work using agent-prepared assets, including a modest response allowance. They are not simultaneous weekly commitments or guaranteed reach.

| Priority | Specific route | Artifact and title | Owner hours |
|---|---|---|---:|
| 1 | The five existing recipients, then introductions to German-speaking Apple Silicon users who already dictate at least three days/week | One short diagnostic follow-up, then a personal signed-test invitation. Find ten qualified prospects including three outside close friends. | 0.75 initially, 0.75 reviewing results |
| 2 | r/macapps, through its eligible main-feed route or current App Pile megathread | Actual demo and post: “I cancelled my $15/month dictation subscription and built PressTalk: local Mac dictation, $20 once.” Include German use, Apple comparison scope, price, privacy and trial links. | 0.75–1.0 for posting and replies; participation eligibility is extra if absent |
| 3 | ifun.de editorial tips | German review packet. Subject: “PressTalk: Diktieren am Mac ohne Abo — 20 US-Dollar einmalig, lokal auf dem Mac.” Demo, signed download, review licence and bounded comparison. | 0.4 |
| 4 | MacStories, with MacStories Weekly as the specific newsletter target | Personal pitch: “A $20 Mac dictation app that replaced my subscription — review build inside.” Same demonstration with English captions; give editors something they can use themselves. | 0.4 |
| 5 | German Google search | German page titled “Diktieren am Mac ohne Abo: PressTalk für Deutsch”; target “diktieren mac deutsch offline ohne abo.” One useful comparison page: “Apple Diktat oder PressTalk? Deutsch im direkten Test,” targeting “Apple Diktat Alternative Deutsch.” | 0.5 review once, then 0.15/month; roughly 2–3 agent hours |

The r/macapps moderator announcement requires problem/comparison/pricing, limits promotion frequency, and describes transparency/identity/terms requirements or the megathread alternative. Verify the current rules and the owner's actual eligibility immediately before posting; the rules page did not expose its full contents in this review. Use the permitted route, not a promotional reply in another developer's thread. [Moderator announcement](https://www.reddit.com/r/macapps/comments/1ryaeex/rmacapps_mods_went_too_far_whats_changing_phase_3/).

Use [ifun's editorial contact route](https://www.ifun.de/kontakt/). MacStories explicitly tests apps for coverage and distinguishes reviews from paid sponsorship; [MacStories Weekly](https://www.macstories.net/plans/) covers Mac apps, and its [team/contact page](https://www.macstories.net/about/) provides the editorial route. These are pitches for independent coverage. No editorial acceptance or newsletter slot is guaranteed. Do not buy placements for this pilot.

Search is a later source of intent, not next week's customer quota. Today's results are crowded with alternative-dictation pages. I have not established keyword volume, difficulty or a credible ranking date. Publish one genuinely useful German comparison rather than a generic “best 20 apps” article. Add actual independent observations only when obtained, with permission. “Wispr Flow Alternative Deutsch ohne Abo” is a later cancellation-story page if the first two pages earn impressions; do not make three near-duplicate pages now.

Show HN is a later optional event, title: “Show HN: PressTalk — hold Fn to dictate locally on a Mac, $20 once.” Budget 1–1.5 owner hours for discussion if eligible. HN requires a usable project and encourages a low-barrier trial; it has also announced restrictions on Show HNs from unfamiliar/new participants. An unestablished account makes it unsuitable as a required launch dependency. [Show HN guidelines](https://news.ycombinator.com/showhn.html), [posting restriction notice](https://news.ycombinator.com/showlim). Defer Product Hunt, paid ads, r/privacy promotion, a Discord server and daily social content. None fits this owner's present time allowance as well as learning from a few actual users.

**One follow-up for the existing silent recipients**

> Quick PressTalk check: which best describes what happened? Didn't get to it; macOS blocked it; setup got stuck; tried it but preferred something else; or still using it. A few words are enough. I can't see usage, so silence doesn't tell me which. No need to send anything you dictated.

Send once, personally. No reply stays unknown. Do not pursue five reminders or count silence as rejection.

**New tester invitation**

> I use PressTalk for my own German dictation and cancelled the $15/month subscription it replaced. Hold Fn, speak, release; text goes into your Mac app. It will cost $20 once. I'm looking for three people who already dictate regularly to try the signed build in their normal work. The app reports nothing back. If you agree, I'll ask once about setup and once a week later about whether you kept using it. No recordings or dictated text needed.

**Reddit body, ready to adapt to the permitted route**

> I'm the developer of PressTalk. I already relied on dictation; I wanted the hold-a-key workflow without a recurring bill or uploading my speech. I now use it daily and cancelled my $15/month Wispr Flow subscription.
>
> Hold Fn, speak, release, and the text appears in the app you were using. Recognition runs locally on Apple Silicon. The demo shows an actual German reply at actual speed.
>
> Apple Dictation is free, so I compared the recognition engines: 12.71% versus 19.38% word error rate on the same synthetic German clips, with the same vocabulary correction. That's a bounded regression result; please try your own voice and compare the corrections.
>
> The signed release has a 14-day trial with no account or card. It's $20 once to keep it, including every future Mac version of PressTalk we release. Apple Silicon, macOS 14+. No app telemetry. [Demo and download] [Privacy] [Terms] [Developer identity]

The last paragraph is release-stage copy, conditional on a completed and tested trial. Replace bracketed links with real published assets; do not post placeholders.

**German editorial pitch**

> Hallo liebes ifun-Team,
>
> ich habe PressTalk für meine eigene Arbeit gebaut und damit mein Diktier-Abo für 15 US-Dollar im Monat ersetzt. Fn gedrückt halten, sprechen, loslassen: Der Text landet in der geöffneten Mac-App. Die Erkennung läuft lokal auf Apple Silicon. Einmal 20 US-Dollar, kein Abo.
>
> Hier sind eine kurze, unbeschleunigte Demo mit deutscher Sprache, der signierte Download und eine Testlizenz: [Links]. Unser Vergleich mit Apples On-Device-Engine ist offengelegt; die Audios sind synthetisch, deshalb behaupte ich damit keinen Vorteil für jede echte Stimme. Sie können Ihre eigenen Sätze testen.
>
> Falls es für Ihre Leser passt, freue ich mich über eine unabhängige Prüfung. Für Rückfragen antworte ich selbst.
>
> Alex

## 4. First value, first week, referral

The unit of value is a useful sentence delivered into the intended field and accepted after any corrections. A generated transcript or a clipboard copy alone does not establish that experience.

**First session**

1. Direct signed download. Show compatibility and model size before the click. For the public offer, allow trial before licence entry.
2. Open to: “Let's put your first sentence in a note.” Keep the existing sequential setup policy. Explain microphone permission, then the trigger permission if required, then Accessibility for insertion. Explain each immediately before its actual OS prompt.
3. Model download: “Downloading the speech model — about 460 MB. This is what lets dictation work offline.” Visible progress and recovery after interruption; no optional larger-model choice in this first flow.
4. Show “Ready. Open a note, click where you want the text, hold Fn and speak.” Use a harmless sentence of the user's choosing. Let the user confirm “The text appeared in the right place.” Do not call a successful paste API a proven insertion.
5. If it copied instead: “Your words are on the clipboard. Press Command-V to paste. Enable Accessibility for automatic insertion.” Offer Recent Dictations. Keep recovery separate from the successful automatic-insertion outcome.
6. After the first completed sentence: “Now try one reply you actually need to write.” This second dictation in a real task is the meaningful first-session win.
7. “Make this your one use this week: the first email reply longer than two sentences.” Offer launch at login as a clear user choice if implemented; otherwise explain how to reopen PressTalk. No auto-enabled reminders or notification request.

The current setup code already sequences permissions and has a first-dictation step. Improve that flow rather than building a separate onboarding system. Start the trial at the first successful delivered dictation, as the entitlement policy intends. Test the expiry boundary and preserve an in-progress recording/result; the paywall must not discard work mid-dictation.

**First week**

- Day 0: Do the real reply. End the tutorial. The product belongs in the user's normal app now.
- Days 1–3: Repeat that same job. Maintain a dependable ready state, recognisable recording indicator and visible recovery when insertion fails. Avoid tours of additional triggers, benchmarks or model options.
- Days 4–7: Let the user expand into a second app when the same need occurs. Keep the trigger constant. A menu item can say “Try PressTalk in another app”; it does not need an interrupting prompt.
- Day 7: Send the one agreed research check-in to consenting testers. No daily usage reminders in the group from which you want evidence of unprompted return. If users later request a tips sequence, measure that as a different, prompted group.
- Near day 14: A calm, locally determined trial-expiry notice: “Your trial ends in 2 days. Keep PressTalk for $20 once. No subscription.” Actions: “Buy PressTalk” and “Later.” No made-up usage totals or time-saved claims. After expiry: “Your trial has ended. Your settings are saved.” Preserve recovery of existing text.

**Purchase and receipt**

> Keep the shortcut. Lose the subscription.
>
> PressTalk is $20 once, with every future Mac version of PressTalk we release included.

Use an ordinary hosted checkout link. The receipt/fulfilment message says:

> Thanks for buying PressTalk. Your licence is below. Copy it, open PressTalk → Settings → Licence, and paste it there. It is checked on your Mac and works offline.
>
> If PressTalk is already installed, you don't need to reinstall. For help or a refund within 14 days of purchase, reply to this email.

Confirm the exact UI labels against the shipped build. For the first five buyers, manual fulfilment is acceptable only with the delivery window stated before payment, and with continued trial access while awaiting the key. Use the existing pilot's two-business-day maximum. Do not run public discovery into slow manual fulfilment: finish and rehearse order-to-licence delivery before widening exposure. Transaction emails must not silently subscribe the buyer to marketing.

**The one-week research email**

Subject: “Did PressTalk earn a place on your Mac?”

> You agreed to one setup check and this one-week follow-up. I can't see app usage.
>
> On how many days did you use PressTalk this week: 0, 1, 2, or 3+? What did you use it for? If you stopped, what got in the way: setup, corrections, forgetting the shortcut, preferring your old tool, or something else?
>
> A short reply is enough. Please don't send dictated text or recordings.

For a nonbuyer add: “At $20 once, is this worth keeping? If not, what is missing?” A reply is an intention; actual payment is the purchase signal. Referral and quote permission are separate, optional asks only after a positive reply.

**Referral moment**

The best moment is when someone says they reached for Fn automatically, replaced their previous app, or actually cancelled a subscription. The operator can learn that through an explicitly volunteered reply. Do not infer it from the app running.

> Know someone who already dictates on a Mac? You can send them this: “I've been using PressTalk for [my actual use]. Hold Fn, speak, release. It runs on the Mac and costs $20 once. Here's a short demo and a free trial: [link].”

Use an ordinary link. No referral discount, contact upload or tracking ID. An always-available “Share PressTalk” menu item can copy a neutral description; the user edits and sends it. Do not turn an unverified “saved 3 hours” counter into the referral pitch. Ask separately before publishing any user's words, name, Mac details or screenshot.

## 5. Measurement without weakening the promise

Choose **zero new app telemetry and zero site analytics**. The minimum is one local ledger, GitHub asset totals, checkout order/refund records and a small consenting research group. The result is incomplete but decision-useful. It cannot yield a complete visitor-to-habit conversion rate, identify every anonymous user's exit, or measure population retention.

| Stage | Available signal | What it does not establish |
|---|---|---|
| Discovery | Known personal invitations; community post views if the platform exposes them; replies; later search impressions/clicks reported by the search engine | A post view is not a site visit or a qualified buyer. Some platforms provide no usable reach count. |
| Interest | Explicit signed-release requests, questions, trial requests; release-asset download increments | Download requests include repeat downloads, upgrades and automation. They are not unique visitors or installations. |
| Installation and first value | Consenting testers' answers about installation and text in the intended app | Silence is unknown. Permission success, text generation and licence issuance are not proof of this outcome. |
| Purchase | Completed paid orders, successful fulfilment and refunds | No purchase does not distinguish checkout abandonment from never visiting checkout. |
| Habit | One-week replies, reporting use on 3+ distinct days and a concrete recurring task | Response selection and self-report bias remain. This is a sample of respondents, not all users. |
| Referral | “Who sent you?” voluntary answer; permissioned recommendation or introduction | An untagged shared link will usually have no attributable sender. |

GitHub's release-asset API provides `download_count`; take a dated baseline for the exact public asset and inspect changes at the weekly review. Keep separate versions separate. Note known test downloads without pretending to deduplicate the whole population. [GitHub release assets](https://docs.github.com/en/rest/releases/assets).

Homebrew supplies aggregate analytics with opt-outs. Check whether this project's third-party cask/tap appears in the available public reports before treating it as a signal. Its present availability here has not been verified. Do not add anything to the cask, request that users enable analytics, or sum Homebrew counts with GitHub downloads: a Homebrew install can fetch the same GitHub asset. Even when available, these are partial install-related counts, not active users. [Homebrew analytics](https://docs.brew.sh/Analytics).

For the five-buyer pilot, review/export Lemon Squeezy orders and refunds manually. No measurement server is needed. When automated licence fulfilment is required, its transaction receiver may handle `order_created` and `order_refunded`, with webhook validation and duplicate handling. That is disclosed purchase processing; the app never contacts it. Do not invent a `checkout_started` webhook or claim a reliable abandon rate from these events. [Lemon Squeezy event types](https://docs.lemonsqueezy.com/help/webhooks/event-types).

For source attribution, start with an optional “Where did you hear about PressTalk?” in the purchase reply or agreed research conversation. Record unknown if unanswered. Later, a static channel label can accompany a checkout link, visibly disclosed, with no user identifier, cookie, fingerprint or app event. Lemon Squeezy supports checkout custom data, but it only helps when that particular link survives to purchase; it cannot reconnect an anonymous trial download to a later generic in-app checkout. This is optional, not part of the initial instrumentation. [Checkout custom data](https://docs.lemonsqueezy.com/help/checkout/passing-custom-data).

For search later, use Search Console's search-side impressions/clicks with file/meta or DNS ownership verification. Do not add a site analytics tag. These reports describe Google search performance, not all traffic or the rest of the funnel. [Search Console performance report](https://support.google.com/webmasters/answer/7576553).

**Research consent text, unchecked**

> I'd like to help improve PressTalk. You may email me once about setup and once after a week. Participation is optional and doesn't affect the app or my licence. No app activity, audio or dictated text is sent automatically. Reply “stop” at any time.

Store consent date, the two allowed contacts and only the outcomes the person supplies. Keep the operational ledger local with minimal access. Do not attach full support logs to it. Delete identifiable research notes after a defined short window, proposed 30 days after the final check-in, unless the person separately agrees to ongoing contact. Keep required purchase records separately from voluntary research. Record consent for public quotations separately.

**Research ledger fields**

`participant alias | recruitment source | consent date | compatibility confirmed | tried installation? | first useful text in intended app? | setup minutes | returned on 3+ days? | recurring task | purchased? | refunded? | volunteered blocker | next agreed contact`

Use `yes`, `no` and `unknown` distinctly. Separately keep weekly aggregate asset counts, order/refund totals and owner support minutes. Join identified research outcomes to purchase records only within the research purpose the participant agreed to. Do not join anonymous people by IP or device signature.

A useful report reads: “10 qualified invitations; 6 agreed; 4 confirmed first text; 2 reported use on 3+ days; 3 bought; 0 refunded; 2 participants haven't replied.” Those are illustrative numbers, not current results. At this size, report counts and concrete reasons, not precision percentages or A/B-test winners. If 4 of 10 people answer and 3 report continued use, say exactly that; do not say 75% retention.

**How the ledger leads to a decision**

- Invitations get no affirmative replies: change the prospect selection or invitation. You have not located an app-quality failure.
- People agree but cannot install: fix packaging, permissions or model download before promotion.
- People install but correct more than they want: inspect the specific failure privately with explicit consent; improve that defect if feasible or narrow the audience. A synthetic WER improvement does not overrule them.
- People get value but forget Fn: reinforce one recurring job and make readiness reliable; do not add more features to tour.
- People use it repeatedly but do not buy: ask whether the price, purchase flow, missing capability or existing free access explains it. Distinguish grandfathered users.
- Orders arrive but licences/setup stall: fix fulfilment, not acquisition.
- Returning buyers voluntarily introduce others: reuse their actual job and words, with permission, in the next demonstration.
- Downloads rise without replies: installation and retention remain unknown. Ask a new consenting sample; do not deploy hidden analytics to fill the gap.

No new in-app usage counter is necessary for the first ten prospects. If manual recollection becomes the specific limiting issue later, offer an unchecked local-only seven-day summary: number of dictations and days used, no content or destination-app names, no identifiers, and automatic local deletion after the window. Show its contents before “Compose feedback email”; the person must send the email themselves. Explain that counts of text production do not prove correct insertion. This would be an explicit product change and privacy-document addition. It must not introduce a telemetry endpoint, even for opted-in users.

## 6. Assets and build order

This follows the existing two-week pilot's signed-install gate and five-buyer limit. The newer user brief governs current product facts, including 0.1.8 and the completed offline licence work. The older document's empty-key assertion is not treated as current. The trial policy's advisory status remains visible in current source and needs verification in the actual build before trial marketing.

| Order | Concrete deliverable | Responsibility |
|---|---|---|
| 1 | One offer/claim sheet: current $20 price, update rights, trial behaviour, grandfathering, support/refund text, version/configuration-tagged evidence and unresolved timing receipt | **An agent can write this unattended**; owner reconciles future-price policy with the parallel proposal |
| 2 | Follow-up message for the five recipients; ten-prospect invitation; consent and two check-in drafts; local research ledger | **An agent can write this unattended** |
| 3 | Finish store application/business and payout details; manage signing identity; answer platform approval questions | **Needs the owner**; do this while copy and packaging are prepared |
| 4 | Prepare release signing/notarization/stapling procedure, direct exact-artifact download, Homebrew secondary link, guided setup fixes, trial/expiry/unlock verification | **An agent can write this unattended**; actual identity use and unfamiliar-Mac testing require the owner/test participants |
| 5 | Make the real demo recording in German, including visible insertion and actual delay | **Needs the owner**, target 25–30 minutes |
| 6 | Assemble EN/DE pages, captions, video poster, social preview image, FAQ, full-method link and lightweight self-hosted assets; prepare publication | **An agent can write this unattended** |
| 7 | Reconcile and publish the actual offer, privacy, terms, support, compatibility and purchase-delivery window; prepare checkout and receipt copy | **An agent can write this unattended** for drafts; live commercial setup and publication **needs the owner** |
| 8 | Three actual fresh-install/return checks and one signed-to-signed update check; invited users observe their own Macs | **Needs the owner** to recruit and review; testers do the installation/use |
| 9 | Rehearse paid order → offline licence → import → restart, and refund handling; fulfil at most five pilot orders within the disclosed window | **Needs the owner** for live payment/fulfilment; agent prepares verification and draft replies |
| 10 | Public trial-to-purchase/receipt delivery that works without waiting for a personal reply; technical order processing if needed | **An agent can write this unattended**; live payment integration and final acceptance **needs the owner** |
| 11 | r/macapps eligible-route post, comparison/identity/privacy/terms links and concise answers to likely questions | **An agent can write this unattended**; owner publishes and discusses |
| 12 | ifun and MacStories review packets with the same video, exact build and licence; one personal pitch each | **An agent can write this unattended**; owner checks and sends |
| 13 | German comparison page, sitemap, page titles, canonical links and search verification instructions; optional real domain after pilot evidence | **An agent can write this unattended**; registration/publishing/verification **needs the owner** |
| 14 | Day-seven review, permissioned customer quote, simple referral message and final weekly ledger | **An agent can write this unattended** from provided evidence; owner requests consent and contacts people |

Do not add CRM, newsletter production, behavioural analytics, referral software or an automatic usage-email pipeline to this list. A static site on an existing host, personal email and a local ledger suffice for the pilot. Do not block it on a new domain. A coherent domain can follow before ongoing public promotion; no domain availability or purchase is assumed here.

**Owner calendar**

- Week 1: 30 minutes administration, 25 minutes real demo, 25 minutes personal invitations, 10 minutes review. Total 90 minutes; keep 30 minutes reserve.
- Week 2: 45 minutes reviewing asynchronous install/use results, 30 minutes checkout/licence rehearsal, 15 minutes pilot offers or responses. Total 90 minutes; keep 30 minutes reserve. Approval delays move dependent work rather than manufacturing a launch date.
- Week 3: 30–60 minutes on agreed follow-ups, fulfilment and support. Keep the five-buyer cap while refund windows and return behaviour are assessed. Agents prepare public assets and automate fulfilment if needed.
- Week 4, only if the pilot passes and public fulfilment is ready: 45–60 minutes for the one eligible Reddit post and replies, 30 minutes support/review, 15 minutes approval of the next packet. Stay below two hours.
- Week 5: one German editorial pitch and support/review, about 60 minutes total.
- Week 6: one newsletter pitch and search-page review plus support, 60–90 minutes total. Skip any new channel if support consumes the allowance.
- Thereafter: one 15-minute ledger review, 30–45 minutes support, and at most one 30-minute discovery action each week. An agent refreshes counts on demand; no new background job is required.

Agent engineering, drafting and page preparation need their own estimate. Preserve the existing first-fortnight eight-hour engineering allowance as a pilot cap; if the actual trial/release work does not fit, delay promotion instead of moving the overrun into the owner's evenings. Later public assets/fulfilment are additional agent work, provisionally another 6–12 hours, subject to the actual missing code. These are estimates, not a claim that completion is one checkout-link edit away.

**The decision to widen distribution**

Retain the existing pilot gates: three fresh installs reach useful text unaided within 15 minutes including model download; actual dictations arrive in the intended fields; signed replacement preserves permissions; at least two independent users return on three days. Seek three actual buyers among ten qualified prospects, with two reporting repeated use, including evidence outside close friends. Keep the first five customers' support/refund window manageable before widening. A confirmed lost or misdirected dictation, repeated installation failure, two refund requests among five, or more owner support than the weekly allowance pauses new promotion and sales while the particular problem is addressed. Preserve existing buyer rights and support obligations.

These are small-pilot operating decisions, not statistical proof of a market. If the group uses it but won't pay, examine the offer and checkout. If they buy but don't use it, another sales-page rewrite will not create a habit. If qualified people will neither try it nor respond, the immediate acquisition approach has failed and should be changed once, within the time cap, before more assets are commissioned.

The next owner hour should buy three things: the administrative path to a trusted download, one true demonstration, and permission to learn what happened to the people who already received it. Further recognition benchmarking is not the next sales asset.
