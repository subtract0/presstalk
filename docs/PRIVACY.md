# Privacy

PressTalk's pitch is that your voice stays on your Mac. This page says exactly
what that means, including the parts where the network is involved, because a
privacy promise with an asterisk you find later is worse than no promise.

Purchase-service disclosures updated against the prepared implementation on
2026-09-08. Automatic purchase delivery is not live until deployment acceptance
is complete.

## The short version

> Dictation runs on your Mac. PressTalk does not upload your recordings or your
> dictated text. Downloading the speech models during setup needs an internet
> connection. After setup, dictation works offline.

## What happens to your data

| Data | Where it lives | Does it leave your Mac? |
|---|---|---|
| Your voice while you hold the key | Memory only, discarded when the dictation finishes | No |
| The transcript | Pasted into the app you were using, and kept in memory for the "Recent Dictations" menu | No |
| Recent Dictations (last 5) | Memory only. Gone after 15 minutes, on quit, or via "Forget These" | No |
| The clipboard | Every dictation passes through the normal macOS clipboard on its way into the app, then the previous contents are put back about a second later | While it is on the clipboard it follows macOS clipboard behaviour, including Universal Clipboard if you have Handoff on |
| Trace log (`~/Library/Logs/presstalk_trace.log`) | Your Mac. Transcripts are redacted to a length, a word count, and a short digest. Rotates at 8 MB | No, unless you attach it to a support email yourself |
| Diagnostics export | A file you choose to create | Only if you send it |
| Speech models (~460 MB) | `~/Library/Application Support/` | Downloaded from huggingface.co during setup |
| Licence key | Purchase service and your Mac, checked locally after import | Delivered through your receipt, email or licence file. The app does not upload it or contact an activation server |
| Purchase email and order identifiers | Payment processor and purchase service | Used to verify payment, deliver the licence and recover the same licence later |

### About the clipboard, specifically

PressTalk pastes by putting the text on the clipboard and sending Cmd-V. That is
how nearly every dictation and text-expansion tool on macOS works, and it means
your dictated text is briefly on the clipboard even on the normal path.

An earlier version of this page said the clipboard was only used when PressTalk
could not paste. That was wrong, and with Handoff enabled it was wrong in a way
that mattered: dictated text could reach your other Apple devices. PressTalk now
restores whatever you had on the clipboard about a second after pasting, and
leaves it alone if you copied something else in the meantime.

If that still bothers you, turn Handoff off in System Settings → General →
AirDrop & Handoff.

## What PressTalk connects to

In normal dictation mode, the app's network use is for model setup. It does not
send anything you said:

- **huggingface.co** — downloads the speech recognition model, and a tokenizer
  file for the optional second-pass model. Hugging Face sees a download request
  and your IP address, the same as any file download.
- There is no analytics service, crash reporter, telemetry endpoint or recurring
  licence check. Buying or recovering a licence opens the purchase website in
  your browser; that website has the separate data flow described below.

Set `PRESSTALK_LOG_TRANSCRIPTS=1` and PressTalk writes transcripts to its log
verbatim instead of redacting them. That is for debugging your own recognition
problems. It is off by default and it stays on your Mac either way.

## The exceptions, stated plainly

**The optional second-pass model.** PressTalk can run a second, larger model over
low-confidence results to improve them. It is a separate ~620 MB download, it is
not fetched unless you ask for it, and it also runs locally.

**Assistant mode is not dictation mode.** PressTalk ships in dictation mode: hold,
speak, release, paste. It also contains an experimental assistant mode which, if
you turn it on, sends your transcript to an endpoint you configure. That mode is
off by default and you have to set an environment variable to reach it. If you
turn it on, your transcript goes wherever you pointed it.

**Buying is not anonymous.** Stripe processes the payment. The purchase service
reads the payment status, purchased item and checkout email address. It stores
the order identifiers, that email address, the signed licence and delivery
status so it can deliver and recover the same licence. Card numbers are not
received by the purchase service or the Mac app. No recording or dictated text
is involved in buying or recovery.

The prepared service uses Cloudflare Workers and D1 for hosting and order
storage, and Resend for licence emails. Resend receives the recipient address
and receipt contents, including the licence attachment. Email open and click
tracking are disabled. Recovery requests use hashed email and network-address
values to limit repeated requests; the service sends only to the original
checkout address. Order and licence records are retained for future recovery.

Receipt links and licence files are private: anyone you give them to can obtain
the licence. Receipt pages do not use analytics or tracking pixels, are marked
not to be cached, and suppress outgoing referrers. The Mac verifies the licence
locally after import; it does not require a purchase-service connection to keep
dictating.

**Where the text ends up is the other app's business.** PressTalk pastes into
whatever you are using. What Notion or Mail or your terminal then does with those
words follows their behaviour, not ours.

## What we do not claim

No compliance certifications of any kind. No claim of suitability for clinical,
legal, or financial record-keeping. No security audit has been performed. If your
work requires a formal assessment, PressTalk has not had one.

## Checking for yourself

- Turn off Wi-Fi after setup and dictate. It works.
- Search `Sources/` for `URLSession` and `https://` to inspect app connections;
  inspect `commerce/` separately for purchase and email processing.
- Little Snitch or `lsof -i -P | grep PressTalk` will show you the connections.

The source is public at <https://github.com/subtract0/presstalk>. A privacy claim
you can check is worth more than one you have to take on faith.
