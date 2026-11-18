#!/usr/bin/env bash
#
# Reverse install.sh: remove the launcher override and the KWin rule.
# The system launcher (/usr/share/applications/com.blackmagicdesign.resolve.desktop)
# takes over again - it is never touched by install.sh.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_DST="$DATA_HOME/applications/com.blackmagicdesign.resolve.desktop"
RULE_GROUP="davinci-resolve-decorations"

ok() { echo "  ✓ $*"; }
echo "── Removing DaVinci Resolve Plasma 6 fixes ──"

RULEBOOK="${HOME}/.config/kwinrulesrc"
if [[ -f "$RULEBOOK" ]]; then
  awk -v target="[$RULE_GROUP]" '
    /^\[/ { keep = ($0 != target) }
    keep { print }
  ' "$RULEBOOK" > "$RULEBOOK.tmp" && mv "$RULEBOOK.tmp" "$RULEBOOK"
  ok "removed KWin rule '$RULE_GROUP'"
else
  echo "  (no kwinrulesrc found - nothing to remove)"
fi

if [[ -f "$DESKTOP_DST" ]]; then
  rm -f "$DESKTOP_DST"
  ok "removed launcher override"
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
fi

reconfigure_ok=no
if command -v gdbus >/dev/null 2>&1 && \
   gdbus call --session --dest org.kde.KWin --object-path /KWin \
      --method org.kde.KWin.reconfigure >/dev/null 2>&1; then
  reconfigure_ok=yes
elif command -v qdbus >/dev/null 2>&1 && \
     qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1; then
  reconfigure_ok=yes
fi
if [[ "$reconfigure_ok" == yes ]]; then
  ok "KWin reconfigured"
fi

echo
echo "── Done ──"
echo "Quit and relaunch DaVinci Resolve to return to the stock launcher."
echo "Optional: to restore a previous window layout backup, put it back:"
echo "  mv ~/.local/share/DaVinciResolve/.ui.cache.db.bak.XXXXXXXX \\"
echo "     ~/.local/share/DaVinciResolve/.ui.cache.db   (with Resolve closed)"
