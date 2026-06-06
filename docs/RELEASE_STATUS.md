# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc1`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc1`
- Asset: `PressTalk-0.1.5-rc1-macos-arm64.zip`
- SHA-256: `7afcbf0284f7f832741eb9cf999a5da5b1f1cd3067aa21d318aba3c701d91e14`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.

Known current blocker:

- `studio1` shows `PressTalk.app` enabled in Input Monitoring, but the freshly
  started app still reports `Startup blocked: Input Monitoring permission
  missing`. The stale duplicate process path was fixed in the installer, so the
  remaining likely issue is TCC identity/signature mismatch from repeated ad-hoc
  development rebuilds. Refresh the permission toggle after the current build, or
  build with a stable `PRESSTALK_CODESIGN_IDENTITY`, before attempting the Fn
  dictation smoke.

Do not claim full release coverage until these are recorded:

- `studio1`: Fn dictation smoke after Input Monitoring approval.
- `s1`: install plus Fn dictation smoke.
- `s2`: install plus Fn dictation smoke.
- `mbp1`: M1 Max install plus Fn or Option dictation smoke.
