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

# --- user config (defaults; overridable from the rc file, see below) --------
# These are the DEFAULTS. They are overridden by the rc file sourced in main
# (CC_STATUSLINE_RC, default ~/.config/cc-limits-statusline.conf). Defining them
# here means a sourced unit test (which never sees the rc) always gets defaults.
#
# Colour thresholds (percentages). The "worst-of-two" limit is coloured:
#   < YELLOW_AT          green   (plenty of headroom — not paying)
#   YELLOW_AT..RED_AT-1  yellow  (getting close to the limit)
#   RED_AT..DOUBLE_AT-1  red ●   (at the limit → paid overage about to start)
#   >= DOUBLE_AT         red ●●  (over the limit, paid overage is active)
YELLOW_AT=${YELLOW_AT:-80}
RED_AT=${RED_AT:-95}
DOUBLE_AT=${DOUBLE_AT:-101}

# Field visibility (1 = show, 0 = hide). The line is built from whichever of
# these are enabled, in this order, so hiding one just drops it (and its
# separator) cleanly.
SHOW_CWD=${SHOW_CWD:-1}      # ~/dev/myproject — current working directory
SHOW_PLAN=${SHOW_PLAN:-1}    # [Max 20x]       — subscription plan
SHOW_MODEL=${SHOW_MODEL:-1}  # Claude Opus 4.8 — active model
SHOW_5H=${SHOW_5H:-1}        # 5h 42% (3h 12m) — 5-hour session window
SHOW_7D=${SHOW_7D:-1}        # 7d 18% (5d 4h)  — 7-day weekly window
SHOW_CTX=${SHOW_CTX:-1}      # ctx 31%         — context window used
SHOW_EXTRA=${SHOW_EXTRA:-1}  # Extra-Usage: ON ● — overage state + status dot
SHOW_COST=${SHOW_COST:-1}    # 💳 $0.00        — current-session cost

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

# --- colour a percentage by the configured thresholds ----------------------
# < YELLOW_AT green, YELLOW_AT..RED_AT-1 yellow, >= RED_AT red.
color_for() {
  local p=$1
  if   [ "$p" -ge "$RED_AT" ];    then printf '\033[01;31m'   # red (bold)
  elif [ "$p" -ge "$YELLOW_AT" ]; then printf '\033[33m'      # yellow
  else                                 printf '\033[32m'; fi   # green
}

# --- the ANSI-coloured extra-usage dot for the worst-of-two percentage ------
# Colours match color_for; a plain text glyph (U+25CF) is used instead of a
# 🟢/🔴 emoji so the colour comes from ANSI and tracks the terminal theme:
#   ● green  < YELLOW_AT            (plenty of headroom, not spending money)
#   ● yellow YELLOW_AT..RED_AT-1    (getting close to the limit)
#   ● red    RED_AT..DOUBLE_AT-1    (at the limit → paid overage starting/active)
#   ●● red   ≥ DOUBLE_AT            (over the limit, paid overage is active)
dot_for() {
  local p=$1
  if   [ "$p" -ge "$DOUBLE_AT" ]; then printf '\033[01;31m●●\033[0m'
  elif [ "$p" -ge "$RED_AT" ];    then printf '\033[01;31m●\033[0m'
  elif [ "$p" -ge "$YELLOW_AT" ]; then printf '\033[33m●\033[0m'
  else                                 printf '\033[32m●\033[0m'; fi
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
# Load the user rc file (if any) so it can override the thresholds and SHOW_*
# flags defined at the top. Sourced only here in main, so unit tests that source
# this script keep the pristine defaults. Override the path with CC_STATUSLINE_RC.
RC="${CC_STATUSLINE_RC:-$HOME/.config/cc-limits-statusline.conf}"
# shellcheck disable=SC1090
[ -f "$RC" ] && . "$RC"

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
# Show an "Extra-Usage: ON ●" / "Extra-Usage: OFF" tag (its own │-separated
# field before the cost). ON/OFF reflects whether paid overage ("extra usage")
# is enabled on your account. The ANSI-coloured ● dot — signalling the WORST of
# the two limits — is only shown when extra usage is ON (OFF means no overage
# can start, so the dot carries no useful signal).
MAXP=$H5I; [ "$D7I" -gt "$MAXP" ] && MAXP=$D7I
if [ "$EXTRA" = "true" ]; then
  EXTRA_TAG=$(printf "Extra-Usage: ON %s" "$(dot_for "$MAXP")")
else
  EXTRA_TAG="Extra-Usage: OFF"
fi

# Layout: cwd  [plan]  model │ 5h │ 7d │ ctx │ Extra-Usage: ON ● │ 💳 cost
# Build it field by field so any SHOW_*=0 just drops that field (and its
# separator). cwd/[plan]/model form a space-joined header; the metric fields
# that follow are │-separated. 💳 (current-session cost) stays last.
# Built via printf so the \033 escapes in DIM/R become real ESC bytes (the line
# itself is emitted with `printf '%s'`, which would not interpret them).
SEP=$(printf " ${DIM}│${R} ")
LINE=""
add() { # value  — append with the │ separator, or as the first field
  [ -z "$1" ] && return
  if [ -n "$LINE" ]; then LINE="$LINE$SEP$1"; else LINE="$1"; fi
}

# Header group (cwd [plan] model), space-joined into one field.
HDR=""
[ "$SHOW_CWD" = 1 ]   && HDR=$(printf "${BLUE}%s${R}" "$CWD")
[ "$SHOW_PLAN" = 1 ]  && HDR="${HDR:+$HDR }$(printf "${MAG}[%s]${R}" "$PLAN")"
[ "$SHOW_MODEL" = 1 ] && HDR="${HDR:+$HDR }$MODEL"
add "$HDR"

[ "$SHOW_5H" = 1 ]    && add "$(printf "5h ${H5_C}%s%%${R} ${DIM}(%s)${R}" "$H5_PCT" "$(fmt_reset "$H5_RESET")")"
[ "$SHOW_7D" = 1 ]    && add "$(printf "7d ${D7_C}%s%%${R} ${DIM}(%s)${R}" "$D7_PCT" "$(fmt_reset "$D7_RESET")")"
[ "$SHOW_CTX" = 1 ]   && add "$(printf "${DIM}ctx %s%%${R}" "$CTX")"
[ "$SHOW_EXTRA" = 1 ] && add "$EXTRA_TAG"
[ "$SHOW_COST" = 1 ]  && add "$(printf "💳 \$%s" "$COST_F")"

printf '%s' "$LINE"
