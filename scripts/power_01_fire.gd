extends BasePower

# -------------------------------------------------
# NODES
# -------------------------------------------------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


# -------------------------------------------------
# DADOS ESPECÍFICOS DO FIRE
# -------------------------------------------------
var speed: float = 0.0
var direction: int = 1  # 1 = direita, -1 = esquerda


# -------------------------------------------------
# CONTROLE DE HITS
# -------------------------------------------------
var max_hits: int = 1
var hits_done: int = 0


# -------------------------------------------------
# FADE OUT
# -------------------------------------------------
@export var fade_out_time: float = 0.12
var is_fading_out: bool = false


# -------------------------------------------------
# CICLO DE VIDA
# -------------------------------------------------
func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_fading_out:
		return

	# CORRIGIDO v1.1.8: Movimento com direction correto
	# Vetor base usa direction (1=direita, -1=esquerda)
	# Depois rotaciona pelo ângulo do leque
	position += Vector2(direction, 0).rotated(rotation) * speed * delta


# -------------------------------------------------
# COLISÃO
# -------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	if is_fading_out:
		return

	if not area.is_in_group("EnemyHurtbox"):
		return

	# aplica dano respeitando damage_interval
	super._on_area_entered(area)

	hits_done += 1

	if max_hits != -1 and hits_done >= max_hits:
		start_fade_out()


# -------------------------
# FIM DE VIDA
# -------------------------
func on_life_time_end() -> void:
	start_fade_out()


# -------------------------
# FADE OUT
# -------------------------
func start_fade_out() -> void:
	if is_fading_out:
		return

	is_fading_out = true

	set_deferred("monitoring", false)

	var tween := create_tween()

	tween.tween_property(
		anim,
		"modulate:a",
		0.0,
		fade_out_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(queue_free)


# -------------------------
# SETTERS
# -------------------------
func set_power_direction(player_direction: int) -> void:
	direction = player_direction
	anim.flip_h = direction < 0


func set_attack_data(data: AttackData) -> void:
	super.set_attack_data(data)
	# v1.2.6: Aplicar projectile_speed_multiplier
	speed = data.speed * PowerUpStatsGlobal.projectile_speed_multiplier
	max_hits = data.max_hits


# MODIFICADO v1.1.8: Define rotação visual
# Chamado por attack_controller quando projectile_count > 1
func set_projectile_index(index: int, total: int) -> void:
	if total == 1:
		rotation = 0.0
		return
	
	# Busca ângulo de dispersão do attack_data
	var spread_angle = 30.0  # Valor padrão
	if attack_data:
		spread_angle = attack_data.projectile_angle_spread
	
	# Calcula todos os ângulos do leque
	var angles = calculate_projectile_spread_angles(total, spread_angle)
	
	# Pega o ângulo correspondente a este índice
	if index < angles.size():
		var angle_degrees = angles[index]
		
		# CORRIGIDO v1.1.8: Rotação visual
		rotation = deg_to_rad(angle_degrees)
		# Para esquerda, inverte visualmente (flip_h já espelha horizontalmente)
		if direction < 0:
			rotation = -rotation
