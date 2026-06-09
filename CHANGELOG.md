# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
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
