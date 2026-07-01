extends Node

## =================================================
## SPAWN MANAGER (Singleton)
## =================================================
## Sistema de spawn baseado em Vampire Survivors.
## Controla spawning de inimigos com:
## - Budget system (dificuldade crescente)
## - Weight system (frequência de tipos)
## - Limite de inimigos simultâneos
## =================================================

# =================================================
# SINAIS
# =================================================
## Emitido quando dados de debug são atualizados
signal debug_data_updated(data: Dictionary)

# =================================================
# CONFIGURAÇÕES GERAIS
# =================================================
@export_group("Spawn Settings")
## Número máximo de inimigos vivos simultaneamente
@export var max_enemies: int = 100

## Budget inicial por segundo (aumenta com dificuldade)
@export var base_budget_per_second: float = 1.0

## Budget mínimo necessário para INICIAR spawning
## O sistema só spawna quando budget >= minimal_budget
## Deve ser >= ao custo do inimigo mais caro
@export var minimal_budget: float = 3.0

# =================================================
# SPAWN ÁREA RETANGULAR (Baseado na Tela)
# =================================================
@export_group("Spawn Area (Rectangular)")
## Margem MÍNIMA horizontal (esquerda/direita) além da tela
## Inimigos NÃO spawnam mais perto que isso
@export var spawn_margin_min_horizontal: float = 50.0

## Margem MÍNIMA vertical (cima/baixo) além da tela
## Inimigos NÃO spawnam mais perto que isso
@export var spawn_margin_min_vertical: float = 50.0

## Margem MÁXIMA horizontal (esquerda/direita) além da tela
## Inimigos NÃO spawnam mais longe que isso
@export var spawn_margin_max_horizontal: float = 200.0

## Margem MÁXIMA vertical (cima/baixo) além da tela
## Inimigos NÃO spawnam mais longe que isso
@export var spawn_margin_max_vertical: float = 150.0

## Margem extra de segurança no filtro offscreen
@export var offscreen_safety_margin: float = 20.0

# =================================================
# DIFICULDADE
# =================================================
@export_group("Difficulty Scaling")
## Multiplicador de dificuldade por minuto
## 1.0 = sem aumento, 1.5 = +50% por minuto
@export var difficulty_increase_per_minute: float = 0.3

## Dificuldade máxima (plateau)
@export var max_difficulty_multiplier: float = 10.0

# =================================================
# ENEMY DEFINITIONS
# =================================================
@export_group("Enemy Pool")
## Lista de inimigos que podem spawnar
@export var enemy_definitions: Array[EnemySpawnData] = []

# =================================================
# TELEPORT SYSTEM
# =================================================
@export_group("Teleport System")
## Habilitar teleporte de inimigos distantes
@export var teleport_enabled: bool = true

## Distância máxima do player antes de teleportar (px)
## Inimigos além desta distância serão teleportados
@export var max_distance_from_player: float = 350.0

## Intervalo para checar e teleportar inimigos (segundos)
@export var teleport_check_interval: float = 2.0

## Limite de teleports por frame
## Evita processar muitos inimigos de uma vez (performance)
## 0 = sem limite
@export var max_teleports_per_frame: int = 10

# =================================================
# SPAWN VALIDATION
# =================================================
@export_group("Spawn Validation")
## Distância mínima entre inimigos no spawn (px)
## Evita que inimigos spawnem muito próximos uns dos outros
@export var min_distance_between_enemies: float = 48.0

## Distância mínima de paredes (px)
## Verifica se há espaço livre ao redor do ponto (360° completo)
## Usa Physics Shape Query para detectar colisões em área circular
## Valores menores = mais permissivo | Maiores = mais seguro
## Recomendado: 48px (3x tamanho do collider do inimigo)
@export var min_distance_from_walls: float = 32.0

# =================================================
# GRID SAMPLING
# =================================================
@export_group("Grid Sampling")
## Espaçamento entre pontos da grade (pixels)
## Menor = mais preciso e pesado | Maior = mais leve e menos preciso
@export var grid_sample_spacing: float = 32.0

## Visualizar grade e clusters (debug visual)
@export var debug_draw_enabled: bool = false

# =================================================
# DEBUG
# =================================================
@export_group("Debug")
## Mostrar mensagens de debug no console
@export var debug_enabled: bool = false

## Mostrar avisos quando não encontrar posição válida
@export var show_spawn_warnings: bool = true

# =================================================
# ESTADO INTERNO
# =================================================
var spawn_budget: float = 0.0
var game_time: float = 0.0
var difficulty_multiplier: float = 1.0
var is_spawning_enabled: bool = false

## Delay inicial antes do primeiro spawn (segundos)
## Garante que sistema de navegação está inicializado
var initial_spawn_delay: float = 0.5
var time_since_start: float = 0.0

# DEBUG: Estatísticas
var total_spawn_attempts: int = 0
var failed_spawn_attempts: int = 0

# TELEPORT: Controle e estatísticas
var teleport_timer: float = 0.0
var total_teleports: int = 0

# GRID SAMPLING: Última varredura (para debug visual)
var last_scanned_clusters: Array = []

# TELEPORT: Cache de posições pré-validadas (ABORDAGEM 1)
# Preparado 1x por ciclo, consumido durante teleports
var safe_teleport_positions: Array[Vector2] = []

# PERFORMANCE: shape reutilizado em is_safe_from_walls
var _wall_check_circle: CircleShape2D = CircleShape2D.new()

# =================================================
# REFERÊNCIAS
# =================================================
var player: Node2D = null
var current_scene: Node = null

# =================================================
# READY
# =================================================
func _ready() -> void:
	# Aguarda a cena carregar completamente
	await get_tree().process_frame
	set_process(false)  # Desativado até start_spawning() ser chamado

# =================================================
# INICIALIZAÇÃO
# =================================================
func start_spawning() -> void:
	"""
	Inicia o sistema de spawn.
	Deve ser chamado quando o jogo começa.
	"""
	# Busca referências
	player = get_tree().get_first_node_in_group("Player")
	current_scene = get_tree().current_scene
	
	if not player:
		push_error("SpawnManager: Player não encontrado!")
		return
	
	if not current_scene:
		push_error("SpawnManager: Current scene não encontrada!")
		return
	
	if enemy_definitions.is_empty():
		push_error("SpawnManager: Nenhum inimigo configurado em enemy_definitions!")
		return
	
	# Reseta estado
	game_time = 0.0
	time_since_start = 0.0
	# Inicia budget em 0.0 e deixa acumular durante o delay inicial
	spawn_budget = 0.0
	difficulty_multiplier = 1.0
	
	# Ativa spawning
	is_spawning_enabled = true
	set_process(true)
	
	print("✅ SpawnManager iniciado!")
	print("   Delay inicial: ", initial_spawn_delay, "s (garante navegação pronta)")

func stop_spawning() -> void:
	"""
	Para o sistema de spawn.
	"""
	is_spawning_enabled = false
	set_process(false)
	print("⏸️ SpawnManager parado!")

# =================================================
# PROCESS (Loop Principal)
# =================================================
func _process(delta: float) -> void:
	if not is_spawning_enabled:
		return
	
	# Atualiza tempo de jogo
	game_time += delta
	time_since_start += delta
	
	# Atualiza dificuldade
	update_difficulty()
	
	# Acumula budget
	accumulate_budget(delta)
	
	# ====================================================
	# DELAY INICIAL: Aguarda navegação estar pronta
	# ====================================================
	if time_since_start < initial_spawn_delay:
		# Ainda no delay inicial
		# Budget acumula mas NÃO spawna
		# Isso garante que sistema de navegação está inicializado
		return
	
	# Teleporta inimigos distantes (se habilitado)
	if teleport_enabled:
		check_and_teleport_distant_enemies(delta)
	
	# Tenta spawnar inimigos (após delay)
	try_spawn_enemies()
	
	# Emite dados para debug visual (se habilitado)
	if debug_draw_enabled and not last_scanned_clusters.is_empty():
		var debug_data: Dictionary = {
			"clusters": last_scanned_clusters,
			"player_position": player.global_position if player else Vector2.ZERO,
			"camera_position": get_camera_position(),
			"margin_min_h": spawn_margin_min_horizontal,
			"margin_min_v": spawn_margin_min_vertical,
			"margin_max_h": spawn_margin_max_horizontal,
			"margin_max_v": spawn_margin_max_vertical
		}
		debug_data_updated.emit(debug_data)

# =================================================
# DIFICULDADE
# =================================================
func update_difficulty() -> void:
	"""
	Aumenta dificuldade com o tempo.
	"""
	var minutes_passed := game_time / 60.0
	difficulty_multiplier = 1.0 + (minutes_passed * difficulty_increase_per_minute)
	difficulty_multiplier = min(difficulty_multiplier, max_difficulty_multiplier)

# =================================================
# BUDGET SYSTEM
# =================================================
func accumulate_budget(delta: float) -> void:
	"""
	Acumula budget baseado em tempo e dificuldade.
	"""
	var budget_gain := base_budget_per_second * difficulty_multiplier * delta
	spawn_budget += budget_gain

# =================================================
# TELEPORT SYSTEM
# =================================================
func check_and_teleport_distant_enemies(delta: float) -> void:
	"""
	Verifica inimigos distantes e teleporta de volta para perto do player.
	USA SISTEMA DE CACHE PRÉ-VALIDADO (Abordagem 1).
	
	Performance: O(1) por teleport ao invés de O(100) tentativas.
	"""
	teleport_timer += delta
	
	# Só executa a cada X segundos
	if teleport_timer < teleport_check_interval:
		return
	
	teleport_timer = 0.0
	
	# Valida player
	if not player or not is_instance_valid(player):
		return
	
	# FASE 0: PREPARA cache de posições seguras (1x por ciclo)
	prepare_safe_teleport_cache()
	
	# Se cache está vazio, não há posições válidas
	if safe_teleport_positions.is_empty():
		if debug_enabled:
			print("⚠️ Cache de teleport vazio - sem posições seguras disponíveis")
		return
	
	# Pega todos os inimigos
	var enemies: Array[Node] = get_tree().get_nodes_in_group("Enemy")
	var enemies_to_teleport: Array = []
	
	# FASE 1: COLETA inimigos que precisam teleportar
	for enemy in enemies:
		if not enemy or not is_instance_valid(enemy):
			continue
		
		# Calcula distância até o player
		var distance_to_player: float = enemy.global_position.distance_to(player.global_position)
		
		# Se está muito longe, marca para teleport
		if distance_to_player > max_distance_from_player:
			enemies_to_teleport.append(enemy)
			
			# LIMITE: Se atingiu max_teleports_per_frame, para
			if max_teleports_per_frame > 0 and enemies_to_teleport.size() >= max_teleports_per_frame:
				break  # Resto fica para próximo check
	
	# Se não há inimigos para teleportar, sai
	if enemies_to_teleport.is_empty():
		return
	
	# FASE 2: ATRIBUI posições do cache (O(1) por inimigo)
	var teleported_count: int = 0
	
	for enemy in enemies_to_teleport:
		# Se cache acabou, para (restantes esperam próximo ciclo)
		if safe_teleport_positions.is_empty():
			if debug_enabled:
				print("⚠️ CACHE ESGOTADO - ", enemies_to_teleport.size() - teleported_count, " inimigos aguardam próximo ciclo\n")
			break
		
		# Pega próxima posição do cache (O(1))
		var pos: Vector2 = safe_teleport_positions.pop_back()
		var pos_before: Vector2 = enemy.global_position
		
		# Teleporta
		enemy.global_position = pos
		total_teleports += 1
		teleported_count += 1

		# v1.4.x Passo 1: zera velocidade residual e força recálculo imediato de rota
		if enemy is CharacterBody2D:
			enemy.velocity = Vector2.ZERO
		if enemy.has_method("makepath"):
			enemy.makepath()
		
		# DEBUG: Log básico de teleport
		if debug_enabled:
			print("📍 TELEPORT #", total_teleports)
			print("├─ Inimigo: ", enemy.name)
			print("├─ Posição ANTES: (", int(pos_before.x), ", ", int(pos_before.y), ")")
			print("├─ Posição DEPOIS: (", int(pos.x), ", ", int(pos.y), ")")
			print("├─ Distância do player: ", int(pos_before.distance_to(player.global_position)), "px")
			print("└─ Cache restante: ", safe_teleport_positions.size(), "\n")
	
	# Debug resumo
	if debug_enabled and teleported_count > 0:
		print("✅ Total teleportado neste ciclo: ", teleported_count, " inimigos\n")

func prepare_safe_teleport_cache() -> void:
	"""
	Prepara cache de posições pré-validadas para teleport.
	Executado 1x por ciclo de teleport (a cada teleport_check_interval).
	
	DEBUG MODE: Registra estatísticas detalhadas.
	"""
	safe_teleport_positions.clear()
	
	# Varre grade e filtra clusters offscreen
	var clusters: Array = scan_navigable_grid()
	var offscreen: Array = filter_offscreen_clusters(clusters)
	
	if offscreen.is_empty():
		if debug_enabled:
			print("⚠️ === CACHE VAZIO ===")
			print("Sem clusters offscreen disponíveis")
		return
	
	# Contadores de debug
	var total_points: int = 0
	var rejected_not_navigable: int = 0
	var rejected_distance: int = 0
	var rejected_enemies: int = 0
	var approved: int = 0
	
	# PRÉ-VALIDA todos os pontos de todos os clusters
	for cluster in offscreen:
		for point in cluster:
			total_points += 1
			
			if debug_enabled:
				# VERSÃO DEBUG: Tracking detalhado
				var validation_result = validate_teleport_position_debug(point)
				
				if validation_result.approved:
					safe_teleport_positions.append(point)
					approved += 1
				else:
					# Contabiliza rejeição
					if not validation_result.navigable:
						rejected_not_navigable += 1
					elif not validation_result.safe_from_walls:
						rejected_distance += 1
					elif not validation_result.safe_from_enemies:
						rejected_enemies += 1
			else:
				# VERSÃO PRODUÇÃO: Simples e rápida
				if validate_teleport_position(point):
					safe_teleport_positions.append(point)
					approved += 1
	
	# Embaralha cache para distribuição aleatória
	safe_teleport_positions.shuffle()
	
	# Debug detalhado
	if debug_enabled:
		print("\n🔄 === PREPARAÇÃO DE CACHE ===")
		print("Total de pontos escaneados: ", total_points)
		print("├─ Rejeitados (não navegável): ", rejected_not_navigable)
		print("├─ Rejeitados (parede próxima < ", min_distance_from_walls, "px): ", rejected_distance)
		print("├─ Rejeitados (perto de inimigos): ", rejected_enemies)
		print("└─ APROVADOS: ", approved)
		print("Cache final: ", safe_teleport_positions.size(), " posições seguras\n")

func validate_teleport_position(pos: Vector2) -> bool:
	"""
	Validação de posição de teleport (PRODUÇÃO).
	Delega para is_valid_enemy_position, que é a mesma usada
	na validação extra do spawn normal.
	"""
	return is_valid_enemy_position(pos)

func validate_teleport_position_debug(pos: Vector2) -> Dictionary:
	"""
	Validação DETALHADA com tracking (apenas para DEBUG).
	Retorna Dictionary com resultado e motivos de rejeição.
	
	Mantém os 3 checks separados (incluindo navegabilidade) para
	fins de diagnóstico/estatística, mesmo que na prática o ponto
	já tenha vindo navegável do scan.
	"""
	var result = {
		"approved": false,
		"navigable": false,
		"safe_from_walls": false,
		"safe_from_enemies": false
	}
	
	# 1. Navegável básico
	result.navigable = is_position_navigable(pos)
	if not result.navigable:
		return result
	
	# 2. Espaço livre ao redor
	result.safe_from_walls = is_safe_from_walls(pos, min_distance_from_walls)
	if not result.safe_from_walls:
		return result
	
	# 3. Seguro de outros inimigos
	result.safe_from_enemies = is_safe_from_other_enemies(pos)
	if not result.safe_from_enemies:
		return result
	
	# Todas validações passaram
	result.approved = true
	return result

func is_safe_from_walls(pos: Vector2, safety_radius: float) -> bool:
	"""
	Verifica se há paredes/colisões dentro de um raio circular ao redor do ponto.
	
	Usa Physics Shape Query para testar área circular completa (360°).
	Detecta paredes em QUALQUER direção, incluindo diagonais.
	
	PERFORMANCE: 1 query otimizada (muito mais rápido que múltiplas checagens).
	
	Args:
		pos: Posição central a testar
		safety_radius: Raio do círculo de segurança (em pixels)
	
	Returns:
		true se área está livre (sem paredes)
		false se detectar parede dentro do raio
	"""
	if not player or not is_instance_valid(player):
		return false

	var space = player.get_world_2d().direct_space_state
	var params = PhysicsShapeQueryParameters2D.new()
	
	# Reutiliza shape cacheado — evita criar objeto novo a cada chamada
	_wall_check_circle.radius = safety_radius
	params.shape = _wall_check_circle
	params.transform = Transform2D(0, pos)
	params.collision_mask = 1  # Layer 1 = TileMap collision (paredes)
	
	# Verifica se há colisão dentro do círculo
	var results = space.intersect_shape(params, 1)
	
	# Se results vazio = sem colisão = seguro
	return results.is_empty()


func try_spawn_enemies() -> void:
	"""
	Tenta spawnar inimigos com sistema de Minimal Budget.
	
	LÓGICA:
	1. Só spawna se budget >= minimal_budget
	2. Quando atinge minimal_budget, spawna MÚLTIPLOS inimigos
	3. Continua spawnando até budget < minimal_budget
	
	EXEMPLO:
	- Budget = 5.0, Minimal = 3.0
	- Spawna Gator (1.0) → Budget = 4.0 (ainda >= 3.0)
	- Spawna Red Gator (3.0) → Budget = 1.0 (< 3.0)
	- Para até acumular novamente
	"""
	
	# ====================================================
	# VERIFICAÇÃO: Só spawna se atingiu minimal_budget
	# ====================================================
	if spawn_budget < minimal_budget:
		return  # Aguarda acumular
	
	# ====================================================
	# SPAWNING LOOP: Gasta budget até ficar < minimal
	# ====================================================
	var spawns_this_frame := 0
	var max_spawns_per_frame := 10  # Limite de segurança
	
	# Continua spawnando enquanto:
	# - Tem budget >= minimal
	# - Pode spawnar mais inimigos
	# - Não excedeu limite de spawns por frame
	while spawn_budget >= minimal_budget and can_spawn_more() and spawns_this_frame < max_spawns_per_frame:
		
		# Escolhe inimigo que CABE no budget atual
		var enemy_data := choose_enemy(spawn_budget)
		
		if not enemy_data:
			# Nenhum inimigo disponível que caiba no budget
			# (Raro: só acontece se todos custam mais que budget atual)
			break
		
		# Encontra posição válida de spawn
		var spawn_pos := find_spawn_position()
		
		if spawn_pos == Vector2.ZERO:
			# Não encontrou posição navegável válida
			# Para de tentar spawnar neste frame
			break
		
		# SPAWNA o inimigo
		spawn_enemy(enemy_data, spawn_pos)
		
		# DESCONTA o custo do budget
		spawn_budget -= enemy_data.spawn_cost
		
		spawns_this_frame += 1
		
		# Debug: Mostra quantos spawns neste burst
		if debug_enabled and spawns_this_frame > 1:
			print("💥 Burst spawn! Total neste frame: ", spawns_this_frame)

func can_spawn_more() -> bool:
	"""
	Verifica se pode spawnar mais inimigos.
	"""
	if not player or not is_instance_valid(player):
		return false
	
	var enemies_alive := get_tree().get_nodes_in_group("Enemy").size()
	return enemies_alive < max_enemies

# =================================================
# ESCOLHA DE INIMIGO (Weight System)
# =================================================
func choose_enemy(available_budget: float = INF) -> EnemySpawnData:
	"""
	Escolhe qual inimigo spawnar baseado em:
	- Tempo de jogo (min/max_game_time)
	- Budget disponível (spawn_cost)
	- Weight (frequência relativa)
	"""
	# Filtra inimigos disponíveis no tempo atual E que cabem no budget
	var available_enemies: Array[EnemySpawnData] = []
	
	for enemy_data in enemy_definitions:
		# Slot vazio no Inspector — ignora
		if not enemy_data:
			continue

		# Verifica tempo
		if game_time < enemy_data.min_game_time or game_time > enemy_data.max_game_time:
			continue
		
		# Verifica budget (NOVO!)
		if enemy_data.spawn_cost > available_budget:
			continue
		
		available_enemies.append(enemy_data)
	
	if available_enemies.is_empty():
		return null
	
	# Weighted random selection
	var total_weight := 0.0
	for enemy_data in available_enemies:
		total_weight += enemy_data.spawn_weight
	
	var random_value := randf() * total_weight
	var cumulative_weight := 0.0
	
	for enemy_data in available_enemies:
		cumulative_weight += enemy_data.spawn_weight
		if random_value <= cumulative_weight:
			return enemy_data
	
	# Fallback (não deveria acontecer)
	return available_enemies[0]

# =================================================
# SPAWN POSITION (Grid Sampling)
# =================================================
func find_spawn_position() -> Vector2:
	"""
	Encontra posição de spawn usando Grid Sampling.
	Varre grade retangular, agrupa clusters navegáveis, filtra offscreen.
	"""
	if not player or not is_instance_valid(player):
		return Vector2.ZERO
	
	total_spawn_attempts += 1
	
	# =========================================
	# GRID SAMPLING: Varredura inteligente
	# =========================================
	
	# 1. Escaneia grade e encontra clusters navegáveis
	var clusters: Array = scan_navigable_grid()
	
	# Armazena para debug visual
	last_scanned_clusters = clusters
	
	# 2. Filtra clusters que estão FORA da tela
	var offscreen_clusters: Array = filter_offscreen_clusters(clusters)
	
	# 3. Se não encontrou clusters offscreen, falha
	if offscreen_clusters.is_empty():
		failed_spawn_attempts += 1
		
		if show_spawn_warnings:
			push_warning("⚠️ SpawnManager: Nenhum cluster offscreen encontrado!")
			push_warning("   Clusters totais: ", clusters.size(), " | Offscreen: 0")
			push_warning("   Possível causa: Player muito perto de paredes ou área navegável pequena")
		
		return Vector2.ZERO
	
	# 4. Escolhe cluster aleatório
	var chosen_cluster: Array = offscreen_clusters.pick_random()
	
	# 5. Sorteia ponto dentro do cluster
	var spawn_pos: Vector2 = chosen_cluster.pick_random()
	
	# 6. Validação extra: distância de paredes e de outros inimigos
	#    (navegabilidade já garantida por scan_navigable_grid)
	if not is_valid_enemy_position(spawn_pos):
		# Tenta outros pontos do mesmo cluster
		for point in chosen_cluster:
			if is_valid_enemy_position(point):
				spawn_pos = point
				break
	
	if debug_enabled:
		print("✅ Grid Sampling: Spawn em ", spawn_pos)
		print("   Clusters: ", clusters.size(), " | Offscreen: ", offscreen_clusters.size())
		print("   Cluster escolhido: ", chosen_cluster.size(), " pontos")
	
	return spawn_pos

func scan_navigable_grid() -> Array:
	"""
	Varre grade em 4 RETÂNGULOS (perímetro de spawn) SEM sobreposição.
	
	OTIMIZAÇÃO v1.1.6:
	- Gera pontos APENAS nas 4 faixas úteis de spawn
	- Norte/Sul: retângulos horizontais completos (cobrem cantos)
	- Oeste/Leste: retângulos verticais centrais (sem cantos - já cobertos por N/S)
	- ZERO desperdício: não gera pontos que seriam descartados
	
	PERFORMANCE:
	- Reduz ~75-85% de pontos gerados em cenários médios/grandes
	- Elimina checagens booleanas (inside_min/inside_max)
	"""
	var navigable_points: Array = []
	var spacing: float = grid_sample_spacing
	
	# Pega viewport e câmera
	var viewport: Viewport = get_viewport()
	if not viewport:
		return []
	
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var camera_pos: Vector2 = get_camera_position()
	
	var half_w: float = viewport_size.x / 2
	var half_h: float = viewport_size.y / 2
	
	# Limites dos retângulos
	var outer_left: float = camera_pos.x - half_w - spawn_margin_max_horizontal
	var outer_right: float = camera_pos.x + half_w + spawn_margin_max_horizontal
	var outer_top: float = camera_pos.y - half_h - spawn_margin_max_vertical
	var outer_bottom: float = camera_pos.y + half_h + spawn_margin_max_vertical
	
	var inner_left: float = camera_pos.x - half_w - spawn_margin_min_horizontal
	var inner_right: float = camera_pos.x + half_w + spawn_margin_min_horizontal
	var inner_top: float = camera_pos.y - half_h - spawn_margin_min_vertical
	var inner_bottom: float = camera_pos.y + half_h + spawn_margin_min_vertical
	
	# =========================================
	# FAIXA NORTE (retângulo horizontal completo)
	# Cobre: Norte, Nordeste, Noroeste
	# =========================================
	var x: float = outer_left
	while x <= outer_right:
		var y: float = outer_top
		while y < inner_top:  # Apenas altura do topo
			if is_position_navigable(Vector2(x, y)):
				navigable_points.append(Vector2(x, y))
			y += spacing
		x += spacing
	
	# =========================================
	# FAIXA SUL (retângulo horizontal completo)
	# Cobre: Sul, Sudeste, Sudoeste
	# =========================================
	x = outer_left
	while x <= outer_right:
		var y: float = inner_bottom
		while y <= outer_bottom:  # Apenas altura da base
			if is_position_navigable(Vector2(x, y)):
				navigable_points.append(Vector2(x, y))
			y += spacing
		x += spacing
	
	# =========================================
	# FAIXA OESTE (retângulo vertical central)
	# Cobre: Oeste (cantos já cobertos por Norte/Sul)
	# =========================================
	x = outer_left
	while x < inner_left:  # Apenas largura esquerda
		var y: float = inner_top
		while y <= inner_bottom:  # Apenas altura central
			if is_position_navigable(Vector2(x, y)):
				navigable_points.append(Vector2(x, y))
			y += spacing
		x += spacing
	
	# =========================================
	# FAIXA LESTE (retângulo vertical central)
	# Cobre: Leste (cantos já cobertos por Norte/Sul)
	# =========================================
	x = inner_right
	while x <= outer_right:  # Apenas largura direita
		var y: float = inner_top
		while y <= inner_bottom:  # Apenas altura central
			if is_position_navigable(Vector2(x, y)):
				navigable_points.append(Vector2(x, y))
			y += spacing
		x += spacing
	
	# Agrupa pontos adjacentes em clusters
	var clusters: Array = group_adjacent_points(navigable_points, spacing)
	
	if debug_enabled:
		print("🔍 Grid Scan OTIMIZADO (4 retângulos): ", navigable_points.size(), " pontos navegáveis")
		print("   Clusters: ", clusters.size())
		print("   Faixas: Norte, Sul, Oeste, Leste (sem sobreposição)")
	
	return clusters

func group_adjacent_points(points: Array, threshold: float) -> Array:
	"""
	Agrupa pontos navegáveis adjacentes em clusters.
	Usa algoritmo flood-fill simplificado.
	"""
	if points.is_empty():
		return []
	
	var clusters: Array = []
	var visited: Array = []
	var adjacency_threshold: float = threshold * 1.5  # Margem de 50%
	
	for point in points:
		if point in visited:
			continue
		
		# Novo cluster
		var cluster: Array = [point]
		var queue: Array = [point]
		visited.append(point)
		
		# Flood fill
		while not queue.is_empty():
			var current: Vector2 = queue.pop_front()
			
			# Procura vizinhos não visitados
			for other in points:
				if other in visited:
					continue
				
				# Se está próximo o suficiente, adiciona ao cluster
				if current.distance_to(other) <= adjacency_threshold:
					cluster.append(other)
					queue.append(other)
					visited.append(other)
		
		# Adiciona cluster à lista
		clusters.append(cluster)
	
	return clusters

func get_camera_position() -> Vector2:
	"""
	Obtém a posição real da câmera.
	Se houver Camera2D, usa a posição dela.
	Senão, assume que câmera segue o player.
	"""
	if not player or not is_instance_valid(player):
		return Vector2.ZERO
	
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera and is_instance_valid(camera):
		return camera.get_screen_center_position()
	
	# Fallback: assume câmera centralizada no player
	return player.global_position

func filter_offscreen_clusters(clusters: Array) -> Array:
	"""
	Filtra clusters mantendo APENAS pontos que estão offscreen + margem de segurança.
	
	LÓGICA RETANGULAR:
	- Para cada cluster, filtra pontos individuais
	- Só mantém pontos que estão FORA da viewport + margem
	- Garante que sortear qualquer ponto = sempre offscreen
	"""
	if clusters.is_empty():
		return []
	
	var offscreen_clusters: Array = []
	
	# Pega tamanho da viewport
	var viewport: Viewport = get_viewport()
	if not viewport:
		return []
	
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	
	# Pega posição REAL da câmera
	var camera_center: Vector2 = get_camera_position()
	
	# Define limites da tela + margem de segurança
	var screen_left: float = camera_center.x - viewport_size.x / 2 - offscreen_safety_margin
	var screen_right: float = camera_center.x + viewport_size.x / 2 + offscreen_safety_margin
	var screen_top: float = camera_center.y - viewport_size.y / 2 - offscreen_safety_margin
	var screen_bottom: float = camera_center.y + viewport_size.y / 2 + offscreen_safety_margin
	
	# Processa cada cluster
	for cluster in clusters:
		var offscreen_points: Array = []
		
		# Filtra APENAS pontos que estão offscreen (além da margem)
		for point in cluster:
			var is_offscreen: bool = (
				point.x < screen_left or
				point.x > screen_right or
				point.y < screen_top or
				point.y > screen_bottom
			)
			
			if is_offscreen:
				offscreen_points.append(point)
		
		# Se cluster tem pontos offscreen válidos, adiciona
		if not offscreen_points.is_empty():
			offscreen_clusters.append(offscreen_points)
	
	return offscreen_clusters

func is_position_navigable(check_pos: Vector2) -> bool:
	"""
	Verifica se uma posição está em Navigation Layer válido.
	Usa múltiplos métodos para garantir validação correta:
	1. Verifica se está em área navegável (NavigationServer2D)
	2. Verifica se NÃO está em colisão física (PhysicsServer2D)
	"""
	# Validação: precisa do player para acessar o world_2d
	if not player or not is_instance_valid(player):
		return false
	
	# =========================================
	# VALIDAÇÃO 1: NAVIGATION LAYER
	# =========================================
	# Obtém o mapa de navegação padrão do mundo via player
	var navigation_map: RID = player.get_world_2d().navigation_map
	
	# Encontra o ponto mais próximo na malha de navegação
	var closest_point := NavigationServer2D.map_get_closest_point(
		navigation_map,
		check_pos
	)
	
	# Calcula distância até o ponto navegável mais próximo
	var distance_to_nav := check_pos.distance_to(closest_point)
	
	# Se está muito longe de área navegável, não é válido
	# Tolerância: 32 pixels (antes era 16)
	if distance_to_nav > 16.0:
		return false
	
	# =========================================
	# VALIDAÇÃO 2: COLLISION (Physics Layer)
	# =========================================
	# Verifica se posição está dentro de colisão física
	var space_state := player.get_world_2d().direct_space_state
	
	# Configura query para verificar colisões
	var query := PhysicsPointQueryParameters2D.new()
	query.position = check_pos
	query.collision_mask = 1  # Layer 1 = environment/walls
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Realiza query
	var result := space_state.intersect_point(query, 1)
	
	# Se encontrou colisão, posição não é válida
	if result.size() > 0:
		return false
	
	# =========================================
	# VALIDAÇÃO PASSOU
	# =========================================
	return true

func is_safe_from_other_enemies(check_pos: Vector2) -> bool:
	"""
	Verifica se posição mantém distância mínima de outros inimigos.
	Evita que inimigos spawnem muito próximos uns dos outros.
	"""
	# Se validação está desabilitada, sempre retorna true
	if min_distance_between_enemies <= 0:
		return true
	
	# Pega todos os inimigos existentes
	var enemies: Array[Node] = get_tree().get_nodes_in_group("Enemy")
	
	# Verifica distância para cada inimigo
	for enemy in enemies:
		if not enemy or not is_instance_valid(enemy):
			continue
		
		var distance_to_enemy: float = check_pos.distance_to(enemy.global_position)
		
		# Se está muito próximo de outro inimigo, não é válido
		if distance_to_enemy < min_distance_between_enemies:
			return false
	
	# Nenhum inimigo muito próximo, é válido
	return true

func is_valid_enemy_position(pos: Vector2) -> bool:
	"""
	Validação extra de uma posição para inimigos (spawn normal ou teleport).
	
	PRECONDIÇÃO: pos deve vir de scan_navigable_grid() — a navegabilidade
	básica já foi garantida ali (via is_position_navigable), então não é
	re-checada aqui. Verificamos apenas:
	1. Espaço livre ao redor (sem paredes dentro de min_distance_from_walls)
	2. Distância segura de outros inimigos
	"""
	if not is_safe_from_walls(pos, min_distance_from_walls):
		return false
	
	if not is_safe_from_other_enemies(pos):
		return false
	
	return true

# =================================================
# SPAWN DE INIMIGO
# =================================================
func spawn_enemy(enemy_data: EnemySpawnData, spawn_pos: Vector2) -> void:
	"""
	Instancia o inimigo na posição especificada.
	"""
	if not enemy_data.enemy_scene:
		push_error("SpawnManager: enemy_scene não configurado!")
		return
	
	var enemy := enemy_data.enemy_scene.instantiate()
	
	# Adiciona na cena — _ready() roda aqui, makepath() é chamado da posição errada
	current_scene.add_child(enemy)
	
	# Define posição real APÓS _ready()
	enemy.global_position = spawn_pos
	
	# Recalcula rota da posição correta de spawn
	# Mesmo fix já aplicado aos teleportes (Passo 1)
	if enemy.has_method("makepath"):
		enemy.makepath()
	
	if debug_enabled:
		print("🔴 Spawned: ", enemy_data.enemy_name, " at ", spawn_pos, " | Budget: ", spawn_budget)
		if enemy_data.enemy_name == "Red Gator":
			print("🔥🔥🔥 RED GATOR SPAWNED! 🔥🔥🔥")
			print("   Game Time: ", game_time, "s")
			print("   Budget antes: ", spawn_budget + enemy_data.spawn_cost)
			print("   Budget depois: ", spawn_budget)

# =================================================
# UTILITÁRIOS
# =================================================
func get_enemies_alive() -> int:
	"""
	Retorna quantidade de inimigos vivos.
	"""
	return get_tree().get_nodes_in_group("Enemy").size()

func get_current_difficulty() -> float:
	"""
	Retorna multiplicador de dificuldade atual.
	"""
	return difficulty_multiplier

func get_current_budget() -> float:
	"""
	Retorna budget atual acumulado.
	"""
	return spawn_budget
