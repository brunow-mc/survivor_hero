extends AnimatedSprite2D
class_name OcclusionSilhouetteAnimated

# =================================================
# OCCLUSION SILHOUETTE — versão AnimatedSprite2D (inimigos)
# =================================================
# Irmã de OcclusionSilhouette (Sprite2D, jogador): mesma ideia, mesmo shader
# e mesmo material. Copia sprite_frames/animation/frame em vez de texture,
# porque inimigos animam por spritesheet num AnimatedSprite2D.
#
# DIFERENÇA DE PROPÓSITO: só liga sobre TILES DA FRENTE. A detecção por cor
# acende a silhueta com QUALQUER coisa na frente do corpo — no jogador isso é
# desejado (ele nunca se perde na horda), mas numa horda os inimigos se
# sobrepõem o tempo todo pelo Y-sort e a tela se encheria de contornos. Então
# a cópia fica INVISÍVEL (o shader nem roda) a menos que o retângulo da
# sprite esteja sobre algum tile da frente.
#
# "Tile da frente" = tile com z_index >= FRONT_TILE_MIN_Z no TileSet (os
# *_alpha usam z 4; os de trás, 0; os de decoração no Y-sort, 2). Nenhuma
# marcação extra no TileSet.
#
# Criada por código (EnemyBase._attach_occlusion_silhouette()).
# process_priority alto: copia depois da troca de quadro do frame.
# =================================================

const SILHOUETTE_Z: int = 50

## z_index de tile a partir do qual ele conta como "da frente" (desenhado por
## cima das entidades, que ficam em 2 dentro do YSortContainer).
const FRONT_TILE_MIN_Z: int = 4

var source: AnimatedSprite2D = null

# Índice das células "da frente", montado uma vez por cena e compartilhado por
# todos os inimigos: [{ "layer": TileMapLayer, "cells": Dictionary }].
# Tiles são estáticos; ler TileData por célula por inimigo por frame seria
# caro, um Dictionary é uma consulta de hash.
static var _front_index: Array = []
static var _front_index_scene_id: int = 0


func setup(source_sprite: AnimatedSprite2D, silhouette_material: Material) -> void:
	source = source_sprite
	material = silhouette_material


func _ready() -> void:
	z_as_relative = false
	z_index = SILHOUETTE_Z
	process_priority = 100
	_copy_from_source()


func _process(_delta: float) -> void:
	_copy_from_source()


func _copy_from_source() -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree():
		visible = false
		return

	sprite_frames = source.sprite_frames
	if animation != source.animation:
		animation = source.animation
	frame = source.frame
	frame_progress = source.frame_progress
	global_transform = source.global_transform
	centered = source.centered
	offset = source.offset
	flip_h = source.flip_h
	flip_v = source.flip_v
	modulate = source.modulate
	self_modulate = source.self_modulate

	visible = _is_over_front_tile()


# -------------------------------------------------
# TILES DA FRENTE
# -------------------------------------------------
## O retângulo desenhado da sprite toca alguma célula da frente?
func _is_over_front_tile() -> bool:
	var index: Array = _get_front_index(get_tree())
	if index.is_empty():
		return false

	var rect: Rect2 = _global_sprite_rect()
	if rect.size == Vector2.ZERO:
		return false

	for entry in index:
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


## Retângulo global do quadro atual. Une o retângulo com o seu espelho, para
## cobrir flip_h com offset sem depender de detalhe de como a Godot espelha.
func _global_sprite_rect() -> Rect2:
	if not sprite_frames or not sprite_frames.has_animation(animation):
		return Rect2()
	var tex: Texture2D = sprite_frames.get_frame_texture(animation, frame)
	if not tex:
		return Rect2()
	var size: Vector2 = tex.get_size()
	var local := Rect2(offset - size / 2.0 if centered else offset, size)
	local = local.merge(Rect2(Vector2(-local.end.x, local.position.y), size))
	return global_transform * local


## Monta (uma vez por cena) o índice das células da frente de todas as
## TileMapLayer da cena atual.
static func _get_front_index(tree: SceneTree) -> Array:
	var scene: Node = tree.current_scene
	if not scene:
		return []
	if scene.get_instance_id() == _front_index_scene_id:
		return _front_index

	_front_index = []
	_front_index_scene_id = scene.get_instance_id()
	for layer in scene.find_children("*", "TileMapLayer", true, false):
		var tile_layer := layer as TileMapLayer
		if not tile_layer.tile_set:
			continue
		var cells: Dictionary = {}
		for cell in tile_layer.get_used_cells():
			# Célula órfã (fonte removida do TileSet depois de pintada):
			# get_cell_tile_data() nela gera erro C++. Mesma guarda do
			# SpawnManager.
			if not tile_layer.tile_set.has_source(tile_layer.get_cell_source_id(cell)):
				continue
			var data: TileData = tile_layer.get_cell_tile_data(cell)
			if data and data.z_index >= FRONT_TILE_MIN_Z:
				cells[cell] = true
		if not cells.is_empty():
			_front_index.append({ "layer": tile_layer, "cells": cells })
	return _front_index
