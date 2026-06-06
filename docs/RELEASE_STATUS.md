# Release Status

Current status: public source staged, full cross-machine release not yet proven.

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.

Known current blocker:

- `studio1` has not granted Input Monitoring to PressTalk yet, so the local runtime stops at the macOS permission gate before a real Fn dictation smoke test.

Do not claim full release coverage until these are recorded:

- `studio1`: Fn dictation smoke after Input Monitoring approval.
- `s1`: install plus Fn dictation smoke.
- `s2`: install plus Fn dictation smoke.
- `mbp1`: M1 Max install plus Fn or Option dictation smoke.
