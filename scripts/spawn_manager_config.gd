extends Node

## =================================================
## SPAWN MANAGER CONFIG
## =================================================
## Cena configurável que inicializa o SpawnManagerGlobal.
## Pode ser instanciada em qualquer stage/arena.
## Define os parâmetros de spawn específicos daquela fase.
## =================================================

# =================================================
# CONFIGURAÇÕES GERAIS
# =================================================
@export_group("Spawn Settings")
## Número máximo de inimigos vivos simultaneamente
@export var max_enemies: int = 100

## Budget inicial por segundo (aumenta com dificuldade)
@export var base_budget_per_second: float = 1.0

## Budget mínimo necessário para INICIAR spawning
## Deve ser >= ao custo do inimigo mais caro
## Exemplo: Se Red Gator custa 3.0, minimal_budget = 3.0
@export var minimal_budget: float = 3.0

# =================================================
# SPAWN ÁREA RETANGULAR
# =================================================
@export_group("Spawn Area (Rectangular)")
## Margem MÍNIMA horizontal (esquerda/direita) além da tela
@export var spawn_margin_min_horizontal: float = 50.0

## Margem MÍNIMA vertical (cima/baixo) além da tela
@export var spawn_margin_min_vertical: float = 50.0

## Margem MÁXIMA horizontal (esquerda/direita) além da tela
@export var spawn_margin_max_horizontal: float = 150.0

## Margem MÁXIMA vertical (cima/baixo) além da tela
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
# Y-SORT CONTAINER
# =================================================
@export_group("Y-Sort")
## Container onde os inimigos spawnados são adicionados
## (ex: YSortContainer). Entidades só participam do Y-sort
## se forem FILHAS do node com y_sort_enabled.
## Vazio = inimigos vão para a raiz da cena (sem Y-sort).
@export var enemy_container: Node2D

# =================================================
# TELEPORT SYSTEM
# =================================================
# TELEPORT SYSTEM
# =================================================
@export_group("Teleport System")
## Habilitar teleporte de inimigos distantes
@export var teleport_enabled: bool = true

## Distância máxima do player antes de teleportar (px)
@export var max_distance_from_player: float = 350.0

## Intervalo para checar e teleportar inimigos (segundos)
@export var teleport_check_interval: float = 2.0

## Limite de teleports por frame (0 = sem limite)
@export var max_teleports_per_frame: int = 10

# =================================================
# SPAWN VALIDATION
# =================================================
@export_group("Spawn Validation")
## Distância mínima entre inimigos no spawn (px)
@export var min_distance_between_enemies: float = 48.0

## Distância mínima de paredes (px), medida no CENTRO DO CORPO
## (ponto de spawn + body_center_offset). Deve cobrir o raio do colisor
## do MAIOR inimigo + margem. Recomendado: 20.
@export var min_distance_from_walls: float = 20.0

## Offset do centro do corpo em relação ao ponto de spawn (os pés).
## A validação de paredes testa o círculo nesta posição.
@export var body_center_offset: Vector2 = Vector2(0, -14)

## Raio de captura do snap ao navmesh (px)
## Pontos da grade a até esta distância são "grudados" no ponto navegável
## mais próximo — a grade grossa enxerga corredores estreitos sem custo.
@export var nav_snap_radius: float = 32.0

# =================================================
# GRID SAMPLING
# =================================================
@export_group("Grid Sampling")
## Espaçamento entre pontos da grade (pixels)
@export var grid_sample_spacing: float = 32.0

## Visualizar grade e clusters (debug visual)
@export var debug_draw_enabled: bool = false

# =================================================
# AUTO-INICIALIZAÇÃO
# =================================================
@export_group("Initialization")
## Se true, inicia spawning automaticamente em _ready()
@export var auto_start: bool = true

# =================================================
# READY
# =================================================
func _ready() -> void:
	if auto_start:
		# Aguarda 1 frame para garantir que tudo foi inicializado
		await get_tree().process_frame
		initialize_spawn_manager()
	
	# Instancia debug overlay se habilitado
	if debug_draw_enabled:
		create_debug_overlay()

# =================================================
# INICIALIZAÇÃO DO SPAWN MANAGER GLOBAL
# =================================================
func initialize_spawn_manager() -> void:
	"""
	Configura e inicia o SpawnManagerGlobal com os parâmetros desta cena.
	"""
	if not SpawnManagerGlobal:
		push_error("SpawnManagerConfig: SpawnManagerGlobal não encontrado!")
		return
	
	# Transfere configurações para o singleton
	SpawnManagerGlobal.max_enemies = max_enemies
	SpawnManagerGlobal.base_budget_per_second = base_budget_per_second
	SpawnManagerGlobal.minimal_budget = minimal_budget
	
	# Transfere margens retangulares
	SpawnManagerGlobal.spawn_margin_min_horizontal = spawn_margin_min_horizontal
	SpawnManagerGlobal.spawn_margin_min_vertical = spawn_margin_min_vertical
	SpawnManagerGlobal.spawn_margin_max_horizontal = spawn_margin_max_horizontal
	SpawnManagerGlobal.spawn_margin_max_vertical = spawn_margin_max_vertical
	SpawnManagerGlobal.offscreen_safety_margin = offscreen_safety_margin
	
	SpawnManagerGlobal.difficulty_increase_per_minute = difficulty_increase_per_minute
	SpawnManagerGlobal.max_difficulty_multiplier = max_difficulty_multiplier
	SpawnManagerGlobal.enemy_definitions = enemy_definitions

	# Aviso: sem container, inimigos caem na raiz da cena (z efetivo menor
	# que o do player dentro do YSortContainer) e o player fica sempre na
	# frente deles — Y-sort player↔inimigos quebra silenciosamente.
	# Causa comum: trocar/recolocar o YSortContainer sem rearrastá-lo aqui.
	if not is_instance_valid(enemy_container):
		push_warning("SpawnManagerConfig: 'enemy_container' vazio — inimigos vão para a raiz da cena e o Y-sort player↔inimigos não vai funcionar. Arraste o YSortContainer para o campo 'Enemy Container' no Inspector.")
	SpawnManagerGlobal.enemy_container = enemy_container
	
	# Transfere configurações de teleport
	SpawnManagerGlobal.teleport_enabled = teleport_enabled
	SpawnManagerGlobal.max_distance_from_player = max_distance_from_player
	SpawnManagerGlobal.teleport_check_interval = teleport_check_interval
	SpawnManagerGlobal.max_teleports_per_frame = max_teleports_per_frame
	
	# Transfere configurações de validação
	SpawnManagerGlobal.min_distance_between_enemies = min_distance_between_enemies
	SpawnManagerGlobal.min_distance_from_walls = min_distance_from_walls
	SpawnManagerGlobal.body_center_offset = body_center_offset
	SpawnManagerGlobal.nav_snap_radius = nav_snap_radius
	
	# Transfere configurações de Grid Sampling
	SpawnManagerGlobal.grid_sample_spacing = grid_sample_spacing
	SpawnManagerGlobal.debug_draw_enabled = debug_draw_enabled
	
	# Inicia o spawning
	SpawnManagerGlobal.start_spawning()
	
	print("✅ SpawnManagerConfig: Sistema de spawn inicializado!")
	print("   Max Enemies: ", max_enemies)
	print("   Budget/s: ", base_budget_per_second)
	print("   Minimal Budget: ", minimal_budget)
	print("   Enemy Types: ", enemy_definitions.size())
	print("   Teleport: ", "ATIVADO" if teleport_enabled else "DESATIVADO")
	print("   Grid Sampling: ", grid_sample_spacing, "px | Debug: ", "SIM" if debug_draw_enabled else "NÃO")
	print("   Margens: Min(", spawn_margin_min_horizontal, ",", spawn_margin_min_vertical, ") Max(", spawn_margin_max_horizontal, ",", spawn_margin_max_vertical, ")")

# =================================================
# DEBUG OVERLAY
# =================================================
func create_debug_overlay() -> void:
	"""
	Instancia o debug overlay para visualização do Grid Sampling.
	"""
	var overlay_scene = load("uid://bx7n3k9q2wdhs")
	if not overlay_scene:
		push_warning("SpawnManagerConfig: Debug overlay scene não encontrada!")
		return
	
	var overlay = overlay_scene.instantiate()
	get_tree().root.add_child(overlay)
	overlay.set_enabled(true)
	
	print("🎨 Debug overlay criado e ativado!")
