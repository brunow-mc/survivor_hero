---
paths:
  - "autoload/fade.*"
  - "ui/**"
  - "entities/effects/**"
  - "debug/**"
  - "scripts/pause_menu.gd"
  - "scripts/game_over_menu.gd"
  - "scripts/level_up_ui.gd"
---

### Screen fade (`FadeGlobal`)

**`autoload/fade.tscn`**: a `CanvasLayer` (layer 50) with one full-rect black `ColorRect` named `Overlay` (`mouse_filter = Ignore`, so the invisible layer never swallows clicks in the mouse-driven level-up menu; hidden except during a fade). It is an autoload **scene** because the stage door fades out in one scene and fades in in the next — a per-scene fade would die halfway.

- **API:** `await FadeGlobal.fade_out(seconds)`, `await FadeGlobal.fade_in(seconds)`, `clear()`. A tween animates `Overlay.modulate.a`.
- **The caller is the conductor, the fade is the instrument.** The fade decides only *how* to darken; *when*, *for how long* and *what happens in the dark* belong to whoever calls it — the room door's durations are its own constants (`HOLD_BEFORE_MOVE` = fade-out, `HOLD_AFTER_MOVE` = fade-in), and that is where they are calibrated. The same fade serves every caller, each with its own numbers — doors and the chamber, for example.
- **It freezes nothing.** Covering the screen and holding the player are separate pieces: a door asks `HoldGlobal` *and* `FadeGlobal`; a boss entrance may hold without darkening.
- The tween is bound to the fade node, which inherits the tree's pause — so **a fade waits while the pause menu is open**, like `HoldGlobal`'s waits, and the menu draws above the black (layer 90 vs 50).
- **Every scene change fades** — stage door, restart, Main Menu — through the same `GameStateGlobal._go()` sequence (see *Scene changes*): the black survives the swap and fades in once the new scene is in place. `clear()` is only the failure path (an invalid destination), never the normal one.
- **`fade_out(seconds, while_paused = false)`.** By default the tween pauses with the tree (a door's fade waits while the pause menu is open). `true` makes it run on a **paused** tree — needed when the fade starts *from* a menu (pause menu restart, game over), or the tween would never advance. Callers never pass it by hand: `_go()` detects `get_tree().paused` and passes it.

### Draw layers (`CanvasLayer.layer` vs `z_index`)

Godot has **two unrelated things called "layer"**. `CanvasLayer.layer` stacks **whole sheets**; `z_index` orders items **inside one sheet** (and is the one that sums with the parent via `z_as_relative`, see *Y-sort*). The entire world — tiles, player, enemies, items — lives on the implicit sheet **0** and is ordered by `z_index`; any `CanvasLayer` above 0 covers that whole sheet regardless of `z_index`. That is why the HUD on sheet 10 is always above scenery tiles at `z_index` 4: different rulers, not tree order. **The world never consumes `CanvasLayer` numbers.**

Convention — groups spaced in tens so new layers fit between them:

| `CanvasLayer.layer` | Group |
|---|---|
| 0 | the world (implicit; ordered by `z_index`) |
| 10 | HUD — `XPBar`, `LoadoutBar` |
| 50 | `FadeGlobal` |
| 90 | menus — `PauseMenu`, `GameOverMenu` |
| 100 | `LevelUpUI` |
| 110 | `DebugDrawOverlay` — above everything; it used to sit at 100, tied with `LevelUpUI`, and a tie is broken by tree order, which is fragile |

The fade must sit above the HUD (or the XP bar shows through the black) and below the pause menu (or pausing mid-crossing hides the menu under the black). A new `CanvasLayer` picks its slot from this table. Members of the same group may share the group's number; where they overlap, tree order decides. For a fixed order inside a group, use a free number in its ten (11–19 for the HUD, for example). Never use another group's number.

**Inside the world sheet, `z_index` order** (effective values; relative z sums with the parent — `YSortContainer` is z 0, so inside it the written value is the effective one):

| Effective z | What |
|---|---|
| 0 | floor and, normally, back tiles |
| 2 | entities in the `YSortContainer`, and tiles that Y-sort with them inside it |
| 4 | front tiles (per-tile z 4 in the TileSet), always above the entities |
| **50 (absolute)** | **occlusion silhouette** (see *Occlusion silhouette*) |
| **51–59** | **visual effects** — for example `impact_01.tscn`: root `z_index = 51`, its `AnimatedSprite2D` at 0 (so the number lives in one place); added to the enemy's parent, the container, so it stays at **51**. Above the silhouette (drawn after the snapshot, so a death effect bursting over the player no longer lights the player's outline) and below powers |
| **60+** | **every power** — `z_index = 60` on each power scene's root, relative (60 loose in the container, 62 when attached to the player) |

**Rule: every power scene uses `z_index = 60`** on its root, set in the Inspector like the rest of the power calibration. It does two jobs: powers always draw above players, enemies and scenery (the design intent), and they draw **after** the silhouette took its screen snapshot, so they never trigger it. A new power left at a low z makes the silhouette flicker whenever it crosses a body — visible at once, not silent.
