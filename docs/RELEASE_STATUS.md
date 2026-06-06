# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc3`
- Commit: `95ae172578e524e19d08ddc8dec0102d9594e95d`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc3`
- Asset: `PressTalk-0.1.5-rc3-macos-arm64.zip`
- SHA-256: `608b8c1b0adc38694cb32fc54a4bd9f8213cffa817882f706120fff99df576fd`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc3` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc3` zip was inspected locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, bundled bootstrap helper, and
  bundled local-signing helper.
- A local development code-signing identity was created on `studio1`, and a
  local build now signs as `Authority=PressTalk Local Development Code Signing`
  instead of ad-hoc. The LaunchAgent was restarted against that stable-signed
  build with `PRESSTALK_TRIGGER_KEY=fn`.
- The bundled bootstrap path was tested on `studio1`: a normal ad-hoc build was
  re-signed by the app-bundled local-signing helper before launchd started it.
  The resulting app reports `Authority=PressTalk Local Development Code
  Signing`, and launchd is running it with `PRESSTALK_TRIGGER_KEY=fn`.
- While blocked on Input Monitoring, the local app now starts a quiet setup retry
  timer. Trace evidence on `studio1`: `Setup retry timer started
  interval_seconds=5.0`.

Known current blocker:

- `studio1` has repeated ad-hoc development rebuilds. The trace proved one build
  could reach `Input Monitoring permission OK` and `Microphone permission OK`,
  but the next rebuild changed the ad-hoc CDHash and the runtime again reported
  `Startup blocked: Input Monitoring permission missing`. `studio1` now has a
  stable local development signing identity, so refresh the permission toggle
  once for the stable-signed build before attempting the Fn dictation smoke.
- `v0.1.5-rc3` includes the settings-window fix for this case: the UI now
  distinguishes "not granted to this rebuilt ad-hoc copy" from a generic missing
  permission, and diagnostics include the app code-signature summary.
- Remote verification has not started: local SSH aliases `s1` and `s2` are not
  configured on `studio1`, and `mbp1` currently resolves but SSH times out.

Do not claim full release coverage until these are recorded:

- `studio1`: Fn dictation smoke after Input Monitoring approval.
- `s1`: install plus Fn dictation smoke.
- `s2`: install plus Fn dictation smoke.
- `mbp1`: M1 Max install plus Fn or Option dictation smoke.
