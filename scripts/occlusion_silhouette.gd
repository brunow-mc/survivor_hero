extends Sprite2D
class_name OcclusionSilhouette

# =================================================
# OCCLUSION SILHOUETTE
# =================================================
# Cópia da sprite de uma entidade, desenhada por cima de todo o mundo com o
# shader occlusion_silhouette.gdshader: mostra contorno + miolo leve só onde
# algo cobre o corpo (ver o shader).
#
# Criada POR CÓDIGO pelo dono da sprite, nunca posta à mão: nenhuma cena
# precisa ser editada.
#
# A cada frame copia tudo o que define a imagem desenhada pela sprite
# original. O modulate também: o shader compara cores, e sem copiá-lo o
# piscar vermelho de dano acenderia o contorno no corpo inteiro.
#
# process_priority alto: copia DEPOIS do AnimationPlayer trocar o quadro. Se
# copiasse antes, por um frame a cópia teria o quadro anterior, as cores não
# bateriam e o corpo inteiro "acenderia" a cada troca de quadro.
# =================================================

## Acima dos tiles da frente (z 4) e das entidades (z 2). As
## interfaces ficam acima por estarem em CanvasLayer.
const SILHOUETTE_Z: int = 50

var source: Sprite2D = null

## true = só aparece atrás de TILES DA FRENTE (FrontTiles), nunca por cima de
## outras entidades — itens. false = qualquer coisa na frente — jogador.
var only_over_front_tiles: bool = false


func setup(source_sprite: Sprite2D, silhouette_material: Material, front_tiles_only: bool = false) -> void:
	source = source_sprite
	material = silhouette_material
	only_over_front_tiles = front_tiles_only


func _ready() -> void:
	z_as_relative = false
	z_index = SILHOUETTE_Z
	process_priority = 100
	if only_over_front_tiles:
		# Teste por pixel: só tiles da frente acendem (não outras entidades).
		# O jogador não liga isto — deve mostrar o contorno com inimigos na
		# frente.
		FrontTiles.bind_mask(get_tree(), material)
	_copy_from_source()


func _process(_delta: float) -> void:
	_copy_from_source()


func _copy_from_source() -> void:
	if not is_instance_valid(source):
		visible = false
		return

	visible = source.is_visible_in_tree()
	global_transform = source.global_transform

	texture = source.texture
	centered = source.centered
	offset = source.offset
	flip_h = source.flip_h
	flip_v = source.flip_v
	region_enabled = source.region_enabled
	region_rect = source.region_rect
	hframes = source.hframes
	vframes = source.vframes
	frame = source.frame

	modulate = source.modulate
	self_modulate = source.self_modulate

	if visible and only_over_front_tiles:
		visible = FrontTiles.rect_touches(get_tree(), _global_sprite_rect())


## Retângulo global do quadro atual (considera region e hframes/vframes).
## Une com o espelho, para cobrir flip_h com offset.
func _global_sprite_rect() -> Rect2:
	if not texture:
		return Rect2()
	var size: Vector2 = region_rect.size if region_enabled else texture.get_size()
	size /= Vector2(maxi(hframes, 1), maxi(vframes, 1))
	var local := Rect2(offset - size / 2.0 if centered else offset, size)
	local = local.merge(Rect2(Vector2(-local.end.x, local.position.y), size))
	return global_transform * local
