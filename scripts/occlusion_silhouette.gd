extends Sprite2D
class_name OcclusionSilhouette

# =================================================
# OCCLUSION SILHOUETTE
# =================================================
# Cópia da sprite de uma entidade, desenhada por cima de todo o mundo com o
# shader occlusion_silhouette.gdshader: mostra contorno + miolo leve só onde
# algo cobre o corpo (ver o shader).
#
# Criada POR CÓDIGO (PlayerBase), nunca posta à mão: nenhuma cena de
# personagem precisa ser editada, e personagens futuros ganham o efeito.
#
# A cada frame copia tudo o que define a imagem desenhada pela sprite
# original. O modulate também: o shader compara cores, e sem copiá-lo o
# piscar vermelho de dano acenderia o contorno no corpo inteiro.
#
# process_priority alto: copia DEPOIS do AnimationPlayer trocar o quadro. Se
# copiasse antes, por um frame a cópia teria o quadro anterior, as cores não
# bateriam e o corpo inteiro "acenderia" a cada troca de quadro.
# =================================================

## Acima dos tiles da frente (z 4) e das entidades (z efetivo 4). As
## interfaces ficam acima por estarem em CanvasLayer.
const SILHOUETTE_Z: int = 50

var source: Sprite2D = null


func setup(source_sprite: Sprite2D, silhouette_material: Material) -> void:
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
