#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/presstalk_host_discovery.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-host-discovery-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

ssh_config="$TEST_TMPDIR/ssh_config"
json_report="$TEST_TMPDIR/host-discovery.json"
text_report="$TEST_TMPDIR/host-discovery.txt"
probe_json_report="$TEST_TMPDIR/host-discovery-probe.json"
tailscale_failure_json_report="$TEST_TMPDIR/host-discovery-tailscale-failure.json"
fake_tailscale="$TEST_TMPDIR/tailscale"
fake_arp="$TEST_TMPDIR/arp"

cat >"$ssh_config" <<'SSHCONFIG'
Host mbp1-tb
  HostName 10.77.77.3
  User alexandermonas
  Port 22
  IdentityFile /Users/am/.ssh/id_ed25519

Host s1 s1.local
  HostName s1.local
  User am

Host invalid-host
  HostName presstalk-invalid-host.invalid
  User am
SSHCONFIG

cat >"$fake_tailscale" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "status" ]]; then
  echo "unexpected tailscale arg: $*" >&2
  exit 2
fi
if [[ "${PRESSTALK_FAKE_TAILSCALE_FAIL_STDOUT:-0}" == "1" ]]; then
  echo "The Tailscale CLI failed to start: Tailscale.CLIError error 1."
  exit 0
fi
cat <<'STATUS'
100.64.0.10 s1 alex@ macOS active
100.64.0.20 mbp1 alex@ macOS active
STATUS
SH
chmod +x "$fake_tailscale"

cat >"$fake_arp" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "-a" ]]; then
  echo "unexpected arp arg: $*" >&2
  exit 2
fi
cat <<'ARP'
s1.local (192.168.0.23) at 1:2:3:4:5:6 on en1 ifscope [ethernet]
macbookpro (192.168.0.41) at 86:13:32:de:1:a7 on en1 ifscope [ethernet]
ARP
SH
chmod +x "$fake_arp"

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" PRESSTALK_TAILSCALE_PATH="$fake_tailscale" PRESSTALK_ARP_PATH="$fake_arp" "$HELPER" \
  --no-bonjour \
  --target mbp1-tb \
  --target s1 \
  --json-output "$json_report" >"$text_report"

if [[ ! -s "$json_report" ]]; then
  echo "FAIL: host discovery did not write JSON"
  exit 1
fi
if ! grep -Fq "HostDiscoveryJSON: $json_report" "$text_report"; then
  echo "FAIL: host discovery text did not report JSON path"
  exit 1
fi
if ! grep -Fq "Tailscale: enabled" "$text_report"; then
  echo "FAIL: host discovery text did not report Tailscale status"
  exit 1
fi
if ! grep -Fq "ARP: enabled" "$text_report"; then
  echo "FAIL: host discovery text did not report ARP status"
  exit 1
fi

schema_version="$(plutil -extract schemaVersion raw -o - "$json_report")"
if [[ "$schema_version" != "1" ]]; then
  echo "FAIL: unexpected schemaVersion $schema_version"
  exit 1
fi

host_count="$(plutil -extract sshConfig.hosts raw -o - "$json_report")"
if [[ "$host_count" != "4" ]]; then
  echo "FAIL: expected 4 ssh config hosts, got $host_count"
  plutil -p "$json_report"
  exit 1
fi

target_count="$(plutil -extract targets raw -o - "$json_report")"
if [[ "$target_count" != "2" ]]; then
  echo "FAIL: expected 2 targets, got $target_count"
  plutil -p "$json_report"
  exit 1
fi

tailscale_available="$(plutil -extract tailscale.statusAvailable raw -o - "$json_report")"
if [[ "$tailscale_available" != "true" ]]; then
  echo "FAIL: expected Tailscale status available, got $tailscale_available"
  plutil -p "$json_report"
  exit 1
fi

tailscale_node_count="$(plutil -extract tailscale.nodes raw -o - "$json_report")"
if [[ "$tailscale_node_count" != "2" ]]; then
  echo "FAIL: expected 2 Tailscale nodes, got $tailscale_node_count"
  plutil -p "$json_report"
  exit 1
fi

tailscale_first_node="$(plutil -extract tailscale.nodes.0.name raw -o - "$json_report")"
if [[ "$tailscale_first_node" != "s1" ]]; then
  echo "FAIL: unexpected first Tailscale node $tailscale_first_node"
  plutil -p "$json_report"
  exit 1
fi

arp_entry_count="$(plutil -extract arp.entries raw -o - "$json_report")"
if [[ "$arp_entry_count" != "2" ]]; then
  echo "FAIL: expected 2 ARP entries, got $arp_entry_count"
  plutil -p "$json_report"
  exit 1
fi

arp_first_host="$(plutil -extract arp.entries.0.host raw -o - "$json_report")"
if [[ "$arp_first_host" != "s1.local" ]]; then
  echo "FAIL: unexpected first ARP host $arp_first_host"
  plutil -p "$json_report"
  exit 1
fi

arp_second_ip="$(plutil -extract arp.entries.1.ip raw -o - "$json_report")"
if [[ "$arp_second_ip" != "192.168.0.41" ]]; then
  echo "FAIL: unexpected second ARP IP $arp_second_ip"
  plutil -p "$json_report"
  exit 1
fi

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" \
  PRESSTALK_TAILSCALE_PATH="$fake_tailscale" \
  PRESSTALK_ARP_PATH="$fake_arp" \
  PRESSTALK_FAKE_TAILSCALE_FAIL_STDOUT=1 \
  "$HELPER" \
  --no-bonjour \
  --json-output "$tailscale_failure_json_report" >/dev/null

tailscale_failure_available="$(plutil -extract tailscale.statusAvailable raw -o - "$tailscale_failure_json_report")"
if [[ "$tailscale_failure_available" != "false" ]]; then
  echo "FAIL: expected failed Tailscale status to be unavailable"
  plutil -p "$tailscale_failure_json_report"
  exit 1
fi

tailscale_failure_error="$(plutil -extract tailscale.error raw -o - "$tailscale_failure_json_report")"
if [[ "$tailscale_failure_error" != "The Tailscale CLI failed to start: Tailscale.CLIError error 1." ]]; then
  echo "FAIL: expected stdout Tailscale failure to be recorded, got $tailscale_failure_error"
  plutil -p "$tailscale_failure_json_report"
  exit 1
fi

mbp_host="$(plutil -extract targets.0.hostName raw -o - "$json_report")"
if [[ "$mbp_host" != "10.77.77.3" ]]; then
  echo "FAIL: unexpected mbp1-tb HostName $mbp_host"
  plutil -p "$json_report"
  exit 1
fi

invalid_probe="$(plutil -extract targets.1.sshProbe.success raw -o - "$json_report")"
if [[ "$invalid_probe" != "false" ]]; then
  echo "FAIL: non-probed target should report sshProbe.success=false"
  plutil -p "$json_report"
  exit 1
fi

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" PRESSTALK_TAILSCALE_PATH="$fake_tailscale" PRESSTALK_ARP_PATH="$fake_arp" "$HELPER" \
  --no-bonjour \
  --timeout 1 \
  --probe-ssh \
  --target invalid-host \
  --json-output "$probe_json_report" >/dev/null

invalid_probe="$(plutil -extract targets.0.sshProbe.success raw -o - "$probe_json_report")"
if [[ "$invalid_probe" != "false" ]]; then
  echo "FAIL: invalid host probe should not succeed"
  plutil -p "$probe_json_report"
  exit 1
fi

bonjour_enabled="$(plutil -extract bonjour.enabled raw -o - "$json_report")"
if [[ "$bonjour_enabled" != "false" ]]; then
  echo "FAIL: expected Bonjour disabled, got $bonjour_enabled"
  plutil -p "$json_report"
  exit 1
fi

echo "PASS host_discovery"
