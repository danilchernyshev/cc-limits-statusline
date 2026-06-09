# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
