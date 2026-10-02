extends Node

# =================================================
# PLAYER ROSTER
# =================================================
# Quem está disponível e quem está escolhido.
#
# POR QUE É UM AUTOLOAD PRÓPRIO, e não uma variável no GameStateGlobal: o
# critério é TEMPO DE VIDA. O GameStateGlobal é o estado da PARTIDA (vida,
# FSM), e o restart_game() é documentado como o único lugar que limpa estado
# entre sessões. Nada daqui deve ser limpo: morrer e reiniciar não troca o seu
# personagem, e desbloqueio vai para arquivo de save. Guardar isto lá
# funcionaria hoje e criaria a armadilha de quem acrescentar algo ao
# restart_game() ter de lembrar de NÃO limpar estas linhas.
#
# Nomeado pelo PAPEL (o elenco), não pelo mecanismo: "PlayerSelection"
# envelheceria no dia em que o desbloqueio entrar.
#
# É AQUI que o desbloqueio de personagens vai morar.
# =================================================

## Personagem usado quando ninguém escolheu nada — o caso de apertar F5 direto
## na stage01, sem passar pela safe house.
##
## É um padrão de PROJETO, não de fase. Uma fase que precise impor um
## personagem (tutorial, intro, fase roteirizada) usa o forced_player do
## PlayerSpawner dela, e não este valor.
const DEFAULT_PLAYER: PackedScene = preload("uid://cefydgegqsrfo")  # uid = entities/players/major_heat.tscn

## Personagem escolhido. Escrito pela estátua da safe house (ainda não
## construída) e lido pelo PlayerSpawner de cada fase.
var selected_player: PackedScene = DEFAULT_PLAYER


func select_player(scene: PackedScene) -> void:
	if not scene:
		push_warning(
			"PlayerRoster: select_player() recebeu null. Escolha NÃO alterada; segue %s."
			% _name_of(selected_player)
		)
		return

	selected_player = scene
	print("🧍 PlayerRoster: personagem escolhido — %s" % _name_of(scene))


func get_selected_player() -> PackedScene:
	# Nunca devolve null: o PlayerSpawner não tem o que fazer com isso, e cair
	# no padrão é melhor que uma fase sem jogador.
	if selected_player:
		return selected_player

	push_warning("PlayerRoster: selected_player estava vazio; usando o DEFAULT_PLAYER.")
	return DEFAULT_PLAYER


func _name_of(scene: PackedScene) -> String:
	return scene.resource_path.get_file() if scene else "<nada>"
