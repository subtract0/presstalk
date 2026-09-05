# Monetization

Superseded. There is exactly one source for prices and entitlements now, and it
is code:

- `Sources/PressTalkCore/EntitlementPolicy.swift` — `PressTalkOffer` holds the
  prices and what they cover; `EntitlementPolicy` decides what an installation
  is entitled to.

The offer: **$20 founder, $39 personal, one-time, updates through 1.x, no
subscription.**

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
- "Updates through 1.x" is written into the licence as `maxMajorVersion` and
  checked at verification, so it is a promise the app can keep rather than a
  sentence on a checkout page.

Commercial and team licensing are not designed yet. They need inbound demand
first; see `PRESSTALK_DISTRIBUTION_ROADMAP_V1.md`.
