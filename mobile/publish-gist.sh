#!/bin/bash
# Moon Gazer — publish a fresh snapshot to the secret gist.
# Run every minute by the launchd agent that setup-widget.sh installs.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$HOME/.config/moongazer/publisher.json"
[ -f "$CONFIG" ] || { echo "no publisher config — run mobile/setup-widget.sh first" >&2; exit 1; }

GID="$(/usr/bin/python3 -c "import json;print(json.load(open('$CONFIG'))['gistId'])")"

BIN="$ROOT/Moon Gazer.app/Contents/MacOS/MoonGazer"
[ -x "$BIN" ] || BIN="$ROOT/.build/release/MoonGazer"
[ -x "$BIN" ] || { echo "MoonGazer binary not found — run ./build-app.sh" >&2; exit 1; }

# Run --json with a watchdog: a stale binary (built before --json existed) launches
# the GUI and never returns, so kill it rather than hang the launchd job forever.
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
"$BIN" --json > "$TMP" 2>/dev/null & jpid=$!
w=0; while kill -0 "$jpid" 2>/dev/null; do sleep 1; w=$((w+1)); \
  [ $w -ge 45 ] && { kill -9 "$jpid" 2>/dev/null; echo "snapshot timed out — rebuild: ./build-app.sh" >&2; exit 1; }; done
wait "$jpid" 2>/dev/null || { echo "snapshot failed" >&2; exit 1; }
/usr/bin/python3 -c "import json;json.load(open('$TMP'))" 2>/dev/null \
  || { echo "snapshot not valid JSON — rebuild: ./build-app.sh" >&2; exit 1; }

# PATCH the gist file with the fresh snapshot (only computed numbers — no tokens).
/usr/bin/python3 - "$GID" "$TMP" <<'PY'
import json, sys, subprocess
gid, tmp = sys.argv[1], sys.argv[2]
body = json.dumps({"files": {"mg_snapshot.json": {"content": open(tmp).read()}}}).encode()
subprocess.run(["gh", "api", "-X", "PATCH", "gists/" + gid, "--input", "-"],
               input=body, check=True, stdout=subprocess.DEVNULL)
PY
