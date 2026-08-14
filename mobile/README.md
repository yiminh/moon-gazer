# Moon Gazer — iPhone widget

Watch your Claude / Codex / OMLX status from your phone, anywhere — no VPN, no port
forwarding, no NAS. Your Mac publishes a small JSON snapshot to a **secret GitHub Gist**
every minute; a [Scriptable](https://scriptable.app) widget on the phone reads it.

```
Mac (MoonGazer --json)  →  every 60s  →  secret Gist  →  Scriptable widget (iPhone)
```

Only computed numbers are published (quota %, resets, GPU/MEM, tok/s, model name). **No
tokens or credentials ever leave your Mac.**

## Setup (once, on the Mac)

1. Build the app if you haven't: `./build-app.sh`
2. Install [Scriptable](https://apps.apple.com/app/scriptable/id1405459188) on the iPhone
   (free) and make sure iCloud Drive sync is on for it.
3. Copy `Moon Gazer.js` into Scriptable's iCloud folder
   (`~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/`) — done for you if
   you ran this from the repo on the Mac.
4. Run the setup script:

   ```bash
   ./mobile/setup-widget.sh
   ```

   It creates the secret gist, wires the widget to it, and installs a launchd job that
   republishes every 60s. It prints the gist URL and the raw URL it wired in.

5. On the iPhone: long-press the Home Screen → **+** → **Scriptable** → pick a size →
   drop it, then edit the widget and choose the **Moon Gazer** script.

## Sizes

- **Small** — Claude / Codex weekly % and OMLX GPU %, each with a bar.
- **Medium** — three columns: hero %, weekly bar, reset countdown, a session/MEM line, and
  the working/idle/quiet status.
- **Large** — the medium detail plus pace (`▲/▼ n% over/under pace`), the session bar,
  recent tasks, and OMLX's memory, model name, and PP/TG tok/s.

## Notes

- **Refresh cadence:** the Mac publishes every 60s, but iOS decides how often a widget
  actually refreshes (typically every few to ~30 minutes, more often when you look at it).
  Tap the widget to open Scriptable for an on-demand refresh.
- **The Mac must be awake** to publish (that's where the Claude/Codex tokens live — a NAS
  can't read them). If it sleeps, the widget shows the last snapshot and marks it stale.
- **Privacy:** the gist is *secret* (unguessable URL) and carries only numbers. Delete it
  anytime with `gh gist delete <id>` and `launchctl unload ~/Library/LaunchAgents/com.moongazer.publisher.plist`.
- **First run** may raise a Keychain prompt the first time the launchd job calls `gh`
  (it reads your GitHub token) — allow it.
- **Where it runs:** setup installs the binary and publisher into
  `~/Library/Application Support/MoonGazer/` and points the launchd job there. This avoids
  macOS TCC: a background launchd agent can't execute anything inside `~/Documents`,
  `~/Desktop`, or `~/Downloads` after a reboot (`Operation not permitted`), so the repo can
  live in those folders while the running copies sit in Application Support. Re-run
  `setup-widget.sh` after `./build-app.sh` to refresh the installed binary.
- Logs: `~/Library/Logs/moongazer-publisher.log`.

## Files

| File | Where it runs | What it does |
|---|---|---|
| `Moon Gazer.js` | iPhone (Scriptable) | The widget. `RAW_URL` is filled in by setup. |
| `setup-widget.sh` | Mac, once | Creates the gist, wires the widget, installs the launchd job. |
| `publish-gist.sh` | Mac, every 60s | Runs `MoonGazer --json` and PATCHes the gist. |
