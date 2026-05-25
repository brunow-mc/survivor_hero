extends Node2D

## =================================================
## DEBUG DRAWER
## =================================================
## Node2D child que faz o desenho real do debug.
## Desenha RETÂNGULOS (mínimo e máximo) ao invés de círculos.
## =================================================

# Dados para desenhar (atualizados pelo parent)
var clusters: Array = []
var player_position: Vector2 = Vector2.ZERO
var camera_position: Vector2 = Vector2.ZERO
var margin_min_h: float = 50.0
var margin_min_v: float = 50.0
var margin_max_h: float = 200.0
var margin_max_v: float = 150.0
var cluster_colors: Array = []
var point_size: float = 6.0

# =================================================
# DRAW
# =================================================
func _draw() -> void:
	if clusters.is_empty():
		return
	
	var viewport_size: Vector2 = get_viewport_rect().size
	
	# =========================================
	# 1. DESENHA PONTOS DOS CLUSTERS
	# =========================================
	for i in range(clusters.size()):
		var cluster: Array = clusters[i]
		if cluster_colors.is_empty():
			continue
		
		var color: Color = cluster_colors[i % cluster_colors.size()]
		
		# Desenha cada ponto do cluster
		for point in cluster:
			# Converte coordenadas globais para tela
			var screen_pos: Vector2 = point - camera_position + viewport_size / 2
			draw_circle(screen_pos, point_size, color)
	
	# =========================================
	# 2. RETÂNGULO DA TELA (Branco - Grosso)
	# =========================================
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	draw_rect(viewport_rect, Color.WHITE, false, 3.0)
	
	# =========================================
	# 3. RETÂNGULO MÍNIMO (Verde - Zona proibida)
	# =========================================
	# Calcula posição em coordenadas de tela
	var min_rect_top_left: Vector2 = Vector2(
		-margin_min_h,
		-margin_min_v
	)
	var min_rect_size: Vector2 = Vector2(
		viewport_size.x + 2 * margin_min_h,
		viewport_size.y + 2 * margin_min_v
	)
	var min_rect: Rect2 = Rect2(min_rect_top_left, min_rect_size)
	draw_rect(min_rect, Color.GREEN, false, 2.0)
	
	# =========================================
	# 4. RETÂNGULO MÁXIMO (Vermelho - Limite externo)
	# =========================================
	var max_rect_top_left: Vector2 = Vector2(
		-margin_max_h,
		-margin_max_v
	)
	var max_rect_size: Vector2 = Vector2(
		viewport_size.x + 2 * margin_max_h,
		viewport_size.y + 2 * margin_max_v
	)
	var max_rect: Rect2 = Rect2(max_rect_top_left, max_rect_size)
	draw_rect(max_rect, Color.RED, false, 2.0)
