# Signed automatic updates

PressTalk uses pinned Sparkle 2.10.1 to update the installed app while retaining
the official `com.am.presstalk` Developer ID identity. The public channel is
`https://presstalk.app/appcast.xml`; its update ZIPs use exact GitHub release-tag
URLs. The feed and ZIP are signed with PressTalk's dedicated EdDSA key. This
workflow does not publish a release or website automatically.

Versions before the Sparkle integration, including 0.1.25, need one ordinary
installation of the first released updater-enabled app. An update feed cannot
retrofit an updater into those older binaries. Use released builds for normal
fleet use and keep development bundles under their separate identity.

## Signing identity and artifacts

The private updater key stays in the login Keychain account
`com.am.presstalk.updates`. Its public key is committed in
`resources/PressTalkUpdatePublicKey.txt` and embedded as `SUPublicEDKey`.
`generate_keys --account com.am.presstalk.updates -p` only reads the existing
public key. Do not create another default key, export a private key, put one in
the website repository, or rotate it as part of routine packaging.

The app enables `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`.
`SUSignedFeedFailureExpirationInterval=0` keeps signature enforcement enabled.
The archive must be Developer ID signed, notarized and stapled. Its bundle build
number increases numerically; use the actual final `CFBundleVersion`, not a Git
commit or a prerelease string. The release tool checks the approved Developer ID
requirement, updater key, arm64 executable, minimum macOS, and feed settings.

Sparkle's own `generate_appcast` produces the feed and archive signatures. Its
`sign_update --verify` verifies both. We implement no signing algorithm.
Framework symlinks must survive ZIP creation, so keep the existing `ditto`
packaging step. See [Sparkle setup and signed feeds](https://sparkle-project.org/documentation/)
and [publishing updates](https://sparkle-project.org/documentation/publishing/).

## Release order

1. Finish app verification, signing, notarization and stapling. Package the final
   ZIP once. Preserve its SHA-256 and exact bundle build. No binary or plist
   edits are allowed after signing. Retain the previous release and its receipts.
2. Publish that ZIP under its exact stable GitHub tag, such as
   `v0.1.26/PressTalk-0.1.26-macos-arm64.zip`. The release must be published,
   non-draft and non-prerelease. Never replace that asset or retarget the tag.
   GitHub's immutable-release setting is useful additional protection; its
   presence is recorded by the verifier.
3. Run the preparation command below. It signs the feed, validates it, checks
   the public GitHub release/asset identity and size, downloads the public ZIP,
   compares its SHA-256, and compares builds against the currently published
   signed feed. A failed check leaves publication blocked.
4. Review `appcast.xml` and `publication-receipt.json`. Add the unchanged signed
   XML at `site/appcast.xml` in the **current website checkout**. Preserve other
   website work, including the checkout-recovery PR. Coordinate the updater
   network disclosure before deploying; do not deploy an older website tree
   simply because it contains the app release sources.
5. Publish the feed last. Fetch it over HTTPS and compare its bytes with the
   signed local file. Re-run the preparation command: an identical already-live
   feed is accepted, while a changed same-version feed or downgrade is rejected.
   Test an actual older updater-enabled app updating to the new signed app,
   preserving permissions and settings, then perform a real dictation.

For the first updater release, after its asset has been published:

```sh
UPDATER_TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
python3 scripts/presstalk_appcast.py prepare \
  --archive "$PWD/dist/PressTalk-0.1.26-macos-arm64.zip" \
  --output "$PWD/dist/appcast-0.1.26" \
  --tools-dir "$UPDATER_TOOLS" \
  --keychain-account com.am.presstalk.updates \
  --public-key-file resources/PressTalkUpdatePublicKey.txt \
  --previous-build 25.1 \
  --allow-initial-feed
```

Use the actual release version/path; this example does not declare 0.1.26 ready.
`--allow-initial-feed` permits the canonical feed's first HTTP 404 only. Remove
it after the first publication. For subsequent releases, supply the previous
public build and `--previous-appcast /path/to/previous-signed-appcast.xml`; the
highest previous build wins. Existing feed entries are kept by Sparkle within
its retention limits. The release tool does not enable deltas or beta channels.
Optional `--release-notes /path/to/notes.md` embeds notes in the signed feed.

The command is idempotent: an existing valid output feed is verified and reused
without rewriting its signed bytes. Changed release notes require a fresh
output directory. `publication-receipt.json` records the latest successful
public checks; its asset ID cannot change on a rerun. It never publishes files.
For offline pre-publication checks, `generate` creates only the local signed
feed/receipt; that result is not the public publication gate. `validate` checks
an existing feed and archive, authenticating both before extraction.

Use an ordinary authorized terminal for Keychain and code-signing checks.
Restricted automation can falsely report signature failures despite identical
bytes; do not re-sign or modify an app to work around that diagnostic boundary.

## Verification and recovery

Run the policy tests and official verifier tamper tests:

```sh
PRESSTALK_TEST_SPARKLE_TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin" \
PRESSTALK_TEST_SPARKLE_ACCOUNT=com.am.presstalk.updates \
PRESSTALK_TEST_PUBLIC_KEY_FILE="$PWD/resources/PressTalkUpdatePublicKey.txt" \
  python3 scripts/test_presstalk_appcast.py
```

These sign temporary, noninstallable fixtures and test tampered archives,
unsigned/tampered feeds, wrong configured public keys, downgrade builds,
mutable URLs, draft releases and compatibility errors. They never install an
app, export a private key, or prove a complete user update by themselves.

For real installer acceptance, use `scripts/test_presstalk_sparkle_install.py`
with a fresh private output directory and a coherent Xcode SDK:

```sh
python3 scripts/test_presstalk_sparkle_install.py \
  --output /path/to/new/private-test-run \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk
```

This compiles the unchanged pinned [official sparkle-cli sources](https://sparkle-project.org/documentation/sparkle-cli/)
against the pinned framework and runs its real installer on synthetic apps over
loopback. It uses an ephemeral test key, unique previously absent preference
domains and a settings sentinel. It verifies exact v1-to-v2 replacement and
tampered-payload refusal with v1 intact, then removes the test key and active
test preferences/caches. Receipts retain actual process results and manifests.
No production key, daily app, microphone, elevated installation or public host
is involved. The synthetic apps are ad-hoc signed and closed during the update;
this does not prove notarized PressTalk relaunch or TCC grant continuity.

If a public release is bad, stop offering it while preparing a corrective build
with a higher build number. Keep the original asset and receipts. An old feed
does not downgrade already-updated clients. Do not work around failures by
disabling signature checks, replacing an asset, resetting permissions, or
changing the official signing identity.
