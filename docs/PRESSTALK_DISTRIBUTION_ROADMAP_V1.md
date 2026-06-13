# PressTalk Distribution Roadmap v1.0

Date: 2026-06-13
Audience: agents, operators, collaborators
Source baseline: `feature/ane-parakeet-backend` at `7a51c12` (`Fix short no-speech status reset`)
Public tester build currently available: `0.1.6-test6` through `subtract0/homebrew-presstalk`

## One Sentence

PressTalk is the private, local, Apple Silicon dictation app for people who want push-to-talk voice input without sending audio or transcripts to a cloud service and without paying a recurring dictation subscription.

## Reality Check

No plan can honestly promise that Alex becomes rich overnight. The correct v1.0 plan is the highest-upside path that does not depend on fraud, hype, fake privacy claims, or unproven technical work. It is designed to convert the current working local product into a trusted paid Mac utility as fast as possible.

The goal is not to beat every feature of Wispr Flow or Monologue immediately. The goal is to own one narrow wedge so clearly that the right buyers understand it in ten seconds:

> Hold Fn. Speak. Release. Text appears. It runs locally on your Mac. Buy once.

## Locked Decisions

- Product name: `PressTalk`.
- Platform: Apple Silicon macOS first.
- Default trigger: `Fn / Globe`.
- Technical baseline: freeze `7a51c12` until the first paid beta is stable.
- Distribution: direct notarized Mac app plus Homebrew cask first; Mac App Store later.
- Pricing: paid early access at `$20` one-time, stable launch at `$39` one-time, later commercial license at `$99` per seat or `$299` per small team.
- Payment stack: Lemon Squeezy first, because it is a Merchant of Record and handles payment, sales tax, refunds, chargebacks, and PCI surface for digital purchases.
- Privacy promise: local audio and local transcript by default. No cloud transcription. No audio upload. No transcript upload. No telemetry containing dictated content.
- Support promise: direct support for installation and permissions during beta. No enterprise compliance claims until there is a written policy and legal review.
- Marketing wedge: stop renting cloud dictation.

## External Facts Used

- Wispr Flow lists Flow Pro at `$15/user/mo` monthly or `$12/user/mo` billed annually, with Basic word limits and privacy mode/zero data retention listed as a feature. Source: https://wisprflow.ai/pricing
- Monologue App Store listing says the app is free with in-app purchases, includes monthly Pro prices around `$9.99` early bird and `$14.99`, and positions smart formatting, personal dictionary, modes, multilingual use, no saved audio/transcripts on servers, and zero LLM data retention. Source: https://apps.apple.com/us/app/monologue-smart-dictation/id6755956193
- Apple says Developer ID signing lets Gatekeeper verify software distributed outside the Mac App Store, and notarization gives users additional confidence by assigning a ticket after Apple security checks. Source: https://developer.apple.com/developer-id/
- Lemon Squeezy describes itself as a Merchant of Record handling payments, sales tax, refunds, chargebacks, and PCI compliance for purchases. Source: https://docs.lemonsqueezy.com/help/payments/merchant-of-record

## Red Team

### Failure 1: "Local" is not enough if quality is worse.

Risk: Buyers compare against Wispr Flow and Monologue on output quality, punctuation, names, and long-form reliability.

Countermeasure:
- Do not market PressTalk as "best dictation overall" at launch.
- Market it as "best private local push-to-talk for Apple Silicon".
- Keep the Parakeet ANE path as the fast default.
- Add opt-in custom vocabulary only after the stable paid beta is running.
- Use public demos with real mixed English/German dictation so expectations are honest.

Pass condition:
- 80 percent of first 50 paid beta users say the output is good enough for daily short-form dictation.

### Failure 2: Install and permissions kill conversion.

Risk: macOS Microphone, Input Monitoring, and Accessibility permissions create fear and confusion.

Countermeasure:
- Ship Developer ID signed and notarized app before public paid launch.
- First-run setup must explain exactly three permissions, one at a time.
- The app must never repeatedly open System Settings if a permission is already granted.
- Keep a visible "Run Setup Check" and "Copy Diagnostics" button.

Pass condition:
- 90 percent of fresh testers reach a successful first dictation in under five minutes.

### Failure 3: The one-time purchase leaves too little business upside.

Risk: `$20` lifetime attracts users but caps revenue.

Countermeasure:
- `$20` is early-access only.
- Stable launch becomes `$39`.
- When trust exists, raise to `$49`.
- Add commercial license tiers without removing the core one-time promise for individuals.

Pass condition:
- First 100 paid users convert without discounts beyond early-access framing.

### Failure 4: Privacy claims become liability.

Risk: Saying "private" without proof creates legal and trust exposure.

Countermeasure:
- Use precise language: "local audio and transcript by default" and "no cloud transcription".
- Do not claim HIPAA, medical compliance, legal compliance, or enterprise security certifications.
- Add a privacy page with a table: data type, where stored, whether uploaded.
- Include a local traffic statement: "PressTalk does not need network access for dictation."

Pass condition:
- Website, app, and checkout all use the same privacy wording.

### Failure 5: Subscription competitors respond.

Risk: Wispr Flow or Monologue can add local mode or lifetime deals.

Countermeasure:
- Own simplicity and trust, not feature breadth.
- Publish a transparent local-first architecture page.
- Build founder community and "buy once" brand before incumbents care.
- Avoid their broad team/enterprise feature set initially.

Pass condition:
- Launch comments repeat the phrase "local and buy once" without prompting.

### Failure 6: Mac-only looks small.

Risk: Investors and broad consumers prefer cross-platform apps.

Countermeasure:
- Do not apologize for Mac-only.
- Position as "built for Apple Silicon, not a lowest-common-denominator web service".
- Mac users are reachable through Homebrew, Hacker News, developer Twitter, productivity YouTube, and privacy communities.

Pass condition:
- First 500 paying users come from Mac-specific channels before any Windows/iOS expansion.

### Failure 7: Beta users request too many features.

Risk: Agents overbuild modes, correction learning, custom dictionaries, iPhone, teams, sync, and LLM cleanup before distribution is proven.

Countermeasure:
- Freeze runtime for paid beta.
- Only fix crash, install, no-paste, stuck-state, and severe transcription regressions.
- Everything else goes into a public roadmap.

Pass condition:
- Paid beta reaches 50 users before adding a major feature branch.

### Failure 8: License cracking distracts the team.

Risk: A one-time Mac app can be copied.

Countermeasure:
- Use signed license files and simple online activation.
- Allow offline use after activation.
- Do not waste weeks on hard DRM.
- The real moat is trust, brand, speed, support, and updates.

Pass condition:
- License system takes less than three engineering days and never blocks legitimate offline dictation.

### Failure 9: Launch traffic arrives before support is ready.

Risk: A viral post produces confused users and refunds.

Countermeasure:
- Create a one-page support playbook before public launch.
- Include a diagnostics export button.
- Require first-run setup checklist to produce a machine-readable status.
- Cap early access at 200 users if support breaks.

Pass condition:
- Median first response time under 24 hours during beta week.

### Failure 10: The product sounds like a toy.

Risk: "PressTalk" may sound small if the buyer has serious privacy needs.

Countermeasure:
- Brand line does the heavy work: "Private dictation for Apple Silicon".
- Use serious visual language: clean, direct, technical, not cute.
- Demo must show real work: terminal, email, notes, German/English switch, no cloud.

Pass condition:
- The landing page communicates the product without a paragraph of explanation.

## Product Boundary for v1

### Included

- Fn / Globe hold-to-talk.
- Local Apple Silicon ASR default.
- Real text-field insertion.
- Lightweight voice light / HUD.
- Settings for trigger, HUD, paste behavior, language/tail behavior.
- Homebrew install for technical users.
- Notarized direct download for normal users.
- License key activation.
- Diagnostics export.
- Privacy page.

### Excluded Until After Paid Beta

- iPhone app.
- Windows app.
- Teams dashboard.
- Cloud sync.
- Enterprise compliance claims.
- Automatic correction learning.
- Full LLM rewrite/polish engine.
- App Store submission.
- Subscription-only pricing.

## Offer

### Early Access

Name: PressTalk Founder License

Price: `$20` one-time

Includes:
- current Mac app
- updates through `1.x`
- direct beta support
- founder pricing locked
- no subscription

Limit:
- first 200 buyers or first 14 days, whichever comes first

### Stable Launch

Name: PressTalk Personal

Price: `$39` one-time, later `$49`

Includes:
- one user
- up to two personal Macs
- local dictation
- updates through `1.x`
- no subscription

### Commercial

Name: PressTalk Work

Price:
- `$99` per seat
- `$299` small team pack for up to 5 users

Includes:
- business use
- priority support
- deployment notes
- invoice-friendly checkout

No enterprise procurement path exists until inbound demand proves it.

## Revenue Math

These are not promises. They are launch targets.

- 50 founder buyers at `$20`: `$1,000` gross validation.
- 200 founder buyers at `$20`: `$4,000` gross and enough support data.
- 1,000 buyers at `$39`: `$39,000` gross.
- 10,000 buyers at `$49`: `$490,000` gross.
- 100,000 buyers at `$49`: `$4,900,000` gross.

The rich-outcome path is not one miracle night. It is one sharp demo, one trusted installer, one obvious price contrast, and repeated distribution through audiences that already feel the subscription pain.

## Landing Page v1

### Headline

PressTalk

### Subheadline

Private dictation for Apple Silicon. Hold Fn, speak, release, and text appears. No cloud transcription. No monthly subscription.

### Primary CTA

Buy early access for `$20`

### Secondary CTA

Install with Homebrew

### Proof Strip

- Runs locally on Apple Silicon
- Default trigger: Fn / Globe
- German and English mixed dictation
- No audio upload
- No transcript upload
- One-time purchase

### Demo Sequence

Record one 75-second video:

1. Open a plain text editor.
2. Hold Fn and say one English sentence.
3. Release; text appears.
4. Hold Fn and say one German sentence.
5. Release; text appears.
6. Open the menu/settings and show "local" and "Fn / Globe".
7. Show network disabled or explain "dictation runs locally".
8. End on pricing: `$20 early access, no subscription`.

No voiceover is needed. On-screen captions are enough.

## Distribution Stack

### Technical Channel

Homebrew:

```bash
brew update
brew tap subtract0/presstalk
brew install --cask subtract0/presstalk/presstalk
```

Use Homebrew for testers, developers, and public credibility.

### Consumer Channel

Direct download:

- notarized `.zip` or `.dmg`
- download button from landing page
- no terminal required
- first-run setup checklist

### Payment Channel

Lemon Squeezy checkout:

- product: PressTalk Founder License
- variant: Mac Apple Silicon
- license key: enabled
- tax/VAT handled by Merchant of Record
- refund policy: 14 days, no questions asked during beta

### License

Implementation choice:

- signed license file stored in `~/Library/Application Support/PressTalk/license.json`
- activation binds to email plus license key plus machine hash
- app works offline after activation
- app shows "Founder License" in settings
- if activation server is unavailable, allow a seven-day grace period

Do not implement invasive DRM.

## Release Gates

Stable paid beta cannot launch until all are true:

- Source clean and pushed.
- Artifact signed with Developer ID.
- Hardened runtime enabled.
- Notarization ticket stapled.
- Artifact audit passes with `--require-distribution --require-notarized`.
- Homebrew cask points to the exact release artifact and SHA.
- Fresh install proof passes on:
  - `studio1`
  - one M1/M2 class Mac
  - one clean or near-clean tester Mac
- First-run setup reaches successful dictation without manual shell commands.
- Privacy page is published.
- Checkout and refund path tested.
- Diagnostics export works.

## Agent Execution Plan

### Phase 0: Freeze

Objective: protect the working product.

Commands:

```bash
cd /Users/am/Code/presstalk
git status --short --branch
git log -1 --oneline
```

Expected:

- branch `feature/ane-parakeet-backend`
- head at or after `7a51c12`
- no dirty source changes unless intentionally staged

Rule:

- No runtime feature changes before paid beta.
- Only fix install, signing, crash, paste, stuck-state, or severe transcription regressions.

### Phase 1: Notarized Beta Artifact

Objective: create a trustworthy direct download.

Tasks:

1. Confirm Developer ID Application identity exists.
2. Configure notarytool credentials.
3. Run distribution signing preflight.
4. Package `0.1.7-beta1`.
5. Audit artifact.
6. Dry-run Homebrew publish.
7. Install on local machine from artifact.

Commands:

```bash
bash scripts/presstalk_distribution_signing_preflight.sh \
  --json-output dist/PressTalk-0.1.7-beta1-distribution-preflight.json

PRESSTALK_DISTRIBUTION_SIGNING=1 \
PRESSTALK_NOTARIZE=1 \
bash scripts/package_presstalk_release.sh 0.1.7-beta1

bash scripts/presstalk_release_artifact_audit.sh \
  --zip dist/PressTalk-0.1.7-beta1-macos-arm64.zip \
  --expected-version 0.1.7-beta1 \
  --require-distribution \
  --require-notarized \
  --json-output dist/PressTalk-0.1.7-beta1-artifact-audit.json
```

Stop rule:

- If notarization fails, do not publish. Fix signing/notarization only.

### Phase 2: Payment and License

Objective: make buying real without adding heavy infrastructure.

Tasks:

1. Create Lemon Squeezy product: PressTalk Founder License.
2. Set price to `$20`.
3. Enable license keys.
4. Add checkout URL to landing page.
5. Add "Enter License Key" in settings only if implementation is ready.
6. If license UI is not ready, sell manually and email direct download to the first 25 buyers.

Stop rule:

- Do not block beta launch on perfect licensing. Manual license fulfillment is acceptable for first 25 buyers.

### Phase 3: Landing Page

Objective: convert one obvious pain.

Required sections:

1. Hero: "Private dictation for Apple Silicon."
2. Demo video.
3. "Why local" section.
4. "How it works" section.
5. "Compared with subscriptions" section.
6. Pricing.
7. Privacy table.
8. FAQ.
9. Homebrew install for technical users.

Copy rule:

- Never claim "HIPAA compliant" or "medical-grade".
- Never claim "never uses network" unless the app cannot call any network path.
- Use "dictation runs locally by default" and "no cloud transcription".

### Phase 4: Private Paid Beta

Objective: get 25-50 real buyers before public noise.

Channels:

- Alex direct network
- Crow and trusted technical testers
- Mac-heavy friends
- privacy-conscious professionals
- developers who already use Homebrew

Script:

> I built a local Mac dictation app because I do not want to rent cloud voice input forever. It runs on Apple Silicon, uses Fn push-to-talk, and pastes into the focused app. I am selling the first founder licenses for `$20` one-time. I want brutal install and quality feedback.

Feedback form:

- Mac model
- macOS version
- install path: direct / Homebrew
- did first dictation work: yes/no
- output quality: 1-5
- paste reliability: 1-5
- would you pay `$39`: yes/no
- biggest missing feature

Stop rule:

- If fewer than 50 percent would pay `$39`, do not public-launch. Fix positioning, onboarding, or quality first.

### Phase 5: Public Launch

Objective: sell the privacy/subscription wedge.

Launch order:

1. Personal X/LinkedIn post with demo.
2. Hacker News "Show HN".
3. Reddit `r/macapps`.
4. Reddit `r/LocalLLaMA` if post is technical and local-model focused.
5. Product Hunt only after the landing page and support flow are stable.
6. Email Mac productivity newsletters and YouTube creators.

Launch headline variants:

- "I built a local Mac dictation app so I could stop renting voice input."
- "PressTalk: private Apple Silicon dictation, buy once."
- "Hold Fn, speak, release. No cloud transcription."

Never lead with model names. Lead with user pain.

### Phase 6: Scale

Objective: turn paid beta into durable revenue.

Only after 200 paying users:

- custom vocabulary
- snippets
- app-specific modes
- correction learning, opt-in only
- direct DMG auto-update
- affiliate program
- German landing page
- comparison page

Only after 1,000 paying users:

- commercial license
- team deployment page
- notarized auto-updater
- limited enterprise inquiry form

Only after 5,000 paying users:

- Windows feasibility
- iPhone companion feasibility
- optional local LLM cleanup

## Support Playbook

### First Response

Ask for:

- Mac model
- macOS version
- install method
- whether permissions show granted
- diagnostics export
- exact trigger used

Never tell users to repeatedly grant the same permissions. If settings show granted but app disagrees, treat it as identity/signing/install-state mismatch.

### Refund Policy

During beta:

- 14 days
- no argument
- ask for one optional reason

This protects trust and reduces public anger.

## Metrics

### Activation

- landing page to download: target 20 percent
- download to first successful dictation: target 70 percent
- first successful dictation within five minutes: target 90 percent

### Payment

- landing page to purchase: target 3 to 8 percent for warm traffic
- direct beta invite to purchase: target 10 to 30 percent
- refund rate: below 10 percent

### Product

- paste success: above 95 percent
- user-rated quality: above 4 out of 5
- install support tickets: below 20 percent of buyers

## Roadmap

### 48 Hours

- Create notarized `0.1.7-beta1`.
- Create landing page.
- Create 75-second demo video.
- Create Lemon Squeezy founder product.
- Invite first 10 paid testers.

### 7 Days

- Reach 25 paid testers.
- Fix only install/paste/status blockers.
- Publish public beta page.
- Prepare launch posts.

### 14 Days

- Reach 100 founder buyers.
- Raise price to `$39` if feedback is strong.
- Start comparison content.

### 30 Days

- Reach 500 buyers or identify the blocking metric.
- Add exactly one high-value feature from buyer feedback.
- Prepare stable `1.0`.

### 90 Days

- Reach 2,000 buyers or pivot positioning.
- Add commercial license.
- Decide whether Mac App Store is worth the sandbox and review constraints.

## Final Agent Rule

For every PressTalk task, ask:

1. Does this increase paid-user trust?
2. Does this reduce install friction?
3. Does this improve the local/private wedge?
4. Does this preserve the frozen working runtime?

If the answer is no, do not do it before paid beta.
