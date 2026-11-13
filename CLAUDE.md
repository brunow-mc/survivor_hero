# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Survivor Hero** — Vampire Survivors-style game built in **Godot 4.7.2** (GDScript). Viewport: 480×270, pixel art (no texture filtering). No CLI build or test system; everything runs through the Godot Editor.

## Running the game

Open `project.godot` in Godot 4.7.2 and press F5 (or the play button) to run the main scene set in `run/main_scene`; it changes as the game grows, so do not rely on which scene it is. F6 runs the scene open in the editor.

There are no automated tests. Manual playtesting is the only validation method.

## Architecture overview

### Autoloads (singletons — always available globally)

| Name | File | Purpose |
|---|---|---|
| `GameStateGlobal` | `autoload/game_state.gd` | Central FSM of the `GameplayState` (the game's current mode). Also owns player health. |
| `XPManagerGlobal` | `autoload/xp_manager.gd` | XP accumulation, level-up signal, selectable level-up curve (LINEAR/EXPONENTIAL/FIXED/POWER — see XP & Level-up flow). |
| `LevelUpManagerGlobal` | `autoload/level_up_manager.gd` | Generates upgrade options on level-up, pauses game, delegates to controllers. |
| `SpawnManagerGlobal` | `autoload/spawn_manager.gd` | Budget-based enemy spawn with grid sampling and teleport system. |
| `PowerUpStatsGlobal` | `autoload/power_up_stats.gd` | Flat store for computed player stats (damage, armor, cooldown reduction, etc.). Emits `stats_changed`. |
| `AudioManagerGlobal` | `autoload/audio_manager.gd` | Central SFX playback (2D and positional). |
| `InputManagerGlobal` | `autoload/input_manager.gd` | Input abstraction. |
| `TargetTrackerGlobal` | `autoload/target_tracker_global.gd` | Tracks recently-targeted enemies to prevent repetition (used by attacks that pick a random target). |
| `PlayerRosterGlobal` | `autoload/player_roster.gd` | Which character is chosen, with a default. Read by `PlayerSpawner` (see Player). Future home of character unlocks. |
| `HoldGlobal` | `autoload/hold.gd` | Brief holds: freezes *specific* parts of the game for an instant (a door crossing, for example). See *Brief holds*. |
| `FadeGlobal` | `autoload/fade.tscn` (+ `fade.gd`) | Fades the screen to black and back. Registered as a **scene**, not a script, so its visual node exists and survives scene changes. See *Draw layers and Screen fade*. |

**Suspending the player is the GameplayState's job, never the progression's.** A safe house, a dialogue or a cutscene wants "you still have your level-5 Fire, it just doesn't fire *now*" — that is `is_combat_allowed()`, a temporal gate the attacks, contact damage and XP pickup all already consult. It is **not** `remove_powerup()` or anything that writes `current_level = 0`: those erase what the player earned and would need a save-and-restore layer to undo. Progression answers *how much you have*; the state answers *what may happen right now*. Don't mix the two axes.

**Critical gate:** `GameStateGlobal.is_combat_allowed()` returns `false` during PAUSED, UPGRADE, CUTSCENE, DIALOGUE, EXPLORATION and PLAYER_DEAD. `PLAYER_DEAD` is a terminal state — only a scene change (restart or Main Menu) leaves it. **Its consumers are exactly four:** attack firing (`AttackController`), contact damage (`PlayerBase`), XP pickup (`XPItem`) and XP accumulation (`XPManager`). **Spawning, enemy movement and XP-item magnet movement do NOT consult it** — they stop only when the whole tree is paused. **It is a BLOCKLIST, so every new state is born with combat ALLOWED:** when adding a state (`SHOP`, `BOSS_INTRO`…), add it to the list in the same pass.

**Leaving a transient state returns to where the game WAS, never to a hardcoded COMBAT.** `resume_game()` restores `previous_state`; the level-up menu restores its own memory of the state it opened from.

**Every stage DECLARES its own mode — `entities/stage_parts/stage_config.tscn` (`scripts/stage_config.gd`).** The state survives a scene change, so a stage that declares nothing inherits the previous one's mode. It declares in `_enter_tree()`, before anything in the stage starts.
- **New stage checklist (state):** instance `stage_config.tscn` anywhere in the stage and set `Gameplay State` (and, if wanted, `Start Hold Seconds`) on that instance. Never set it on the base scene — that value would leak into every stage (same rule as `SpawnManagerConfig`).

Full rules: `.claude/rules/gameplay-state.md`. It loads by itself with `game_state.gd`, `StageConfig`, `InputManager`, `LevelUpManager` and the pause menu; read it first when discussing game modes without opening those files. Covers why the gate is a blocklist, a safe house with enemies or items in it ("ghost mode"), freezing versus removing what is on screen, the level-up menu returning to the wrong mode, pause inside the level-up menu, which modes a stage may declare, and a stage that keeps the previous stage's mode.

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

### Draw layers and Screen fade

What draws above what (`CanvasLayer.layer` for whole sheets, `z_index` inside the world sheet) and the black screen fade used by doors and scene changes. Full rules: `.claude/rules/draw-layers.md`. It loads by itself with the UI, fade, effect and debug-overlay files; read it first when adding a `CanvasLayer`, a visual effect or a power, or when discussing the fade, without opening those files. Covers the layer and z tables, the HUD or a menu showing over or under the black, a power or effect lighting the silhouette, a fade that never ends on a paused tree, and who decides the fade durations.

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

Entities and scenery tiles occlude each other by the Y of their feet, inside the stage's `YSortContainer`. Full rules: `.claude/rules/y-sort.md`. It loads by itself with the stages, tilesets and `YSortContainer`; read it first when discussing depth or occlusion without opening them. Covers the three requirements for Y-sort, which TileMap layers go inside the container, the player always drawn in front of or behind enemies, a tile that covers or uncovers an entity at the wrong height, and how spawned enemies, items and projectiles join the container.

### Player

The player is created at runtime by `PlayerSpawner`, never placed by hand, and characters normally share `player_character.gd`. Full rules: `.claude/rules/player.md`. It loads by itself with the player scripts and scenes, `PlayerSpawner`, `PlayerRosterGlobal` and the overhead health bar and label; read it first when discussing them without opening those files. Covers creating a character, where the player appears, which character is chosen, two players or no player in a stage, the order of nodes in the stage tree, swapping characters in a stage with enemies, armor, and the overhead health hiding or showing the wrong number.

### Attack system

Powers and powerups grow by level through resources read by a controller on the player. Full rules: `.claude/rules/powers-and-powerups.md`. It loads by itself with the power and powerup scripts, scenes and data; read it first when discussing them without opening those files. Covers creating or leveling a power or powerup, an upgrade that has no effect, cooldown, damage and speed bonuses, `attack_scale`, attacks hitting the feet or aiming at the wrong enemy, repeated targets and which side the snowflake falls on.

### Enemy system
Enemy logic lives in `EnemyBase`, then an archetype script such as `enemy_chaser.gd`, and a per-enemy script only when the logic diverges. Full rules: `.claude/rules/enemy-system.md`. It loads by itself with the enemy scripts and scenes; read it first when discussing enemies without opening them. Covers creating an enemy, its death, item drops, enemies jumping a few pixels near walls, recalculating the route after a teleport, and the damage flash and ghost effect fighting over `modulate`.

### Knockback
Same rules file as *Enemy system*: `.claude/rules/enemy-system.md`. Covers the knockback direction, how fast it fades, and how it passes from one enemy to the next.

### Enemy inter-enemy avoidance — Context Steering
Enemies dodge each other by context steering, not RVO, and the `NavigationAgent2D` only finds the route. Full rules: `.claude/rules/enemy-steering.md`. It loads by itself with `scripts/enemy_base.gd` and the enemy scenes; read it first when discussing enemy movement without opening them. Covers enemies that crowd, queue, stand still or slow down around each other, walls while dodging, the `steer_*` calibration, priority between enemies, why RVO was removed, repath spikes and `path_recalc_interval`.

### Spawn system (`SpawnManagerGlobal`)

Budget-based enemy spawn with grid sampling and a teleport system. Full rules: `.claude/rules/spawn.md`. It loads by itself when the spawn files are touched; read it first when discussing spawn without opening them. Covers how many enemies appear and when (budget, difficulty, `max_enemies`), where they appear (offscreen grid sampling, walkable ground, excluded layers, wall clearance, enemy spacing, enemies stuck to walls or overlapping), the teleport of distant enemies, per-stage calibration (`SpawnManagerConfig`, `EnemySpawnData`) and spawn stutter.

### XP & Level-up flow

An enemy drops XP items, collecting them fills the bar, and each level opens a menu with upgrade options for powers and powerups. Full rules: `.claude/rules/xp-level-up.md`. It loads by itself with the XP, level-up, `XPBar` and `LoadoutBar` files; read it first when discussing them without opening those files. Covers the XP curve and its modes, levels that come too fast or too slow, several level-ups in a row, a menu that closes or reopens wrongly, a bar that freezes during the menu, and icons missing from the `LoadoutBar`.

### World objects (gates, barriers, doors, chambers)

A world object is normally a self-contained scene with an editable size, an `open()`/`close()` (or equivalent) API driven by signals rather than hardcoded to one trigger, and a physics layer that blocks only the intended actor. Barrier, doors and chambers are examples.

**Barrier — one-way gate.** The player crosses once and it closes behind them; enemies are never blocked. Full rules: `.claude/rules/barrier.md`. It loads by itself when the barrier files are touched; read it first when discussing the barrier without opening them. Covers a gate that closes, opens or blocks the wrong side, enemies turning semi-transparent or ghosted while crossing, its size and rotation, art that must stay upright, and its open and close animation.

**A scene change is ALWAYS a fresh start; continuity exists only inside one scene; one stage = one scene.** Every COMBAT stage starts the player from zero (100% health, level 1, primary attack only), and a multi-room stage is **one** scene with in-scene doors, never several scenes. That rule is what keeps a future mid-stage safe room cheap — it would be a room, needing only a state change — whereas carrying a build across scenes would need a save-and-restore layer for every attack and powerup level (they live on the player's controllers, which die with the scene). So there are two door types, deliberately **separate scenes**: a room door (same scene, everything continues) and a stage door (another scene, fresh start). A room door misconfigured as a stage door would wipe the player's progress mid-stage.

**Room doors and stage doors.** Full rules: `.claude/rules/doors.md`. It loads by itself when the door files are touched; read it first when discussing doors without opening them. Covers how the two door types differ, linking two doors, one-way doors, a door that does nothing or sends the player straight back, where the player arrives, the fade and hold of a crossing, how rooms must be spaced in a combat stage, and a stage door pointing at its destination.

**Every scene change goes through `GameStateGlobal.go_to_scene()` or `restart_game()`** — they own the whole sequence (fade, holds, cleanup, swap), because whoever triggers it dies with the old scene halfway and an autoload survives the swap. A scene change made any other way reopens a known trap: a frozen black screen after pausing mid-change. Full rules: `.claude/rules/scene-changes.md`. It loads by itself with `autoload/game_state.gd`; read it first when discussing a scene change without opening that file. Covers the order of the sequence, restart and Main Menu from a paused tree, menus that stay on screen, sounds that cross into the next scene, what the shared cleanup clears, the fade durations, a frozen black screen, and pause during a transition.

**Chambers — character swap in the safe house.** A glass chamber the player touches to change character. Full rules: `.claude/rules/chambers.md`. It loads by itself when the chamber files are touched; read it first when discussing chambers without opening them. Covers choosing or swapping the character, a chamber that shows empty, stays locked or ignores the touch, where the new character appears, the swap sound, and why a swap needs a scene without enemies.

**`@tool` scenes and the `RESET` animation.** Traps of the Godot editor that apply to any `@tool` script and any `AnimationPlayer`. Full rules: `.claude/rules/godot-tool-scenes.md`. It loads by itself with the existing `@tool` files; **read it first before writing or changing any `@tool` script or keying a new animation track.** Covers resize code that silently does nothing, resizing one instance changing all the others, a value that will not stick in the Inspector, reacting to a manual rotation in the editor, and a stage listed as changed after only playing.

### PowerUp system

Same rules file as *Attack system*: `.claude/rules/powers-and-powerups.md`.

## Node groups

Project-wide registry. **Each group has exactly one declaration site** — never declare the same group both in a script and in a scene's Groups tab. (That duplication is how the dead `"Enemies"` look-alike of `"Enemy"` was born and survived for months.)

| Group | Declared in | Consumed by |
|---|---|---|
| `Player` | **scene** — each player scene's root (Groups tab) | every system that looks for the player — e.g. camera, enemies, spawn, level-up, loadout bar, XP items, doors, chambers, `PlayerSpawner`, powers that follow the player |
| `Enemy` | **code** — `enemy_base.gd` `_ready()` | spawn manager, power targeting, steering neighbours, knockback transfer |
| `EnemyHurtbox` | **scene** — each enemy's `Hurtbox` node | every power's hit detection |
| `PlayerHurtbox` | **scene** — player's `Hurtbox` node | enemy hitboxes (contact damage), XP item pickup |
| `YSortContainer` | **scene** — `y_sort_container.tscn` root (Groups tab) | `SpawnManagerConfig` and `PlayerSpawner` (resolve the parent of enemies and player; see Y-sort) |
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

- **Folder layout — named by role, in the game's own vocabulary.** For example, `stages/` holds the playable stages, `entities/stage_parts/` the pieces a stage is assembled from (doors, `stage_config`, `y_sort_container`…) and `debug/` the debug tools that code creates. **Moving files is safe here because nothing references assets by path**: scenes store `uid://` alongside the path and resolve by uid first, code uses `uid://`, and `run/main_scene` is a uid. The condition: move **through Godot's FileSystem dock**, never the OS file explorer, so the editor rewrites stored paths and its uid cache.

- **Singleton naming**: `NomeFuncionalGlobal` (e.g. `TargetTrackerGlobal`, `PowerUpStatsGlobal`).
- **`@export` discipline**: only fields that must appear in the Inspector. Non-`@export` fields are **not copied by `duplicate(true)`** — fields set at runtime that need to survive a `duplicate()` call must be `@export`. Two consequences that have already cost time here:
  - **`@export` on a script autoload is decorative.** Autoloads registered as `*res://…gd` (all of them here) are instantiated by the engine with no Inspector and no serialization, so their exports can never be edited or stored — the values always arrive from elsewhere (for `SpawnManagerGlobal`, from `SpawnManagerConfig`). Don't read an `@export` there as "a knob someone can turn".
  - **Removing or renaming an `@export` orphans the value already stored in every scene.** Godot rewrites `NodePath`s automatically but never property *names*, so the old `name = value` line stays in the `.tscn` pointing at nothing and is silently ignored. Harmless when the property was inert; a silent loss of calibration when it was not. **Delete those lines from the affected scenes in the same pass** (with Godot closed) rather than relying on the editor to drop them on the next save.
- **Resource sharing strategy** — pick by how the data varies: data that must be identical everywhere (attack stats, powerups) → shared `.tres` + runtime `duplicate()`; data owned by one scene/instance (enemy drop tables, per-stage spawn definitions) → embedded resources created directly in the Inspector. Embedded resources live inside the scene file and are invisible in the FileSystem dock — use the resource's `resource_name` field to label them in Array slots. When a scene is instanced (e.g. `SpawnManagerConfig` inside a stage), configure embedded resources on the **instance**, not the base scene, or the data leaks into every instance.
- **Asset references in code use `uid://`, never `res://` paths**: uids survive file moves/reorganization (which happens often here); string paths silently break — `load()` and `change_scene_to_file()` are **not** tracked by the editor and keep pointing at the old path. Bind the uid to a descriptively-named `const`/`var` so the reference is self-documenting (e.g. `const LEVEL_UP_UI_SCENE = preload("uid://...")`); **when there is no such name** (e.g. an inline `preload` inside a call), add a short comment naming the target file (e.g. `load("uid://...")  # uid = debug/debug_draw_overlay.tscn`). Use `preload` (load-time) for assets always used; `load(uid)` for conditional/rare ones (e.g. the debug overlay). **Never hand-write uids** — let Godot generate them; a typed uid with `_` or characters outside `0-9a-z` is invalid and unresolvable (Godot can't register it, so `Copy UID` and `load` both fail).
- **`super._ready()` in subclasses**: GDScript does **not** run the parent's `_ready()` automatically — defining `_ready()` in a subclass fully overrides it. So: subclass **has** its own `_ready()` → it must call **`super._ready()` as the first line**; subclass has **no** `_ready()` → nothing to do, the parent's runs. This already bit the project: `power_02/04/06` each duplicated `add_to_group("Power")` because they overrode `_ready()` without `super`. The `Power` group now has a single source in `base_power.gd` and **depends on those `super._ready()` calls** (`power_05_gear.gd` was the original correct example).
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
- **Measuring performance** (cases and numbers in `.claude/rules/performance.md`): measure before optimizing, and measure the suspect call, not the frame; never read `Performance.TIME_*` as a per-frame cost; never measure a call's cost by playing — use a deterministic bench; an instrument must report its own validity; instrumentation must not alter the game; run measurements with V-Sync off.
- **One commit closes a task:** correct → test → update `docs/pendencias.md` → commit. Tests read the files in the folder, so they run before the commit and nothing is left over for the next one.
- **Temporary test code:** when its test ends, evaluate whether it is still needed and **ask the user before removing it** — a test may need to live longer. If it stays, record it in `docs/pendencias.md`.
- Explain the "why" before implementing.
- No over-engineering: prefer generalizable solutions over artificial ones.
