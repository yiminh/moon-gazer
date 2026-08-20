# Acknowledgements

Moon Gazer's usage-fetching approach was learned by studying a number of open-source
Claude / Codex usage trackers. Credit and thanks to their authors. Where an idea or the
shape of an API interaction came directly from one of these projects, it is noted below.
All of these are MIT-licensed at the time of writing; each remains under its own license
and copyright.

| Project | Author | What Moon Gazer learned from it |
|---|---|---|
| [ai-pace](https://github.com/lbybrilee/ai-pace) | lbybrilee | The symmetric dual-provider model, and the shape of the Claude OAuth usage probe (`api.anthropic.com/api/oauth/usage`, `platform.claude.com/v1/oauth/token` refresh, credential ladder). |
| [CodexUsageBar](https://github.com/Artzainnn/CodexUsageBar) & [ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar) | Artzainnn / Linkko Technology | Reading `~/.codex/auth.json` and calling `chatgpt.com/backend-api/wham/usage`, with `auth.openai.com/oauth/token` refresh; the Codex rate-limit-window JSON shape. |
| [CodexBar](https://github.com/steipete/CodexBar) | Peter Steinberger | Multi-provider architecture, Codex OAuth handling, and `CODEX_HOME` / config-path resolution. |
| [TokenEater](https://github.com/AThevon/TokenEater) | AThevon | The Claude Desktop Electron `safeStorage` decryption technique (AES-128-CBC, PBKDF2 `saltysalt`/1003/SHA1, reading the key via `/usr/bin/security` to avoid a Keychain prompt). |
| [ClaudeMeter](https://github.com/eddmann/ClaudeMeter) | Edd Mann | A clean reference for menu-bar app structure, backoff, and caching. |
| [ClaudeBar](https://github.com/tddworks/ClaudeBar) | tddworks | Multi-provider probe abstraction and Claude-Code-hooks-based session status. |
| [Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | hamed-elfayome | Floating always-on window and hook-based per-task status. |
| [claude-usage gist](https://gist.github.com/omachala/5ea5af4bfa0b194a1d48d6f2eedd6274) | omachala | The original minimal proof: pull the Keychain OAuth token via `security` and hit `api/oauth/usage`. |

Moon Gazer does not vendor or redistribute any of these projects' code; it is an
independent implementation informed by their public techniques. If you maintain one of
these and would like the credit adjusted or removed, please open an issue.

## E-ink frontend (`trmnl/`)

- [**TRMNL**](https://usetrmnl.com) — the e-ink platform and its open Liquid framework
  (server-side 1-bit rendering, the `progress-bar` / `columns` / `border--*` component
  classes the markup builds on). See [usetrmnl/byos_hanami](https://github.com/usetrmnl).
- [**JetBrains Mono**](https://github.com/JetBrains/JetBrainsMono) and
  [**IBM Plex Mono**](https://github.com/IBM/plex) — the optional embeddable monospace
  faces (`inject_font.py`), both under the SIL Open Font License 1.1. The repo does not
  bundle the font files; `inject_font.py` fetches them on demand.

Built with [Claude Code](https://claude.com/claude-code) (Claude Opus).
