#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-/tmp/presstalk-asr-bench}"
mkdir -p "$out_dir"

say -v Daniel -o "$out_dir/en-30s.aiff" \
  "This is a PressTalk benchmark. I am speaking long enough to measure release latency, streaming throughput, and final transcription speed on Apple Silicon. The important result is not just raw accuracy, but whether the model can keep up while I speak and paste almost immediately after release."

say -v Anna -o "$out_dir/de-30s.aiff" \
  "Schnelle Lieferung und Blitzversand aus Kaiserslautern. Schnell, sicher und direkt zu dir. DHL, DPD und Abholung sind moeglich. Zahlungsarten sind Klarna, Paypal, Visa und Vorkasse. Auch Kauf auf Rechnung ist fuer nicht private Personen auf Anfrage moeglich."

printf 'Wrote benchmark fixtures:\n'
printf '  %s\n' "$out_dir/en-30s.aiff"
printf '  %s\n' "$out_dir/de-30s.aiff"

if command -v afinfo >/dev/null 2>&1; then
  afinfo "$out_dir/en-30s.aiff" | sed -n '1,12p'
  afinfo "$out_dir/de-30s.aiff" | sed -n '1,12p'
fi
