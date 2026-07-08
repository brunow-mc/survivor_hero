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

# Dedup: ids já exibidos. Necessário porque desbloqueios via level up
# chegam por DUAS rotas — upgrade_applied (síncrono, durante a pausa)
# e attack_unlocked/powerup_unlocked (polling, após despausar).
var filled_attack_ids: Dictionary = {}
var filled_powerup_ids: Dictionary = {}

# =================================================
# READY
# =================================================
func _ready() -> void:
	_collect_slots(attack_slots, attack_icons)
	_collect_slots(powerup_slots, powerup_icons)
	show()

	# Rota síncrona: atualiza a barra DURANTE a pausa do menu de upgrade
	# (menus encadeados da fila implícita). O polling do AttackController
	# só emite attack_unlocked após despausar — tarde demais para a UI.
	LevelUpManagerGlobal.upgrade_applied.connect(_on_upgrade_applied)

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
			filled_attack_ids[upgrade.attack_id] = true
			attack_index += 1

	# Powerups começam sempre vazios — sem estado inicial a preencher

# =================================================
# CALLBACK DO LEVEL UP MANAGER (rota síncrona)
# =================================================
func _on_upgrade_applied(choice: Dictionary) -> void:
	# Só desbloqueios novos (next_level 1); upgrades de level e
	# bonus (First Aid) não mexem em slots.
	if choice.next_level != 1:
		return

	match choice.type:
		"attack":
			_fill_next_empty_slot(attack_icons, filled_attack_ids, choice.id, choice.icon)
		"powerup":
			_fill_next_empty_slot(powerup_icons, filled_powerup_ids, choice.id, choice.icon)

# =================================================
# CALLBACKS DOS CONTROLLERS (debug e fontes futuras)
# =================================================
func _on_attack_unlocked(attack_id: int, icon: Texture2D) -> void:
	_fill_next_empty_slot(attack_icons, filled_attack_ids, attack_id, icon)

func _on_powerup_unlocked(powerup_id: int, icon: Texture2D) -> void:
	_fill_next_empty_slot(powerup_icons, filled_powerup_ids, powerup_id, icon)

# =================================================
# PREENCHE O PRÓXIMO SLOT VAZIO (com dedup por id)
# =================================================
func _fill_next_empty_slot(icons: Array[TextureRect], filled_ids: Dictionary, id: int, icon: Texture2D) -> void:
	if filled_ids.has(id):
		return

	for icon_rect in icons:
		if icon_rect.texture == null:
			icon_rect.texture = icon
			filled_ids[id] = true
			return
