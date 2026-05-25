extends CanvasLayer

## =================================================
## DEBUG DRAW OVERLAY
## =================================================
## Desenha visualização debug do Grid Sampling.
## CanvasLayer contém um Node2D child que faz o desenho real.
## =================================================

# Node2D child que faz o desenho
var drawer: Node2D = null

# Dados recebidos do SpawnManager
var clusters: Array = []
var player_position: Vector2 = Vector2.ZERO
var camera_position: Vector2 = Vector2.ZERO
var margin_min_h: float = 50.0
var margin_min_v: float = 50.0
var margin_max_h: float = 200.0
var margin_max_v: float = 150.0

# Configuração
var enabled: bool = false
var point_size: float = 6.0

# Cores para clusters
var cluster_colors: Array = [
	Color.GREEN,
	Color.CYAN,
	Color.YELLOW,
	Color.MAGENTA,
	Color.ORANGE,
	Color.LIGHT_BLUE,
	Color.PINK,
	Color.LIME_GREEN
]

# =================================================
# READY
# =================================================
func _ready() -> void:
	# Cria Node2D child para desenhar
	drawer = Node2D.new()
	drawer.set_script(preload("res://scripts/debug_drawer.gd"))
	add_child(drawer)
	
	# Conecta ao SpawnManager
	if SpawnManagerGlobal:
		SpawnManagerGlobal.debug_data_updated.connect(_on_debug_data_updated)
	
	print("🎨 Debug Overlay criado!")

# =================================================
# PROCESS
# =================================================
func _process(_delta: float) -> void:
	if enabled and drawer:
		# Atualiza dados do drawer
		drawer.clusters = clusters
		drawer.player_position = player_position
		drawer.camera_position = camera_position
		drawer.margin_min_h = margin_min_h
		drawer.margin_min_v = margin_min_v
		drawer.margin_max_h = margin_max_h
		drawer.margin_max_v = margin_max_v
		drawer.cluster_colors = cluster_colors
		drawer.point_size = point_size
		drawer.queue_redraw()

# =================================================
# CALLBACKS
# =================================================
func _on_debug_data_updated(data: Dictionary) -> void:
	"""
	Recebe dados do SpawnManager.
	"""
	clusters = data.get("clusters", [])
	player_position = data.get("player_position", Vector2.ZERO)
	camera_position = data.get("camera_position", Vector2.ZERO)
	margin_min_h = data.get("margin_min_h", 50.0)
	margin_min_v = data.get("margin_min_v", 50.0)
	margin_max_h = data.get("margin_max_h", 200.0)
	margin_max_v = data.get("margin_max_v", 150.0)

# =================================================
# CONTROLE
# =================================================
func set_enabled(value: bool) -> void:
	enabled = value
	if drawer:
		drawer.queue_redraw()
