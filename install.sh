#!/bin/bash
# Link this repo into Omarchy as the ward.ai-usage bar plugin, put the `ai-usage` CLI on PATH,
# and add the widget to the bar. Re-running is safe.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ward.ai-usage"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }

if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  echo "$PLUGIN_DIR exists and isn't a link to this repo; move it away first." >&2
  exit 1
fi

mkdir -p "$HOME/.config/omarchy/plugins" "$HOME/.local/bin"
ln -sfn "$REPO" "$PLUGIN_DIR"
ln -sfn "$REPO/bin/ai-usage" "$HOME/.local/bin/ai-usage"

omarchy-shell -q shell rescanPlugins || true

if ! grep -q "\"$PLUGIN_ID\"" "$SHELL_JSON" 2>/dev/null; then
  # Beside Omarchy's own Agents icon when it's in the bar, else where the manifest says.
  if grep -q '"omarchy.agents"' "$SHELL_JSON" 2>/dev/null; then
    omarchy plugin enable "$PLUGIN_ID" --before omarchy.agents
  else
    omarchy plugin enable "$PLUGIN_ID"
  fi
fi

echo "Installed. Accounts: $(python3 "$REPO/bin/ai-usage" paths | sed -n 's/^config  //p')"
echo "Try: ai-usage show, or click the widget in the bar."
