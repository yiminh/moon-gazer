# Moon Gazer — TRMNL Private Plugin

Show Claude / Codex / OMLX usage on an e-ink device via [TRMNL](https://usetrmnl.com) —
either a TRMNL device or the TRMNL app on your own e-reader (BYOD). TRMNL renders the
plugin **server-side** to 1-bit e-ink; your Mac just feeds it the numbers.

```
Mac  (Moon Gazer --json)  →  push-trmnl.py  →  TRMNL webhook  →  render  →  e-ink
```

Reset countdowns, pace, the elapsed-time tick and the task line are all pre-computed on
the Mac, so the Liquid markup stays a thin presentation layer over flat merge variables.

## Two layouts — pick one

| File | Look |
|---|---|
| `moongazer.liquid` | **Minimal** — big % per column, a labelled bar, pace, a second bar, a tail line. Airy, mirrors the Mac app. |
| `moongazer-framed.liquid` | **Framed** — TRMNL's own idiom: native columns with dithered vertical dividers, inverted plan chips, and a ruled stat table under each bar. |

Both read the **same** merge variables, so the same webhook push drives either one. Paste
whichever you prefer into the plugin's markup.

## Setup

### 1. Create the plugin on TRMNL
1. `usetrmnl.com` → **Plugins → Private Plugin → Add New** (needs a BYOD license or the
   developer add-on).
2. Strategy: **Webhook**. Save — TRMNL shows a webhook URL
   `https://usetrmnl.com/api/custom_plugins/<uuid>`. Copy it.
3. **Edit Markup** → paste one of the `.liquid` files into the **full** tab → Save. Paste
   `sample.json`'s object into the sample-data box to preview before the first real push.

### 2. Point the Mac at it
```bash
mkdir -p ~/.config/moongazer
echo '{"webhook":"https://usetrmnl.com/api/custom_plugins/<uuid>"}' > ~/.config/moongazer/trmnl.json
python3 push-trmnl.py            # one manual push (prints "posted … HTTP 200")
```
The webhook lives only in that local config (or a `TRMNL_WEBHOOK` env var) — never in the
markup or this repo. `push-trmnl.py --dry-run` prints the payload without posting.

### 3. Push on a schedule (launchd, every 5 min)
```bash
mkdir -p "$HOME/Library/Application Support/MoonGazer"
cp push-trmnl.py "$HOME/Library/Application Support/MoonGazer/push-trmnl.py"
# also copy the built `Moon Gazer.app` binary next to it, or set MOONGAZER_BIN
PLIST="$HOME/Library/LaunchAgents/com.moongazer.trmnl.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.moongazer.trmnl</string>
  <key>ProgramArguments</key>
    <array><string>/usr/bin/python3</string><string>$HOME/Library/Application Support/MoonGazer/push-trmnl.py</string></array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/moongazer-trmnl.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/moongazer-trmnl.log</string>
</dict></plist>
EOF
launchctl unload "$PLIST" 2>/dev/null; launchctl load "$PLIST"
```
Living under `~/Library/Application Support` (not `~/Documents`) keeps it clear of the
macOS TCC restrictions that block launchd agents from running out of the home doc folders.

### 4. Add it to your device
On TRMNL, add the plugin to a **playlist**; the device shows it in rotation. **Force
Refresh** on the plugin page requests an immediate render.

## Font (optional)

TRMNL's cloud renderer ships no monospace font, so the markup falls back to the renderer's
system mono (DejaVu Sans Mono). To pin an exact face across the cloud preview and the
device, embed one with `inject_font.py`:

```bash
base=https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5/files
curl -sSLo /tmp/jbm-400.woff2 "$base/jetbrains-mono-latin-400-normal.woff2"
curl -sSLo /tmp/jbm-700.woff2 "$base/jetbrains-mono-latin-700-normal.woff2"
python3 inject_font.py moongazer.liquid "JetBrains Mono" /tmp/jbm-400.woff2 /tmp/jbm-700.woff2
```
This writes the base64 `@font-face` at the `/* @@FONTFACE@@ */` anchor. [JetBrains Mono]
and [IBM Plex Mono] are both OFL-licensed. Re-running is safe (it replaces the old embed).

[JetBrains Mono]: https://github.com/JetBrains/JetBrainsMono
[IBM Plex Mono]: https://github.com/IBM/plex

## Notes
- The Mac must be awake to push (that's where the Claude/Codex tokens live).
- Webhook limits: **2 KB / payload, 12 posts per hour** on the free/BYOD tier (5 KB / 30
  on TRMNL+). A 5-minute cadence stays well within it — e-ink refreshes slowly anyway.
- TRMNL dedupes identical payloads; if a render looks stuck, use **Force Refresh**.
- Fields: Claude/Codex show weekly % + a secondary window (5h session, or a per-model
  quota like Codex's `5.3-Spark`) + pace + the active task; OMLX shows GPU %, memory,
  model and PP/TG throughput.
