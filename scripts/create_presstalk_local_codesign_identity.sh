#!/usr/bin/env bash
set -euo pipefail

IDENTITY="${PRESSTALK_LOCAL_CODESIGN_IDENTITY:-PressTalk Local Development Code Signing}"
KEYCHAIN="${PRESSTALK_LOCAL_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/presstalk-local-dev.keychain-db}"
STATE_DIR="$HOME/Library/Application Support/PressTalk"
PASSWORD_FILE="$STATE_DIR/local-codesign-keychain-password"
DAYS="${PRESSTALK_LOCAL_CODESIGN_DAYS:-3650}"
TRUST_TIMEOUT_SECONDS="${PRESSTALK_LOCAL_CODESIGN_TRUST_TIMEOUT_SECONDS:-10}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "Missing required command: openssl" >&2
  exit 1
fi

mkdir -p "$(dirname "$KEYCHAIN")" "$STATE_DIR"
chmod 700 "$STATE_DIR"

if [[ -f "$PASSWORD_FILE" ]]; then
  KEYCHAIN_PASSWORD="$(cat "$PASSWORD_FILE")"
else
  umask 077
  KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
  printf '%s\n' "$KEYCHAIN_PASSWORD" >"$PASSWORD_FILE"
fi

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null

add_keychain_to_search_list() {
  local existing
  local keychains=("$KEYCHAIN")
  existing="$(security list-keychains -d user | sed 's/^[[:space:]]*"//;s/"$//')"
  if printf '%s\n' "$existing" | grep -Fx "$KEYCHAIN" >/dev/null; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    keychains+=("$line")
  done <<<"$existing"
  security list-keychains -d user -s "${keychains[@]}" >/dev/null
}

find_identity_hash() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
    awk -v name="$IDENTITY" '$0 ~ name { print $2; exit }'
}

trust_certificate_for_codesigning() {
  security add-trusted-cert -k "$KEYCHAIN" -p codeSign "$1" >/dev/null 2>&1 &
  local trust_pid=$!
  local waited=0
  while kill -0 "$trust_pid" >/dev/null 2>&1; do
    if (( waited >= TRUST_TIMEOUT_SECONDS )); then
      kill "$trust_pid" >/dev/null 2>&1 || true
      sleep 0.2
      kill -KILL "$trust_pid" >/dev/null 2>&1 || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$trust_pid"
}

IDENTITY_HASH="$(find_identity_hash)"

if [[ -z "$IDENTITY_HASH" ]]; then
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-codesign.XXXXXX")"
  cleanup() {
    rm -rf "$TMP_DIR"
  }
  trap cleanup EXIT

  P12_PASSWORD="$(openssl rand -hex 24)"
  OPENSSL_CONFIG="$TMP_DIR/openssl.cnf"
  CERT_PEM="$TMP_DIR/cert.pem"
  KEY_PEM="$TMP_DIR/key.pem"
  P12="$TMP_DIR/identity.p12"

  cat >"$OPENSSL_CONFIG" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = $IDENTITY

[ v3_codesign ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$KEY_PEM" \
    -x509 \
    -days "$DAYS" \
    -out "$CERT_PEM" \
    -config "$OPENSSL_CONFIG" >/dev/null 2>&1

  # macOS security(1) can reject OpenSSL 3's newer PKCS#12 defaults.
  openssl pkcs12 \
    -export \
    -inkey "$KEY_PEM" \
    -in "$CERT_PEM" \
    -out "$P12" \
    -name "$IDENTITY" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

  security import "$P12" \
    -f pkcs12 \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

  if ! trust_certificate_for_codesigning "$CERT_PEM"; then
    echo "Warning: timed out while adding code-signing trust for $IDENTITY." >&2
    echo "If the identity is not valid below, open Keychain Access and trust the certificate for code signing." >&2
  fi
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

  IDENTITY_HASH="$(find_identity_hash)"
fi

if [[ -z "$IDENTITY_HASH" ]]; then
  echo "Could not create a valid code-signing identity in $KEYCHAIN" >&2
  exit 1
fi

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

add_keychain_to_search_list

echo "PressTalk local code-signing identity is ready."
echo "Identity: $IDENTITY"
echo "Hash: $IDENTITY_HASH"
echo "Keychain: $KEYCHAIN"
echo
echo "Build with:"
echo "  PRESSTALK_CODESIGN_IDENTITY=$IDENTITY_HASH bash scripts/build_jarvistap.sh"
