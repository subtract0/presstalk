#!/bin/bash
# Score every German eval clip on every backend. One TSV row per clip so the
# result can be sliced by category, voice, or backend afterwards.
set -u
BIN="$1"; ROOT="$2"; OUT="$3"
printf 'backend\tcategory\tid\tvoice\twer\tcer\trtfx\ttranscript\n' > "$OUT"
for b in parakeet-v3-ane parakeet-v3-gpu stock-v1-gpu; do
  for f in "$ROOT"/audio/*.aiff; do
    base=$(basename "$f" .aiff)
    cat=${base%%__*}; rest=${base#*__}; id=${rest%%__*}; voice=${rest#*__}
    r=$("$BIN" --input "$f" --backend "$b" --reference "$ROOT/ref/$base.txt" \
        --runs 1 --offline --language de 2>&1)
    wer=$(printf '%s' "$r" | grep -o 'wer=[0-9.]*' | head -1 | cut -d= -f2)
    cer=$(printf '%s' "$r" | grep -o 'cer=[0-9.]*' | head -1 | cut -d= -f2)
    rtfx=$(printf '%s' "$r" | grep -o 'rtfx=[0-9.]*' | head -1 | cut -d= -f2)
    tr_=$(printf '%s' "$r" | grep -m1 '^transcript=' | sed 's/^transcript=//')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$b" "$cat" "$id" "$voice" "${wer:-NA}" "${cer:-NA}" "${rtfx:-NA}" "$tr_" >> "$OUT"
  done
  echo "  done $b ($(date +%H:%M:%S))"
done
