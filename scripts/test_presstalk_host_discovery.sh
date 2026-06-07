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

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" "$HELPER" \
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

PRESSTALK_SSH_CONFIG_PATH="$ssh_config" "$HELPER" \
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
