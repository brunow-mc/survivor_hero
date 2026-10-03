extends Area2D
class_name RoomDoor

# =================================================
# ROOM DOOR
# =================================================
# Porta entre salas da MESMA cena. Tocar a área leva o jogador ao
# ArrivalPoint da porta parceira. Nada é destruído nem recriado: vida, nível,
# poderes e música continuam. (Trocar de CENA é outra coisa — porta de fase,
# que faz o recomeço.)
#
# O mesmo script serve em EXPLORATION e em COMBAT: nada aqui depende do
# GameplayState.
#
# MÃO DUPLA é o padrão: A aponta para B e B aponta para A, cada uma no seu
# próprio campo partner. MÃO ÚNICA = deixar o partner VAZIO na porta de
# chegada: ela continua servindo de ponto de chegada, mas tocá-la não leva a
# lugar nenhum. Vazio é declaração, não esquecimento.
#
# POR QUE O JOGADOR NÃO VOLTA NA HORA: ele chega no ArrivalPoint, que fica
# FORA da área da porta. O Area2D só dispara quando o corpo passa de fora
# para dentro; chegando fora, voltar exige andar até a porta de novo — uma
# entrada nova, legítima. (Mesma solução de A Link to the Past.)
#
# A TRAVESSIA NÃO É INSTANTÂNEA: reter → espera → mover → espera → devolver,
# pelo HoldGlobal (conjunto TRANSITION). O jogador para na porta, reaparece
# do outro lado, e só então volta a responder. Quando o fade existir, ele
# preenche as duas esperas.
#
# A porta IGNORA o jogador enquanto o direcional dele estiver retido: quem não
# pode andar não entra em porta. Isso impede encadear portas e também anula o
# efeito de um ArrivalPoint mal posto — se o jogador chegar dentro da área da
# porta de destino, o toque acontece durante a retenção e é ignorado; ao
# liberar ele já está dentro (não há entrada nova) e precisa sair e voltar.
# O aviso de _validate_setup() continua valendo: a porta não quebra, mas o
# jogador aparece em cima dela.
# =================================================

## Porta para onde esta leva. Só aceita outra RoomDoor.
##
## VAZIO = esta porta é só ponto de chegada (mão única).
@export var partner: RoomDoor = null

## Folga ao redor da área ao verificar o ArrivalPoint. O ponto marca os PÉS do
## jogador (a origem da cena dele), mas o colisor do jogador tem tamanho: um
## ponto 1px fora da área ainda deixaria o corpo sobreposto e dispararia a
## porta. Valor aproximado — o aviso é rede de segurança, não medida exata.
const ARRIVAL_CLEARANCE: float = 6.0

## Quanto o jogador fica parado na porta ANTES de ser movido (segundos).
## Com o fade, vira a duração do escurecer.
const HOLD_BEFORE_MOVE: float = 0.25

## Quanto o jogador fica parado do outro lado DEPOIS de chegar (segundos).
## Com o fade, vira a duração do clarear.
const HOLD_AFTER_MOVE: float = 0.25


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_validate_setup()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	if not partner:
		return  # mão única: esta porta só recebe
	if HoldGlobal.is_held(HoldGlobal.Scope.PLAYER_INPUT):
		return  # já há uma travessia (ou outra retenção) em andamento
	_cross(body)


func _cross(body: Node2D) -> void:
	var hold_id := HoldGlobal.hold(HoldGlobal.TRANSITION, "RoomDoor '%s'" % name)

	# As esperas também tiram o movimento de dentro do callback da física
	# (onde o toque chegou), que é onde a Godot prefere não ver corpos mexendo.
	await get_tree().create_timer(HOLD_BEFORE_MOVE, false).timeout
	if is_instance_valid(body) and is_instance_valid(partner):
		body.global_position = partner.get_arrival_position()
		print("🚪 RoomDoor: '%s' → '%s'" % [name, partner.name])

	await get_tree().create_timer(HOLD_AFTER_MOVE, false).timeout
	HoldGlobal.release(hold_id)


## Onde o jogador aparece ao chegar POR esta porta. Lido pela porta parceira.
func get_arrival_position() -> Vector2:
	var marker := get_node_or_null("ArrivalPoint") as Marker2D
	if marker:
		return marker.global_position
	# Sem marcador o jogador cairia dentro da própria área desta porta.
	# O aviso disso sai uma vez, em _validate_setup().
	return global_position


# =================================================
# VALIDAÇÃO (na inicialização, uma vez por porta)
# =================================================
func _validate_setup() -> void:
	if partner == self:
		push_warning("RoomDoor '%s': o partner aponta para ela mesma. Tocar a porta devolveria o jogador ao próprio ArrivalPoint." % name)

	var marker := get_node_or_null("ArrivalPoint") as Marker2D
	if not marker:
		push_warning("RoomDoor '%s': sem filho 'ArrivalPoint'. Quem chegar por esta porta aparece no centro dela, DENTRO da área." % name)
		return

	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not shape_node or not (shape_node.shape is RectangleShape2D):
		return  # só sabemos verificar retângulo; outras formas passam sem checagem

	# Leva o ArrivalPoint para o espaço local da forma (respeita posição e
	# rotação dela) e testa contra o retângulo crescido pela folga.
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var local_point: Vector2 = shape_node.global_transform.affine_inverse() * marker.global_position
	var area := Rect2(-size / 2.0, size).grow(ARRIVAL_CLEARANCE)
	if area.has_point(local_point):
		push_warning("RoomDoor '%s': o ArrivalPoint está dentro (ou a até %.0fpx) da área da própria porta. Quem chegar por ela aparece em cima da porta e precisa sair e voltar para usá-la. Afaste-o para dentro da sala." % [name, ARRIVAL_CLEARANCE])
