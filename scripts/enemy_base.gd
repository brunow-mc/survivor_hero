extends CharacterBody2D
class_name EnemyBase

# =================================================
# ESTADOS
# =================================================
enum EnemyState {
	IDLE,
	WALK,
	DEAD
}

# =================================================
# CONFIGURAÇÕES GERAIS
# =================================================
@export_group("Stats")
@export var max_health: float = 10.0
@export var move_speed: float = 25.0
@export var damage_per_tick: float = 1.0
@export var damage_interval: float = 0.1

# =================================================
# DISTÂNCIAS DE COMPORTAMENTO
# =================================================
@export_group("Distances")
@export var stop_distance: float = 15.0
@export var attack_distance: float = 50.0

# =================================================
# KNOCKBACK
# =================================================
@export_group("Knockback")
@export var knockback_decay: float = 2.8
@export var knockback_transfer_ratio: float = 0.55
@export var min_knockback_to_transfer: float = 8.0

# =================================================
# PATHFINDING
# =================================================
@export_group("Pathfinding")
@export var path_recalc_interval: float = 0.5

# =================================================
# VISUAL
# =================================================
@export_group("Visual")
@export var flip_deadzone: float = 0.15

# =================================================
# ANIMAÇÕES (CONFIGURÁVEIS)
# =================================================
@export_group("Animations")
@export var idle_anim: String = "idle"
@export var walk_anim: String = "walk"
@export var attack_anim: String = "attack"
@export var walk_attack_anim: String = "walk_attack"

# =================================================
# ITEM DROP SYSTEM (NOVO!)
# =================================================
@export_group("Item Drop")
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.05  # 5% por padrão
@export var min_drop_amount: int = 1
@export var max_drop_amount: int = 1
@export var drop_spread_radius: float = 20.0  # Raio de espalhamento dos items

# =================================================
# VISUAL EFFECTS
# =================================================
@export_group("Visual Effects")
@export var flash_count: int = 3
@export var flash_duration: float = 0.09
@export var flash_color: Color = Color.RED

# =================================================
# ESTADO
# =================================================
var status: EnemyState = EnemyState.IDLE
var life: float = 0.0
var is_alive: bool = true
var can_walk: bool = true
var facing_right: bool = true

# =================================================
# NODES (configurados por classes filhas)
# =================================================
var navigation_agent: NavigationAgent2D
var player: CharacterBody2D
var anim: AnimatedSprite2D
var hitbox: Area2D

# =================================================
# DAMAGE TO PLAYER
# =================================================
var player_in_contact: bool = false
var damage_timer: Timer

# =================================================
# PATH TIMER
# =================================================
var path_timer: Timer

# =================================================
# MOVEMENT
# =================================================
var knockback: Vector2 = Vector2.ZERO
var direction_to_player: Vector2 = Vector2.ZERO
var distance_to_player: float = 0.0

# =================================================
# ANIMATION CONTROL
# =================================================
var next_frame: int = 0

# =================================================
# READY
# =================================================
func _ready() -> void:
	add_to_group("Enemy")
	life = max_health
	_setup_base()

func _setup_base() -> void:
	# Path timer
	path_timer = Timer.new()
	path_timer.wait_time = path_recalc_interval
	path_timer.timeout.connect(_on_path_timer_timeout)
	add_child(path_timer)
	path_timer.start()
	
	# Damage timer
	damage_timer = Timer.new()
	damage_timer.wait_time = damage_interval
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	add_child(damage_timer)
	
	# Busca player
	player = get_tree().get_first_node_in_group("Player")
	
	makepath()

# =================================================
# LOOP PRINCIPAL (CENTRALIZADO)
# =================================================
func _physics_process(delta: float) -> void:
	var pos_before: Vector2 = global_position
	
	match status:
		EnemyState.IDLE:
			base_idle_state()
		
		EnemyState.WALK:
			base_walk_state()
		
		EnemyState.DEAD:
			dead_state()
	
	move_and_slide()
	handle_knockback_transfer()
	
	_guard_against_position_jump(pos_before, delta)

# =================================================
# PROTEÇÃO CONTRA SALTOS ANÔMALOS DE POSIÇÃO
# (correção de overlap do move_and_slide)
# =================================================
func _guard_against_position_jump(pos_before: Vector2, delta: float) -> void:
	var actual_delta: Vector2 = global_position - pos_before
	var displacement: float = actual_delta.length()
	var expected: float = velocity.length() * delta
	var max_allowed: float = expected * 3.0
	if max_allowed < 2.0:
		max_allowed = 2.0
	
	if displacement > max_allowed:
		global_position = pos_before + actual_delta.normalized() * max_allowed

# =================================================
# MOVIMENTO BASE
# =================================================
func base_move() -> void:
	update_direction()
	
	if knockback != Vector2.ZERO:
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, knockback_decay)
		return
	
	if distance_to_player <= stop_distance:
		can_walk = false
		velocity = Vector2.ZERO
	elif is_alive:
		can_walk = true
		velocity = direction_to_player * move_speed

# =================================================
# DIREÇÃO + ANTI-FLICKER
# =================================================
func update_direction() -> void:
	if not navigation_agent or not player or not is_instance_valid(player):
		return
	
	direction_to_player = to_local(
		navigation_agent.get_next_path_position()
	).normalized()
	
	distance_to_player = global_position.distance_to(player.global_position)
	
	if abs(direction_to_player.x) > flip_deadzone:
		facing_right = direction_to_player.x > 0
	
	if anim:
		anim.flip_h = not facing_right

# =================================================
# SISTEMA DE ANIMAÇÃO BASE
# =================================================
func get_animation_for_state() -> String:
	var is_attacking := distance_to_player <= attack_distance
	
	match status:
		EnemyState.IDLE:
			return attack_anim if is_attacking else idle_anim
		EnemyState.WALK:
			return walk_attack_anim if is_attacking else walk_anim
		_:
			return idle_anim

func switch_animation(new_anim: String) -> void:
	if not anim or anim.animation == new_anim:
		return
	
	next_frame = anim.frame + 1
	anim.play(new_anim)
	
	if next_frame >= anim.sprite_frames.get_frame_count(new_anim):
		next_frame = 0
	
	anim.frame = next_frame

# =================================================
# STATES BASE
# =================================================
func base_idle_state() -> void:
	base_move()
	
	if velocity != Vector2.ZERO:
		go_to_walk_state()
		return
	
	switch_animation(get_animation_for_state())

func base_walk_state() -> void:
	base_move()
	
	if velocity == Vector2.ZERO:
		go_to_idle_state()
		return
	
	switch_animation(get_animation_for_state())

func go_to_idle_state() -> void:
	status = EnemyState.IDLE

func go_to_walk_state() -> void:
	status = EnemyState.WALK

func go_to_dead_state() -> void:
	status = EnemyState.DEAD

# =================================================
# PATHFINDING
# =================================================
func makepath() -> void:
	if navigation_agent and player and is_instance_valid(player):
		navigation_agent.target_position = player.global_position

func _on_path_timer_timeout() -> void:
	makepath()

# =================================================
# HIT / DEATH - MODIFICADO v1.1.12
# =================================================
func receive_hit(hit_data: HitData, source_pos: Vector2) -> void:
	if not is_alive:
		return
	
	life -= hit_data.damage
	knockback = (global_position - source_pos).normalized() * hit_data.knockback_force
	
	if life <= 0:
		die(hit_data)
	else:
		flash_red()
		if hit_data.hit_sound:
			AudioManagerGlobal.play_sound_2d(
				hit_data.hit_sound,
				global_position,
				hit_data.hit_sound_volume_db,
				hit_data.hit_sound_pitch_scale
			)

func die(hit_data: HitData) -> void:
	if not is_alive:
		return
	
	is_alive = false
	can_walk = false
	go_to_dead_state()
	
	if hit_data.death_sound:
		AudioManagerGlobal.play_sound_2d(
			hit_data.death_sound,
			global_position,
			hit_data.death_sound_volume_db,
			hit_data.death_sound_pitch_scale
		)
	
	_spawn_death_effect()
	
	# NOVO: Sistema de drop de items
	_try_spawn_drop_items()

# =================================================
# ITEM DROP SYSTEM (NOVO!)
# =================================================
func _try_spawn_drop_items() -> void:
	# Verifica chance de drop
	var random_chance := randf()
	
	if random_chance > drop_chance:
		return  # Não dropou nada
	
	# Determina quantidade de items a dropar
	var amount := randi_range(min_drop_amount, max_drop_amount)
	
	# Spawna os items
	for i in range(amount):
		_spawn_single_drop_item(i, amount)

func _spawn_single_drop_item(index: int, total: int) -> void:
	var item_scene := _get_drop_item_scene()
	
	if not item_scene:
		return
	
	var item := item_scene.instantiate()
	
	var spawn_pos := global_position
	
	if total > 1:
		var angle := (TAU / total) * index + randf_range(-0.3, 0.3)
		var distance := randf_range(drop_spread_radius * 0.5, drop_spread_radius)
		spawn_pos += Vector2(cos(angle), sin(angle)) * distance
	else:
		spawn_pos += Vector2(randf_range(-10, 10), randf_range(-10, 10))
	
	# CORREÇÃO: Usa call_deferred para adicionar DEPOIS do frame de física
	get_tree().current_scene.call_deferred("add_child", item)
	item.global_position = spawn_pos

# =================================================
# MÉTODO VIRTUAL: CLASSES FILHAS DEFINEM O ITEM
# =================================================
func _get_drop_item_scene() -> PackedScene:
	# Classes filhas sobrescrevem isso para definir qual item dropar
	# Exemplo no Gator: return preload("res://entities/items/xp_item_01.tscn")
	return null

# =================================================
# FLASH DAMAGE BASE
# =================================================
func flash_red() -> void:
	if not anim:
		return
	
	for i in range(flash_count):
		anim.modulate = flash_color
		await get_tree().create_timer(flash_duration, false).timeout
		anim.modulate = Color.WHITE
		await get_tree().create_timer(flash_duration, false).timeout

# =================================================
# KNOCKBACK TRANSFER BASE
# =================================================
func handle_knockback_transfer() -> void:
	if knockback.length() < min_knockback_to_transfer:
		return
	
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var other := col.get_collider()
		
		if other and other.is_in_group("Enemy"):
			if other.knockback != Vector2.ZERO:
				continue
			
			var push_dir := -col.get_normal()
			var transferred := knockback.length() * knockback_transfer_ratio
			
			other.knockback = push_dir * transferred
			knockback *= 0.8
			return

# =================================================
# DAMAGE TO PLAYER
# =================================================
func _on_damage_timer_timeout() -> void:
	if player_in_contact and player and is_instance_valid(player):
		player.take_damage(damage_per_tick)

# =================================================
# MÉTODOS VIRTUAIS
# =================================================
func _spawn_death_effect() -> void:
	pass  # Implementar em classes filhas

func dead_state() -> void:
	pass  # Implementar em classes filhas (ex: queue_free())
