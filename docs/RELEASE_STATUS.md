# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc2`
- Commit: `0d891c0c26413744e5020e49f91b0a79273de81d`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc2`
- Asset: `PressTalk-0.1.5-rc2-macos-arm64.zip`
- SHA-256: `0d825aa1de0ee0adc861cf277bd45415c80d0a250e14c075df2d5082aae56a92`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc2` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc2` zip was unpacked locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, and ad-hoc app signature.
- A local development code-signing identity was created on `studio1`, and a
  local build now signs as `Authority=PressTalk Local Development Code Signing`
  instead of ad-hoc. The LaunchAgent was restarted against that stable-signed
  build with `PRESSTALK_TRIGGER_KEY=fn`.

Known current blocker:

- `studio1` has repeated ad-hoc development rebuilds. The trace proved one build
  could reach `Input Monitoring permission OK` and `Microphone permission OK`,
  but the next rebuild changed the ad-hoc CDHash and the runtime again reported
  `Startup blocked: Input Monitoring permission missing`. `studio1` now has a
  stable local development signing identity, so refresh the permission toggle
  once for the stable-signed build before attempting the Fn dictation smoke.
- `v0.1.5-rc2` includes the settings-window fix for this case: the UI now
  distinguishes "not granted to this rebuilt ad-hoc copy" from a generic missing
  permission, and diagnostics include the app code-signature summary.
- Remote verification has not started: local SSH aliases `s1` and `s2` are not
  configured on `studio1`, and `mbp1` currently resolves but SSH times out.

Do not claim full release coverage until these are recorded:

- `studio1`: Fn dictation smoke after Input Monitoring approval.
- `s1`: install plus Fn dictation smoke.
- `s2`: install plus Fn dictation smoke.
- `mbp1`: M1 Max install plus Fn or Option dictation smoke.
