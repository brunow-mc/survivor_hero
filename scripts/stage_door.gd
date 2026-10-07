extends Area2D
class_name StageDoor

# =================================================
# STAGE DOOR
# =================================================
# Porta de FASE: troca de CENA. Diferente da room_door, que só move o jogador
# dentro da mesma cena.
#
# Trocar de cena é sempre RECOMEÇO (vida cheia, nível 1, só o ataque
# primário) — a limpeza é a de GameStateGlobal.change_stage(). Continuidade só
# existe dentro de uma cena; por isso as duas portas são cenas separadas: uma
# porta de sala configurada por engano como porta de fase apagaria o progresso
# do jogador no meio da fase.
#
# MÃO ÚNICA por natureza: não há porta parceira. Quem chega numa fase nova
# aparece no PlayerSpawner dela.
#
# DESTINO COMO TEXTO (@export_file), não como PackedScene: assim a fase
# destino só é lida do disco quando o jogador toca a porta. Com PackedScene,
# a safe house carregaria junto todas as fases para onde tem porta, e safe
# house ↔ fase apontando uma para a outra seria uma dependência circular que a
# Godot não consegue carregar.
#
# SEQUÊNCIA: toda dentro de GameStateGlobal.change_stage() — bloquear pausa,
# reter, escurecer, trocar, clarear, liberar. Esta porta só detecta o jogador
# e passa o destino e as durações: ela morre junto com a cena antiga no meio
# do caminho, e um autoload sobrevive à troca.
# =================================================

## Cena de fase para onde esta porta leva. Escolha o arquivo .tscn no
## Inspector.
@export_file("*.tscn") var destination: String = ""

## Duração do ESCURECER, ainda na cena atual (segundos).
const FADE_OUT_TIME: float = 0.3

## Duração do CLAREAR, já na cena nova (segundos).
const FADE_IN_TIME: float = 0.3


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_validate_setup()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	if destination.is_empty():
		return  # já avisado em _validate_setup()
	if HoldGlobal.is_held(HoldGlobal.Scope.PLAYER_INPUT):
		return  # já há uma travessia (ou outra retenção) em andamento
	_go()


func _go() -> void:
	print("🚪 StageDoor: '%s' → %s" % [name, destination])
	GameStateGlobal.change_stage(destination, FADE_OUT_TIME, FADE_IN_TIME)


func _validate_setup() -> void:
	if destination.is_empty():
		push_warning("StageDoor '%s': sem destino. Tocar a porta não faz nada. Escolha a cena no campo Destination do Inspector." % name)
		return
	if not ResourceLoader.exists(destination):
		push_warning("StageDoor '%s': o destino '%s' não existe (arquivo apagado ou movido por fora da Godot?). Escolha a cena de novo no Inspector." % [name, destination])
