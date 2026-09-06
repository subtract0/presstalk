# Monetization

Superseded. There is exactly one source for prices and entitlements now, and it
is code:

- `Sources/PressTalkCore/EntitlementPolicy.swift` — `PressTalkOffer` holds the
  prices and what they cover; `EntitlementPolicy` decides what an installation
  is entitled to.

The offer: **$20 founder (first 25), then $39, one-time. Every future Mac
update included, major versions too. No subscription.**

> "Pay $20 once: keep the Mac app indefinitely on compatible Macs, use it offline
> without a subscription, and receive every future Mac update we release —
> including major versions — free."
>
> Future releases, indefinite support, and compatibility with future macOS
> versions are not guaranteed.

Two promises get confused here and only one is dangerous. *Every release we make
is free to you* costs nothing extra per customer, and is what someone means when
they say they do not want to be rented to. *We will keep releasing forever* is
unbounded labour by one person against a platform that changes annually. The
offer makes the first promise and explicitly declines the second, in the same
breath rather than in a buried FAQ.

The first 25 buyers get an introductory price, not better permanent rights.
Customer 26 pays $39 with identical entitlements — a founder tier that is
permanently superior to every later tier is a thing people notice and resent.

This file previously described a Free/Pro/Founding structure at $8/mo, $59/yr,
and $49 lifetime. That contradicted both the distribution roadmap and the
string the app itself displayed, and three prices in three places is how a
product ends up charging someone something they never agreed to. The old
structure is not deferred; it is dropped.

Two commitments the code enforces, not just documents:

- Anyone who used PressTalk before it was paid keeps core dictation free. The
  shipped settings pane promised that for months. `EntitlementPolicy` detects
  prior use and grandfathers those installations, and there is a test whose only
  job is to fail if an existing user is ever turned into an expired trial.
- Licences are issued with `maxMajorVersion = allMajorVersions`, so the app
  honours every future release. The field stays in the schema because a bounded
  entitlement is something a later commercial tier might need, and adding it back
  afterwards would mean a schema change and a second key rollout.

Commercial and team licensing are not designed yet. They need inbound demand
first; see `PRESSTALK_DISTRIBUTION_ROADMAP_V1.md`.

## VoiceInk, and what is actually left of the differentiation

Surfaced 7 September 2026 by an outside review of this repository, not by
anything in it. Worth writing down because it removes two things we had been
treating as ours.

[VoiceInk](https://tryvoiceink.com/) is a macOS dictation app that runs
recognition locally and sells one-time: $25 solo, $39 for two devices, $49 for
three, at a promotional 50% off. Its own words: "VoiceInk processes all voice
transcription locally on your device. Your voice data never leaves your Mac."

So neither **local processing** nor **buy it once** distinguishes PressTalk.
Both were in our copy as though they did. Apple's built-in Dictation also
processes on device in supported configurations, which removes the third.

What survives, stated narrowly:

- **A published German word error rate with the test set, the references and
  the scorer.** VoiceInk's site does not mention German at all. This is a real
  gap, but it is a gap in *their marketing* -- it is not evidence their engine
  is worse, and nobody has run the comparison.
- **Price.** €20 against $25 at their promotional rate, more against their list.
- **The source is public.** Anyone can read what the app does rather than
  believe a privacy page.

Astra separately retracted the stronger form of this: publishing a benchmark is
a practice a competitor can copy, and the overlap between our eval set and our
repair lexicon limits what it establishes about unfamiliar speech. Credibility,
not a moat.

**Do not write copy that implies local-and-one-time is unusual.** It is the
category now. If PressTalk wins it will be on German results a buyer can check
against their own sentences, and that has not been demonstrated to a single
stranger yet.
