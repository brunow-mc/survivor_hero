@tool
extends Node2D
class_name Chamber

# =================================================
# CHAMBER (troca de personagem)
# =================================================
# Câmara envidraçada da safe house com um personagem dentro. Tocar uma
# chamber ATIVA troca o personagem: retém, escurece, troca no escuro (o novo
# surge no ExitPoint desta chamber), clareia, libera.
#
# UMA cena para todos os personagens: as chambers diferem só em DADOS (qual
# personagem, quais imagens, bloqueada ou não), configurados por instância
# no Inspector. Valor posto numa instância fica só nela.
#
# TRÊS ESTADOS, nesta prioridade:
#   SELECTED — é o personagem escolhido agora → imagem vazia, toque ignorado
#   LOCKED   — bloqueada                      → imagem de bloqueada, toque ignorado
#   ACTIVE   — o resto                        → imagem do personagem, toque troca
#
# @tool MÍNIMO: no editor ela só desenha a própria imagem (bloqueada ou
# normal), para a montagem da sala não ser às cegas. Toda lógica de jogo fica
# atrás de Engine.is_editor_hint() — no editor os autoloads não existem.
# Lições da barrier aplicadas: o Sprite2D é procurado DENTRO da função (nunca
# @onready, que pode ficar null no editor) e nenhum recurso compartilhado é
# alterado — só a textura que o Sprite2D desta instância mostra.
#
# TROCA SÓ É LEGAL EM CENA SEM INIMIGOS: inimigos guardam o BodyCenter do
# jogador e o SpawnManager guarda o jogador; trocar numa fase de combate
# deixaria os dois apontando para um nó liberado. Avisado no _ready.
#
# A safe house nunca deve usar forced_player no PlayerSpawner: a imagem vazia
# mostra a escolha do PlayerRosterGlobal, e um personagem imposto pela fase
# deixaria a chamber mentindo sobre quem está em jogo.
# =================================================

enum State { ACTIVE, LOCKED, SELECTED }

## Duração do ESCURECER antes da troca (segundos).
const FADE_OUT_TIME: float = 0.7

## Duração do CLAREAR depois da troca (segundos). É também a hesitação do
## personagem novo: a retenção segura o jogador e o início dos ataques até
## a tela clarear (HoldGlobal.SCENE_ARRIVAL).
const FADE_IN_TIME: float = 0.7

## Folga mínima entre o ExitPoint e a TouchArea desta chamber (px). Margem
## aproximada para o colisor dos pés do personagem.
const EXIT_CLEARANCE: float = 6.0

@export_group("Player")
## Personagem que esta chamber contém e entrega ao ser tocada.
@export var player_scene: PackedScene

@export_group("Lock")
## Bloqueada: mostra a imagem de bloqueada e ignora o toque. Lido SÓ por
## _is_locked() — no futuro a verdade vem do save, via PlayerRosterGlobal.
@export var locked: bool = false:
	set(value):
		locked = value
		_refresh_visual()

@export_group("Visual")
## Imagem com o personagem dentro (chamber ativa).
@export var texture_unlocked: Texture2D:
	set(value):
		texture_unlocked = value
		_refresh_visual()

## Imagem com o personagem em preto e branco (chamber bloqueada).
@export var texture_locked: Texture2D:
	set(value):
		texture_locked = value
		_refresh_visual()

## Imagem da câmara vazia (o personagem escolhido saiu dela).
@export var texture_empty: Texture2D:
	set(value):
		texture_empty = value
		_refresh_visual()


func _ready() -> void:
	_refresh_visual()
	if Engine.is_editor_hint():
		return

	_validate_setup()

	var touch_area := get_node_or_null("TouchArea") as Area2D
	if touch_area:
		touch_area.body_entered.connect(_on_body_entered)

	PlayerRosterGlobal.selected_player_changed.connect(_on_selected_player_changed)


# -------------------------------------------------
# ESTADO
# -------------------------------------------------
func _current_state() -> State:
	if PlayerRosterGlobal.is_selected(player_scene):
		return State.SELECTED
	if _is_locked():
		return State.LOCKED
	return State.ACTIVE


## ÚNICO lugar que responde "está bloqueada?". Hoje lê o Inspector; quando
## existir save, passa a perguntar ao PlayerRosterGlobal (ex.:
## not PlayerRosterGlobal.is_unlocked(player_scene)) — o desbloqueio acontece
## longe daqui (vencer uma fase), então a verdade vai morar no roster.
func _is_locked() -> bool:
	return locked


# -------------------------------------------------
# VISUAL
# -------------------------------------------------
func _refresh_visual() -> void:
	# Procurado aqui, nunca por @onready: no editor um setter pode rodar antes
	# dos filhos existirem.
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if not sprite:
		return

	var texture: Texture2D
	if Engine.is_editor_hint():
		# Montagem: "quem está escolhido" é pergunta de partida, não de
		# editor — nunca mostra a vazia aqui.
		texture = texture_locked if locked else texture_unlocked
	else:
		match _current_state():
			State.SELECTED:
				texture = texture_empty
			State.LOCKED:
				texture = texture_locked
			_:
				texture = texture_unlocked

	if texture:
		sprite.texture = texture


func _on_selected_player_changed(_scene: PackedScene) -> void:
	_refresh_visual()


# -------------------------------------------------
# TOQUE E TROCA
# -------------------------------------------------
func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	if not player_scene:
		return  # já avisado em _validate_setup()
	# Quem não pode andar não troca: impede encadear chambers e ignora o
	# toque que acontece durante a própria troca.
	if HoldGlobal.is_held(HoldGlobal.Scope.PLAYER_INPUT):
		return
	if _current_state() != State.ACTIVE:
		return
	_swap(body)


func _swap(old_player: Node2D) -> void:
	print("🧪 Chamber '%s': troca para %s" % [name, player_scene.resource_path.get_file()])

	# SCENE_ARRIVAL, e não só TRANSITION: o personagem novo também hesita —
	# os ataques dele só começam quando a tela clarear.
	var ticket: int = HoldGlobal.hold(HoldGlobal.SCENE_ARRIVAL, "chamber %s" % name)
	await FadeGlobal.fade_out(FADE_OUT_TIME)

	# No escuro. Escolher primeiro: o sinal faz TODAS as chambers trocarem de
	# imagem aqui (esta fica vazia, a do anterior volta a mostrá-lo).
	PlayerRosterGlobal.select_player(player_scene)

	# Sair do grupo ANTES de liberar: queue_free() só remove no fim do frame,
	# e quem procura o "Player" agora (câmera, ferramentas de teste do novo)
	# acharia o antigo.
	if is_instance_valid(old_player):
		old_player.remove_from_group("Player")
		old_player.queue_free()

	var exit_point := get_node_or_null("ExitPoint") as Node2D
	var at: Vector2 = exit_point.global_position if exit_point else global_position
	PlayerSpawner.spawn(player_scene, at, self)

	await FadeGlobal.fade_in(FADE_IN_TIME)
	HoldGlobal.release(ticket)


# -------------------------------------------------
# VALIDAÇÃO (só avisa, nunca quebra)
# -------------------------------------------------
func _validate_setup() -> void:
	if not player_scene:
		push_warning("Chamber '%s': sem Player Scene. Tocar não faz nada. Escolha o personagem no Inspector." % name)
	if not texture_unlocked or not texture_locked or not texture_empty:
		push_warning("Chamber '%s': falta imagem em Visual (unlocked, locked ou empty). A chamber pode mostrar a imagem errada." % name)

	if GameStateGlobal.current_state == GameState.GameplayState.COMBAT:
		push_warning("Chamber '%s': esta cena está em COMBAT. Trocar de personagem só é legal em cena SEM inimigos (eles guardam referência ao jogador)." % name)

	var exit_point := get_node_or_null("ExitPoint") as Node2D
	if not exit_point:
		push_warning("Chamber '%s': sem ExitPoint. O personagem novo vai surgir na base da chamber." % name)
		return

	var touch_area := get_node_or_null("TouchArea") as Area2D
	if not touch_area:
		push_warning("Chamber '%s': sem TouchArea. Tocar não faz nada." % name)
		return

	for child in touch_area.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var size: Vector2 = child.shape.size
			var rect := Rect2(touch_area.position + child.position - size / 2.0, size).grow(EXIT_CLEARANCE)
			if rect.has_point(exit_point.position):
				push_warning("Chamber '%s': ExitPoint dentro ou a menos de %.0f px da TouchArea. Afaste-o (Filhos Editáveis na instância)." % [name, EXIT_CLEARANCE])
