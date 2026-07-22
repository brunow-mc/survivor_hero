extends Camera2D

## =================================================
## CAMERA
## =================================================
## Segue o CENTRO DO CORPO do player (BodyCenter), não a origem da cena —
## a origem fica nos PÉS (convenção feet origin), e segui-la deixaria o
## player renderizado ~11px abaixo do centro da tela.
##
## Roda em _physics_process porque o player se move em _physics_process
## (CharacterBody2D + move_and_slide): seguir no frame de render amostraria
## posições entre passos de física.
## =================================================

var target: Node2D = null

func _ready() -> void:
	_acquire_target()

func _physics_process(_delta: float) -> void:
	# Reaquisição: o alvo pode ainda não existir no _ready (quando houver um
	# sistema de spawn/seleção de player, o player nasce depois da câmera) ou
	# ter sido liberado. Sem alvo, a câmera simplesmente fica parada.
	if not is_instance_valid(target):
		_acquire_target()
		if not is_instance_valid(target):
			return

	# global_position dos DOIS lados: a câmera e o player não compartilham
	# pai (Camera é filha do stage, player é filho do YSortContainer), então
	# usar `position` local só funciona enquanto os dois pais estiverem na
	# origem — acoplamento acidental que quebraria em silêncio.
	global_position = _target_body_position()

func _acquire_target() -> void:
	target = get_tree().get_first_node_in_group("Player") as Node2D

func _target_body_position() -> Vector2:
	# Acessor canônico do PlayerBase; fallback defensivo para a origem caso
	# o alvo não seja um PlayerBase.
	if target.has_method("get_body_center_position"):
		return target.get_body_center_position()
	return target.global_position
