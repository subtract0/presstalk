# Release Status

Current status: public prerelease smoke artifact published, full cross-machine
release not yet proven.

Public prerelease:

- Tag: `v0.1.5-rc7`
- Commit: `9bb83ae086556d5d6301e8940f3bb328908426be`
- URL: `https://github.com/subtract0/presstalk/releases/tag/v0.1.5-rc7`
- Asset: `PressTalk-0.1.5-rc7-macos-arm64.zip`
- SHA-256: `b6b7180e3c6553aa60f3277d6f29f40e5841f9beb8158c1ca17ca788d47e2633`

Verified on `studio1` on 2026-06-06:

- `swift build -c release` succeeds.
- `scripts/build_jarvistap.sh` produces `~/Applications/PressTalk.app`.
- The generated bundle declares microphone, input monitoring, and accessibility usage descriptions.
- `scripts/install_jarvistap_launchd.sh` writes and starts `com.am.jarvistap` with `PRESSTALK_TRIGGER_KEY=fn`.
- `v0.1.5-rc7` is published as a public prerelease smoke artifact, and GitHub
  reports the expected asset SHA-256 digest.
- The `v0.1.5-rc7` zip was inspected locally and contains the expected arm64
  `PressTalk.app`, permission usage descriptions, bundled bootstrap helper,
  bundled local-signing helper, and bundled smoke-status collector.
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
- Current builds write machine-readable runtime status to
  `~/Library/Application Support/JarvisTap/runtime-status.json`; the bundled
  `presstalk-collect-smoke-status.sh` helper collects that file together with
  app signature, launchd state, machine info, and trace tail for cross-machine
  proof.
- Current local builds do not auto-show the settings window by default. They add
  a `Restart PressTalk` settings action for refreshing the running process and
  run read-only preflights plus real listener capability probes during setup.
- Current bootstrap runs launch PressTalk through LaunchServices via
  `/usr/bin/open -gjW` so macOS privacy identity is app-bundle based, and they
  no longer open System Settings panes unless `PRESSTALK_OPEN_PERMISSION_PANES=1`
  is set.
- Current startup/setup checks no longer call macOS permission-request APIs
  automatically. They only preflight and attempt the real listener capability,
  so repeated restarts do not keep prompting for already-approved permissions.
- After the rc6 publish path, the local app was re-bootstrapped and re-signed as
  `Authority=PressTalk Local Development Code Signing`; the collector reports
  LaunchAgent `program = /usr/bin/open`, `Open permission panes: 0`,
  `microphoneGranted=true`, `inputMonitoringGranted=false`,
  `accessibilityGranted=false`, and `setupRetryActive=true`.

Known current blocker:

- On `studio1`, macOS Settings can show PressTalk as enabled while the current
  PressTalk runtime still reports Input Monitoring and Accessibility preflight
  unavailable, and the HID/session event-tap listener probes fail. Treat this as
  a listener/probe blocker; do not keep reopening panes or re-granting
  permissions as the default response.
- `v0.1.5-rc7` includes the latest settings restart/status-collector fixes and
  is the artifact to use for the next cross-machine smoke attempts.
- Remote verification has not started: local SSH aliases `s1` and `s2` are not
  configured on `studio1`, and `mbp1` currently resolves but SSH times out.

Do not claim full release coverage until these are recorded:

- `studio1`: Fn dictation smoke after the listener/probe blocker is resolved.
- `s1`: install plus Fn dictation smoke.
- `s2`: install plus Fn dictation smoke.
- `mbp1`: M1 Max install plus Fn or Option dictation smoke.
