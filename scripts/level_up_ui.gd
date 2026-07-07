extends CanvasLayer

# ======================================
# ÁUDIO
# ======================================
@export_group("Audio")
@export var level_up_sound: AudioStream
@export var level_up_volume: float = 0.0
@export var level_up_pitch: float = 1.0

# Referências aos botões
@onready var option1: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OptionsContainer/Option1
@onready var option2: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OptionsContainer/Option2
@onready var option3: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OptionsContainer/Option3

# Array de referências para facilitar acesso
var option_buttons: Array[Button] = []

# Dados das opções atuais
var current_options: Array = []

signal option_selected(option_index: int)

func _ready() -> void:
	# Configura process_mode para continuar ativo mesmo com jogo pausado
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Inicialmente invisível
	visible = false

	# Monta array de botões
	option_buttons = [option1, option2, option3]

	# Conecta ao sinal do LevelUpManager
	LevelUpManagerGlobal.upgrade_options_ready.connect(_on_upgrade_options_ready)

func _input(event: InputEvent) -> void:
	"""Bloqueia ESC/Pause quando menu está visível"""
	if not visible:
		return

	# Se menu está visível, consumir input de pause (ESC)
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()

func _on_upgrade_options_ready(options: Array) -> void:
	"""Chamado quando o LevelUpManager prepara as opções de upgrade"""
	current_options = options
	_populate_options()
	_show_menu()

func _populate_options() -> void:
	"""v1.4.0: Preenche botões com dados vindos dos Resources"""
	for i in range(3):
		if i >= current_options.size():
			option_buttons[i].visible = false
			continue

		var option = current_options[i]
		var button = option_buttons[i]
		button.visible = true

		# Referências aos labels
		var name_label = button.get_node("HBoxContainer/TextContainer/NameLabel")
		var desc_label = button.get_node("HBoxContainer/TextContainer/DescLabel")
		var icon_rect = button.get_node("HBoxContainer/IconPlaceholder")

		# Lê display_name e description direto do dicionário
		name_label.text = option.display_name
		desc_label.text = option.description.replace("\\n", "\n")

		# v1.4.4: exibe ícone se disponível
		if option.has("icon") and option.icon != null:
			icon_rect.texture = option.icon
			icon_rect.visible = true
		else:
			icon_rect.texture = null
			icon_rect.visible = false

func _show_menu() -> void:
	"""Exibe o menu (jogo já está pausado pelo LevelUpManager)"""
	if level_up_sound:
		AudioManagerGlobal.play_sound(level_up_sound, level_up_volume, level_up_pitch)

	visible = true

	# Dá foco no primeiro botão para navegação por teclado
	option1.grab_focus()

func _on_option_pressed(option_index: int) -> void:
	"""Chamado quando um botão é clicado"""
	if option_index < 0 or option_index >= current_options.size():
		return

	# Esconde ANTES de emitir: se a escolha conceder outro level
	# (fila implícita), o novo menu reabre sincronamente DURANTE o
	# emit — esconder depois apagaria o menu recém-aberto.
	_hide_menu()

	# Emite sinal com a escolha
	option_selected.emit(option_index)

func _hide_menu() -> void:
	"""Esconde o menu (LevelUpManager vai despausar)"""
	visible = false
