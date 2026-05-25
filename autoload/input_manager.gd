extends Node
class_name InputManager


func _ready() -> void:
	# Precisa continuar processando mesmo com o jogo pausado
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	_handle_pause()


func _handle_pause() -> void:
	if GameStateGlobal.current_state == GameStateGlobal.GameplayState.PLAYER_DEAD:
		return

	match GameStateGlobal.current_state:
		GameStateGlobal.GameplayState.PAUSED:
			GameStateGlobal.resume_game()
		_:
			GameStateGlobal.pause_game()
