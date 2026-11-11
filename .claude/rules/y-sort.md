---
paths:
  - "entities/stage_parts/y_sort_container.tscn"
  - "stages/**"
  - "tiles/**"
---

### Y-sort (2.5D depth illusion)

Entities and scenery tiles occlude each other by Y position (feet origin = the sort line). Three requirements, ALL mandatory:

1. **Same `z_index`** — Y-sort only breaks ties within one z level; a different z overrides it. The world standard is **`z_index = 2`** (`z_as_relative = true`): player, enemies, XP items set it on the scene root; TileMap layers get it **per-tile in the TileSet** (setting it on the TileMapLayer node in the Inspector does NOT work for this — leave the layer at z 0 and paint z 2 inside the TileSet tiles).
2. **`y_sort_enabled = true`** on the entity root and on participating TileMap layers.
3. **Being a child of the Y-sort container** — Y-sort only sorts CHILDREN of a `y_sort_enabled` parent. Each stage instances **`entities/stage_parts/y_sort_container.tscn`** (a configured, permanently-empty Node2D `YSortContainer`: z 0, y-sort on). **The container stays at z 0 on purpose:** relative z sums with the parent, and a neutral container means the `z_index` written on an entity or tile is the effective one — a container at 2 made every child silently land 2 higher, which was easy to forget. **The membership criterion is functional and single: anything that needs variable occlusion along the Y axis (Godot's Y-sort) goes inside the container; anything that doesn't stays outside.**
   - **Player and enemies always belong to the container** (they always need variable occlusion), and **both join at runtime**: the player via `PlayerSpawner`, enemies via `SpawnManager` (see next paragraph). Both resolve the container by the `YSortContainer` group, so a stage wires nothing, and no player is placed in a stage tree by hand.
   - **TileMap layers are case-by-case**, decided per layer by whether they need to trade occlusion with entities. **No layer trait decides this**: having collision does not determine participation (`TileMapDecoration` itself has colliders and is inside), having navigation does not either, and tiles with neither collision nor navigation don't either. Only the functional criterion decides.
   - **Expect TileMaps both inside and outside the container within the same stage.** Typically a floor layer does not need variable occlusion and stays outside — that is the only "normal" case; no other TileMap name should be treated as fixedly inside or outside.

   Content placed in the editor inside the instance belongs to the stage file; never add children to the base scene `y_sort_container.tscn` (they would be shared across every stage).

   **Why the container matters for spawned enemies:** Y-sort only compares children of the same `y_sort_enabled` parent. Player and enemies are all `z_index = 2`, so inside the container they tie on z and Y-sort orders them by their feet. If enemies were parented anywhere else (the scene root, for example), they would still be at z 2 but would no longer be sorted against the player: who covers whom would follow tree order, the same way for the whole match, whatever their Y.

   **Tiles outside the container never trade occlusion by Y.** A layer can mix tiles with different per-tile `z_index` — a building's normal tiles at 0 and its `*_front` tiles at 4 in the same layer, besides block-type tiles. A tile above the entities' 2 always covers them (the front tiles the silhouette relies on); a tile below always stays under. A tile at exactly 2 belongs inside the container with Y-sort, like the decoration layer; left outside at 2 it would tie with the entities and fall back to tree order.

   **The container is resolved automatically by group — no per-stage wiring.** The base scene `y_sort_container.tscn` carries the group **`YSortContainer`**, so every instance in every stage is already in it. `SpawnManagerConfig.initialize_spawn_manager()` resolves in cascade: the `enemy_container` export (explicit override) → `get_first_node_in_group("YSortContainer")` → nothing (one `push_warning`). **Leave the export empty in the normal case**; fill it only to disambiguate a stage with more than one container. This replaced a manual drag-and-drop step whose omission broke Y-sort silently (deleting a container invalidated the NodePath and a fresh one was never auto-reassigned).

**Spawned entities join the container via explicit parenting**: the container resolved by `SpawnManagerConfig` (see above) is transferred to `SpawnManagerGlobal` — `spawn_enemy()` adds enemies there (fallback: scene root, no Y-sort). Item drops inherit it for free (`_spawn_single_drop_item` adds to the enemy's `get_parent()`), and projectiles too (`add_sibling(player)` = child of the player's parent). Tile occlusion switch points are calibrated via each tile's **Y Sort Origin** in the TileSet relative to the entity feet origin.
