---
paths:
  - "autoload/xp_manager.gd"
  - "autoload/level_up_manager.gd"
  - "scripts/xp_item.gd"
  - "scripts/level_up_ui.gd"
  - "scripts/xp_bar.gd"
  - "scripts/loadout_bar.gd"
  - "entities/items/**"
---

### XP & Level-up flow

1. Enemy dies → drops XP item(s) chosen from its `drop_table` (see Enemy system). XP items normally share `scripts/xp_item.gd` (`class_name XPItem`) and differ only by Inspector calibration (`xp_value`, sprite) — e.g. `xp_item_01.tscn`, `xp_item_02.tscn`. New item scripts are only created when collect logic diverges (e.g. a future healing item).
2. Player picks up item → `XPManagerGlobal.add_xp()`.
3. XP fills → `level_up` signal → `LevelUpManagerGlobal._on_level_up()`.
4. `LevelUpManager` pauses game (`GameStateGlobal.UPGRADE`), generates `options_count` options from `AttackController` and `PowerUpController` pools.
5. Player selects → `controller.apply_upgrade(id)` → `level_up()` on the relevant resource, which owns the level ceiling (see *Shared progression* in `powers-and-powerups.md`).
6. `AttackController._check_upgrade_changes()` detects the level change next physics frame and updates the timer.

**How the menu picks its options** (`generate_upgrade_options()`): the pool holds every power and powerup below its `max_level`. When `attack_capacity` or `powerup_capacity` is reached, nothing new of that kind can be unlocked, while what is already owned keeps leveling. Up to `early_game_threshold`, at least one attack is guaranteed while any is available. With an empty pool, the only option is *First Aid*, which heals `heal_amount`.

**Where the values live.** The curve settings are plain variables in `xp_manager.gd`. The `@export`s of `LevelUpManager` (`options_count`, the capacities, `early_game_threshold`) sit on a script autoload, so they are also changed only in code.

**XP curve** — `XPManager` computes the requirement for the next level in `_calculate_xp_requirement()`, selected by `xp_scaling_type` (`ScalingType`). Four modes, all kept:
- `LINEAR` — `base × level`: constant increment, never accelerates.
- `EXPONENTIAL` — `base × factor^(level−1)`: geometric; uses `xp_scaling_factor`. Its shape is inherently *flat start + late explosion* (small base + `int()` truncation glues the first steps, then the ratio compounds into thousands) — hard to tune well.
- `FIXED` — `base`: same cost every level.
- `POWER` — `base × level^exponent`: polynomial; uses `xp_power_exponent`. Rising steps from level 1 with no runaway — the mode that gave the wanted pacing where the other three couldn't.

Key facts: `base_xp_requirement` sets level 1's cost and anchors **every** mode (level 1 always costs `base`, since all four formulas equal `base` at level 1). `xp_scaling_factor` is used by **EXPONENTIAL only**; `xp_power_exponent` by **POWER only**. `xp_to_next_level` is an **output** (recomputed each level), never an input — editing it does nothing. The requirement is only one side of pacing; XP *supply* (drop rate + item value) is the other — tune the curve first, then the drops. (Concrete factor/exponent/base values are live calibration, not documented here.)

**Implicit level-up queue** — `XPManager._check_level_up()` grants at most **1 level per call** (`if`, not `while`) and is blocked by `is_waiting_for_upgrade` while a menu is pending. Surplus XP stays in `current_xp` and acts as the queue: when the player confirms a choice, `LevelUpManager.apply_upgrade()` calls `XPManagerGlobal.upgrade_selected()`, which re-checks the surplus — if it covers another level, a new menu opens **synchronously** and the game stays paused in UPGRADE (no COMBAT flicker between chained menus). Two ordering constraints keep the synchronous chain working: `apply_upgrade()` re-checks *before* unpausing (and returns without unpausing if a new menu opened), and `level_up_ui._on_option_pressed()` hides the menu *before* emitting `option_selected` (hiding after would erase the newly opened menu).

**XPBar is pause-immune** — `process_mode = PROCESS_MODE_ALWAYS` so level-up animations (label pulse, bar fill) complete behind the paused upgrade menu. New XP can't enter during the pause (`add_xp` is gated by `is_combat_allowed()`), but a chained level-up does change the values: `_level_up()` subtracts from `current_xp` and emits `xp_changed` with the game paused. Gotcha: `get_tree().create_timer()` inside XPBar sequences must pass `process_always = true` — SceneTree timers ignore the node's `process_mode` and would freeze the animation chain mid-sequence.

**Unlock notifications reach the LoadoutBar via two asymmetric routes** (pause does not block signals — only `_process`/`_physics_process`/input): `PowerUpController` emits `powerup_unlocked` synchronously inside `apply_upgrade()`, but `AttackController` emits `attack_unlocked` from its `_physics_process` polling, which is paused during the upgrade menu — so it only fires after unpause, too late for chained menus. `LoadoutBar` therefore listens to **both** `LevelUpManagerGlobal.upgrade_applied` (synchronous, updates during pause; only acts on `next_level == 1`) and the controller signals (covers debug keys and future unlock sources), deduplicating by id (`filled_attack_ids` / `filled_powerup_ids`) since menu unlocks arrive through both routes. Don't "fix" the asymmetry by making `AttackController` process-always or by calling `_check_upgrade_changes()` synchronously — attack timers would tick during pause, and `start_immediately` shots would be swallowed by the `is_combat_allowed()` guard.
