extends Node
class_name StageConfig

# =================================================
# STAGE CONFIG
# =================================================
# Declara em que GameplayState a fase começa.
#
# POR QUE ISSO EXISTE: o GameStateGlobal é autoload, então o estado
# SOBREVIVE à troca de cena. Sem este nó, uma fase herda o modo da fase
# anterior — sair de uma safe house em EXPLORATION deixaria a próxima fase
# de combate com ataque, dano e XP bloqueados. E a stage01 era COMBAT por
# OMISSÃO (valor inicial da variável no autoload), não por decisão.
#
# Cada fase declara o seu. O valor inicial do autoload passa a ser só rede
# de segurança para cenas que NÃO são fases (menu de título, game over).
# =================================================

## Modo em que esta fase começa.
##
## Exposto com o enum INTEIRO de propósito. A lista não prevê o que o jogo
## vai precisar: além de COMBAT e EXPLORATION, uma fase de intro pode nascer
## em CUTSCENE e uma cena puramente narrativa em DIALOGUE. Estados futuros
## (SHOP, BOSS_INTRO…) aparecem aqui sozinhos, sem tocar neste arquivo.
##
## Três valores são recusados em runtime — ver FORBIDDEN_STATES.
@export var gameplay_state: GameState.GameplayState = GameState.GameplayState.COMBAT

## Estados que uma fase NÃO pode declarar, porque não são "onde o jogo está"
## e sim mecanismos com dono e com saída própria:
##
##   UPGRADE     — pertence ao LevelUpManager, que pausa a árvore e conta com
##                 fechar um menu depois. Uma fase nascida aqui não tem menu
##                 para fechar: a árvore ficaria pausada sem UI nenhuma.
##   PAUSED      — pause_game() faz DUAS coisas: muda o enum E pausa a árvore.
##                 Declarar pelo set_state() faria só a primeira, e o jogo
##                 ficaria "pausado" rodando. resume_game() também só sai
##                 daqui se já estiver aqui.
##   PLAYER_DEAD — terminal. O próprio set_state() se recusa a sair dele; só
##                 restart_game() sai. Uma fase nascida morta travaria.
##
## DIALOGUE e CUTSCENE ficam PERMITIDOS: nada os possui, nada precisa ser
## fechado, e são modos de abertura plausíveis para uma fase.
## (Tipado como Array[int] porque enum é int — Array[<enum>] não é garantido.)
const FORBIDDEN_STATES: Array[int] = [
	GameState.GameplayState.UPGRADE,
	GameState.GameplayState.PAUSED,
	GameState.GameplayState.PLAYER_DEAD,
]


func _enter_tree() -> void:
	# _enter_tree(), não _ready(): a Godot executa TODOS os _enter_tree()
	# antes de qualquer _ready(), então o modo já está declarado quando o
	# jogador, o AttackController e o SpawnManager começam a funcionar —
	# independente de onde este nó esteja na árvore da fase. Mesma razão do
	# NavmeshMerger. Com _ready(), a correção dependeria da ordem dos nós.
	if gameplay_state in FORBIDDEN_STATES:
		push_warning(
			"StageConfig [%s]: '%s' não pode ser o modo de uma fase — é um mecanismo com dono, não um lugar. Modo NÃO aplicado; a fase segue no estado que já estava. Ver FORBIDDEN_STATES em stage_config.gd."
			% [_stage_name(), GameState.GameplayState.keys()[gameplay_state]]
		)
		return

	# Se o estado atual for PLAYER_DEAD, set_state() recusa por projeto (é
	# terminal). Não há nada a fazer aqui: limpar a morte é papel do
	# restart_game(), que zera o estado ANTES de recarregar a cena.
	GameStateGlobal.set_state(gameplay_state)

	print("🎬 StageConfig [%s]: modo %s" % [
		_stage_name(),
		GameState.GameplayState.keys()[gameplay_state]
	])


func _stage_name() -> String:
	# Nome da CENA que contém este nó, não do nó — é o que identifica a fase
	# no console. Em _enter_tree() o pai já existe; o owner pode não estar
	# resolvido ainda, então cai para o nome do pai.
	if owner and not owner.scene_file_path.is_empty():
		return owner.scene_file_path.get_file()
	var parent := get_parent()
	return parent.name if parent else name
