---
paths:
  - "autoload/hold.gd"
  - "scripts/stage_config.gd"
---

### Brief holds — details

What a hold is, how to ask for one and the two sets live in `CLAUDE.md`.

**Rejected alternatives.** **`get_tree().paused`** (freezes the hold's own timer and the stage music, and collides with the pause menu — `resume_game()` would unpause the tree mid-crossing); **a new `GameplayState`** (states are exclusive and drag `StageConfig`, the level-up menu's memory and `previous_state` along, while holds overlap and last half a second — a boss may use the `CUTSCENE` state *and* a hold, two layers); **a flag on `PlayerBase`** (dies with the player, and the chamber swap destroys and recreates the player mid-hold — which is also why the hold lives in an autoload).

**Why requests overlap.** A scope is free only when every request holding it has been released — with a plain boolean, the first request to end would unlock everything while another still holds (the stage-start hold ending mid-door). Durations can be constants in an autoload or plain script, an `@export` on a scene like a chamber or boss, or a field on `StageConfig` for a stage-start hold.

**Safety rules:** `clear()` runs on **every scene change** (in the shared `_end_current_scene()` of `restart_game()` and `go_to_scene()`) — a request whose owner dies with the scene would otherwise leave the player frozen in the next one. Tickets are **never reused**, even after `clear()`, so a stale `hold_for()` expiring later cannot release a new request. Waits never use `process_always`, so a hold **waits while the pause or level-up menu is open** — the two kinds of pause compose.

**`TRANSITION` is what doors ask for, not their own list**, so when a new scope is implemented it joins that set and every door holds it without touching the door's script (a future "cinematic" set would work the same way). It also covers the fade-out half of a scene change.

**`SCENE_ARRIVAL` is asked by whoever must also hold the start of the attacks**: for example the arrival hold in `GameStateGlobal._swap_scene_in_dark()`, from the swap until the fade-in ends, the stage-start hold and the chamber swap. **The match starts when the screen finishes clearing**: no attack fires in the dark, and the player's initial hesitation gives the stage start visual weight ("doesn't start in a tumult"). The arrival hold covers every scene change (stage door either way, restart, Main Menu) and does not care about the destination's mode — in EXPLORATION it waits too, unnoticed, since the gate blocks firing anyway. **F5/F6 straight into a stage has no arrival hold**, so attacks start at once unless `start_hold_seconds` is above 0; harmless, since in the real game every stage is entered through an event (a door, a menu). The fade-in alone gives a hesitation equal to **the caller's fade-in duration**; on top of it each stage can add its own **stage-start hold** (`StageConfig.start_hold_seconds`, see *Every stage DECLARES its own mode*).

**Stage-start hold — it starts AFTER the fade-in and ADDS to it.** The value means "seconds of hesitation with the screen already clear", identical by every entry path, and it also covers F5 (no fade, so it counts at once). Rejected: starting with the scene and overlapping the fade, where the visible wait would vary with the caller's fade-in and a value below the fade would do nothing. Mechanics (`StageConfig._run_start_hold()`): the hold (`SCENE_ARRIVAL`) is **requested in `_enter_tree()`** — on F5 the player is born in `PlayerSpawner._ready()`, and a request made in `StageConfig._ready()` could come after its `AttackController` already started; then, if `GameStateGlobal.is_changing_scene()`, it awaits `GameStateGlobal.scene_arrival_finished` (emitted right after the fade-in, **before** the arrival hold is released — the two holds overlap, so no frame slips free between them); then a **pausable** timer of `start_hold_seconds`; then release. A restart mid-wait is safe: `HoldGlobal.clear()` wipes it, and the stale ticket's late `release()` is ignored.

**Scopes in code:**

| Scope | Freezes | Used for |
|---|---|---|
| `PLAYER_INPUT` | movement input in `PlayerBase.move()` (direction zeroed → keeps facing, visual FSM goes idle) | doors, chamber, stage start |
| `ATTACKS` (start only) | the **start** of the attacks: while held, `AttackController.setup()` sets `_waiting_to_start` instead of starting; `_physics_process()` tests the bit and, on release, `_start_attacks()` starts every timer with level > 0 and fires the `start_immediately` shots — once. Attacks already running never stop (an unlock during the wait is left to the release). `_create_attack_timer()` only creates timers | scene arrival, stage start, chamber |
| `ENEMIES` | movement **and contact damage together** — a held player touching a moving-or-damaging enemy would take hits with no way to flee. Movement: one check in `EnemyBase._physics_process()` **after** the DEAD branch (player attacks keep running through doors, so dying mid-hold must still work; knockback received while held is applied on release; sprite animation keeps playing). Damage: one check in `PlayerBase.take_damage()`, next to the `is_combat_allowed()` gate — one place covers both contact paths (the initial touch and the damage timer, both in `enemy_base`) | doors, scene arrival, boss, hitstop |
| `SPAWN_CLOCK` | **the whole `SpawnManager._physics_process()` loop, by one check at its top** (after `is_spawning_enabled`): match clock (`game_time`, `time_since_start`), difficulty growth, budget accumulation, the initial delay, teleport and spawning. Blocking only the spawn step would let budget **and difficulty** grow while the player can do nothing, and a long hold would end in an undeserved burst. **Calibration consequence:** on arrival the clock is frozen during the fade-in, so `initial_spawn_delay` counts only after the screen clears | doors, scene arrival, stage start, boss |

**Ideas with no code yet:**

| Idea | What it would freeze | Would serve |
|---|---|---|
| attacks (time stopped) | extends `ATTACKS` from "delay the start" to "freeze running attacks" — three timing layers in `AttackController`: **pause** the looping `Timer`s (`Timer.paused`, keeping the remaining time — faithful to "time stopped", unlike skipping the shot); re-check **inside** the staggered-projectile loop, since the gate is checked only before the loop; **defer** (not drop) `start_immediately` shots | stage start, boss — **never doors** (see below) |
| *(maybe)* projectiles | powers in flight and player-attached ones (`gear` keeps spinning and would hit frozen enemies). Costly: every power moves itself in its own `_physics_process()` | boss, hitstop — decide on a real case |

**Doors do NOT interrupt attacks — decided by playtest, not by omission.** With the safe house temporarily in COMBAT and every attack on, attacks kept firing normally through room-door crossings, and it read well: it communicates what is happening and suits a combat stage with few or many doors. So the `attacks` scope must **never** join `TRANSITION`. A stage door is the same story: attacks run only during the fade-out half, and the scene change then destroys them. The three attack mechanisms in the table are kept for the cases that really want "time stopped" (stage start, boss), not for doors.

**Hold vs event — the boomerang problem (accepted, no event).** `power_04_bo` flies back toward the player's body (`get_body_center_position()`), so after a room-door crossing it returns from the room the player left. Rooms are laid out in geometric order but far apart (as most of the level design will be), so the bo comes back from the right direction, just with a long delay — judged **acceptable** in play. The planned fix (an **event** at the instant of the move removing non-attached projectiles via the `Power` group) was therefore **dropped**; `Power` stays reserved. If it ever returns, the reasoning still holds: the issue is *place*, not *time* — freezing the bo would not help — and cleaning what was left behind is an event owned by the trigger, not a hold.

**Powerups: what only changes a number is immune; what ACTS over time must consult the hold.** A regeneration-per-second, a pulse every N seconds, a damage aura or a recharging shield crosses that line — effectively attacks, entering through the same door as attacks.

**`TargetTrackerGlobal` uses the wall clock (`Time.get_ticks_msec`)**, which neither a hold nor the pause menu stops. Holds do not interfere with its list, because doors keep the attacks firing. Music and camera keep going during a hold, as wanted. A future use the same system covers: **hitstop** (enemies + projectiles for ~0.05 s on a heavy hit).
