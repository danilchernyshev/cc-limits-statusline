# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
