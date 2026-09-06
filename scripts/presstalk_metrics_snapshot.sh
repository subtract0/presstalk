#!/usr/bin/env bash
# Writes one dated JSON snapshot of every free counter we are allowed to read.
#
# Run it daily. Nearly every source here is cumulative with no history, or a
# short rolling window, so a number not captured today is gone: GitHub's
# download_count has no time series, Homebrew publishes 30/90/365-day windows
# only, and the repo traffic API forgets after fourteen days. Starting the
# snapshot before there is anything to see is the entire point.
#
# Nothing here touches a user. There is no telemetry in PressTalk and this does
# not add any: these are counters other people's servers already keep about
# public artefacts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PRESSTALK_METRICS_DIR:-$ROOT/metrics}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y-%m-%d)"
OUT="$OUT_DIR/$STAMP.json"

REPO="subtract0/presstalk"
# The tap repo is homebrew-presstalk, so Homebrew's key is user/tap/cask with the
# "homebrew-" prefix dropped: subtract0/presstalk/presstalk. Getting this wrong
# reads as a permanent zero, which is indistinguishable from nobody installing.
#
# Verified 2026-09-06: the unscoped feed carries 12,437 casks of which 5,086 are
# third-party taps in exactly this key shape (microsoft/git/microsoft-git,
# nikitabobko/tap/aerospace). We are simply absent, so found=false today means a
# genuine zero rather than a wrong key.
CASK_KEY="subtract0/presstalk/presstalk"

json_get() { curl -s -m 20 "$1" 2>/dev/null || echo '{}'; }

python3 - "$OUT" "$REPO" "$CASK_KEY" <<'PY'
import json, subprocess, sys, urllib.request, datetime

out_path, repo, cask_key = sys.argv[1], sys.argv[2], sys.argv[3]

def fetch(url, timeout=20):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.load(r)
    except Exception as e:
        return {"_error": str(e)}

def gh(path):
    try:
        out = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout) if out.returncode == 0 else {"_error": out.stderr.strip()[:200]}
    except Exception as e:
        return {"_error": str(e)}

snapshot = {
    "capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "notes": "Counters kept by third parties about public artefacts. PressTalk itself sends nothing.",
}

# Downloads per release asset. Cumulative, inflated by bots and mirrors, and
# GitHub exposes no history — hence the daily capture.
releases = fetch(f"https://api.github.com/repos/{repo}/releases")
if isinstance(releases, list):
    snapshot["releases"] = [
        {
            "tag": r.get("tag_name"),
            "prerelease": r.get("prerelease"),
            "assets": [{"name": a.get("name"), "downloads": a.get("download_count")}
                       for a in r.get("assets", [])],
        }
        for r in releases
    ]
else:
    snapshot["releases"] = releases

# Homebrew. The UNSCOPED endpoint is the one that contains third-party taps; the
# homebrew-cask-scoped path holds official casks only and would always miss us.
brew = fetch("https://formulae.brew.sh/api/analytics/cask-install/30d.json")
if isinstance(brew, dict) and "items" in brew:
    hit = [i for i in brew["items"] if i.get("cask") == cask_key]
    snapshot["homebrew30d"] = {
        "caskKey": cask_key,
        "found": bool(hit),
        "installs": hit[0].get("count") if hit else 0,
        "caveat": "install events, not people; undercounted by HOMEBREW_NO_ANALYTICS opt-out, "
                  "which is structurally higher for a privacy-minded audience. `brew upgrade` "
                  "emits nothing, so this counts first installs only.",
    }
else:
    snapshot["homebrew30d"] = brew

# Repo traffic: 14-day rolling window, top ten referrers only.
snapshot["traffic"] = {"views": gh(f"repos/{repo}/traffic/views"),
                       "referrers": gh(f"repos/{repo}/traffic/popular/referrers")}

# Any mention on Hacker News.
snapshot["hackerNews"] = fetch("https://hn.algolia.com/api/v1/search?query=presstalk&tags=story")

repo_meta = fetch(f"https://api.github.com/repos/{repo}")
snapshot["stars"] = repo_meta.get("stargazers_count") if isinstance(repo_meta, dict) else None

with open(out_path, "w") as f:
    json.dump(snapshot, f, indent=2)

# A short human line, because a JSON file nobody opens is not a measurement.
rel = snapshot.get("releases")
total = sum(a["downloads"] or 0 for r in rel for a in r["assets"]) if isinstance(rel, list) else 0
hb = snapshot.get("homebrew30d", {})
print(f"{snapshot['capturedAt'][:10]}  downloads={total}  "
      f"brew30d={hb.get('installs', 'n/a')}  stars={snapshot.get('stars')}  "
      f"hn={snapshot.get('hackerNews', {}).get('nbHits', 0)}")
PY

echo "wrote $OUT"
