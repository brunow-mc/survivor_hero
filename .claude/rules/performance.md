---
paths:
  - "scripts/navmesh_merger.gd"
  - "entities/stage_parts/navmesh_merger.tscn"
---

## Performance budget (measured, not assumed)

Target: **60 fps = 16.7 ms of CPU per frame**. Physics runs at a fixed 60 Hz while rendering runs free, so ~30% of drawn frames carry no physics tick — only the frames that *do* are worth measuring.

Measured on the dev machine with ~108 live enemies, wall-clock deltas, V-Sync off (so no wait is counted as work):

| Part | ms |
|---|---|
| **navigation** (`update_direction()` × N) | **~0.35** |
| engine servers (physics + navigation) | ~2.1 |
| move_and_slide | 0.60 |
| steering | 0.50 |
| **rendering** | **~0.5** |
| spawn + teleport + attacks | 0.14 |
| **total** | **~5.2 ms** |

The rows add up to ~4.2 ms; the remaining ~1 ms was not attributed to any part.

The navigation row assumes the merged navmesh (see *NavmeshMerger*); before it, that single row cost **~3.1 ms** and dominated the frame.

A frame with **no** physics tick costs ~0.5 ms — subtracting it from the full frame is how the engine-server row above was isolated, without instrumenting the engine.

Express the target as **fixed cost + cost per enemy**, never as "the game handles N enemies": `max_enemies` is per-stage and deliberately undefined for a long while yet (see Spawn system).

Three conclusions that should stop old debates:

- **There is no longer a dominant cost.** Navigation used to be ~40% of the frame; the merged navmesh removed it. Steering, `move_and_slide`, spawn, teleport, attacks and rendering **together** are under 1.8 ms — all closed subjects. Before optimizing anything here again, measure: nothing left is known to be expensive.
- **The stutters were never compute.** With V-Sync on, the same frame measured ~13.9 ms, of which ~7.5 ms was the game standing still waiting for the display; the judder came from the presentation path, not from work. A light CPU graph plus a bad feel means pacing, not load.
- **Rendering measured ~0.5 ms.** A 480×270 pixel-art game was nowhere near GPU-bound. This measurement predates the occlusion silhouette, which uses a shader, so measure again before relying on it.

**Any future measurement must run with V-Sync disabled**, or the wait is silently attributed to whatever bucket closes the frame — which is exactly how a phantom "8.9 ms of engine/render cost" appeared and survived several rounds of analysis.

### NavmeshMerger — why the navmesh is baked, not per-tile

`TileMapLayer` creates **one navigation region per tile** (3,762 in stage_01 when the merger was created). Every path query locates its start/end polygons by **linear scan over every polygon in the map**, so that scan — not the A* search — was the cost (measured at that time):

| | per-tile | merged |
|---|---|---|
| polygons | 3,762 | **206** |
| `map_get_closest_point` | 125 µs | **3.7 µs** |
| one path query | ~300 µs | **19 µs** |
| in game, per enemy per frame | 39 µs | **4.3 µs** |

It was the *same* linear scan that already cost ~40 ms per spawn scan and forced reading tile data directly — reappearing through another door. **It scales with polygon count, never with enemy count**, which is why cutting enemies never helped.

**`entities/stage_parts/navmesh_merger.tscn`** (script `scripts/navmesh_merger.gd`) replaces those regions with a single baked one. It is a reusable **scene**, like the other stage pieces (for example `stage_config` and `barrier`) — it used to be a bare `Node2D` with the script attached by hand in each stage, the only one off the pattern. The base scene stores **no** property values, so all three exports come from the script defaults (`mode = MERGED`, `log_bake` on, `verify_connectivity` off) — which is exactly the wanted project-wide default. **Configure on the instance, never on the base scene:** ticking `verify_connectivity` there would make every stage run 60 route checks on load (same rule as `SpawnManagerConfig`).

**It is a `Node2D` because of `get_world_2d()`, not because of its transform.** `get_world_2d()` lives on `CanvasItem`; a plain `Node` does not have it, and the script needs it twice to reach the 2D navigation map where the baked region is registered. Its own position is **ignored by design** — the region is registered with `Transform2D.IDENTITY`, and the tile polygons are converted through each `TileMapLayer`'s own `to_global()`. So moving this node in the editor changes nothing, and "simplifying" it to a plain `Node` would break the bake.

Non-obvious properties, all load-bearing:

- **It bakes in `_enter_tree()`.** Godot fires every `_enter_tree()` before any `_ready()`, so the mesh exists before `SpawnManager` starts and before any enemy calls `makepath()` — **regardless of where the node sits in the scene**. Moving it to `_ready()` would make correctness depend on tree order.
- **It reads each tile's REAL polygon, never the cell.** Navigable tiles are normally full squares, so both would agree — which is exactly what makes the shortcut dangerous: it would pass every test and break silently on the first partial tile. Square tiles take a fast path (maximal rectangles, 3,762 cells → 166 rectangles); any other shape goes through the general union untouched.
- **`agent_radius = 0`** on the baked mesh, so the geometry matches the tiles exactly. Any positive value shrinks the mesh and changes where enemies can walk.
- **Per-tile navigation is disabled only after the bake succeeds.** Any failure warns and leaves the native navigation intact — the map is never left unnavigable.
- **It sweeps for layers with navigation** rather than taking a list, because that is the same union semantics the native navmesh applies. **Not** `enemy_spawn_excluded_layers`, which decides where enemies are *not born* (nor teleported to), not where they *walk*.
- **Reverting is one Inspector field**: `mode = PER_TILE`. The TileSet is never touched.
- **`verify_connectivity`** (opt-in) samples 60 point pairs and warns if any route no longer reaches its target. Run it after editing scenery; leave it off otherwise. It is **asymmetric** — it detects a *lost* passage, never an *invented* one (a spurious diagonal join would keep every route working). Only playing catches that.
- **A stage without the node still works**, on per-tile navigation — a silent performance regression, not a bug.
- **Engine warning `Navigation map synchronization had N edge error(s)` in a stage without the node:** navigable tiles of two layers on the same cell stack identical polygons. Painting over a cell in one layer only replaces its tile, so the overlap needs two layers, normally with different TileSets. Erase one of the two tiles. The `cell_size` advice in the warning does not apply.

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

### Measuring — how this project learned to measure

- **Measure before optimizing — and measure the suspect call, not the frame.** The spawn stutter cost four failed optimizations (grid cache frequency, `group_adjacent_points` O(N³)→hash, query reuse, moving to `_physics_process`) because they attacked what *looked* expensive. The profiler's script self-time does **not** include time spent inside server calls, so the real culprit was invisible: 98% of the scan sat inside `map_get_closest_point`. What settled it was temporary instrumentation timing the suspect calls directly, and then running old and new methods **side by side** to prove equivalence before swapping.
- **`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the WORST frame of the last second, published once per second — never a per-frame cost.** Godot accumulates a max and only publishes it when the 1 s slice closes, so the same value repeats for ~60 frames. **The Analisador's Process/Physics Time graph plots exactly these monitors**, so it is an envelope of maxima sampled at 1 Hz — which inherently draws a sawtooth. This cost a whole investigation: a "periodic spike every ~150 frames" was chased through the teleport cycle, the grid scan, the spawn cadence and the attack system (all four tests negative) before the metric itself turned out to be the artifact. Measuring frame time properly means `Time.get_ticks_usec()` deltas between frames (wall time, includes render) with percentiles — at which point the real answer was 0.1% of frames above 21 ms, none above 34, with a full horde of 38 bodies / 474 collision pairs. **Corollary for any future in-game instrument: never `print()` per frame** — the console goes through the debugger socket and the measurement starts paying for itself; buffer in memory and print aggregates only.
- **Never measure a call's cost by playing.** Two sessions with identical settings differed by **53%** on the same metric, because the cost of an A* query depends on *where* the fight happens (route length, how open that part of the map is) — so the play route silently becomes the independent variable, and any effect smaller than that swamps. Costs of a *call* are measured by a **deterministic bench**: fixed seed, fixed point pairs, issued straight at the server with the game stopped, so two runs return the same number. In-game instrumentation is only for **confirming** a gain a bench already proved. A whole sweep of `NavigationAgent2D` settings was run, and discarded, before this was understood.
- **A measuring instrument must report its own validity.** The bench prints whether each setting even existed in this Godot version (`INDISPONIVEL`, never a fabricated number), how many routes actually reached their target (a setting that "gains" by breaking navigation is exposed on the spot), and how many enemies were alive competing for CPU. An instrument that can quietly lie is worse than no instrument — and this project has already lost rounds to `Performance.TIME_*`, to a `PackedFloat32Array` that silently discarded every sample, and to paused frames diluting an average.
- **Instrumentation must not alter the game.** A bench that disabled spawning to reduce noise broke the run for anyone who pressed F5. Side effects of temporary code are stated up front, not buried in a paragraph.
