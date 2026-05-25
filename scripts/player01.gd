extends PlayerBase

# =================================================
# NODES
# =================================================
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var hurtbox: Area2D = $Hurtbox
@onready var attack_controller: AttackController = $AttackController
@onready var attack_position_right: Node2D = $AttackPositionRight
@onready var attack_position_left: Node2D = $AttackPositionLeft

# =================================================
# CONTROLE DE ANIMAÇÃO
# =================================================
var current_anim: String = ""
var is_attacking: bool = false

# =================================================
# READY
# =================================================
func _ready() -> void:
	super()

	_play_anim("idle")

	attack_controller.primary_attack_started.connect(_on_primary_attack_started)
	attack_controller.setup(self, attack_position_right, attack_position_left)

# =================================================
# MOVIMENTO + FLIP + FSM VISUAL
# =================================================
func move() -> void:
	super()

	# Flip horizontal baseado no movimento
	if movement_direction.x < 0:
		sprite.flip_h = true
		facing_direction = -1.0
	elif movement_direction.x > 0:
		sprite.flip_h = false
		facing_direction = 1.0

	# FSM visual (fora do ataque)
	if not is_attacking:
		if velocity.is_zero_approx():
			_play_anim("idle")
		else:
			_play_anim("walk")
	else:
		_update_attack_animation()

# =================================================
# ATAQUE (CHAMADO PELO AttackController)
# =================================================
func _on_primary_attack_started() -> void:
	if is_attacking:
		return

	is_attacking = true
	go_to_attack_state()

	var attack_anim: String
	if velocity.is_zero_approx():
		attack_anim = "attack"
	else:
		attack_anim = "walk_attack"

	_play_anim(attack_anim)

	var duration := anim.get_animation(attack_anim).length
	await get_tree().create_timer(duration, false).timeout

	is_attacking = false

	if status == PlayerState.dead:
		return

	if velocity.is_zero_approx():
		go_to_idle_state()
	else:
		go_to_walk_state()

# =================================================
# CONTINUIDADE attack <-> walk_attack
# =================================================
func _update_attack_animation() -> void:
	var desired_anim: String
	if velocity.is_zero_approx():
		desired_anim = "attack"
	else:
		desired_anim = "walk_attack"

	if desired_anim == current_anim:
		return

	var t := anim.current_animation_position
	anim.play(desired_anim)
	anim.seek(t, true)
	current_anim = desired_anim

# =================================================
# PLAY SEGURO (NÃO REINICIA)
# =================================================
func _play_anim(anim_name: String) -> void:
	if current_anim == anim_name:
		return

	anim.play(anim_name)
	current_anim = anim_name

# =================================================
# HOOKS OBRIGATÓRIOS DO PlayerBase
# =================================================
func _on_death_animation() -> void:
	_play_anim("idle")  # Substitua por "die" quando a animação estiver pronta

func _disable_collision() -> void:
	# set_deferred evita erro de physics lock
	hurtbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)

func flash_red() -> void:
	for i in range(2):
		sprite.modulate = Color(1, 0, 0)
		await get_tree().create_timer(0.1, false).timeout
		sprite.modulate = Color.WHITE
