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
# CONTEXT STEERING
# Direção de movimento por "context map": amostra N fatias ao redor,
# pontua cada uma por INTERESSE (rumo ao player) e PERIGO (por OCUPAÇÃO
# ANGULAR — cada vizinho bloqueia só o arco que seu corpo realmente ocupa)
# e escolhe a fatia mais livre e mais alinhada ao player, em velocidade
# cheia. Vãos maiores que um corpo ficam livres (o inimigo os atravessa).
# Substitui o RVO enquanto ligado (ver base_move) e traz separação
# embutida. Não usa colisor.
# =================================================
@export_group("Context Steering")
## Liga o context steering (e bypassa o RVO enquanto ligado).
@export var steering_enabled: bool = true
## Nº de fatias amostradas ao redor (resolução angular; 8 = 45°).
@export var steer_slice_count: int = 8
## Raio em que vizinhos entram no cálculo (px). ~1.5× o diâmetro do corpo.
@export var steer_detect_radius: float = 32.0
## Folga que cada VIZINHO bloqueia (px): ~ corpo do vizinho + corpo próprio.
## Define a meia-largura angular bloqueada = asin(enemy_clearance / distância).
@export var steer_enemy_clearance: float = 22.0
## Distância de PAREDE (Solução B): alcance do raycast que marca uma fatia como
## bloqueada por parede (layer 1). Independente do espaçamento entre inimigos.
## Maior = mantém mais distância das paredes. 0 = steering ignora paredes.
@export var steer_wall_clearance: float = 16.0
## "Aguardar": se nem a melhor fatia livre aponta razoavelmente para o player
## (interesse abaixo disto), o inimigo está cercado sem acesso — segura a
## posição em vez de circular/forçar. Interesse = cos do ângulo até o rumo do
## player (0.3 ≈ 72°). 0 desliga o "aguardar" (volta a sempre circular).
@export var steer_block_min_interest: float = 0.3
## Staggering: recomputa a direção do steering só 1 a cada N frames físicos
## (escalonado por inimigo, para não computarem todos no mesmo frame).
## 1 = recomputa todo frame (sem staggering). Maior = mais barato, com rumo
## levemente mais defasado. O inimigo continua se MOVENDO todo frame.
@export var steer_update_interval: int = 4

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
## BodyCenter do player, cacheado (fallback: origem/pés). Alvo da perseguição
## e referência de distance_to_player (corpo do inimigo ↔ corpo do player).
var player_body_center: Node2D = null
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
# NAVIGATION ANCHOR
# Pai do NavigationAgent2D (o BodyCenter). É a posição que o
# agente navega — ver comentário em _setup_base().
# =================================================
var _nav_anchor: Node2D = null

# Marcador BodyCenter (= centro do CollisionShape2D físico). Referência
# canônica de "onde está o corpo" — ver get_body_center_position().
var body_center: Node2D = null

# Staggering do steering: recomputa a direção 1 a cada steer_update_interval
# frames (escalonado por _steer_stagger, sorteado por instância), reutilizando
# _steer_cached_dir nos frames intermediários. _steer_has_cached força o
# primeiro cálculo logo no início.
var _steer_cached_dir: Vector2 = Vector2.ZERO
var _steer_has_cached: bool = false
var _steer_stagger: int = 0

# Perigo de parede (Solução B): raycast por fatia contra a layer 1, cacheado
# por posição — paredes são estáticas, então só recomputa ao mover o
# suficiente (barato para hordas com muitos inimigos parados/lentos).
var _wall_danger: PackedFloat32Array = PackedFloat32Array()
var _wall_danger_pos: Vector2 = Vector2.ZERO
var _wall_danger_slices: int = 0
var _wall_danger_valid: bool = false

# Grid espacial de inimigos: bucketiza as posições em células de GRID_CELL_SIZE,
# reconstruído 1×/frame físico e compartilhado por todas as instâncias. Cada
# inimigo consulta só as células que cobrem seu detect_radius (O(vizinhos)) em
# vez de varrer todos os inimigos (O(N²) no total). A reconstrução faz o único
# get_nodes_in_group por frame (substitui o cache de lista anterior).
const GRID_CELL_SIZE: float = 32.0
static var _grid: Dictionary = {}
static var _grid_frame: int = -1

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

	# Marcador do centro do corpo (cacheado uma vez). Degrada graciosamente:
	# se a cena não tiver BodyCenter, get_body_center_position() cai no
	# _nav_anchor e depois na origem (pés).
	body_center = get_node_or_null("BodyCenter") as Node2D

	# Avoidance — conecta o sinal que devolve a velocidade
	# ajustada pelo NavigationServer2D (RVO)
	if navigation_agent:
		navigation_agent.velocity_computed.connect(_on_velocity_computed)
		# Âncora de navegação: o NavigationAgent2D navega a posição do
		# PAI dele. Com o agente reparentado sob o BodyCenter, o ponto
		# navegante é o centro do colisor (não os pés/origem) — caminho,
		# waypoints e RVO todos no mesmo referencial do corpo.
		_nav_anchor = navigation_agent.get_parent() as Node2D
	
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
	
	# Busca player e cacheia seu BodyCenter (fallback tratado nos consumidores).
	player = get_tree().get_first_node_in_group("Player")
	if player:
		player_body_center = player.get_node_or_null("BodyCenter")

	# Escalona o steering desta instância (staggering) para os inimigos não
	# recomputarem a direção todos no mesmo frame.
	_steer_stagger = randi() % max(1, steer_update_interval)

	_validate_scene_setup()

	makepath()

# =================================================
# GUARDS DE INICIALIZAÇÃO
# Erros de montagem de cena degradam graciosamente (nunca crasham), mas isso
# os torna invisíveis em jogo. Estes avisos fecham o contrato "degrada E
# avisa". Rodam UMA VEZ POR CENA de inimigo (guard estático), não por
# instância — senão uma horda geraria centenas de avisos idênticos.
# =================================================
static var _warned_enemy_scenes: Dictionary = {}

func _validate_scene_setup() -> void:
	var scene_key: String = scene_file_path
	if scene_key == "" or _warned_enemy_scenes.has(scene_key):
		return
	_warned_enemy_scenes[scene_key] = true

	var who: String = scene_key.get_file()

	# 1. Hurtbox sem o grupo → o inimigo fica INVULNERÁVEL (todo power checa
	#    is_in_group("EnemyHurtbox") antes de aplicar dano).
	var hurtbox: Node = get_node_or_null("Hurtbox")
	if hurtbox == null:
		push_warning("EnemyBase [%s]: nó 'Hurtbox' não encontrado — este inimigo NÃO poderá receber dano dos ataques." % who)
	elif not hurtbox.is_in_group("EnemyHurtbox"):
		push_warning("EnemyBase [%s]: Hurtbox fora do grupo 'EnemyHurtbox' — este inimigo NÃO poderá receber dano dos ataques." % who)

	# 2. BodyCenter ausente → mira dos ataques, direção do knockback e
	#    navegação voltam ao referencial dos PÉS.
	if body_center == null:
		push_warning("EnemyBase [%s]: marcador 'BodyCenter' ausente — mira dos ataques, knockback e navegação vão usar os PÉS (viés para baixo)." % who)

	# 3. NavigationAgent2D fora do BodyCenter → o agente navega a raiz (pés)
	#    em vez do corpo, reintroduzindo o bug do caminho em "arco".
	if navigation_agent and body_center and navigation_agent.get_parent() != body_center:
		push_warning("EnemyBase [%s]: NavigationAgent2D não é filho de 'BodyCenter' — a navegação vai operar no referencial dos PÉS e os caminhos ficarão enviesados." % who)

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
		# Context steering: escolhe a direção mais livre rumo ao player,
		# preservando a velocidade (ver _steer_direction).
		var move_dir: Vector2 = direction_to_player
		if steering_enabled:
			# Staggering: recomputa o steering só 1 a cada steer_update_interval
			# frames (escalonado por _steer_stagger); nos demais reutiliza o
			# rumo em cache. O inimigo continua se movendo todo frame.
			var interval: int = max(1, steer_update_interval)
			if not _steer_has_cached or (Engine.get_physics_frames() + _steer_stagger) % interval == 0:
				_steer_cached_dir = _steer_direction(direction_to_player)
				_steer_has_cached = true
			move_dir = _steer_cached_dir
		var desired_velocity: Vector2 = move_dir * move_speed

		if steering_enabled:
			# Steering no comando: velocidade direta, sem passar pelo RVO.
			# move_dir == ZERO → estado "aguardar" (cercado sem acesso, ou
			# navegação concluída): segura a posição, como a parada normal.
			# A animação segue a regra atual (velocity ZERO → IDLE; ataque
			# ainda decidido só pela distância de 50px). Nada é alterado nela.
			if move_dir == Vector2.ZERO:
				can_walk = false
				velocity = Vector2.ZERO
			else:
				velocity = desired_velocity
			_avoidance_pending = false
		elif navigation_agent and navigation_agent.avoidance_enabled:
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

	# Direção do PONTO NAVEGANTE (pai do agente = BodyCenter) ao próximo
	# waypoint — o caminho nasce e é seguido no referencial do corpo.
	# Não usar to_local(): a origem da cena está nos pés, fora desse
	# referencial.
	direction_to_player = (
		navigation_agent.get_next_path_position() - _nav_anchor.global_position
	).normalized()

	# Distância BodyCenter-a-BodyCenter (corpo do inimigo ↔ corpo do player):
	# mesmo referencial que a perseguição (makepath mira o BodyCenter do player),
	# para que parada (stop_distance) e animação de ataque (attack_distance)
	# batam com onde os corpos realmente estão. Fallback: origem/pés.
	var enemy_center: Vector2 = _nav_anchor.global_position if _nav_anchor else global_position
	var player_center: Vector2 = player.global_position
	if is_instance_valid(player_body_center):
		player_center = player_body_center.global_position
	distance_to_player = enemy_center.distance_to(player_center)
	
	if abs(direction_to_player.x) > flip_deadzone:
		facing_right = direction_to_player.x > 0
	
	if anim:
		anim.flip_h = not facing_right

# =================================================
# CONTEXT STEERING (context map — perigo por OCUPAÇÃO ANGULAR)
# Dado base_dir (direção desejada, vinda do caminho de navegação), amostra
# steer_slice_count fatias ao redor. Cada vizinho bloqueia apenas o ARCO
# que seu corpo ocupa: meia-largura θ = asin(clearance / distância). Uma
# fatia é "bloqueada" (perigo 1) se cair dentro do arco de ALGUM vizinho;
# senão fica livre (perigo 0). Assim, vãos maiores que um corpo permanecem
# livres e o inimigo os atravessa. Escolhe, entre as fatias livres, a de
# maior interesse (mais alinhada ao player) e anda em velocidade cheia.
# Campo aberto (nada bloqueia) → retorna base_dir (reto e suave).
# Usa só posições dos vizinhos, não o colisor.
# =================================================
func _steer_direction(base_dir: Vector2) -> Vector2:
	if base_dir == Vector2.ZERO or steer_slice_count < 2:
		return base_dir

	var my_pos: Vector2 = global_position

	# Coleta vizinhos dentro do raio: direção (unit) + cosseno da meia-largura
	# angular que o corpo dele bloqueia (cos θ, com θ = asin(clearance/d)).
	# Uma fatia é bloqueada se sdir.dot(dir_vizinho) > cos θ.
	var neigh_dirs: Array[Vector2] = []
	var neigh_cos_theta: Array[float] = []
	_rebuild_grid_if_needed()
	# Consulta só as células que cobrem o steer_detect_radius (não todos os
	# inimigos): O(vizinhos por perto) em vez de O(N).
	var cell_min: Vector2i = _cell_of(my_pos - Vector2(steer_detect_radius, steer_detect_radius))
	var cell_max: Vector2i = _cell_of(my_pos + Vector2(steer_detect_radius, steer_detect_radius))
	for cx in range(cell_min.x, cell_max.x + 1):
		for cy in range(cell_min.y, cell_max.y + 1):
			var cell_key: Vector2i = Vector2i(cx, cy)
			if not _grid.has(cell_key):
				continue
			for e in _grid[cell_key]:
				if e == self or not (e is Node2D):
					continue
				var to_e: Vector2 = (e as Node2D).global_position - my_pos
				var d: float = to_e.length()
				if d < 0.01 or d > steer_detect_radius:
					continue
				var ratio: float = clamp(steer_enemy_clearance / d, 0.0, 1.0)
				neigh_dirs.append(to_e / d)
				neigh_cos_theta.append(sqrt(1.0 - ratio * ratio))   # cos(asin(ratio))

	# Ninguém por perto → segue reto (campo aberto, movimento suave). Sem vizinho
	# não há desvio, logo paredes não importam (base_dir já as evita via caminho).
	if neigh_dirs.is_empty():
		return base_dir

	# Perigo de PAREDE (Solução B): raycast por fatia contra a layer 1, cacheado
	# por posição (paredes são estáticas). Só entra em cena quando há vizinho —
	# ou seja, quando o steering pode desviar para dentro de uma parede.
	var use_walls: bool = steer_wall_clearance > 0.0
	if use_walls:
		var wall_origin: Vector2 = _nav_anchor.global_position if _nav_anchor else global_position
		if not _wall_danger_valid or _wall_danger_slices != steer_slice_count or wall_origin.distance_to(_wall_danger_pos) > 4.0:
			_compute_wall_danger(steer_slice_count, wall_origin)

	# Mapas por fatia: interesse (rumo ao player) e perigo (0 livre / 1 bloqueada
	# por inimigo OU parede). found_danger conta só INIMIGO — é o que decide se
	# vale desviar do rumo base; parede apenas restringe QUAL fatia escolher.
	var slice_dirs: Array[Vector2] = []
	var slice_interest: Array[float] = []
	var slice_danger: Array[float] = []
	var min_danger: float = INF
	var found_danger: bool = false

	for i in steer_slice_count:
		var ang: float = TAU * float(i) / float(steer_slice_count)
		var sdir: Vector2 = Vector2.RIGHT.rotated(ang)
		var interest: float = max(0.0, sdir.dot(base_dir))
		var enemy_danger: float = 0.0
		for j in neigh_dirs.size():
			# Bloqueada se a fatia cai dentro do arco ocupado pelo vizinho.
			if sdir.dot(neigh_dirs[j]) > neigh_cos_theta[j]:
				enemy_danger = 1.0
				break
		var danger: float = enemy_danger
		if use_walls and danger == 0.0 and _wall_danger[i] > 0.5:
			danger = 1.0
		slice_dirs.append(sdir)
		slice_interest.append(interest)
		slice_danger.append(danger)
		if danger < min_danger:
			min_danger = danger
		if enemy_danger > 0.05:
			found_danger = true

	# Nada realmente bloqueia → segue reto.
	if not found_danger:
		return base_dir

	# Entre as fatias MAIS livres (perigo perto do mínimo), pega a de maior
	# interesse — a brecha mais alinhada ao player.
	var best_dir: Vector2 = base_dir
	var best_interest: float = -1.0
	for i in steer_slice_count:
		if slice_danger[i] <= min_danger + 0.05 and slice_interest[i] > best_interest:
			best_interest = slice_interest[i]
			best_dir = slice_dirs[i]

	# "Aguardar": nem a melhor fatia livre aponta razoavelmente para o player
	# → cercado sem acesso. Retorna ZERO para o base_move segurar a posição
	# (mesmo tratamento da parada normal; animação não é tocada aqui).
	if best_interest < steer_block_min_interest:
		return Vector2.ZERO

	return best_dir

# =================================================
# PERIGO DE PAREDE (Solução B)
# Lança um raycast por fatia (direções fixas no mundo) contra a layer 1
# (paredes), a partir da BodyCenter (= centro do colisor físico). Uma fatia
# cujo raio bate em parede dentro de steer_wall_clearance é marcada como
# bloqueada. Resultado cacheado em _wall_danger (por posição), pois paredes
# são estáticas — só é refeito quando o inimigo se move o suficiente.
# =================================================
func _compute_wall_danger(slice_count: int, origin: Vector2) -> void:
	if _wall_danger.size() != slice_count:
		_wall_danger.resize(slice_count)
	var space := get_world_2d().direct_space_state
	for i in slice_count:
		var sdir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(slice_count))
		# Terceiro arg = collision_mask 1 (layer 1 = environment/paredes). O
		# próprio inimigo está na layer 3, então não é atingido.
		var q := PhysicsRayQueryParameters2D.create(origin, origin + sdir * steer_wall_clearance, 1)
		_wall_danger[i] = 1.0 if space.intersect_ray(q) else 0.0
	_wall_danger_pos = origin
	_wall_danger_slices = slice_count
	_wall_danger_valid = true

# Célula do grid que contém uma posição de mundo.
static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / GRID_CELL_SIZE), floori(pos.y / GRID_CELL_SIZE))

# Reconstrói o grid espacial no máximo 1×/frame físico (o primeiro inimigo a
# chamar no frame refaz; os demais reusam). Faz o único get_nodes_in_group por
# frame. Dentro de um frame o grupo é estável (queue_free é diferido).
func _rebuild_grid_if_needed() -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _grid_frame:
		return
	_grid_frame = frame
	_grid.clear()
	for e in get_tree().get_nodes_in_group("Enemy"):
		if not (e is Node2D):
			continue
		var cell: Vector2i = _cell_of((e as Node2D).global_position)
		if _grid.has(cell):
			_grid[cell].append(e)
		else:
			_grid[cell] = [e]

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
		# Alvo no BodyCenter do player (cacheado) — mesmo referencial do ponto
		# navegante e de distance_to_player. Fallback: origem (pés).
		if is_instance_valid(player_body_center):
			navigation_agent.target_position = player_body_center.global_position
		else:
			navigation_agent.target_position = player.global_position

func _on_path_timer_timeout() -> void:
	makepath()

# =================================================
# HIT / DEATH
# =================================================
## Posição global do CENTRO DO CORPO (o BodyCenter, que coincide com o centro
## do CollisionShape2D físico). É a referência canônica para qualquer sistema
## que precise saber "onde está o corpo deste inimigo": direção de knockback,
## mira de ataques que perseguem inimigos, etc. NÃO usar `global_position`
## para isso — a origem da cena são os PÉS, o que injeta um viés para baixo.
## Cadeia de fallback: BodyCenter → _nav_anchor → origem (pés).
func get_body_center_position() -> Vector2:
	if is_instance_valid(body_center):
		return body_center.global_position
	if is_instance_valid(_nav_anchor):
		return _nav_anchor.global_position
	return global_position

func receive_hit(hit_data: HitData, source_pos: Vector2) -> void:
	if not is_alive:
		return
	
	life -= hit_data.damage
	# Direção do empurrão: do centro do projétil ATÉ O CENTRO DO CORPO — o
	# impulso corre através do centro de massa (modelo de sinuca). Usar a
	# origem da cena (pés) injetaria um componente para baixo constante
	# (~13px no gator, ~19px no red gator), porque a colisão é detectada no
	# Hurtbox, bem acima dos pés.
	knockback = (get_body_center_position() - source_pos).normalized() * hit_data.knockback_force
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

	# Base: CENTRO DO CORPO (BodyCenter, via _nav_anchor — que já cai
	# na origem se o inimigo não tiver o marcador). A origem da cena
	# fica nos pés; dropar a partir dela colocava itens dentro de
	# paredes abaixo do inimigo.
	var spawn_pos := _nav_anchor.global_position if _nav_anchor else global_position

	if total > 1:
		# Anel de raio EXATO drop_spread_radius, centrado no corpo.
		# O jitter angular (±0.3 rad) evita o padrão geométrico rígido;
		# o raio não varia — o valor do Inspector é literal.
		var angle := (TAU / total) * index + randf_range(-0.3, 0.3)
		spawn_pos += Vector2(cos(angle), sin(angle)) * drop_spread_radius
	# total == 1: item único nasce exatamente no centro do corpo, sem sorteio.

	# Item nasce no MESMO parent do inimigo (o container Y-sort) —
	# drops no chão participam da sobreposição como qualquer entidade.
	get_parent().call_deferred("add_child", item)
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
