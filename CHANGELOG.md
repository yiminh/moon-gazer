# Changelog

All notable changes to Moon Gazer are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) —
**MAJOR.MINOR.PATCH**: MAJOR for incompatible changes, MINOR for backward-compatible
features, PATCH for backward-compatible fixes.

## [1.5.4] — 2026-08-13

### Fixed
- **Widget feed silently went stale (~19h).** The launchd publisher ran from a copy in
  `~/Documents`, a macOS TCC-protected folder; after a reboot the background agent lost
  permission to execute it (`Operation not permitted`, exit 126) and stopped updating the
  gist. Setup now installs the binary and publisher into
  `~/Library/Application Support/MoonGazer/` and points the launchd job there, so it keeps
  running across reboots regardless of where the repo lives.

## [1.5.3] — 2026-08-13

### Changed
- **Widget alignment pass.** The big-number "%" is lifted to the number's baseline (no
  longer dropped below it). The status dot is drawn as a small circle placed one space
  after "OMLX" and vertically centred. Medium: the reset time and OMLX's `MEM%·PP·TG`
  line share one size, and the middle-dot separators lost their spaces so nothing clips.
  Large: OMLX is more compact (tighter row spacing, smaller model text) so the Claude and
  Codex bands get more room.

## [1.5.2] — 2026-08-13

### Changed
- **More widget layout fixes.** The big number's "%" now sits on the baseline (both
  sizes). Medium: the plan (Max/Plus) sits inline after the name; OMLX drops "MLX" and
  puts the online dot on the right; the reset line shows just the duration; OMLX's second
  line is `MEM% · PP · TG`, left-aligned with middle dots. Large: plan inline after the
  name, OMLX regains its "%" and drops "MLX", and metric groups are re-spaced so each
  label hugs its own bar with clear gaps between groups.

## [1.5.1] — 2026-08-13

### Changed
- **Widget polish from real-device feedback.** Accents now match the app's configured
  colours (coral / mint / aqua). Medium: Claude/Codex show a single weekly bar with the
  reset time as text below (no 7d/5h tags, no session bar, no tasks); OMLX drops the
  GPU/MEM labels and shows `MEM% · PP · TG` spread across one line. Large: bar labels get
  a colon and every percentage is right-aligned at one size (Weekly/Session/GPU/MEM),
  PP/TG shows as `844/61` aligned above MEM's `47/96G`, and the model name gets two lines.

## [1.5.0] — 2026-08-13

### Changed
- **Redesigned the iPhone widget** around each size instead of shrinking the desktop
  layout. Progress bars are now drawn crisply (DrawContext) with a time-pace tick — the
  old nested-stack bars collapsed to a dot at low percentages. Brighter accents (orange
  #FF9F0A / green #30D158 / blue #0A84FF). **Medium**: bigger % numbers, two labelled
  bars with ticks, no reset text or tasks; OMLX shows an "MLX" tag and GPU/MEM. **Large**:
  three stacked full-width bands (Claude / Codex / OMLX) with weekly + session bars, reset
  countdowns, and OMLX's model + PP/TG.

## [1.4.2] — 2026-08-13

### Fixed
- **Widget setup could hang forever** if the built app was stale (built before the
  `--json` snapshot mode existed): the old binary opened the GUI and never returned.
  `setup-widget.sh` and `publish-gist.sh` now run the snapshot under a watchdog and
  validate the JSON, failing fast with a "rebuild: ./build-app.sh" message instead.

## [1.4.1] — 2026-08-13

### Fixed
- **iPhone widget crashed on load** with `Font.monospacedSystemFont is not a function` on
  Scriptable versions without that API. The widget now uses `new Font("Menlo", size)` for
  its monospaced look.

## [1.4.0] — 2026-08-13

### Added
- **iPhone widget (Scriptable).** A `--json` snapshot mode plus a small pipeline
  (`mobile/`): the Mac publishes a compact JSON snapshot to a secret GitHub Gist every
  60s (launchd), and a Scriptable widget reads it on the phone — works anywhere, no VPN or
  port forwarding. Small / Medium / Large layouts; medium and up keep reset countdowns,
  session bars, pace, tasks, and OMLX GPU/MEM/model/tok-s. Only computed numbers are
  published; no tokens ever leave the Mac.

## [1.3.1] — 2026-08-10

### Fixed
- **OMLX pane now shows the model actually in use.** The agent read the model name from
  the server's list of *available* models and always returned the first one, so the name
  never changed when you switched models. It now reads the *currently loaded / serving*
  model from the oMLX admin stats (`/admin/api/stats` → `active_models`), preferring the
  model that is generating or has in-flight requests. Updates within one poll (~4s). (#1)

## [1.3.0] — 2026-08-10

### Added
- **Settings window (⌘,).** A sidebar preferences window; everything persists to
  `~/.config/moongazer/settings.json`.
  - **Templates** — five looks to start from: Terminal, Material, Cupertino, Editorial,
    Luxe. Each is a bundle of fonts, weights, accents, alert colours, and light/dark
    surfaces; pick one, then override anything.
  - **Typography** — separate typefaces for body text and the big numbers, each with a
    bold toggle. Eight system fonts (SF Mono, Menlo, New York, Charter, SF Pro, SF Rounded,
    Helvetica Neue, Avenir Next); nothing bundled.
  - **Colors** — per-pane accent, warning/danger colours and their thresholds, three bar
    modes (alert colours grey out in accent-only), 32 curated presets (~16 for dark, ~16
    for light, brand colours included), plus hex entry and a native colour wheel.
  - **Appearance** — Light, Dark, or Follow System (live).
  - **Layout** — choose which columns show and their left-to-right order.

### Changed
- The theme is now a dynamic layer over the settings; the dashboard restyles live.

## [1.2.0] — 2026-08-10

### Added
- **OMLX tokens/sec.** When the watched host runs [oMLX](https://github.com/jundot/omlx),
  the agent reports prompt-processing (PP) and text-generation (TG) throughput, shown in
  the OMLX pane.
- **Selectable bar-colour behavior** and an **optional display label** for the OMLX host
  (`omlxLabel`) to override a munged system hostname.

## [1.1.0] — 2026-08-10

### Added
- **OMLX pane (optional third column).** Watches another machine on the LAN via a tiny,
  dependency-free agent (`agent/omlx-agent.py`): GPU utilisation, memory, and the loaded
  model, shown with an ONLINE/OFFLINE indicator. Hidden until configured.

## [1.0.0] — 2026-08-09

### Added
- Initial release. A dual-pane macOS dashboard for **Claude** and **Codex** usage:
  weekly/session quota, reset countdowns, a time-pace marker, and live/finished CLI task
  status. Zero-auth (reuses existing CLI/Desktop sign-ins), real full-screen on a dedicated
  display, and an app icon.

[1.5.4]: https://github.com/yiminh/moon-gazer/releases/tag/v1.5.4
[1.5.3]: https://github.com/yiminh/moon-gazer/releases/tag/v1.5.3
[1.5.2]: https://github.com/yiminh/moon-gazer/releases/tag/v1.5.2
[1.5.1]: https://github.com/yiminh/moon-gazer/releases/tag/v1.5.1
[1.5.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.5.0
[1.4.2]: https://github.com/yiminh/moon-gazer/releases/tag/v1.4.2
[1.4.1]: https://github.com/yiminh/moon-gazer/releases/tag/v1.4.1
[1.4.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.4.0
[1.3.1]: https://github.com/yiminh/moon-gazer/releases/tag/v1.3.1
[1.3.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.3.0
[1.2.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.2.0
[1.1.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.1.0
[1.0.0]: https://github.com/yiminh/moon-gazer/releases/tag/v1.0.0
