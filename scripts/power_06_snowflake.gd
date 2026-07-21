extends BasePower


# -------------------------------------------------
# NODES
# -------------------------------------------------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


# =================================================
# TARGETING
# =================================================
@export_group("Targeting")
@export var screen_edge_tolerance: float = 0.0
## Margem de busca de inimigos além da tela.

@export_group("Fallback Position")
@export var fallback_distance_min: float = 100.0
@export var fallback_distance_max: float = 150.0
@export var fallback_vertical_range: float = 50.0

@export_group("Visual Effects")
@export var fade_out_time: float = 0.15


# -------------------------------------------------
# REFERÊNCIAS
# -------------------------------------------------
var player_ref: Node2D = null
var collision: CollisionShape2D = null
var is_fading_out: bool = false


# =================================================
# DANO CONTÍNUO
# =================================================
var enemies_in_contact: Dictionary = {}


# -------------------------------------------------
# READY
# -------------------------------------------------
func _ready() -> void:
	super._ready()
	player_ref = get_tree().get_first_node_in_group("Player")
	
	# Conectar sinais de colisão
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	# Invisível até estar na posição correta
	anim.modulate.a = 0.0
	
	await get_tree().process_frame
	
	# 1. Escolher posição
	_choose_spawn_position()
	
	# 2. Aplicar scale
	if attack_data:
		anim.scale = Vector2(attack_data.attack_scale, attack_data.attack_scale)
	
	# 3. Tornar visível
	anim.modulate.a = 1.0
	
	# 4. Tocar animação
	anim.play("default")
	
	# 5. Som inicial (raio)
	if attack_data and attack_data.attack_sound:
		AudioManagerGlobal.play_sound_2d(
			attack_data.attack_sound,
			global_position,
			attack_data.attack_sound_volume_db,
			attack_data.attack_sound_pitch_scale
		)
	
	# 6. Aguardar activation_delay
	if attack_data and attack_data.activation_delay > 0:
		await get_tree().create_timer(attack_data.activation_delay, false).timeout
	
	# 7. Criar collision + som secundário
	_create_collision()
	
	if attack_data and attack_data.secondary_sound:
		AudioManagerGlobal.play_sound_2d(
			attack_data.secondary_sound,
			global_position,
			attack_data.secondary_sound_volume_db,
			attack_data.secondary_sound_pitch_scale
		)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_cleanup_freed_enemies()


# =================================================
# TARGETING
# =================================================
func _choose_spawn_position() -> void:
	var target = find_random_enemy_on_screen(screen_edge_tolerance)
	
	if target:
		global_position = target.global_position
	else:
		_apply_fallback_position()


func _apply_fallback_position() -> void:
	if not is_instance_valid(player_ref):
		return
	
	var distance = randf_range(fallback_distance_min, fallback_distance_max)
	var vertical = randf_range(-fallback_vertical_range, fallback_vertical_range)
	
	var direction = 1
	if is_instance_valid(player_ref) and player_ref.has_method("get") and player_ref.get("velocity"):
		direction = 1 if player_ref.velocity.x >= 0 else -1
	
	global_position = player_ref.global_position + Vector2(
		direction * distance,
		vertical
	)


# =================================================
# COLLISION
# =================================================
func _create_collision() -> void:
	collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	
	if attack_data:
		shape.radius = attack_data.collision_area_size / 2.0
	else:
		shape.radius = 25.0
	
	collision.shape = shape
	collision.scale = anim.scale
	collision.position = Vector2.ZERO
	
	add_child(collision)


# =================================================
# COLISÃO - DANO CONTÍNUO
# =================================================
func _on_area_entered(area: Area2D) -> void:
	if is_fading_out:
		return
	if not area.is_in_group("EnemyHurtbox"):
		return
	
	var enemy := area.get_parent()
	if enemy == null or not is_instance_valid(enemy):
		return
	
	super._on_area_entered(area)
	_start_continuous_damage(enemy, area)


func _start_continuous_damage(enemy: Node, area: Area2D) -> void:
	if enemies_in_contact.has(enemy):
		return
	
	if not is_instance_valid(enemy):
		return
	
	var t := Timer.new()
	t.wait_time = damage_interval
	t.one_shot = false
	
	t.timeout.connect(func():
		if not is_instance_valid(enemy) or not is_instance_valid(area):
			if is_instance_valid(t):
				t.stop()
				t.queue_free()
			return
		
		super._on_area_entered(area)
	)
	
	add_child(t)
	enemies_in_contact[enemy] = t
	t.start()


func _on_area_exited(area: Area2D) -> void:
	if not area.is_in_group("EnemyHurtbox"):
		return
	
	var enemy := area.get_parent()
	if enemy == null:
		return
	
	_stop_continuous_damage(enemy)


func _stop_continuous_damage(enemy: Node) -> void:
	if not enemies_in_contact.has(enemy):
		return
	
	var t = enemies_in_contact.get(enemy)
	if is_instance_valid(t):
		t.stop()
		t.queue_free()
	
	enemies_in_contact.erase(enemy)


# =================================================
# LIMPEZA
# =================================================
func _cleanup_freed_enemies() -> void:
	var keys_to_remove: Array = []
	
	for enemy in enemies_in_contact.keys():
		if not is_instance_valid(enemy):
			keys_to_remove.append(enemy)
	
	for enemy in keys_to_remove:
		var t = enemies_in_contact.get(enemy)
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
		enemies_in_contact.erase(enemy)


func _clear_all_continuous_timers() -> void:
	var all_enemies: Array = []
	for enemy in enemies_in_contact.keys():
		all_enemies.append(enemy)
	
	for enemy in all_enemies:
		if not enemies_in_contact.has(enemy):
			continue
		
		var t = enemies_in_contact.get(enemy)
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
	
	enemies_in_contact.clear()


# =================================================
# FADE OUT
# =================================================
func on_life_time_end() -> void:
	start_fade_out()


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


func _exit_tree() -> void:
	_clear_all_continuous_timers()
