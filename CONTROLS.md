# Spinel Controls

A cheat sheet for learning Spinel's keyboard and mouse controls.

---

## Symbol legend

| Symbol | Key | Where it is on a Mac keyboard |
| :---: | --- | --- |
| **⌥** | Option (Alt) | Bottom row, between Control and Command |
| **⇧** | Shift | Left and right of the letter rows |
| **⌃** | Control | Bottom row, far left (next to fn 🌐) |
| **⌘** | Command | Bottom row, either side of the space bar |
| **,** | Comma key | Right of M |
| **.** | Period key | Right of the comma |
| **Space** | Space bar | |

**How to read a shortcut:** hold down every modifier key (⌥ ⇧ ⌃ ⌘) first, then tap the
letter. For example, **⌥⇧L** means *hold Option and Shift, then press L*.

---

## The one idea to remember: H J K L are arrows

Spinel uses the Vim arrow keys. Your right hand rests on them:

```
   H        J        K        L
   ←        ↓        ↑        →
  left     down      up     right
```

The modifier you hold chooses **what** happens. The letter chooses **which direction**:

| Hold | + H J K L does… |
| --- | --- |
| **⌥** | **Focus**: jump to the window in that direction |
| **⌥⇧** | **Move**: carry the focused window in that direction |
| **⌥⌃** | **Resize**: change the focused window's size |

**The arrow keys work too.** Anywhere this sheet says H / J / K / L, you can use
← / ↓ / ↑ / → instead (for example **⌥←** = **⌥H**, **⌥⇧→** = **⌥⇧L**, **⌥⌃↓** = **⌥⌃J**).

> **Heads-up:** in text editors, ⌥← / ⌥→ normally jump one word and ⌥⇧← / ⌥⇧→ select one
> word. While Spinel runs, the arrow-key shortcuts move between windows instead. If you
> miss the word-jumping, delete the `alt-left` / `alt-right` / `alt-shift-left` /
> `alt-shift-right` lines from your config.

---

## 1. Moving focus (choosing a window)

| Keys | What it does |
| --- | --- |
| **⌥H** | Focus the window to the **left** |
| **⌥J** | Focus the window **below** |
| **⌥K** | Focus the window **above** |
| **⌥L** | Focus the window to the **right** |
| **⌥ ,** | Focus the **previous** display |
| **⌥ .** | Focus the **next** display |

> At the edge of a screen, ⌥H/J/K/L continues onto the neighboring display.

---

## 2. Moving windows

| Keys | What it does |
| --- | --- |
| **⌥⇧H** | Swap the window with its neighbor on the **left** |
| **⌥⇧J** | Swap the window with its neighbor **below** |
| **⌥⇧K** | Swap the window with its neighbor **above** |
| **⌥⇧L** | Swap the window with its neighbor on the **right** |

> At the edge of a screen, the window moves **onto the next display** in that direction.

---

## 3. Moving windows between screens

| Keys | What it does |
| --- | --- |
| **⌥⇧ .** | Send the window to the **next** display |
| **⌥⇧ ,** | Send the window to the **previous** display |
| **⌥⇧H / ⌥⇧L** | At a screen edge, push the window onto the display to the left / right |
| **⌥⇧J / ⌥⇧K** | At a screen edge, push the window onto the display below / above |

"Next" and "previous" go through your displays **left to right**, as arranged in
System Settings → Displays, and wrap around at the end.

> A screen showing a **fullscreen app** can't receive windows. That Space belongs to macOS.

---

## 4. Resizing

| Keys | What it does |
| --- | --- |
| **⌥⌃L** | Make the window **wider** |
| **⌥⌃H** | Make the window **narrower** |
| **⌥⌃J** | Make the window **taller** |
| **⌥⌃K** | Make the window **shorter** |
| **⌥⇧B** | **Balance**: make all windows on this screen equal again |

> Each press changes the size by 60 points (set by `resizeStep` in the config).

---

## 5. Layout

| Keys | What it does |
| --- | --- |
| **⌥E** | **Flip the split**: switch between side-by-side ◫ and stacked ⊟ |
| **⌥M** | Switch this Desktop between **Tiling** and **Monocle** |
| **⌥F** | **Zoom**: make the window fill the screen; press again to undo |
| **⌥⇧F** | **Native macOS fullscreen** on or off (the window gets its own Space) |
| **⌥⇧Space** | **Float** the window (take it out of the tiling), or tile it again |

**Tiling vs Monocle**

- **Tiling (BSP):** windows share the screen. Each new window splits the focused one in half.
- **Monocle:** every window is full-size, stacked on top of each other.
  In monocle, **⌥H/⌥K** go to the previous window and **⌥L/⌥J** go to the next.

---

## 6. Control

| Keys | What it does |
| --- | --- |
| **⌥⇧T** | **Pause / resume** tiling (use this if something misbehaves) |
| **⌥⇧R** | **Retile**: rebuild every layout from scratch |

---

## 7. Mouse

| Action | What it does |
| --- | --- |
| Drag a window **onto another window** | The two windows **swap** places |
| Drag a window **onto another screen** | It **joins that screen's** layout |
| Drag a window's **edge** | **Resizes the split**, and the neighbors adjust |

---

## 8. Native macOS controls (these still work)

Spinel keeps the normal Mac Desktops. Each Desktop on each screen has its own layout.

| Keys / gesture | What it does |
| --- | --- |
| **⌃←** / **⌃→** | Previous / next Desktop |
| Three- or four-finger swipe left/right | Previous / next Desktop |
| **⌃↑** or **F3** | Mission Control (drag windows between Desktops here) |

---

## Practice plan

1. **Day 1, focus:** use only **⌥H J K L** to jump between windows. Don't touch the mouse.
2. **Day 2, move:** add **⌥⇧H J K L** to rearrange windows and **⌥⇧ , .** to throw them
   between screens.
3. **Day 3, size:** add **⌥⌃H J K L**, then **⌥⇧B** to reset.
4. **Day 4, layout:** try **⌥E** (flip), **⌥F** (zoom), **⌥M** (monocle) and **⌥⇧Space** (float).

---

## Changing the shortcuts

Shortcuts live in `~/.config/spinel/config.json` under `"bindings"`:

```json
"bindings": {
  "alt-h": "focus left",
  "alt-shift-l": "move right"
}
```

Modifier names are `alt` (⌥), `shift` (⇧), `ctrl` (⌃) and `cmd` (⌘). After editing, click the
menu bar icon → **Reload Config**.

> **Note:** while Spinel is running, Option+letter shortcuts replace the special characters
> those keys normally type (for example, ⌥E normally starts an accent like é).
