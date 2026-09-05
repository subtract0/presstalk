# Go to market: the plan three models agreed on

Historical decision record. The [5–18 September two-week plan](TWO_WEEK_PLAN_2026-09-05.md)
supersedes the sequencing and commercial gates below; these earlier arguments
remain for traceability.

2026-09-05. Claude, a local frontier model (ddalcu-flashnext on studio1), and
GPT-6 Astra argued this out over two rounds. Where we disagreed is recorded, and
so is who conceded.

## The short answer to "should I spend the $99 now?"

**Not yet. Probably today.** Three gates come first, all free. Two are mine and
cost you nothing. One costs you two hours. Enrol the same hour they pass.

Both other models initially said buy now; I said buy now. **Astra said later and
was right, and I conceded.** The argument that moved it: the cheapest thing that
can kill this project is watching a real person dictate on a fresh Mac, and that
test does not need a certificate — an unsigned build opens fine through Privacy
& Security → Open Anyway, and a tester you personally invited will do that once.
Paying first, to remove friction for strangers who do not exist yet, puts $99
ahead of the falsification it is supposed to follow.

Frontier's counter-argument survives, but about *why* not *when*: for strangers,
the Gatekeeper warning is fatal, and $99 is the cheapest insurance against "it
doesn't work on my Mac" support. That is a reason the cert is mandatory before
you sell to anyone you don't know. It is not a reason to buy it before you know
the thing works.

## Gate 1 — Is it actually better than the dictation people already have?

Astra's sharpest contribution: the competitor is not Wispr Flow. **It is the
microphone key already on every Mac, which is free and now runs on-device.**

Frontier's sharpest contribution: **the wedge is German.** Everyone else is
English-first.

Those combine into one question, and half of it is now answered. On the same 144
German clips, scored by the same function, against the same references:

| Engine | Word error rate |
|---|---|
| Apple's on-device speech engine, same vocabulary pass | 19.38 % |
| PressTalk, default configuration | **12.71 %** |

**About a third fewer word errors, like for like.** An earlier version of this
said "roughly half", comparing PressTalk with its German vocabulary pass against
Apple without it, and quoting a PressTalk figure that needed a 620 MB model a new
buyer never downloads. Corrected: both sides now get the same vocabulary pass and
both are the default configuration.

Two limits, stated so nobody over-reads it: the audio is synthesised speech in
three voices, and this compares recognition engines rather than the whole
Dictation experience, which has its own punctuation and correction behaviour.

**Still open:** time from speaking to *finished, corrected* text. Astra wants a
20% median improvement over Apple Dictation on 20 clips. That needs a human
doing real corrections, so it belongs with Gate 2.

## Gate 2 — Does it work for a person on a Mac that has never seen it? (yours, 2 hours)

This is the one nobody can do for you, and the only remaining unknown that could
invalidate everything else. The harness suppresses insertion by design, so
144/144 means "produced text", not "text arrived in another app".

1. A Mac that has never run PressTalk. Install from the cask. Open Anyway on
   first launch.
2. Grant each permission at the real prompt, one at a time.
3. Watch the model download. Cancel it once and relaunch.
4. **20 physical Fn dictations: 10 into two different real apps.** All 20 must
   land.
5. Time 20 of them against Apple Dictation, to finished corrected text.
6. Get **five named people** to say they will pay $20.

**Stop if:** fewer than 20/20 land, or you cannot find five people, or it takes
more than two hours.

## Gate 3 — Enrol and sell (yours, ~30 minutes + $99)

Enrol the same hour Gates 1 and 2 pass. Then the runbook in
[LAUNCH_GATES.md](LAUNCH_GATES.md) is four commands. Lemon Squeezy store approval
takes 2–3 business days, so start both applications together.

**Stop if:** 5/5 testers cannot install and reach a first dictation unaided in
five minutes.

## Gate 4 — The paid pilot (yours, ~2 hours over 30 days)

Cap it at 25 sales at $20. Then $39 with identical rights.

**Stop if:** fewer than 20 paying customers, or fewer than 10 using it three or
more days a week for two consecutive weeks.

Twenty people who paid and kept using it is a real signal. Downloads and stars
are not.

## Gate 5 — iOS (not now)

You asked to ship iOS ASAP with all-in-one pricing. All three of us say no, and
the reason is not strategy, it is a hard platform fact:

**An iOS keyboard extension cannot access the microphone.** Not a memory limit —
a restriction since iOS 8 that Full Access does not lift. So an iOS PressTalk
cannot work the way the Mac one does. The only shape that exists is: tap a mic
button in a keyboard, which launches the containing app, which records and
transcribes, writes to a shared container, and hands the text back to the
keyboard. **An app switch on every single dictation.** That is what Wispr Flow
does on iOS, and it is why iOS dictation apps feel worse than Mac ones.

There is a second constraint on "all-in-one pricing": App Store guideline 3.1
generally forbids unlocking with an independent licence key, so the offline
licence built for the Mac cannot unlock an App Store iOS build. A shared purchase
is possible under the multiplatform rules, but only with a matching in-app
purchase, which means App Store distribution and its cut.

**The gate:** 20 paying Mac customers, 10 using it 3+ days a week, and **five who
independently ask for the same iPhone workflow**. Then one prototype spike, ≤2
hours and ≤$25. Stop if fewer than 4 of those 5 still want it once they feel the
app switch.

## What the offer says

This is where the three of us disagreed longest, and where astra revised its own
position mid-argument.

You said: *"own this app indefinitely, locally, no subscription, free updates for
life."*

Frontier wanted to refuse the last part outright — "own v1 forever", paid 2.0
upgrade — calling an open-ended update promise "a suicide pact" for a solo developer. I
proposed the same thing in gentler words. **Astra took your side and changed my
mind**, with the observation that separated two promises we had been treating as
one:

- *Every release we make is free to you.* Costs nothing extra per customer. This
  is what someone means when they say they don't want to be rented to.
- *We will keep releasing forever.* Unbounded labour by one person against a
  platform that changes annually. Nobody can honour it.

Astra also corrected a factual error in my case against you: Developer ID apps
keep working after the membership lapses, so "a $99 annual liability forever" was
wrong. The real exposure is maintenance effort, not signing.

So the offer makes the first promise and explicitly declines the second, in the
same breath rather than in a buried FAQ:

> **Pay $20 once: keep the Mac app indefinitely on compatible Macs, use it
> offline without a subscription, and receive every future Mac update we release
> — including major versions — free.**
>
> Future releases, indefinite support, and compatibility with future macOS
> versions are not guaranteed.

The first 25 get the price, not better rights. Customer 26 pays $39 with
identical entitlements — a founder tier that is permanently superior to every
later tier is a thing people notice and resent.

Licences now issue with `maxMajorVersion = allMajorVersions`, so the code matches
the offer.

## Maximum exposure if all of it fails

| | |
|---|---|
| Money | $99, plus payment fees only on actual sales |
| Your hours | ~2 (Gate 2) + 0.5 (Gate 3) + 2 (Gate 4) = **under 5** |
| When you would know | Gate 2 kills it in 48 hours. Gate 4 kills it in 30 days. |

Astra's ongoing ceiling: **one owner-hour per month.** Exceeding it pauses new
sales. Existing licences and their update rights survive any stop — that is what
buying rather than renting has to mean when the seller walks away.
