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

### Player

- **`scripts/player_base.gd`** — `CharacterBody2D` base class: FSM (idle/walk/attack/dead), movement, `take_damage()`, flash effect, audio.
- **`entities/players/major_heat.tscn`** — concrete player scene; extends `player_base.gd` via `scripts/player01.gd`.
- Player has two child controller nodes: **`AttackController`** and **`PowerUpController`**.
- Health state lives entirely in `GameStateGlobal` (registered via `register_player()`); the player node just calls `take_damage()` there.
- Armor from `PowerUpStatsGlobal.get_armor_damage_reduction()` is applied before forwarding damage.

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

**`BasePower`** — `Area2D` base for all projectiles: life-time countdown, per-enemy hit cooldown (`enemies_last_hit`), damage calculation (additive: `damage_upgrade_bonus + (damage_multiplier − 1.0)`), knockback multiplier from globals. Provides `calculate_projectile_spread_angles()`, `find_nearest_enemy_on_screen()`, and `find_random_enemy_on_screen()`.

**Damage bonus is additive** across sources: `damage_upgrade_bonus` (from `AttackUpgradeData`) + global powerup bonus are summed once and applied as `damage × (1 + total_bonus)`.

### Enemy system

- **`scripts/enemy_base.gd`** — `CharacterBody2D` base: FSM (IDLE/WALK/DEAD), NavigationAgent2D pathfinding with RVO avoidance (async via `velocity_computed` signal), knockback with chain-transfer to adjacent enemies, item drops, `receive_hit()` / `die()`.
- **`_guard_against_position_jump()`** in `enemy_base.gd` — called every physics frame after `move_and_slide()`. Compares actual displacement against `velocity × delta × 3.0` (floor: 2 px); if exceeded, clamps the position back. This suppresses anomalous pixel-jumps that `move_and_slide()` produces when resolving collisions near walls or corners, especially under active RVO avoidance. Symptom that motivated it: enemies spawned or teleported near walls would visibly snap a few pixels in a random direction when the player moved toward/away from walls.
- Concrete enemies: `entities/enemies/gator.tscn` and `red_gator.tscn`.
- Enemy scenes must be in group `"Enemy"`. Hurtboxes in group `"EnemyHurtbox"`.
- After spawning or teleporting, always call `enemy.makepath()` to recalculate navigation from the new position.
- **Item drop system**: on `die()`, `EnemyBase` rolls `drop_chance` once, then drops `min/max_drop_amount` items scattered within `drop_spread_radius`. Each dropped unit is picked independently from `drop_table` (`Array[ItemDropData]`) via weighted random in `_choose_drop_item()` — same weight logic as `choose_enemy()`, null-safe. `ItemDropData` (`data/item_drop/item_drop_data.gd`) holds just `item_scene` + `spawn_weight`. Drop tables are configured as **embedded resources** in each enemy scene's Inspector (not `.tres` files), so different enemies can drop the same item with independent weights. New enemies need zero drop code — Inspector only.

### Spawn system (`SpawnManagerGlobal`)

Budget-based, inspired by Vampire Survivors:
- `base_budget_per_second × difficulty_multiplier` accumulates each frame.
- When budget ≥ `minimal_budget`, spawns enemies (weighted random by `spawn_weight`) until budget runs out.
- Positions found via **grid sampling** of 4 rectangular bands around the viewport (N/S/E/W strips), clustered by flood-fill, then filtered to offscreen-only. Validated for NavigationServer2D reachability + wall clearance + enemy spacing.
- **Teleport system**: every `teleport_check_interval` seconds, enemies beyond `max_distance_from_player` are teleported to pre-validated offscreen positions.
- Call `SpawnManagerGlobal.start_spawning()` when the stage starts; `stop_spawning()` on restart.
- **Per-stage spawn resources**: `EnemySpawnData` `.tres` files live in `data/enemy_spawn/stageXX/` (e.g. `stage01/spawn_gator.tres`). Each stage gets its own folder with its own copies — never share spawn `.tres` files across stages, since editing a shared Resource would change the calibration of every stage that references it. Empty slots in the `enemy_definitions` array are safely ignored by `choose_enemy()`.

### XP & Level-up flow

1. Enemy dies → drops XP item(s) chosen from its `drop_table` (see Enemy system). All XP items share `scripts/xp_item.gd` (`class_name XPItem`) and differ only by Inspector calibration (`xp_value`, sprite) — e.g. `xp_item_01.tscn`, `xp_item_02.tscn`. New item scripts are only created when collect logic diverges (e.g. a future healing item).
2. Player picks up item → `XPManagerGlobal.add_xp()`.
3. XP fills → `level_up` signal → `LevelUpManagerGlobal._on_level_up()`.
4. `LevelUpManager` pauses game (`GameStateGlobal.UPGRADE`), generates 3 options from `AttackController` and `PowerUpController` pools.
5. Player selects → `controller.apply_upgrade(id)` → `current_level++` on the relevant resource.
6. `AttackController._check_upgrade_changes()` detects the level change next physics frame and updates the timer.

### PowerUp system

- **`PowerUpController`** (`entities/controllers/power_up_controller.tscn`) — child of player; holds `Array[PowerUpData]`. `apply_upgrade(id)` increments level and recomputes all stats into `PowerUpStatsGlobal.update_stats()`.
- Powerup data lives in `data/power_up_data/`.
- `PowerUpStatsGlobal.stats_changed` triggers `AttackController._on_stats_changed()` to recalculate all attack timers immediately.

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
- **Resource sharing strategy** — pick by how the data varies: data that must be identical everywhere (attack stats, powerups) → shared `.tres` + runtime `duplicate()`; per-stage data with reuse across stages (enemy spawn) → separate `.tres` folders per stage; per-instance data with no reuse (enemy drop tables) → embedded resources created directly in the Inspector. Embedded resources live inside the scene file and are invisible in the FileSystem dock — use the resource's `resource_name` field to label them in Array slots.
- **`attack_id` is the join key** between `AttackData`, `AttackUpgradeData`, and `attack_timers`. Keep IDs consistent across all three.
- **Additive bonuses everywhere**: cooldown, damage, and projectile speed all use `base × (1 + sum_of_bonuses)` — never chain multiplications. For speed, `speed_upgrade_bonus` (per-attack upgrade) and `projectile_speed_multiplier − 1.0` (global powerup) are summed before applying. `power_05_gear` is the one exception: the global speed bonus is dampened by `orbit_speed_effectiveness` (currently `0.4`) before summing, because orbital speed generates hits much more efficiently than linear speed — but the gear's own `orbit_speed_upgrade_bonus` always enters at full value.
- **`is_combat_allowed()` gate**: every system that acts on game state must check this before proceeding.
- **Deferred calls for spawning**: use `call_deferred` or `add_child` then set `global_position` afterward (so `_ready` runs before position is overwritten).
- **Audio buses**: SFX plays on the `"SFX"` bus. Powers that manage looping audio set `handles_own_audio = true` on their `AttackData` to suppress the controller from also playing it.

## Known bugs

*(none currently documented)*

## Calibration reference

### Knockback
- Decay is frame-rate independent: `knockback = knockback.move_toward(Vector2.ZERO, knockback_decay * delta)` — values are **per second**.
- Gator: `knockback_decay = 168.0` | Red Gator: `knockback_decay = 330.0`
- `knockback_retention_after_transfer` default: `0.8` (export var on `EnemyBase`).

### Item drops (current values)
- Gator drop table: `xp_item_01` (weight 100) + `xp_item_02` (weight 10) → ~91% / ~9%.
- Red Gator drop table: `xp_item_02` only.
- XP values: `xp_item_01` = 1 | `xp_item_02` = 3 (set in each item scene's Inspector).

### Attack cooldown constants (`attack_controller.gd`)
- `COOLDOWN_REDUCTION_CAP = 0.99`
- `MIN_ATTACK_INTERVAL = 0.05`

### Enemy avoidance (RVO — `NavigationAgent2D`)
- Avoidance Radius: `14 px` | Time Horizon: `0.5 s` | Max Neighbors: `8` | Neighbor Distance: `80 px`
- `_avoidance_pending` flag in `EnemyBase` prevents stale `velocity_computed` callbacks from overriding knockback.
- **Note**: initial test with `set_velocity` showed no visible difference vs. plain physics collision — needs further investigation before relying on RVO for balancing.

### `power_06_snowflake`
- Uses `TargetTrackerGlobal`: FIFO exclusion list, max 5 recently-targeted enemies. Resets automatically when the batch interval elapses.
- Set `sprite.modulate.a = 0.0` before positioning the node to prevent a one-frame flicker at the origin.

## Working style

- One change at a time, with a test between each.
- Explain the "why" before implementing.
- Provide complete files when making changes — no partial diffs.
- No over-engineering: prefer generalizable solutions over artificial ones.
