#!/usr/bin/env bash
# Gathers everything a supervisor needs to judge whether Astra is on track.
#
# Deliberately does no judging. It answers questions that have factual answers,
# so the judgement is made against evidence rather than against a feeling about
# how the transcript reads. A supervisor that intervenes on vibes will supply
# method, and supplying method to an Astra-class model is the mistake the whole
# handover exists to avoid.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$HOME/.presstalk-sales"
cd "$ROOT" || exit 1

echo "=============================================================="
echo "ASTRA SUPERVISION REPORT · $(date '+%Y-%m-%d %H:%M %Z')"
echo "=============================================================="

echo
echo "## Is a turn running right now?"
if pgrep -f "codex exec" >/dev/null; then
  echo "YES — do not interrupt. Assess after it finishes."
else
  echo "no"
fi

echo
echo "## Session continuity"
if [[ -s "$STATE/astra-session-id" ]]; then
  echo "session $(cat "$STATE/astra-session-id")"
elif pgrep -f "codex exec" >/dev/null; then
  echo "not yet — the id is written when the first turn ends. Normal mid-turn."
else
  echo "NO SESSION RECORDED — every turn restarts from the brief and Astra"
  echo "repeats work it has already done. This is the single most damaging"
  echo "failure mode of the loop and it is silent."
fi
echo "turns run: $(ls -1 "$STATE/runs"/*.txt 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "## Days elapsed against the gates it set itself"
START="2026-09-07"
DAYS=$(( ( $(date +%s) - $(date -j -f "%Y-%m-%d" "$START" +%s) ) / 86400 ))
echo "day $DAYS of the campaign (started $START)"
printf '  day 21 (5 unrelated unsubsidised buyers): %s\n' \
  "$( ((DAYS>=21)) && echo "DUE — verify against Stripe" || echo "in $((21-DAYS)) days")"
printf '  day 35 (5 surviving the refund window):   %s\n' \
  "$( ((DAYS>=35)) && echo "DUE" || echo "in $((35-DAYS)) days")"
printf '  day 56 (second cohort growing):           %s\n' \
  "$( ((DAYS>=56)) && echo "DUE" || echo "in $((56-DAYS)) days")"

echo
echo "## Money"
echo "cap: 50 USD discretionary. Committed spend recorded in LOG.md:"
grep -inE "spent|committed|paid|EUR [0-9]|USD [0-9]|\\\$[0-9]" docs/launch/LOG.md 2>/dev/null \
  | grep -viE "^[0-9]+:.*(cap|hard cap|does not cover|unspent|not a target)" | tail -6 || echo "  (nothing recorded)"

echo
echo "## Open asks for Alex"
if [[ -f docs/launch/ASKS.md ]]; then
  awk 'NR>4 && /^\|/ && $0 !~ /^\|[-: |]+\|$/ && $0 !~ /none yet/' docs/launch/ASKS.md | head -8
  [[ -z "$(awk 'NR>4 && /^\|/ && $0 !~ /^\|[-: |]+\|$/ && $0 !~ /none yet/' docs/launch/ASKS.md)" ]] && echo "  (none)"
else
  echo "  ASKS.md missing"
fi

echo
echo "## What Astra changed (last 12 commits)"
git log --oneline -12 2>/dev/null | sed 's/^/  /'

echo
echo "## Engineering budget — is it drifting back into the codebase?"
echo "Its own limit: repairs only to defects blocking install, first dictation,"
echo "purchase, licence delivery or continued paid use. One day each, 20% of"
echo "effort per fortnight. No refactors, engines, benchmarks or features."
# Counted from the handover commit forward. The first version used "last 14
# days" and swept up an entire night of pre-handover engineering, reporting
# Astra as 51% over a ceiling it had existed for four minutes to exceed. A
# supervisor that cries wolf on its first run teaches everyone to ignore it.
HANDOVER="${ASTRA_HANDOVER_COMMIT:-5824050}"
if git cat-file -e "$HANDOVER^{commit}" 2>/dev/null; then
  SRC=$(git log --oneline "$HANDOVER..HEAD" -- Sources/ 2>/dev/null | wc -l | tr -d ' ')
  ALL=$(git log --oneline "$HANDOVER..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  echo "  since handover ($HANDOVER): $SRC of $ALL commits touch Sources/"
  if [[ "$ALL" -ge 5 ]] && [[ $((SRC * 100 / ALL)) -gt 20 ]]; then
    echo "  OVER its 20% ceiling — check each one names the blocked customer action"
  elif [[ "$ALL" -lt 5 ]]; then
    echo "  (too few commits since handover to judge a ratio)"
  fi
  git log --oneline "$HANDOVER..HEAD" -- Sources/ 2>/dev/null | head -5 | sed 's/^/    /'
else
  echo "  handover commit $HANDOVER not found; cannot measure"
fi

echo
echo "## Selling — has anything reached a stranger?"
echo "  GitHub release downloads:"
gh api repos/subtract0/presstalk/releases --jq '.[] | select(.assets|length>0) | "    \(.tag_name): \(.assets[0].download_count)"' 2>/dev/null | head -4 || echo "    (unavailable)"
echo "  stars/forks: $(gh api repos/subtract0/presstalk --jq '"\(.stargazers_count)/\(.forks_count)"' 2>/dev/null || echo '?')"
echo "  site reachable: $(curl -sS -o /dev/null -w '%{http_code}' -L -m 12 https://presstalk.app 2>/dev/null)"
echo "  checkout reachable: $(curl -sS -o /dev/null -w '%{http_code}' -L -m 12 https://buy.stripe.com/eVq9AU7Egdf55cc345cs80c 2>/dev/null)"

echo
echo "## Do the public claims still hold?"
for g in "presstalk_claims_gate.sh" ; do
  ./scripts/$g >/dev/null 2>&1 && echo "  claims gate: pass" || echo "  claims gate: FAIL — published copy has an unsupported claim"
done
python3 scripts/presstalk_offer_consistency_gate.py >/dev/null 2>&1 && echo "  offer gate: pass" || echo "  offer gate: FAIL — stated offer disagrees with the app"
python3 scripts/presstalk_download_link_gate.py >/dev/null 2>&1 && echo "  link gate: pass" || echo "  link gate: FAIL — a buyer cannot download or pay"

echo
echo "## Last 25 lines Astra wrote"
LAST=$(ls -1t "$STATE/runs"/*.last-message.md 2>/dev/null | head -1)
[[ -n "$LAST" ]] && tail -25 "$LAST" | sed 's/^/  /' || echo "  (no final message recorded yet)"

echo
echo "=============================================================="
