#!/usr/bin/env bash
#
# DaVinci Resolve 20/21 on KDE Plasma 6 (Wayland):
#   1. Restore the window title bar (KWin 6.6+ CSD detection quirk)
#   2. Fix launch crash: "symbol lookup error ... g_once_init_leave_pointer"
#      (Resolve's bundled old GLib colliding with the system GLib on XWayland)
#
# Safe to run multiple times. No root required.
# https://github.com/ZebyWebby/davinci-resolve-plasma6-fixes
set -euo pipefail

RESOLVE_BIN="${RESOLVE_BIN:-/opt/resolve/bin/resolve}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_DST="$DATA_HOME/applications/com.blackmagicdesign.resolve.desktop"
RULE_GROUP="davinci-resolve-decorations"
UI_CACHE="$HOME/.local/share/DaVinciResolve/.ui.cache.db"

MODE=full      # full | rule-only
RESET_LAYOUT=no

usage() {
  cat <<'EOF'
Usage: install.sh [--rule-only] [--reset-layout]

  --rule-only    Only add the KWin title-bar rule; leave the app launcher as is.
                 (Keeps Resolve on native Wayland. The title bar rule needs
                 KWin 6.6+ to exist / to apply to Wayland windows reliably.)
  --reset-layout Also rename Resolve's UI layout cache (.ui.cache.db), which
                 repairs stuck frameless / off-screen window layouts.
                 Your projects are not touched; panel layouts reset to default.
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
msg()  { echo "==> $*"; }
ok()   { echo "  ✓ $*"; }

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
esac
for arg in "$@"; do
  case "$arg" in
    --rule-only)    MODE=rule-only ;;
    --reset-layout) RESET_LAYOUT=yes ;;
    *) usage; fail "unknown option: $arg" ;;
  esac
done

echo "── DaVinci Resolve + KDE Plasma 6 fixes ──"

[[ -x "$RESOLVE_BIN" ]] || fail "DaVinci Resolve not found at $RESOLVE_BIN"

# ── KWin reconfigure (so the rule applies immediately, even to running windows)
reconfigure_kwin() {
  if command -v gdbus >/dev/null 2>&1 &&
     gdbus call --session --dest org.kde.KWin --object-path /KWin \
        --method org.kde.KWin.reconfigure >/dev/null 2>&1; then
    return 0
  elif command -v qdbus >/dev/null 2>&1 &&
     qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1; then
    return 0
  elif command -v dbus-send >/dev/null 2>&1 &&
     dbus-send --session --print-reply --dest=org.kde.KWin /KWin \
        org.kde.KWin.reconfigure >/dev/null 2>&1; then
    return 0
  fi
  echo "  (note: could not signal KWin to reload - the rule applies at next login)" >&2
  return 0
}

# ── 1. KWin window rule: force server-side decorations for Resolve ──────────
# KWin 6.6+ hides decorations when an app claims it draws its own window chrome
# (_GTK_FRAME_EXTENTS). Resolve's newer Qt build sets that hint, so KWin draws
# nothing. This rule forces KWin's own title bar for window class "resolve".
msg "Adding KWin window rule"
command -v kwriteconfig6 >/dev/null 2>&1 || \
  fail "kwriteconfig6 not found - this fix targets KDE Plasma 6"
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" \
  --key Description "DaVinci Resolve Studio - always draw server-side title bar"
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key Enabled true
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key wmclass resolve
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key wmclassmatch 2     # SubstringMatch
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key wmclasscomplete false
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key title "DaVinci Resolve"
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key titlematch 2       # SubstringMatch
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key decorationpolicy server
kwriteconfig6 --file kwinrulesrc --group "$RULE_GROUP" --key decorationpolicyrule 2  # Force
reconfigure_kwin
ok "rule '$RULE_GROUP' installed (main Resolve windows get a title bar; the splash stays frameless as BMD intended)"

# ── 2. Launcher: run Resolve on XWayland with the system GLib preloaded ─────
if [[ "$MODE" == full ]]; then
  msg "Installing launcher override (fixes both the title bar and the glib crash)"
  LIBDIR=""
  for d in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu; do
    if [[ -e "$d/libglib-2.0.so.0" && -e "$d/libgobject-2.0.so.0" && \
          -e "$d/libgio-2.0.so.0" && -e "$d/libgmodule-2.0.so.0" ]]; then
      LIBDIR="$d"; break
    fi
  done
  [[ -n "$LIBDIR" ]] || fail "could not locate system GLib (libglib/libgobject/libgio/libgmodule)"

  mkdir -p "$(dirname "$DESKTOP_DST")"
  cat > "$DESKTOP_DST" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=DaVinci Resolve
GenericName=DaVinci Resolve
Comment=DaVinci Resolve on XWayland with system GLib preloaded (title bar + crash fix)
Path=/opt/resolve/
Exec=env QT_QPA_PLATFORM=xcb LD_PRELOAD="$LIBDIR/libglib-2.0.so.0:$LIBDIR/libgobject-2.0.so.0:$LIBDIR/libgio-2.0.so.0:$LIBDIR/libgmodule-2.0.so.0" $RESOLVE_BIN %u
Terminal=false
MimeType=application/x-resolveproj;
Icon=/opt/resolve/graphics/DV_Resolve.png
StartupNotify=true
DESKTOP

  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  fi
  ok "wrote $DESKTOP_DST"
  ok "XWayland + LD_PRELOAD(system GLib: glib, gobject, gio, gmodule)"
else
  msg "Skipping launcher override (--rule-only)"
fi

# ── 3. Optional: reset Resolve's UI layout cache ─────────────────────────────
if [[ "$RESET_LAYOUT" == yes ]]; then
  msg "Resetting Resolve UI layout cache"
  if [[ -f "$UI_CACHE" ]]; then
    mv "$UI_CACHE" "$UI_CACHE.bak.$(date +%Y%m%d%H%M%S)"
    ok "renamed to a .bak file; Resolve rebuilds it on next launch"
  else
    ok "no layout cache found (nothing to do)"
  fi
fi

echo
echo "── Done ──"
echo "If Resolve is running: quit it (Ctrl+Q) and start it again from your app"
echo "menu. The title bar (minimize / maximize / close) should be back."
echo "Uninstall anytime with: bash uninstall.sh"
