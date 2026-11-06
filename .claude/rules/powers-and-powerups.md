---
paths:
  - "scripts/attack_controller.gd"
  - "scripts/base_power.gd"
  - "scripts/power_*.gd"
  - "autoload/power_up_stats.gd"
  - "autoload/target_tracker_global.gd"
  - "data/attack_data/**"
  - "data/attack_upgrade_data/**"
  - "data/hit_data/**"
  - "data/power_up_data/**"
  - "entities/powers/**"
  - "entities/controllers/**"
---

### Shared progression — powers and powerups

Both grow the same way: a `.tres` with per-level arrays, read by a controller that is a child of the player. The differences are recorded here on purpose; they are not to be read as design decisions unless the text says so.

| | Powers | Powerups |
|---|---|---|
| Per-level resource | `AttackUpgradeData` | `PowerUpData` |
| Base stats | `AttackData` (+ `HitData`) | the player's own values and `PowerUpStatsGlobal` |
| Join key | `attack_id`, shared by `AttackData`, `AttackUpgradeData` and `attack_timers`; keep it consistent across the three | `powerup_id`, inside one resource |
| Controller | `AttackController` | `PowerUpController` |
| Sum helper | `_sum_int` / `_sum_float` | `_get_value` |
| Bonus getters return | `int` or `float` | `Dictionary` (`flat`, `percent`) |
| Starting level | forced by code: `primary_attack_id` at 1, every other attack at 0, whatever the `.tres` says | the `current_level` stored in the `.tres` |
| A level change reaches the game | by polling in `_physics_process`, so never during a pause | at once, inside `apply_upgrade()` |

The primary attack comes from `primary_attack_id` on the `AttackController` of each player scene, so each character can start with a different attack. The level-change asymmetry has consequences for the LoadoutBar: see *XP & Level-up flow*.

**Per-level arrays are INCREMENTS, summed.** Both resources sum `arr[0..current_level-1]`, so `[20, 20, 20]` means +20 per level and 60 at level 3, not "the value at level 3".

**The RESOURCE owns the level ceiling — controllers ask, never check-and-write.** `AttackController.apply_upgrade()` calls `upgrade.level_up()`, exactly as `PowerUpController.apply_upgrade()` calls `powerup.level_up()`; the `max_level` test lives once, inside the resource. It used to be duplicated: `AttackUpgradeData.level_up()` existed with the rule inside it, and the controller re-implemented the same test and wrote `current_level += 1` itself — so editing the rule in the obvious place (the resource) would have changed powerups and silently left attacks alone. Same trap as the old duplicated `body_center_offset`, with a *rule* instead of a value. **Setting a level to zero (`remove_powerup()`) is still a direct write** — that is a reset, not an increment.
  - **Hitting max level returns `false` silently — it is not a warning.** It used to `push_warning`, which lit the editor's error panel every time a player simply maxed an attack. A full attack is normal gameplay; the caller decides whether to say anything (the debug tool prints). The *other* `push_warning` in that function — `Upgrade not found for attack_id` — stays, because an attack with no configured upgrade **is** a misconfiguration.

**Adding a level means editing TWO places, and forgetting either fails silently.** `max_level` is its own `@export` (default `5`), **not** derived from the per-level arrays, while the sum helpers accumulate over `min(current_level, arr.size())`. So: raise `max_level` and forget to extend an array → the new level is reachable but grants that array's bonus at the previous level's value, no error; extend the arrays and forget `max_level` → the new entries are unreachable dead data, no error. Both edits happen in the same `.tres` Inspector — do them together. (The arrays may legitimately have *different* lengths from each other: a shorter one simply stops contributing at its last entry, which is how "this attack gains projectiles only up to level 3" is expressed.)

**Both controllers duplicate their resources in `_ready()`,** so editor assets are never mutated at runtime. Always duplicate before modifying shared resources.

**Additive bonuses everywhere.** Cooldown, damage and projectile speed all use `base × (1 + sum_of_bonuses)` — never chain multiplications.
- **Damage:** `damage_upgrade_bonus` (from `AttackUpgradeData`) + the global powerup bonus (`damage_multiplier − 1.0`) are summed once in `BasePower`.
- **Speed:** `speed_upgrade_bonus` (per-attack upgrade) + `projectile_speed_multiplier − 1.0` (global powerup) are summed in each power script.
- **Spinning attacks dampen the global speed bonus with `orbit_speed_effectiveness`** before summing, because orbital speed generates hits much more efficiently than linear speed. The field lives on `AttackData`, so a future spinning attack can reuse it; `power_05_gear` is an example, applying it in its own `set_attack_data()`. The attack's own upgrade bonus (`orbit_speed_upgrade_bonus`) always enters at full value.

**Adding a new stat crosses several files, and forgetting a step normally fails silently:**
- **Power stat:** the base field in `AttackData`, when it needs one → array and getter in `AttackUpgradeData` → its copy in `_duplicate_and_initialize_upgrades()` and its line in `create_attack_data_with_upgrades()` (without that line the upgrade has no effect) → the power script reads it.
- **Powerup stat:** array and getter in `PowerUpData` → its copy in `_duplicate_powerup_resources()`, a total and an entry in `stats` in `_recalculate_all_stats()` → the variable, `update_stats()` and `reset()` in `PowerUpStatsGlobal` → the system that uses it.

### Powers

Three-layer design:

1. **`AttackData`** (`data/attack_data/attack_data.gd`) — `Resource` with base stats for one attack: scene, timing (`interval`), damage, speed, projectile count, etc. One `.tres` per attack in `data/attack_data/`.
2. **`AttackUpgradeData`** (`data/attack_upgrade_data/attack_upgrade_data.gd`) — `Resource` with per-level arrays (e.g. `cooldown_reduction_per_level`). One `.tres` per attack in `data/attack_upgrade_data/`.
3. **`AttackController`** (`scripts/attack_controller.gd`) — Node child of player. Owns a `Timer` per attack. Detects level changes via `_physics_process → _check_upgrade_changes()` polling.

**Cooldown formula** (additive, not multiplicative):
```
wait_time = max(base_interval × (1 − min(attack_cd_reduction + global_cd_reduction, COOLDOWN_REDUCTION_CAP)), MIN_ATTACK_INTERVAL)
```
Both constants live in `attack_controller.gd`. Recalculated whenever `PowerUpStatsGlobal.stats_changed` fires.

**What the controller expects of a power.** Powers can differ deeply from one another, so this is the contract with `AttackController`, not a recipe. Normally a power:
- lives in `entities/powers/` and extends **`BasePower`** (`scripts/base_power.gd`);
- uses `z_index = 60` on its root (see *Draw layers*);
- receives its data through `set_attack_data()`;
- has `set_power_direction()` only if it needs the side: having this method also places it at `AttackPositionRight/Left` on spawn;
- has `set_projectile_index()` only if it needs its position within the volley;
- calls `super._physics_process(delta)` if it overrides `_physics_process()`.

**`attack_scale` is applied through `node.scale`**, never by resizing shapes: `BasePower._apply_attack_scale()` scales the **direct children** of type `CollisionShape2D` and `AnimatedSprite2D` — any shape type works, and it matches the power standard (a power normally animates with an `AnimatedSprite2D` and has a collider). Not scaled: `Sprite2D`, `Polygon2D` or deeper nodes. A power may handle scale itself; for example, `power_04_bo` overrides it with its dynamic grow/shrink in flight, and `power_06_snowflake` has no `CollisionShape2D` in its scene (it creates one by code) and scales it and its sprite by hand. A future power with a still image: use an `AnimatedSprite2D` with one frame (zero code), or add the `Sprite2D` case to `_apply_attack_scale()`.

**A volley that shares spawn point, direction and target needs `projectile_stagger_delay > 0`.** `power_02_ring` is an example: its rings spawn at the same point, with the same direction, and all aim at the **same** nearest enemy, so at 0 they would fly identical paths, stacked.

**`BasePower`** — `Area2D` base for all projectiles: life-time countdown, per-enemy hit cooldown (`enemies_last_hit`), damage calculation, knockback multiplier from globals. Provides `calculate_projectile_spread_angles()`, `find_nearest_enemy_on_screen()`, `find_random_enemy_on_screen()`, and **`_enemy_body_position(enemy)`**.

**Targeting reads the enemy's BODY, never its origin.** `_enemy_body_position()` resolves to `EnemyBase.get_body_center_position()` (with a defensive fallback) and is the **only** way a power should read an enemy's position — both to pick a target and to aim at it. Reading `enemy.global_position` targets the **feet**, below the body, which visibly makes attacks converge on the ground. It is used by the shared selection helpers (on-screen test + distance ranking, so an enemy whose body is visible but whose feet are off-screen still counts) and by attacks that chase an enemy, for example `power_02_ring` (arc destination), `power_04_bo` (straight-shot direction) and `power_06_snowflake` (where the flake spawns). Any future enemy-seeking attack must use it too.

### `power_06_snowflake`
- Uses `TargetTrackerGlobal`, through `find_random_enemy_on_screen()`: a FIFO exclusion list limited by `max_recent_targets`. The list works one target at a time and nothing tells it when a volley starts. Its reset deduces that from the time since the last target, compared with `attack_data.interval`. With two or more flakes that time is normally shorter than the interval (the volley's own duration consumes part of it, and the global cooldown reduction is not in `attack_data.interval`), so the reset normally does not fire between volleys. This is accepted: old targets still leave the list, and a repeat is allowed when every enemy on screen is recent.
- Set `anim.modulate.a = 0.0` before positioning the node to prevent a one-frame flicker at the origin.
- **No enemy on screen → it falls IN FRONT of the player, on the side they FACE**, from the player's BodyCenter (`fallback_distance_*`, `fallback_vertical_range`). The side comes from `set_power_direction()`, fed by `AttackController` with `int(player.facing_direction)` at fire time — the same door as the other directional powers. It used to read `velocity.x`: standing still `velocity` is `(0, 0)`, falsy in an `if`, so the default (right) won, and moving only vertically gave `x = 0` → right too; facing left while standing, the flake fell on the right. **Never derive "which side" from movement — use `facing_direction`.**

### Powerups

- **`PowerUpController`** (`entities/controllers/power_up_controller.tscn`) — child of player; holds `Array[PowerUpData]`. `apply_upgrade(id)` raises the level and recomputes all stats into `PowerUpStatsGlobal.update_stats()`.
- Powerup data lives in `data/power_up_data/`.
- `PowerUpStatsGlobal.stats_changed` triggers `AttackController._on_stats_changed()` to recalculate all attack timers immediately.
