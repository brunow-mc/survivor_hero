extends Marker2D
class_name PlayerSpawner

# =================================================
# PLAYER SPAWNER
# =================================================
# Cria o jogador no ponto onde ESTE nó está. Aqui a transformação do nó É o
# dado — diferente do NavmeshMerger, que também é Node2D mas cuja posição é
# ignorada de propósito. Mover este nó no editor muda onde o jogador nasce.
#
# Substitui o jogador escrito à mão na cena. Com isso, "qual personagem" deixa
# de ser edição de cena e passa a ser um valor — lido do PlayerRosterGlobal.
#
# É Marker2D e não Area2D: ele não detecta nada, é lido. Quem detecta o
# jogador é a chamber de troca (chamber.gd), que tem a sua TouchArea.
#
# A criação em si mora em spawn() (estática), usada também pela chamber: um
# único lugar decide como um jogador entra no mundo.
#
# ORDEM NA ÁRVORE: coloque este nó ANTES do SpawnManagerConfig. O
# initialize_spawn_manager() dele chama start_spawning(), que busca o grupo
# "Player" — se o jogador ainda não existir, ele dá push_error e NÃO liga o
# spawn. A ordem errada falha ALTO, não em silêncio.
# =================================================

## Impõe um personagem nesta fase, ignorando a escolha do jogador.
##
## VAZIO é o caso normal: a fase usa o personagem escolhido no
## PlayerRosterGlobal (pelas chambers da safe house). Preencher é para a
## exceção — fase inicial, tutorial, intro, ou fase roteirizada em cima de um
## personagem específico.
##
## Mesma disciplina de dois estados do enemy_spawn_ground_layers: vazio não é
## esquecimento, é a declaração do padrão.
@export var forced_player: PackedScene = null


func _ready() -> void:
	# Um jogador por partida. Se a fase ainda tiver um posto à mão, criar o
	# segundo quebraria tudo que resolve o jogador por grupo (câmera,
	# LevelUpManager, SpawnManager) de forma difícil de ver.
	var existing: Node = get_tree().get_first_node_in_group("Player")
	if existing:
		push_warning(
			"PlayerSpawner: já existe um nó no grupo 'Player' ('%s'). Esta fase provavelmente ainda tem um jogador posto à mão na cena — apague-o, ou haverá dois. Nada foi criado."
			% existing.name
		)
		return

	var scene: PackedScene = forced_player
	if not scene:
		scene = PlayerRosterGlobal.get_selected_player()

	if not scene:
		push_error("PlayerSpawner: nenhuma cena de jogador para criar (forced_player vazio e o PlayerRosterGlobal não devolveu nada).")
		return

	spawn(scene, global_position, self)

	print("🧍 PlayerSpawner: %s (%s) em %s" % [
		scene.resource_path.get_file(),
		"imposto pela fase" if forced_player else "escolhido no roster",
		global_position
	])


## Cria um jogador da cena dada, com os PÉS em `at`. Devolve o jogador.
## Usada por este spawner (início de fase) e pela chamber (troca na safe
## house). `from` é qualquer nó já na árvore — só serve para chegar nela.
static func spawn(scene: PackedScene, at: Vector2, from: Node) -> Node2D:
	# O jogador tem de entrar no YSortContainer, resolvido por grupo —
	# exatamente como o SpawnManagerConfig resolve o pai dos inimigos. Fora
	# dele o z efetivo é 2 em vez de 4, e o jogador renderiza atrás de todo
	# inimigo, permanentemente.
	var parent: Node = from.get_tree().get_first_node_in_group("YSortContainer")
	if not parent:
		parent = from.get_parent()
		push_warning(
			"PlayerSpawner: nenhum nó no grupo 'YSortContainer'. O jogador vai para '%s' e o Y-sort NÃO vai funcionar — ele renderiza atrás de todo inimigo (z efetivo 2 contra 4). Instancie entities/stage_parts/y_sort_container.tscn nesta fase."
			% parent.name
		)

	var player: Node2D = scene.instantiate()

	# add_child ANTES de escrever a posição: o _ready() do jogador roda dentro
	# do add_child, então escrever depois garante que nada sobrescreva o ponto.
	parent.add_child(player)
	player.global_position = at
	return player
