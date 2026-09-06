# The posts, written out

Copy these. Do not improvise on the day. Every number here is in
`docs/MEASUREMENTS.md` and the claims gate checks that it stays so.

---

## r/macapps — monthly megathread

> **PressTalk — local push-to-talk dictation, $20 once, and I published the error rate**
>
> Hold Fn, talk, let go, the text lands in whatever app you were in. Recognition
> runs on the Neural Engine — nothing is uploaded, no account, works with Wi-Fi off
> once it is set up.
>
> The thing I have not seen anyone else in this category do: I measured it and
> published the measurement. On 144 German test clips, scored against written
> references with the same post-processing applied to both, Apple's own on-device
> engine gets 19.38% word error rate and PressTalk gets 12.71%. The test set and
> the scorer are in the repo, so you can disagree with me using my own data.
>
> Honest limits: that audio is synthesised speech in three voices, not people in
> rooms, so treat it as a regression baseline rather than a promise about your
> voice. I have not benchmarked against Wispr Flow or Superwhisper and I am not
> going to claim I am better than something I have not measured.
>
> I cancelled a $15/month subscription to use this instead. 174 dictations over 26
> days on my own machines, none lost.
>
> Apple Silicon, macOS 14+. $20 once, every future Mac update included.
>
> `brew install --cask subtract0/presstalk/presstalk`

---

## Hacker News — Show HN

**Title:**
> Show HN: I measured my Mac dictation app's German error rate against Apple's own

**Body:**
> Every dictation app claims accuracy. I could not find one that published a
> number you could check, so I published mine along with the test set and the
> scorer.
>
> 144 German clips, scored against written references, the same vocabulary
> post-processing applied to both engines so it is like for like: Apple's
> on-device engine 19.38% WER, PressTalk 12.71%. About a third fewer errors.
>
> What I will not claim: the audio is synthesised speech in three voices rather
> than people in rooms, so it is a regression baseline. Most of the brand and
> technical terms in the vocabulary list also appear in the test sentences, which
> flatters both columns. And I have not benchmarked against the paid competitors,
> so I have no idea whether I beat them.
>
> The app is push-to-talk: hold Fn, speak, release, the text is pasted into the
> focused app. Recognition is Parakeet v3 on the Neural Engine via FluidAudio.
> Nothing leaves the machine — there is no analytics, no crash reporter and no
> licence server, and the licence is an offline signed file so it keeps working
> if I disappear.
>
> Median from key release to text on screen is 0.618s on an M4 Max, worst case
> 0.629s across the run. The interesting part is the max: an earlier build had a
> second recognizer that fired about half the time and produced a 3.3s tail, and
> removing it collapsed the variance rather than just moving the median.
>
> $20 once. Source is public.

**Expect:** "why not whisper.cpp", "Apple's dictation is free", and someone who
has built the same thing. The measurement framing is what survives those.

---

## The German post

**Title:**
> Warum Apples deutsche Diktierfunktion scheitert — und was ich dagegen gemacht habe

**Opening:**
> Apples Diktierfunktion läuft inzwischen lokal auf dem Mac. Für Deutsch reicht das
> oft trotzdem nicht: Markennamen, Fachbegriffe und zusammengesetzte Substantive
> gehen reihenweise daneben.
>
> Ich habe es gemessen, statt es zu behaupten. 144 deutsche Testclips, gegen
> geschriebene Referenzen, dieselbe Nachbearbeitung auf beiden Seiten: Apples
> eigene On-Device-Engine 19,38 % Wortfehlerrate, PressTalk 12,71 %.
>
> Testset und Auswertungsskript liegen im Repository. Wer mir nicht glaubt, kann
> es mit meinen eigenen Daten widerlegen.

Then the category table from `MEASUREMENTS.md`, then the honest limits, then the
Homebrew line.

---

## When someone asks "is it better than Wispr Flow?"

Do not guess. The true answer is stronger than a guess:

> I don't know — I haven't measured against it, and I'm not going to tell you I'm
> better than something I haven't tested. What I can tell you is I cancelled my
> Wispr Flow subscription to use this, it costs $20 once instead of $180 a year,
> and nothing I say goes to anyone's server. If you try it and it's worse for
> you, I'll refund you.
