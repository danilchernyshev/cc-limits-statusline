# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Windows `.exe` installer.** A double‑clickable setup (built with Inno Setup)
  that auto‑installs the runtime dependencies via winget (`jq` and Git for Windows
  for `bash`), copies `statusline.sh`, wires up `settings.json` with the absolute
  path to `bash.exe` (works without touching PATH), and seeds the default config.
  The logic lives in `windows/install-steps.ps1` (and `uninstall-steps.ps1`),
  which also run standalone via `irm … | iex`; the `.exe` is built by the
  `windows-installer` GitHub Actions workflow and attached to releases. The
  installer logic has a zero-dependency PowerShell test suite
  (`windows/tests/run.ps1`, run in CI). README's Windows section now leads with
  this installer.
- The `ctx` (context window) percentage is now colour‑coded, keyed to when it
  pays to run `/compact` rather than to billing: green `<70%`, yellow `70–84%`,
  red `≥85%` (auto‑compact imminent). New `CTX_YELLOW_AT` (70) / `CTX_RED_AT`
  (85) config thresholds; `color_for` now takes optional threshold arguments.
- Tests for the explicit‑threshold `color_for`, the ctx colour bands, and a
  custom‑`CTX_RED_AT` override.
- Config robustness: every setting is now validated after the rc file is sourced,
  so a value left **blank** (`YELLOW_AT=`) or **malformed** (`RED_AT=abc`,
  `SHOW_CWD=x`) falls back to its built‑in default instead of overriding it or
  emitting an arithmetic error. (Omitted/commented lines already defaulted.)
  Thresholds accept a non‑negative integer; `SHOW_*` flags accept `0`/`1`. Added
  `int_or`/`flag_or` helpers and unit + integration tests covering blank, garbage,
  and empty‑file configs.

### Changed
- Widened the default colour bands so red signals an *actual* overage: `RED_AT`
  `95 → 100` and `DOUBLE_AT` `101 → 120`. The worst‑of‑two limit (and its dot)
  is now green `<80%`, yellow `80–99%`, red `100–119%`, double‑red `≥120%`. This
  also colours the 5h/7d percentages, so they only turn red once you have truly
  hit the limit.

## [1.0.1] — 2026-06-09

### Added
- Optional config file (`~/.config/cc-limits-statusline.conf`, overridable with
  `CC_STATUSLINE_RC`) sourced on every refresh — no restart needed. See
  `config.example.conf`.
  - Configurable colour thresholds: `YELLOW_AT` (80), `RED_AT` (95) and
    `DOUBLE_AT` (101, was the hard‑coded `EXTRA_HEAVY`).
  - Per‑field visibility toggles (`SHOW_CWD`, `SHOW_PLAN`, `SHOW_MODEL`,
    `SHOW_5H`, `SHOW_7D`, `SHOW_CTX`, `SHOW_EXTRA`, `SHOW_COST`) — hiding a field
    drops its `│` separator too.
- `install.sh` now seeds the config file from `config.example.conf` if absent
  (never overwrites an existing one).
- Tests covering custom thresholds and hidden fields (incl. no leading
  separator when the whole header is hidden).

### Changed
- Renamed the `EXTRA_HEAVY` threshold to `DOUBLE_AT`, now read from the config
  file (default unchanged: `101`).
- Reworked the extra‑usage field from `Extra-Usage-ON: [y] sts:●` to
  `Extra-Usage: ON ●` / `Extra-Usage: OFF` — it shows the current account state
  in plain words; the coloured `●` dot follows only when extra usage is `ON`
  (hidden when `OFF`, since no overage can start).
- Refined the plan tag to distinguish Max tiers (`[Max 20x]` / `[Max 5x]`) by
  reading `organizationRateLimitTier`, since `organizationType` is the generic
  `claude_max` for every Max plan.
- Moved the extra‑usage signal out of the plan brackets into its own
  `│`‑separated field before the cost: `Extra-Usage-ON: [y/n] sts:●`. It is now
  always shown — `[y]`/`[n]` reflects whether paid overage is enabled, and the
  coloured `sts:` dot still tracks the worst of the two limits.

## [1.0.0] — 2026-06-08

### Added
- Statusline showing CWD, plan, model, 5‑hour and 7‑day rate limits (with
  reset countdowns), session cost, and context usage.
- Colour‑coded percentages: green `<80%`, yellow `80–94%`, red `≥95%`.
- Extra‑usage signal using colour‑in‑glyph circle emoji (🟢/🟡/🔴/🔴🔴) keyed
  to the worst of the two limits, with a configurable `EXTRA_HEAVY` threshold.
- `install.sh` that copies the script into `~/.claude/` and wires up
  `settings.json` (with backup).
- Claude Code plugin manifest (`.claude-plugin/plugin.json`).
