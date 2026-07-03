extends EnemyBase

const IMPACT_01 = preload("uid://bg33gkayu217w")
const XP_ITEM_01 = preload("res://entities/items/xp_item_01.tscn")  # NOVO!

# =================================================
# NODES
# =================================================
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = $Hitbox

# =================================================
# READY
# =================================================
func _ready() -> void:
	navigation_agent = navigation_agent_2d
	anim = animated_sprite
	hitbox = hitbox_area
	
	super._ready()
	
	go_to_idle_state()

# =================================================
# DEAD STATE
# =================================================
func dead_state() -> void:
	queue_free()

# =================================================
# OVERRIDE: DEATH EFFECT
# =================================================
func _spawn_death_effect() -> void:
	var impact = IMPACT_01.instantiate()
	add_sibling(impact)
	impact.position = position

# =================================================
# OVERRIDE: ITEM DROP (NOVO!)
# =================================================
func _get_drop_item_scene() -> PackedScene:
	return XP_ITEM_01  # Gator dropa XPItem01

# =================================================
# HITBOX
# =================================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("PlayerHurtbox"):
		player_in_contact = true
		if player:
			player.take_damage(damage_per_tick)
		damage_timer.start()

func _on_hitbox_area_exited(area: Area2D) -> void:
	if area.is_in_group("PlayerHurtbox"):
		player_in_contact = false
		damage_timer.stop()
