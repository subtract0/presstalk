#!/usr/bin/env bash
# Refuses phrases PressTalk has no evidence for.
#
# What this catches: superlatives, absolutes, and borrowed numbers. What it
# cannot catch: an ordinary sentence that is simply false. Passing is a floor,
# not a review.
#
# Every entry here was blocked for a reason recorded beside it. Marketing copy
# drifts toward superlatives on its own, and the gap between "115x realtime
# throughput" and "20x faster dictation" is the kind of sentence that gets
# written in good faith and is still false.
#
# Adding a phrase is easy. Removing one requires the evidence named in its
# reason.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) echo "Usage: presstalk_claims_gate.sh [files or dirs…]"; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  # Customer-facing surfaces only. Engineering notes discuss "instantaneous
  # throughput" and quote forbidden phrases in order to forbid them; gating those
  # would train everyone to pass --no-verify.
  TARGETS=(
    "$ROOT/README.md"
    "$ROOT/site"
    "$ROOT/docs/PRIVACY.md"
    "$ROOT/docs/SUPPORT.md"
    "$ROOT/docs/MONETIZATION.md"
  )
fi

# phrase|reason
FORBIDDEN=(
  "fastest|no competitor comparison has been run"
  "the best |no competitor comparison has been run"
  "most accurate|no competitor comparison has been run"
  "best-in-class|no competitor comparison has been run"
  "unmatched|no competitor comparison has been run"
  "instant|inference throughput is not user-visible latency"
  "instantly|inference throughput is not user-visible latency"
  "zero latency|inference throughput is not user-visible latency"
  "real-time transcription|the shipped default is push-to-talk, not streaming"
  "20x faster|throughput relative to audio duration is not a speed comparison"
  "115x faster|115x is realtime factor against audio duration, not against anything else"
  "never uses the internet|models and a tokenizer download during setup"
  "no internet|models and a tokenizer download during setup"
  "works completely offline|true only after setup finishes"
  "downloads once|reinstalls, cleared caches, and model updates can download again"
  "no data ever leaves|downloads, purchases, and diagnostics need separate wording"
  "zero data collection|downloads, purchases, and diagnostics need separate wording"
  "anonymous purchase|the payment processor sees the buyer"
  "nothing is stored|needs a complete audio, transcript, log, clipboard and diagnostics audit"
  "works in every app|secure fields, focus loss, and delivery failures exist"
  "never loses|delivery failures exist"
  "no setup|three permissions and a model download exist"
  "lightweight|model storage, peak RAM, and energy were never measured"
  "battery efficient|energy use was never measured"
  "battery-efficient|energy use was never measured"
  "lifetime updates|undefined and unenforceable; the licence covers 1.x"
  "unlimited support|undefined and unenforceable"
  "HIPAA|no compliance assessment exists"
  "GDPR compliant|no compliance assessment exists"
  "enterprise-grade security|no security assessment exists"
  "medical-grade|no assessment exists"
  "military-grade|no assessment exists"
  "guaranteed accuracy|WER on a small evaluation is not a guarantee"
  "100% accurate|no"
  "Apple approved|notarization is not approval, and it is not done yet"
  "seamless updates|there is no updater"
  "bank-level|means nothing"
)

# Legitimate uses: the gate's own list, and prose that quotes a phrase to reject it.
EXEMPT_PATTERN='presstalk_claims_gate|do-not-say|DO NOT SAY|must not claim|never claim|do not claim|Do not say|cannot claim'

failures=0
files=()
for target in "${TARGETS[@]}"; do
  [[ -e "$target" ]] || continue
  if [[ -d "$target" ]]; then
    while IFS= read -r file; do files+=("$file"); done \
      < <(find "$target" -type f \( -name '*.md' -o -name '*.html' -o -name '*.txt' \))
  else
    files+=("$target")
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files to check."
  exit 0
fi

echo "Checking ${#files[@]} file(s) against ${#FORBIDDEN[@]} blocked phrases."
for file in "${files[@]}"; do
  for entry in "${FORBIDDEN[@]}"; do
    phrase="${entry%%|*}"
    reason="${entry#*|}"
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      line_number="${hit%%:*}"
      line_text="${hit#*:}"
      if printf '%s' "$line_text" | grep -qiE "$EXEMPT_PATTERN"; then
        continue
      fi
      echo "FAIL ${file#$ROOT/}:${line_number}"
      echo "     phrase: \"${phrase}\""
      echo "     reason: ${reason}"
      failures=$((failures + 1))
    done < <(grep -inE "(^|[^[:alnum:]-])${phrase}([^[:alnum:]-]|$)" "$file" || true)
  done
done

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures unsupported claim(s). Either remove the phrase or produce the evidence." >&2
  exit 1
fi
# Deliberately modest. A phrase list cannot establish that a sentence is true --
# it caught nothing in "no silence guessing, no waiting", which was plainly false
# against a capture path that waits for silence. Only a reader who knows the code
# catches that.
echo "None of the blocked phrases appear. This does not establish that the claims are true."
