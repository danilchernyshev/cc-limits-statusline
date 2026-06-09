#!/usr/bin/env bash
# cc-limits-statusline — a Claude Code statusline that shows your REAL plan limits.
#
# Data source: the JSON that Claude Code feeds to the statusline command on stdin.
#   rate_limits.five_hour  — current session (5-hour rolling window)
#   rate_limits.seven_day  — weekly limit
#   cost.total_cost_usd    — cost of the current session (credits / paid overage)
#   context_window         — context window usage
#
# Plan name and "extra usage" (paid overage) flag are read from ~/.claude.json.
#
# Requires: jq. Repo: https://github.com/danilchernyshev/cc-limits-statusline

input=$(cat)

# --- jq is required; degrade gracefully if it is missing -------------------
if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq not found (install it: https://stedolan.github.io/jq/)'
  exit 0
fi

# --- subscription plan and extra-usage flag from Claude Code config --------
CFG="$HOME/.claude.json"
PLAN_RAW=$(jq -r '.oauthAccount.organizationType // "?"' "$CFG" 2>/dev/null)
EXTRA=$(jq -r '.oauthAccount.hasExtraUsageEnabled // false' "$CFG" 2>/dev/null)
case "$PLAN_RAW" in
  claude_pro)         PLAN="Pro" ;;
  claude_max)         PLAN="Max" ;;
  claude_max_5x)      PLAN="Max 5x" ;;
  claude_max_20x)     PLAN="Max 20x" ;;
  claude_team*)       PLAN="Team" ;;
  claude_enterprise*) PLAN="Enterprise" ;;
  "?"|"")             PLAN="?" ;;
  *)                  PLAN="${PLAN_RAW#claude_}" ;;   # fallback: show as-is
esac

# --- pull every value we need in a single jq call --------------------------
# Percentages are rounded to whole numbers (`| round`) so the bar never shows
# noise like "55.00000000000001%".
IFS=$'\t' read -r CWD MODEL H5_PCT H5_RESET D7_PCT D7_RESET COST CTX <<EOF
$(printf '%s' "$input" | jq -r '
  [ .cwd // .workspace.current_dir // "?",
    .model.display_name // "?",
    (.rate_limits.five_hour.used_percentage // 0 | round),
    (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.used_percentage // 0 | round),
    (.rate_limits.seven_day.resets_at // 0),
    (.cost.total_cost_usd // 0),
    (.context_window.used_percentage // 0 | round)
  ] | @tsv')
EOF

# --- colour a percentage: <80 green, 80-94 yellow, >=95 red ----------------
color_for() {
  local p=$1
  if   [ "$p" -ge 95 ]; then printf '\033[01;31m'   # red (bold)
  elif [ "$p" -ge 80 ]; then printf '\033[33m'      # yellow
  else                       printf '\033[32m'; fi   # green
}

# --- humanise the time left until a reset (from a unix timestamp) ----------
fmt_reset() {
  local t=$1 now d days hours mins
  now=$(date +%s)
  d=$((t - now))
  [ "$d" -le 0 ] && { printf 'now'; return; }
  days=$((d / 86400)); hours=$(((d % 86400) / 3600)); mins=$(((d % 3600) / 60))
  if   [ "$days" -gt 0 ]; then printf '%dd %dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then printf '%dh %dm' "$hours" "$mins"
  else printf '%dm' "$mins"; fi
}

R='\033[0m'; DIM='\033[02m'; MAG='\033[01;35m'; BLUE='\033[01;34m'

# At/over this percentage the dot doubles (●●) — past the limit, into overage.
EXTRA_HEAVY=101

# Integer versions of the percentages, for comparisons (values may be floats).
H5I=${H5_PCT%%.*}; D7I=${D7_PCT%%.*}; H5I=${H5I:-0}; D7I=${D7I:-0}

H5_C=$(color_for "$H5I")
D7_C=$(color_for "$D7I")
COST_F=$(printf '%.2f' "$COST")

# --- extra-usage indicator + signal ----------------------------------------
# When paid overage ("extra usage") is enabled, the plan tag gets a "$" marker
# (e.g. [Pro $]) and an ANSI-coloured ● dot sits right next to it. We use a
# plain text glyph (U+25CF) instead of a 🟢/🔴 emoji so the colour comes from
# ANSI — it tracks the terminal theme and keeps a single-cell width.
# Colour = worst of the two limits (matches the percentage colours):
#   ● green  < 80%     (plenty of headroom, not spending money)
#   ● yellow 80–94%    (getting close to the limit)
#   ● red    95–100%   (at the limit → paid overage about to start / active)
#   ●● red   ≥ EXTRA_HEAVY%  (over the limit, paid overage is active)
MAXP=$H5I; [ "$D7I" -gt "$MAXP" ] && MAXP=$D7I
if [ "$EXTRA" != "true" ]; then
  PLAN_X=""; MARK=""
else
  PLAN_X=' $'
  if   [ "$MAXP" -ge "$EXTRA_HEAVY" ]; then MARK=$(printf ' \033[01;31m●●\033[0m')
  elif [ "$MAXP" -ge 95 ];            then MARK=$(printf ' \033[01;31m●\033[0m')
  elif [ "$MAXP" -ge 80 ];            then MARK=$(printf ' \033[33m●\033[0m')
  else                                      MARK=$(printf ' \033[32m●\033[0m')
  fi
fi

# Layout: cwd  [plan $ ●]  model │ 5h │ 7d │ ctx │ 💳 cost
# The "$" tag + ● signal live inside the plan brackets; 💳 (current-session
# cost) stays last. ${MAG} is re-applied after ● (which ends in a reset) so the
# closing bracket keeps the plan colour.
printf "${BLUE}%s${R} ${MAG}[%s%s%s${MAG}]${R} %s ${DIM}│${R} 5h ${H5_C}%s%%${R} ${DIM}(%s)${R} ${DIM}│${R} 7d ${D7_C}%s%%${R} ${DIM}(%s)${R} ${DIM}│ ctx %s%%${R} ${DIM}│${R} 💳 \$%s" \
  "$CWD" "$PLAN" "$PLAN_X" "$MARK" "$MODEL" \
  "$H5_PCT" "$(fmt_reset "$H5_RESET")" \
  "$D7_PCT" "$(fmt_reset "$D7_RESET")" \
  "$CTX" "$COST_F"
