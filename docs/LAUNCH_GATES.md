# What stands between here and selling PressTalk

For current decisions, limits and ordering, use the
[5–18 September two-week plan](TWO_WEEK_PLAN_2026-09-05.md).
This earlier technical checklist includes dated status and is not proof that
the new plan's gates have passed.

Written 2026-09-05. Everything below is either **yours** (needs your Apple ID,
your bank details, your face, or a Mac I do not have) or **open** (mine, not
finished).

## Yours: the Developer ID certificate

This is the one blocker with nothing behind it. Until it is done, every buyer
sees "PressTalk cannot be opened because the developer cannot be verified", and
that is not a thing you can charge $20 for.

```bash
# 1. Membership + certificate, in a browser
#    developer.apple.com/account -> Certificates -> + -> Developer ID Application
#    Download it, double-click to install into the login keychain.
security find-identity -v -p codesigning | grep "Developer ID Application"

# 2. Store notarytool credentials once. Use an app-specific password from
#    appleid.apple.com, never your Apple ID password.
xcrun notarytool store-credentials presstalk-notary \
  --apple-id "<your apple id>" --team-id "<TEAMID>"

# 3. Everything after this is scripted.
cd ~/Code/presstalk
export PRESSTALK_CODESIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)"
export PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary
PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_NOTARIZE=1 \
  bash scripts/package_presstalk_release.sh 0.1.7

# 4. Prove it, rather than assuming the exit code meant it worked.
bash scripts/presstalk_notarization_readiness.sh \
  --app <the built app> --require-developer-id
```

Step 4 checks authority, team identifier, secure timestamp, stapled ticket, and
`spctl` acceptance. `package_presstalk_release.sh` runs it for you before the zip
and again after stapling, so a bad artifact stops there rather than reaching the
cask.

**Two things it already caught, before you had a certificate:**

The build signed no entitlements at all. Apple requires
`com.apple.security.device.audio-input` for a hardened process to use the
microphone, and notarization requires the hardened runtime. Fixed.

`presstalk-manual-fn-smoke` shipped inside `Contents/Resources` as a Mach-O still
carrying its linker signature, because a bundle-level `codesign` treats a binary
there as a resource rather than as code. `codesign --verify --deep --strict`
accepts that; the notary service rejects it. Fixed, and developer probes are now
excluded from distribution builds entirely.

Both would have turned certificate day into a debugging day.

## Yours: the rest of the commercial surface

| | Why it needs you |
|---|---|
| Lemon Squeezy product | Your business details and bank account |
| The signing key for licences | `.build/debug/presstalk-license generate-key --out <dir> --key-id founder-2026`, then paste the printed public key into `PressTalkLicenseStore.trustedPublicKeys`. **Back the private key up encrypted.** Losing it means no further licences for keys already shipped |
| Where the site lives | A domain purchase. `site/index.html` is a draft, self-contained, ready to deploy |
| The 75-second demo video | Your screen and your voice |
| First 25 buyers | Your network. The roadmap has the script |

Turn off Lemon Squeezy's own licence-key generation. It issues its own keys,
which are not PressTalk licences, and customers receiving two different "keys" is
a support problem you do not need.

For a capped founder launch, issue by hand:

```bash
.build/debug/presstalk-license issue \
  --key <private key> --key-id founder-2026 --entitlement founder
```

Automating that needs an online signing component, so an always-offline private
key and immediate unattended fulfilment cannot both be true. Manual issuance with a
stated delivery window is the honest version for the first 25.

## Open: gates I could not close

**Nobody has run a real dictation on a fresh Mac.** This is the one that matters.
The harness exercises the whole path headlessly with replayed audio, which found
real bugs, but it cannot press a physical key, grant a permission for the first
time, or paste into another app. What needs a human:

1. A Mac that has never run PressTalk. Install from the cask.
2. Grant each permission at the real system prompt, one at a time.
3. Watch the model download — including cancelling it and relaunching.
4. Hold the physical Fn key, speak, release, and see text arrive **in another
   app**, not in a PressTalk window.
5. Deny a permission on purpose and confirm the app says something useful.

Until that has happened once, "it installs and works" is inference, not
observation.

**The quality fallback default is unresolved.** See
[MEASUREMENTS.md](MEASUREMENTS.md). Aggregate word error rate improves by 3.83
points; per clip it is nearly even; the evidence is synthetic speech. Codex's
provisional recommendation is primary-only with the second pass explicitly
optional. Note that a fresh install already behaves that way, because the
fallback model is never downloaded implicitly.

**Trial expiry is classified but not enforced.** `EntitlementPolicy` works out
whether an install is grandfathered, licensed, on trial, or expired, and
`allowsDictation` says what each state permits — but nothing calls it. That is
deliberate: enforcing expiry before there is any way to buy a licence locks
people out of a product they cannot pay for. Wire it up when the checkout opens,
and test the whole sequence first: fresh defaults, setup, a dictation, restart,
then day 15.

**No updater.** Homebrew users get `brew upgrade`; direct-download buyers get an
email. Sparkle belongs at paid launch, after an actual old-to-new distribution
build test, which needs the certificate. Do not set `auto_updates true` in the
cask until the app really installs updates.

**The harness measures recognition, not delivery.** It suppresses insertion by
default so a test run cannot type into whatever window happens to be focused,
which means its 144/144 figure means "produced text", not "text arrived in
another app". Those are the same thing only when insertion works, and insertion
is exactly what the fresh-Mac run above has to check.

**Live-speech latency is unmeasured.** The 0.95 s p50 comes from replayed audio
where the silence-aware release tail always runs to its cap. Real speech ends in
silence and should exit earlier, so the true number is probably better — but
"probably better" is not a measurement.

**Trial expiry has never been observed.** The grandfathering and 14-day trial
logic is unit-tested including the case that must never happen (an existing user
becoming an expired trial), but no installation has actually reached day 15.

## What changed overnight

| | |
|---|---|
| Tests | 19 → 82, all green |
| First-run download | ~1.1 GB → ~460 MB |
| Time until dictation works after launch | 7.3 s → 0.7 s |
| Text delivery, headless German runs | 4/5 → 144/144 |
| Onboarding | none → guided, ending in delivered text |
| Licensing | a UserDefaults string → offline Ed25519, issuer, import UI |
| Prices in the product | three, contradictory → one |
| Dictated words written to disk | 1,302 → 0 |
| Customer-facing pages | none → privacy, support, landing page, README |
| Gates | none → notarization readiness, claims, transcript leakage |

## Recommended order when you wake up

1. Read [MEASUREMENTS.md](MEASUREMENTS.md), so the numbers you repeat are the ones
   with methods attached.
2. Get the Developer ID certificate. It unblocks everything else.
3. Do the fresh-Mac run above. It is the only remaining unknown that could
   invalidate the rest.
4. Then Lemon Squeezy, the licence key, the demo, the first 25 buyers.
