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
fake_ssh_keyscan="$TEST_TMPDIR/ssh-keyscan"
test_host_key="$TEST_TMPDIR/test_host_key"
known_hosts="$TEST_TMPDIR/known_hosts"

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

ssh-keygen -q -t ed25519 -N '' -f "$test_host_key" >/dev/null
test_host_public_key="$(awk '{ print $2 }' "$test_host_key.pub")"
printf 's1.local ssh-ed25519 %s\n' "$test_host_public_key" >"$known_hosts"

cat >"$fake_ssh_keyscan" <<SH
#!/usr/bin/env bash
ip="\${@: -1}"
if [[ "\$ip" == "192.168.0.23" ]]; then
  echo "\$ip ssh-ed25519 $test_host_public_key"
  exit 0
fi
exit 1
SH
chmod +x "$fake_ssh_keyscan"

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" \
  PRESSTALK_KNOWN_HOSTS_PATH="$known_hosts" \
  PRESSTALK_TAILSCALE_PATH="$fake_tailscale" \
  PRESSTALK_ARP_PATH="$fake_arp" \
  PRESSTALK_SSH_KEYSCAN_PATH="$fake_ssh_keyscan" \
  "$HELPER" \
  --no-bonjour \
  --probe-arp-ssh \
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
if ! grep -Fq "ARP SSH keyscan: enabled" "$text_report"; then
  echo "FAIL: host discovery text did not report ARP SSH keyscan status"
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

known_hosts_exists="$(plutil -extract knownHosts.exists raw -o - "$json_report")"
if [[ "$known_hosts_exists" != "true" ]]; then
  echo "FAIL: expected known_hosts to exist, got $known_hosts_exists"
  plutil -p "$json_report"
  exit 1
fi

known_host_fingerprints="$(plutil -extract knownHosts.fingerprints raw -o - "$json_report")"
if [[ "$known_host_fingerprints" != "1" ]]; then
  echo "FAIL: expected one known_hosts fingerprint, got $known_host_fingerprints"
  plutil -p "$json_report"
  exit 1
fi

known_host_first_host="$(plutil -extract knownHosts.fingerprints.0.host raw -o - "$json_report")"
if [[ "$known_host_first_host" != "s1.local" ]]; then
  echo "FAIL: expected known_hosts fingerprint host s1.local, got $known_host_first_host"
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

arp_first_keyscan="$(plutil -extract arp.entries.0.sshKeyscan.success raw -o - "$json_report")"
if [[ "$arp_first_keyscan" != "true" ]]; then
  echo "FAIL: expected first ARP keyscan to succeed"
  plutil -p "$json_report"
  exit 1
fi

arp_first_fingerprints="$(plutil -extract arp.entries.0.sshKeyscan.fingerprints raw -o - "$json_report")"
if [[ "$arp_first_fingerprints" != "1" ]]; then
  echo "FAIL: expected one first ARP keyscan fingerprint, got $arp_first_fingerprints"
  plutil -p "$json_report"
  exit 1
fi

arp_first_key_type="$(plutil -extract arp.entries.0.sshKeyscan.fingerprints.0.keyType raw -o - "$json_report")"
if [[ "$arp_first_key_type" != "ED25519" ]]; then
  echo "FAIL: expected ED25519 first ARP key type, got $arp_first_key_type"
  plutil -p "$json_report"
  exit 1
fi

arp_first_known_matches="$(plutil -extract arp.entries.0.sshKeyscan.fingerprints.0.knownHostMatches raw -o - "$json_report")"
if [[ "$arp_first_known_matches" != "1" ]]; then
  echo "FAIL: expected one known_hosts match for first ARP fingerprint, got $arp_first_known_matches"
  plutil -p "$json_report"
  exit 1
fi

arp_first_known_match_host="$(plutil -extract arp.entries.0.sshKeyscan.fingerprints.0.knownHostMatches.0.host raw -o - "$json_report")"
if [[ "$arp_first_known_match_host" != "s1.local" ]]; then
  echo "FAIL: expected first ARP known_hosts match host s1.local, got $arp_first_known_match_host"
  plutil -p "$json_report"
  exit 1
fi

arp_second_keyscan="$(plutil -extract arp.entries.1.sshKeyscan.success raw -o - "$json_report")"
if [[ "$arp_second_keyscan" != "false" ]]; then
  echo "FAIL: expected second ARP keyscan to fail"
  plutil -p "$json_report"
  exit 1
fi

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" \
  PRESSTALK_KNOWN_HOSTS_PATH="$known_hosts" \
  PRESSTALK_TAILSCALE_PATH="$fake_tailscale" \
  PRESSTALK_ARP_PATH="$fake_arp" \
  PRESSTALK_SSH_KEYSCAN_PATH="$fake_ssh_keyscan" \
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

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" PRESSTALK_KNOWN_HOSTS_PATH="$known_hosts" PRESSTALK_TAILSCALE_PATH="$fake_tailscale" PRESSTALK_ARP_PATH="$fake_arp" "$HELPER" \
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
