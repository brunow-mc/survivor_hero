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

## Budget com que a partida começa (aplicado no start_spawning, one-shot).
## Qualquer valor > 0 adianta o 1º spawn; >= minimal_budget dispara rajada.
## Definido pelo SpawnManagerConfig por stage. 0 = começo frio (comportamento antigo).
var initial_budget: float = 0.0

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

## Limites de teleporte por EIXO (retangulares, acompanhando a forma da tela
## e da área de spawn). Inimigos além do limite em QUALQUER eixo são
## teleportados. Definidos pelo SpawnManagerConfig por stage.
@export var max_distance_from_player_horizontal: float = 430.0
@export var max_distance_from_player_vertical: float = 325.0

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

## Distância mínima de paredes (px), medida no CENTRO DO CORPO
## (ponto de spawn + body_center_offset), onde fica o colisor real.
## Deve cobrir o raio do colisor do MAIOR inimigo + margem.
## Gator: raio 13 | Red Gator: raio 16 | Recomendado: 20 (folga
## para inimigos futuros maiores). Corredor mínimo spawnável ≈ 2x este valor.
@export var min_distance_from_walls: float = 20.0

## Offset do centro do corpo em relação ao ponto de spawn (os pés).
## A validação de paredes testa o círculo NESTA posição — é onde o
## colisor do inimigo realmente fica. Valor de referência entre o
## gator (0,-11) e inimigos maiores (red gator: 0,-16).
@export var body_center_offset: Vector2 = Vector2(0, -14)

## Raio de captura do snap ao navmesh (px)
## Pontos da grade a até esta distância do navmesh são "grudados"
## no ponto navegável mais próximo. Permite que a grade grossa
## enxergue corredores estreitos sem custo de performance.
## Recomendado: metade do grid_sample_spacing.
@export var nav_snap_radius: float = 32.0

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

# =================================================
# CACHE DA GRADE NAVEGÁVEL
# scan_navigable_grid() é a parte cara do spawn: por PONTO da grade faz uma
# consulta de navegabilidade (nos tiles) + uma de física. Mas o chão e as
# paredes são ESTÁTICOS — o resultado só muda quando a CÂMERA se move (a faixa
# é construída ao redor dela). Sem cache, um frame que spawna 5 inimigos varria
# a grade 5 vezes produzindo o mesmo resultado, e o custo cresce ~4x a cada
# vez que grid_sample_spacing é reduzido pela metade.
# Invalidação: câmera moveu mais de GRID_CACHE_MOVE_THRESHOLD, ou o
# espaçamento mudou. Ficar desatualizado degrada de forma segura: a faixa fica
# deslocada, nunca aprova ponto inválido (a navegabilidade não muda) e o filtro
# offscreen roda sempre com a câmera atual. O CUSTO da defasagem é de outra
# natureza — a borda dianteira da faixa fica sub-amostrada enquanto o player
# avança, enviesando os candidatos para TRÁS dele.
# =================================================
## Quanto a câmera pode andar antes de a grade ser revarrida (px).
## É uma DISTÂNCIA FIXA, deliberadamente independente de grid_sample_spacing:
## antes era "meia célula", o que amarrava a FREQUÊNCIA das varreduras à
## resolução da grade — reduzir o espaçamento pela metade dobrava o número de
## varreduras por segundo E quadruplicava os pontos de cada uma (~7x mais
## consultas ao servidor por segundo). O que define a tolerância aqui não é a
## resolução, e sim quanto a faixa de spawn pode ficar deslocada e ainda
## servir — e a faixa tem ~100px de espessura.
## CALIBRAÇÃO: valores altos economizam varreduras mas enviesam o spawn para
## trás do player (a faixa dianteira fica defasada). Como a varredura ficou
## ~10x mais barata ao migrar para leitura de tiles, o certo é manter este
## valor BAIXO — a economia deixou de ser necessária.
const GRID_CACHE_MOVE_THRESHOLD: float = 16.0

## Camadas onde inimigos podem NASCER. Não têm relação com a navegação:
## quem move inimigo é o navmesh, que não passa por aqui.
## Resolvidas pelo SpawnManagerConfig (export preenchido -> essas camadas;
## export vazio -> varredura da cena).
## Listar a camada NÃO diz que ela é toda navegável — quem decide é cada
## tile (ver _get_nav_layer_data).
var enemy_spawn_ground_layers: Array[TileMapLayer] = []
var _nav_layer_data: Array = []
var _nav_cache_built: bool = false

var _grid_cache: Array = []
var _grid_cache_camera_pos: Vector2 = Vector2.INF
var _grid_cache_spacing: float = -1.0
var _grid_cache_valid: bool = false

## Delay inicial antes do primeiro spawn (segundos).
## O SPAWN não depende mais do navmesh (lê navegabilidade dos tiles), mas o
## PATHFINDING dos inimigos depende — o delay evita que os primeiros inimigos
## nasçam antes de a navegação estar pronta e fiquem parados.
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

# PERFORMANCE: shape e query reutilizados em is_safe_from_walls.
# Os campos fixos são configurados uma vez no _ready(); por chamada só
# variam o raio do círculo e a transform.
var _wall_check_circle: CircleShape2D = CircleShape2D.new()
var _wall_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()

# PERFORMANCE: lista de inimigos reaproveitada dentro do mesmo frame de
# física (ver _get_enemies).
var _enemy_cache: Array[Node] = []
var _enemy_cache_frame: int = -1

# Guarda de repetição do aviso "nenhum cluster offscreen" (ver
# find_spawn_position). Rearmado a cada spawn bem-sucedido.
var _warned_no_offscreen: bool = false

# PERFORMANCE: query reutilizada em get_snapped_navigable_point.
# Era criada com .new() a cada PONTO da grade — no laço mais quente do
# sistema, isso significava centenas de alocações por varredura (e o
# lixo correspondente). Os campos fixos são configurados uma vez aqui;
# só `position` muda a cada chamada.
var _point_query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()

# =================================================
# REFERÊNCIAS
# =================================================
var player: Node2D = null
var current_scene: Node = null

## Container onde os inimigos são adicionados (ex: YSortContainer).
## Entidades precisam ser FILHAS do node com y_sort_enabled para
## participar do Y-sort — spawnar na raiz da cena as deixaria fora.
## Definido por SpawnManagerConfig; fallback: current_scene.
var enemy_container: Node2D = null

# =================================================
# READY
# =================================================
func _ready() -> void:
	# Campos fixos da query reutilizada (só `position` muda por chamada)
	_point_query.collision_mask = 1  # Layer 1 = environment/walls
	_point_query.collide_with_areas = false
	_point_query.collide_with_bodies = true

	# Idem para a query de área (só raio e transform mudam por chamada)
	_wall_query.shape = _wall_check_circle
	_wall_query.collision_mask = 1  # Layer 1 = TileMap collision (paredes)

	# Aguarda a cena carregar completamente
	await get_tree().process_frame
	set_physics_process(false)  # Desativado até start_spawning() ser chamado

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
	# Budget parte da reserva inicial (rajada de abertura); 0 = começo frio.
	spawn_budget = initial_budget
	difficulty_multiplier = 1.0
	_grid_cache_valid = false  # nova partida: descarta a grade da anterior
	_enemy_cache_frame = -1    # a lista de inimigos da partida anterior morreu junto
	_warned_no_offscreen = false

	# Ativa spawning
	is_spawning_enabled = true
	set_physics_process(true)
	
	print("✅ SpawnManager iniciado!")
	print("   Delay inicial: ", initial_spawn_delay, "s (aguarda a navegação ficar pronta para o pathfinding)")

func stop_spawning() -> void:
	"""
	Para o sistema de spawn.
	"""
	is_spawning_enabled = false
	set_physics_process(false)
	print("⏸️ SpawnManager parado!")

# =================================================
# PROCESS (Loop Principal)
# =================================================
## Roda em _physics_process, NÃO em _process. O spawn consulta o
## direct_space_state (intersect_point, intersect_shape), que é feito para ser
## consultado durante o FRAME DE FÍSICA — do frame idle o estado pode estar em
## trânsito. Bônus: o delta aqui é fixo, então o acúmulo de budget fica estável.
## NÃO é otimização: foi tentado como tal durante a caça ao engasgo e o pico
## apenas migrou de Process Time para Physics Time, com a mesma altura. Foi
## mantido por correção, não por desempenho.
func _physics_process(delta: float) -> void:
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
	
	# FASE 1: COLETA inimigos que precisam teleportar.
	# Feita ANTES de preparar o cache: é uma checagem BARATA (uma distância
	# por inimigo, sem consulta de física/navmesh), enquanto o cache varre e
	# valida a grade inteira. Na ordem anterior o cache era preparado sempre,
	# a cada teleport_check_interval, mesmo com ZERO inimigos elegíveis — e
	# todo esse trabalho era descartado logo abaixo.
	var enemies: Array[Node] = _get_enemies()
	var enemies_to_teleport: Array = []

	for enemy in enemies:
		if not enemy or not is_instance_valid(enemy):
			continue

		# Distância por EIXO. O teste é RETANGULAR (não radial) para
		# acompanhar a forma da tela e da faixa de spawn: um raio único
		# ficaria curto num eixo e folgado no outro. Bônus: sem raiz
		# quadrada — comparação direta de componentes.
		var offset: Vector2 = enemy.global_position - player.global_position

		# Se ultrapassou o limite em QUALQUER eixo, marca para teleport
		if absf(offset.x) > max_distance_from_player_horizontal \
				or absf(offset.y) > max_distance_from_player_vertical:
			enemies_to_teleport.append(enemy)

			# LIMITE: Se atingiu max_teleports_per_frame, para
			if max_teleports_per_frame > 0 and enemies_to_teleport.size() >= max_teleports_per_frame:
				break  # Resto fica para próximo check

	# Ninguém longe → sai SEM varrer a grade
	if enemies_to_teleport.is_empty():
		return

	# FASE 0: PREPARA cache de posições seguras (só agora que sabemos que
	# há alguém para teleportar)
	prepare_safe_teleport_cache()

	# Se cache está vazio, não há posições válidas
	if safe_teleport_positions.is_empty():
		if debug_enabled:
			print("⚠️ Cache de teleport vazio - sem posições seguras disponíveis")
		return

	# FASE 2: ATRIBUI posições do cache (O(1) por inimigo)
	var teleported_count: int = 0
	
	for enemy in enemies_to_teleport:
		# Se cache acabou, para (restantes esperam próximo ciclo)
		if safe_teleport_positions.is_empty():
			if debug_enabled:
				print("⚠️ CACHE ESGOTADO - ", enemies_to_teleport.size() - teleported_count, " inimigos aguardam próximo ciclo\n")
			break
		
		# Pega do cache uma posição onde ESTE inimigo cabe
		# (re-valida com a folga do próprio EnemySpawnData)
		var pos: Vector2 = _take_position_fitting_enemy(enemy)
		if pos == Vector2.INF:
			continue  # sem posição compatível neste ciclo; tenta no próximo

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
	
	# Varre grade (cacheada) e filtra clusters offscreen
	var clusters: Array = get_navigable_grid()
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
	Validação de posição de teleport (PRODUÇÃO) — PRÉ-FILTRO do cache.
	Usa a MENOR folga entre os inimigos definidos, para que pontos de
	corredores estreitos entrem no cache (cabem para o menor inimigo).
	Na atribuição, cada inimigo re-testa o encaixe com a PRÓPRIA folga
	(_take_position_fitting_enemy).
	"""
	return is_valid_enemy_position(pos, _get_min_spawn_clearance(), body_center_offset)


func _get_min_spawn_clearance() -> float:
	"""Menor spawn_clearance_radius entre os inimigos definidos."""
	var min_clearance: float = min_distance_from_walls
	for def in enemy_definitions:
		if def and def.spawn_clearance_radius < min_clearance:
			min_clearance = def.spawn_clearance_radius
	return min_clearance


func _find_definition_for_enemy(enemy: Node) -> EnemySpawnData:
	"""Localiza o EnemySpawnData de um inimigo vivo pelo path da cena."""
	for def in enemy_definitions:
		if def and def.enemy_scene and def.enemy_scene.resource_path == enemy.scene_file_path:
			return def
	return null


func _take_position_fitting_enemy(enemy: Node) -> Vector2:
	"""
	Retira do cache uma posição onde ESTE inimigo cabe (folga do seu
	EnemySpawnData; fallback: defaults globais). Vector2.INF se nenhuma
	das posições testadas servir neste ciclo.
	"""
	var clearance: float = min_distance_from_walls
	var offset: Vector2 = body_center_offset
	var def := _find_definition_for_enemy(enemy)
	if def:
		clearance = def.spawn_clearance_radius
		offset = def.body_center_offset

	# Testa do fim para o início (cache já embaralhado); limita
	# tentativas para não varrer o cache inteiro por inimigo.
	var max_tries: int = mini(safe_teleport_positions.size(), 16)
	for i in range(max_tries):
		var idx: int = safe_teleport_positions.size() - 1 - i
		var pos: Vector2 = safe_teleport_positions[idx]
		if is_safe_from_walls(pos + offset, clearance):
			safe_teleport_positions.remove_at(idx)
			return pos

	return Vector2.INF

func validate_teleport_position_debug(pos: Vector2) -> Dictionary:
	"""
	Validação DETALHADA com tracking. Só é chamada quando debug_enabled
	está ligado (ver prepare_safe_teleport_cache) — a versão de produção
	é validate_teleport_position().

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

	# 2. Espaço livre ao redor do CENTRO DO CORPO (mesma regra
	# de is_valid_enemy_position)
	result.safe_from_walls = is_safe_from_walls(pos + body_center_offset, min_distance_from_walls)
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

	var space := player.get_world_2d().direct_space_state

	# Query e shape são reutilizados entre chamadas — esta função roda ~150x
	# num frame de teleporte, e alocar os dois objetos toda vez era puro lixo.
	# shape/collision_mask são fixos e setados no _ready(); aqui só variam o
	# raio e a posição.
	_wall_check_circle.radius = safety_radius
	_wall_query.transform = Transform2D(0, pos)

	# Verifica se há colisão dentro do círculo
	var results := space.intersect_shape(_wall_query, 1)
	
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
		
		# Encontra posição válida de spawn (folga do inimigo sorteado)
		var spawn_pos := find_spawn_position(enemy_data)
		
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
	
	var enemies_alive := _get_enemies().size()
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
func find_spawn_position(enemy_data: EnemySpawnData = null) -> Vector2:
	"""
	Encontra posição de spawn usando Grid Sampling.
	Varre grade retangular, agrupa clusters navegáveis, filtra offscreen.
	A validação de paredes usa a folga do INIMIGO sorteado (enemy_data),
	para que cada inimigo spawne onde ele fisicamente cabe.
	"""
	if not player or not is_instance_valid(player):
		return Vector2.ZERO

	var clearance: float = enemy_data.spawn_clearance_radius if enemy_data else min_distance_from_walls
	var body_offset: Vector2 = enemy_data.body_center_offset if enemy_data else body_center_offset
	
	total_spawn_attempts += 1
	
	# =========================================
	# GRID SAMPLING: Varredura inteligente
	# =========================================
	
	# 1. Grade navegável (cacheada — ver get_navigable_grid)
	var clusters: Array = get_navigable_grid()
	
	# Armazena para debug visual
	last_scanned_clusters = clusters
	
	# 2. Filtra clusters que estão FORA da tela
	var offscreen_clusters: Array = filter_offscreen_clusters(clusters)
	
	# 3. Se não encontrou clusters offscreen, falha
	if offscreen_clusters.is_empty():
		failed_spawn_attempts += 1
		
		# Avisa UMA VEZ por episódio. Esta condição dura enquanto durar
		# (player encurralado, área navegável pequena) e find_spawn_position
		# roda a cada frame de física — sem a guarda são milhares de avisos,
		# cada um com rastreamento de pilha. O flag é rearmado quando um
		# spawn volta a ter sucesso, então um novo episódio avisa de novo.
		if show_spawn_warnings and not _warned_no_offscreen:
			_warned_no_offscreen = true
			push_warning("SpawnManager: nenhum cluster offscreen encontrado — spawn suspenso ate normalizar. Clusters totais: %d | Offscreen: 0. Causa provavel: player muito perto de paredes, ou area navegavel pequena para as margens de spawn configuradas." % clusters.size())

		return Vector2.ZERO
	
	# 4. Escolhe cluster aleatório
	var chosen_cluster: Array = offscreen_clusters.pick_random()
	
	# 5. Sorteia ponto dentro do cluster
	var spawn_pos: Vector2 = chosen_cluster.pick_random()
	
	# 6. Validação extra: distância de paredes e de outros inimigos
	#    (navegabilidade já garantida por scan_navigable_grid)
	if not is_valid_enemy_position(spawn_pos, clearance, body_offset):
		# Tenta outros pontos do mesmo cluster
		var found_valid: bool = false
		for point in chosen_cluster:
			if is_valid_enemy_position(point, clearance, body_offset):
				spawn_pos = point
				found_valid = true
				break

		# NENHUM ponto do cluster passou na validação completa:
		# NÃO spawnar. Usar o ponto reprovado colocaria o corpo do
		# inimigo dentro de paredes (a origem fica nos pés; o colisor
		# se estende ~24px acima do ponto). O budget fica retido e o
		# spawn tenta novamente no próximo frame.
		if not found_valid:
			failed_spawn_attempts += 1
			if debug_enabled:
				print("⚠️ Spawn abortado: nenhum ponto seguro no cluster (", chosen_cluster.size(), " pontos)")
			return Vector2.ZERO

	# Spawn bem-sucedido: rearma o aviso de "sem cluster offscreen".
	_warned_no_offscreen = false

	if debug_enabled:
		print("✅ Grid Sampling: Spawn em ", spawn_pos)
		print("   Clusters: ", clusters.size(), " | Offscreen: ", offscreen_clusters.size())
		print("   Cluster escolhido: ", chosen_cluster.size(), " pontos")

	return spawn_pos

## Grade navegável, reaproveitada enquanto continuar válida (ver _grid_cache).
## Todo consumidor deve chamar ESTE método, nunca scan_navigable_grid() direto.
func get_navigable_grid() -> Array:
	var cam: Vector2 = get_camera_position()

	if (not _grid_cache_valid
			or _grid_cache_spacing != grid_sample_spacing
			or cam.distance_to(_grid_cache_camera_pos) > GRID_CACHE_MOVE_THRESHOLD):
		_grid_cache = scan_navigable_grid()
		_grid_cache_camera_pos = cam
		_grid_cache_spacing = grid_sample_spacing
		_grid_cache_valid = true

	return _grid_cache

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
	var snapped_point: Vector2
	
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
			snapped_point = get_snapped_navigable_point(Vector2(x, y))
			if snapped_point != Vector2.INF:
				navigable_points.append(snapped_point)
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
			snapped_point = get_snapped_navigable_point(Vector2(x, y))
			if snapped_point != Vector2.INF:
				navigable_points.append(snapped_point)
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
			snapped_point = get_snapped_navigable_point(Vector2(x, y))
			if snapped_point != Vector2.INF:
				navigable_points.append(snapped_point)
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
			snapped_point = get_snapped_navigable_point(Vector2(x, y))
			if snapped_point != Vector2.INF:
				navigable_points.append(snapped_point)
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
	Agrupa pontos navegáveis adjacentes em clusters (flood-fill).

	PERFORMANCE — três correções sobre a versão original, que era CÚBICA:
	1. `visited` é Dictionary (busca O(1)); era Array, cujo `in` faz
	   varredura LINEAR — dentro de dois laços aninhados.
	2. Vizinhos vêm de um HASH ESPACIAL (só as 9 células ao redor), em vez
	   de varrer TODOS os pontos a cada item da fila. Mesma técnica do grid
	   espacial do steering dos inimigos.
	3. A fila avança por índice; `pop_front()` num Array desloca todos os
	   elementos a cada chamada.

	Isso é o que tornava `grid_sample_spacing` explosivo: metade do
	espaçamento = 4x mais pontos = ~64x mais trabalho na versão antiga.
	"""
	if points.is_empty():
		return []

	var adjacency_threshold: float = threshold * 1.5  # Margem de 50%

	# Hash espacial. Célula = adjacency_threshold, então todo vizinho válido
	# cai na própria célula ou numa das 8 adjacentes.
	var cell_size: float = adjacency_threshold
	var buckets: Dictionary = {}
	for point in points:
		var cell := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
		if buckets.has(cell):
			buckets[cell].append(point)
		else:
			buckets[cell] = [point]

	var clusters: Array = []
	var visited: Dictionary = {}

	for point in points:
		if visited.has(point):
			continue

		# Novo cluster
		var cluster: Array = [point]
		var queue: Array = [point]
		visited[point] = true

		# Flood fill — consulta só as células vizinhas, não todos os pontos
		var head: int = 0
		while head < queue.size():
			var current: Vector2 = queue[head]
			head += 1

			var base_cell := Vector2i(floori(current.x / cell_size), floori(current.y / cell_size))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var cell := base_cell + Vector2i(dx, dy)
					if not buckets.has(cell):
						continue

					for other in buckets[cell]:
						if visited.has(other):
							continue

						# Se está próximo o suficiente, entra no cluster
						if current.distance_to(other) <= adjacency_threshold:
							cluster.append(other)
							queue.append(other)
							visited[other] = true

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

func get_snapped_navigable_point(check_pos: Vector2) -> Vector2:
	"""
	SNAP AO CHÃO NAVEGÁVEL: em vez de exigir que o ponto da grade caia em
	cima de uma célula navegável, "gruda" o ponto no CENTRO da célula
	navegável mais próxima (se estiver dentro do raio nav_snap_radius).

	Isso permite que a grade grossa enxergue faixas finas (corredores
	estreitos) sem jamais aprovar um ponto fora do chão caminhável.

	FONTE DA VERDADE: os próprios tiles, via TileData.get_navigation_polygon()
	— exatamente o dado a partir do qual o Godot gera o navmesh.

	Antes isto perguntava a NavigationServer2D.map_get_closest_point(), que faz
	busca LINEAR em todas as regiões do mapa. O TileMapLayer cria UMA REGIÃO
	POR TILE (3762 no stage01, ~7500 triângulos), então cada consulta custava
	~140 us e uma varredura de 288 pontos travava o frame por ~40 ms. Ler do
	tile é busca de hash. A equivalência foi verificada empiricamente rodando
	os dois métodos lado a lado: ZERO divergências de veredito em 27 varreduras.

	Retorna o ponto grudado, ou Vector2.INF se não capturável.
	"""
	if not player or not is_instance_valid(player):
		return Vector2.INF

	var best: Vector2 = Vector2.INF
	var best_dist: float = nav_snap_radius

	for data in _get_nav_layer_data():
		var layer: TileMapLayer = data["layer"]
		if not is_instance_valid(layer):
			continue

		var cells: Dictionary = data["cells"]
		var half: Vector2 = data["half"]
		var cell_radius: int = data["cell_radius"]
		var local: Vector2 = layer.to_local(check_pos)
		var center_cell: Vector2i = layer.local_to_map(local)

		for dx in range(-cell_radius, cell_radius + 1):
			for dy in range(-cell_radius, cell_radius + 1):
				var cell := Vector2i(center_cell.x + dx, center_cell.y + dy)
				if not cells.has(cell):
					continue

				var c: Vector2 = layer.map_to_local(cell)

				# SELEÇÃO (qual célula vence): distância até o ponto mais
				# próximo do RETÂNGULO da célula. Medir até o centro encolheria
				# o alcance efetivo do nav_snap_radius em até meia diagonal do
				# tile, tirando células de borda que hoje são alcançáveis.
				# Aproximação aceita: um tile cujo polígono de navegação cobre
				# só parte do tile é tratado como o tile inteiro. A validação de
				# física abaixo e o clearance do spawn cobrem o resíduo.
				var clamped := Vector2(
					clampf(local.x, c.x - half.x, c.x + half.x),
					clampf(local.y, c.y - half.y, c.y + half.y)
				)
				var d: float = check_pos.distance_to(layer.to_global(clamped))

				if d <= best_dist:
					best_dist = d
					# POSIÇÃO DEVOLVIDA: o CENTRO da célula, nunca a borda.
					# Prender ao retângulo joga todo ponto vindo de fora
					# exatamente na FRONTEIRA do tile — isto é, o mais colado
					# possível na parede vizinha. Era a causa sistemática de
					# inimigos nascendo encostados em paredes (o método antigo,
					# via map_get_closest_point, tinha o mesmo viés).
					# O centro é, por definição, o ponto mais distante das
					# bordas daquela célula; num corredor de 1 tile é a linha
					# central do corredor. Ganho duplo: melhor posicionamento E
					# mais pontos aprovados no is_safe_from_walls, que roda
					# DEPOIS do snap — corredores estreitos ganham candidatos.
					best = layer.to_global(c)
			if best_dist == 0.0:
				break  # já está sobre célula navegável; nada fica mais perto
		if best_dist == 0.0:
			break

	if best == Vector2.INF:
		return Vector2.INF

	# =========================================
	# VALIDAÇÃO: COLLISION (Physics Layer)
	# Verifica o ponto GRUDADO (o que será usado), não o da grade
	# =========================================
	var space_state := player.get_world_2d().direct_space_state

	# Reutiliza a query cacheada — evita uma alocação por ponto da grade.
	# collision_mask/collide_with_* são fixos e setados no _ready().
	_point_query.position = best

	if space_state.intersect_point(_point_query, 1).size() > 0:
		return Vector2.INF

	return best


## Navegabilidade por célula, PRÉ-COMPUTADA.
##
## Os TileMaps são estáticos, então "esta célula é navegável?" nunca muda em
## runtime. Sem o cache, cada ponto da grade fazia ~75 chamadas de
## get_cell_tile_data() (5x5 células x 3 camadas) = ~25 us; com ele, viram
## buscas de hash. Se alguma fase futura alterar tiles em runtime — ou
## nav_snap_radius —, chame invalidate_nav_layer_cache().
##
## O filtro é POR TILE, nunca por camada: uma camada como TileMapBuildings
## mistura tiles de colisão e tiles de navegação, e só os que têm polígono de
## navegação entram. Camadas cujo TileSet não tem nenhuma camada de navegação
## (ex.: decoração) são descartadas inteiras, de graça.
func _get_nav_layer_data() -> Array:
	if _nav_cache_built:
		var stale: bool = false
		for data in _nav_layer_data:
			if not is_instance_valid(data["layer"]):
				stale = true
				break
		if not stale:
			return _nav_layer_data

	_nav_layer_data.clear()
	_nav_cache_built = true

	for layer in enemy_spawn_ground_layers:
		if not is_instance_valid(layer) or layer.tile_set == null:
			continue

		var ts: TileSet = layer.tile_set
		var nav_layer_count: int = ts.get_navigation_layers_count()
		if nav_layer_count <= 0:
			continue

		var cells: Dictionary = {}
		var orphan_cells: Array[Vector2i] = []
		for cell in layer.get_used_cells():
			# Célula pintada cuja fonte não existe mais no TileSet (fonte
			# removida/reimportada depois da pintura). get_cell_tile_data()
			# emitiria erro do C++ nesses casos, então checa antes.
			var source_id: int = layer.get_cell_source_id(cell)
			if source_id < 0 or not ts.has_source(source_id):
				orphan_cells.append(cell)
				continue

			var td: TileData = layer.get_cell_tile_data(cell)
			if td == null:
				continue
			for i in nav_layer_count:
				if td.get_navigation_polygon(i) != null:
					cells[cell] = true
					break

		if not orphan_cells.is_empty():
			var where: PackedStringArray = []
			for c in orphan_cells.slice(0, 8):
				var w: Vector2 = layer.to_global(layer.map_to_local(c))
				where.append("celula %s ~ mundo (%.0f, %.0f)" % [c, w.x, w.y])
			push_warning("SpawnManager: a camada '%s' tem %d celula(s) apontando para fontes de TileSet que nao existem mais (tiles orfaos). Foram ignoradas, mas sao dados invalidos na cena e valem uma limpeza no editor: %s" % [
				layer.name, orphan_cells.size(), ", ".join(where)
			])

		if cells.is_empty():
			continue

		var tile_size := Vector2(ts.tile_size)
		_nav_layer_data.append({
			"layer": layer,
			"cells": cells,
			"half": tile_size * 0.5,
			"cell_radius": int(ceil(nav_snap_radius / minf(tile_size.x, tile_size.y))),
		})

	if _nav_layer_data.is_empty():
		push_warning("SpawnManager: nenhuma camada com tiles navegáveis encontrada — NÃO HAVERÁ SPAWN. Verifique se a cena tem TileMapLayer com polígono de navegação no TileSet, ou corrija 'Enemy Spawn Ground Layers' no SpawnManagerConfig.")

	return _nav_layer_data


## Descarta o cache de navegabilidade (e a grade, que deriva dele).
func invalidate_nav_layer_cache() -> void:
	_nav_cache_built = false
	_grid_cache_valid = false


func is_position_navigable(check_pos: Vector2) -> bool:
	"""
	Verifica se uma posição é navegável (via snap ao chão navegável).
	Para pontos já sobre uma célula navegável (ex: validação de teleporte),
	o snap é identidade e isto equivale à checagem direta.
	"""
	return get_snapped_navigable_point(check_pos) != Vector2.INF

func is_safe_from_other_enemies(check_pos: Vector2) -> bool:
	"""
	Verifica se posição mantém distância mínima de outros inimigos.
	Evita que inimigos spawnem muito próximos uns dos outros.
	"""
	# Se validação está desabilitada, sempre retorna true
	if min_distance_between_enemies <= 0:
		return true

	# Compara o QUADRADO da distância — evita uma raiz quadrada por inimigo
	# num laço que roda (nº de candidatos x nº de inimigos) vezes por ciclo.
	var min_dist_sq: float = min_distance_between_enemies * min_distance_between_enemies

	# Distâncias em frame de PÉS: check_pos é um ponto do chão e
	# enemy.global_position é a origem (pés) do inimigo — os dois lados na
	# mesma referência. Aqui NÃO se usa o BodyCenter de propósito.
	for enemy in _get_enemies():
		if not is_instance_valid(enemy):
			continue

		if check_pos.distance_squared_to(enemy.global_position) < min_dist_sq:
			return false

	# Nenhum inimigo muito próximo, é válido
	return true


## Lista de inimigos vivos, cacheada por FRAME DE FÍSICA.
##
## is_safe_from_other_enemies() roda >100x num frame de teleporte, e cada
## chamada fazia um get_nodes_in_group("Enemy") — que ALOCA um Array novo a
## cada vez. A lista só muda quando um inimigo nasce ou morre: a morte é
## coberta pelo is_instance_valid de quem consome, e o nascimento invalida
## este cache explicitamente (ver spawn_enemy), porque um mesmo frame pode
## spawnar vários inimigos e o segundo precisa "enxergar" o primeiro.
func _get_enemies() -> Array[Node]:
	var frame: int = Engine.get_physics_frames()
	if frame != _enemy_cache_frame:
		_enemy_cache = get_tree().get_nodes_in_group("Enemy")
		_enemy_cache_frame = frame
	return _enemy_cache

func is_valid_enemy_position(pos: Vector2, clearance: float = -1.0, offset: Vector2 = Vector2.INF) -> bool:
	"""
	Validação extra de uma posição para inimigos (spawn normal ou teleport).
	
	PRECONDIÇÃO: pos deve vir de scan_navigable_grid() — a navegabilidade
	básica já foi garantida ali (via is_position_navigable), então não é
	re-checada aqui. Verificamos apenas:
	1. Espaço livre ao redor (sem paredes dentro de min_distance_from_walls)
	2. Distância segura de outros inimigos
	"""
	# Checagem de paredes no CENTRO DO CORPO (onde o colisor fica),
	# não nos pés: é o teste "o corpo cabe aqui sem tocar parede?".
	# clearance/offset vêm do EnemySpawnData do inimigo sorteado
	# (folga POR INIMIGO — o gator cabe onde o red gator não cabe);
	# sem inimigo específico, caem nos defaults globais.
	if clearance < 0.0:
		clearance = min_distance_from_walls
	if offset == Vector2.INF:
		offset = body_center_offset

	if not is_safe_from_walls(pos + offset, clearance):
		return false

	if not is_safe_from_other_enemies(pos):
		return false

	return true

# =================================================
# SPAWN DE INIMIGO
# =================================================
# O body_center_offset do EnemySpawnData é uma DUPLICATA MANUAL da posição do
# nó BodyCenter da cena do inimigo, usada para validar a folga de parede no
# ponto certo. Se as duas divergirem, o spawn valida o lugar errado — e isso é
# invisível em jogo (já aconteceu: Red Gator com 4px de erro). Avisa UMA VEZ
# por cena de inimigo.
var _warned_offset_scenes: Dictionary = {}

func _validate_body_center_offset(enemy: Node, enemy_data: EnemySpawnData) -> void:
	var scene_key: String = enemy.scene_file_path
	if scene_key == "" or _warned_offset_scenes.has(scene_key):
		return
	_warned_offset_scenes[scene_key] = true

	var marker: Node2D = enemy.get_node_or_null("BodyCenter") as Node2D
	if marker == null:
		return  # ausência do marcador já é avisada pelo EnemyBase

	if not marker.position.is_equal_approx(enemy_data.body_center_offset):
		push_warning(
			"SpawnManager [%s]: body_center_offset do EnemySpawnData (%s) diverge do nó BodyCenter da cena (%s) — a folga de parede está sendo validada no ponto errado. Sincronize os dois."
			% [scene_key.get_file(), enemy_data.body_center_offset, marker.position]
		)

func spawn_enemy(enemy_data: EnemySpawnData, spawn_pos: Vector2) -> void:
	"""
	Instancia o inimigo na posição especificada.
	"""
	if not enemy_data.enemy_scene:
		push_error("SpawnManager: enemy_scene não configurado!")
		return
	
	var enemy := enemy_data.enemy_scene.instantiate()

	# Adiciona no container Y-sort (fallback: raiz da cena) —
	# _ready() roda aqui, makepath() é chamado da posição errada
	var parent_node: Node = enemy_container if is_instance_valid(enemy_container) else current_scene
	parent_node.add_child(enemy)
	
	# Define posição real APÓS _ready()
	enemy.global_position = spawn_pos

	# O add_child acima já rodou o _ready() do inimigo (e portanto o
	# add_to_group("Enemy")). Invalida o cache para que um segundo spawn
	# NESTE MESMO frame respeite min_distance_between_enemies em relação a
	# este que acabou de nascer.
	_enemy_cache_frame = -1
	
	# Recalcula rota da posição correta de spawn
	# Mesmo fix já aplicado aos teleportes (Passo 1)
	if enemy.has_method("makepath"):
		enemy.makepath()

	_validate_body_center_offset(enemy, enemy_data)
	
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
	return _get_enemies().size()

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
