#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.5}"
PUBLIC_NAME="${PUBLIC_NAME:-PressTalk}"
RELEASE_REPO="${RELEASE_REPO:-subtract0/presstalk-releases}"
TAP_REPO="${TAP_REPO:-subtract0/homebrew-presstalk}"
ARCH="${ARCH:-arm64}"
ASSET_NAME="${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.zip"
ASSET_PATH="$ROOT/dist/$ASSET_NAME"
SHA_PATH="$ROOT/dist/${PUBLIC_NAME}-${VERSION}-macos-${ARCH}.sha256"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-publish.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
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

require_cmd gh
require_cmd git

bash "$ROOT/scripts/package_presstalk_release.sh" "$VERSION" >/dev/null

if [[ ! -f "$ASSET_PATH" ]]; then
  echo "Missing packaged asset: $ASSET_PATH" >&2
  exit 1
fi

SHA256="$(awk '{print $1}' "$SHA_PATH")"
RELEASE_TAG="v$VERSION"
RELEASE_URL="https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
IS_PRERELEASE=0
if [[ "${PRESSTALK_RELEASE_PRERELEASE:-0}" == "1" || "$VERSION" == *-* ]]; then
  IS_PRERELEASE=1
fi

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
