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

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
"$BIN" --json > "$TMP"

# PATCH the gist file with the fresh snapshot (only computed numbers — no tokens).
/usr/bin/python3 - "$GID" "$TMP" <<'PY'
import json, sys, subprocess
gid, tmp = sys.argv[1], sys.argv[2]
body = json.dumps({"files": {"mg_snapshot.json": {"content": open(tmp).read()}}}).encode()
subprocess.run(["gh", "api", "-X", "PATCH", "gists/" + gid, "--input", "-"],
               input=body, check=True, stdout=subprocess.DEVNULL)
PY
