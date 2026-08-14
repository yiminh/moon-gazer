#!/bin/bash
# Moon Gazer — one-time setup for the iPhone widget.
#
# Creates a secret GitHub Gist that holds a live JSON snapshot, wires the
# Scriptable widget to it, and installs a launchd job that republishes a fresh
# snapshot every 60s. The snapshot contains only computed numbers — never tokens.
#
# Requires: the built app (./build-app.sh) and GitHub CLI (`gh auth login`).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/Moon Gazer.app/Contents/MacOS/MoonGazer"
[ -x "$BIN" ] || BIN="$ROOT/.build/release/MoonGazer"
[ -x "$BIN" ] || { echo "Build the app first:  ./build-app.sh"; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI required:  brew install gh && gh auth login"; exit 1; }

echo "→ Generating the first snapshot…"
WORK="$(mktemp -d)"; SNAP="$WORK/mg_snapshot.json"
# Watchdog: a stale binary (built before --json existed) opens the GUI and never
# returns. Kill it and tell the user to rebuild rather than hang here forever.
"$BIN" --json > "$SNAP" 2>/dev/null & jpid=$!
w=0; while kill -0 "$jpid" 2>/dev/null; do sleep 1; w=$((w+1)); \
  [ $w -ge 45 ] && { kill -9 "$jpid" 2>/dev/null; echo "!! Snapshot timed out — your app is stale. Rebuild:  ./build-app.sh  then re-run this."; exit 1; }; done
wait "$jpid" 2>/dev/null || { echo "!! Snapshot failed. Rebuild:  ./build-app.sh"; exit 1; }
/usr/bin/python3 -c "import json;json.load(open('$SNAP'))" 2>/dev/null \
  || { echo "!! Snapshot isn't valid JSON — your app is stale. Rebuild:  ./build-app.sh  then re-run this."; exit 1; }

echo "→ Creating a secret gist…"
URL="$(gh gist create "$SNAP" --desc 'Moon Gazer live snapshot (private widget feed)')"
GID="$(basename "$URL")"
LOGIN="$(gh api user --jq .login)"
RAW="https://gist.githubusercontent.com/$LOGIN/$GID/raw/mg_snapshot.json"

mkdir -p "$HOME/.config/moongazer"
printf '{"gistId":"%s"}\n' "$GID" > "$HOME/.config/moongazer/publisher.json"

# Install the binary + publisher into ~/Library/Application Support (NOT a TCC-protected
# folder like ~/Documents), so the launchd agent can run them after a reboot.
SUP="$HOME/Library/Application Support/MoonGazer"
mkdir -p "$SUP"
cp "$BIN" "$SUP/MoonGazer"
cp "$ROOT/mobile/publish-gist.sh" "$SUP/publish.sh"
chmod +x "$SUP/publish.sh"
echo "→ Installed publisher to $SUP"

# Wire the Scriptable widget's URL (its iCloud copy on this Mac).
SCRIPT="$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/Moon Gazer.js"
if [ -f "$SCRIPT" ]; then
  /usr/bin/sed -i '' "s#__RAW_URL__#$RAW#g" "$SCRIPT"
  echo "→ Wired the widget script to the gist"
else
  echo "!! Scriptable file not found. Paste this as RAW_URL in the widget script:"
  echo "   $RAW"
fi

# Install + load the launchd publisher (every 60s).
PLIST="$HOME/Library/LaunchAgents/com.moongazer.publisher.plist"
LOG="$HOME/Library/Logs/moongazer-publisher.log"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.moongazer.publisher</string>
  <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$SUP/publish.sh</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

cat <<EOF

✅ Done.
   Gist:     $URL
   Raw URL:  $RAW
   Publisher runs every 60s  (log: $LOG)

On your iPhone: long-press the Home Screen → add a Scriptable widget → edit it →
choose the "Moon Gazer" script. Small, Medium and Large are all supported.

To stop later:  launchctl unload "$PLIST"
EOF
