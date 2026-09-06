# Support

PressTalk is built by one developer. Support may be handled by the project's
operator, who identifies their role when replying.

New purchases are temporarily paused while payment and licence delivery are
verified. Existing licences, included-update promises and the advertised
14-day refund promise remain in force. If you have already paid and need a
licence or refund, contact **help@presstalk.app**.

## Getting help

Email **help@presstalk.app** with:

1. Your Mac model and macOS version (Apple menu → About This Mac)
2. How you installed: Homebrew or direct download
3. Which trigger key you use
4. What you expected and what happened
5. A diagnostics export, if you can: menu bar → Settings → **Export Diagnostics**

The diagnostics file contains your permission states, signing identity, audio
device, and app version. Transcripts are redacted before they reach the log, so
it does not contain what you dictated. Read it before you send it if you like;
it is plain text.

## The problems people hit first

**"PressTalk cannot be opened because the developer cannot be verified."**
The public 0.1.11 release is signed with Alexander Monas's Developer ID and
carries a stapled notarization ticket. macOS may still ask you to confirm that
you want to open an app downloaded from the internet. A damaged-app or
unverified-developer warning is different: check that you downloaded the current
[official release](https://github.com/subtract0/presstalk/releases/tag/v0.1.11),
and contact support with the exact message before proceeding. See
[Apple's explanation of these prompts](https://support.apple.com/en-us/102445).

**I hold the key and nothing happens.**
Usually Input Monitoring. Open Settings from the menu bar and check the permission
rows; they say which one is missing. If macOS already shows PressTalk as enabled
and the app disagrees, do not keep toggling it — that means the app's signature
changed and macOS is tracking a different identity. Export diagnostics and email
them.

**Text goes to the clipboard instead of the app.**
Accessibility permission is missing, or the target app does not accept programmatic
insertion (secure password fields never do). PressTalk copies instead of losing
your words. The menu bar's **Recent Dictations** has the last few if you need one
back.

**The first dictation takes a while.**
The speech model is about 460 MB and downloads during setup, with progress shown.
After that it stays on your Mac, unless you clear the cache or reinstall.

**German words come out wrong.**
Some are fixable and some are not yet. PressTalk carries a German vocabulary
repair pass for brand names, technical terms, and compounds. If a word you use
often is consistently wrong, send the word and how it should be spelled.

## Refunds

**14 days, no argument.** Email and say you want a refund. You do not have to
explain, and you will not be talked out of it. One optional question about what
went wrong, which you can ignore.

This is not generosity, it is self-interest: a refund costs less than someone
feeling stuck with software that did not work for them.

## Response times

Best effort, usually within a day or two. There is no guaranteed response time
and no support contract. If that is not enough for your situation, do not buy
this yet.

## What is not supported

- Intel Macs. Apple Silicon only.
- Anything before macOS 14.
- The experimental assistant mode. It exists in the source, it is off by default,
  and you are on your own with it.
- Deployment across a managed fleet. No documented path for that yet.
