# TileMyMac

A tiling window manager for macOS that works *with* the Mac instead of around it.

Most macOS tilers either ask you to disable SIP (yabai) or replace native Spaces with their
own virtual workspaces (AeroSpace). TileMyMac does neither:

- **Native Spaces stay native.** Every Desktop on every display gets its own layout. Switch
  with Ctrl-←/→, Mission Control or trackpad swipes as usual; each Desktop keeps its layout.
- **Native fullscreen is respected.** Fullscreen apps and Split View live in their own Spaces,
  which TileMyMac leaves alone. When an app leaves fullscreen it slides back where it was.
- **Each display is independent**, whether or not "Displays have separate Spaces" is on.
  The menu bar, notch and Dock are respected per display.
- **The mouse still works.** Drag a tiled window onto another to swap them, onto another
  display to move it there, or drag its edge to resize the split.
- **No SIP changes, no Input Monitoring.** Only the Accessibility permission.

## Install

**Download:** grab `TileMyMac-<version>.zip` from
[Releases](https://github.com/PzmuV1517/TileMyMac/releases), unzip it and move
`TileMyMac.app` to Applications. The app isn't notarized yet, so the first time, right-click it
→ **Open** (or System Settings → Privacy & Security → **Open Anyway**).

**From source:**

```sh
make install     # builds, signs, copies to /Applications and launches
```

On first launch, grant Accessibility access when asked (System Settings → Privacy & Security →
Accessibility). The menu bar icon shows the current Desktop number and layout.

Other targets: `make test`, `make run` (launch from `build/`), `make diagnose` (print what
TileMyMac sees of your displays and Spaces).

## Default keys

| Keys | Action |
| --- | --- |
| ⌥ H J K L | Focus window left / down / up / right (crosses displays) |
| ⌥⇧ H J K L | Move window (at a display edge, moves onto the next display) |
| ⌥⌃ H / L | Shrink / grow width |
| ⌥⌃ K / J | Shrink / grow height |
| ⌥ E | Flip the split (side by side ↔ stacked) |
| ⌥⇧ B | Balance windows |
| ⌥ M | Toggle BSP / monocle layout for this Desktop |
| ⌥ F | Zoom the window to fill the Desktop (toggle) |
| ⌥⇧ F | Native macOS fullscreen (toggle) |
| ⌥⇧ Space | Float / tile the focused window |
| ⌥ , / . | Focus previous / next display |
| ⌥⇧ , / . | Move window to previous / next display |
| ⌥⇧ T | Pause / resume tiling |
| ⌥⇧ R | Retile everything from scratch |

The arrow keys work in place of H J K L everywhere (⌥←, ⌥⇧→, ⌥⌃↓…). Keys are physical positions, so they work with any keyboard layout.

## Configuration

`~/.config/tilemymac/config.json` is created on first launch. Every key is optional.

```json
{
  "gaps": { "inner": 8, "outer": 8 },
  "defaultLayout": "bsp",
  "resizeStep": 60,
  "mouseFollowsFocus": false,
  "floatApps": ["com.apple.systempreferences", "com.apple.calculator"],
  "rules": [
    { "app": "Finder", "title": "^(Copy|Move)", "float": true },
    { "app": "com.apple.Music", "float": true }
  ],
  "bindings": {
    "alt-h": "focus left",
    "alt-ctrl-l": "resize width 120",
    "cmd-alt-m": "layout monocle"
  }
}
```

Reload from the menu bar (⌘R in the menu) or bind `reload-config`.

**Commands:** `focus <dir>`, `move <dir>`, `grow|shrink <width|height>`,
`resize <width|height> <±points>`, `toggle-split`, `balance`, `toggle-float`, `zoom`,
`fullscreen`, `layout <bsp|monocle|toggle>`, `focus-display <next|previous|dir>`,
`move-to-display <next|previous|dir>`, `toggle-tiling`, `retile`, `reload-config`.

**Modifiers:** `cmd`, `alt`/`opt`, `ctrl`, `shift`. **Keys:** letters, digits, `left`/`right`/`up`/`down`,
`return`, `space`, `tab`, `escape`, `minus`, `equal`, `comma`, `period`, `slash`, `semicolon`,
`quote`, `grave`, `leftbracket`, `rightbracket`, `backslash`, `f1`–`f12`.

## What floats

Dialogs, sheets, panels, palettes, windows that can't be resized, windows shown on all Desktops,
minimized windows, hidden apps, and anything matched by `floatApps` or a `rules` entry with
`"float": true`. A rule with `"float": false` forces tiling.

## Recommended macOS settings

- **Stage Manager off.** TileMyMac pauses itself while it is on.
- **System Settings → Desktop & Dock → "Drag windows to screen edges to tile" off**, so macOS
  Sequoia+ native tiling doesn't fight the layout.
- **"Automatically rearrange Spaces based on most recent use" off**, so Desktop numbers stay put.

## Roadmap

- Move a window to another Desktop by keyboard (needs care without SIP)
- Native-feeling animations
- `tilemymac` CLI for scripting (Raycast, Shortcuts, skhd)
- Master/stack layout, per-Desktop gap overrides
- Remember layouts across restarts
