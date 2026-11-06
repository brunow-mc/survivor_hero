---
paths:
  - "scripts/enemy_*.gd"
  - "scripts/player_*.gd"
  - "scripts/camera.gd"
  - "scripts/attack_controller.gd"
  - "scripts/power_05_gear.gd"
  - "entities/enemies/**"
  - "entities/players/**"
---

### Entity anatomy — details

The convention itself (feet origin + `BodyCenter`) and the "degrade AND warn" contract live in `CLAUDE.md`.

**`BodyCenter` and the collider.** On the player the physics collider sits near the feet and `BodyCenter` marks the centre of the visible body. On enemies `BodyCenter` tends to coincide with the centre of the physical collider, but this is a tendency, not a law: the enemy construction design is not concluded (see *Knockback* on the `Hurtbox`). An enemy that separates them must review what assumes they coincide, such as the steering wall raycasts, which start at `BodyCenter`.

**Enemy navigation is anchored on BodyCenter via reparenting**: each enemy's `NavigationAgent2D` is a child of `BodyCenter`, not of the root. `NavigationAgent2D` navigates **its parent node's position** — so path start, waypoint advancement and `is_navigation_finished()` all operate at `BodyCenter`. `enemy_base.gd` caches the parent as `_nav_anchor` and computes direction as `next_path_position − _nav_anchor.global_position` (never `to_local()`, which is feet-frame). `makepath()` targets the **player's BodyCenter** (body chases body). Nice property: when navigation finishes, `get_next_path_position()` returns the agent (= BodyCenter) position, so the direction degenerates to `Vector2.ZERO` and the enemy gracefully stands still.

**Enemy-to-player distances are BodyCenter-to-BodyCenter**: `distance_to_player` (`stop_distance` / `attack_distance`) uses the enemy's BodyCenter (`_nav_anchor.global_position`) to the player's BodyCenter (`player_body_center`, cached in `_setup_base`; fallback to each origin). This is the **same frame the chase uses** (`makepath` targets the player's BodyCenter, and the enemy navigates its own BodyCenter) — so the enemy stops and switches to its attack animation exactly when the two **bodies** are close, matching what it is chasing. The game simulates 2.5D depth but is essentially 2D: consistency with the chased point matters more than the height-symmetry an origin-to-origin measure would give. (Historically this was feet-to-feet at the scene origins, which drifted from the chased BodyCenter and made enemies stop/attack based on the wrong point.)

**Body-anchored systems read the BodyCenter**, falling back to the origin. Examples: enemy pathfinding target (`makepath`), item drops (`_spawn_single_drop_item`, base = enemy's own BodyCenter via `_nav_anchor`), **enemy knockback direction** (see *Knockback*), **power targeting** (every attack that chases an enemy — see *Attack system*), player-attached attacks, and the **camera** (follows the player's body, not its feet).

**The accessors.** `get_body_center_position()` is what `CLAUDE.md` tells every system to use.
- **On enemies:** `EnemyBase.get_body_center_position()`, fallback chain `BodyCenter` → `_nav_anchor` → origin.
- **On the player:** `PlayerBase.get_body_center_position()`, fallback `BodyCenter` → origin. Examples of use: the camera, attached-attack spawn, the gear orbit (`player.to_local(...)` — gear lives in the player's local frame), the snowflake fallback, the `power_04_bo` return, the XP item attraction and the spawn distance checks. This list grows: a new system that reads where a body is joins it.

**One deliberate exception:** `EnemyBase` caches the player's BodyCenter *node* (`player_body_center`) and reads `.global_position` in `update_direction()`, a per-frame per-enemy hot path where a node-property read beats a method call — do not "uniformise" it. The cache assumes **one player per run, created before the enemies and alive for the whole match** — no runtime player swap in a stage that has enemies (see *Player*: swapping is legal only in the safe house). So the risk is not staleness but **creation order**, and that is handled: spawning starts only after the player exists, and a missing player makes `start_spawning()` `push_error` and never enable spawning, so no enemy is ever born with an empty cache. The camera already tolerates a missing player via per-frame re-acquisition.

**Attached attacks.** `AttackController._spawn_single_projectile()` places **any** `attach_to_player` attack at the player's BodyCenter — automatic for future attacks with that flag, no per-attack code needed (for example, electricity and gear). **Exception — attacks that rewrite their own `position` every physics frame** (orbitals like `power_05_gear`): the spawn placement is overwritten on the first frame, so their movement formula must add the body offset itself — gear captures `_orbit_center_offset` from the player's BodyCenter in `_ready` and adds it to the orbit position. Any future self-positioning attached attack needs the same anchoring.

**Player markers:** `BodyCenter` and `AttackPositionRight/Left` are **all declared in `PlayerBase`** with `get_node_or_null`, and every consumer has a fallback chain — e.g. projectile spawn: `AttackPositionRight/Left` → player `BodyCenter` (`PlayerBase.get_body_center_position()`) → `player.global_position`. A player scene missing markers still works (attacks spawn slightly off) and `AttackController.setup()` warns, so the omission is visible in the console.

**Current guards** (all at init, all silent when the project is correct):

| Guard | Where | Catches |
|---|---|---|
| Player `BodyCenter` | `AttackController.setup()` | projectile spawn, `attach_to_player` attacks, a self-positioning orbit and enemy chasing all falling back to the feet |
| Player `AttackPositionRight/Left` | `AttackController.setup()` | directional attacks spawning without their lateral offset |
| `Hurtbox` / `EnemyHurtbox` group | `EnemyBase._validate_scene_setup()` | **enemy would be invulnerable** (powers gate damage on that group) |
| `Hitbox` | `EnemyBase._validate_scene_setup()` | **enemy deals no contact damage** |
| Enemy `BodyCenter` | `EnemyBase._validate_scene_setup()` | aim, knockback and navigation reverting to the feet |
| `NavigationAgent2D` not under `BodyCenter` | `EnemyBase._validate_scene_setup()` | navigation silently returning to the feet frame (the historical "arc" bug) |
| `Hurtbox` / `PlayerHurtbox` group | `PlayerBase._validate_scene_setup()` | **player immune to contact damage** |
