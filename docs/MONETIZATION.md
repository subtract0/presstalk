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
