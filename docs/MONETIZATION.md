# Monetization Plan

This is the current product direction for PressTalk.

## Positioning

PressTalk is a local-first Apple Silicon dictation tool.

That means the monetization should feel lighter and fairer than cloud transcription products. The core promise is:

- hold `Option + Space`, `Fn / Globe`, `Option`, `F5`, or trackpad hold
- speak
- release
- get text locally

That should remain free.

## Model

The recommended structure is:

- `Free`
- `Pro`
- `Founding`

## Pricing

Planned pricing:

- `Free`
- `Pro Monthly`: `$8/mo`
- `Pro Yearly`: `$59/yr`
- `Founding Lifetime`: `$49`

These numbers are intentionally below the common `$12–15/mo` cloud-dictation range because PressTalk has a narrower, local-first cost structure.

## What Stays Free

- unlimited basic local dictation
- configurable hold-to-talk trigger
- basic HUD
- basic language and insertion settings
- standard local WhisperKit path
- normal text insertion into the focused app

## What Belongs in Pro

Pro should unlock leverage, not basic usability.

Recommended Pro features:

- custom vocabulary
- replacements and snippets
- app-specific profiles
- formatting modes such as `plain`, `email`, `notes`, `code-safe`
- advanced punctuation behavior
- hotkey customization
- dictation history
- export/import settings
- future sync

## Founding Tier

Founding should be simple:

- one-time payment
- all Pro features through the early product cycle
- optional supporter badge in Settings

This is the fastest way to validate willingness to pay without forcing a subscription too early.

## Payments

Recommended payment stack:

- `Lemon Squeezy` first

Reason:

- Merchant of Record
- simpler VAT/sales-tax handling
- good fit for indie Mac software

The app should eventually support:

- `Upgrade to Pro`
- `Enter License Key`
- `Restore Purchase`
- `Manage Subscription`

## Rollout

1. Keep `0.1.x` generous and stable.
2. Add visible plan/billing scaffolding in-app.
3. Wire a real checkout URL.
4. Launch Founding + Pro.
5. Gate only power features, not core dictation quality.
