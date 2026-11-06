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
| `HoldGlobal` | `autoload/hold.gd` | Brief holds: freezes *specific* parts of the game for an instant (door crossing today). See *Brief holds*. |
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

It is deliberately **not** called "pause": that word already names the `PAUSED` state and the paused tree. Rejected alternatives: **`get_tree().paused`** (freezes the hold's own timer and the stage music, and collides with the pause menu — `resume_game()` would unpause the tree mid-crossing); **a new `GameplayState`** (states are exclusive and drag `StageConfig`, the level-up menu's memory and `previous_state` along, while holds overlap and last half a second — a boss may use the `CUTSCENE` state *and* a hold, two layers); **a flag on `PlayerBase`** (dies with the player, and the chamber swap destroys and recreates the player mid-hold — which is also why the hold lives in an autoload).

**How it works.** Each request names **what** it freezes (one or more `Scope` bits) and gets a **ticket**. Requests **overlap**: a scope is free only when every request holding it has been released — with a plain boolean, the first request to end would unlock everything while another still holds (the stage-start hold ending mid-door). Two ways to ask: `hold(scopes, reason)` + `release(ticket)` when the end is an event (fade finished, boss animation over), `hold_for(scopes, seconds, reason)` when it is only time. Consumers ask `is_held(scope)` — a bit test against a cached mask, cheap enough per enemy per frame. **Durations live with whoever asks, never in `HoldGlobal`**: the pattern is *how* to ask, the number belongs to each situation (constants in an autoload or plain script, an `@export` on a scene like a chamber or boss, a field on `StageConfig` for a stage-start hold).

**Safety rules:** `clear()` runs on **every scene change** (in the shared `_end_current_scene()` of `restart_game()` and `go_to_scene()`) — a request whose owner dies with the scene would otherwise leave the player frozen in the next one. Tickets are **never reused**, even after `clear()`, so a stale `hold_for()` expiring later cannot release a new request. Waits never use `process_always`, so a hold **waits while the pause or level-up menu is open** — the two kinds of pause compose.

**Scopes exist in code ONLY with a consumer.** A declared scope nobody consults is an empty promise — someone asks for "enemies" and nothing happens, silently (the lesson of the deleted caller-less API, see *Debug and test systems*). Each scope below enters `HoldGlobal.Scope` **in the same pass as its consumer**. Callers that cross doors ask for the **`TRANSITION` set**, not their own list, so when a new scope is implemented it joins that set and every door holds it without touching the door's script (a future "cinematic" set would work the same way).

**Two sets exist:** `TRANSITION = PLAYER_INPUT | ENEMIES | SPAWN_CLOCK` (doors, and the fade-out half of a scene change) and **`SCENE_ARRIVAL = TRANSITION | ATTACKS`**, asked only by `GameStateGlobal._swap_scene_in_dark()` for the arrival hold — from the swap until the fade-in ends. **The match starts when the screen finishes clearing**: no attack fires in the dark, and the player's initial hesitation gives the stage start visual weight ("doesn't start in a tumult"). It covers every scene change (stage door either way, restart, Main Menu) and does not care about the destination's mode — in EXPLORATION it waits too, unnoticed, since the gate blocks firing anyway. **F5/F6 straight into a stage has no hold**, so attacks start at once; harmless, since in the real game every stage is entered through an event (a door, a menu). The fade-in alone gives a hesitation equal to **the caller's fade-in duration**; on top of it each stage can add its own **stage-start hold** (`StageConfig.start_hold_seconds`, see *Every stage DECLARES its own mode*).

**Stage-start hold — it starts AFTER the fade-in and ADDS to it.** The value means "seconds of hesitation with the screen already clear", identical by every entry path, and it also covers F5 (no fade, so it counts at once). Rejected: starting with the scene and overlapping the fade, where the visible wait would vary with the caller's fade-in and a value below the fade would do nothing. Mechanics (`StageConfig._run_start_hold()`): the hold (`SCENE_ARRIVAL`) is **requested in `_enter_tree()`** — on F5 the player is born in `PlayerSpawner._ready()`, and a request made in `StageConfig._ready()` could come after its `AttackController` already started; then, if `GameStateGlobal.is_changing_scene()`, it awaits `GameStateGlobal.scene_arrival_finished` (emitted right after the fade-in, **before** the arrival hold is released — the two holds overlap, so no frame slips free between them); then a **pausable** timer of `start_hold_seconds`; then release. A restart mid-wait is safe: `HoldGlobal.clear()` wipes it, and the stale ticket's late `release()` is ignored.

**The map** (✅ = exists):

| Scope | Freezes | Needed for |
|---|---|---|
| `PLAYER_INPUT` ✅ | movement input in `PlayerBase.move()` (direction zeroed → keeps facing, visual FSM goes idle) | doors, chamber, stage start |
| `ATTACKS` ✅ (start only) | the **start** of the attacks: while held, `AttackController.setup()` sets `_waiting_to_start` instead of starting; `_physics_process()` tests the bit and, on release, `_start_attacks()` starts every timer with level > 0 and fires the `start_immediately` shots — once. Attacks already running never stop (an unlock during the wait is left to the release). `_create_attack_timer()` only creates timers now | scene arrival (`SCENE_ARRIVAL`) |
| `ENEMIES` ✅ | movement **and contact damage together** — a held player touching a moving-or-damaging enemy would take hits with no way to flee. Movement: one check in `EnemyBase._physics_process()` **after** the DEAD branch (player attacks keep running through doors, so dying mid-hold must still work; knockback received while held is applied on release; sprite animation keeps playing). Damage: one check in `PlayerBase.take_damage()`, next to the `is_combat_allowed()` gate — one place covers both contact paths (the initial touch in `enemy_chaser`, the damage timer in `enemy_base`) | doors, scene arrival, boss, hitstop |
| `SPAWN_CLOCK` ✅ | **the whole `SpawnManager._physics_process()` loop, by one check at its top** (after `is_spawning_enabled`): match clock (`game_time`, `time_since_start`), difficulty growth, budget accumulation, the initial delay, teleport and spawning. Blocking only the spawn step would let budget **and difficulty** grow while the player can do nothing, and a long hold would end in an undeserved burst. **Calibration consequence:** on arrival the clock is frozen during the fade-in, so `initial_spawn_delay` now counts only after the screen clears (the fade used to eat part of it) | doors, scene arrival, stage start, boss |
| attacks (time stopped) | extends `ATTACKS` from "delay the start" to "freeze running attacks" — three timing layers in `AttackController`: **pause** the looping `Timer`s (`Timer.paused`, keeping the remaining time — faithful to "time stopped", unlike skipping the shot); re-check **inside** the staggered-projectile loop, which today checks the gate **once, before starting**; **defer** (not drop) `start_immediately` shots | stage start, boss — **never doors** (see below) |
| *(maybe)* projectiles | powers in flight and player-attached ones (`gear` keeps spinning and would hit frozen enemies). Costly: every power moves itself in its own `_physics_process()` | boss, hitstop — decide on a real case |

**Doors do NOT interrupt attacks — decided by playtest, not by omission.** With the safe house temporarily in COMBAT and every attack on, attacks kept firing normally through room-door crossings, and it read well: it communicates what is happening and suits a combat stage with few or many doors. So the `attacks` scope must **never** join `TRANSITION`. A stage door is the same story: attacks run only during the fade-out half, and the scene change then destroys them. The three attack mechanisms in the table are kept for the cases that really want "time stopped" (stage start, boss), not for doors.

**Hold vs event — the boomerang problem (accepted, no event).** `power_04_bo` flies back toward `player_ref.global_position`, so after a room-door crossing it returns from the room the player left. Rooms are laid out in geometric order but far apart (as most of the level design will be), so the bo comes back from the right direction, just with a long delay — judged **acceptable** in play. The planned fix (an **event** at the instant of the move removing non-attached projectiles via the `Power` group) was therefore **dropped**; `Power` stays reserved. If it ever returns, the reasoning still holds: the issue is *place*, not *time* — freezing the bo would not help — and cleaning what was left behind is an event owned by the trigger, not a hold.

**Powerups: today none is hold-sensitive** — all eight are stat multipliers recomputed on level change, with no timer. The rule for the future: **what only changes a number is immune; what ACTS over time must consult the hold.** A regeneration-per-second, a pulse every N seconds, a damage aura or a recharging shield crosses that line — effectively attacks, entering through the same door as attacks.

Also verified: `TargetTrackerGlobal` detects "new batch" by wall clock (`Time.get_ticks_msec`), which a hold does not stop — a long hold reads as a new batch and clears the list, which is the right outcome (the pause menu already does the same). Music and camera keep going, as wanted. A future use the same system covers: **hitstop** (enemies + projectiles for ~0.05 s on a heavy hit).

**The former gap is closed:** a room door in a **COMBAT** stage used to hold only the player's input, leaving them standing still and vulnerable for the crossing. With `ENEMIES` and `SPAWN_CLOCK` in `TRANSITION`, the horde freezes and nobody is hurt during the crossing, while the player's attacks keep firing (by decision). Cost: one bit test per enemy per frame.

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

Player and every enemy scene follow this layout (in preparation for Y-sort):

- **Scene origin (root position) = the FEET.** Sprites/colliders are offset upward so `global_position` marks the ground point. Rendering/sorting and gameplay distances live in this frame.
- **`BodyCenter` (Node2D child) = center of the body/collider.** Player: `(0,-12)` | Gator: `(0,-10)` | Red Gator: `(0,-15)`. Navigation and body-anchored systems live in this frame.
- **Never mix the two frames.** Steering a body-frame point toward feet-frame path points (or vice versa) injects a constant vertical bias that accumulates along paths — enemies visibly "arc" below straight lines. This class of bug cannot be fixed by calibration; fix it by putting the whole pipeline in one frame.

**Enemy navigation is anchored on BodyCenter via reparenting**: each enemy's `NavigationAgent2D` is a child of `BodyCenter`, not of the root. `NavigationAgent2D` navigates **its parent node's position** — so path start, waypoint advancement and `is_navigation_finished()` all operate at the collider center. `enemy_base.gd` caches the parent as `_nav_anchor` and computes direction as `next_path_position − _nav_anchor.global_position` (never `to_local()`, which is feet-frame). `makepath()` targets the **player's BodyCenter** (body chases body). Nice property: when navigation finishes, `get_next_path_position()` returns the agent (= BodyCenter) position, so the direction degenerates to `Vector2.ZERO` and the enemy gracefully stands still.

**Gameplay distances are BodyCenter-to-BodyCenter**: `distance_to_player` (`stop_distance` / `attack_distance`) uses the enemy's BodyCenter (`_nav_anchor.global_position`) to the player's BodyCenter (`player_body_center`, cached in `_setup_base`; fallback to each origin). This is the **same frame the chase uses** (`makepath` targets the player's BodyCenter, and the enemy navigates its own BodyCenter) — so the enemy stops and switches to its attack animation exactly when the two **bodies** are close, matching what it is chasing. The game simulates 2.5D depth but is essentially 2D: consistency with the chased point matters more than the height-symmetry an origin-to-origin measure would give. (Historically this was feet-to-feet at the scene origins, which drifted from the chased BodyCenter and made enemies stop/attack based on the wrong point.)

**Body-anchored systems all read the BodyCenter** (via `get_node_or_null("BodyCenter")`, falling back to the origin): enemy pathfinding target (`makepath`), item drops (`_spawn_single_drop_item`, base = enemy's own BodyCenter via `_nav_anchor`), **enemy knockback direction** (see *Knockback*), **power targeting** (every attack that chases an enemy — see *Attack system*), player-attached attacks, and the **camera** (follows the player's body, not its feet). **On enemies the canonical accessor is `EnemyBase.get_body_center_position()`** (fallback chain `BodyCenter` → `_nav_anchor` → origin) — never read `enemy.global_position` when you mean "where the body is": the scene origin is the FEET, and using it injects a systematic downward bias. **On the player the symmetric accessor is `PlayerBase.get_body_center_position()`** (fallback `BodyCenter` → origin), used by the camera, attached-attack spawn, and the gear orbit (`player.to_local(...)` — gear lives in the player's local frame). One deliberate exception: `EnemyBase` caches the player's BodyCenter *node* (`player_body_center`) and reads `.global_position` in `update_direction()`, a per-frame per-enemy hot path where a node-property read beats a method call — do not "uniformise" it. The cache assumes **one player per run, created before the enemies and alive for the whole match** — no runtime player swap in a stage that has enemies (see *Player*: swapping is legal only in the safe house). So the risk is not staleness but **creation order**, and that is now handled: `PlayerSpawner` creates the player and sits as the stage's first child, so it runs before `SpawnManagerConfig` calls `start_spawning()`; a wrong order makes `start_spawning()` `push_error` and never enable spawning, so no enemy is ever born with an empty cache. The camera already tolerates a missing player via per-frame re-acquisition. `AttackController._spawn_single_projectile()` places **any** `attach_to_player` attack at the player's BodyCenter local position — automatic for future attacks with that flag, no per-attack code needed (current: electricity, gear). **Exception — attacks that rewrite their own `position` every physics frame** (orbitals like `power_05_gear`): the spawn placement is overwritten on the first frame, so their movement formula must add the body offset itself — gear captures `_orbit_center_offset` from the player's BodyCenter in `_ready` and adds it to the orbit position. Any future self-positioning attached attack needs the same anchoring.

**Marker nodes degrade gracefully, never crash**: position markers (`BodyCenter`, `AttackPositionRight/Left`) are **all declared in `PlayerBase`** with `get_node_or_null`, and every consumer has a fallback chain ending in a property that always exists — e.g. projectile spawn: `AttackPositionRight/Left` → player `BodyCenter` (`PlayerBase.get_body_center_position()`) → `player.global_position`. A player scene missing markers still works (attacks spawn slightly off) and `AttackController.setup()` emits one `push_warning` so the omission is visible in the console. Follow this pattern for any new marker node.

**The contract is "degrade AND warn" — a silent fallback is a bug.** Falling back keeps the game running, but the degradation (e.g. everything silently re-anchoring to the FEET) is nearly invisible in play, so every fallback needs a one-time warning. Two rules make the warnings usable:
- **Warn at initialization, never at the point of use.** Most consumers sit in hot paths (`_enemy_body_position()` runs per targeting call, `_setup_base()` runs per spawn) — a warning there would flood the console.
- **Warn once per *scene*, not per instance**, via a static `Dictionary` guard keyed by `scene_file_path`. A horde of 200 gators must produce **one** warning, not 200.

Current guards (all at init, all silent when the project is correct):

| Guard | Where | Catches |
|---|---|---|
| Player `BodyCenter` | `AttackController.setup()` | projectile spawn, `attach_to_player` attacks, gear orbit centre and enemy chasing all falling back to the feet |
| `Hurtbox` / `EnemyHurtbox` group | `EnemyBase._validate_scene_setup()` | **enemy would be invulnerable** (powers gate damage on that group) |
| Enemy `BodyCenter` | `EnemyBase._validate_scene_setup()` | aim, knockback and navigation reverting to the feet |
| `NavigationAgent2D` not under `BodyCenter` | `EnemyBase._validate_scene_setup()` | navigation silently returning to the feet frame (the historical "arc" bug) |
| `Hurtbox` / `PlayerHurtbox` group | `PlayerBase._validate_scene_setup()` | **player immune to contact damage** |

**New enemy checklist**: origin at feet · `BodyCenter` node at collider center · `NavigationAgent2D` as child of `BodyCenter` · `Hurtbox` in the `EnemyHurtbox` group (or the enemy is invulnerable) · fill the `Spawn Fit` group in its `EnemySpawnData` (see Spawn system) · root configured for Y-sort (`z_index = 2`, `y_sort_enabled = true` — see Y-sort). **A new "only chases" enemy needs no new script** — point its scene's root at `enemy_chaser.gd` and calibrate in the Inspector; write a script only when the *logic* differs (then extend `EnemyBase` directly, using `@onready` path `$BodyCenter/NavigationAgent2D`).

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

- **`scripts/player_base.gd`** — `CharacterBody2D` base class: FSM (idle/walk/attack/dead), movement, `take_damage()`, flash effect, audio.
- **Concrete player scenes** live in `entities/players/` (`major_heat.tscn`, `sonic_gal.tscn`, and more to come) — **every one of them shares the same script `scripts/player_character.gd`** (extends `PlayerBase`), differing only by Inspector calibration and assets. A new character normally needs **no new script**: build the scene, point its root at `player_character.gd`, and calibrate. Two layers, not three: `PlayerBase` (FSM, input movement, damage, audio — scene-agnostic) → `player_character.gd` (wires the concrete nodes, flip + `facing_direction`, the visual FSM, and the attack cycle whose duration comes from `anim.get_animation(...).length`). Unlike enemies, players have **no divergent archetypes** — every player walks by input and attacks via `AttackController` — so a third layer only appears if a future player diverges in *logic* (a dash, a transformation), never merely in art: animations are driven by **name and time** (`current_animation_position`), never by frame index, so a player with a different frame count shares the same script untouched. Named for its **role** (`player_character`), not for a mechanism (`player_animated` would age badly the moment a player animates differently).
- **The player is CREATED AT RUNTIME by `entities/stage_parts/player_spawner.tscn` (`scripts/player_spawner.gd`) — never placed by hand in a stage.** Root is a **`Marker2D`**: here the node's transform **is** the data (it marks where the player appears), unlike `NavmeshMerger`, which is also `Node2D` but whose position is ignored. Not an `Area2D` — it detects nothing, it is read; the swap chamber is what detects (see *Chambers*). Creation itself lives in the static `PlayerSpawner.spawn(scene, at, from)` (`class_name PlayerSpawner`), shared by this spawner and the chamber, so one place decides how a player enters the world.
  - **Which character comes from `PlayerRosterGlobal`, with a two-state override on the instance.** Cascade: the spawner's `forced_player` export (filled) → `PlayerRosterGlobal.get_selected_player()` → `PlayerRosterGlobal.DEFAULT_PLAYER`. **Empty `forced_player` is the normal case, not an omission** (same discipline as `enemy_spawn_excluded_layers`); filling it means *this stage imposes this character* — a tutorial, an intro, a stage scripted around one character.
  - **It adds the player to the `YSortContainer`, resolved by group**, exactly as `SpawnManagerConfig` resolves the enemy parent. Outside the container the effective z is `2` instead of `4` and the player renders permanently behind every enemy; the fallback (own parent) warns and says so.
  - **It refuses to spawn if the `Player` group is already occupied**, with a warning — the net against leaving a hand-placed player in a stage, which would give two players and silently break every system that resolves the player by group.
  - **Tree order: place it as the FIRST child of the stage.** `_ready()` runs in tree order, so being first puts the player in place before `Camera`, `LoadoutBar` and — the one that matters — `SpawnManagerConfig`, whose `initialize_spawn_manager()` calls `start_spawning()` and looks up the `Player` group. A wrong order **fails loudly** (`push_error`, spawn never enabled), never silently.
- **`PlayerRosterGlobal` is a separate autoload, NOT a variable in `GameStateGlobal`, and the criterion is LIFETIME.** `GameStateGlobal` holds *match* state (health, the FSM) and `restart_game()` is documented as the single place that clears cross-session state. Nothing in the roster may be cleared: dying and restarting must not change your character, and unlocks will go to a save file. Keeping it there would work today and leave the trap of whoever next adds to `restart_game()` having to remember *not* to clear those lines. Named for the **role** (the roster) — `PlayerSelection` would age badly the day unlocks land.
  - **API:** `select_player(scene)` (written by the chambers; emits `selected_player_changed`), `get_selected_player()` (never null — falls back to `DEFAULT_PLAYER`), `is_selected(scene)` (compares by `resource_path`, so it does not depend on both references coming from the same cache).
  - **The chosen character is a `PackedScene`, and that is the whole identity — there is NO integer ID system, and none is planned.** `player_character.gd` is shared by every character, so no code needs to know *which* player. An `attack_id`-style int exists only where **three** things must agree (`AttackData` ↔ `AttackUpgradeData` ↔ timer); nothing here needs joining. Saving to disk would need the `uid://` **string**, still not an int, and a per-character `PlayerData` resource (name, portrait, locked state) would *replace* an ID system rather than require one.
- **A player swap at runtime is only legal in a scene with NO enemies.** `EnemyBase` caches the player's `BodyCenter` **node** and `SpawnManagerGlobal.player` is captured once in `start_spawning()` — a swap in a combat stage dangles both, per live enemy. This is why character choice belongs in the safe house (a chamber the player walks up to), not in a combat stage. It is a rule, not a coincidence of where the chambers were placed.
- Player has two child controller nodes: **`AttackController`** and **`PowerUpController`**.
- Health state lives entirely in `GameStateGlobal` (registered via `register_player()`); the player node just calls `take_damage()` there.
- **The overhead `HealthBar` and `HealthLabel` hide in `EXPLORATION`** (`scripts/health_bar.gd`, `scripts/health_label.gd`): in the safe house health does not matter, and a bar over the head reads oddly there. Each connects to `GameStateGlobal.state_changed` **and applies the current state in its own `_ready()`** — a signal only reports *transitions*, and the player is born in the safe house with the mode already declared by `StageConfig` in `_enter_tree()`, so no transition would ever arrive (same lesson as the Barrier's `_reconcile_phasing()`). The condition is the **specific state**, never `is_combat_allowed()`, which is also false in `PAUSED` and `UPGRADE` — hiding health when you pause would be wrong. Invisible is not disabled: `HealthBar._process()` keeps animating behind it (cheap). The label's damage blink writes `modulate`, not `visible`, so the two never collide. The label shows health **truncated** (98.7 shows "98", not "99") — deliberate, common in games — **but never "0" while the player is alive**: with health > 0 it shows at least "1" (`maxi(1, int(current))`), the same rule as the bar, which with health > 0 always paints at least 1 px. Before, 0.37 health showed "0" on a living player. If a third element or a second state (`DIALOGUE`, `CUTSCENE`) needs the same rule, centralise it then.
- Armor from `PowerUpStatsGlobal.get_armor_damage_reduction()` is applied before forwarding damage.
- Follows the **feet origin + BodyCenter** convention (see Entity anatomy). The physics collider is at the feet; the `BodyCenter` marker is what enemies chase (`makepath` targets it).

### Attack system

Three-layer design:

1. **`AttackData`** (`data/attack_data/attack_data.gd`) — `Resource` with base stats for one attack: scene, timing (`interval`), damage, speed, projectile count, etc. One `.tres` per attack in `data/attack_data/`.
2. **`AttackUpgradeData`** (`data/attack_upgrade_data/attack_upgrade_data.gd`) — `Resource` with per-level arrays (e.g. `cooldown_reduction_per_level`). Values are **additive**: `get_cooldown_reduction()` sums `arr[0..current_level-1]`. One `.tres` per attack in `data/attack_upgrade_data/`.
3. **`AttackController`** (`scripts/attack_controller.gd`) — Node child of player. Owns a `Timer` per attack. On `_ready`, **duplicates** all `AttackUpgradeData` resources to prevent shared state. Detects level changes via `_physics_process → _check_upgrade_changes()` polling.

**Cooldown formula** (additive, not multiplicative):
```
wait_time = base_interval × (1 − clamp(attack_cd_reduction + global_cd_reduction, 0, 0.99))
```
Minimum interval floor: `0.05s`. Recalculated whenever `PowerUpStatsGlobal.stats_changed` fires.

**Linking key:** `attack_id` (integer) connects `AttackData` ↔ `AttackUpgradeData` ↔ timer in `attack_timers` dictionary.

**The RESOURCE owns the level ceiling — controllers ask, never check-and-write.** `AttackController.apply_upgrade()` calls `upgrade.level_up()`, exactly as `PowerUpController.apply_upgrade()` calls `powerup.level_up()`; the `max_level` test lives once, inside the resource. It used to be duplicated: `AttackUpgradeData.level_up()` existed with the rule inside it, and the controller re-implemented the same test and wrote `current_level += 1` itself — so editing the rule in the obvious place (the resource) would have changed powerups and silently left attacks alone. Same trap as the old duplicated `body_center_offset`, with a *rule* instead of a value. **Setting a level to zero (`disable_attack`, `remove_powerup`) is still a direct write on both sides** — that is a reset, not an increment, and the two controllers already agree.
  - **Hitting max level returns `false` silently — it is not a warning.** It used to `push_warning`, which lit the editor's error panel every time a player simply maxed an attack. A full attack is normal gameplay; the caller decides whether to say anything (the debug tool prints). The *other* `push_warning` in that function — `Upgrade not found for attack_id` — stays, because an attack with no configured upgrade **is** a misconfiguration.

**Adding a level to an existing attack means editing TWO places, and forgetting either fails silently.** `max_level` is its own `@export` (default `5`), **not** derived from the per-level arrays, while `_sum_int`/`_sum_float` accumulate over `min(current_level, arr.size())`. So: raise `max_level` and forget to extend an array → the new level is reachable but grants that array's bonus at the previous level's value, no error; extend the arrays and forget `max_level` → the new entries are unreachable dead data, no error. Both edits happen in the same `.tres` Inspector — do them together. (The arrays may legitimately have *different* lengths from each other: a shorter one simply stops contributing at its last entry, which is how "this attack gains projectiles only up to level 3" is expressed.)

**Attack scenes** live in `entities/powers/`: `power_01_fire`, `power_02_ring`, `power_03_electricity`, `power_04_bo`, `power_05_gear`, `power_06_snowflake`. All extend **`BasePower`** (`scripts/base_power.gd`).

**`attack_scale` is applied through `node.scale`**, never by resizing shapes: `BasePower._apply_attack_scale()` scales the **direct children** of type `CollisionShape2D` and `AnimatedSprite2D` — any shape type works, and it matches the power standard (every power animates with an `AnimatedSprite2D` and has a collider). Not scaled: `Sprite2D`, `Polygon2D` or deeper nodes. Two powers handle scale themselves: `power_04_bo` overrides it with its dynamic grow/shrink in flight, and `power_06_snowflake` has no `CollisionShape2D` in its scene (it creates one by code) and scales it and its sprite by hand. A future power with a still image: use an `AnimatedSprite2D` with one frame (zero code), or add the `Sprite2D` case to `_apply_attack_scale()`.

**`power_02_ring` keeps `projectile_stagger_delay > 0`** — confirmed in code: the rings of one volley spawn at the same point, with the same direction, and all aim at the **same** nearest enemy, so at 0 they would fly identical paths, stacked. Base 0.2; the upgrades subtract 0.015 on four levels, so the minimum at max level is 0.14.

**`BasePower`** — `Area2D` base for all projectiles: life-time countdown, per-enemy hit cooldown (`enemies_last_hit`), damage calculation (additive: `damage_upgrade_bonus + (damage_multiplier − 1.0)`), knockback multiplier from globals. Provides `calculate_projectile_spread_angles()`, `find_nearest_enemy_on_screen()`, `find_random_enemy_on_screen()`, and **`_enemy_body_position(enemy)`**.

**Targeting reads the enemy's BODY, never its origin.** `_enemy_body_position()` resolves to `EnemyBase.get_body_center_position()` (with a defensive fallback) and is the **only** way a power should read an enemy's position — both to pick a target and to aim at it. Reading `enemy.global_position` targets the **feet**, ~10 px below the body on the gator and ~15 px on the red gator, which visibly makes attacks converge on the ground. It is used by the shared selection helpers (on-screen test + distance ranking, so an enemy whose body is visible but whose feet are off-screen still counts) and by the three chasing attacks: `power_02_ring` (arc destination), `power_04_bo` (straight-shot direction), `power_06_snowflake` (where the flake spawns). Any future enemy-seeking attack must use it too.

**Damage bonus is additive** across sources: `damage_upgrade_bonus` (from `AttackUpgradeData`) + global powerup bonus are summed once and applied as `damage × (1 + total_bonus)`.

### Enemy system

- **`scripts/enemy_base.gd`** — `CharacterBody2D` base: FSM (IDLE/WALK/DEAD), NavigationAgent2D pathfinding + **context-steering** inter-enemy avoidance (see *Enemy inter-enemy avoidance*), knockback with chain-transfer to adjacent enemies, item drops, `receive_hit()` / `die()`.
- **`_guard_against_position_jump()`** in `enemy_base.gd` — called every physics frame after `move_and_slide()`. Compares actual displacement against `velocity × delta × 3.0` (floor: 2 px); if exceeded, clamps the position back. This suppresses anomalous pixel-jumps that `move_and_slide()` produces when resolving collisions near walls or corners. Symptom that motivated it: enemies spawned or teleported near walls would visibly snap a few pixels in a random direction when the player moved toward/away from walls.
- Concrete enemies: `entities/enemies/gator.tscn` and `red_gator.tscn` — **both use the same script `scripts/enemy_chaser.gd`** and differ only by Inspector calibration (stats, sprites, `steer_*`). Enemy logic lives in **three layers**: `EnemyBase` (everything shared — FSM, movement, steering, knockback, drops) → **`enemy_chaser.gd`** (the "only chases the player" archetype: wires the concrete nodes to the base's generic vars, `queue_free` on death, impact effect, contact-damage handlers) → a **per-enemy script only when the *logic* diverges** (a shooter, a flyer…), which extends `EnemyBase` directly and skips `enemy_chaser`. Animation is **scene data** (`SpriteFrames`), never in the script, so chasers with different sprites/frame-counts still share `enemy_chaser`. Named by archetype (`enemy_chaser`), not by instance (`enemy01`); no `class_name` for now (deliberate, revisit when a second archetype appears).
- Enemies belong to group `"Enemy"` (added by `enemy_base.gd`, not by the scene) and their `Hurtbox` to `"EnemyHurtbox"` (marked per scene) — see *Node groups*.
- After spawning or teleporting, always call `enemy.makepath()` to recalculate navigation from the new position.
- **Item drop system**: on `die()`, `EnemyBase` rolls `drop_chance` once, then drops `min/max_drop_amount` items scattered within `drop_spread_radius`. Each dropped unit is picked independently from `drop_table` (`Array[ItemDropData]`) via weighted random in `_choose_drop_item()` — same weight logic as `choose_enemy()`, null-safe. `ItemDropData` (`data/item_drop/item_drop_data.gd`) holds just `item_scene` + `spawn_weight`. Drop tables are configured as **embedded resources** in each enemy scene's Inspector (not `.tres` files), so different enemies can drop the same item with independent weights. New enemies need zero drop code — Inspector only.
- **`modulate` is split by channel between two visual effects — RGB vs alpha, each with a single owner.** Damage flash (`flash_red()`, export `flash_color`) writes only RGB via `_set_tint()`, which rebuilds the color keeping `anim.modulate.a` untouched. The Barrier ghost effect (`set_phasing()`, export `phase_alpha`) writes only `.a`. This is why `flash_color`'s own alpha is **ignored** — `_set_tint()` never reads `tint.a` — so the two effects don't stomp each other and can render simultaneously (an enemy can flash red while ghosted). This channel split is a **stopgap, not an architecture**: it only works because exactly two effects exist and each claimed a different channel by chance. A third effect wanting either channel (or changing damage flash to blink alpha) would conflict again — the real fix is a single "modulate arbitrator" that all effects report state to instead of writing `modulate` directly, not yet built.

### Spawn system (`SpawnManagerGlobal`)

Budget-based enemy spawn with grid sampling and a teleport system. Full rules: `.claude/rules/spawn.md`. It loads by itself when the spawn files are touched; read it first when discussing spawn without opening them. Covers how many enemies appear and when (budget, difficulty, `max_enemies`), where they appear (offscreen grid sampling, walkable ground, excluded layers, wall clearance, enemy spacing, enemies stuck to walls or overlapping), the teleport of distant enemies, per-stage calibration (`SpawnManagerConfig`, `EnemySpawnData`) and spawn stutter.

### XP & Level-up flow

1. Enemy dies → drops XP item(s) chosen from its `drop_table` (see Enemy system). All XP items share `scripts/xp_item.gd` (`class_name XPItem`) and differ only by Inspector calibration (`xp_value`, sprite) — e.g. `xp_item_01.tscn`, `xp_item_02.tscn`. New item scripts are only created when collect logic diverges (e.g. a future healing item).
2. Player picks up item → `XPManagerGlobal.add_xp()`.
3. XP fills → `level_up` signal → `LevelUpManagerGlobal._on_level_up()`.
4. `LevelUpManager` pauses game (`GameStateGlobal.UPGRADE`), generates 3 options from `AttackController` and `PowerUpController` pools.
5. Player selects → `controller.apply_upgrade(id)` → `current_level++` on the relevant resource.
6. `AttackController._check_upgrade_changes()` detects the level change next physics frame and updates the timer.

**XP curve** — `XPManager` computes the requirement for the next level in `_calculate_xp_requirement()`, selected by `xp_scaling_type` (`ScalingType`). Four modes, all kept:
- `LINEAR` — `base × level`: constant increment, never accelerates.
- `EXPONENTIAL` — `base × factor^(level−1)`: geometric; uses `xp_scaling_factor`. Its shape is inherently *flat start + late explosion* (small base + `int()` truncation glues the first steps, then the ratio compounds into thousands) — hard to tune well.
- `FIXED` — `base`: same cost every level.
- `POWER` — `base × level^exponent`: polynomial; uses `xp_power_exponent`. Rising steps from level 1 with no runaway — the mode that gave the wanted pacing where the other three couldn't, and the current default.

Key facts: `base_xp_requirement` sets level 1's cost and anchors **every** mode (level 1 always costs `base`, since all four formulas equal `base` at level 1). `xp_scaling_factor` is used by **EXPONENTIAL only**; `xp_power_exponent` by **POWER only**. `xp_to_next_level` is an **output** (recomputed each level), never an input — editing it does nothing. The requirement is only one side of pacing; XP *supply* (drop rate + item value) is the other — tune the curve first, then the drops. (Concrete factor/exponent/base values are live calibration, not documented here; they may become per-stage later.)

**Implicit level-up queue** — `XPManager._check_level_up()` grants at most **1 level per call** (`if`, not `while`) and is blocked by `is_waiting_for_upgrade` while a menu is pending. Surplus XP stays in `current_xp` and acts as the queue: when the player confirms a choice, `LevelUpManager.apply_upgrade()` calls `XPManagerGlobal.upgrade_selected()`, which re-checks the surplus — if it covers another level, a new menu opens **synchronously** and the game stays paused in UPGRADE (no COMBAT flicker between chained menus). Two ordering constraints keep the synchronous chain working: `apply_upgrade()` re-checks *before* unpausing (and returns without unpausing if a new menu opened), and `level_up_ui._on_option_pressed()` hides the menu *before* emitting `option_selected` (hiding after would erase the newly opened menu).

**XPBar is pause-immune** — `process_mode = PROCESS_MODE_ALWAYS` so level-up animations (label pulse, bar fill) complete behind the paused upgrade menu. Values can't change during pause (`add_xp` is gated by `is_combat_allowed()`). Gotcha: `get_tree().create_timer()` inside XPBar sequences must pass `process_always = true` — SceneTree timers ignore the node's `process_mode` and would freeze the animation chain mid-sequence.

**Unlock notifications reach the LoadoutBar via two asymmetric routes** (pause does not block signals — only `_process`/`_physics_process`/input): `PowerUpController` emits `powerup_unlocked` synchronously inside `apply_upgrade()`, but `AttackController` emits `attack_unlocked` from its `_physics_process` polling, which is paused during the upgrade menu — so it only fires after unpause, too late for chained menus. `LoadoutBar` therefore listens to **both** `LevelUpManagerGlobal.upgrade_applied` (synchronous, updates during pause; only acts on `next_level == 1`) and the controller signals (covers debug keys and future unlock sources), deduplicating by id (`filled_attack_ids` / `filled_powerup_ids`) since menu unlocks arrive through both routes. Don't "fix" the asymmetry by making `AttackController` process-always or by calling `_check_upgrade_changes()` synchronously — attack timers would tick during pause, and `start_immediately` shots would be swallowed by the `is_combat_allowed()` guard.

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

**`@tool` scenes and the `RESET` animation.** Traps of the Godot editor that apply to any `@tool` script and any `AnimationPlayer`. Full rules: `.claude/rules/godot-tool-scenes.md`. It loads by itself with the existing `@tool` files; **read it first before writing or changing any `@tool` script or keying a new animation track.** Covers resize code that silently does nothing, resizing one instance changing all the others, a value that will not stick in the Inspector, and reacting to a manual rotation in the editor.

### PowerUp system

- **`PowerUpController`** (`entities/controllers/power_up_controller.tscn`) — child of player; holds `Array[PowerUpData]`. `apply_upgrade(id)` increments level and recomputes all stats into `PowerUpStatsGlobal.update_stats()`.
- Powerup data lives in `data/power_up_data/`.
- **Per-level arrays are INCREMENTS, summed** — same rule as `AttackUpgradeData`: `PowerUpData` sums `arr[0..current_level-1]` (since v1.3.6), so `[20, 20, 20]` means +20 per level and 60 at level 3, not "the value at level 3". And the **two-place rule applies here too**: raising `max_level` without extending the arrays, or the reverse, fails silently (see *Attack system*).
- `PowerUpStatsGlobal.stats_changed` triggers `AttackController._on_stats_changed()` to recalculate all attack timers immediately.

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
3. **Belongs to a specific child node** → that scene's **Groups tab** (`EnemyHurtbox`, `PlayerHurtbox`). These are the only groups repeated scene by scene, so they are the easiest to forget — and forgetting one makes that entity **invulnerable**. Both are covered by init guards (see *Marker nodes*).
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
- **Versioning**: semântico `v1.x.x` nos comentários de código.
- **`@export` discipline**: only fields that must appear in the Inspector. Non-`@export` fields are **not copied by `duplicate(true)`** — fields set at runtime that need to survive a `duplicate()` call must be `@export`. Two consequences that have already cost time here:
  - **`@export` on a script autoload is decorative.** Autoloads registered as `*res://…gd` (all of them here) are instantiated by the engine with no Inspector and no serialization, so their exports can never be edited or stored — the values always arrive from elsewhere (for `SpawnManagerGlobal`, from `SpawnManagerConfig`). Don't read an `@export` there as "a knob someone can turn".
  - **Removing or renaming an `@export` orphans the value already stored in every scene.** Godot rewrites `NodePath`s automatically but never property *names*, so the old `name = value` line stays in the `.tscn` pointing at nothing and is silently ignored. Harmless when the property was inert; a silent loss of calibration when it was not. **Delete those lines from the affected scenes in the same pass** (with Godot closed) rather than relying on the editor to drop them on the next save.
- **Resource duplication**: `AttackUpgradeData` resources are duplicated in `AttackController._ready()` so editor assets are never mutated at runtime. Always duplicate before modifying shared resources.
- **Resource sharing strategy** — pick by how the data varies: data that must be identical everywhere (attack stats, powerups) → shared `.tres` + runtime `duplicate()`; data owned by one scene/instance (enemy drop tables, per-stage spawn definitions) → embedded resources created directly in the Inspector. Embedded resources live inside the scene file and are invisible in the FileSystem dock — use the resource's `resource_name` field to label them in Array slots. When a scene is instanced (e.g. `SpawnManagerConfig` inside a stage), configure embedded resources on the **instance**, not the base scene, or the data leaks into every instance.
- **`attack_id` is the join key** between `AttackData`, `AttackUpgradeData`, and `attack_timers`. Keep IDs consistent across all three.
- **Additive bonuses everywhere**: cooldown, damage, and projectile speed all use `base × (1 + sum_of_bonuses)` — never chain multiplications. For speed, `speed_upgrade_bonus` (per-attack upgrade) and `projectile_speed_multiplier − 1.0` (global powerup) are summed before applying. `power_05_gear` is the one exception: the global speed bonus is dampened by `orbit_speed_effectiveness` (currently `0.4`) before summing, because orbital speed generates hits much more efficiently than linear speed — but the gear's own `orbit_speed_upgrade_bonus` always enters at full value.
- **Asset references in code use `uid://`, never `res://` paths**: uids survive file moves/reorganization (which happens often here); string paths silently break — `load()` and `change_scene_to_file()` are **not** tracked by the editor and keep pointing at the old path. Bind the uid to a descriptively-named `const`/`var` so the reference is self-documenting (e.g. `const LEVEL_UP_UI_SCENE = preload("uid://...")`); **when there is no such name** (e.g. an inline `preload` inside a call), add a short comment naming the target file (e.g. `set_script(preload("uid://..."))  # uid = scripts/debug_drawer.gd`). Use `preload` (load-time) for assets always used; `load(uid)` for conditional/rare ones (e.g. the debug overlay). **Never hand-write uids** — let Godot generate them; a typed uid with `_` or characters outside `0-9a-z` is invalid and unresolvable (Godot can't register it, so `Copy UID` and `load` both fail).
- **`super._ready()` in subclasses**: GDScript does **not** run the parent's `_ready()` automatically — defining `_ready()` in a subclass fully overrides it. So: subclass **has** its own `_ready()` → it must call **`super._ready()` as the first line**; subclass has **no** `_ready()` → nothing to do, the parent's runs. This already bit the project: `power_02/04/06` each duplicated `add_to_group("Power")` because they overrode `_ready()` without `super`. The `Power` group now has a single source in `base_power.gd` and **depends on those `super._ready()` calls** (`power_05_gear.gd` was the original correct example).
- **`is_combat_allowed()` gate**: every system that acts on combat state (attacking, taking damage, gaining XP) must check this before proceeding. Spawning and enemy movement are deliberately outside it today — see *Critical gate*.
- **Restart must reset autoload state**: `reload_current_scene()` rebuilds only the stage — autoloads and **everything they own survive it**. The single place that clears cross-session state is `GameStateGlobal._end_current_scene()` (scene audio, XP, spawning, audio pool, target tracker, holds), shared by `restart_game()` and `go_to_scene()`; any new autoload that accumulates runtime state must be reset **there**, so both paths get it. This really bit: the `AudioManager` pool's players are children of the autoload, not of the stage, so an attack sound kept playing into the next run long after the attack scene had been freed.
- **Deferred calls for spawning**: use `call_deferred` or `add_child` then set `global_position` afterward (so `_ready` runs before position is overwritten).
- **Audio buses**: SFX plays on the `"SFX"` bus. Powers that manage looping audio set `handles_own_audio = true` on their `AttackData` to suppress the controller from also playing it.
- **Audio export naming**: every configurable sound exposes three exports named `<name>_sound`, `<name>_sound_volume_db` (default `0.0`) and `<name>_sound_pitch_scale` (default `1.0`), passed straight to `AudioManagerGlobal.play_sound_2d(sound, position, volume_db, pitch_scale)`. Sounds are played through the AudioManager's pool — **no per-scene `AudioStreamPlayer` node**. Older code predates this convention and still uses shorter names; migrate to this form when touching it.
- **Pool is for fire-and-forget sounds; sounds with state keep their own player.** Two documented exceptions, both deliberate: **stage music** (an `AudioStreamPlayer` node in the stage — continuous, needs its own loop/stop control, and belongs on the `Music` bus) and the **player's hit sound** (`PlayerBase` creates `audio_hit`/`audio_death` in code). The hit sound can fire ~10×/s from contact damage, and its anti-spam is *"let the sound finish, then wait `hit_post_delay`"* — it listens to that player's `finished` signal, so the clip is **never cut mid-play**. The pool can't do this: it lends an anonymous player and returns no reference, and its own guard is a fixed global `MIN_INTERVAL` that would let most hits through and overlap. Don't "fix" this by forcing it into the pool without first giving the pool a way to report when a specific sound ended.

## Debug and test systems (inventory + status)

Everything in the project that exists only to test or observe. **Kept here so nobody has to rediscover it**, and so that "is this dirt or is this deliberate?" has a written answer.

| What | Where | Status |
|---|---|---|
| `TestPowerups` — keys `1`–`8` apply powerups, `R` reset, `L` list, `S` stats | node in **every** player scene (`scripts/test_powerups.gd`); switch: `const ENABLED` | **Stays.** In daily use |
| `TestAttackUpgrades` — `E T Y U I O` raise each attack one level, `X` list | node in **every** player scene (`scripts/test_attack_upgrades.gd`); switch: `const ENABLED` | **Stays.** In daily use |
| Spawn log + grid overlay | `debug_enabled` / `debug_draw_enabled` on `SpawnManagerConfig`; `debug/debug_draw_overlay.tscn`, `scripts/debug_draw_overlay.gd`, `scripts/debug_drawer.gd` | Gated, **off** in stage_01. Files stay |
| `NavmeshMerger` `log_bake` (default on) / `verify_connectivity` (default off) | `scripts/navmesh_merger.gd` | **Not test code.** Production diagnostics with a switch; both stay |

**Turning both off is two edits: `const ENABLED: bool = true` → `false`, at the top of `scripts/test_powerups.gd` and `scripts/test_attack_upgrades.gd`.** With it `false`, `_ready()` calls `set_process_input(false)` and returns before printing: no key reaches the tool, no help text reaches the console (so someone outside the project never learns the keys), and the node stays in the scene doing nothing. The two tools are independent — one may be on and the other off.

- **It is a `const` in the script, deliberately NOT an `@export` on the node.** "Are the test tools on?" is a fact about the **work session**, not about a character. As an `@export` the value would live inside each player scene: one more place to edit and to diverge invisibly per character (`bo_girl` off while `sonic_gal` is on, with nothing in the console saying so), and the question "are they off?" would only be answerable by opening every player scene. It would also orphan the stored `enabled = …` lines across those scenes the day the property is removed (see *`@export` discipline*).
- **The check belongs in `_ready()`, not at the top of `_input()`.** Guarding only `_input()` would still print the help text and still route every input event through the tool. One place, one effect.
- **Pause behaviour is untouched and must stay so:** these nodes are children of the player, so `get_tree().paused` freezes them — the keys are already dead during PAUSED and UPGRADE. Do not give them `PROCESS_MODE_ALWAYS`.

**These two are nodes duplicated across the player scenes only because the later players were built as copies of the first.** There is no technical reason for it — both find their target through the `Player` group in `_ready()`, so both *could* be autoloads resolved once, and a new player scene built from scratch would silently lack them. **Converting them was evaluated and REFUSED (2026-09-28); revisit only if the player scenes themselves get reworked.** `PlayerSpawner` did not change the argument: it rebuilds the player — and therefore these nodes — on every scene load and on every chamber swap, so the "destroyed and rebuilt with the player" guarantee below still holds. The duplication is one node line, not one copy of logic: a single script is referenced by every player scene, so editing it already affects them all. Against that, the move costs real properties the current shape gives for free: as children of the player these nodes are destroyed and rebuilt by `reload_current_scene()`, so a cached controller reference can never dangle — an autoload survives the restart and would need lazy per-keypress resolution written just to restore that guarantee; and because the keys are **raw keycodes**, not Input Map actions, a global autoload would deliver them to every scene in the game, including future menus, where today the tools simply don't exist. A forgotten node announces itself on the first keypress — that is a checklist step, not technical debt.

**Two production methods are kept alive by `TestPowerups` alone and are commented as such** — `PowerUpController.remove_powerup()` (key `R`) and `list_active_powerups()` (key `L`). They are not dead code today, but they have a single caller and it is a debug tool: when that tool goes, they go with it. The comment sits on the methods, where the debt comes due. Four neighbours that had **no** caller at all were deleted in the same pass (`get_powerup_level`, and `AttackController`'s `disable_attack` / `enable_attack` / `upgrade_attack`, the last two already marked `DEPRECATED` by their own docstrings) — a public API nobody exercises is not a safety net, it is a promise never tested: `disable_attack()` zeroed a level without recalculating anything, while its powerup counterpart always called `_recalculate_all_stats()`, and no one ever found out which behaviour was right.

**A debug tool must reach the game through the same door the game uses.** `TestAttackUpgrades` used to *lower* attack levels by writing `upgrade.current_level -= 1` directly, with the comment "no method for this" — while `AttackUpgradeData.level_down()` had existed all along, validated and never called. It was the only place in the project producing a state no real match can reach, so a bug appearing only after those keys might not have been a bug at all. The feature was **removed** rather than fixed: lowering a level is not a game mechanic, and it had never been used. If it ever becomes one, it starts in the controller with its own validation and the tool merely calls it.

**A removed tool, for the record.** `LevelUpDebug` (keys `Z`/`C`/`V`) chose an option in the level-up menu by keyboard, back when no menu UI existed. Its own header said it would go "when the UI is ready"; the UI now works with keyboard, gamepad and mouse, so the tool survived purely on inertia. Removing it also removed `LevelUpManager.simulate_choice()` and `is_upgrade_active()`, which existed only to serve it. Note its autoload line read `##LevelUpDebug="…"` — the `##` did **not** comment it out, it became part of the singleton's *name*, which is why it kept loading and printing.

Godot writes `<scene>.tscn<hash>.tmp` snapshots when saving; 12 of them had been committed. `*.tmp` is now in `.gitignore` — never version them.

## Known bugs

*(none currently documented)*

## Calibration reference

### Knockback
- Decay is frame-rate independent: `knockback = knockback.move_toward(Vector2.ZERO, knockback_decay * delta)` — values are **per second**, calibrated per enemy in the Inspector (heavier enemies use higher decay so they travel less).
- `knockback_retention_after_transfer` default: `0.8` (export var on `EnemyBase`).
- **Direction, attack → enemy**: `receive_hit()` computes `(get_body_center_position() − source_pos)` — from the projectile's centre **through the enemy's centre of mass** (the `BodyCenter` sits exactly on the physical `CollisionShape2D`). The hit is *detected* on the `Hurtbox`, which is higher than the body (gator `−13` vs `−10`; red gator `−19` vs `−15`), so measuring to the scene origin (feet) added a **constant downward component** (~13 / ~19 px): a dead-on horizontal shot flung the enemy ~35° diagonally down, and upward knockback was nearly impossible. **`Hurtbox`, `CollisionShape2D` and `BodyCenter` may stay unaligned per enemy design** — only the BodyCenter matters for the impulse, because you push the mass, not the point you touched.
- **Direction, enemy → enemy (transfer)**: `handle_knockback_transfer()` uses the **real physics contact normal** from `get_slide_collision()` between the two body colliders — exact, and unaffected by the feet/BodyCenter question. The two mechanisms differ in method (approximation vs true normal) but now agree on *what* is pushed: the body.
- Residual approximation (accepted): the direction leaves the projectile's **centre**, not the surface contact point — `area_entered` gives no contact normal. Fine for small fast projectiles against roughly circular bodies; not compensated.

### Attack cooldown constants (`attack_controller.gd`)
- `COOLDOWN_REDUCTION_CAP = 0.99`
- `MIN_ATTACK_INTERVAL = 0.05`

### Enemy inter-enemy avoidance — Context Steering
Enemies dodge each other by context steering, not RVO, and the `NavigationAgent2D` only finds the route. Full rules: `.claude/rules/enemy-steering.md`. It loads by itself with `scripts/enemy_base.gd` and the enemy scenes; read it first when discussing enemy movement without opening them. Covers enemies that crowd, queue, stand still or slow down around each other, walls while dodging, the `steer_*` calibration, priority between enemies, why RVO was removed, repath spikes and `path_recalc_interval`.

### `power_06_snowflake`
- Uses `TargetTrackerGlobal`: FIFO exclusion list, max 5 recently-targeted enemies. Resets automatically when the batch interval elapses.
- Set `sprite.modulate.a = 0.0` before positioning the node to prevent a one-frame flicker at the origin.
- **No enemy on screen → it falls IN FRONT of the player, on the side they FACE**, from the player's BodyCenter (`fallback_distance_*`, `fallback_vertical_range`). The side comes from `set_power_direction()`, fed by `AttackController` with `int(player.facing_direction)` at fire time — the same door as the other directional powers. It used to read `velocity.x`: standing still `velocity` is `(0, 0)`, falsy in an `if`, so the default (right) won, and moving only vertically gave `x = 0` → right too; facing left while standing, the flake fell on the right. **Never derive "which side" from movement — use `facing_direction`.**

### Debug overlay (Grid Sampling) — only faithful at camera zoom = 1
- The spawn debug (`debug_draw_overlay`, gated by `SpawnManagerConfig.debug_draw_enabled`) draws on a `CanvasLayer` and projects world→screen by hand in `debug_drawer.gd`: `point - camera_position + viewport_size/2`, with **no zoom factor**. `CanvasLayer` also ignores the `Camera2D` transform.
- **Consequence:** it is only correct at camera **zoom = 1**. Under zoom-out (e.g. `0.5`) the scenery scales but the debug points do not, so they "parallax" (move faster than the world) and the overlay detaches — it does **not** work as a magnifying lens.
- **Even at zoom 1 the dots sit a couple of pixels off the tile they represent**: `camera_position` is captured in the *physics* frame (inside the debug dictionary) but `_draw()` runs in the *idle* frame, so the overlay projects with a camera position up to one frame stale while the world renders with the current one. Visible in pixel art, harmless in fact.
- **The spawn logic itself is zoom-invariant and camera-free** (the snap returns `layer.to_global(cell_centre)`, pure world space, and `spawn_enemy` writes that same coordinate); every discrepancy above is confined to the overlay's own projection. Don't misread the parallax or the offset as the spawn system malfunctioning.
- At zoom 1 the points only flash briefly near the screen edge (offscreen ones are culled), so the tool is of low practical use today. **Future fix:** draw in world space (a `Node2D` under the camera-affected world) instead of a `CanvasLayer`, so it inherits the camera transform and works at any zoom.

## Performance budget (measured, not assumed)

Target: **60 fps = 16.7 ms of CPU per frame**. Physics runs at a fixed 60 Hz while rendering runs free, so ~30% of drawn frames carry no physics tick — only the frames that *do* are worth measuring.

Measured on the dev machine with ~108 live enemies, wall-clock deltas, V-Sync off (so no wait is counted as work):

| Part | ms | Share |
|---|---|---|
| **navigation** (`update_direction()` × N) | **~0.35** | |
| engine servers (physics + navigation) | ~2.1 | |
| move_and_slide | 0.60 | |
| steering | 0.50 | |
| **rendering** | **~0.5** | |
| spawn + teleport + attacks | 0.14 | |
| **total** | **~5.2 ms** | |

The navigation row assumes the merged navmesh (see *NavmeshMerger*); before it, that single row cost **~3.1 ms** and dominated the frame.

A frame with **no** physics tick costs ~0.5 ms — subtracting it from the full frame is how the engine-server row above was isolated, without instrumenting the engine.

Express the target as **fixed cost + cost per enemy**, never as "the game handles N enemies": `max_enemies` is per-stage and deliberately undefined for a long while yet (see Spawn system).

Three conclusions that should stop old debates:

- **There is no longer a dominant cost.** Navigation used to be ~40% of the frame; the merged navmesh removed it. Steering, spawn, teleport, attacks and rendering **together** are under 1.8 ms — all closed subjects. Before optimizing anything here again, measure: nothing left is known to be expensive.
- **The stutters were never compute.** With V-Sync on, the same frame measured ~13.9 ms, of which ~7.5 ms was the game standing still waiting for the display; the judder came from the presentation path, not from work. A light CPU graph plus a bad feel means pacing, not load.
- **Rendering is free (~0.5 ms).** A 480×270 pixel-art game is nowhere near GPU-bound. Do not look there.

**Any future measurement must run with V-Sync disabled**, or the wait is silently attributed to whatever bucket closes the frame — which is exactly how a phantom "8.9 ms of engine/render cost" appeared and survived several rounds of analysis.

### NavmeshMerger — why the navmesh is baked, not per-tile

`TileMapLayer` creates **one navigation region per tile** (3,762 in stage_01). Every path query locates its start/end polygons by **linear scan over every polygon in the map**, so that scan — not the A* search — was the cost:

| | per-tile | merged |
|---|---|---|
| polygons | 3,762 | **206** |
| `map_get_closest_point` | 125 µs | **3.7 µs** |
| one path query | 313 µs | **19 µs** |
| in game, per enemy per frame | 39 µs | **4.3 µs** |

It was the *same* linear scan that already cost ~40 ms per spawn scan and forced reading tile data directly — reappearing through another door. **It scales with polygon count, never with enemy count**, which is why cutting enemies never helped.

**`entities/stage_parts/navmesh_merger.tscn`** (script `scripts/navmesh_merger.gd`) replaces those regions with a single baked one. It is a reusable **scene**, like every other stage piece (`stage_config`, `spawn_manager_config`, `y_sort_container`, `barrier`) — it used to be a bare `Node2D` with the script attached by hand in each stage, the only one off the pattern. The base scene stores **no** property values, so all three exports come from the script defaults (`mode = MERGED`, `log_bake` on, `verify_connectivity` off) — which is exactly the wanted project-wide default. **Configure on the instance, never on the base scene:** ticking `verify_connectivity` there would make every stage run 60 route checks on load (same rule as `SpawnManagerConfig`).

**It is a `Node2D` because of `get_world_2d()`, not because of its transform.** `get_world_2d()` lives on `CanvasItem`; a plain `Node` does not have it, and the script needs it twice to reach the 2D navigation map where the baked region is registered. Its own position is **ignored by design** — the region is registered with `Transform2D.IDENTITY`, and the tile polygons are converted through each `TileMapLayer`'s own `to_global()`. So moving this node in the editor changes nothing, and "simplifying" it to a plain `Node` would break the bake.

Non-obvious properties, all load-bearing:

- **It bakes in `_enter_tree()`.** Godot fires every `_enter_tree()` before any `_ready()`, so the mesh exists before `SpawnManager` starts and before any enemy calls `makepath()` — **regardless of where the node sits in the scene**. Moving it to `_ready()` would make correctness depend on tree order.
- **It reads each tile's REAL polygon, never the cell.** Every navigable tile is a full 16×16 square today, so both would agree — which is exactly what makes the shortcut dangerous: it would pass every test now and break silently on the first partial tile. Square tiles take a fast path (maximal rectangles, 3,762 cells → 166 rectangles); any other shape goes through the general union untouched.
- **`agent_radius = 0`** on the baked mesh, so the geometry matches the tiles exactly. Any positive value shrinks the mesh and changes where enemies can walk.
- **Per-tile navigation is disabled only after the bake succeeds.** Any failure warns and leaves the native navigation intact — the map is never left unnavigable.
- **It sweeps for layers with navigation** rather than taking a list, because that is the same union semantics the native navmesh applies. **Not** `enemy_spawn_excluded_layers`, which decides where enemies are *not born* (nor teleported to), not where they *walk*.
- **Reverting is one Inspector field**: `mode = PER_TILE`. The TileSet is never touched.
- **`verify_connectivity`** (opt-in) samples 60 point pairs and warns if any route no longer reaches its target. Run it after editing scenery; leave it off otherwise. It is **asymmetric** — it detects a *lost* passage, never an *invented* one (a spurious diagonal join would keep every route working). Only playing catches that.
- **A stage without the node still works**, on per-tile navigation — a silent performance regression, not a bug.

**Waiting for the navigation server is a two-step handshake, and both steps are required.** `map_get_iteration_id() > 0` is the only legal query before the first synchronization — every other call, `map_get_closest_point` included, raises an engine error in that state. But it is **necessary, not sufficient**: the map can iterate before our region is in that iteration, and then the snap answers about an empty map and returns the *same* point for every input. Three separate bugs came from getting this wrong (a magic frame count, then an illegal probe, then a sufficient-looking one). Poll the iteration id first, then confirm a known mesh point snaps back onto itself.

Everything cheaper than the merge was measured and rejected — do not re-litigate these:

| Rejected | Measured |
|---|---|
| `path_search_max_distance` / `path_search_max_polygons` | 1–5%; the aggressive values that gained more broke ~50% of routes |
| `path_postprocessing = edgecentered` | 5% **slower** than `corridorfunnel` |
| `simplify_path` | 3% |
| `path_max_distance` | no effect at the default 100 px. The mechanism is real but never triggers: at the 10 px minimum every enemy repaths every frame and the game collapses |
| staggering the per-frame read | 8% of the frame at absolute best, and degrades path following |
| raising `path_recalc_interval` | **not a performance lever.** 1.0 s is already the responsiveness limit in play, and may need to go *lower* |

**New stage checklist (navigation):** instance `entities/stage_parts/navmesh_merger.tscn` anywhere in the stage — position in the tree does not matter, and neither does its position in the world. Leave `mode = MERGED`. Nothing else to wire.

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
