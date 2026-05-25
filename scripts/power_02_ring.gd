extends BasePower


# -------------------------------------------------
# NODES
# -------------------------------------------------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


# =================================================
# CONFIGURAÇÃO DO RING
# =================================================
var speed: float = 0.0
var direction: int = 1


# =================================================
# MOVEMENT - TRAJETÓRIA E CURVATURA
# =================================================
@export_group("Movement")
@export var curve_strength: float = 9.0
## Força da curvatura em direção ao alvo.
## Valores maiores = curva mais agressiva, menores = curva mais suave.

@export var min_travel_distance: float = 16.0
## Distância mínima (em pixels) antes de verificar se passou do alvo.
## Evita detecção prematura quando muito próximo ao spawn.

@export var screen_edge_tolerance: float = 10.0
## Distância em pixels além das bordas da tela onde inimigos ainda podem ser detectados.
## 0 = apenas inimigos visíveis, valores maiores incluem inimigos próximos fora da tela.


# -------------------------------------------------
# TRAJETÓRIA (variáveis internas)
# -------------------------------------------------
var target_position: Vector2
var has_target: bool = false
var has_passed_target: bool = false

var move_direction: Vector2 = Vector2.ZERO
var initial_to_target: Vector2 = Vector2.ZERO
var traveled_distance: float = 0.0


# =================================================
# COMBAT - CONTROLE DE HITS
# =================================================
@export_group("Combat")
@export var max_hits: int = 1
## Número máximo de inimigos que o Ring pode atingir.
## -1 = ilimitado, 1 = apenas um hit.

var hits_done: int = 0


# =================================================
# VISUAL EFFECTS - FADE OUT
# =================================================
@export_group("Visual Effects")
@export var fade_out_time: float = 0.15
## Duração (em segundos) do efeito de fade out ao destruir o projétil.

var is_fading_out: bool = false


# -------------------------------------------------
# READY
# -------------------------------------------------
func _ready() -> void:
	add_to_group("Power")

	await get_tree().process_frame
	define_trajectory()

	move_direction = Vector2(direction, 0).normalized()


# -------------------------------------------------
# PROCESS
# -------------------------------------------------
func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_fading_out:
		return

	if has_target and not has_passed_target:
		move_with_curve(delta)
	else:
		move_forward(delta)


# =================================================
# DEFINIÇÃO DA TRAJETÓRIA - v1.3.16
# =================================================
func define_trajectory() -> void:
	# v1.3.16: Usa find_nearest_enemy_on_screen() do BasePower
	# Usa screen_edge_tolerance para controlar margem de busca
	var enemy := find_nearest_enemy_on_screen(screen_edge_tolerance)
	if not enemy:
		has_target = false
		return

	target_position = enemy.global_position
	initial_to_target = (target_position - global_position).normalized()
	has_target = true
	has_passed_target = false


# =================================================
# MOVIMENTO - CURVATURA E DIREÇÃO
# =================================================
func move_with_curve(delta: float) -> void:
	var to_target := target_position - global_position

	# Verifica se já passou do ponto-alvo
	if to_target.dot(initial_to_target) <= 0.0 and traveled_distance >= min_travel_distance:
		has_passed_target = true
		return

	var target_dir := to_target.normalized()

	# Interpola direção atual para direção do alvo
	move_direction = move_direction.lerp(
		target_dir,
		curve_strength * delta
	).normalized()

	apply_movement(delta)


func move_forward(delta: float) -> void:
	apply_movement(delta)


func apply_movement(delta: float) -> void:
	var displacement := move_direction * speed * delta
	global_position += displacement
	traveled_distance += displacement.length()


# =================================================
# COLISÃO
# =================================================
func _on_area_entered(area: Area2D) -> void:
	if is_fading_out:
		return
	if not area.is_in_group("EnemyHurtbox"):
		return

	super._on_area_entered(area)

	hits_done += 1

	# Após primeiro hit, nunca mais curva
	if hits_done == 1:
		has_passed_target = true
		has_target = false

	if max_hits != -1 and hits_done >= max_hits:
		start_fade_out()


# =================================================
# FIM DE VIDA
# =================================================
func on_life_time_end() -> void:
	start_fade_out()


# =================================================
# FADE OUT
# =================================================
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


# =================================================
# SETTERS
# =================================================
func set_power_direction(player_direction: int) -> void:
	direction = player_direction
	anim.flip_h = direction < 0


func set_attack_data(data: AttackData) -> void:
	super.set_attack_data(data)
	# v1.2.6: Aplicar projectile_speed_multiplier
	speed = data.speed * PowerUpStatsGlobal.projectile_speed_multiplier
	max_hits = data.max_hits
