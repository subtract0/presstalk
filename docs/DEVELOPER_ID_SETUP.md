# Developer ID setup — the two steps only the account holder can do

Team: `5HUC5LA94B` (Alexander Monas, individual enrolment, order W1463898468)
Bundle identifier: `com.am.presstalk`

Everything after these two steps is already scripted. Verify with:

    scripts/presstalk_developer_id_check.sh

---

## What PressTalk does NOT need

Two screens in Apple's portals look like the obvious starting point and are not.

**App Store Connect > Apps > "Apps hinzufügen".** That record exists to submit a
build to the App Store or TestFlight. PressTalk ships as a direct download and a
Homebrew cask, so it never touches either. Creating the record has a real cost:
it turns on the EU Digital Services Act trader-status requirement (the red
*Händlerstatus* banner), which asks for a verified public trading address, plus
age ratings, screenshots and review — none of which gate signing or notarizing.
An App Store Connect record is only needed if the decision to sell through the
App Store is ever made. Today it is not.

**Certificates, Identifiers & Profiles > Identifiers > Register an App ID.**
App IDs exist so Apple can mint provisioning profiles. Developer ID distribution
does not use provisioning profiles: the certificate carries the team identity and
the entitlements are embedded at signing time. A profile is only required for
capabilities Apple has to authorise per app — iCloud, Push, App Groups, Sign in
with Apple. PressTalk requests exactly one entitlement,
`com.apple.security.device.audio-input`, which needs no profile.

Registering an App ID would be harmless but inert. Filling in the App Store
Connect record would create obligations for a channel that is not being used.

---

## Step 1 — Developer ID Application certificate

Do this in Xcode rather than the web portal. The web route requires generating a
certificate signing request in Keychain Access first, and a certificate whose
private key was created on a different machine cannot sign anything — a failure
that stays invisible until the first build.

1. Open Xcode.
2. **Xcode > Settings…** (⌘,) > **Accounts**.
3. **+** > **Apple ID** > sign in. This Mac has never been signed in, so this
   step is required and nobody else can do it.
4. Select the team **Alexander Monas (5HUC5LA94B)** > **Manage Certificates…**
5. Bottom-left **+** > **Developer ID Application**.
6. It appears in the list after a few seconds.

Pick **Developer ID Application**, not *Developer ID Installer*. Installer
certificates sign `.pkg` files; PressTalk ships a `.app` inside a zip.

Verify:

    security find-identity -v -p codesigning

The output must contain `Developer ID Application: Alexander Monas (5HUC5LA94B)`.

Apple caps Developer ID Application certificates at five per team, and they are
awkward to revoke. Create one and back it up: Keychain Access > right-click the
certificate > Export as `.p12`, stored wherever the other credentials live. That
`.p12` is the only way to sign from another Mac. It is a signing key, so it never
goes into the repository and never into a chat window.

---

## Step 2 — notarytool credentials

Notarization authenticates separately from signing.

1. Go to **appleid.apple.com** > **Sign-In and Security** >
   **App-Specific Passwords** > generate one, named `presstalk-notary`.
2. In a terminal, run:

       xcrun notarytool store-credentials "presstalk-notary" \
           --apple-id <your-apple-id> --team-id 5HUC5LA94B

   It prompts for the app-specific password. It goes straight into the login
   keychain, so it is typed exactly once and never appears in a script, an
   environment variable, or a transcript.

An App Store Connect API key (`.p8`) also works and is the better long-term
credential, because it is revocable without touching the Apple ID. It costs an
extra trip through App Store Connect > Users and Access > Integrations and the
API terms. Either is fine; the app-specific password is faster today.

---

## The first signing run

The first `codesign` against a newly created certificate raises a modal keychain
prompt asking for access to the private key. Run the first release from a
terminal that is being watched, and click **Always Allow** — not *Allow*, which
re-prompts on every later build and will hang any unattended script.

Measured on studio1 on 2026-09-06: a scripted signature against a certificate
whose key had not been authorised blocked until the process was killed. This is
why `presstalk_developer_id_check.sh` deliberately does not test-sign.

---

## After both steps

    scripts/presstalk_developer_id_check.sh          # must exit 0

    PRESSTALK_DISTRIBUTION_SIGNING=1 PRESSTALK_NOTARIZE=1 \
    PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary \
    PRESSTALK_CODESIGN_IDENTITY="Developer ID Application" \
    scripts/package_presstalk_release.sh 0.1.9

    scripts/presstalk_notarization_readiness.sh --require-developer-id

The readiness gate checks every Mach-O for the hardened runtime flag and a single
Developer ID authority, the entitlement values rather than just their keys, the
usage strings, the secure timestamp, the staple, and `spctl` acceptance.

---

## The consequence nobody should be surprised by

Every existing TCC grant — microphone and accessibility — is keyed to the code
signing identity. Moving from the local development identity to Developer ID
changes that identity, so every Mac already running PressTalk, including mbp1 and
mba1, will be asked for microphone and accessibility permission again on the
first launch of a signed build. That is correct behaviour and not a regression,
but it is the one thing a returning tester will notice, and the release notes
must say so before they hit it.
