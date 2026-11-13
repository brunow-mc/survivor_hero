extends Node2D

## =================================================
## DEBUG DRAW OVERLAY
## =================================================
## Desenha o Grid Sampling do spawn: os pontos candidatos, a área da tela e
## as faixas mínima e máxima de spawn.
##
## Desenha NO MUNDO, e não numa CanvasLayer presa à tela: os pontos chegam em
## coordenadas de mundo e são desenhados como estão, então a câmera aplica
## zoom e posição sozinha. Afastar a câmera mostra a área de spawn inteira, e
## não há atraso de um quadro entre o desenho e o mundo.
## =================================================

## Acima de tudo na folha do mundo, inclusive dos poderes (60+). Absoluto, para
## não depender de onde o nó for colocado.
const OVERLAY_Z: int = 100

# Dados recebidos do SpawnManager
var clusters: Array = []
var margin_min_h: float = 50.0
var margin_min_v: float = 50.0
var margin_max_h: float = 200.0
var margin_max_v: float = 150.0

# Configuração
var enabled: bool = false
## Raio dos pontos, em pixels de TELA (não muda com o zoom).
var point_size: float = 2.0

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
	z_as_relative = false
	z_index = OVERLAY_Z

	if SpawnManagerGlobal and not SpawnManagerGlobal.debug_data_updated.is_connected(_on_debug_data_updated):
		SpawnManagerGlobal.debug_data_updated.connect(_on_debug_data_updated)

	print("🎨 Debug Overlay criado!")

# =================================================
# PROCESS
# =================================================
func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()

# =================================================
# DRAW
# =================================================
func _draw() -> void:
	if not enabled:
		return

	# Desenha em coordenadas de MUNDO, seja qual for a transformação deste nó.
	draw_set_transform_matrix(get_global_transform().affine_inverse())

	# Zoom da câmera: espessuras e raios divididos por ele ficam constantes na tela.
	var camera: Camera2D = get_viewport().get_camera_2d()
	var zoom: float = camera.zoom.x if camera else 1.0
	var radius: float = point_size / zoom

	# 1. Pontos dos clusters, onde estão no mundo.
	if not cluster_colors.is_empty():
		for i in range(clusters.size()):
			var color: Color = cluster_colors[i % cluster_colors.size()]
			for point in clusters[i]:
				draw_circle(point, radius, color)

	if not camera:
		return

	# 2. Retângulos, calculados no momento do desenho a partir da câmera.
	var center: Vector2 = camera.get_screen_center_position()
	var half_view: Vector2 = get_viewport_rect().size / 2.0 / camera.zoom

	# Área visível (branco)
	draw_rect(Rect2(center - half_view, half_view * 2.0), Color.WHITE, false, 3.0 / zoom)

	# Faixa mínima: dentro dela não nasce inimigo (verde)
	var min_half: Vector2 = half_view + Vector2(margin_min_h, margin_min_v)
	draw_rect(Rect2(center - min_half, min_half * 2.0), Color.GREEN, false, 2.0 / zoom)

	# Faixa máxima: limite externo do spawn (vermelho)
	var max_half: Vector2 = half_view + Vector2(margin_max_h, margin_max_v)
	draw_rect(Rect2(center - max_half, max_half * 2.0), Color.RED, false, 2.0 / zoom)

# =================================================
# CALLBACKS
# =================================================
func _on_debug_data_updated(data: Dictionary) -> void:
	clusters = data.get("clusters", [])
	margin_min_h = data.get("margin_min_h", 50.0)
	margin_min_v = data.get("margin_min_v", 50.0)
	margin_max_h = data.get("margin_max_h", 200.0)
	margin_max_v = data.get("margin_max_v", 150.0)

# =================================================
# CONTROLE
# =================================================
func set_enabled(value: bool) -> void:
	enabled = value
	queue_redraw()
