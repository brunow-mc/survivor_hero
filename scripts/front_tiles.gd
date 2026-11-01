class_name FrontTiles

# =================================================
# FRONT TILES
# =================================================
# Responde "este retângulo está atrás de algum tile da frente?". Usado pelas
# silhuetas que só devem aparecer atrás de cenário — inimigos e itens —, e
# não por cima de outras entidades.
#
# "Tile da frente" = tile com z_index >= MIN_Z no TileSet (os *_alpha usam
# z 4; os de trás, 0; os de decoração no Y-sort, 2). Nenhuma marcação extra
# no TileSet.
#
# As células da frente são indexadas UMA VEZ por cena num Dictionary
# compartilhado (estático): tiles são estáticos, e ler TileData por célula
# por entidade por frame seria caro; um Dictionary é uma consulta de hash.
# O índice é refeito quando current_scene muda. Montá-lo custa ler toda
# célula usada — uma vez, na primeira consulta da cena.
# =================================================

## z_index de tile a partir do qual ele conta como "da frente" (desenhado por
## cima das entidades, que ficam em 2 dentro do YSortContainer).
const MIN_Z: int = 4

# [{ "layer": TileMapLayer, "cells": Dictionary }]
static var _index: Array = []
static var _index_scene_id: int = 0


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
	return _index
