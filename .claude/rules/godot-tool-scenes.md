---
paths:
  - "scripts/barrier.gd"
  - "scripts/chamber.gd"
  - "entities/stage_parts/barrier.tscn"
  - "entities/stage_parts/chamber.tscn"
---

**`@tool` scenes that change their own nodes by code:** don't cache those nodes with `@onready`. In editor context, `_ready()` or a setter can run before all children exist (e.g. right when the script is attached), so an `@onready` capture can silently become `null` and never update — the code then does nothing, with no error, until the scene is closed and reopened. Instead, look the nodes up **inside** the function that changes them (`get_node_or_null(...)`), so it always finds whatever exists at that moment.

**Any `Shape2D` (or other sub-resource) a `@tool` script mutates by code must be `resource_local_to_scene = true`.** Without it, Godot shares that one resource across the base scene *and every instance* — resizing one barrier resizes the base scene's shape and every other instance too. Set it on the shape of each affected `CollisionShape2D` before placing multiple instances.

**A stage listed as changed after only playing is normally this flag.** The diff shows only `RectangleShape2D_xxxxx` ids changing, in the `sub_resource` line and in its `shape = SubResource(...)`, with no value changed, so the game is unaffected. The shapes of doors and chambers carry `resource_local_to_scene = true`, and the editor saves before running (`run/auto_save/save_before_running`), so F5 is enough to produce it without touching the scene. The git history of the stages confirms it recurs. Not confirmed: the exact mechanism inside the engine, and why one save reaches an open stage and not another.

**The `RESET` animation gotcha:** the first time you key a *new* property track in any animation, Godot auto-creates (or updates) a special `RESET` library entry, capturing whatever value was live on the node **at that moment** as the "true" default. From then on, the editor re-applies that stored value whenever it resyncs (selecting the `AnimationPlayer`, reopening the scene…) — silently overwriting any value you set by hand afterward in the Inspector. If a property's default won't "stick" no matter how many times you fix it, check `[RESET]` in the animation dropdown — that's almost always where the stale value actually lives. **The fix is to re-key the correct value into `RESET`, not to delete it**: `RESET` is a Godot convention (the editor auto-creates it and does not offer a delete action for it), it never runs at runtime unless code explicitly calls `play("RESET")`, and an empty one is harmless. Select `[RESET]` in the dropdown, set the property to the intended default in the Inspector, and press the key icon to overwrite the stored value.

**Reacting to a manual rotation (Inspector/gizmo) is polling, not a notification:** `NOTIFICATION_TRANSFORM_CHANGED` (via `set_notify_transform(true)`) is the "correct" Godot API for "tell me when this node's transform changes", but proved unreliable for a `@tool` script reacting to editor-driven rotation — it silently never fired. The working fix is a `_process()` comparing `rotation` against a cached `_last_rotation` each frame and re-applying the tile counter-rotation when it changes. Cost is negligible (one float compare per barrier per frame, editor and game alike) — when an "official" transform-change hook doesn't fire reliably in `@tool` context, don't fight it, poll.

