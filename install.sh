#!/usr/bin/env bash
# Installer for cc-limits-statusline.
#
# Copies statusline.sh into ~/.claude/ and wires it into ~/.claude/settings.json
# as the active statusLine command. Safe to re-run; it backs up settings.json
# before editing.
#
#   bash install.sh
# or one-liner:
#   curl -fsSL https://raw.githubusercontent.com/danilchernyshev/cc-limits-statusline/main/install.sh | bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/danilchernyshev/cc-limits-statusline/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (https://stedolan.github.io/jq/)"; exit 1; }

mkdir -p "$CLAUDE_DIR"

# 1) Place the script — prefer the local copy, fall back to downloading it.
if [ -f "$SCRIPT_DIR/statusline.sh" ]; then
  cp "$SCRIPT_DIR/statusline.sh" "$DEST"
else
  curl -fsSL "$REPO_RAW/statusline.sh" -o "$DEST"
fi
chmod +x "$DEST"
echo "✓ installed statusline → $DEST"

# 2) Wire it into settings.json (create the file if it does not exist yet).
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
jq --arg cmd "bash $DEST" \
   '.statusLine = {"type": "command", "command": $cmd}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ updated $SETTINGS (backup saved alongside it)"

# 3) Seed the user config (thresholds + field visibility) if absent. Never
# overwrite an existing one. It is optional — the script has built-in defaults.
RC="${CC_STATUSLINE_RC:-$HOME/.config/cc-limits-statusline.conf}"
if [ ! -f "$RC" ]; then
  mkdir -p "$(dirname "$RC")"
  if [ -f "$SCRIPT_DIR/config.example.conf" ]; then
    cp "$SCRIPT_DIR/config.example.conf" "$RC"
  else
    curl -fsSL "$REPO_RAW/config.example.conf" -o "$RC"
  fi
  echo "✓ wrote default config → $RC (edit to tune thresholds / hide fields)"
else
  echo "• kept existing config → $RC"
fi

echo
echo "Done. Start or reload Claude Code to see the new statusline."
