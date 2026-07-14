extends CanvasLayer

@export var game_over_delay: float = 2.5

@onready var restart_btn: Button = $CenterContainer/VBoxContainer/Restart_Btn
@onready var main_menu_btn: Button = $CenterContainer/VBoxContainer/MainMenu_Btn
@onready var quit_btn: Button = $CenterContainer/VBoxContainer/Quit_Btn


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GameStateGlobal.state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(state: int) -> void:
	if state == GameStateGlobal.GameplayState.PLAYER_DEAD:
		_show_game_over_delayed()
	else:
		visible = false


func _show_game_over_delayed() -> void:
	await get_tree().create_timer(game_over_delay, false).timeout

	visible = true
	GameStateGlobal.show_game_over()  # v1.4.6: via GameStateGlobal em vez de get_tree().paused diretamente
	restart_btn.grab_focus()


# ------------------------
# BUTTONS
# ------------------------

func _on_restart_btn_pressed() -> void:
	GameStateGlobal.restart_game()


func _on_main_menu_btn_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("uid://dfacry0fayx68")


func _on_quit_btn_pressed() -> void:
	get_tree().quit()
