# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Survivor Hero** — Vampire Survivors-style game built in **Godot 4.7.2** (GDScript). Viewport: 480×270, pixel art (no texture filtering). No CLI build or test system; everything runs through the Godot Editor.

## Running the game

Open `project.godot` in Godot 4.7.2 and press F5 (or the play button). The main scene is `stages/stage_01.tscn`.

There are no automated tests. Manual playtesting is the only validation method.

## Architecture overview

### Autoloads (singletons — always available globally)

| Name | File | Purpose |
|---|---|---|
| `GameStateGlobal` | `autoload/game_state.gd` | Central FSM (COMBAT / UPGRADE / PAUSED / PLAYER_DEAD). Also owns player health. |
| `XPManagerGlobal` | `autoload/xp_manager.gd` | XP accumulation, level-up signal, selectable level-up curve (LINEAR/EXPONENTIAL/FIXED/POWER — see XP & Level-up flow). |
| `LevelUpManagerGlobal` | `autoload/level_up_manager.gd` | Generates upgrade options on level-up, pauses game, delegates to controllers. |
| `SpawnManagerGlobal` | `autoload/spawn_manager.gd` | Budget-based enemy spawn with grid sampling and teleport system. |
| `PowerUpStatsGlobal` | `autoload/power_up_stats.gd` | Flat store for computed player stats (damage, armor, cooldown reduction, etc.). Emits `stats_changed`. |
| `AudioManagerGlobal` | `autoload/audio_manager.gd` | Central SFX playback (2D and positional). |
| `InputManagerGlobal` | `autoload/input_manager.gd` | Input abstraction. |
| `TargetTrackerGlobal` | `autoload/target_tracker_global.gd` | Tracks recently-targeted enemies to prevent repetition (used by homing attacks). |
| `PlayerRosterGlobal` | `autoload/player_roster.gd` | Which characters exist and which one is chosen. Read by `PlayerSpawner` (see Player). Future home of character unlocks. |
| `HoldGlobal` | `autoload/hold.gd` | Brief holds: freezes *specific* parts of the game for an instant (a door crossing, for example). See *Brief holds*. |
| `FadeGlobal` | `autoload/fade.tscn` (+ `fade.gd`) | Fades the screen to black and back. Registered as a **scene**, not a script, so its visual node exists and survives scene changes. See *Screen fade*. |

**Suspending the player is the GameplayState's job, never the progression's.** A safe house, a dialogue or a cutscene wants "you still have your level-5 Fire, it just doesn't fire *now*" — that is `is_combat_allowed()`, a temporal gate the attacks, contact damage and XP pickup all already consult. It is **not** `remove_powerup()` or anything that writes `current_level = 0`: those erase what the player earned and would need a save-and-restore layer to undo. Progression answers *how much you have*; the state answers *what may happen right now*. Don't mix the two axes.

**`is_combat_allowed()` is a BLOCKLIST, so every new state is born with combat ALLOWED.** `EXPLORATION` sat in the enum for a long time without being in that list — entering it would have blocked nothing, and the safe house would have had the player attacking. When adding a state (`SHOP`, `BOSS_INTRO`…), add it to the list in the same pass. (An allowlist — `current_state in [COMBAT]` — would fail safe instead, since forgetting would read as "the player can't attack", visible in seconds, rather than "the player attacked during the cutscene", which hides. Deliberately unchanged for now: most of the game is combat. Revisit before `DIALOGUE` and `CUTSCENE` are actually entered.)

**Critical gate:** `GameStateGlobal.is_combat_allowed()` returns `false` during PAUSED, UPGRADE, CUTSCENE, DIALOGUE, EXPLORATION and PLAYER_DEAD. `PLAYER_DEAD` is a terminal state — only `restart_game()` can exit it. **Its consumers are exactly four:** attack firing (`AttackController`), contact damage (`PlayerBase`), XP pickup (`XPItem`) and XP accumulation (`XPManager`). **Spawning, enemy movement and XP-item magnet movement do NOT consult it** — they stop only when the whole tree is paused (`get_tree().paused`), which PAUSED and UPGRADE do and EXPLORATION does not. So a stage in EXPLORATION that still has a `SpawnManagerConfig` produces a "ghost mode": the horde spawns and chases, XP items follow the player forever without ever being collected (the gate covers the *pickup*, not the approach), nobody can hurt anybody. Verified in play, and **correct for what exists** — a real safe house has no spawner and no enemies dropping items, so none of it is reachable there. It becomes a real decision only for a future **mixed** stage (a safe zone inside a combat map), where items already on the ground would hover and then all be collected at once when combat resumes. Treat "which systems should EXPLORATION freeze?" as an open design question, not as three separate bugs.

**"Freeze" is actually THREE things, with different mechanisms — do not bundle them.** **Tap** = stop *creating* (spawn); **brake** = stop what already exists from acting (enemy movement, XP-item approach); **purge** = *remove* what already exists (enemies, items on the ground). Tap and brake are states and fit `is_combat_allowed()` — a consumer asks a question. **Purge cannot be a boolean at all:** a state says "what may happen now", never "what should happen at the moment of the switch", so it belongs to the `state_changed` signal, i.e. to the trigger that caused the transition. And the modes disagree about it — `CUTSCENE` and `DIALOGUE` want the brake and must **refuse** the purge (the horde has to still be there afterwards), while a between-waves breather wants the purge as the *point* of the mechanic. Two consequences to expect: `state_changed(new_state)` carries only the destination, so a purge handler needs the **previous** state added to it (a signature change touching every listener); and purging via `EnemyBase.die()` would **drop items** exactly while pickup is blocked, so it needs a death without drops. Note the first mixed stage probably needs **only the tap**: a safe room closed off by a `Barrier` separates the horde physically, so brake and purge never become reachable.

**Leaving a transient state returns to where the game WAS, never to a hardcoded COMBAT.** `resume_game()` restores `previous_state`; the level-up menu restores `LevelUpManager._state_before_upgrade`, captured at the moment it opens. The menu keeps its **own** memory instead of reading `previous_state` because that is a single slot any transition overwrites. Two details make it hold: the capture is skipped when already in UPGRADE (chained menus re-enter the opening function, and would otherwise record UPGRADE as the origin), and **pause cannot nest inside this menu at all** — `level_up_ui.gd` swallows the `pause` action in `_input()` while visible, before `InputManager` ever sees it in `_unhandled_input()`. That block has existed since the first commit; reading `InputManager`'s `match` alone suggests pause works everywhere, which is wrong. `restart_game()` is the one deliberate COMBAT write.

**Every stage DECLARES its own mode — `entities/stage_parts/stage_config.tscn` (`scripts/stage_config.gd`).** Instance it in each stage and pick `Gameplay State` on the **instance**. `stage_01` carries one set to `COMBAT`: it used to be COMBAT only because that is the autoload variable's initial value, i.e. by *omission*. The autoload default is deliberately kept as the safety net for scenes that are **not** stages (title screen, game over) — those must not warn for lacking the node.

- **Why it is required, not cosmetic:** `GameStateGlobal` is an autoload, so the state **survives a scene change**. Without a per-stage declaration a stage inherits the previous one's mode — leaving a safe house in EXPLORATION would hand the next combat stage a run with attacks, damage and XP all blocked, silently.
- **It declares in `_enter_tree()`**, same reasoning as *NavmeshMerger*: every `_enter_tree()` runs before any `_ready()`, so the mode is set before the player, `AttackController` and `SpawnManager` start — **regardless of where the node sits in the stage tree**. Verified in the console: its line prints before every other init line.
- **The `@export` exposes the WHOLE `GameplayState` enum on purpose.** Restricting it to COMBAT + EXPLORATION was proposed and rejected as an artificial limit: a title/intro stage can legitimately open in CUTSCENE, a purely narrative scene in DIALOGUE, and future states (SHOP, BOSS_INTRO…) appear in the list without touching the script. Typing the export as `GameState.GameplayState` (the `class_name` on `game_state.gd`) is what gives a real Inspector dropdown **without duplicating the state names** — never re-list them in an `@export_enum`.
- **Only three values are refused, for mechanical reasons, in `FORBIDDEN_STATES`:** `UPGRADE` (owned by `LevelUpManager`, which pauses the tree expecting to close a menu later — a stage born there has no menu to close), `PAUSED` (`pause_game()` changes the enum **and** pauses the tree; declaring it via `set_state()` would do only the first, and `resume_game()` only exits from it) and `PLAYER_DEAD` (terminal — `set_state()` itself refuses to leave it). The node `push_warning`s and **does not apply** the mode, leaving the game running.
- `restart_game()` (through `_go()`) leaves the menu state for COMBAT *before* `reload_current_scene()`, and the reloaded stage then re-declares its own mode — verified in play, so a safe house survives a restart correctly.
- **`start_hold_seconds`** (group *Start*, default `0` = off): the stage-start hold — seconds of frozen hesitation (player, attack start, enemies, spawn clock) **after** the screen clears. Calibrated per stage on the instance; the safe house leaves it at 0. See *Brief holds*.
- **New stage checklist (state):** instance `stage_config.tscn` anywhere in the stage and set `Gameplay State` (and, if wanted, `Start Hold Seconds`) on that instance. Never set it on the base scene — that value would leak into every stage (same rule as `SpawnManagerConfig`).

### Brief holds (`HoldGlobal`) — the one pattern for every short pause

"Pause" means **three different things** in this game, and only the third is `HoldGlobal`'s:

| What stops | Examples | Owner |
|---|---|---|
| **Everything** — the whole tree | pause menu, level-up menu | `get_tree().paused`, owned by `GameStateGlobal` |
| **Combat** — nobody hurts anybody, no XP | safe house, dialogue, cutscene | `is_combat_allowed()`, driven by `GameplayState` |
| **Something specific, for an instant** | door crossing, stage start, boss entrance, chamber swap | **`HoldGlobal`** |

It is deliberately **not** called "pause": that word already names the `PAUSED` state and the paused tree.

**How to ask.** Each request names **what** it freezes (one or more `Scope` bits) and gets a **ticket**; requests overlap, and a scope is free only when every request holding it has been released. `hold(scopes, reason)` + `release(ticket)` when the end is an event (fade finished, boss animation over), `hold_for(scopes, seconds, reason)` when it is only time. Consumers ask `is_held(scope)` — a bit test against a cached mask, cheap enough per enemy per frame. **Durations live with whoever asks, never in `HoldGlobal`.**

**Scopes exist in code ONLY with a consumer.** A declared scope nobody consults is an empty promise — someone asks for "enemies" and nothing happens, silently (the lesson of the deleted caller-less API, see *Debug and test systems*). Each new scope enters `HoldGlobal.Scope` **in the same pass as its consumer**.

**Two sets exist:** `TRANSITION = PLAYER_INPUT | ENEMIES | SPAWN_CLOCK` (doors) and `SCENE_ARRIVAL = TRANSITION | ATTACKS` (whoever must also hold the start of the attacks). `ATTACKS` must **never** join `TRANSITION`: doors do not interrupt attacks, by decision.

Full rules: `.claude/rules/brief-holds.md`. It loads by itself with `autoload/hold.gd` and `StageConfig`; read it first when discussing a hold without opening them. Covers why not to use the tree pause or a new state, a player left frozen, a hold ending too early, what each scope freezes, the stage-start hold, enemies or spawn not stopping at a door, attacks starting before the screen clears, time-stop ideas for a boss or hitstop, the Bo coming back from another room, and powerups that act over time.

### Screen fade (`FadeGlobal`)

**`autoload/fade.tscn`**: a `CanvasLayer` (layer 50) with one full-rect black `ColorRect` named `Overlay` (`mouse_filter = Ignore`, so the invisible layer never swallows clicks in the mouse-driven level-up menu; hidden except during a fade). It is an autoload **scene** because the stage door will fade out in one scene and fade in in the next — a per-scene fade would die halfway.

- **API:** `await FadeGlobal.fade_out(seconds)`, `await FadeGlobal.fade_in(seconds)`, `clear()`. A tween animates `Overlay.modulate.a`.
- **The caller is the conductor, the fade is the instrument.** The fade decides only *how* to darken; *when*, *for how long* and *what happens in the dark* belong to whoever calls it — the room door's durations are its own constants (`HOLD_BEFORE_MOVE` = fade-out, `HOLD_AFTER_MOVE` = fade-in), and that is where they are calibrated. The same fade will serve the stage door, the chamber and a stage intro, each with its own numbers.
- **It freezes nothing.** Covering the screen and holding the player are separate pieces: a door asks `HoldGlobal` *and* `FadeGlobal`; a boss entrance may hold without darkening.
- The tween is bound to the fade node, which inherits the tree's pause — so **a fade waits while the pause menu is open**, like `HoldGlobal`'s waits, and the menu draws above the black (layer 90 vs 50).
- **Every scene change fades** — stage door, restart, Main Menu — through the same `GameStateGlobal._go()` sequence (see *Scene changes*): the black survives the swap and fades in once the new scene is in place. `clear()` is only the failure path (an invalid destination), never the normal one.
- **`fade_out(seconds, while_paused = false)`.** By default the tween pauses with the tree (a door's fade waits while the pause menu is open). `true` makes it run on a **paused** tree — needed when the fade starts *from* a menu (pause menu restart, game over), or the tween would never advance. Callers never pass it by hand: `_go()` detects `get_tree().paused` and passes it.

### Draw layers (`CanvasLayer.layer` vs `z_index`)

Godot has **two unrelated things called "layer"**. `CanvasLayer.layer` stacks **whole sheets**; `z_index` orders items **inside one sheet** (and is the one that sums with the parent via `z_as_relative`, see *Y-sort*). The entire world — tiles, player, enemies, items — lives on the implicit sheet **0** and is ordered by `z_index`; any `CanvasLayer` above 0 covers that whole sheet regardless of `z_index`. That is why the HUD on sheet 1 is always above scenery tiles at `z_index` 4: different rulers, not tree order. **The world never consumes `CanvasLayer` numbers.**

Convention — groups spaced in tens so new layers fit between them:

| `CanvasLayer.layer` | Group |
|---|---|
| 0 | the world (implicit; ordered by `z_index`) |
| 10 | HUD — `XPBar`, `LoadoutBar` |
| 50 | `FadeGlobal` |
| 90 | menus — `PauseMenu`, `GameOverMenu` |
| 100 | `LevelUpUI` |
| 110 | `DebugDrawOverlay` — above everything; it used to sit at 100, tied with `LevelUpUI`, and a tie is broken by tree order, which is fragile |

The fade must sit above the HUD (or the XP bar shows through the black) and below the pause menu (or pausing mid-crossing hides the menu under the black). A new `CanvasLayer` picks its slot from this table; never reuse a taken number.

**Inside the world sheet, `z_index` order** (effective values; relative z sums with the parent — `YSortContainer` is z 2):

| Effective z | What |
|---|---|
| 0 | floor and, normally, back tiles |
| 4 | entities in the `YSortContainer` (2 + 2), front tiles (per-tile z 4 in the TileSet) |
| **50 (absolute)** | **occlusion silhouette** (see *Occlusion silhouette*) |
| **51–59** | **visual effects** — `impact_01.tscn`: root `z_index = 51`, its `AnimatedSprite2D` at 0 (so the number lives in one place); added to the enemy's parent, the container, so 51 relative becomes **53**. Above the silhouette (drawn after the snapshot, so a death effect bursting over the player no longer lights the player's outline) and below powers |
| **60+** | **every power** — `z_index = 60` on each power scene's root, relative (62 loose in the container, 64 when attached to the player) |

**Rule: every power scene uses `z_index = 60`** on its root, set in the Inspector like the rest of the power calibration. It does two jobs: powers always draw above players, enemies and scenery (the design intent), and they draw **after** the silhouette took its screen snapshot, so they never trigger it. A new power left at a low z makes the silhouette flicker whenever it crosses a body — visible at once, not silent. (Powers already looked above buildings at z 4 because, loose in the container, 4 relative became 6.)

### Occlusion silhouette — the body shows through whatever covers it

A body covered by something opaque is drawn as a 1-px inner outline with a light fill. Full rules: `.claude/rules/occlusion-silhouette.md`. It loads by itself when the silhouette files are touched; read it first when discussing the silhouette without opening them. Covers outlines that appear or go missing, characters, enemies and items behind buildings, front tiles, the outline colours and their materials.

### Entity anatomy — feet origin + BodyCenter (MANDATORY convention)

Player and every enemy scene follow this layout:

- **Scene origin (root position) = the FEET.** Sprites and enemy colliders are offset upward so `global_position` marks the ground point. Rendering and Y-sort live in this frame.
- **`BodyCenter` (Node2D child) = the centre of the body**, above the origin. Navigation and body-anchored systems live in this frame.
- **Never mix the two frames.** Steering a body-frame point toward feet-frame path points (or vice versa) injects a constant vertical bias that accumulates along paths — enemies visibly "arc" below straight lines. This class of bug cannot be fixed by calibration; fix it by putting the whole pipeline in one frame.
- **Anything that needs to know where a body is uses `get_body_center_position()`** (`EnemyBase` and `PlayerBase`), never `global_position`, which is the FEET and injects a systematic downward bias. Every distance or movement states which frame it uses.

**Position markers degrade gracefully, never crash:** every consumer has a fallback chain ending in a property that always exists. Follow this pattern for any new marker node.

**The contract is "degrade AND warn" — a silent fallback is a bug.** Falling back keeps the game running, but the degradation (e.g. everything silently re-anchoring to the FEET) is nearly invisible in play, so every fallback needs a one-time warning. Two rules make the warnings usable:
- **Warn at initialization, never at the point of use.** Most consumers sit in hot paths (`_enemy_body_position()` runs per targeting call, `_setup_base()` runs per spawn) — a warning there would flood the console.
- **What is born in quantity warns once per *scene*, not per instance**, via a static `Dictionary` guard keyed by `scene_file_path`. A horde of the same enemy must produce **one** warning.

Full rules: `.claude/rules/entity-anatomy.md`. It loads by itself with the enemy and player scripts and scenes, the camera, `AttackController` and `power_05_gear`; read it first when discussing them without opening those files. Covers enemies arcing along paths, stopping or attacking at the wrong distance, navigation anchored on the wrong point, attacks spawning off-centre, the gear orbit, a missing marker and what each startup warning means.

### Y-sort (2.5D depth illusion)

Entities and scenery tiles occlude each other by Y position (feet origin = the sort line). Three requirements, ALL mandatory:

1. **Same `z_index`** — Y-sort only breaks ties within one z level; a different z overrides it. The world standard is **`z_index = 2`** (`z_as_relative = true`): player, enemies, XP items set it on the scene root; TileMap layers get it **per-tile in the TileSet** (setting it on the TileMapLayer node in the Inspector does NOT work for this — leave the layer at z 0 and paint z 2 inside the TileSet tiles).
2. **`y_sort_enabled = true`** on the entity root and on participating TileMap layers.
3. **Being a child of the Y-sort container** — Y-sort only sorts CHILDREN of a `y_sort_enabled` parent. Each stage instances **`entities/stage_parts/y_sort_container.tscn`** (a configured, permanently-empty Node2D `YSortContainer`: z 2, relative, y-sort on). **The membership criterion is functional and single: anything that needs variable occlusion along the Y axis (Godot's Y-sort) goes inside the container; anything that doesn't stays outside.**
   - **Player and enemies always belong to the container** (they always need variable occlusion), and **both now join at runtime**: the player via `PlayerSpawner`, enemies via `SpawnManager` (see next paragraph). Both resolve the container by the `YSortContainer` group, so a stage wires nothing. No player is placed in a stage tree any more.
   - **TileMap layers are case-by-case**, decided per layer by whether they need to trade occlusion with entities. **No layer trait decides this**: having collision does not determine participation (`TileMapDecoration` itself has colliders and is inside), having navigation does not either, and tiles with neither collision nor navigation don't either. Only the functional criterion decides.
   - **Expect TileMaps both inside and outside the container within the same stage.** Typically a floor layer does not need variable occlusion and stays outside — that is the only "normal" case; no other TileMap name should be treated as fixedly inside or outside.

   Content placed in the editor inside the instance belongs to the stage file; never add children to the base scene `y_sort_container.tscn` (they would be shared across every stage).

   **Why the container matters for spawned enemies:** the effective z of an entity is `parent_z + own_z`. Player and enemies are all `z_index = 2` (relative), so inside the container they land at `2 + 2 = 4` and Y-sort tie-breaks them by Y. If enemies were parented to the scene root instead (z 0) they would land at effective z `0 + 2 = 2` — **below** the player's 4 — and the player would render permanently in front of every enemy.

   **The container is resolved automatically by group — no per-stage wiring.** The base scene `y_sort_container.tscn` carries the group **`YSortContainer`**, so every instance in every stage is already in it. `SpawnManagerConfig.initialize_spawn_manager()` resolves in cascade: the `enemy_container` export (explicit override) → `get_first_node_in_group("YSortContainer")` → nothing (one `push_warning`). **Leave the export empty in the normal case**; fill it only to disambiguate a stage with more than one container. This replaced a manual drag-and-drop step whose omission broke Y-sort silently (deleting a container invalidated the NodePath and a fresh one was never auto-reassigned).

**Spawned entities join the container via explicit parenting**: the container resolved by `SpawnManagerConfig` (see above) is transferred to `SpawnManagerGlobal` — `spawn_enemy()` adds enemies there (fallback: scene root, no Y-sort). Item drops inherit it for free (`_spawn_single_drop_item` adds to the enemy's `get_parent()`), and projectiles too (`add_sibling(player)` = child of the player's parent). Tile occlusion switch points are calibrated via each tile's **Y Sort Origin** in the TileSet relative to the entity feet origin.

### Player

The player is created at runtime by `PlayerSpawner`, never placed by hand, and characters normally share `player_character.gd`. Full rules: `.claude/rules/player.md`. It loads by itself with the player scripts and scenes, `PlayerSpawner`, `PlayerRosterGlobal` and the overhead health bar and label; read it first when discussing them without opening those files. Covers creating a character, where the player appears, which character is chosen, two players or no player in a stage, the order of nodes in the stage tree, swapping characters in a stage with enemies, armor, and the overhead health hiding or showing the wrong number.

### Attack system

Powers and powerups grow by level through resources read by a controller on the player. Full rules: `.claude/rules/powers-and-powerups.md`. It loads by itself with the power and powerup scripts, scenes and data; read it first when discussing them without opening those files. Covers creating or leveling a power or powerup, an upgrade that has no effect, cooldown, damage and speed bonuses, `attack_scale`, attacks hitting the feet or aiming at the wrong enemy, repeated targets and which side the snowflake falls on.

### Enemy system
Enemy logic lives in `EnemyBase`, then an archetype script such as `enemy_chaser.gd`, and a per-enemy script only when the logic diverges. Full rules: `.claude/rules/enemy-system.md`. It loads by itself with the enemy scripts and scenes; read it first when discussing enemies without opening them. Covers creating an enemy, its death, item drops, enemies jumping a few pixels near walls, recalculating the route after a teleport, and the damage flash and ghost effect fighting over `modulate`.

### Spawn system (`SpawnManagerGlobal`)

Budget-based enemy spawn with grid sampling and a teleport system. Full rules: `.claude/rules/spawn.md`. It loads by itself when the spawn files are touched; read it first when discussing spawn without opening them. Covers how many enemies appear and when (budget, difficulty, `max_enemies`), where they appear (offscreen grid sampling, walkable ground, excluded layers, wall clearance, enemy spacing, enemies stuck to walls or overlapping), the teleport of distant enemies, per-stage calibration (`SpawnManagerConfig`, `EnemySpawnData`) and spawn stutter.

### XP & Level-up flow

An enemy drops XP items, collecting them fills the bar, and each level opens a menu with upgrade options for powers and powerups. Full rules: `.claude/rules/xp-level-up.md`. It loads by itself with the XP, level-up, `XPBar` and `LoadoutBar` files; read it first when discussing them without opening those files. Covers the XP curve and its modes, levels that come too fast or too slow, several level-ups in a row, a menu that closes or reopens wrongly, a bar that freezes during the menu, and icons missing from the `LoadoutBar`.

### World objects (gates, barriers, future interactables)

The stage will grow more objects like this — Barrier is the first, not a special case. General shape: a self-contained scene with an editable size, an `open()`/`close()` (or equivalent) API driven by signals rather than hardcoded to one trigger, and a physics layer that blocks only the intended actor.

**Barrier — one-way gate.** The player crosses once and it closes behind them; enemies are never blocked. Full rules: `.claude/rules/barrier.md`. It loads by itself when the barrier files are touched; read it first when discussing the barrier without opening them. Covers a gate that closes, opens or blocks the wrong side, enemies turning semi-transparent or ghosted while crossing, its size and rotation, art that must stay upright, and its open and close animation.

**Scene changes and doors — the rule that shapes everything below: a scene change is ALWAYS a fresh start; continuity exists only inside one scene; one stage = one scene.** Every COMBAT stage starts the player from zero (100% health, level 1, primary attack only), and a multi-room stage is **one** scene with in-scene doors, never several scenes. That rule is what keeps a future mid-stage safe room cheap — it would be a room, needing only a state change — whereas carrying a build across scenes would need a save-and-restore layer for every attack and powerup level (they live on the player's controllers, which die with the scene). Two door types follow from it, deliberately **separate scenes**, because their logic diverges at the most expensive point — a room door misconfigured as a stage door would wipe the player's progress mid-stage:

| | Room door (`room_door`) | Stage door (`stage_door`) |
|---|---|---|
| Changes scene | no | yes |
| Used | inside any scene, EXPLORATION **and** COMBAT | safe house → stage; stage end → safe house |
| Direction | two-way by default | one-way by nature |
| Destination | the partner door, same scene | a scene file, loaded only on touch |
| Player, music, build | continue | fresh start |

**Room doors and stage doors.** Full rules: `.claude/rules/doors.md`. It loads by itself when the door files are touched; read it first when discussing doors without opening them. Covers linking two doors, one-way doors, a door that does nothing or sends the player straight back, where the player arrives, the fade and hold of a crossing, how rooms must be spaced in a combat stage, and a stage door pointing at its destination.

**Scene changes — `GameStateGlobal.go_to_scene()` and `restart_game()` own the WHOLE sequence**, because whoever triggers it (a door, a menu button) dies with the old scene halfway and an autoload survives the swap. **Every scene change in the game goes through one of them**: stage doors and the game-over **Main Menu** button call `go_to_scene(path, fade_out, fade_in)`; restart (pause menu or game over) calls `restart_game()`. Both run the same private `_go()`: **block pause → leave a menu state → hold → fade out → shared cleanup → hold again → swap → wait for the new scene → fade in → release → unblock pause.** The swap itself is the only difference (`change_scene_to_file()` vs `reload_current_scene()`), passed in as a `Callable`; the dark half is `_swap_scene_in_dark()`.
- **Details:** `.claude/rules/scene-changes.md`. It loads by itself with `autoload/game_state.gd`; read it first when discussing a scene change without opening that file. Covers restart and Main Menu from a paused tree, menus that stay on screen, sounds that cross into the next scene, what the shared cleanup clears, the fade durations, a frozen black screen, and pause during a transition.
- **Trap this closes, keep in mind:** a stage's `StageConfig` declares its mode in `_enter_tree()` via `set_state()`, which happily overwrites `PAUSED` — leaving the state at COMBAT/EXPLORATION while the tree stays paused: frozen black screen, no menu, a second ESC "pauses" again. It is unreachable only because pause is blocked during `go_to_scene()`. **Any future scene change must go through `go_to_scene()`** (or block pause the same way) or it reopens.

**Chambers — character swap in the safe house.** A glass chamber the player touches to change character. Full rules: `.claude/rules/chambers.md`. It loads by itself when the chamber files are touched; read it first when discussing chambers without opening them. Covers choosing or swapping the character, a chamber that shows empty, stays locked or ignores the touch, where the new character appears, the swap sound, and why a swap needs a scene without enemies.

**`@tool` scenes and the `RESET` animation.** Traps of the Godot editor that apply to any `@tool` script and any `AnimationPlayer`. Full rules: `.claude/rules/godot-tool-scenes.md`. It loads by itself with the existing `@tool` files; **read it first before writing or changing any `@tool` script or keying a new animation track.** Covers resize code that silently does nothing, resizing one instance changing all the others, a value that will not stick in the Inspector, reacting to a manual rotation in the editor, and a stage listed as changed after only playing.

### PowerUp system

Same rules file as *Attack system*: `.claude/rules/powers-and-powerups.md`.

## Node groups

Project-wide registry. **Each group has exactly one declaration site** — never declare the same group both in a script and in a scene's Groups tab. (That duplication is how the dead `"Enemies"` look-alike of `"Enemy"` was born and survived for months.)

| Group | Declared in | Consumed by |
|---|---|---|
| `Player` | **scene** — each player scene's root (Groups tab) | camera, level-up, spawn manager, enemies, loadout bar, powers 04/05/06 |
| `Enemy` | **code** — `enemy_base.gd` `_ready()` | spawn manager, power targeting, steering neighbours, knockback transfer |
| `EnemyHurtbox` | **scene** — each enemy's `Hurtbox` node | every power's hit detection |
| `PlayerHurtbox` | **scene** — player's `Hurtbox` node | enemy hitboxes (contact damage) |
| `YSortContainer` | **scene** — `y_sort_container.tscn` root (Groups tab) | `SpawnManagerConfig` (resolves the enemy parent; see Y-sort) |
| `Power` | **code** — `base_power.gd` `_ready()` | *(reserved — no consumer yet)* |
| `XPItems` | **code** — `xp_item.gd` `_ready()` | *(reserved — no consumer yet)* |

**Where to declare — the rule:**
1. **Queried during initialization** (inside another node's `_ready()`) → **Groups tab**. A tab group is active the moment the node enters the tree, *before* any `_ready()`; a group added by `add_to_group()` only exists after that node's own `_ready()` has run. `camera.gd._ready()` looks up `Player` immediately — which is why `Player` must stay in the tab.
2. **Family defined by a script shared across many scenes**, queried only at runtime → **base script** (`add_to_group`). Guarantees a new subclass scene cannot forget it (`Enemy`, `Power`, `XPItems`).
3. **Belongs to a specific child node** → that scene's **Groups tab** (`EnemyHurtbox`, `PlayerHurtbox`). These are the only groups repeated scene by scene, so they are the easiest to forget — and forgetting one makes that entity **invulnerable**. Both are covered by init guards (see *Entity anatomy*).
4. **Never create a script just to add a group.** A scene with no script declares it in the tab — this is exactly the case of `YSortContainer`, a pure marker scene that must never gain a script.

**Reserved groups:** `Power` and `XPItems` have no consumer today; they are kept as single-source handles for future use (acting on all live projectiles mid-game; a magnet powerup pulling XP). Note `XPItems` covers **only items using `xp_item.gd`** — a future non-XP collectible with its own script would need a broader group (or a shared item base script), not this one.

**Global registry + descriptions (`project.godot`)** — every group above is registered under `[global_group]` so the editor's Groups dock lists the whole inventory in any scene, including the code-declared ones (which otherwise exist only at runtime and never show up). **Registering a name there assigns it to no node** — it is editor metadata; membership still comes only from the scene tab or `add_to_group()`.

Each entry carries a **description** (the quoted value after `=`) stating **where the group is declared** and **what breaks without it** — for code-declared groups it reads `NAO ticar em cenas`, so the warning lands exactly where someone would be tempted to create the duplicate declaration. **The editor has no UI to write these descriptions**: edit `project.godot` by hand with Godot closed. Keep them ASCII — the editor rewrites that file on every settings change. **When adding a new group, register the name and write its description in the same pass**; a registered group with an empty description is an invitation to tick it on the wrong node.

**Editor gotcha:** deleting a group from the Groups dock does **not** rewrite scenes that already carry it — the `groups=[...]` entry stays in each `.tscn` and becomes hard to spot in the dock. Remove it on the node itself, or edit the scene file.

## Physics layers (2D)

| Layer | Name |
|---|---|
| 1 | environment (walls/TileMap) |
| 2 | player |
| 3 | enemies |
| 4 | power (projectiles) |
| 5 | player_barrier (obstacles that block only the player — e.g. Barrier) |
| 9 | enemy_hurtbox |

## Key conventions

- **Folder layout — named by role, in the game's own vocabulary.** `stages/` holds the playable stages (`stage_01`, `safe_house_01`…); `entities/stage_parts/` holds the pieces you assemble a stage from (`barrier`, `chamber`, `navmesh_merger`, `player_spawner`, `room_door`, `spawn_manager_config`, `stage_door`, `stage_config`, `y_sort_container`); `debug/` holds debug tools that code creates, never placed by hand (`debug_draw_overlay`). Stages used to live in `scenes/` — a name that says nothing in Godot, where every `.tscn` is a scene — while `entities/stages/` held the *parts*, inverting the project's own "stage" vocabulary. **Moving files is safe here because nothing references assets by path**: scenes store `uid://` alongside the path and resolve by uid first, code uses `uid://` (verified: no `res://` path to these folders in any `.gd`), and `run/main_scene` is a uid. The condition: move **through Godot's FileSystem dock**, never the OS file explorer, so the editor rewrites stored paths and its uid cache.

- **Singleton naming**: `NomeFuncionalGlobal` (e.g. `TargetTrackerGlobal`, `PowerUpStatsGlobal`).
- **`@export` discipline**: only fields that must appear in the Inspector. Non-`@export` fields are **not copied by `duplicate(true)`** — fields set at runtime that need to survive a `duplicate()` call must be `@export`. Two consequences that have already cost time here:
  - **`@export` on a script autoload is decorative.** Autoloads registered as `*res://…gd` (all of them here) are instantiated by the engine with no Inspector and no serialization, so their exports can never be edited or stored — the values always arrive from elsewhere (for `SpawnManagerGlobal`, from `SpawnManagerConfig`). Don't read an `@export` there as "a knob someone can turn".
  - **Removing or renaming an `@export` orphans the value already stored in every scene.** Godot rewrites `NodePath`s automatically but never property *names*, so the old `name = value` line stays in the `.tscn` pointing at nothing and is silently ignored. Harmless when the property was inert; a silent loss of calibration when it was not. **Delete those lines from the affected scenes in the same pass** (with Godot closed) rather than relying on the editor to drop them on the next save.
- **Resource sharing strategy** — pick by how the data varies: data that must be identical everywhere (attack stats, powerups) → shared `.tres` + runtime `duplicate()`; data owned by one scene/instance (enemy drop tables, per-stage spawn definitions) → embedded resources created directly in the Inspector. Embedded resources live inside the scene file and are invisible in the FileSystem dock — use the resource's `resource_name` field to label them in Array slots. When a scene is instanced (e.g. `SpawnManagerConfig` inside a stage), configure embedded resources on the **instance**, not the base scene, or the data leaks into every instance.
- **Asset references in code use `uid://`, never `res://` paths**: uids survive file moves/reorganization (which happens often here); string paths silently break — `load()` and `change_scene_to_file()` are **not** tracked by the editor and keep pointing at the old path. Bind the uid to a descriptively-named `const`/`var` so the reference is self-documenting (e.g. `const LEVEL_UP_UI_SCENE = preload("uid://...")`); **when there is no such name** (e.g. an inline `preload` inside a call), add a short comment naming the target file (e.g. `set_script(preload("uid://..."))  # uid = scripts/debug_drawer.gd`). Use `preload` (load-time) for assets always used; `load(uid)` for conditional/rare ones (e.g. the debug overlay). **Never hand-write uids** — let Godot generate them; a typed uid with `_` or characters outside `0-9a-z` is invalid and unresolvable (Godot can't register it, so `Copy UID` and `load` both fail).
- **`super._ready()` in subclasses**: GDScript does **not** run the parent's `_ready()` automatically — defining `_ready()` in a subclass fully overrides it. So: subclass **has** its own `_ready()` → it must call **`super._ready()` as the first line**; subclass has **no** `_ready()` → nothing to do, the parent's runs. This already bit the project: `power_02/04/06` each duplicated `add_to_group("Power")` because they overrode `_ready()` without `super`. The `Power` group now has a single source in `base_power.gd` and **depends on those `super._ready()` calls** (`power_05_gear.gd` was the original correct example).
- **`is_combat_allowed()` gate**: every system that acts on combat state (attacking, taking damage, gaining XP) must check this before proceeding. Spawning and enemy movement are deliberately outside it today — see *Critical gate*.
- **Restart must reset autoload state**: `reload_current_scene()` rebuilds only the stage — autoloads and **everything they own survive it**. The single place that clears cross-session state is `GameStateGlobal._end_current_scene()` (scene audio, XP, spawning, audio pool, target tracker, holds), shared by `restart_game()` and `go_to_scene()`; any new autoload that accumulates runtime state must be reset **there**, so both paths get it. This really bit: the `AudioManager` pool's players are children of the autoload, not of the stage, so an attack sound kept playing into the next run long after the attack scene had been freed.
- **Deferred calls for spawning**: use `call_deferred` or `add_child` then set `global_position` afterward (so `_ready` runs before position is overwritten).
- **Audio buses**: SFX plays on the `"SFX"` bus. Powers that manage looping audio set `handles_own_audio = true` on their `AttackData` to suppress the controller from also playing it.
- **Audio export naming**: every configurable sound exposes three exports named `<name>_sound`, `<name>_sound_volume_db` (default `0.0`) and `<name>_sound_pitch_scale` (default `1.0`), passed straight to `AudioManagerGlobal.play_sound_2d(sound, position, volume_db, pitch_scale)`. Sounds are played through the AudioManager's pool — **no per-scene `AudioStreamPlayer` node**. Older code predates this convention and still uses shorter names; migrate to this form when touching it.
- **Pool is for fire-and-forget sounds; sounds with state keep their own player.** Two documented exceptions, both deliberate: **stage music** (an `AudioStreamPlayer` node in the stage — continuous, needs its own loop/stop control, and belongs on the `Music` bus) and the **player's hit sound** (`PlayerBase` creates `audio_hit`/`audio_death` in code). The hit sound can fire ~10×/s from contact damage, and its anti-spam is *"let the sound finish, then wait `hit_post_delay`"* — it listens to that player's `finished` signal, so the clip is **never cut mid-play**. The pool can't do this: it lends an anonymous player and returns no reference, and its own guard is a fixed global `MIN_INTERVAL` that would let most hits through and overlap. Don't "fix" this by forcing it into the pool without first giving the pool a way to report when a specific sound ended.
- **Never version Godot's save snapshots:** Godot writes `<scene>.tscn<hash>.tmp` when saving, and some had been committed. `*.tmp` is in `.gitignore`.

## Debug and test systems

Tools that exist only to test or observe: the keyboard test tools on each player, the spawn log and grid overlay, and the `NavmeshMerger` diagnostics. Full rules: `.claude/rules/debug-tools.md`. It loads by itself with the test and debug scripts; read it first when discussing them without opening those files. Covers which test keys exist, turning the test tools off, why they are nodes on the player and not autoloads, methods kept alive only by a test tool, removed tools, and the spawn overlay drawing in the wrong place.

## Known bugs

*(none currently documented)*

## Calibration reference

### Knockback
- Decay is frame-rate independent: `knockback = knockback.move_toward(Vector2.ZERO, knockback_decay * delta)` — values are **per second**, calibrated per enemy in the Inspector (heavier enemies use higher decay so they travel less).
- `knockback_retention_after_transfer` default: `0.8` (export var on `EnemyBase`).
- **Direction, attack → enemy**: `receive_hit()` computes `(get_body_center_position() − source_pos)` — from the projectile's centre **through the enemy's centre of mass** (the `BodyCenter` normally sits on the physical `CollisionShape2D`). The hit is *detected* on the `Hurtbox`, which is higher than the body (gator `−13` vs `−10`; red gator `−19` vs `−15`), so measuring to the scene origin (feet) added a **constant downward component** (~13 / ~19 px): a dead-on horizontal shot flung the enemy ~35° diagonally down, and upward knockback was nearly impossible. **The misalignment between `Hurtbox` and `BodyCenter` is tolerated, not a finished design:** the BodyCenter sets the impulse, because you push the mass, not the point you touched, but the hit is still detected higher up, on the `Hurtbox`.
- **Direction, enemy → enemy (transfer)**: `handle_knockback_transfer()` uses the **real physics contact normal** from `get_slide_collision()` between the two body colliders — exact, and unaffected by the feet/BodyCenter question. The two mechanisms differ in method (approximation vs true normal) but now agree on *what* is pushed: the body.
- Residual approximation (accepted): the direction leaves the projectile's **centre**, not the surface contact point — `area_entered` gives no contact normal. Fine for small fast projectiles against roughly circular bodies; not compensated.

### Enemy inter-enemy avoidance — Context Steering
Enemies dodge each other by context steering, not RVO, and the `NavigationAgent2D` only finds the route. Full rules: `.claude/rules/enemy-steering.md`. It loads by itself with `scripts/enemy_base.gd` and the enemy scenes; read it first when discussing enemy movement without opening them. Covers enemies that crowd, queue, stand still or slow down around each other, walls while dodging, the `steer_*` calibration, priority between enemies, why RVO was removed, repath spikes and `path_recalc_interval`.

## Performance budget and NavmeshMerger

Measured costs of the game and why the navigation mesh is baked into one region. Full rules: `.claude/rules/performance.md`. It loads by itself with the `NavmeshMerger` files; read it first when discussing performance, frame time, stutter or navigation cost without opening them. Covers what is expensive and what is not, how to read the measurements, the settings already measured and rejected, the merged navmesh, enemies losing routes after a scenery edit, the engine warning about navigation edge errors and waiting for the navigation server.

**New stage checklist (navigation):** instance `entities/stage_parts/navmesh_merger.tscn` anywhere in the stage and leave `mode = MERGED`. Position in the tree or in the world does not matter, and nothing else needs wiring.

## Working style

- One change at a time, with a test between each.
- **Godot closed for `project.godot` and `.tscn`:** edit them only with the editor closed, or it rewrites them from memory and silently undoes the change.
- **Move or rename files only through Godot's FileSystem dock, warning first** (see *Folder layout* for why).
- **The user builds the scenes; Claude writes the code.**
- **Ask before implementing. A recommendation is not a decision:** it is followed only after the user confirms it, and when unsure what was decided, ask.
- **Documents follow reality.** When a system, rule or working practice changes, update its document in the same step. If the change comes up in conversation and it is unclear whether it is definitive, ask whether to record it. If a document contradicts the code or what was agreed, say so instead of silently following either.
- **Project cleanliness comes first:** no leftovers or loose files.
- **Follow the patterns already in the project.**
- **Write for a game that keeps growing.** Documents and code comments describe rules and patterns, not inventories: no counts of game content (powers, enemies, players, materials, scripts, tiles), no status of what is finished, no notes that work will continue. A current name appears only when the text truly needs an example, and it reads as an example. Measurements stay, as records. Unless the code enforces it, a pattern is a tendency: write "normally", without guessing future exceptions. Before stating a fact about the game, check the game itself. Content may still be unconfigured, so never treat it as a pattern; when in doubt, ask. Before raising an alarm, follow the whole path in the code and compare it with what was seen in play; state what is confirmed.
- **No file changes without the user's authorization.** This covers every project file and Claude's memory. The only exception is `docs/pendencias.md` (open work), which Claude may update freely, always telling the user what changed.
- **Measure before optimizing — and measure the suspect call, not the frame.** The spawn stutter cost four failed optimizations (grid cache frequency, `group_adjacent_points` O(N³)→hash, query reuse, moving to `_physics_process`) because they attacked what *looked* expensive. The profiler's script self-time does **not** include time spent inside server calls, so the real culprit was invisible: 98% of the scan sat inside `map_get_closest_point`. What settled it was temporary instrumentation timing the suspect calls directly, and then running old and new methods **side by side** to prove equivalence before swapping.
- **`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the WORST frame of the last second, published once per second — never a per-frame cost.** Godot accumulates a max and only publishes it when the 1 s slice closes, so the same value repeats for ~60 frames. **The Analisador's Process/Physics Time graph plots exactly these monitors**, so it is an envelope of maxima sampled at 1 Hz — which inherently draws a sawtooth. This cost a whole investigation: a "periodic spike every ~150 frames" was chased through the teleport cycle, the grid scan, the spawn cadence and the attack system (all four tests negative) before the metric itself turned out to be the artifact. Measuring frame time properly means `Time.get_ticks_usec()` deltas between frames (wall time, includes render) with percentiles — at which point the real answer was 0.1% of frames above 21 ms, none above 34, with a full horde of 38 bodies / 474 collision pairs. **Corollary for any future in-game instrument: never `print()` per frame** — the console goes through the debugger socket and the measurement starts paying for itself; buffer in memory and print aggregates only.
- **Never measure a call's cost by playing.** Two sessions with identical settings differed by **53%** on the same metric, because the cost of an A* query depends on *where* the fight happens (route length, how open that part of the map is) — so the play route silently becomes the independent variable, and any effect smaller than that swamps. Costs of a *call* are measured by a **deterministic bench**: fixed seed, fixed point pairs, issued straight at the server with the game stopped, so two runs return the same number. In-game instrumentation is only for **confirming** a gain a bench already proved. A whole sweep of `NavigationAgent2D` settings was run, and discarded, before this was understood.
- **A measuring instrument must report its own validity.** The bench prints whether each setting even existed in this Godot version (`INDISPONIVEL`, never a fabricated number), how many routes actually reached their target (a setting that "gains" by breaking navigation is exposed on the spot), and how many enemies were alive competing for CPU. An instrument that can quietly lie is worse than no instrument — and this project has already lost rounds to `Performance.TIME_*`, to a `PackedFloat32Array` that silently discarded every sample, and to paused frames diluting an average.
- **Instrumentation must not alter the game.** A bench that disabled spawning to reduce noise broke the run for anyone who pressed F5. Side effects of temporary code are stated up front, not buried in a paragraph.
- **One commit closes a task:** correct → test → update `docs/pendencias.md` → commit. Tests read the files in the folder, so they run before the commit and nothing is left over for the next one.
- **Temporary test code:** when its test ends, evaluate whether it is still needed and **ask the user before removing it** — a test may need to live longer. If it stays, record it in `docs/pendencias.md`.
- Explain the "why" before implementing.
- No over-engineering: prefer generalizable solutions over artificial ones.
