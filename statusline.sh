#!/usr/bin/env bash
# cc-limits-statusline — a Claude Code statusline that shows your REAL plan limits.
#
# Data sources — note the two have DIFFERENT freshness guarantees:
#
#   1. The JSON Claude Code pipes to this command on stdin (LIVE, per refresh):
#        rate_limits.five_hour  — current session (5-hour rolling window)
#        rate_limits.seven_day  — weekly limit
#        cost.total_cost_usd    — cost of the current session (credits / overage)
#        context_window         — context window usage
#
#   2. The cached config file ~/.claude.json (see $CFG below) — plan name and the
#      "extra usage" flag. Claude Code only rewrites oauthAccount on AUTH events
#      (login / token refresh / restart), NOT in real time. So right after you
#      upgrade your plan on the web it keeps showing the old tier until Claude
#      Code re-authenticates — restart Claude Code to refresh it. There is no
#      plan field on stdin, so this cache is the only source for the plan name.
#
# Override the config path (e.g. for tests) with CC_STATUSLINE_CONFIG.
#
# Requires: jq. Repo: https://github.com/danilchernyshev/cc-limits-statusline

CFG="${CC_STATUSLINE_CONFIG:-$HOME/.claude.json}"

# At/over this percentage the dot doubles (●●) — past the limit, into overage.
EXTRA_HEAVY=101

R='\033[0m'; DIM='\033[02m'; MAG='\033[01;35m'; BLUE='\033[01;34m'

# --- map the raw organizationType to a short plan label --------------------
plan_label() {
  case "$1" in
    claude_pro)         printf 'Pro' ;;
    claude_max)         printf 'Max' ;;
    claude_max_5x)      printf 'Max 5x' ;;
    claude_max_20x)     printf 'Max 20x' ;;
    claude_team*)       printf 'Team' ;;
    claude_enterprise*) printf 'Enterprise' ;;
    "?"|"")             printf '?' ;;
    *)                  printf '%s' "${1#claude_}" ;;   # fallback: show as-is
  esac
}

# --- colour a percentage: <80 green, 80-94 yellow, >=95 red ----------------
color_for() {
  local p=$1
  if   [ "$p" -ge 95 ]; then printf '\033[01;31m'   # red (bold)
  elif [ "$p" -ge 80 ]; then printf '\033[33m'      # yellow
  else                       printf '\033[32m'; fi   # green
}

# --- the ANSI-coloured extra-usage dot for the worst-of-two percentage ------
# Colours match color_for; a plain text glyph (U+25CF) is used instead of a
# 🟢/🔴 emoji so the colour comes from ANSI and tracks the terminal theme:
#   ● green  < 80%            (plenty of headroom, not spending money)
#   ● yellow 80–94%           (getting close to the limit)
#   ● red    95% .. EXTRA_HEAVY-1   (at the limit → paid overage starting/active)
#   ●● red   ≥ EXTRA_HEAVY%    (over the limit, paid overage is active)
dot_for() {
  local p=$1
  if   [ "$p" -ge "$EXTRA_HEAVY" ]; then printf '\033[01;31m●●\033[0m'
  elif [ "$p" -ge 95 ];            then printf '\033[01;31m●\033[0m'
  elif [ "$p" -ge 80 ];            then printf '\033[33m●\033[0m'
  else                                  printf '\033[32m●\033[0m'; fi
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

# When sourced (e.g. by the test suite) stop here: the functions above are
# exposed without reading stdin or printing a status line.
[ "${BASH_SOURCE[0]}" = "${0}" ] || return 0

# ===== main ================================================================
input=$(cat)

# --- jq is required; degrade gracefully if it is missing -------------------
if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq not found (install it: https://stedolan.github.io/jq/)'
  exit 0
fi

# --- subscription plan and extra-usage flag from the cached config ---------
PLAN_RAW=$(jq -r '.oauthAccount.organizationType // "?"' "$CFG" 2>/dev/null)
EXTRA=$(jq -r '.oauthAccount.hasExtraUsageEnabled // false' "$CFG" 2>/dev/null)
PLAN=$(plan_label "$PLAN_RAW")

# organizationType is generic "claude_max" for every Max tier; the 5x/20x
# distinction lives only in organizationRateLimitTier. When the plan resolved
# to a bare "Max", refine it from that field so [Max] becomes [Max 20x].
if [ "$PLAN" = "Max" ]; then
  RL_TIER=$(jq -r '.oauthAccount.organizationRateLimitTier // ""' "$CFG" 2>/dev/null)
  case "$RL_TIER" in
    *max_20x) PLAN='Max 20x' ;;
    *max_5x)  PLAN='Max 5x'  ;;
  esac
fi

# --- pull every live value we need in a single jq call ---------------------
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

# Integer versions of the percentages, for comparisons (values may be floats).
H5I=${H5_PCT%%.*}; D7I=${D7_PCT%%.*}; H5I=${H5I:-0}; D7I=${D7I:-0}

H5_C=$(color_for "$H5I")
D7_C=$(color_for "$D7I")
COST_F=$(printf '%.2f' "$COST")

# --- extra-usage indicator + signal ----------------------------------------
# Always show an "Extra-Usage-ON: [y/n] sts:●" tag (as its own │-separated
# field before the cost): [y]/[n] reflects whether paid overage ("extra
# usage") is enabled, and the ANSI-coloured ● dot signals the WORST of the
# two limits.
MAXP=$H5I; [ "$D7I" -gt "$MAXP" ] && MAXP=$D7I
if [ "$EXTRA" = "true" ]; then YN='y'; else YN='n'; fi
EXTRA_TAG=$(printf "Extra-Usage-ON: [%s] sts:%s" "$YN" "$(dot_for "$MAXP")")

# Layout: cwd  [plan]  model │ 5h │ 7d │ ctx │ Extra-Usage-ON: [y/n] sts:● │ 💳 cost
# Only the plan is bracketed; the overage tag is its own field right before the
# cost. 💳 (current-session cost) stays last.
printf "${BLUE}%s${R} ${MAG}[%s]${R} %s ${DIM}│${R} 5h ${H5_C}%s%%${R} ${DIM}(%s)${R} ${DIM}│${R} 7d ${D7_C}%s%%${R} ${DIM}(%s)${R} ${DIM}│ ctx %s%%${R} ${DIM}│${R} %s ${DIM}│${R} 💳 \$%s" \
  "$CWD" "$PLAN" "$MODEL" \
  "$H5_PCT" "$(fmt_reset "$H5_RESET")" \
  "$D7_PCT" "$(fmt_reset "$D7_RESET")" \
  "$CTX" "$EXTRA_TAG" "$COST_F"
