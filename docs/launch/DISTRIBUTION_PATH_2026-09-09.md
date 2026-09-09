# Current PressTalk distribution path

As of 9 September 2026, the public release is **0.1.24**. This supersedes the
June roadmap's build, checkout-provider and rollout assumptions. Existing
customer commitments are preserved.

## Download and purchase

The main customer route is the [Mac download](https://presstalk.app/download.html),
with a [German version](https://presstalk.app/de/download.html). The notarized
DMG supports Apple Silicon and macOS 14 or later. The app provides native setup
and shortcut selection, including alternatives to Fn / Globe.

The public trial lasts three days without a card or account. Purchases use the
[current purchase page](https://presstalk.app/buy.html). The current offer and
licence-recovery information on those pages are authoritative; do not reuse
old payment links or “purchases paused” launch packets.

The first recording after connecting AirPods may require a retry. Keep this
limitation visible. The website demonstration is labelled an illustration;
it should not be represented as captured runtime footage.

## Homebrew

The [project tap](https://github.com/subtract0/homebrew-presstalk) follows the
same released app. Its 0.1.24 cask uses the DMG and this SHA-256:

```text
f88c6618ffd69d4cfb9e354953a3757b1cb71bab3a71953e699cee6f1bea79e4
```

The updated cask requires Apple Silicon, uses native app setup and checks the
current stable GitHub release. It removes the old bootstrap postflight and
Karabiner instructions. `brew audit --cask --strict --online` passed, including
artifact download and extraction. This does not substitute for a fresh-user
installation and dictation test.

For existing Homebrew users: quit the app, update Homebrew and upgrade the cask.
Direct-download users should replace their existing app in the same Applications
folder and keep one copy. Preserve preferences, licences and permissions.
No in-app automatic updater is currently claimed.

## Release consistency

Before a release is called distributed, check the live English/German download
links, the GitHub release, the Homebrew cask and the exact artifact digests.
Audit the cask and its livecheck. Date-based tags and prereleases must not be
mistaken for the current stable release.

The legacy publisher's cask template now uses the same native-setup contract.
Its existing artifact-format selection, signing and machine-proof gates are
unchanged. Rendering the template was checked against the audited cask after
version interpolation; the full publisher was not run for this update.

## Next distribution improvements

- Record actual dictation and insertion, preserving the real delay and any
  correction. Label setup/model download separately.
- Learn from first-use and repeat-use reports before expanding acquisition.
- Keep editorial submissions specific and distinguish a sent pitch, published
  coverage, download requests, successful use and purchases.
- Use the public developer-tip routes of relevant Mac publications. Publication
  and reach are not guaranteed. Avoid buying placements against site-wide
  audience claims without evidence about the actual placement.
- Follow current platform rules. In particular, [HN guidelines](https://news.ycombinator.com/newsguidelines.html)
  prohibit generated or AI-edited comments; generated reply drafts are not
  suitable material to post there.
- Plan update discovery and permission/licence-preserving direct upgrades as a
  separate product task. Included updates do not imply an automatic updater.

GitHub asset counts include retries and verification downloads. They do not
measure people or activations, and UTM parameters alone do not record visits.
Any later measurement design must respect the published privacy policy and
avoid dictated content and unsupported attribution claims.
