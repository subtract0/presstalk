#!/bin/bash
# Generate the German eval clips.
#
# TWO traps this guards against, both hit for real on 2026-09-04:
#
# 1. `say -v Reed` resolves to the ENGLISH "Reed", not "Reed (Deutsch
#    (Deutschland))". German text then gets spoken by an English voice and the
#    clip is nonsense -- but `say` exits 0, so the eval silently scored 96 bad
#    clips at >100% WER and blamed the model. Voice names MUST be the full
#    identifier from `say -v '?'`.
#
# 2. Text through the shell mangles umlauts. It goes through `say -f` instead,
#    so the reference matches what was spoken byte for byte.
#
# The gate below transcribes one clip per voice and refuses to build the set if
# a voice does not actually produce German. A fixture must prove itself before
# anything measured on it is allowed to mean something.
set -eu
SET="$1"; OUT="$2"; BIN="$3"
mkdir -p "$OUT/audio" "$OUT/ref" "$OUT/.gate"
VOICES=("Anna" "Sandy (Deutsch (Deutschland))" "Rocko (Deutsch (Deutschland))")

printf '%s' "Die Geschäftsführerin überprüft die Größe der Räume für die Übergabe." > "$OUT/.gate/ref.txt"
for v in "${VOICES[@]}"; do
  say -v "$v" -f "$OUT/.gate/ref.txt" -o "$OUT/.gate/probe.aiff"
  w=$("$BIN" --input "$OUT/.gate/probe.aiff" --backend parakeet-v3-ane \
        --reference "$OUT/.gate/ref.txt" --runs 1 --offline --language de 2>&1 \
      | grep -o 'wer=[0-9.]*' | head -1 | cut -d= -f2)
  ok=$(awk -v x="${w:-999}" 'BEGIN{print (x+0<30)?1:0}')
  printf 'gate: %-32s WER=%-7s %s\n' "$v" "${w:-NA}" "$([ "$ok" = 1 ] && echo PASS || echo FAIL)"
  [ "$ok" = 1 ] || { echo "ABORT: '$v' is not producing German audio."; exit 1; }
done

i=0
while IFS=$'\t' read -r cat id text; do
  [ -z "${cat:-}" ] && continue
  for v in "${VOICES[@]}"; do
    short=$(printf '%s' "$v" | sed 's/ .*//')
    base="${cat}__${id}__${short}"
    printf '%s' "$text" > "$OUT/ref/$base.txt"
    say -v "$v" -f "$OUT/ref/$base.txt" -o "$OUT/audio/$base.aiff"
    i=$((i+1))
  done
done < "$SET"
echo "generated $i clips across ${#VOICES[@]} validated German voices"
