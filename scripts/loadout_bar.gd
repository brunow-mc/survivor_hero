extends CanvasLayer

# =================================================
# LOADOUT BAR
# =================================================
# Exibe os ataques e powerups já possuídos pelo Player
# em duas fileiras de slots no topo-direito da tela.
# Atualiza automaticamente a cada novo desbloqueio.
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
	# Coletar TextureRects de cada slot na ordem da cena
	for slot in attack_slots.get_children():
		attack_icons.append(slot.get_node("Icon"))

	for slot in powerup_slots.get_children():
		powerup_icons.append(slot.get_node("Icon"))

	# Conectar ao sinal de upgrade aplicado
	LevelUpManagerGlobal.upgrade_applied.connect(_on_upgrade_applied)

	# Aguardar um frame para garantir que Player e controllers estejam prontos
	await get_tree().process_frame
	_initialize_from_player()

# =================================================
# INICIALIZAÇÃO — lê estado atual do Player
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

	# Preencher slots de ataque já ativos (current_level > 0)
	var attack_index := 0
	for upgrade in attack_controller.attack_upgrades:
		if upgrade.current_level > 0 and attack_index < attack_icons.size():
			var attack_data = attack_controller.find_attack_data(upgrade.attack_id)
			if attack_data and attack_data.icon:
				attack_icons[attack_index].texture = attack_data.icon
			attack_index += 1

	# Preencher slots de powerup já ativos (current_level > 0)
	var powerup_index := 0
	for powerup in powerup_controller.powerups:
		if powerup.current_level > 0 and powerup_index < powerup_icons.size():
			if powerup.icon:
				powerup_icons[powerup_index].texture = powerup.icon
			powerup_index += 1

# =================================================
# ATUALIZAÇÃO — chamado a cada upgrade aplicado
# =================================================
func _on_upgrade_applied(choice: Dictionary) -> void:
	# Apenas novos desbloqueios (0 → 1) ocupam um slot novo
	# Upgrades de itens já possuídos (current_level > 0) não alteram slots
	if choice.current_level != 0:
		return

	if choice.type == "attack":
		_fill_next_empty_slot(attack_icons, choice.icon)
	elif choice.type == "powerup":
		_fill_next_empty_slot(powerup_icons, choice.icon)

# =================================================
# PREENCHE O PRÓXIMO SLOT VAZIO
# =================================================
func _fill_next_empty_slot(icons: Array[TextureRect], icon: Texture2D) -> void:
	for icon_rect in icons:
		if icon_rect.texture == null:
			icon_rect.texture = icon
			return
