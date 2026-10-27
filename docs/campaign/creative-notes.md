# PressTalk: two launch creative concepts

Prepared 27 October 2026 for the existing founder offer. These assets introduce no new product entitlement, price, trial length, or payment rail.

## Destinations and message match

Both concepts lead to `https://presstalk.app/voice-to-text.html`. The landing page leads to the existing `download.html` and `buy.html` flows. The campaign attribution implementation must preserve the chosen campaign and creative across those links; these asset names alone do not establish purchase attribution.

| Concept | Main promise | Files |
| --- | --- | --- |
| Prompts | Speak a prompt instead of typing it. | `site/ads/presstalk-prompts-728x90.png`, `site/ads/presstalk-prompts-300x250.png` |
| Privacy | Dictation runs on the buyer’s Mac and works offline after setup. | `site/ads/presstalk-privacy-728x90.png`, `site/ads/presstalk-privacy-300x250.png` |

Matching SVG originals are supplied beside each PNG. Text is converted to vector outlines, so the SVG does not depend on a viewer having the font installed. The artwork uses a restrained ivory, ink, and lime variation of the existing PressTalk identity. The webpage uses the existing locally served Archivo and IBM Plex Mono fonts.

## Upload specifications

- Desktop: 728 × 90 pixels, PNG.
- Mobile: 300 × 250 pixels, PNG.
- Each export is less than 15 KB.
- Both concepts identify Mac M1+ and macOS 14+.
- Use the PNG for the advertising upload. SVG is an editable source format, not a format accepted by the advertised 4chan image specification.
- Neither concept imitates a download control, video player, system notification, or browser alert.
- Confirm that the founder offer still applies before funding a price-bearing advertisement. No remaining-founder count or invented deadline appears in these assets.

## Copy and evidence boundaries

The page states the current three-day trial, no card/account for the trial, $20 founder price, $39 later price, one-time payment, offline use after setup, and future published Mac updates. It explicitly preserves the limits on future development, indefinite support, and future operating-system compatibility. The FAQ identifies macOS 27 as not yet verified by the current release.

The visual interaction is labelled **Illustration · no microphone access**. It reuses the existing finite `demo.js` animation, including reduced-motion support and pause/replay controls. It is not a video of the application, a live transcription feature, or a timing claim.

The public repository is described as source that can be inspected. These assets make no unsupported open-source-licence claim, comparative accuracy/speed claim, customer-count claim, or testimonial.

Relevant existing sources:

- `Sources/PressTalkCore/EntitlementPolicy.swift`
- `site/index.html`, `site/download.html`, `site/buy.html`
- `docs/PRIVACY.md`, `docs/SUPPORT.md`, `docs/MONETIZATION.md`
- Release notes for `v0.1.25`

## Verification

The four raster images were rendered from their corresponding vector originals and inspected at their actual dimensions. The parent launch workflow owns browser checks of the assembled page, purchase attribution, live checkout verification, and publication.
