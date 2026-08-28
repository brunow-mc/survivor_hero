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

## Reserva de budget com que a partida COMEÇA (one-shot: consumida uma vez,
## depois o ritmo volta ao normal; não mexe na taxa base nem na dificuldade).
## Quanto maior, mais cheio o início:
##   0            = começo frio (espera acumular do zero).
##   0 < x < min  = adianta o 1º spawn (reduz a espera inicial).
##   x >= min     = já cruza o limiar e dispara uma rajada de abertura.
## (min = minimal_budget.)
@export var initial_budget: float = 0.0

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
## Container onde os inimigos spawnados são adicionados (o YSortContainer do
## stage). Entidades só participam do Y-sort se forem FILHAS do node com
## y_sort_enabled.
##
## OPCIONAL — deixe VAZIO no caso normal: o container é resolvido sozinho pelo
## grupo "YSortContainer", que vem marcado na cena base (logo toda instância em
## qualquer stage já nasce nele). Preencha apenas como OVERRIDE explícito, por
## exemplo num stage com mais de um container.
@export var enemy_container: Node2D

# =================================================
# TELEPORT SYSTEM
# =================================================
# TELEPORT SYSTEM
# =================================================
@export_group("Teleport System")
## Habilitar teleporte de inimigos distantes
@export var teleport_enabled: bool = true

## Distância HORIZONTAL máxima do player antes de teleportar (px).
## Separado do vertical porque a tela é retangular (480x270): a área de
## spawn é mais larga que alta, então uma distância única serviria mal aos
## dois eixos. Deve ficar MAIOR que a borda externa de spawn desse eixo
## (meia tela + spawn_margin_max_horizontal), senão o inimigo já nasce
## elegível a teleporte.
@export var max_distance_from_player_horizontal: float = 430.0

## Distância VERTICAL máxima do player antes de teleportar (px).
## Mesma regra: > meia tela + spawn_margin_max_vertical.
@export var max_distance_from_player_vertical: float = 325.0

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

## Camadas onde inimigos PODEM NASCER.
##
## VAZIO = toda camada da cena que tenha polígono de navegação é elegível.
## Esse é um padrão declarado, não um esquecimento — é o caso normal.
##
## PREENCHIDO = só as camadas listadas geram spawn. Serve para EXCLUIR uma
## área do spawn sem excluí-la da navegação (inimigos continuam podendo
## ANDAR nela: quem move inimigo é o navmesh, que não passa por aqui).
##
## ATENÇÃO: listar uma camada NÃO declara que ela é toda navegável — declara
## apenas "consulte esta camada". Quem decide é cada tile, pelo seu polígono
## de navegação. Por isso uma camada mista como TileMapBuildings (tiles de
## colisão + tiles de navegação) entra sem problema: só os tiles com
## polígono são aceitos.
@export var enemy_spawn_ground_layers: Array[TileMapLayer] = []

## Raio de captura do snap ao chão navegável (px)
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
	# [TEMPORARIO — PERF PROBE] remover junto com scripts/perf_probe.gd.
	# Instanciado por class_name (sem uid nem caminho) porque e codigo
	# descartavel e nao deve criar referencia a arquivo.
	var perf_probe := PerfProbe.new()
	perf_probe.name = "PerfProbe"
	get_tree().root.add_child.call_deferred(perf_probe)

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
	SpawnManagerGlobal.initial_budget = initial_budget
	
	# Transfere margens retangulares
	SpawnManagerGlobal.spawn_margin_min_horizontal = spawn_margin_min_horizontal
	SpawnManagerGlobal.spawn_margin_min_vertical = spawn_margin_min_vertical
	SpawnManagerGlobal.spawn_margin_max_horizontal = spawn_margin_max_horizontal
	SpawnManagerGlobal.spawn_margin_max_vertical = spawn_margin_max_vertical
	SpawnManagerGlobal.offscreen_safety_margin = offscreen_safety_margin
	
	SpawnManagerGlobal.difficulty_increase_per_minute = difficulty_increase_per_minute
	SpawnManagerGlobal.max_difficulty_multiplier = max_difficulty_multiplier
	SpawnManagerGlobal.enemy_definitions = enemy_definitions

	# Resolve o container Y-sort: export (override explícito) → grupo → nada.
	# O grupo está marcado na CENA BASE do YSortContainer, então nenhum stage
	# precisa de fiação manual — o que elimina o erro silencioso de esquecer
	# de arrastar (sem container, os inimigos caem na raiz da cena, com z
	# efetivo menor que o do player, e o player renderiza sempre na frente).
	var container: Node2D = enemy_container
	if not is_instance_valid(container):
		container = get_tree().get_first_node_in_group("YSortContainer") as Node2D

	if not is_instance_valid(container):
		push_warning("SpawnManagerConfig: nenhum container Y-sort encontrado — o export 'Enemy Container' está vazio E não há nó no grupo 'YSortContainer'. Os inimigos vão para a raiz da cena e o Y-sort player↔inimigos não vai funcionar.")

	SpawnManagerGlobal.enemy_container = container
	
	# Transfere configurações de teleport
	SpawnManagerGlobal.teleport_enabled = teleport_enabled
	SpawnManagerGlobal.max_distance_from_player_horizontal = max_distance_from_player_horizontal
	SpawnManagerGlobal.max_distance_from_player_vertical = max_distance_from_player_vertical
	SpawnManagerGlobal.teleport_check_interval = teleport_check_interval
	SpawnManagerGlobal.max_teleports_per_frame = max_teleports_per_frame
	
	# Transfere configurações de validação
	SpawnManagerGlobal.min_distance_between_enemies = min_distance_between_enemies
	SpawnManagerGlobal.min_distance_from_walls = min_distance_from_walls
	SpawnManagerGlobal.body_center_offset = body_center_offset
	SpawnManagerGlobal.nav_snap_radius = nav_snap_radius

	# Resolve o chão de spawn: DOIS estados, nenhum deles é "esquecimento".
	#   export preenchido -> só essas camadas
	#   export vazio      -> varre a cena (tudo com navegação é elegível)
	# Não existe caminho por grupo: um único lugar decide, e ele é visível
	# no Inspector.
	var nav_layers: Array[TileMapLayer] = []
	var quebradas: int = 0

	for layer in enemy_spawn_ground_layers:
		if is_instance_valid(layer):
			nav_layers.append(layer)
		else:
			# Slot vazio. Duas origens, mesmo resultado: alguém adicionou uma
			# linha no array sem atribuir nada, ou a camada foi APAGADA.
			# (Renomear ou mover NÃO cai aqui: o editor reescreve o NodePath
			# sozinho. Editar o .tscn fora da Godot, sim.)
			# Nunca é escolha, sempre é erro de cena — e sem este aviso o
			# jogo rodaria calado com menos áreas de spawn.
			quebradas += 1

	if quebradas > 0:
		push_warning("SpawnManagerConfig: %d de %d entradas de 'Enemy Spawn Ground Layers' estão vazias (slot sem camada atribuída, ou a camada foi apagada da cena). O spawn vai rodar com %d camada(s) — atribua ou remova as linhas vazias no Inspector." % [
			quebradas, enemy_spawn_ground_layers.size(), nav_layers.size()
		])

	if nav_layers.is_empty():
		# Padrão declarado, não falha: sem lista, todo chão navegável serve.
		# Camadas sem polígono de navegação são descartadas de graça depois.
		_collect_tilemap_layers(get_tree().current_scene, nav_layers)

	SpawnManagerGlobal.enemy_spawn_ground_layers = nav_layers
	SpawnManagerGlobal.invalidate_nav_layer_cache()
	
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
	print("   Chão de spawn: ", nav_layers.map(func(l): return l.name),
		" (lista explícita)" if not enemy_spawn_ground_layers.is_empty() else " (cena inteira)")

## Usado quando o export está vazio: coleta toda TileMapLayer da cena.
## Camadas sem navegação são descartadas de graça pelo SpawnManager.
func _collect_tilemap_layers(node: Node, out: Array[TileMapLayer]) -> void:
	if not node:
		return
	if node is TileMapLayer:
		out.append(node as TileMapLayer)
	for child in node.get_children():
		_collect_tilemap_layers(child, out)

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
