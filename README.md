# cc-limits-statusline

A [Claude Code](https://claude.com/claude-code) statusline that shows your **real
plan limits** at a glance — the 5‑hour session window, the 7‑day weekly window,
your session cost, context usage, and a colour‑coded **extra‑usage signal** so
you instantly know whether you're about to start paying for overage.

```
~/dev/myproject [Pro] 🟢 Claude Opus 4.8 │ 5h 42% (3h 12m) │ 7d 18% (5d 4h) │ 💳 $0.00 │ ctx 31%
```

## What it shows

| Field            | Meaning                                                              |
| ---------------- | ------------------------------------------------------------------- |
| `~/dev/myproject`| Current working directory                                           |
| `[Pro]`          | Your subscription plan (Pro / Max / Max 5x / Max 20x / Team / …)    |
| 🟢 / 🟡 / 🔴      | Extra‑usage signal (only shown when extra usage is enabled)         |
| `Claude Opus 4.8`| Active model                                                        |
| `5h 42% (3h 12m)`| 5‑hour session limit used, and time until it resets                |
| `7d 18% (5d 4h)` | 7‑day weekly limit used, and time until it resets                  |
| `💳 $0.00`       | Cost of the current session (paid overage / credits)               |
| `ctx 31%`        | Context window used                                                |

Percentages are colour‑coded: **green** `<80%`, **yellow** `80–94%`,
**red** `≥95%`.

### The extra‑usage signal

When **extra usage** (paid overage) is enabled on your account, a coloured
circle reflects the **worst** of your two limits:

| Sign  | When                          | Meaning                                  |
| ----- | ----------------------------- | ---------------------------------------- |
| 🟢    | worst limit `< 90%`           | Enabled, plenty of headroom — not paying |
| 🟡    | `90–99%`                      | Close to the limit, overage about to kick in |
| 🔴    | `≥ 100%`                      | Limit reached → paid overage is active   |
| 🔴🔴  | `≥ 120%` (`EXTRA_HEAVY`)      | Leaning heavily on paid overage          |

> **Why circles and not ⚡?** Emoji like ⚡ are rendered by the terminal in
> their own fixed colour and ignore ANSI colour codes, so a "coloured lightning
> bolt" always looks the same yellow. Circle emoji carry the colour *in the
> glyph*, so the signal is reliably distinct across terminals.

The `EXTRA_HEAVY` threshold (default `120`) is a plain variable near the top of
`statusline.sh` — change it to taste.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [`jq`](https://stedolan.github.io/jq/) (`sudo apt install jq` / `brew install jq`)
- A POSIX shell (`bash`)

## Install

### Option A — install script (any setup)

```bash
git clone https://github.com/danilchernyshev/cc-limits-statusline.git
cd cc-limits-statusline
bash install.sh
```

…or as a one‑liner:

```bash
curl -fsSL https://raw.githubusercontent.com/danilchernyshev/cc-limits-statusline/main/install.sh | bash
```

The installer copies `statusline.sh` into `~/.claude/` and adds this to your
`~/.claude/settings.json` (backing it up first):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /home/you/.claude/statusline.sh"
  }
}
```

Reload Claude Code and you're done.

### Option B — as a Claude Code plugin (marketplace)

This repo doubles as its own Claude Code marketplace. From inside Claude Code:

```
/plugin marketplace add danilchernyshev/cc-limits-statusline
/plugin install cc-limits-statusline@cc-limits-statusline
```

The plugin contributes the statusline via `${CLAUDE_PLUGIN_ROOT}/statusline.sh`,
so there's nothing to copy by hand. Update later with `/plugin marketplace update
cc-limits-statusline`.

### Manual install

1. Copy `statusline.sh` anywhere (e.g. `~/.claude/statusline.sh`).
2. `chmod +x ~/.claude/statusline.sh`
3. Add the `statusLine` block above to `~/.claude/settings.json`.

## How it works

Claude Code pipes a JSON blob to the statusline command on stdin every time it
refreshes. The script reads the live `rate_limits`, `cost`, and `context_window`
fields from that JSON, and reads the plan name + extra‑usage flag from
`~/.claude.json`. No network calls, no extra state.

## Uninstall

Remove the `statusLine` key from `~/.claude/settings.json` (or restore one of
the `settings.json.bak.*` backups the installer left), and delete
`~/.claude/statusline.sh`.

## License

[MIT](LICENSE) © 2026 Danil Chernyshev
