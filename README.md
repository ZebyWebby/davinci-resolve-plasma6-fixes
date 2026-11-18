# 🎬 DaVinci Resolve + KDE Plasma 6 (Wayland) fixes

Fixes for running **DaVinci Resolve 20/21** on **KDE Plasma 6 with Wayland**:

1. **Missing title bar** — Resolve's window has no minimize / maximize / close bar.
2. **Launch crash** — `symbol lookup error: .../libpango-1.0.so.0: undefined symbol: g_once_init_leave_pointer` (or `g_module_open_full`) when Resolve starts on XWayland.
3. *(Bonus)* **Stuck window layout** — if Resolve comes back maximized/frameless/off-screen no matter what you do.

No root required. Everything installs into your home directory and is easy to undo.

---

## Symptoms

- Resolve fills the screen but only shows its own in-app menu bar; the desktop
  (KWin) provides no title bar at all. Other KDE apps still have theirs.
- When launching Resolve through XWayland (e.g. to restore the title bar), it
  dies instead: `symbol lookup error ... g_once_init_leave_pointer` /
  `g_module_open_full`.
- Resolve's splash screen ("DaVinci Resolve Studio 21") briefly gets an odd
  generic title bar when this is fixed app-wide.

## Why it happens (the fun part)

**1. Title bar.** Since KDE Plasma **6.6**, KWin asks X11/XWayland apps how
*they* want decorations, using the new `DecorationPolicy`. When an app sets the
`_GTK_FRAME_EXTENTS` hint (Chromium apps do this to draw their own "chrome"),
KWin honors it and draws nothing. [Resolve ≥ 20's Qt build sets that hint
too](https://invent.kde.org/plasma/kwin/-/blob/v6.8.3/src/x11window.cpp) —
`preferredDecorationMode()` then returns `Client` for it, even though the older
`noBorder` flag stays `false`. So KWin politely draws no title bar for a
window that actually wants one.

The fix is KWin's own new rule: force `decorationpolicy=server` for the
window class `resolve` — scoped with a title match so real, titled Resolve
windows get the bar while the (deliberately frameless) splash screen keeps its
custom look.

**2. Launch crash.** Resolve ships an **old private copy of GLib**. On
XWayland, its Qt loads the system GTK/pango stack (for the platform theme),
which binds to the *bundled* old GLib instead of the modern system one — and
calls a symbol the old GLib doesn't have. Preloading your system's
`libglib`, `libgobject`, `libgio` and `libgmodule` forces every library to use
the system GLib, which is backwards-compatible. The title bar and this preload
together make XWayland the stable way to run Resolve on Plasma 6.

**3. Layout cache.** Resolve persists its window layout, including an
undecorated/misplaced state, in `~/.local/share/DaVinciResolve/.ui.cache.db`.
Removing it makes Resolve rebuild its default layout (projects are unaffected).

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZebyWebby/davinci-resolve-plasma6-fixes/main/install.sh)
```

or clone first:

```bash
git clone https://github.com/ZebyWebby/davinci-resolve-plasma6-fixes
cd davinci-resolve-plasma6-fixes
bash install.sh
```

Options:

```bash
bash install.sh --rule-only     # only the KWin title-bar rule (keeps native Wayland)
bash install.sh --reset-layout  # additionally reset the UI layout cache
```

Then: **quit Resolve (Ctrl+Q) and start it again from your app menu.**

### What the script does

| Step | What | Where |
|---|---|---|
| 1 | Adds a KWin rule: decoration policy **forced to `server`** for window class `resolve` (title contains `DaVinci Resolve`), then tells KWin to reconfigure — the bar appears **live, even while Resolve is running** | `~/.config/kwinrulesrc` |
| 2 | Installs a launcher override that starts Resolve on **XWayland** with the **system GLib preloaded** | `~/.local/share/applications/com.blackmagicdesign.resolve.desktop` |
| 3 | Optionally moves the UI layout cache aside (`--reset-layout`) | `~/.local/share/DaVinciResolve/` |

The system launcher in `/usr/share/applications/` is never modified, so
uninstalling restores stock behavior.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ZebyWebby/davinci-resolve-plasma6-fixes/main/uninstall.sh)
```

## Requirements & tested with

- KDE Plasma / KWin **6.6+** for the decoration-policy rule (tested on **6.8.3**)
- DaVinci Resolve Studio **21.0.0** (build 48) — tested, Nov 2026, CachyOS (Arch)
- Wayland session; the KWin rule part is KDE-specific. GNOME users: only the
  XWayland/preload launcher part (manual excerpt below) applies. PRs welcome.

## Manual install (no script)

<details>
<summary>Step by step</summary>

**Title bar rule** (Plasma 6.6+):

```bash
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations \
  --key Description "DaVinci Resolve Studio - always draw server-side title bar"
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key Enabled true
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key wmclass resolve
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key wmclassmatch 2
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key wmclasscomplete false
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key title "DaVinci Resolve"
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key titlematch 2
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key decorationpolicy server
kwriteconfig6 --file kwinrulesrc --group davinci-resolve-decorations --key decorationpolicyrule 2
gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure
```

(`2` = `SubstringMatch`, and rule type `2` = `Force`.)

**Launcher** (`~/.local/share/applications/com.blackmagicdesign.resolve.desktop`):

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=DaVinci Resolve
GenericName=DaVinci Resolve
Comment=DaVinci Resolve on XWayland with system GLib preloaded (title bar + crash fix)
Path=/opt/resolve/
Exec=env QT_QPA_PLATFORM=xcb LD_PRELOAD="/usr/lib/libglib-2.0.so.0:/usr/lib/libgobject-2.0.so.0:/usr/lib/libgio-2.0.so.0:/usr/lib/libgmodule-2.0.so.0" /opt/resolve/bin/resolve %u
Terminal=false
MimeType=application/x-resolveproj;
Icon=/opt/resolve/graphics/DV_Resolve.png
StartupNotify=true
```

(`install.sh` auto-detects the correct lib dir, e.g. `/usr/lib64` or
`/usr/lib/x86_64-linux-gnu` on other distros.)

**Layout cache reset** (with Resolve closed):

```bash
mv ~/.local/share/DaVinciResolve/.ui.cache.db ~/.local/share/DaVinciResolve/.ui.cache.db.bak
```

</details>

## Troubleshooting

- **Still no title bar after install?** Check that the rule exists in
  *System Settings → Window Management → Window Rules* → "DaVinci Resolve
  Studio – always draw server-side title bar", and that your window class is
  really `resolve` (open the rule editor and use the window-picking tool).
- **Crash persists with a *different* missing symbol?** The same pattern
  applies: find which system library calls it and preload the system copy. The
  four GLib-family libraries cover the common cases (tested end-to-end).
- **Window still stuck frameless/off-screen?** Add `--reset-layout`.
- **You want the splash to have a bar too** (weirdo 😄): in the rule editor,
  remove the `title` match — the rule then applies to the whole application.

## How this was diagnosed

Window-geometry probes through KWin's D-Bus scripting interface showed Resolve
as an X11 window with `frame == client` (no decoration reserved) while
`noBorder == false`, which pointed away from classic causes; reading KWin
6.8.3's `x11window.cpp` revealed the new `DecorationPolicy` +
`_GTK_FRAME_EXTENTS` "CSD detection" behavior, and `rulesettings.kcfg` gave the
exact rule keys above. The glib clash was caught in the systemd journal at the
first XWayland launch attempt.

## License

MIT — see [LICENSE](LICENSE).
