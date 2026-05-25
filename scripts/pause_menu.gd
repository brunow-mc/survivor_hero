extends CanvasLayer

@onready var resume_btn: Button = $Menu_Holder/Resume_Btn
@onready var reload_timer: Timer = $Reload_Timer


func _ready() -> void:
	# Precisa continuar ativo mesmo com o jogo pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Escuta mudanças de estado do jogo
	GameStateGlobal.state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(state: int) -> void:
	visible = state == GameStateGlobal.GameplayState.PAUSED

	if visible:
		resume_btn.grab_focus()


func _on_resume_btn_pressed() -> void:
	GameStateGlobal.resume_game()


func _on_restart_btn_pressed() -> void:
	reload_timer.start()


func _on_reload_timer_timeout() -> void:
	GameStateGlobal.restart_game()


func _on_quit_btn_pressed() -> void:
	get_tree().quit()
