#!/usr/bin/env bash
set -euo pipefail

SSH_CONFIG="${PRESSTALK_SSH_CONFIG_PATH:-$HOME/.ssh/config}"
OUTPUT_FORMAT="text"
JSON_OUTPUT_PATH=""
BONJOUR_ENABLED=1
TAILSCALE_ENABLED=1
ARP_ENABLED=1
BONJOUR_TIMEOUT="${PRESSTALK_BONJOUR_TIMEOUT:-3}"
SSH_CONNECT_TIMEOUT="${PRESSTALK_SSH_CONNECT_TIMEOUT:-3}"
PROBE_SSH=0
TARGETS=()

usage() {
  cat <<EOF
Usage: presstalk-host-discovery.sh [options]

Collects read-only host/alias evidence before PressTalk release matrix runs.
It can parse local SSH config aliases, browse Bonjour SSH advertisements, record
Tailscale and ARP status, and optionally run strict read-only SSH probes.

Options:
  --target HOST       Target alias to inspect. May be repeated.
  --targets LIST      Comma-separated target aliases.
  --probe-ssh         Also run a strict BatchMode SSH probe for each target.
  --timeout SECONDS   SSH ConnectTimeout and Bonjour browse timeout. Default: 3.
  --no-bonjour        Skip Bonjour browsing.
  --no-tailscale      Skip Tailscale status collection.
  --no-arp            Skip ARP table collection.
  --json              Write only machine-readable JSON to stdout.
  --json-output PATH  Also write machine-readable JSON to PATH.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --target" >&2
        exit 2
      fi
      TARGETS+=("$2")
      shift 2
      ;;
    --targets)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --targets" >&2
        exit 2
      fi
      IFS=',' read -r -a parsed_targets <<<"$2"
      for parsed_target in "${parsed_targets[@]}"; do
        parsed_target="${parsed_target#"${parsed_target%%[![:space:]]*}"}"
        parsed_target="${parsed_target%"${parsed_target##*[![:space:]]}"}"
        [[ -z "$parsed_target" ]] && continue
        TARGETS+=("$parsed_target")
      done
      shift 2
      ;;
    --probe-ssh)
      PROBE_SSH=1
      shift
      ;;
    --timeout)
      if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ || "$2" -eq 0 ]]; then
        echo "Invalid value for --timeout" >&2
        exit 2
      fi
      SSH_CONNECT_TIMEOUT="$2"
      BONJOUR_TIMEOUT="$2"
      shift 2
      ;;
    --no-bonjour)
      BONJOUR_ENABLED=0
      shift
      ;;
    --no-tailscale)
      TAILSCALE_ENABLED=0
      shift
      ;;
    --no-arp)
      ARP_ENABLED=0
      shift
      ;;
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --json-output)
      JSON_OUTPUT_PATH="${2:-}"
      if [[ -z "$JSON_OUTPUT_PATH" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-host-discovery.XXXXXX")"
trap 'rm -rf "$RUN_TMPDIR"' EXIT
RESULT_PLIST="$RUN_TMPDIR/host-discovery.plist"
plutil -create xml1 "$RESULT_PLIST" >/dev/null

plist_insert_string() {
  local key="$1"
  local value="${2:-}"
  plutil -insert "$key" -string "${value:-unknown}" "$RESULT_PLIST" >/dev/null
}

plist_insert_int() {
  local key="$1"
  local value="${2:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    plutil -insert "$key" -integer "$value" "$RESULT_PLIST" >/dev/null
  else
    plutil -insert "$key" -integer 0 "$RESULT_PLIST" >/dev/null
  fi
}

plist_insert_bool() {
  local key="$1"
  local value="${2:-false}"
  case "$value" in
    true|1) plutil -insert "$key" -bool true "$RESULT_PLIST" >/dev/null ;;
    *) plutil -insert "$key" -bool false "$RESULT_PLIST" >/dev/null ;;
  esac
}

append_array_string() {
  local key="$1"
  local value="${2:-}"
  plutil -insert "$key" -string "${value:-unknown}" -append "$RESULT_PLIST" >/dev/null
}

single_line_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c 1-500
  fi
}

ssh_config_value() {
  local target="$1"
  local key="$2"
  local output_file="$3"
  awk -v key="$key" 'tolower($1) == key { $1=""; sub(/^[[:space:]]+/, ""); print; exit }' "$output_file"
}

plist_insert_string "schemaVersion" "1"
plist_insert_string "generatedAt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
plutil -insert sshConfig -dictionary "$RESULT_PLIST" >/dev/null
plist_insert_string "sshConfig.path" "$SSH_CONFIG"
plist_insert_bool "sshConfig.exists" "$([[ -f "$SSH_CONFIG" ]] && echo true || echo false)"
plist_insert_int "sshConnectTimeoutSeconds" "$SSH_CONNECT_TIMEOUT"
plist_insert_int "bonjourTimeoutSeconds" "$BONJOUR_TIMEOUT"
plist_insert_bool "sshProbeEnabled" "$([[ "$PROBE_SSH" == "1" ]] && echo true || echo false)"
plist_insert_bool "tailscaleEnabled" "$([[ "$TAILSCALE_ENABLED" == "1" ]] && echo true || echo false)"
plist_insert_bool "arpEnabled" "$([[ "$ARP_ENABLED" == "1" ]] && echo true || echo false)"
plutil -insert sshConfig.hosts -array "$RESULT_PLIST" >/dev/null

if [[ -f "$SSH_CONFIG" ]]; then
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    append_array_string "sshConfig.hosts" "$host"
  done < <(
    awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) print $i }' "$SSH_CONFIG" |
      sort -u
  )
fi

plutil -insert tailscale -dictionary "$RESULT_PLIST" >/dev/null
plist_insert_bool "tailscale.enabled" "$([[ "$TAILSCALE_ENABLED" == "1" ]] && echo true || echo false)"
plutil -insert tailscale.rawLines -array "$RESULT_PLIST" >/dev/null
plutil -insert tailscale.nodes -array "$RESULT_PLIST" >/dev/null
if [[ "$TAILSCALE_ENABLED" == "1" ]]; then
  tailscale_bin="${PRESSTALK_TAILSCALE_PATH:-$(command -v tailscale 2>/dev/null || true)}"
  plist_insert_string "tailscale.path" "${tailscale_bin:-missing}"
  if [[ -n "$tailscale_bin" && -x "$tailscale_bin" ]]; then
    tailscale_output="$RUN_TMPDIR/tailscale-status.out"
    tailscale_error="$RUN_TMPDIR/tailscale-status.err"
    tailscale_status=0
    set +e
    "$tailscale_bin" status >"$tailscale_output" 2>"$tailscale_error"
    tailscale_status=$?
    set -e
    plist_insert_int "tailscale.exitStatus" "$tailscale_status"
    tailscale_error_summary="$(single_line_file "$tailscale_error")"
    tailscale_output_summary="$(single_line_file "$tailscale_output")"
    if [[ "$tailscale_status" -eq 0 ]] &&
       ! printf '%s\n' "$tailscale_output_summary" | grep -Eiq 'failed to start|clierror|error'; then
      plist_insert_bool "tailscale.statusAvailable" true
      plist_insert_string "tailscale.error" "$tailscale_error_summary"
    else
      plist_insert_bool "tailscale.statusAvailable" false
      if [[ -n "$tailscale_error_summary" ]]; then
        plist_insert_string "tailscale.error" "$tailscale_error_summary"
      else
        plist_insert_string "tailscale.error" "$tailscale_output_summary"
      fi
    fi

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      plutil -insert tailscale.rawLines -string "$line" -append "$RESULT_PLIST" >/dev/null
      ip="$(printf '%s\n' "$line" | awk '{ print $1 }')"
      name="$(printf '%s\n' "$line" | awk '{ print $2 }')"
      if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$ip" == *":"* ]]; then
        node_plist="$RUN_TMPDIR/tailscale-node-$RANDOM.plist"
        plutil -create xml1 "$node_plist" >/dev/null
        plutil -insert ip -string "$ip" "$node_plist" >/dev/null
        plutil -insert name -string "${name:-unknown}" "$node_plist" >/dev/null
        plutil -insert statusLine -string "$line" "$node_plist" >/dev/null
        node_json="$(plutil -convert json -r -o - "$node_plist")"
        plutil -insert tailscale.nodes -json "$node_json" -append "$RESULT_PLIST" >/dev/null
      fi
    done <"$tailscale_output"
  else
    plist_insert_int "tailscale.exitStatus" 0
    plist_insert_bool "tailscale.statusAvailable" false
    plist_insert_string "tailscale.error" "tailscale unavailable"
  fi
else
  plist_insert_int "tailscale.exitStatus" 0
  plist_insert_bool "tailscale.statusAvailable" false
  plist_insert_string "tailscale.error" "disabled"
fi

plutil -insert arp -dictionary "$RESULT_PLIST" >/dev/null
plist_insert_bool "arp.enabled" "$([[ "$ARP_ENABLED" == "1" ]] && echo true || echo false)"
plutil -insert arp.rawLines -array "$RESULT_PLIST" >/dev/null
plutil -insert arp.entries -array "$RESULT_PLIST" >/dev/null
if [[ "$ARP_ENABLED" == "1" ]]; then
  arp_bin="${PRESSTALK_ARP_PATH:-$(command -v arp 2>/dev/null || true)}"
  plist_insert_string "arp.path" "${arp_bin:-missing}"
  if [[ -n "$arp_bin" && -x "$arp_bin" ]]; then
    arp_output="$RUN_TMPDIR/arp.out"
    arp_error="$RUN_TMPDIR/arp.err"
    arp_status=0
    set +e
    "$arp_bin" -a >"$arp_output" 2>"$arp_error"
    arp_status=$?
    set -e
    plist_insert_int "arp.exitStatus" "$arp_status"
    plist_insert_string "arp.error" "$(single_line_file "$arp_error")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      plutil -insert arp.rawLines -string "$line" -append "$RESULT_PLIST" >/dev/null
      if [[ "$line" == *" ("* && "$line" == *") at "* && "$line" == *" on "* ]]; then
        host="${line%% (*}"
        ip_part="${line#*(}"
        ip="${ip_part%%)*}"
        if [[ "$ip" == 224.* || "$ip" == 239.* ]]; then
          continue
        fi
        after_at="${line#*) at }"
        mac="${after_at%% on *}"
        after_on="${line##* on }"
        interface="${after_on%% *}"
        entry_plist="$RUN_TMPDIR/arp-entry-$RANDOM.plist"
        plutil -create xml1 "$entry_plist" >/dev/null
        plutil -insert host -string "${host:-unknown}" "$entry_plist" >/dev/null
        plutil -insert ip -string "${ip:-unknown}" "$entry_plist" >/dev/null
        plutil -insert mac -string "${mac:-unknown}" "$entry_plist" >/dev/null
        plutil -insert interface -string "${interface:-unknown}" "$entry_plist" >/dev/null
        plutil -insert rawLine -string "$line" "$entry_plist" >/dev/null
        entry_json="$(plutil -convert json -r -o - "$entry_plist")"
        plutil -insert arp.entries -json "$entry_json" -append "$RESULT_PLIST" >/dev/null
      fi
    done <"$arp_output"
  else
    plist_insert_int "arp.exitStatus" 0
    plist_insert_string "arp.error" "arp unavailable"
  fi
else
  plist_insert_int "arp.exitStatus" 0
  plist_insert_string "arp.error" "disabled"
fi

plutil -insert targets -array "$RESULT_PLIST" >/dev/null
if [[ "${#TARGETS[@]}" -gt 0 ]]; then
for target in "${TARGETS[@]}"; do
  target_plist="$RUN_TMPDIR/target-$RANDOM.plist"
  plutil -create xml1 "$target_plist" >/dev/null
  plutil -insert target -string "$target" "$target_plist" >/dev/null

  ssh_g_output="$RUN_TMPDIR/ssh-g-$RANDOM.txt"
  ssh_g_error="$RUN_TMPDIR/ssh-g-$RANDOM.err"
  ssh_g_status=0
  ssh_config_args=()
  if [[ -f "$SSH_CONFIG" ]]; then
    ssh_config_args=(-F "$SSH_CONFIG")
  fi
  set +e
  ssh "${ssh_config_args[@]}" -T -G "$target" >"$ssh_g_output" 2>"$ssh_g_error"
  ssh_g_status=$?
  set -e

  plutil -insert sshConfigResolved -bool "$([[ "$ssh_g_status" -eq 0 ]] && echo true || echo false)" "$target_plist" >/dev/null
  plutil -insert sshConfigError -string "$(single_line_file "$ssh_g_error")" "$target_plist" >/dev/null
  if [[ "$ssh_g_status" -eq 0 ]]; then
    plutil -insert hostName -string "$(ssh_config_value "$target" hostname "$ssh_g_output")" "$target_plist" >/dev/null
    plutil -insert user -string "$(ssh_config_value "$target" user "$ssh_g_output")" "$target_plist" >/dev/null
    plutil -insert port -string "$(ssh_config_value "$target" port "$ssh_g_output")" "$target_plist" >/dev/null
    plutil -insert identityFile -string "$(ssh_config_value "$target" identityfile "$ssh_g_output")" "$target_plist" >/dev/null
  else
    plutil -insert hostName -string "unknown" "$target_plist" >/dev/null
    plutil -insert user -string "unknown" "$target_plist" >/dev/null
    plutil -insert port -string "unknown" "$target_plist" >/dev/null
    plutil -insert identityFile -string "unknown" "$target_plist" >/dev/null
  fi

  plutil -insert sshProbe -dictionary "$target_plist" >/dev/null
  plutil -insert sshProbe.enabled -bool "$([[ "$PROBE_SSH" == "1" ]] && echo true || echo false)" "$target_plist" >/dev/null
  if [[ "$PROBE_SSH" == "1" ]]; then
    probe_out="$RUN_TMPDIR/probe-$RANDOM.out"
    probe_err="$RUN_TMPDIR/probe-$RANDOM.err"
    probe_status=0
    set +e
    ssh "${ssh_config_args[@]}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=yes \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      "$target" 'printf presstalk-ssh-ok' >"$probe_out" 2>"$probe_err"
    probe_status=$?
    set -e
    plutil -insert sshProbe.exitStatus -integer "$probe_status" "$target_plist" >/dev/null
    plutil -insert sshProbe.success -bool "$([[ "$probe_status" -eq 0 ]] && echo true || echo false)" "$target_plist" >/dev/null
    plutil -insert sshProbe.output -string "$(single_line_file "$probe_out")" "$target_plist" >/dev/null
    plutil -insert sshProbe.error -string "$(single_line_file "$probe_err")" "$target_plist" >/dev/null
  else
    plutil -insert sshProbe.exitStatus -integer 0 "$target_plist" >/dev/null
    plutil -insert sshProbe.success -bool false "$target_plist" >/dev/null
    plutil -insert sshProbe.output -string "not_requested" "$target_plist" >/dev/null
    plutil -insert sshProbe.error -string "not_requested" "$target_plist" >/dev/null
  fi

  target_json="$(plutil -convert json -r -o - "$target_plist")"
  plutil -insert targets -json "$target_json" -append "$RESULT_PLIST" >/dev/null
done
fi

plutil -insert bonjour -dictionary "$RESULT_PLIST" >/dev/null
plist_insert_bool "bonjour.enabled" "$([[ "$BONJOUR_ENABLED" == "1" ]] && echo true || echo false)"
plutil -insert bonjour.services -array "$RESULT_PLIST" >/dev/null
if [[ "$BONJOUR_ENABLED" == "1" && -x /usr/bin/dns-sd ]]; then
  for service_type in "_ssh._tcp" "_sftp-ssh._tcp"; do
    service_plist="$RUN_TMPDIR/bonjour-$RANDOM.plist"
    service_output="$RUN_TMPDIR/bonjour-$RANDOM.out"
    plutil -create xml1 "$service_plist" >/dev/null
    plutil -insert serviceType -string "$service_type" "$service_plist" >/dev/null
    plutil -insert rawLines -array "$service_plist" >/dev/null
    plutil -insert names -array "$service_plist" >/dev/null

    /usr/bin/dns-sd -B "$service_type" local >"$service_output" 2>&1 &
    dns_pid=$!
    sleep "$BONJOUR_TIMEOUT"
    kill "$dns_pid" >/dev/null 2>&1 || true
    wait "$dns_pid" >/dev/null 2>&1 || true

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      plutil -insert rawLines -string "$line" -append "$service_plist" >/dev/null
      if [[ "$line" == *" Add "* && "$line" == *"$service_type."* ]]; then
        name="$(printf '%s\n' "$line" | sed "s/.*$service_type\\. *//")"
        [[ -n "$name" ]] && plutil -insert names -string "$name" -append "$service_plist" >/dev/null
      fi
    done <"$service_output"

    service_json="$(plutil -convert json -r -o - "$service_plist")"
    plutil -insert bonjour.services -json "$service_json" -append "$RESULT_PLIST" >/dev/null
  done
else
  plist_insert_string "bonjour.skippedReason" "$([[ "$BONJOUR_ENABLED" == "1" ]] && echo "dns-sd unavailable" || echo "disabled")"
fi

write_json() {
  local path="$1"
  plutil -convert json -r -o "$path" "$RESULT_PLIST"
}

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  write_json "-"
else
  targets_text="(none)"
  if [[ "${#TARGETS[@]}" -gt 0 ]]; then
    targets_text="${TARGETS[*]}"
  fi
  echo "PressTalk host discovery"
  echo "SSH config: $SSH_CONFIG"
  echo "Targets: $targets_text"
  echo "Bonjour: $([[ "$BONJOUR_ENABLED" == "1" ]] && echo enabled || echo disabled)"
  echo "Tailscale: $([[ "$TAILSCALE_ENABLED" == "1" ]] && echo enabled || echo disabled)"
  echo "ARP: $([[ "$ARP_ENABLED" == "1" ]] && echo enabled || echo disabled)"
  echo "SSH probe: $([[ "$PROBE_SSH" == "1" ]] && echo enabled || echo disabled)"
  if [[ -n "$JSON_OUTPUT_PATH" ]]; then
    echo "HostDiscoveryJSON: $JSON_OUTPUT_PATH"
  fi
fi

if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  write_json "$JSON_OUTPUT_PATH"
fi
