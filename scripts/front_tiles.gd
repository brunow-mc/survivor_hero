class_name FrontTiles

# =================================================
# FRONT TILES
# =================================================
# Responde "isto está atrás de algum tile da frente?". Usado pelas silhuetas
# que só devem aparecer atrás de cenário — inimigos e itens —, e não por cima
# de outras entidades.
#
# "Tile da frente" = tile com z_index >= MIN_Z no TileSet (os *_alpha usam
# z 4; os de trás, 0; os de decoração no Y-sort, 2). Nenhuma marcação extra
# no TileSet.
#
# DUAS PRECISÕES, as duas montadas UMA VEZ por cena (tiles são estáticos):
#   - rect_touches(): o retângulo da sprite toca alguma célula da frente?
#     Liga/desliga a cópia inteira (fora dos prédios o shader nem roda).
#   - MAPA DE CÉLULAS (bind_mask): uma imagem com 1 pixel por célula
#     (1 = tile da frente), entregue ao shader. Cada pixel do corpo só vira
#     silhueta se a cor da tela diferir E ele estiver numa célula da frente.
#     Sem isso, um item meio atrás do prédio ligava a cópia inteira, e um
#     inimigo passando pela metade APARENTE também a acendia — a cor não diz
#     O QUE está na frente.
#
# Precisão do mapa: a célula (16 px), não o desenho do tile. Supõe todas as
# camadas na mesma grade (mesmo tile_size, sem deslocamento entre elas) —
# verdadeiro hoje.
#
# O índice é refeito quando current_scene muda. Montá-lo custa ler toda
# célula usada — uma vez, na primeira consulta da cena.
# =================================================

## z_index de tile a partir do qual ele conta como "da frente" (desenhado por
## cima das entidades, que ficam em 2 dentro do YSortContainer).
const MIN_Z: int = 4

# [{ "layer": TileMapLayer, "cells": Dictionary }]
static var _index: Array = []
static var _index_scene_id: int = 0

# Mapa de células para o shader (coordenadas de MUNDO).
static var _mask_texture: ImageTexture = null
static var _mask_origin: Vector2 = Vector2.ZERO      # canto da célula (0,0) do mapa, em px de mundo
static var _mask_cell_size: Vector2 = Vector2(16, 16)
static var _mask_size_cells: Vector2 = Vector2.ONE


## O retângulo GLOBAL toca alguma célula da frente?
static func rect_touches(tree: SceneTree, rect: Rect2) -> bool:
	if rect.size == Vector2.ZERO:
		return false
	for entry in _get_index(tree):
		var layer: TileMapLayer = entry["layer"]
		if not is_instance_valid(layer):
			continue
		var cells: Dictionary = entry["cells"]
		var a: Vector2i = layer.local_to_map(layer.to_local(rect.position))
		var b: Vector2i = layer.local_to_map(layer.to_local(rect.end))
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				if cells.has(Vector2i(x, y)):
					return true
	return false


## Entrega o mapa de células da cena atual ao material (liga use_front_mask).
## Chamado por cada cópia "só atrás de cenário" ao nascer; numa cena nova o
## mapa é refeito antes. O material é compartilhado por todas as cópias do
## mesmo tipo, e os parâmetros só mudam em memória — o .tres em disco segue
## com use_front_mask = false.
static func bind_mask(tree: SceneTree, mat: Material) -> void:
	var shader_mat := mat as ShaderMaterial
	if not shader_mat:
		return
	_get_index(tree)
	if not _mask_texture:
		# Cena sem tiles da frente: nada pode acender (a cópia nem liga,
		# rect_touches() é sempre falso). Desliga o teste por pixel.
		shader_mat.set_shader_parameter("use_front_mask", false)
		return
	shader_mat.set_shader_parameter("front_mask", _mask_texture)
	shader_mat.set_shader_parameter("mask_origin", _mask_origin)
	shader_mat.set_shader_parameter("mask_cell_size", _mask_cell_size)
	shader_mat.set_shader_parameter("mask_size_cells", _mask_size_cells)
	shader_mat.set_shader_parameter("use_front_mask", true)


static func _get_index(tree: SceneTree) -> Array:
	var scene: Node = tree.current_scene
	if not scene:
		return []
	if scene.get_instance_id() == _index_scene_id:
		return _index

	_index = []
	_index_scene_id = scene.get_instance_id()
	for node in scene.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if not layer.tile_set:
			continue
		var cells: Dictionary = {}
		for cell in layer.get_used_cells():
			# Célula órfã (fonte removida do TileSet depois de pintada):
			# get_cell_tile_data() nela gera erro C++. Mesma guarda do
			# SpawnManager.
			if not layer.tile_set.has_source(layer.get_cell_source_id(cell)):
				continue
			var data: TileData = layer.get_cell_tile_data(cell)
			if data and data.z_index >= MIN_Z:
				cells[cell] = true
		if not cells.is_empty():
			_index.append({ "layer": layer, "cells": cells })

	_build_mask()
	return _index


## Monta a imagem do mapa de células, em coordenadas de MUNDO (todas as
## camadas juntas na mesma grade).
static func _build_mask() -> void:
	_mask_texture = null
	if _index.is_empty():
		return

	var first_layer: TileMapLayer = _index[0]["layer"]
	_mask_cell_size = Vector2(first_layer.tile_set.tile_size)

	# Células de mundo: centro da célula de cada camada → índice na grade.
	var world_cells: Array[Vector2i] = []
	var min_c := Vector2i(1 << 30, 1 << 30)
	var max_c := Vector2i(-(1 << 30), -(1 << 30))
	for entry in _index:
		var layer: TileMapLayer = entry["layer"]
		if Vector2(layer.tile_set.tile_size) != _mask_cell_size:
			push_warning("FrontTiles: a camada '%s' usa tile_size diferente de '%s'. O mapa de células da silhueta supõe uma grade só; os tiles da frente dela podem ficar imprecisos." % [layer.name, first_layer.name])
		for cell in entry["cells"]:
			var world_center: Vector2 = layer.to_global(layer.map_to_local(cell))
			var wc := Vector2i((world_center / _mask_cell_size).floor())
			world_cells.append(wc)
			min_c = Vector2i(mini(min_c.x, wc.x), mini(min_c.y, wc.y))
			max_c = Vector2i(maxi(max_c.x, wc.x), maxi(max_c.y, wc.y))

	var size := max_c - min_c + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	for wc in world_cells:
		image.set_pixelv(wc - min_c, Color.WHITE)

	_mask_texture = ImageTexture.create_from_image(image)
	_mask_origin = Vector2(min_c) * _mask_cell_size
	_mask_size_cells = Vector2(size)
