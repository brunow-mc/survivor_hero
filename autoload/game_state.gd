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
	return current_state not in [
		GameplayState.PLAYER_DEAD,
		GameplayState.PAUSED,
		GameplayState.UPGRADE,
		GameplayState.CUTSCENE,
		GameplayState.DIALOGUE
	]

# -------------------------------------------------
# RESTART GAME
# -------------------------------------------------
func restart_game() -> void:
	# Seta current_state diretamente (não via set_state) para
	# contornar o guard de PLAYER_DEAD e permitir o reinício.
	get_tree().paused = false
	current_state = GameplayState.COMBAT
	previous_state = GameplayState.COMBAT
	state_changed.emit(current_state)
	if XPManagerGlobal:
		XPManagerGlobal.reset()
	if SpawnManagerGlobal:
		SpawnManagerGlobal.stop_spawning()
	get_tree().reload_current_scene()

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
