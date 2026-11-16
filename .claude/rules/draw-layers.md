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

The fade must sit above the HUD (or the XP bar shows through the black) and below the pause menu (or pausing mid-crossing hides the menu under the black). A new `CanvasLayer` picks its slot from this table. Members of the same group may share the group's number; where they overlap, tree order decides. For a fixed order inside a group, use a free number in its ten (11–19 for the HUD, for example). Never use another group's number.

**Inside the world sheet, `z_index` order** (effective values; relative z sums with the parent — `YSortContainer` is z 0, so inside it the written value is the effective one):

| Effective z | What |
|---|---|
| 0 | **floor** — ground tiles and other ground objects. Colliders do not move a tile out of here: a non-navigable ground tile with colliders (for example `road_01_block`) stays at 0 because the drawing asks for it |
| 1 | above the floor, below everything else — for example the entities' shadows (`shadow_01.tscn`, written z −3, relative to the entity's 4) and the Barrier |
| 2 | **scenery behind the entities** (players, enemies, XP items) — for example `building_01` and `tech_01`. Neither collision nor navigation decides this level; only being behind the entities does |
| 3 | decoration laid over the z-2 scenery, still behind the entities — for example `tech_signs_01`, `occlusion_shadow_01`. Normally no collision or navigation |
| **4** | **the Y-sort level** — everything that trades occlusion by Y inside the `YSortContainer`: players, enemies, XP items, chambers, and tiles that Y-sort with them (for example `street_objects_01`) |
| 5 | **front tiles** (normally the `*_front` sources), always above the entities; this is where the silhouettes of bodies behind scenery show (`FrontTiles.MIN_Z`, see *Occlusion silhouette*) |
| 6 | decoration over the front tiles — for example `occlusion_shadow_01_front`, `tech_signs_01_front`. Normally no collision or navigation |
| 7 | invisible spacers (for example `block_01`); when shown for editing, above all the scenery |
| 9 | overhead `HealthBar` and `HealthLabel` — written z 5, relative to the player's 4 |
| **50 (absolute)** | **occlusion silhouette** (see *Occlusion silhouette*) |
| **51–59** | **visual effects** — for example `impact_01.tscn`: root `z_index = 51`, its `AnimatedSprite2D` at 0 (so the number lives in one place); added to the enemy's parent, the container, so it stays at **51**. Above the silhouette (drawn after the snapshot, so a death effect bursting over the player no longer lights the player's outline) and below powers |
| **60+** | **every power** — `z_index = 60` on each power scene's root, relative (60 loose in the container, 62 when attached to the player) |
| **100 (absolute)** | **spawn debug overlay** (`debug_draw_overlay`, only when `debug_draw_enabled` is on) — above everything in the world, but under the HUD and menus, which are `CanvasLayer`s |

**Levels 0–9 follow one criterion: what must be in front of or behind the entities**, never whether a tile has collision or navigation. Tiles take their level per tile in the TileSet (see *Y-sort*). **Moving the Y-sort level moves every participant at once**: the root of each player, enemy, XP item and chamber scene, and the per-tile z of every tile that Y-sorts with them. A participant left behind no longer ties, so it always wins or always loses, whatever its Y. A forgotten character showed this once: it only appeared after a chamber swap, because only then did that scene enter the game. `FrontTiles.MIN_Z` must stay one above the Y-sort level.

**Rule: every power scene uses `z_index = 60`** on its root, set in the Inspector like the rest of the power calibration. It does two jobs: powers always draw above players, enemies and scenery (the design intent), and they draw **after** the silhouette took its screen snapshot, so they never trigger it. A new power left at a low z makes the silhouette flicker whenever it crosses a body — visible at once, not silent.
