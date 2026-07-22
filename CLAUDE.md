# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Survivor Hero** — Vampire Survivors-style game built in **Godot 4.6** (GDScript). Viewport: 480×270, pixel art (no texture filtering). No CLI build or test system; everything runs through the Godot Editor.

## Running the game

Open `project.godot` in Godot 4.6 and press F5 (or the play button). The main scene is `scenes/stage01.tscn`.

There are no automated tests. Manual playtesting is the only validation method.

## Architecture overview

### Autoloads (singletons — always available globally)

| Name | File | Purpose |
|---|---|---|
| `GameStateGlobal` | `autoload/game_state.gd` | Central FSM (COMBAT / UPGRADE / PAUSED / PLAYER_DEAD). Also owns player health. |
| `XPManagerGlobal` | `autoload/xp_manager.gd` | XP accumulation, level-up signal, exponential curve. |
| `LevelUpManagerGlobal` | `autoload/level_up_manager.gd` | Generates upgrade options on level-up, pauses game, delegates to controllers. |
| `SpawnManagerGlobal` | `autoload/spawn_manager.gd` | Budget-based enemy spawn with grid sampling and teleport system. |
| `PowerUpStatsGlobal` | `autoload/power_up_stats.gd` | Flat store for computed player stats (damage, armor, cooldown reduction, etc.). Emits `stats_changed`. |
| `AudioManagerGlobal` | `autoload/audio_manager.gd` | Central SFX playback (2D and positional). |
| `InputManagerGlobal` | `autoload/input_manager.gd` | Input abstraction. |
| `TargetTrackerGlobal` | `autoload/target_tracker_global.gd` | Tracks recently-targeted enemies to prevent repetition (used by homing attacks). |

**Critical gate:** before any gameplay action (spawning, damage, XP), always check `GameStateGlobal.is_combat_allowed()`. It returns `false` during PAUSED, UPGRADE, CUTSCENE, DIALOGUE, and PLAYER_DEAD. `PLAYER_DEAD` is a terminal state — only `restart_game()` can exit it.

### Entity anatomy — feet origin + BodyCenter (MANDATORY convention)

Player and every enemy scene follow this layout (in preparation for Y-sort):

- **Scene origin (root position) = the FEET.** Sprites/colliders are offset upward so `global_position` marks the ground point. Rendering/sorting and gameplay distances live in this frame.
- **`BodyCenter` (Node2D child) = center of the body/collider.** Player: `(0,-11)` | Gator: `(0,-11)` | Red Gator: `(0,-16)`. Navigation and body-anchored systems live in this frame.
- **Never mix the two frames.** Steering a body-frame point toward feet-frame path points (or vice versa) injects a constant vertical bias that accumulates along paths — enemies visibly "arc" below straight lines. This class of bug cannot be fixed by calibration; fix it by putting the whole pipeline in one frame.

**Enemy navigation is anchored on BodyCenter via reparenting**: each enemy's `NavigationAgent2D` is a child of `BodyCenter`, not of the root. `NavigationAgent2D` navigates **its parent node's position** — so path start, waypoint advancement and `is_navigation_finished()` all operate at the collider center. `enemy_base.gd` caches the parent as `_nav_anchor` and computes direction as `next_path_position − _nav_anchor.global_position` (never `to_local()`, which is feet-frame). `makepath()` targets the **player's BodyCenter** (body chases body). Nice property: when navigation finishes, `get_next_path_position()` returns the agent (= BodyCenter) position, so the direction degenerates to `Vector2.ZERO` and the enemy gracefully stands still.

**Gameplay distances are BodyCenter-to-BodyCenter**: `distance_to_player` (`stop_distance` / `attack_distance`) uses the enemy's BodyCenter (`_nav_anchor.global_position`) to the player's BodyCenter (`player_body_center`, cached in `_setup_base`; fallback to each origin). This is the **same frame the chase uses** (`makepath` targets the player's BodyCenter, and the enemy navigates its own BodyCenter) — so the enemy stops and switches to its attack animation exactly when the two **bodies** are close, matching what it is chasing. The game simulates 2.5D depth but is essentially 2D: consistency with the chased point matters more than the height-symmetry an origin-to-origin measure would give. (Historically this was feet-to-feet at the scene origins, which drifted from the chased BodyCenter and made enemies stop/attack based on the wrong point.)

**Body-anchored systems all read the BodyCenter** (via `get_node_or_null("BodyCenter")`, falling back to the origin): enemy pathfinding target (`makepath`), item drops (`_spawn_single_drop_item`, base = enemy's own BodyCenter via `_nav_anchor`), **enemy knockback direction** (see *Knockback*), **power targeting** (every attack that chases an enemy — see *Attack system*), and player-attached attacks. **On enemies the canonical accessor is `EnemyBase.get_body_center_position()`** (fallback chain `BodyCenter` → `_nav_anchor` → origin) — never read `enemy.global_position` when you mean "where the body is": the scene origin is the FEET, and using it injects a systematic downward bias. `AttackController._spawn_single_projectile()` places **any** `attach_to_player` attack at the player's BodyCenter local position — automatic for future attacks with that flag, no per-attack code needed (current: electricity, gear). **Exception — attacks that rewrite their own `position` every physics frame** (orbitals like `power_05_gear`): the spawn placement is overwritten on the first frame, so their movement formula must add the body offset itself — gear captures `_orbit_center_offset` from the player's BodyCenter in `_ready` and adds it to the orbit position. Any future self-positioning attached attack needs the same anchoring.

**Marker nodes degrade gracefully, never crash**: position markers (`BodyCenter`, `AttackPositionRight/Left`) are looked up with `get_node_or_null` and every consumer has a fallback chain ending in a property that always exists — e.g. projectile spawn: `AttackPositionRight/Left` → player `BodyCenter` (`AttackController._get_player_body_position()`) → `player.global_position`. A player scene missing markers still works (attacks spawn slightly off) and `AttackController.setup()` emits one `push_warning` so the omission is visible in the console. Follow this pattern for any new marker node.

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
| `body_center_offset` drift | `SpawnManager._validate_body_center_offset()` | spawn validating wall clearance at the wrong point (this really happened — see Spawn system) |
| `Hurtbox` / `PlayerHurtbox` group | `PlayerBase._validate_scene_setup()` | **player immune to contact damage** |

**New enemy checklist**: origin at feet · `BodyCenter` node at collider center · `NavigationAgent2D` as child of `BodyCenter` · subclass `@onready` path `$BodyCenter/NavigationAgent2D` · fill the `Spawn Fit` group in its `EnemySpawnData` (see Spawn system) · root configured for Y-sort (`z_index = 2`, `y_sort_enabled = true` — see Y-sort).

### Y-sort (2.5D depth illusion)

Entities and scenery tiles occlude each other by Y position (feet origin = the sort line). Three requirements, ALL mandatory:

1. **Same `z_index`** — Y-sort only breaks ties within one z level; a different z overrides it. The world standard is **`z_index = 2`** (`z_as_relative = true`): player, enemies, XP items set it on the scene root; TileMap layers get it **per-tile in the TileSet** (setting it on the TileMapLayer node in the Inspector does NOT work for this — leave the layer at z 0 and paint z 2 inside the TileSet tiles).
2. **`y_sort_enabled = true`** on the entity root and on participating TileMap layers.
3. **Being a child of the Y-sort container** — Y-sort only sorts CHILDREN of a `y_sort_enabled` parent. Each stage instances **`entities/stages/y_sort_container.tscn`** (a configured, permanently-empty Node2D `YSortContainer`: z 2, relative, y-sort on). **The membership criterion is functional and single: anything that needs variable occlusion along the Y axis (Godot's Y-sort) goes inside the container; anything that doesn't stays outside.**
   - **Player and enemies always belong to the container** (they always need variable occlusion). The player currently sits in the stage tree only because there is no player spawn/selection system yet — that is circumstantial, not the definitive method. Enemies join at runtime (see next paragraph).
   - **TileMap layers are case-by-case**, decided per layer by whether they need to trade occlusion with entities. **No layer trait decides this**: having collision does not determine participation (`TileMapDecoration` itself has colliders and is inside), having navigation does not either, and tiles with neither collision nor navigation don't either. Only the functional criterion decides.
   - **Expect TileMaps both inside and outside the container within the same stage.** Typically a floor layer does not need variable occlusion and stays outside — that is the only "normal" case; no other TileMap name should be treated as fixedly inside or outside.

   Content placed in the editor inside the instance belongs to the stage file; never add children to the base scene `y_sort_container.tscn` (they would be shared across every stage).

   **Why the container matters for spawned enemies:** the effective z of an entity is `parent_z + own_z`. Player and enemies are all `z_index = 2` (relative), so inside the container they land at `2 + 2 = 4` and Y-sort tie-breaks them by Y. If enemies were parented to the scene root instead (z 0) they would land at effective z `0 + 2 = 2` — **below** the player's 4 — and the player would render permanently in front of every enemy.

   **The container is resolved automatically by group — no per-stage wiring.** The base scene `y_sort_container.tscn` carries the group **`YSortContainer`**, so every instance in every stage is already in it. `SpawnManagerConfig.initialize_spawn_manager()` resolves in cascade: the `enemy_container` export (explicit override) → `get_first_node_in_group("YSortContainer")` → nothing (one `push_warning`). **Leave the export empty in the normal case**; fill it only to disambiguate a stage with more than one container. This replaced a manual drag-and-drop step whose omission broke Y-sort silently (deleting a container invalidated the NodePath and a fresh one was never auto-reassigned).

**Spawned entities join the container via explicit parenting**: the container resolved by `SpawnManagerConfig` (see above) is transferred to `SpawnManagerGlobal` — `spawn_enemy()` adds enemies there (fallback: scene root, no Y-sort). Item drops inherit it for free (`_spawn_single_drop_item` adds to the enemy's `get_parent()`), and projectiles too (`add_sibling(player)` = child of the player's parent). Tile occlusion switch points are calibrated via each tile's **Y Sort Origin** in the TileSet relative to the entity feet origin.

### Player

- **`scripts/player_base.gd`** — `CharacterBody2D` base class: FSM (idle/walk/attack/dead), movement, `take_damage()`, flash effect, audio.
- **`entities/players/major_heat.tscn`** — concrete player scene; extends `player_base.gd` via `scripts/player01.gd`.
- Player has two child controller nodes: **`AttackController`** and **`PowerUpController`**.
- Health state lives entirely in `GameStateGlobal` (registered via `register_player()`); the player node just calls `take_damage()` there.
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

**Attack scenes** live in `entities/powers/`: `power_01_fire`, `power_02_ring`, `power_03_electricity`, `power_04_bo`, `power_05_gear`, `power_06_snowflake`. All extend **`BasePower`** (`scripts/base_power.gd`).

**`BasePower`** — `Area2D` base for all projectiles: life-time countdown, per-enemy hit cooldown (`enemies_last_hit`), damage calculation (additive: `damage_upgrade_bonus + (damage_multiplier − 1.0)`), knockback multiplier from globals. Provides `calculate_projectile_spread_angles()`, `find_nearest_enemy_on_screen()`, `find_random_enemy_on_screen()`, and **`_enemy_body_position(enemy)`**.

**Targeting reads the enemy's BODY, never its origin.** `_enemy_body_position()` resolves to `EnemyBase.get_body_center_position()` (with a defensive fallback) and is the **only** way a power should read an enemy's position — both to pick a target and to aim at it. Reading `enemy.global_position` targets the **feet**, ~10 px below the body on the gator and ~15 px on the red gator, which visibly makes attacks converge on the ground. It is used by the shared selection helpers (on-screen test + distance ranking, so an enemy whose body is visible but whose feet are off-screen still counts) and by the three chasing attacks: `power_02_ring` (arc destination), `power_04_bo` (straight-shot direction), `power_06_snowflake` (where the flake spawns). Any future enemy-seeking attack must use it too.

**Damage bonus is additive** across sources: `damage_upgrade_bonus` (from `AttackUpgradeData`) + global powerup bonus are summed once and applied as `damage × (1 + total_bonus)`.

### Enemy system

- **`scripts/enemy_base.gd`** — `CharacterBody2D` base: FSM (IDLE/WALK/DEAD), NavigationAgent2D pathfinding + **context-steering** inter-enemy avoidance (see *Enemy inter-enemy avoidance*), knockback with chain-transfer to adjacent enemies, item drops, `receive_hit()` / `die()`.
- **`_guard_against_position_jump()`** in `enemy_base.gd` — called every physics frame after `move_and_slide()`. Compares actual displacement against `velocity × delta × 3.0` (floor: 2 px); if exceeded, clamps the position back. This suppresses anomalous pixel-jumps that `move_and_slide()` produces when resolving collisions near walls or corners. Symptom that motivated it: enemies spawned or teleported near walls would visibly snap a few pixels in a random direction when the player moved toward/away from walls.
- Concrete enemies: `entities/enemies/gator.tscn` and `red_gator.tscn`.
- Enemies belong to group `"Enemy"` (added by `enemy_base.gd`, not by the scene) and their `Hurtbox` to `"EnemyHurtbox"` (marked per scene) — see *Node groups*.
- After spawning or teleporting, always call `enemy.makepath()` to recalculate navigation from the new position.
- **Item drop system**: on `die()`, `EnemyBase` rolls `drop_chance` once, then drops `min/max_drop_amount` items scattered within `drop_spread_radius`. Each dropped unit is picked independently from `drop_table` (`Array[ItemDropData]`) via weighted random in `_choose_drop_item()` — same weight logic as `choose_enemy()`, null-safe. `ItemDropData` (`data/item_drop/item_drop_data.gd`) holds just `item_scene` + `spawn_weight`. Drop tables are configured as **embedded resources** in each enemy scene's Inspector (not `.tres` files), so different enemies can drop the same item with independent weights. New enemies need zero drop code — Inspector only.

### Spawn system (`SpawnManagerGlobal`)

Budget-based, inspired by Vampire Survivors:
- `base_budget_per_second × difficulty_multiplier` accumulates each frame.
- When budget ≥ `minimal_budget`, spawns enemies (weighted random by `spawn_weight`) until budget runs out.
- Positions found via **grid sampling** of 4 rectangular bands around the viewport (N/S/E/W strips), clustered by flood-fill, then filtered to offscreen-only.
- **Snap-to-navmesh**: grid points are not required to land on the navmesh — `get_snapped_navigable_point()` snaps each point to the closest navmesh position within `nav_snap_radius` (export, default 32 ≈ half the 64px grid spacing). This lets the coarse grid "see" thin corridor strips at zero extra cost, and guarantees every candidate lies ON the mesh (never spawn off-mesh). **Frame nuance:** the snap is done in the **feet frame** (the grid point is a feet position), while the `NavigationAgent2D` actually navigates the **BodyCenter** — so the feet land on the mesh, not necessarily the body. It degrades gracefully (the agent resolves to the nearest mesh point and `makepath()` runs right after spawn), but it is the last residual frame mismatch in this pipeline and a candidate for future refinement.
- **Per-enemy spawn fit**: wall clearance is validated **at the body center** (`pos + body_center_offset`), answering "does this enemy's collider fit here?" — and uses the chosen enemy's own values from `EnemySpawnData`'s `Spawn Fit` group (`spawn_clearance_radius`, `body_center_offset`). Small enemies spawn in corridors that large ones can't. Clearance slightly below the collider radius is a legal calibration: it allows ~1-3px wall overlap that physics gently resolves on the first frame (used to raise density in tight corridors); going much lower risks depenetration ejecting the enemy through thin walls.
  - **`body_center_offset` shifts nothing — it only validates.** The enemy is placed with `enemy.global_position = spawn_pos`, i.e. its **feet** land exactly on the chosen point (correct: grid points are floor/navmesh positions). The offset merely tells the validator *where the collider will sit* so it can check walls there.
  - ⚠️ **It is a manual duplicate of the enemy scene's `BodyCenter` node position and must be kept in sync.** They already drifted once (Red Gator's resource was left at the default while its `BodyCenter` was at `-15`, so wall fit was validated at the wrong point). When you move a `BodyCenter`, update the matching `EnemySpawnData` — `SpawnManager._validate_body_center_offset()` now compares the two on first spawn of each enemy scene and warns if they diverge.
- **No silent fallback**: if no point in the chosen cluster passes full validation, `find_spawn_position()` returns `Vector2.ZERO` and the spawn is skipped this frame (budget is retained). Never spawn on a rejected point — that was the historical source of enemies inside walls.
- **Teleport system**: every `teleport_check_interval` seconds, enemies beyond `max_distance_from_player` are teleported. Two-phase validation: the cache is pre-filtered with the **smallest** clearance among defined enemies (so tight-corridor points exist in it), then `_take_position_fitting_enemy()` re-validates each candidate with the specific enemy's own clearance at assignment time.
- Call `SpawnManagerGlobal.start_spawning()` when the stage starts; `stop_spawning()` on restart.
- **Per-stage spawn calibration**: `enemy_definitions` is configured as **embedded resources** on the `SpawnManagerConfig` instance inside each stage scene (e.g. in `stage01.tscn`'s scene tree) — never on the base `spawn_manager_config.tscn`, whose default must stay empty (setting it there would leak into every stage). Embedded entries keep each stage's calibration independent. Empty slots in the `enemy_definitions` array are safely ignored by `choose_enemy()`.

### XP & Level-up flow

1. Enemy dies → drops XP item(s) chosen from its `drop_table` (see Enemy system). All XP items share `scripts/xp_item.gd` (`class_name XPItem`) and differ only by Inspector calibration (`xp_value`, sprite) — e.g. `xp_item_01.tscn`, `xp_item_02.tscn`. New item scripts are only created when collect logic diverges (e.g. a future healing item).
2. Player picks up item → `XPManagerGlobal.add_xp()`.
3. XP fills → `level_up` signal → `LevelUpManagerGlobal._on_level_up()`.
4. `LevelUpManager` pauses game (`GameStateGlobal.UPGRADE`), generates 3 options from `AttackController` and `PowerUpController` pools.
5. Player selects → `controller.apply_upgrade(id)` → `current_level++` on the relevant resource.
6. `AttackController._check_upgrade_changes()` detects the level change next physics frame and updates the timer.

**Implicit level-up queue** — `XPManager._check_level_up()` grants at most **1 level per call** (`if`, not `while`) and is blocked by `is_waiting_for_upgrade` while a menu is pending. Surplus XP stays in `current_xp` and acts as the queue: when the player confirms a choice, `LevelUpManager.apply_upgrade()` calls `XPManagerGlobal.upgrade_selected()`, which re-checks the surplus — if it covers another level, a new menu opens **synchronously** and the game stays paused in UPGRADE (no COMBAT flicker between chained menus). Two ordering constraints keep the synchronous chain working: `apply_upgrade()` re-checks *before* unpausing (and returns without unpausing if a new menu opened), and `level_up_ui._on_option_pressed()` hides the menu *before* emitting `option_selected` (hiding after would erase the newly opened menu).

**XPBar is pause-immune** — `process_mode = PROCESS_MODE_ALWAYS` so level-up animations (label pulse, bar fill) complete behind the paused upgrade menu. Values can't change during pause (`add_xp` is gated by `is_combat_allowed()`). Gotcha: `get_tree().create_timer()` inside XPBar sequences must pass `process_always = true` — SceneTree timers ignore the node's `process_mode` and would freeze the animation chain mid-sequence.

**Unlock notifications reach the LoadoutBar via two asymmetric routes** (pause does not block signals — only `_process`/`_physics_process`/input): `PowerUpController` emits `powerup_unlocked` synchronously inside `apply_upgrade()`, but `AttackController` emits `attack_unlocked` from its `_physics_process` polling, which is paused during the upgrade menu — so it only fires after unpause, too late for chained menus. `LoadoutBar` therefore listens to **both** `LevelUpManagerGlobal.upgrade_applied` (synchronous, updates during pause; only acts on `next_level == 1`) and the controller signals (covers debug keys and future unlock sources), deduplicating by id (`filled_attack_ids` / `filled_powerup_ids`) since menu unlocks arrive through both routes. Don't "fix" the asymmetry by making `AttackController` process-always or by calling `_check_upgrade_changes()` synchronously — attack timers would tick during pause, and `start_immediately` shots would be swallowed by the `is_combat_allowed()` guard.

### PowerUp system

- **`PowerUpController`** (`entities/controllers/power_up_controller.tscn`) — child of player; holds `Array[PowerUpData]`. `apply_upgrade(id)` increments level and recomputes all stats into `PowerUpStatsGlobal.update_stats()`.
- Powerup data lives in `data/power_up_data/`.
- `PowerUpStatsGlobal.stats_changed` triggers `AttackController._on_stats_changed()` to recalculate all attack timers immediately.

## Node groups

Project-wide registry. **Each group has exactly one declaration site** — never declare the same group both in a script and in a scene's Groups tab. (That duplication is how the dead `"Enemies"` look-alike of `"Enemy"` was born and survived for months.)

| Group | Declared in | Consumed by |
|---|---|---|
| `Player` | **scene** — `major_heat.tscn` root (Groups tab) | camera, level-up, spawn manager, enemies, loadout bar, powers 04/05/06 |
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
| 9 | enemy_hurtbox |

## Key conventions

- **Singleton naming**: `NomeFuncionalGlobal` (e.g. `TargetTrackerGlobal`, `PowerUpStatsGlobal`).
- **Versioning**: semântico `v1.x.x` nos comentários de código.
- **`@export` discipline**: only fields that must appear in the Inspector. Non-`@export` fields are **not copied by `duplicate(true)`** — fields set at runtime that need to survive a `duplicate()` call must be `@export`.
- **Resource duplication**: `AttackUpgradeData` resources are duplicated in `AttackController._ready()` so editor assets are never mutated at runtime. Always duplicate before modifying shared resources.
- **Resource sharing strategy** — pick by how the data varies: data that must be identical everywhere (attack stats, powerups) → shared `.tres` + runtime `duplicate()`; data owned by one scene/instance (enemy drop tables, per-stage spawn definitions) → embedded resources created directly in the Inspector. Embedded resources live inside the scene file and are invisible in the FileSystem dock — use the resource's `resource_name` field to label them in Array slots. When a scene is instanced (e.g. `SpawnManagerConfig` inside a stage), configure embedded resources on the **instance**, not the base scene, or the data leaks into every instance.
- **`attack_id` is the join key** between `AttackData`, `AttackUpgradeData`, and `attack_timers`. Keep IDs consistent across all three.
- **Additive bonuses everywhere**: cooldown, damage, and projectile speed all use `base × (1 + sum_of_bonuses)` — never chain multiplications. For speed, `speed_upgrade_bonus` (per-attack upgrade) and `projectile_speed_multiplier − 1.0` (global powerup) are summed before applying. `power_05_gear` is the one exception: the global speed bonus is dampened by `orbit_speed_effectiveness` (currently `0.4`) before summing, because orbital speed generates hits much more efficiently than linear speed — but the gear's own `orbit_speed_upgrade_bonus` always enters at full value.
- **Asset references in code use `uid://`, never `res://` paths**: uids survive file moves/reorganization (which happens often here); string paths silently break — `load()` and `change_scene_to_file()` are **not** tracked by the editor and keep pointing at the old path. Bind the uid to a descriptively-named `const`/`var` so the reference is self-documenting (e.g. `const LEVEL_UP_UI_SCENE = preload("uid://...")`, like `gator.gd`'s `IMPACT_01`); **when there is no such name** (e.g. an inline `preload` inside a call), add a short comment naming the target file (e.g. `set_script(preload("uid://..."))  # uid = scripts/debug_drawer.gd`). Use `preload` (load-time) for assets always used; `load(uid)` for conditional/rare ones (e.g. the debug overlay). **Never hand-write uids** — let Godot generate them; a typed uid with `_` or characters outside `0-9a-z` is invalid and unresolvable (Godot can't register it, so `Copy UID` and `load` both fail).
- **`super._ready()` in subclasses**: GDScript does **not** run the parent's `_ready()` automatically — defining `_ready()` in a subclass fully overrides it. So: subclass **has** its own `_ready()` → it must call **`super._ready()` as the first line**; subclass has **no** `_ready()` → nothing to do, the parent's runs. This already bit the project: `power_02/04/06` each duplicated `add_to_group("Power")` because they overrode `_ready()` without `super`. The `Power` group now has a single source in `base_power.gd` and **depends on those `super._ready()` calls** (`power_05_gear.gd` was the original correct example).
- **`is_combat_allowed()` gate**: every system that acts on game state must check this before proceeding.
- **Deferred calls for spawning**: use `call_deferred` or `add_child` then set `global_position` afterward (so `_ready` runs before position is overwritten).
- **Audio buses**: SFX plays on the `"SFX"` bus. Powers that manage looping audio set `handles_own_audio = true` on their `AttackData` to suppress the controller from also playing it.

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
Inter-enemy avoidance is **context steering** (Reynolds/Fray family), not RVO. The `NavigationAgent2D` is used **only for pathfinding** (the wall-aware `base_dir`); its RVO avoidance is **off** (`avoidance_enabled` defaults to false on the scenes, and `steering_enabled` bypasses it in `base_move`). The leftover avoidance params on each `NavigationAgent2D` (`radius`, `time_horizon_agents`, `max_neighbors`, `neighbor_distance`, `avoidance_priority`) are **vestigial**. **`steering_enabled` defaults to `true`** in `EnemyBase` — steering is the game standard, so enemy scenes no longer set it; since Godot omits properties equal to the script default, its **absence from a `.tscn` means ON, not off**.

- **Why not RVO:** ORCA slowed enemies to a near-zero creep when circling a stationary enemy to reach the player — it picks the collision-free velocity closest to the desired one, and heading straight into a neighbor that is a slow forward crawl, not a full-speed lateral detour. No RVO param fixed it (`time_horizon`, `avoidance_priority`, `radius`, `max_speed`). Root cause: RVO only **deflects** the desired velocity, it can't **re-route**. Context steering preserves full speed and steers tangentially around blockers.
- **Dormant RVO — not removed yet:** the RVO code path is **still present and functional** in `base_move` / `_on_velocity_computed` (the `velocity_computed` signal is still connected). Setting `steering_enabled = false` **and** `avoidance_enabled = true` on the agent brings RVO back exactly as before. It is kept dormant for now and is **slated for removal** — do not build on it.
- **How it works** (`_steer_direction`): samples `steer_slice_count` slices around the enemy. Each slice gets an **interest** (alignment with `base_dir`, the path toward the player) and a **danger** (0/1). Enemy danger = angular occupancy: a neighbor at distance `d` blocks the arc of half-width `asin(steer_enemy_clearance / d)`, so gaps wider than a body stay open and the enemy threads them. Wall danger = one raycast per slice against layer 1 up to `steer_wall_clearance` ("Solution B"). It picks the clearest slice with the highest interest and moves at **full speed**; open field (no neighbor) returns `base_dir` directly (smooth, straight).
- **Wall perception is gated by enemy proximity (non-obvious):** the whole deviation logic — **including the wall raycasts** — only runs when a neighbor is within `steer_detect_radius`. A **lone** enemy short-circuits to `base_dir` and the `NavigationAgent2D` path alone handles walls. So `steer_wall_clearance` is a **tie-breaker while dodging a neighbor** (it excludes wall-pointing slices when an enemy is boxed in by enemy + wall), **not** a general wall-distance keeper. (Making it always-on would need running the wall pass without a neighbor + a gradient repulsion — future work.)
- **"Wait" state** (`steer_block_min_interest`): if even the best clear slice does not point reasonably toward the player (surrounded, no access), `_steer_direction` returns `Vector2.ZERO` and the enemy **holds position** — forming a natural queue / outer ring until a slot opens. Held `velocity = 0` → IDLE via the existing state machine; the attack pose is still decided **solely by the 50 px distance** (untouched).
- **Colliders stay ON** (layer 3): they enforce final spacing and are what make knockback **chain-transfer** work (`handle_knockback_transfer` reads `get_slide_collision` = physical contact). Knockback itself **bypasses steering** (its own early branch in `base_move`).
- **Cost / scale** (massive-horde game): `_steer_direction` is amortized by three things — **staggering** (`steer_update_interval`: recompute the direction once every N frames, staggered per instance, move every frame from cache), a **spatial grid** (`GRID_CELL_SIZE`, rebuilt once per physics frame and shared; each enemy queries only nearby cells → O(N) instead of O(N²)), and a **wall-danger cache** keyed by position (walls are static → re-raycast only after the enemy moves more than a few px).
- **Calibration** (per enemy, Inspector — `steer_*`): `steer_detect_radius` = perception trigger (a neighbor within it turns the deviation logic on). `steer_enemy_clearance` (enemy spacing) and `steer_wall_clearance` (wall distance) are **independent**. Keep `steer_enemy_clearance ≤ the physical contact distance` (sum of the two colliders) so steering complements physics and enemies **queue** rather than fight for extra room in corridors. Higher `steer_block_min_interest` = "wait"/queue sooner (helps corridors) at the cost of enemies giving up access more easily.

### `power_06_snowflake`
- Uses `TargetTrackerGlobal`: FIFO exclusion list, max 5 recently-targeted enemies. Resets automatically when the batch interval elapses.
- Set `sprite.modulate.a = 0.0` before positioning the node to prevent a one-frame flicker at the origin.

### Debug overlay (Grid Sampling) — only faithful at camera zoom = 1
- The spawn debug (`debug_draw_overlay`, gated by `SpawnManagerConfig.debug_draw_enabled`) draws on a `CanvasLayer` and projects world→screen by hand in `debug_drawer.gd`: `point - camera_position + viewport_size/2`, with **no zoom factor**. `CanvasLayer` also ignores the `Camera2D` transform.
- **Consequence:** it is only correct at camera **zoom = 1**. Under zoom-out (e.g. `0.5`) the scenery scales but the debug points do not, so they "parallax" (move faster than the world) and the overlay detaches — it does **not** work as a magnifying lens.
- **The spawn logic itself is zoom-invariant** (pure world space); this is a *debug-rendering* limitation, not a spawn bug. Don't misread the parallax as the spawn system malfunctioning.
- At zoom 1 the points only flash briefly near the screen edge (offscreen ones are culled), so the tool is of low practical use today. **Future fix:** draw in world space (a `Node2D` under the camera-affected world) instead of a `CanvasLayer`, so it inherits the camera transform and works at any zoom.

## Working style

- One change at a time, with a test between each.
- Explain the "why" before implementing.
- Provide complete files when making changes — no partial diffs.
- No over-engineering: prefer generalizable solutions over artificial ones.
