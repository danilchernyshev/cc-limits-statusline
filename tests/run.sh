#!/usr/bin/env bash
# Zero-dependency test suite for cc-limits-statusline (needs only bash + jq).
#
#   bash tests/run.sh
#
# Unit tests source ../statusline.sh (which stops at the BASH_SOURCE guard, so
# only the pure functions are exposed) and check them directly. Integration
# tests pipe fixture JSON to the script with CC_STATUSLINE_CONFIG pointed at a
# fixture config, then assert against the (ANSI-stripped) rendered line.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../statusline.sh"
FIX="$HERE/fixtures"
ESC=$(printf '\033')

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; printf '      %s\n' "$2"; }

assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_contains() { # desc haystack needle
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "[$2] does not contain [$3]" ;; esac
}
assert_not_contains() { # desc haystack needle
  case "$2" in *"$3"*) bad "$1" "[$2] unexpectedly contains [$3]" ;; *) ok "$1" ;; esac
}

strip_ansi() { sed "s/${ESC}\[[0-9;]*m//g"; }

# Render the status line for a given stdin payload + config, ANSI stripped.
# CC_STATUSLINE_RC is pinned to /dev/null so a real ~/.config rc on the test
# machine can't leak in; render_rc points it at a fixture rc instead.
render() { # stdin_json config_json
  printf '%s' "$1" | CC_STATUSLINE_CONFIG="$2" CC_STATUSLINE_RC=/dev/null bash "$SCRIPT" | strip_ansi
}
render_rc() { # stdin_json config_json rc_file
  printf '%s' "$1" | CC_STATUSLINE_CONFIG="$2" CC_STATUSLINE_RC="$3" bash "$SCRIPT" | strip_ansi
}
# Raw render (ANSI preserved) for asserting on per-field colours. rc defaults to
# /dev/null for isolation; pass a fixture rc as $3 to exercise overrides.
render_raw() { # stdin_json config_json [rc_file]
  printf '%s' "$1" | CC_STATUSLINE_CONFIG="$2" CC_STATUSLINE_RC="${3:-/dev/null}" bash "$SCRIPT"
}

# Expose the pure functions for unit testing (guard stops the script's main).
# shellcheck disable=SC1090
source "$SCRIPT"

echo "== unit: plan_label =="
assert_eq "claude_pro -> Pro"            "Pro"        "$(plan_label claude_pro)"
assert_eq "claude_max -> Max"            "Max"        "$(plan_label claude_max)"
assert_eq "claude_max_5x -> Max 5x"      "Max 5x"     "$(plan_label claude_max_5x)"
assert_eq "claude_max_20x -> Max 20x"    "Max 20x"    "$(plan_label claude_max_20x)"
assert_eq "claude_team* -> Team"         "Team"       "$(plan_label claude_team_acme)"
assert_eq "claude_enterprise* -> Enterprise" "Enterprise" "$(plan_label claude_enterprise_x)"
assert_eq "? -> ?"                       "?"          "$(plan_label '?')"
assert_eq "empty -> ?"                   "?"          "$(plan_label '')"
assert_eq "unknown -> stripped fallback" "experimental" "$(plan_label claude_experimental)"

echo "== unit: color_for (worst-of thresholds) =="
assert_eq "79 -> green"  "${ESC}[32m"    "$(color_for 79)"
assert_eq "80 -> yellow" "${ESC}[33m"    "$(color_for 80)"
assert_eq "99 -> yellow" "${ESC}[33m"    "$(color_for 99)"
assert_eq "100 -> red"   "${ESC}[01;31m" "$(color_for 100)"
assert_eq "119 -> red"   "${ESC}[01;31m" "$(color_for 119)"

echo "== unit: dot_for (glyph + colour by threshold) =="
assert_eq "79  -> green single"  "${ESC}[32m●${ESC}[0m"    "$(dot_for 79)"
assert_eq "80  -> yellow single" "${ESC}[33m●${ESC}[0m"    "$(dot_for 80)"
assert_eq "99  -> yellow single" "${ESC}[33m●${ESC}[0m"    "$(dot_for 99)"
assert_eq "100 -> red single"    "${ESC}[01;31m●${ESC}[0m" "$(dot_for 100)"
assert_eq "119 -> red single"    "${ESC}[01;31m●${ESC}[0m" "$(dot_for 119)"
assert_eq "120 -> red double"    "${ESC}[01;31m●●${ESC}[0m" "$(dot_for 120)"
assert_eq "124 -> red double"    "${ESC}[01;31m●●${ESC}[0m" "$(dot_for 124)"

echo "== unit: color_for with explicit ctx thresholds (compact guidance) =="
# Defaults to YELLOW_AT/RED_AT, but the ctx field passes CTX_YELLOW_AT/CTX_RED_AT.
assert_eq "69 (<70) -> green"   "${ESC}[32m"    "$(color_for 69 70 85)"
assert_eq "70 -> yellow"        "${ESC}[33m"    "$(color_for 70 70 85)"
assert_eq "84 -> yellow"        "${ESC}[33m"    "$(color_for 84 70 85)"
assert_eq "85 -> red"           "${ESC}[01;31m" "$(color_for 85 70 85)"
assert_eq "100 -> red"          "${ESC}[01;31m" "$(color_for 100 70 85)"

echo "== unit: fmt_reset =="
assert_eq "past timestamp -> now" "now" "$(fmt_reset 0)"
assert_contains "far future -> days" "$(fmt_reset $(( $(date +%s) + 90000 )))" "d"

echo "== integration: basic render (Max, extra on, worst 55 -> green) =="
OUT="$(render "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json")"
assert_contains "cwd shown"        "$OUT" "~/dev/myproject"
assert_contains "plan tag [Max]"   "$OUT" "[Max]"
assert_contains "extra tag (on)"   "$OUT" "Extra-Usage: ON ●"
assert_contains "5h rounded"       "$OUT" "5h 55%"
assert_contains "7d rounded"       "$OUT" "7d 21%"
assert_contains "ctx shown"        "$OUT" "ctx 2%"
assert_contains "cost last"        "$OUT" "💳 \$0.13"

echo "== integration: rounding of float percentages =="
OUT="$(render "$(cat "$FIX/stdin_floats.json")" "$FIX/config_max.json")"
assert_contains "54.9999.. -> 55" "$OUT" "5h 55%"
assert_contains "21.4 -> 21"      "$OUT" "7d 21%"
assert_contains "73.6 -> 74"      "$OUT" "ctx 74%"

echo "== integration: heavy overage -> double dot =="
OUT="$(render "$(cat "$FIX/stdin_high.json")" "$FIX/config_max.json")"
assert_contains "double dot in tag" "$OUT" "Extra-Usage: ON ●●"
assert_contains "124% shown"        "$OUT" "5h 124%"

echo "== integration: worst-of-two picks the 7d window =="
# 5h low (10%), 7d over the limit (105%) -> single red dot from the 7d side.
OUT="$(render '{"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":105}}}' "$FIX/config_max.json" | strip_ansi)"
assert_contains "dot reflects worst (7d)" "$OUT" "Extra-Usage: ON ●"

echo "== integration: extra usage state OFF -> shows OFF, no dot =="
OUT="$(render "$(cat "$FIX/stdin_basic.json")" "$FIX/config_extra_off.json")"
assert_contains "plain plan tag"    "$OUT" "[Max]"
assert_contains "shows OFF"         "$OUT" "Extra-Usage: OFF"
assert_not_contains "no ON state"   "$OUT" "Extra-Usage: ON"
assert_not_contains "no dot when OFF" "$OUT" "OFF ●"

echo "== integration: REGRESSION — config says Max -> never shows Pro =="
OUT="$(render "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json")"
assert_contains "shows Max"     "$OUT" "[Max"
assert_not_contains "not Pro"   "$OUT" "Pro"

echo "== integration: Pro config, extra off =="
OUT="$(render "$(cat "$FIX/stdin_basic.json")" "$FIX/config_pro.json")"
assert_contains "plain Pro tag" "$OUT" "[Pro]"

echo "== integration: empty stdin is graceful =="
OUT="$(render '{}' "$FIX/config_pro.json")"
assert_contains "falls back, no crash" "$OUT" "[Pro]"
assert_contains "zero percentages"     "$OUT" "5h 0%"

echo "== integration: ctx percentage is colour-coded (compact guidance) =="
# basic fixture ctx=2 -> green; high fixture ctx=92 -> red (default CTX_RED_AT=85).
RAW="$(render_raw "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json")"
assert_contains "ctx 2% is green"  "$RAW" "ctx${ESC}[0m ${ESC}[32m2%"
RAW="$(render_raw "$(cat "$FIX/stdin_high.json")" "$FIX/config_max.json")"
assert_contains "ctx 92% is red"   "$RAW" "ctx${ESC}[0m ${ESC}[01;31m92%"

echo "== config: custom ctx thresholds via rc =="
# Drop CTX_RED_AT to 2 so the basic fixture's ctx=2 trips red.
RC_CTX="$(mktemp)"; printf 'CTX_YELLOW_AT=1\nCTX_RED_AT=2\n' > "$RC_CTX"
RAW="$(render_raw "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json" "$RC_CTX")"
assert_contains "ctx 2% trips red at CTX_RED_AT=2" "$RAW" "ctx${ESC}[0m ${ESC}[01;31m2%"
rm -f "$RC_CTX"

echo "== config: custom thresholds via rc =="
# Lower the thresholds so a 55% worst-of-two trips the double dot.
RC_LOW="$(mktemp)"; printf 'YELLOW_AT=20\nRED_AT=40\nDOUBLE_AT=50\n' > "$RC_LOW"
OUT="$(render_rc "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json" "$RC_LOW")"
assert_contains "55% trips double dot" "$OUT" "Extra-Usage: ON ●●"
rm -f "$RC_LOW"

echo "== config: hide fields via rc =="
RC_HIDE="$(mktemp)"; printf 'SHOW_COST=0\nSHOW_CTX=0\nSHOW_EXTRA=0\n' > "$RC_HIDE"
OUT="$(render_rc "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json" "$RC_HIDE")"
assert_not_contains "cost hidden"  "$OUT" "💳"
assert_not_contains "ctx hidden"   "$OUT" "ctx"
assert_not_contains "extra hidden" "$OUT" "Extra-Usage"
assert_contains     "5h still shown" "$OUT" "5h 55%"
assert_contains     "plan still shown" "$OUT" "[Max]"
rm -f "$RC_HIDE"

echo "== config: hide the whole header (cwd/plan/model) -> line starts at 5h =="
RC_NOHDR="$(mktemp)"; printf 'SHOW_CWD=0\nSHOW_PLAN=0\nSHOW_MODEL=0\n' > "$RC_NOHDR"
OUT="$(render_rc "$(cat "$FIX/stdin_basic.json")" "$FIX/config_max.json" "$RC_NOHDR")"
assert_not_contains "no cwd"  "$OUT" "~/dev/myproject"
assert_not_contains "no plan" "$OUT" "[Max]"
assert_contains "first field is 5h, no leading separator" "$OUT" "5h 55%"
case "$OUT" in "│"*|" │"*) bad "no leading │" "line starts with a separator: [$OUT]";; *) ok "no leading │";; esac
rm -f "$RC_NOHDR"

echo
printf 'Result: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
