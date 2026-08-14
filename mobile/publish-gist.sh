#!/bin/bash
# Moon Gazer publisher — installed to and run from ~/Library/Application Support/MoonGazer
# (NOT a TCC-protected folder like ~/Documents, so the launchd agent can execute it after
# a reboot). setup-widget.sh copies this here as `publish.sh` alongside the binary.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SUP="$HOME/Library/Application Support/MoonGazer"
CONFIG="$HOME/.config/moongazer/publisher.json"
[ -f "$CONFIG" ] || { echo "no publisher config — run setup-widget.sh first" >&2; exit 1; }
GID="$(/usr/bin/python3 -c "import json;print(json.load(open('$CONFIG'))['gistId'])")"
BIN="$SUP/MoonGazer"
[ -x "$BIN" ] || { echo "no binary at $BIN — re-run setup-widget.sh" >&2; exit 1; }

# Watchdog: a stale binary (built before --json) opens the GUI and never returns.
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
"$BIN" --json > "$TMP" 2>/dev/null & jpid=$!
w=0; while kill -0 "$jpid" 2>/dev/null; do sleep 1; w=$((w+1)); \
  [ $w -ge 45 ] && { kill -9 "$jpid" 2>/dev/null; echo "snapshot timed out — rebuild: ./build-app.sh" >&2; exit 1; }; done
wait "$jpid" 2>/dev/null || { echo "snapshot failed" >&2; exit 1; }
/usr/bin/python3 -c "import json;json.load(open('$TMP'))" 2>/dev/null \
  || { echo "snapshot not valid JSON — rebuild: ./build-app.sh" >&2; exit 1; }

/usr/bin/python3 - "$GID" "$TMP" <<'PY'
import json, sys, subprocess
gid, tmp = sys.argv[1], sys.argv[2]
body = json.dumps({"files": {"mg_snapshot.json": {"content": open(tmp).read()}}}).encode()
subprocess.run(["gh", "api", "-X", "PATCH", "gists/" + gid, "--input", "-"],
               input=body, check=True, stdout=subprocess.DEVNULL)
PY
