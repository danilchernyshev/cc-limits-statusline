# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cc-limits-statusline` is a Claude Code statusline rendered by a single bash
script, `statusline.sh`. Claude Code pipes it a JSON payload on stdin; it prints
one line showing the 5-hour session window, the 7-day weekly window, session
cost, context-window usage, and a colour-coded extra-usage (paid overage) signal.

**No network calls, no persistent state.** The script only reads stdin and two
config files (see below).

The repo is **dual-purpose**: a plain installable script (`install.sh`) *and* its
own Claude Code plugin marketplace (`.claude-plugin/plugin.json` +
`.claude-plugin/marketplace.json`).

## Commands

```bash
bash tests/run.sh          # full test suite (only deps: bash + jq)
bash install.sh            # install into ~/.claude/ and wire up settings.json

# Render the line by hand against a fixture:
printf '%s' "$(cat tests/fixtures/stdin_basic.json)" \
  | CC_STATUSLINE_CONFIG=tests/fixtures/config_max.json bash statusline.sh
```

There is no build or lint step. `jq` is the only runtime dependency.

## Architecture

`statusline.sh` is the whole feature. Its two data sources have **different
freshness guarantees** — keep them straight:

1. **stdin JSON (live, every refresh):** `rate_limits.five_hour`,
   `rate_limits.seven_day`, `cost.total_cost_usd`, `context_window`. Pulled in a
   single `jq … | @tsv` call read into tab-separated vars.
2. **Cached `~/.claude.json` (stale until an auth event):** plan name
   (`oauthAccount.organizationType`, refined via `organizationRateLimitTier` for
   the Max 5x/20x split) and the extra-usage flag (`hasExtraUsageEnabled`).
   Claude Code only rewrites this on login/refresh/restart, so the plan can lag
   reality. Override the path with `CC_STATUSLINE_CONFIG` (tests do this).

### Config & the robustness contract

User config is an **optional sourced-bash file**
(`~/.config/cc-limits-statusline.conf`, override via `CC_STATUSLINE_RC`) carrying
only *overrides* — thresholds (`YELLOW_AT`, `RED_AT`, `DOUBLE_AT`,
`CTX_YELLOW_AT`, `CTX_RED_AT`) and field-visibility flags (`SHOW_*`).

The defaults live **in the script**, in `apply_defaults()` — never in a separate
file a user could delete. `apply_defaults()` runs twice: once at load time (so a
sourced unit test gets pristine defaults) and again right after the rc is
sourced in `main`. Every setting is laundered through `int_or`/`flag_or`, so a
blank (`YELLOW_AT=`) or malformed (`RED_AT=abc`, `SHOW_CWD=x`) value degrades to
its default instead of crashing the downstream arithmetic. **Preserve this:**
blank/garbage config must never break the line — it is covered by tests and is
the whole point of the design.

### The sourcing guard

Line ~145: `[ "${BASH_SOURCE[0]}" = "${0}" ] || return 0`. When the script is
*sourced* (the test suite does this), it stops here, exposing only the pure
functions (`plan_label`, `effort_label`, `effort_color`, `color_for`, `dot_for`,
`fmt_reset`, `int_or`, `flag_or`) without reading stdin or printing. Everything after the guard is
`main`. Keep pure, unit-testable helpers above the guard.

### Line assembly

The line is built field by field via an `add()` helper that inserts the
` │ ` separator, so any `SHOW_*=0` drops that field *and its separator* cleanly
(no dangling/leading separators). Header fields (cwd/plan/model) are
space-joined into one group; the metric fields are `│`-separated; cost stays
last. Colours are real ANSI escapes emitted through `printf`.

## Tests

`tests/run.sh` is zero-dependency (bash + jq). It both **sources** the script to
unit-test the pure functions and **pipes fixture JSON** (`tests/fixtures/*.json`)
through it for integration tests, stripping ANSI before asserting. There is no
per-test filter — extend coverage by adding fixtures and assertions in
`run.sh`. `CC_STATUSLINE_RC` is pinned to `/dev/null` in `render()` so a real rc
on the dev machine can't leak into tests.

The Windows installer has its own zero-dependency suite, `windows/tests/run.ps1`
(`pwsh`, no Pester). It **dot-sources** `install-steps.ps1` / `uninstall-steps.ps1`
— whose side-effecting bodies are behind a `$MyInvocation.InvocationName -ne '.'`
guard (the PowerShell analogue of statusline.sh's `BASH_SOURCE` guard) — and
asserts on the pure helpers (`Get-StatusLineCommand`, `Set-StatusLineSetting`,
`Remove-StatusLineSetting`) using temp files. It covers only the OS-independent
logic (command string, settings.json merge, BOM-free output); winget installs and
`bash.exe` discovery are not unit-testable off Windows. `pwsh` runs on Linux, so
`pwsh -NoProfile -File windows/tests/run.ps1` works on the dev machine too; CI
runs it on `windows-latest` before compiling the `.iss`.

## Releasing

Keep the version in sync across **four** places on every release:
`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`,
and the `MyAppVersion` define in `windows/cc-limits-statusline.iss` (the Windows
installer).
