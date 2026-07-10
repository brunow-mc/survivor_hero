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
@export var knockback_decay: float = 168.0
@export var knockback_transfer_ratio: float = 0.55
@export var knockback_retention_after_transfer: float = 0.8
@export var min_knockback_to_transfer: float = 8.0
@export var max_knockback_magnitude: float = 200.0

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
# ITEM DROP SYSTEM
# =================================================
@export_group("Item Drop")
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.05
@export var min_drop_amount: int = 1
@export var max_drop_amount: int = 1
@export var drop_spread_radius: float = 10.0
## Tabela de itens que este inimigo pode dropar (sorteio ponderado por spawn_weight).
## Cada unidade dropada sorteia independentemente da tabela.
@export var drop_table: Array[ItemDropData] = []

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
# BODY CENTER
# Marcador do centro do corpo. A origem da cena fica nos pés
# (para Y-sort), mas o colisor segue no corpo — a navegação
# (direção e distâncias) usa este ponto para que o CORPO siga
# a linha do caminho, e não os pés (senão o colisor raspa em
# paredes acima em corredores estreitos).
# =================================================
var body_center: Node2D = null

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
# AVOIDANCE
# Controla o fluxo assíncrono do sinal velocity_computed.
# _avoidance_pending é true SOMENTE enquanto aguardamos a
# resposta do NavigationServer2D para a velocidade segura.
# Qualquer sistema prioritário (knockback, parada, morte)
# zera essa flag, descartando respostas obsoletas.
# =================================================
var _avoidance_pending: bool = false
var _pending_delta: float = 0.0
var _pending_pos_before: Vector2 = Vector2.ZERO

# =================================================
# READY
# =================================================
func _ready() -> void:
	add_to_group("Enemy")
	life = max_health
	_setup_base()

func _setup_base() -> void:
	# Física (CharacterBody2D)
	max_slides = 6
	
	# Avoidance — conecta o sinal que devolve a velocidade
	# ajustada pelo NavigationServer2D (RVO)
	if navigation_agent:
		navigation_agent.velocity_computed.connect(_on_velocity_computed)
	
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
	
	# Marcador do centro do corpo (fallback: origem da cena)
	body_center = get_node_or_null("BodyCenter")

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
			base_idle_state(delta)
		
		EnemyState.WALK:
			base_walk_state(delta)
		
		EnemyState.DEAD:
			# Garante que nenhum sinal pendente interfere após a morte
			_avoidance_pending = false
			dead_state()
			return  # Não processa movimento de inimigos mortos
	
	# Se o avoidance está aguardando resposta do NavigationServer2D,
	# o movimento será concluído em _on_velocity_computed.
	# Guardamos delta e pos_before para uso lá.
	if _avoidance_pending:
		_pending_delta = delta
		_pending_pos_before = pos_before
		return
	
	_finish_movement(pos_before, delta)

# =================================================
# MOVIMENTO FINAL (chamado diretamente OU via velocity_computed)
# =================================================
func _finish_movement(pos_before: Vector2, delta: float) -> void:
	move_and_slide()
	handle_knockback_transfer()
	_guard_against_position_jump(pos_before, delta)

# =================================================
# CALLBACK DE AVOIDANCE
# Chamado pelo NavigationServer2D com a velocidade segura calculada.
# =================================================
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	# Se a flag foi zerada enquanto aguardávamos (ex: knockback começou),
	# descarta esta resposta — ela se tornou obsoleta.
	if not _avoidance_pending:
		return
	
	# Inimigo morreu enquanto aguardava — não move mais.
	if not is_alive:
		_avoidance_pending = false
		return
	
	_avoidance_pending = false
	velocity = safe_velocity
	_finish_movement(_pending_pos_before, _pending_delta)
	
	#var desired := direction_to_player * move_speed
	#if safe_velocity.distance_to(desired) > 1.0:
	#	print("RVO ajustou: Δ=", (safe_velocity - desired).length(), "px/s")

# =================================================
# PROTEÇÃO CONTRA SALTOS ANÔMALOS DE POSIÇÃO
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
func base_move(delta: float) -> void:
	update_direction()
	
	if knockback != Vector2.ZERO:
		# Knockback tem prioridade absoluta.
		# Cancela avoidance pendente — não queremos desviar enquanto voando.
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
		_avoidance_pending = false
		return
	
	if distance_to_player <= stop_distance:
		can_walk = false
		velocity = Vector2.ZERO
		_avoidance_pending = false
		return
	
	if is_alive:
		can_walk = true
		var desired_velocity: Vector2 = direction_to_player * move_speed
		
		if navigation_agent and navigation_agent.avoidance_enabled:
			# Declara a velocidade desejada ao servidor de navegação.
			# O servidor calcula a velocidade segura (RVO) e devolve
			# via sinal velocity_computed → _on_velocity_computed.
			navigation_agent.set_velocity(desired_velocity)
			_avoidance_pending = true
		else:
			# Avoidance desligado: usa velocidade desejada diretamente.
			velocity = desired_velocity
			_avoidance_pending = false

# =================================================
# DIREÇÃO + ANTI-FLICKER
# =================================================
func update_direction() -> void:
	if not navigation_agent or not player or not is_instance_valid(player):
		return

	if navigation_agent.is_navigation_finished():
		# Navegação concluída: get_next_path_position() retornaria a
		# posição do próprio agente (direção degenerada). Perseguição
		# direta pés-a-pés como guard.
		direction_to_player = (player.global_position - global_position).normalized()
	else:
		# Steering pela ORIGEM (pés), em espaço global.
		# NÃO trocar por steering a partir do BodyCenter: os waypoints
		# do caminho vivem no plano dos pés (navmesh), e medir a
		# direção de um ponto 11px acima injeta um viés (0,+11) em
		# cada trecho — os inimigos passam a se aproximar em arco por
		# baixo (tentado e revertido em jul/2026).
		direction_to_player = (
			navigation_agent.get_next_path_position() - global_position
		).normalized()

	# Distância pés-a-pés: com todas as origens nos pés, é a métrica
	# simétrica (independe da altura de cada inimigo) e coerente com
	# a calibragem histórica de stop_distance / attack_distance.
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
func base_idle_state(delta: float) -> void:
	base_move(delta)
	
	if velocity != Vector2.ZERO:
		go_to_walk_state()
		return
	
	switch_animation(get_animation_for_state())

func base_walk_state(delta: float) -> void:
	base_move(delta)
	
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
		# Alvo no CORPO do player — mesmo frame do steering (que parte
		# do BodyCenter do inimigo). Frames consistentes = linha reta
		# em campo aberto. Alvo nos pés criaria um viés constante de
		# +body_offset para baixo na direção (arco por baixo).
		navigation_agent.target_position = _get_player_chase_position()

func _on_path_timer_timeout() -> void:
	makepath()

# =================================================
# HIT / DEATH
# =================================================
func receive_hit(hit_data: HitData, source_pos: Vector2) -> void:
	if not is_alive:
		return
	
	life -= hit_data.damage
	knockback = (global_position - source_pos).normalized() * hit_data.knockback_force
	knockback = knockback.limit_length(max_knockback_magnitude)
	
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
	_try_spawn_drop_items()

# =================================================
# ITEM DROP SYSTEM
# =================================================
func _try_spawn_drop_items() -> void:
	var random_chance := randf()
	
	if random_chance > drop_chance:
		return
	
	var amount := randi_range(min_drop_amount, max_drop_amount)
	
	for i in range(amount):
		_spawn_single_drop_item(i, amount)

func _spawn_single_drop_item(index: int, total: int) -> void:
	var item_scene := _choose_drop_item()

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
	
	get_tree().current_scene.call_deferred("add_child", item)
	item.global_position = spawn_pos

# =================================================
# ESCOLHA DE ITEM (Weight System)
# =================================================
func _choose_drop_item() -> PackedScene:
	# Sorteio ponderado sobre drop_table — mesma lógica de
	# choose_enemy() no SpawnManager. Slots vazios são ignorados.
	var total_weight: float = 0.0
	for entry in drop_table:
		if not entry or not entry.item_scene:
			continue
		total_weight += entry.spawn_weight

	if total_weight <= 0.0:
		return null

	var random_value := randf() * total_weight
	var cumulative_weight: float = 0.0

	for entry in drop_table:
		if not entry or not entry.item_scene:
			continue
		cumulative_weight += entry.spawn_weight
		if random_value <= cumulative_weight:
			return entry.item_scene

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
	
	var touching_enemies: Array = []
	var collision_normals: Array = []
	
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var other := col.get_collider()
		
		if other and other.is_in_group("Enemy"):
			touching_enemies.append(other)
			collision_normals.append(col.get_normal())
	
	if touching_enemies.is_empty():
		return
	
	var transferred_total: float = knockback.length() * knockback_transfer_ratio
	var share: float = transferred_total / touching_enemies.size()
	
	var transferred_to_anyone: bool = false
	
	for i in range(touching_enemies.size()):
		var other = touching_enemies[i]
		if other.knockback.length() >= share:
			continue
		
		var push_dir: Vector2 = -collision_normals[i]
		other.knockback += push_dir * share
		other.knockback = other.knockback.limit_length(max_knockback_magnitude)
		transferred_to_anyone = true
	
	if transferred_to_anyone:
		knockback *= knockback_retention_after_transfer

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
	pass

func dead_state() -> void:
	pass
