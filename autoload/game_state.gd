extends Node
class_name GameState

signal state_changed(new_state: int)

enum GameplayState {
	COMBAT,
	UPGRADE,
	EXPLORATION,
	DIALOGUE,
	CUTSCENE,
	PAUSED,
	PLAYER_DEAD
}

var current_state: GameplayState = GameplayState.COMBAT
var previous_state: GameplayState = GameplayState.COMBAT

## true do toque na porta de fase até a tela clarear na cena nova. Bloqueia a
## pausa (ver pause_game) e uma segunda troca simultânea.
var _changing_stage: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# -------------------------------------------------
# STATE CONTROL
# -------------------------------------------------
func set_state(new_state: GameplayState) -> void:
	if current_state == new_state:
		return
	# PLAYER_DEAD é um estado terminal — só restart pode sair dele.
	# Impede que qualquer sistema (level up, pausa, etc.)
	# sobrescreva a morte acidentalmente.
	if current_state == GameplayState.PLAYER_DEAD:
		return
	previous_state = current_state
	current_state = new_state
	state_changed.emit(current_state)

# -------------------------------------------------
# PAUSE / RESUME
# -------------------------------------------------
func pause_game() -> void:
	if current_state == GameplayState.PAUSED:
		return
	if current_state == GameplayState.PLAYER_DEAD:
		return
	# Sem pausa durante uma troca de fase. Há um intervalo em que a cena antiga
	# já saiu da árvore e a nova ainda não entrou: não existe menu de pausa no
	# mundo, e o StageConfig da cena nova sobrescreveria PAUSED com o modo dela
	# deixando a árvore pausada — jogo congelado no preto, sem menu. Bloqueado
	# aqui, e não no InputManager, para valer para qualquer caminho de pausa.
	if _changing_stage:
		return
	previous_state = current_state
	current_state = GameplayState.PAUSED
	get_tree().paused = true
	state_changed.emit(current_state)

func resume_game() -> void:
	if current_state != GameplayState.PAUSED:
		return
	current_state = previous_state
	get_tree().paused = false
	state_changed.emit(current_state)

# -------------------------------------------------
# PLAYER DEAD
# -------------------------------------------------
func notify_player_dead() -> void:
	if current_state == GameplayState.PLAYER_DEAD:
		return
	previous_state = current_state
	current_state = GameplayState.PLAYER_DEAD
	state_changed.emit(current_state)

func show_game_over() -> void:
	# v1.4.6: Centraliza o pause do game over no GameStateGlobal.
	# Chamado pelo game_over_menu após o delay de exibição.
	if current_state != GameplayState.PLAYER_DEAD:
		return
	get_tree().paused = true

# -------------------------------------------------
# COMBAT PERMISSION
# -------------------------------------------------
func is_combat_allowed() -> bool:
	# LISTA DE EXCLUSÃO: combate é permitido em tudo que NÃO está aqui.
	# Consequência a lembrar ao criar um estado novo (SHOP, BOSS_INTRO…):
	# ele nasce com combate LIBERADO até alguém acrescentá-lo a esta lista.
	# Foi o que aconteceu com EXPLORATION, declarado no enum e esquecido aqui.
	return current_state not in [
		GameplayState.PLAYER_DEAD,
		GameplayState.PAUSED,
		GameplayState.UPGRADE,
		GameplayState.CUTSCENE,
		GameplayState.DIALOGUE,
		GameplayState.EXPLORATION
	]

# -------------------------------------------------
# RESTART GAME
# -------------------------------------------------
func restart_game() -> void:
	_end_current_scene()
	# Seta current_state diretamente (não via set_state) para
	# contornar o guard de PLAYER_DEAD e permitir o reinício.
	current_state = GameplayState.COMBAT
	previous_state = GameplayState.COMBAT
	state_changed.emit(current_state)
	# Um fade interrompido (restart no meio de uma travessia) deixaria a cena
	# recarregada preta para sempre. Fica FORA de _end_current_scene() de
	# propósito: na troca de fase o preto tem de atravessar a troca.
	if FadeGlobal:
		FadeGlobal.clear()
	get_tree().reload_current_scene()

# -------------------------------------------------
# CHANGE STAGE (troca de fase — porta de fase)
# -------------------------------------------------
## Troca para outra cena de fase. Toda troca de cena é um RECOMEÇO: XP volta
## ao nível 1, spawn para, sons param, retenções somem. Vida cheia e ataques
## zerados vêm de graça — o PlayerSpawner da cena nova cria um jogador novo.
##
## NÃO força COMBAT: quem declara o modo é o StageConfig da cena destino. Só
## limpa PLAYER_DEAD, porque set_state() se recusa a sair dele e o StageConfig
## novo seria recusado.
##
## A SEQUÊNCIA INTEIRA mora aqui, e não na porta — a porta morre junto com a
## cena antiga no meio do caminho, e um autoload sobrevive à troca:
##   bloqueia pausa → retém o jogador → escurece → limpeza → troca de cena →
##   espera a cena nova → clareia → libera o jogador → libera a pausa.
## Com tudo num lugar só, o bloqueio de pausa liga e desliga no mesmo ponto,
## e o futuro fade do restart pode reaproveitar o mesmo caminho.
##
## Durações vêm de quem chama (a porta), como em todo fade.
##
## scene_path: o texto vindo do @export_file da porta (uid://). A cena é
## carregada só agora — nada a carrega antecipadamente.
func change_stage(scene_path: String, fade_out_seconds: float = 0.0, fade_in_seconds: float = 0.0) -> void:
	if _changing_stage:
		return  # uma troca por vez
	_changing_stage = true

	# Retém já na cena antiga, enquanto escurece.
	HoldGlobal.hold(HoldGlobal.TRANSITION, "change_stage (saída)")
	await FadeGlobal.fade_out(fade_out_seconds)

	# A limpeza zera TODAS as retenções (inclusive a de cima). Por isso a
	# retenção da chegada é pedida de novo logo depois.
	_end_current_scene()
	var hold_id: int = HoldGlobal.hold(HoldGlobal.TRANSITION, "change_stage (chegada)")

	if current_state == GameplayState.PLAYER_DEAD:
		current_state = GameplayState.COMBAT
		previous_state = GameplayState.COMBAT
		state_changed.emit(current_state)

	var old_scene: Node = get_tree().current_scene
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("GameState.change_stage(): não foi possível trocar para '%s' (erro %d). A cena atual continua; tela, jogador e pausa liberados." % [scene_path, err])
		HoldGlobal.release(hold_id)
		FadeGlobal.clear()
		_changing_stage = false
		return

	# A troca é adiada pela Godot. Espera até a cena nova estar de fato no
	# lugar — por comparação, e não por contagem de frames, que dependeria de
	# detalhe de versão da engine.
	while get_tree().current_scene == null or get_tree().current_scene == old_scene:
		await get_tree().process_frame

	await FadeGlobal.fade_in(fade_in_seconds)
	HoldGlobal.release(hold_id)
	_changing_stage = false

# -------------------------------------------------
# LIMPEZA COMPARTILHADA (restart_game e change_stage)
# -------------------------------------------------
## Tudo que pertence à cena que está saindo e sobreviveria a ela. Corrigido
## aqui, vale para os dois caminhos de troca de cena.
func _end_current_scene() -> void:
	# 1) SILENCIAR ANTES DE DESPAUSAR. Sons da própria cena — o hit e a morte
	# do jogador, a música da fase — não estão no pool do AudioManager. Se o
	# jogo estava pausado no meio de um deles, despausar o faria tocar de novo
	# pelos milissegundos que a cena antiga ainda vive (a troca só acontece no
	# fim do frame): era o "soluço" do ouch ao reiniciar pelo menu de pausa.
	_silence_scene_audio()
	# Os players do pool são filhos do AudioManager (autoload): sobrevivem à
	# troca e continuariam tocando o som de um ataque que nem existe mais.
	if AudioManagerGlobal:
		AudioManagerGlobal.stop_all_sounds()

	# 2) Só agora despausa.
	get_tree().paused = false

	# 3) Estado de partida que mora em autoloads.
	if XPManagerGlobal:
		XPManagerGlobal.reset()
	if SpawnManagerGlobal:
		SpawnManagerGlobal.stop_spawning()
	# Guarda referências a inimigos da cena que está saindo.
	if TargetTrackerGlobal:
		TargetTrackerGlobal.clear_recent_targets()
	# Um pedido de retenção cujo dono morre com a cena nunca seria devolvido,
	# e o jogador nasceria congelado na cena seguinte.
	if HoldGlobal:
		HoldGlobal.clear()


## Para todo AudioStreamPlayer/2D da cena atual. Pega também os criados por
## código (owned = false), como o audio_hit e o audio_death do PlayerBase. Não
## toca na lógica do som de dano — só garante silêncio na saída da cena.
func _silence_scene_audio() -> void:
	var scene: Node = get_tree().current_scene
	if not scene:
		return
	for player in scene.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	for player in scene.find_children("*", "AudioStreamPlayer2D", true, false):
		player.stop()

# -------------------------------------------------
# PLAYER HEALTH
# -------------------------------------------------
signal player_health_changed(current: float, max: float)

var player_max_health: float = 100.0
var player_health: float = 100.0

func register_player(max_health: float) -> void:
	player_max_health = max_health
	player_health = max_health
	player_health_changed.emit(player_health, player_max_health)

func apply_damage(amount: float) -> void:
	if current_state == GameplayState.PLAYER_DEAD:
		return
	player_health = max(player_health - amount, 0.0)
	player_health_changed.emit(player_health, player_max_health)
	if player_health <= 0:
		notify_player_dead()

func heal(amount: float) -> void:
	if current_state == GameplayState.PLAYER_DEAD:
		return
	var actual_heal := minf(amount, player_max_health - player_health)
	player_health = minf(player_health + amount, player_max_health)
	player_health_changed.emit(player_health, player_max_health)
	print("❤️ Heal: +%.0f HP (%.0f/%.0f)" % [actual_heal, player_health, player_max_health])
