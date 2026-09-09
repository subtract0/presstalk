# Release acceptance — 2026-09-09

The owner explicitly approved shipping build 23.4 with the known first-attempt
AirPods retry: the first attempt showed an error, the second worked, and the
owner accepted release while the underlying issue remains under investigation.
This supersedes treating that known issue as a publication blocker. It does not
declare the microphone transition fixed or establish every-word reliability.

The installed 0.1.23/build 23.4 produced the following live evidence:

- AirPods session 19 at 09:23:34 UTC stopped after two callbacks. At 24 kHz the
  expected sample timestamp was 480 and the observed timestamp was 1,648, a
  jump of 1,168 frames (about 48.7 ms). The receipt is incomplete, reports
  `PT_DISCONTINUITY`, and shows the customer retry message. This establishes the
  timestamp discontinuity, not whether the underlying hardware omitted PCM or
  rebased its clock. Partial audio was not inserted.
- AirPods sessions 20 and 21 retained/consumed 113,280 and 282,720 native frames,
  respectively, converted 75,520 and 188,480 frames, completed, and reached the
  `dictation_insert` outcome. The owner reported successful dictation. There is
  no independently recorded spoken reference for a word-error measurement.
- The intervening Shure sessions also completed. A zero-audio session at
  09:04 UTC followed a 30 ms Fn tap that ended before capture startup; it is not
  counted as a completed dictation or as evidence about the AirPods transition.

Private receipts: `.local/commerce/owner-airpods-23.4.json` and the local trace.
The archive remains the already-notarized build with SHA-256
`4e810986242f962dbd7ddfeaa71163d409cd091194a2f8fa1db926dc393c490b`.
Release notes, both download languages and the support guide disclose the
AirPods retry limitation with the same behavior described by the app.

## Provider state

The owner completed Cloudflare payment. The actual account Billing dashboard
shows **Workers Paid — Active**, renewing October 9, 2026. Its screenshot is
private at `.local/commerce/provider-ui/cloudflare-paid-confirmation.png`.
Resend remains Free for initial receipt email, and the owner has confirmed that
the existing Tuta support forwarding and sending work. These account steps no
longer block release; email quota planning remains separate from paid Workers.

The current real-service check passes Stripe mode/product/currencies, deployed
D1 schema and all three required indexes, app verification-key wiring, verified
sender DNS and disabled email tracking. An initial D1 verification invocation
failed; a direct read of the same remote schema and indexes and then the full
check passed. The initial failure is not counted as a passing check or diagnosed
as a database outage. Existing checkout is active; webhook, receipt redirect,
public artifact and site changes require their actual cutover verification.
