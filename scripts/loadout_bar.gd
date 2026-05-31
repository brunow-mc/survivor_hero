extends CanvasLayer

# =================================================
# LOADOUT BAR
# =================================================
# Exibe ataques e powerups possuídos pelo Player.
# Escuta sinais dos controllers diretamente —
# funciona para level up, debug e qualquer fonte futura.
# =================================================

# =================================================
# NODES
# =================================================
@onready var attack_slots: HBoxContainer = $Control/HBoxContainer/AttacksGroup/AttackSlots
@onready var powerup_slots: HBoxContainer = $Control/HBoxContainer/PowerupsGroup/PowerupSlots

# =================================================
# ESTADO
# =================================================
var attack_icons: Array[TextureRect] = []
var powerup_icons: Array[TextureRect] = []

# =================================================
# READY
# =================================================
func _ready() -> void:
	_collect_slots(attack_slots, attack_icons)
	_collect_slots(powerup_slots, powerup_icons)
	show()

	await get_tree().process_frame
	_initialize_from_player()

# =================================================
# COLETA E CONFIGURA SLOTS
# =================================================
func _collect_slots(container: HBoxContainer, icons: Array[TextureRect]) -> void:
	for slot in container.get_children():
		var icon_rect := slot.get_node("Icon") as TextureRect
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
		icons.append(icon_rect)

# =================================================
# INICIALIZAÇÃO — lê estado atual e conecta sinais
# =================================================
func _initialize_from_player() -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ LoadoutBar: Player não encontrado!")
		return

	var attack_controller = player.get_node_or_null("AttackController")
	var powerup_controller = player.get_node_or_null("PowerUpController")

	if not attack_controller or not powerup_controller:
		push_error("❌ LoadoutBar: Controllers não encontrados!")
		return

	# Conectar sinais dos controllers — cobre todas as fontes de desbloqueio
	attack_controller.attack_unlocked.connect(_on_attack_unlocked)
	powerup_controller.powerup_unlocked.connect(_on_powerup_unlocked)

	# Preencher estado inicial (ataques já ativos ao iniciar)
	var attack_index := 0
	for upgrade in attack_controller.attack_upgrades:
		if upgrade.current_level > 0 and attack_index < attack_icons.size():
			var attack_data = attack_controller.find_attack_data(upgrade.attack_id)
			if attack_data and attack_data.icon:
				attack_icons[attack_index].texture = attack_data.icon
			attack_index += 1

	# Powerups começam sempre vazios — sem estado inicial a preencher

# =================================================
# CALLBACKS DOS CONTROLLERS
# =================================================
func _on_attack_unlocked(_attack_id: int, icon: Texture2D) -> void:
	_fill_next_empty_slot(attack_icons, icon)

func _on_powerup_unlocked(_powerup_id: int, icon: Texture2D) -> void:
	_fill_next_empty_slot(powerup_icons, icon)

# =================================================
# PREENCHE O PRÓXIMO SLOT VAZIO
# =================================================
func _fill_next_empty_slot(icons: Array[TextureRect], icon: Texture2D) -> void:
	for icon_rect in icons:
		if icon_rect.texture == null:
			icon_rect.texture = icon
			return
