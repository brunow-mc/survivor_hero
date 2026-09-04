extends Node2D
class_name NavmeshMerger

# =====================================================================
# MALHA DE NAVEGACAO UNIFICADA — v1.0.0
#
# O TileMapLayer cria UMA REGIAO DE NAVEGACAO POR TILE (3762 no
# stage01, ~1 poligono cada). Toda consulta de rota localiza os
# poligonos de inicio e fim por VARREDURA LINEAR sobre todos eles, e
# essa localizacao respondia por 80% do custo da navegacao.
#
# Este no substitui isso por UMA regiao com os poligonos unidos.
# Medido no stage01: 3762 -> 206 poligonos, consulta de 303 -> 19 us,
# e em jogo a navegacao caiu de 39 para 4.3 us por inimigo.
#
# LE O POLIGONO REAL DE CADA TILE, NUNCA A CELULA. Hoje todo tile
# navegavel e o quadrado cheio, entao os dois dariam o mesmo resultado
# — e e por isso que o atalho e perigoso: funcionaria agora e
# quebraria em silencio no primeiro tile com navegacao parcial. Tiles
# quadrados pegam o caminho rapido (retangulos maximais); qualquer
# outra forma entra pela uniao geral, sem tratamento especial.
#
# BAKE EM _enter_tree(): a Godot dispara todos os _enter_tree() da
# arvore ANTES de qualquer _ready(), entao a malha fica pronta antes
# de o SpawnManager iniciar e de qualquer inimigo chamar makepath(),
# independente de onde este no esteja na cena.
#
# COMO REVERTER: trocar 'mode' para PER_TILE. O TileSet nunca e
# tocado — a navegacao por tile volta exatamente como era.
# =====================================================================

enum Mode {
	PER_TILE,  ## Comportamento nativo da Godot: uma regiao por tile.
	MERGED,    ## Uma regiao com os poligonos unidos.
}

@export var mode: Mode = Mode.MERGED
## Imprime um resumo do bake no Output.
@export var log_bake: bool = true
## Consulta rotas de amostra apos o bake e avisa se alguma nao chegar
## ao destino — o sintoma de uma passagem perdida na uniao. Ligar
## depois de EDITAR O CENARIO; deixar desligado no dia a dia.
@export var verify_connectivity: bool = false

const EPS: float = 0.01
const VERIFY_PAIRS: int = 60
const VERIFY_SEED: int = 20260828
const VERIFY_DIST_MIN: float = 150.0
const VERIFY_DIST_MAX: float = 500.0
## Teto de quadros que a verificacao espera pelo servidor. Nao e uma
## espera fixa: ela para assim que o mapa responde (ver _verify).
const VERIFY_SYNC_FRAMES: int = 30

var _region: RID
var _mesh: NavigationPolygon

# =================================================
# CICLO DE VIDA
# =================================================
func _enter_tree() -> void:
	if mode != Mode.MERGED:
		return
	_build()

func _exit_tree() -> void:
	if _region.is_valid():
		NavigationServer2D.free_rid(_region)
		_region = RID()

# =================================================
# CONSTRUCAO
# =================================================
func _build() -> void:
	var t0: int = Time.get_ticks_usec()

	# current_scene ainda nao existe em _enter_tree; a raiz da stage e
	# o owner deste no.
	var root: Node = owner if owner != null else get_parent()
	var layers: Array[TileMapLayer] = _layers_with_navigation(root)
	if layers.is_empty():
		push_warning("NavmeshMerger: nenhuma TileMapLayer com navegação encontrada. A malha unificada não foi construída.")
		return

	var tiles: Dictionary = _read_tile_polygons(layers)
	if tiles["cells"] == 0:
		push_warning("NavmeshMerger: nenhum tile navegável encontrado. A malha unificada não foi construída.")
		return

	# Contornos: quadrados viram poucos retângulos maximais; formas
	# parciais entram como estão.
	var outlines: Array = []
	for group in tiles["squares"]:
		outlines.append_array(_maximal_rectangles(group["cells"], group["layer"]))
	outlines.append_array(tiles["irregular"])

	_mesh = _bake(_union(outlines))
	if _mesh == null:
		push_warning("NavmeshMerger: o bake falhou. A navegação por tile foi mantida.")
		return

	# Só agora desliga a navegação por tile: se algo acima tivesse
	# falhado, o mapa continuaria navegável do jeito nativo.
	for layer in layers:
		layer.navigation_enabled = false

	_region = NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(_region, get_world_2d().get_navigation_map())
	NavigationServer2D.region_set_transform(_region, Transform2D.IDENTITY)
	NavigationServer2D.region_set_navigation_polygon(_region, _mesh)

	if log_bake:
		print("🧭 NavmeshMerger: %d tiles → %d polígonos (%.1fx) em %.1f ms" % [
			tiles["cells"], _mesh.get_polygon_count(),
			float(tiles["polygons"]) / maxf(_mesh.get_polygon_count(), 1.0),
			(Time.get_ticks_usec() - t0) / 1000.0,
		])

	if verify_connectivity:
		_verify()

# =================================================
# LEITURA DOS POLIGONOS REAIS
# Usa vertices+polígonos, não get_outline(): tiles autorados no editor
# do TileSet guardam a forma ali, e a lista de contornos vem vazia.
# =================================================
func _read_tile_polygons(layers: Array[TileMapLayer]) -> Dictionary:
	var squares: Array = []
	var irregular: Array = []
	var cells: int = 0
	var polygons: int = 0

	for layer in layers:
		var half: Vector2 = Vector2(layer.tile_set.tile_size) * 0.5
		var square_cells: Array[Vector2i] = []

		for cell in layer.get_used_cells():
			# Célula órfã (fonte removida do TileSet depois de pintada):
			# get_cell_tile_data() dispararia erro em C++.
			var source_id: int = layer.get_cell_source_id(cell)
			if source_id == -1 or not layer.tile_set.has_source(source_id):
				continue
			var data: TileData = layer.get_cell_tile_data(cell)
			if data == null:
				continue
			var np: NavigationPolygon = data.get_navigation_polygon(0)
			if np == null or np.get_polygon_count() == 0:
				continue

			cells += 1
			polygons += np.get_polygon_count()

			if _is_full_square(np, half):
				square_cells.append(cell)
			else:
				var center: Vector2 = layer.map_to_local(cell)
				var verts: PackedVector2Array = np.get_vertices()
				for i in np.get_polygon_count():
					var pts := PackedVector2Array()
					for idx in np.get_polygon(i):
						pts.append(layer.to_global(center + verts[idx]))
					irregular.append(pts)

		if not square_cells.is_empty():
			squares.append({"layer": layer, "cells": square_cells})

	return {
		"squares": squares,
		"irregular": irregular,
		"cells": cells,
		"polygons": polygons,
	}

## Verdadeiro se o NavigationPolygon cobre o tile inteiro.
func _is_full_square(np: NavigationPolygon, half: Vector2) -> bool:
	var v: PackedVector2Array = np.get_vertices()
	if v.size() != 4:
		return false
	for p in v:
		if absf(absf(p.x) - half.x) > EPS or absf(absf(p.y) - half.y) > EPS:
			return false
	return true

## Todas as camadas cuja TileSet declara navegação. É a MESMA semântica
## de união que o navmesh nativo aplica hoje — por isso é varredura, e
## não uma lista no Inspector. Não confundir com
## SpawnManagerConfig.enemy_spawn_ground_layers, que decide onde os
## inimigos NASCEM, não por onde ANDAM.
func _layers_with_navigation(node: Node) -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	if node == null:
		return out
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		if layer.tile_set != null and layer.tile_set.get_navigation_layers_count() > 0:
			out.append(layer)
	for child in node.get_children():
		out.append_array(_layers_with_navigation(child))
	return out

# =================================================
# RETANGULOS MAXIMAIS (só para tiles quadrados)
# Guloso: estende para a direita o máximo possível, depois para baixo
# enquanto a largura toda estiver livre. Uma sala aberta de 400 tiles
# vira 1 retângulo em vez de 400.
# =================================================
func _maximal_rectangles(cells: Array[Vector2i], layer: TileMapLayer) -> Array:
	var free: Dictionary = {}
	for c in cells:
		free[c] = true

	var sorted_cells: Array[Vector2i] = cells.duplicate()
	sorted_cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)

	var half: Vector2 = Vector2(layer.tile_set.tile_size) * 0.5
	var out: Array = []

	for origin in sorted_cells:
		if not free.has(origin):
			continue

		var width: int = 0
		while free.has(Vector2i(origin.x + width, origin.y)):
			width += 1

		var height: int = 0
		while true:
			var row_ok: bool = true
			for dx in width:
				if not free.has(Vector2i(origin.x + dx, origin.y + height)):
					row_ok = false
					break
			if not row_ok:
				break
			height += 1

		for dy in height:
			for dx in width:
				free.erase(Vector2i(origin.x + dx, origin.y + dy))

		var corner_a: Vector2 = layer.to_global(layer.map_to_local(origin) - half)
		var corner_b: Vector2 = layer.to_global(
			layer.map_to_local(Vector2i(origin.x + width - 1, origin.y + height - 1)) + half
		)
		out.append(PackedVector2Array([
			Vector2(corner_a.x, corner_a.y),
			Vector2(corner_b.x, corner_a.y),
			Vector2(corner_b.x, corner_b.y),
			Vector2(corner_a.x, corner_b.y),
		]))

	return out

# =================================================
# UNIAO
# Acumula contornos, mesclando apenas contra os de caixa envolvente
# sobreposta — sem isso a união seria O(N²) de verdade.
# =================================================
func _union(outlines: Array) -> Array:
	var result: Array = []
	var boxes: Array[Rect2] = []

	for p in outlines:
		var box: Rect2 = _bounds(p)
		var current: PackedVector2Array = p
		var i: int = result.size() - 1
		while i >= 0:
			if boxes[i].grow(1.0).intersects(box):
				var merged: Array = Geometry2D.merge_polygons(current, result[i])
				if merged.size() == 1:
					current = merged[0]
					box = _bounds(current)
					result.remove_at(i)
					boxes.remove_at(i)
			i -= 1
		result.append(current)
		boxes.append(box)

	return result

func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for i in range(1, p.size()):
		r = r.expand(p[i])
	return r

# =================================================
# BAKE
# =================================================
func _bake(outlines: Array) -> NavigationPolygon:
	if not NavigationServer2D.has_method("bake_from_source_geometry_data"):
		push_error("NavmeshMerger: bake_from_source_geometry_data indisponível nesta versão da Godot.")
		return null

	var mesh := NavigationPolygon.new()
	# Raio zero: a geometria tem que sair idêntica à dos tiles. Qualquer
	# valor > 0 encolhe a malha e muda por onde os inimigos passam.
	mesh.agent_radius = 0.0

	var geo := NavigationMeshSourceGeometryData2D.new()
	for o in outlines:
		geo.add_traversable_outline(o)

	NavigationServer2D.bake_from_source_geometry_data(mesh, geo)
	if mesh.get_polygon_count() == 0:
		push_error("NavmeshMerger: o bake produziu 0 polígonos.")
		return null
	return mesh

# =================================================
# VERIFICACAO DE CONECTIVIDADE (opcional)
# Sorteia pares de pontos sobre a malha e confere se cada rota chega
# ao destino. Falha isolada = passagem perdida na união. Falha TOTAL
# quase sempre é a verificação rodando cedo demais — daí a espera
# explícita abaixo.
# =================================================
func _verify() -> void:
	var map: RID = get_world_2d().get_navigation_map()

	# Candidatos: centroides dos polígonos da malha.
	var verts: PackedVector2Array = _mesh.get_vertices()
	var raw := PackedVector2Array()
	for i in _mesh.get_polygon_count():
		var indices: PackedInt32Array = _mesh.get_polygon(i)
		if indices.is_empty():
			continue
		var center := Vector2.ZERO
		for idx in indices:
			center += verts[idx]
		raw.append(center / float(indices.size()))

	if raw.size() < 4:
		push_warning("NavmeshMerger: malha pequena demais para verificar (%d polígonos)." % raw.size())
		return

	# Espera o servidor ATE ELE RESPONDER, em vez de contar quadros.
	# O termômetro é map_get_iteration_id(): é a única consulta legal
	# antes da primeira sincronização (devolve 0 até ela acontecer).
	# Qualquer outra — inclusive map_get_closest_point — dispara erro
	# de motor nesse estado, e foi assim que a sonda anterior quebrou:
	# ela media a temperatura com o termômetro que só funciona depois
	# de haver temperatura.
	# Duas condições, nesta ordem — a primeira apenas TORNA A SEGUNDA
	# LEGAL, e sozinha não basta: o mapa pode ter iterado sem que a
	# nossa região tenha entrado nessa iteração, e aí o snap responde
	# sobre um mapa vazio e devolve o MESMO ponto para todos. Foi assim
	# que os 206 candidatos colapsaram em um e nenhuma dupla sobrou.
	var synced: bool = false
	for attempt in VERIFY_SYNC_FRAMES:
		await get_tree().physics_frame
		if NavigationServer2D.map_get_iteration_id(map) <= 0:
			continue
		if NavigationServer2D.map_get_closest_point(map, raw[0]).distance_to(raw[0]) <= 1.0:
			synced = true
			break

	if not synced:
		push_warning("NavmeshMerger: o mapa de navegação não respondeu após %d quadros (%d regiões registradas). A verificação foi abortada — isto NÃO indica união defeituosa." % [
			VERIFY_SYNC_FRAMES, NavigationServer2D.map_get_regions(map).size()
		])
		return

	# Projeta cada candidato sobre a malha. Um centroide calculado pode
	# cair frações de pixel fora dela; partir de um ponto fora devolve
	# rota vazia e se disfarça de "passagem perdida".
	var points := PackedVector2Array()
	for p in raw:
		points.append(NavigationServer2D.map_get_closest_point(map, p))

	var rng := RandomNumberGenerator.new()
	rng.seed = VERIFY_SEED
	var params := NavigationPathQueryParameters2D.new()
	params.map = map
	var res := NavigationPathQueryResult2D.new()

	var tested: int = 0
	var failures: int = 0
	var attempts: int = 0
	while tested < VERIFY_PAIRS and attempts < VERIFY_PAIRS * 400:
		attempts += 1
		var i: int = rng.randi_range(0, points.size() - 1)
		var j: int = rng.randi_range(0, points.size() - 1)
		if i == j:
			continue
		var d: float = points[i].distance_to(points[j])
		if d < VERIFY_DIST_MIN or d > VERIFY_DIST_MAX:
			continue
		tested += 1
		params.start_position = points[i]
		params.target_position = points[j]
		NavigationServer2D.query_path(params, res)
		var path: PackedVector2Array = res.path
		if path.is_empty() or path[path.size() - 1].distance_to(points[j]) > 32.0:
			failures += 1

	if tested == 0:
		# Sem duplas na faixa quase sempre significa amostra degenerada
		# (pontos colapsados), não cenário estranho. Reporta a dispersão
		# para que a causa apareça em vez de ser adivinhada.
		var spread: Rect2 = _bounds(points)
		push_warning("NavmeshMerger: nenhum par na faixa %d–%d px entre %d pontos espalhados por %.0f×%.0f px. Amostra degenerada — a malha pode não estar visível ao mapa." % [
			int(VERIFY_DIST_MIN), int(VERIFY_DIST_MAX), points.size(), spread.size.x, spread.size.y
		])
	elif failures == tested:
		# Falha TOTAL com o mapa comprovadamente respondendo não é
		# topologia: é defeito da própria verificação. Reporta o estado
		# em vez de acusar a união.
		push_warning("NavmeshMerger: as %d rotas falharam com o mapa já respondendo (%d regiões, %d polígonos). Isto aponta defeito na verificação, NÃO na união — o jogo em si está usando esta malha." % [
			tested, NavigationServer2D.map_get_regions(map).size(), _mesh.get_polygon_count()
		])
	elif failures > 0:
		push_warning("NavmeshMerger: %d de %d rotas não chegaram ao destino. A união pode ter perdido uma passagem — compare com o modo PER_TILE." % [failures, tested])
	elif log_bake:
		print("🧭 NavmeshMerger: conectividade OK (%d rotas verificadas)" % tested)
