extends AnimatedSprite2D
class_name OcclusionSilhouetteAnimated

# =================================================
# OCCLUSION SILHOUETTE — versão AnimatedSprite2D (inimigos)
# =================================================
# Irmã de OcclusionSilhouette (Sprite2D): mesma ideia, mesmo shader. Copia
# sprite_frames/animation/frame em vez de texture, porque inimigos animam
# por spritesheet num AnimatedSprite2D.
#
# SÓ LIGA SOBRE TILES DA FRENTE (FrontTiles). A detecção por cor acende a
# silhueta com QUALQUER coisa na frente do corpo — no jogador isso é desejado
# (ele nunca se perde na horda), mas numa horda os inimigos se sobrepõem o
# tempo todo pelo Y-sort e a tela se encheria de contornos. Então a cópia
# fica INVISÍVEL (o shader nem roda) a menos que o retângulo da sprite esteja
# sobre algum tile da frente.
#
# Criada por código (EnemyBase._attach_occlusion_silhouette()).
# process_priority alto: copia depois da troca de quadro do frame.
# =================================================

const SILHOUETTE_Z: int = 50

var source: AnimatedSprite2D = null


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

	visible = FrontTiles.rect_touches(get_tree(), _global_sprite_rect())


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
