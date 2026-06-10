#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.5}"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
RELEASE_REPO="${RELEASE_REPO:-subtract0/presstalk-releases}"
TAP_REPO="${TAP_REPO:-subtract0/homebrew-presstalk}"
ARCH="${ARCH:-arm64}"
DIST_DIR="${PRESSTALK_DIST_DIR:-$ROOT/dist}"
ASSET_NAME="${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.zip"
ASSET_PATH="$DIST_DIR/$ASSET_NAME"
SHA_PATH="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.sha256"
ARTIFACT_AUDIT_SCRIPT="$ROOT/scripts/presstalk_release_artifact_audit.sh"
ARTIFACT_AUDIT_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}-artifact-audit.json"
READINESS_PREFLIGHT_SCRIPT="$ROOT/scripts/presstalk_release_readiness_preflight.sh"
PROOF_GATE_JSON="${PRESSTALK_RELEASE_PROOF_GATE_JSON:-${PRESSTALK_PROOF_GATE_JSON:-}}"
REQUIRED_PROOF_TARGETS="${PRESSTALK_REQUIRED_PROOF_TARGETS:-}"
RELEASE_READINESS_JSON="$DIST_DIR/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}-release-readiness.json"
REQUIRE_STREAMING_RELEASE="${PRESSTALK_REQUIRE_STREAMING_RELEASE:-}"
EXPECTED_ASR_MODE="${PRESSTALK_EXPECTED_ASR_MODE:-parakeet_v3_ane_final_pass}"
STREAMING_BENCH_QUALITY_JSON="${PRESSTALK_STREAMING_BENCH_QUALITY_JSON:-}"
REQUIRE_STREAMING_BENCH_QUALITY="${PRESSTALK_REQUIRE_STREAMING_BENCH_QUALITY:-}"
HYBRID_STREAMING_QUALITY_JSON="${PRESSTALK_HYBRID_STREAMING_QUALITY_JSON:-}"
REQUIRE_HYBRID_STREAMING_QUALITY="${PRESSTALK_REQUIRE_HYBRID_STREAMING_QUALITY:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-publish.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_repo() {
  local repo="$1"
  if gh repo view "$repo" >/dev/null 2>&1; then
    return
  fi
  gh repo create "$repo" --public --confirm
}

configure_git_identity() {
  local repo_dir="$1"
  git -C "$repo_dir" config user.name "${PRESSTALK_RELEASE_GIT_NAME:-PressTalk Release Bot}"
  git -C "$repo_dir" config user.email "${PRESSTALK_RELEASE_GIT_EMAIL:-presstalk-release-bot@users.noreply.github.com}"
}

IS_PRERELEASE=0
if [[ "${PRESSTALK_RELEASE_PRERELEASE:-0}" == "1" || "$VERSION" == *-* ]]; then
  IS_PRERELEASE=1
fi

if [[ "$IS_PRERELEASE" == "0" ]]; then
  if [[ -z "$REQUIRE_STREAMING_RELEASE" ]]; then
    REQUIRE_STREAMING_RELEASE=1
  fi
  if truthy "$REQUIRE_STREAMING_RELEASE" && [[ -z "${PRESSTALK_EXPECTED_ASR_MODE:-}" ]]; then
    EXPECTED_ASR_MODE="any"
  fi
  if [[ -z "$REQUIRE_STREAMING_BENCH_QUALITY" && -z "$REQUIRE_HYBRID_STREAMING_QUALITY" ]]; then
    if [[ -n "$HYBRID_STREAMING_QUALITY_JSON" && -z "$STREAMING_BENCH_QUALITY_JSON" ]]; then
      REQUIRE_HYBRID_STREAMING_QUALITY=1
    else
      REQUIRE_STREAMING_BENCH_QUALITY=1
    fi
  fi
  if [[ -z "$REQUIRED_PROOF_TARGETS" ]]; then
    REQUIRED_PROOF_TARGETS="studio1,mbp1"
  fi
  if ! truthy "${PRESSTALK_DISTRIBUTION_SIGNING:-0}"; then
    cat >&2 <<'EOF'
Refusing to publish a stable PressTalk Homebrew release without production
distribution signing. Set PRESSTALK_DISTRIBUTION_SIGNING=1 plus a Developer ID
identity, or publish a hyphenated prerelease version such as 0.1.6-test5.
EOF
    exit 2
  fi
  if ! truthy "${PRESSTALK_NOTARIZE:-0}"; then
    cat >&2 <<'EOF'
Refusing to publish a stable PressTalk Homebrew release without notarization.
Set PRESSTALK_NOTARIZE=1 with notarytool credentials, or publish a hyphenated
prerelease version such as 0.1.6-test5.
EOF
    exit 2
  fi
  if [[ -z "$PROOF_GATE_JSON" ]]; then
    cat >&2 <<'EOF'
Refusing to publish a stable PressTalk Homebrew release without machine proof.
Set PRESSTALK_RELEASE_PROOF_GATE_JSON to a JSON file produced by
presstalk_release_proof_gate.sh after proving the required target Macs.
EOF
    exit 2
  fi
  if [[ ! -f "$PROOF_GATE_JSON" ]]; then
    echo "Missing release proof gate JSON: $PROOF_GATE_JSON" >&2
    exit 2
  fi
  if truthy "$REQUIRE_STREAMING_BENCH_QUALITY"; then
    if [[ -z "$STREAMING_BENCH_QUALITY_JSON" ]]; then
      cat >&2 <<'EOF'
Refusing to publish a stable PressTalk streaming release without streaming ASR
quality evidence. Set PRESSTALK_STREAMING_BENCH_QUALITY_JSON to JSON produced
by presstalk_streaming_bench_quality_gate.sh after benchmarking the selected
streaming backend against a reference transcript, or set
PRESSTALK_HYBRID_STREAMING_QUALITY_JSON plus
PRESSTALK_REQUIRE_HYBRID_STREAMING_QUALITY=1 for the hybrid streaming HUD plus
finalizer paste architecture.
EOF
      exit 2
    fi
    if [[ ! -f "$STREAMING_BENCH_QUALITY_JSON" ]]; then
      echo "Missing streaming bench quality JSON: $STREAMING_BENCH_QUALITY_JSON" >&2
      exit 2
    fi
  fi
  if truthy "$REQUIRE_HYBRID_STREAMING_QUALITY"; then
    if [[ -z "$HYBRID_STREAMING_QUALITY_JSON" ]]; then
      cat >&2 <<'EOF'
Refusing to publish a stable PressTalk streaming release without hybrid
streaming quality evidence. Set PRESSTALK_HYBRID_STREAMING_QUALITY_JSON to JSON
produced by presstalk_hybrid_streaming_quality_gate.sh after benchmarking the
live partial backend and the final paste backend against reference audio.
EOF
      exit 2
    fi
    if [[ ! -f "$HYBRID_STREAMING_QUALITY_JSON" ]]; then
      echo "Missing hybrid streaming quality JSON: $HYBRID_STREAMING_QUALITY_JSON" >&2
      exit 2
    fi
  fi
fi

require_cmd git
if ! truthy "${PRESSTALK_PUBLISH_DRY_RUN:-0}"; then
  require_cmd gh
fi

ARCH="$ARCH" \
PUBLIC_NAME="$PUBLIC_NAME" \
PRESSTALK_DIST_DIR="$DIST_DIR" \
  bash "$ROOT/scripts/package_presstalk_release.sh" "$VERSION" >/dev/null

if [[ ! -f "$ASSET_PATH" ]]; then
  echo "Missing packaged asset: $ASSET_PATH" >&2
  exit 1
fi

audit_args=(
  --zip "$ASSET_PATH"
  --expected-bundle-id "${PRESSTALK_EXPECTED_BUNDLE_ID:-com.am.presstalk}"
  --expected-version "$VERSION"
  --json-output "$ARTIFACT_AUDIT_JSON"
)
if [[ "$IS_PRERELEASE" == "0" ]] || truthy "${PRESSTALK_REQUIRE_DISTRIBUTION_AUDIT:-0}"; then
  audit_args+=(--require-distribution --require-notarized)
fi
"$ARTIFACT_AUDIT_SCRIPT" "${audit_args[@]}"

if [[ "$IS_PRERELEASE" == "0" ]] || truthy "${PRESSTALK_REQUIRE_RELEASE_READINESS:-0}"; then
  if [[ -z "$PROOF_GATE_JSON" ]]; then
    echo "PRESSTALK_REQUIRE_RELEASE_READINESS=1 requires PRESSTALK_RELEASE_PROOF_GATE_JSON." >&2
    exit 2
  fi
  if [[ ! -f "$PROOF_GATE_JSON" ]]; then
    echo "Missing release proof gate JSON: $PROOF_GATE_JSON" >&2
    exit 2
  fi
  readiness_args=(
    --artifact-audit "$ARTIFACT_AUDIT_JSON"
    --proof-gate "$PROOF_GATE_JSON"
    --expected-asr-mode "$EXPECTED_ASR_MODE"
    --json-output "$RELEASE_READINESS_JSON"
  )
  if [[ -n "$REQUIRED_PROOF_TARGETS" ]]; then
    IFS=',' read -r -a parsed_required_targets <<<"$REQUIRED_PROOF_TARGETS"
    for parsed_required_target in "${parsed_required_targets[@]}"; do
      parsed_required_target="${parsed_required_target#"${parsed_required_target%%[![:space:]]*}"}"
      parsed_required_target="${parsed_required_target%"${parsed_required_target##*[![:space:]]}"}"
      [[ -z "$parsed_required_target" ]] && continue
      readiness_args+=(--require-proof-target "$parsed_required_target")
    done
  fi
  if [[ "$IS_PRERELEASE" == "0" ]]; then
    readiness_args+=(--require-production)
  fi
  if truthy "$REQUIRE_STREAMING_RELEASE"; then
    readiness_args+=(--require-streaming)
  fi
  if [[ -n "$STREAMING_BENCH_QUALITY_JSON" ]]; then
    readiness_args+=(--streaming-bench-quality "$STREAMING_BENCH_QUALITY_JSON")
  fi
  if truthy "$REQUIRE_STREAMING_BENCH_QUALITY"; then
    readiness_args+=(--require-streaming-bench-quality)
  fi
  if [[ -n "$HYBRID_STREAMING_QUALITY_JSON" ]]; then
    readiness_args+=(--hybrid-streaming-quality "$HYBRID_STREAMING_QUALITY_JSON")
  fi
  if truthy "$REQUIRE_HYBRID_STREAMING_QUALITY"; then
    readiness_args+=(--require-hybrid-streaming-quality)
  fi
  "$READINESS_PREFLIGHT_SCRIPT" "${readiness_args[@]}"
fi

if truthy "${PRESSTALK_PUBLISH_DRY_RUN:-0}"; then
  echo "PressTalk publish dry run complete"
  echo "Asset: $ASSET_PATH"
  echo "AuditJSON: $ARTIFACT_AUDIT_JSON"
  if [[ -f "$RELEASE_READINESS_JSON" ]]; then
    echo "ReadinessJSON: $RELEASE_READINESS_JSON"
  fi
  exit 0
fi

SHA256="$(awk '{print $1}' "$SHA_PATH")"
RELEASE_TAG="v$VERSION"
RELEASE_URL="https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

ensure_repo "$RELEASE_REPO"
ensure_repo "$TAP_REPO"

git -C "$TMP_DIR" clone "https://github.com/${RELEASE_REPO}.git" presstalk-releases >/dev/null 2>&1 || true
if [[ ! -d "$TMP_DIR/presstalk-releases/.git" ]]; then
  gh repo clone "$RELEASE_REPO" "$TMP_DIR/presstalk-releases" >/dev/null
fi
configure_git_identity "$TMP_DIR/presstalk-releases"

cat >"$TMP_DIR/presstalk-releases/README.md" <<EOF
# PressTalk Releases

Public binary releases for PressTalk.

Install with Homebrew:

\`\`\`bash
brew tap subtract0/presstalk
brew install --cask presstalk
\`\`\`

The installed app bundle is \`PressTalk.app\`.
EOF

pushd "$TMP_DIR/presstalk-releases" >/dev/null
git add README.md
if ! git diff --cached --quiet; then
  git commit -m "Update release docs for ${RELEASE_TAG}" >/dev/null
  git push origin HEAD >/dev/null
fi
popd >/dev/null

if gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$ASSET_PATH" --repo "$RELEASE_REPO" --clobber >/dev/null
  if [[ "$IS_PRERELEASE" == "1" ]]; then
    gh release edit "$RELEASE_TAG" --repo "$RELEASE_REPO" --prerelease >/dev/null
  fi
else
  release_args=(
    release create "$RELEASE_TAG" "$ASSET_PATH"
    --repo "$RELEASE_REPO"
    --title "PressTalk ${VERSION}"
    --notes "PressTalk ${VERSION} for Apple Silicon macOS."
  )
  if [[ "$IS_PRERELEASE" == "1" ]]; then
    release_args+=(--prerelease)
  fi
  gh "${release_args[@]}" >/dev/null
fi

gh repo clone "$TAP_REPO" "$TMP_DIR/homebrew-presstalk" >/dev/null 2>&1 || true
mkdir -p "$TMP_DIR/homebrew-presstalk/Casks"
configure_git_identity "$TMP_DIR/homebrew-presstalk"

cat >"$TMP_DIR/homebrew-presstalk/README.md" <<EOF
# homebrew-presstalk

\`\`\`bash
brew tap subtract0/presstalk
brew install --cask presstalk
\`\`\`
EOF

cat >"$TMP_DIR/homebrew-presstalk/Casks/presstalk.rb" <<EOF
cask "presstalk" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${RELEASE_URL}"
  name "PressTalk"
  desc "Hold-to-talk local dictation for Apple Silicon"
  homepage "https://github.com/${RELEASE_REPO}"

  depends_on macos: ">= :sonoma"

  app "PressTalk.app"

  postflight do |c|
    c.system_command "/bin/bash",
                     args: ["#{appdir}/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"],
                     must_succeed: false
  end

  caveats <<~EOS
    PressTalk defaults to the native Fn / Globe push-to-talk trigger.
    After install, approve the macOS permission prompts from PressTalk.
    If you need to rerun setup manually, use:
      /bin/bash /Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh
    If you choose the optional F5 trigger and need the Karabiner bridge, use:
      /bin/bash /Applications/PressTalk.app/Contents/Resources/presstalk-karabiner-fallback.sh --enable
  EOS
end
EOF

pushd "$TMP_DIR/homebrew-presstalk" >/dev/null
git add README.md Casks/presstalk.rb
if ! git diff --cached --quiet; then
  git commit -m "Publish PressTalk ${VERSION}" >/dev/null
  git push origin HEAD >/dev/null
fi
popd >/dev/null

echo "Published PressTalk ${VERSION}"
echo "Homebrew: brew tap subtract0/presstalk && brew install --cask presstalk"
