extends EnemyBase

# =================================================
# NODES
# =================================================
@onready var navigation_agent_2d: NavigationAgent2D = $BodyCenter/NavigationAgent2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# =================================================
# READY
# =================================================
func _ready() -> void:
	navigation_agent = navigation_agent_2d
	anim = animated_sprite

	super._ready()

	go_to_idle_state()
