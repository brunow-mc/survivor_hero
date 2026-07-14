extends Node
class_name LevelUpManager

# =================================================
# LEVEL UP MANAGER - v1.3.28 FASE 2
# =================================================

# -------------------------------------------------
# UI
# -------------------------------------------------
const LEVEL_UP_UI_SCENE = preload("uid://c4lqh8k7mjxwb")
var level_up_ui: CanvasLayer = null

# -------------------------------------------------
# SIGNALS
# -------------------------------------------------
signal upgrade_options_ready(options: Array[Dictionary])
signal upgrade_applied(upgrade_data: Dictionary)

# -------------------------------------------------
# FIRST AID
# -------------------------------------------------
## Quantidade de HP recuperada pelo First Aid.
## Capped no Max Health do Player (lógica em GameStateGlobal.heal).
var heal_amount: float = 20.0

## Ícone exibido no botão de First Aid no menu de level up.
var heal_icon: Texture2D = preload("uid://cvpdyr5mb78vr")

# -------------------------------------------------
# CONFIGURAÇÃO DE PESOS (preparado para FASE 4)
# -------------------------------------------------
@export_group("Weight System")
@export var common_weight: float = 1.0
@export var uncommon_weight: float = 0.7
@export var rare_weight: float = 0.3
@export var epic_weight: float = 0.1

@export_group("Options")
@export var options_count: int = 3

## Até esse level, garante ao menos 1 ataque nas opções.
@export var early_game_threshold: int = 3

## Máximo de ataques que o Player pode desbloquear.
@export var attack_capacity: int = 5

## Máximo de powerups que o Player pode desbloquear.
@export var powerup_capacity: int = 5

# -------------------------------------------------
# ESTADO
# -------------------------------------------------
var current_options: Array[Dictionary] = []
var is_waiting_for_choice: bool = false

# -------------------------------------------------
# READY
# -------------------------------------------------
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if XPManagerGlobal:
		XPManagerGlobal.level_up.connect(_on_level_up)
		print("✅ LevelUpManager: Conectado ao XPManagerGlobal")
	else:
		push_error("❌ LevelUpManager: XPManagerGlobal não encontrado!")

	level_up_ui = LEVEL_UP_UI_SCENE.instantiate()
	add_child(level_up_ui)
	level_up_ui.option_selected.connect(_on_ui_option_selected)

# =================================================
# LEVEL UP
# =================================================
func _on_level_up(new_level: int) -> void:
	# Barreira final: não exibe menu com player morto.
	# A cadeia deveria ter sido barrada antes (xp_item → xp_manager),
	# mas este guard garante que o estado PLAYER_DEAD não seja sobrescrito.
	if GameStateGlobal.current_state == GameStateGlobal.GameplayState.PLAYER_DEAD:
		return

	print("🎉 LEVEL UP! Nível %d — abrindo menu de upgrade" % new_level)

	is_waiting_for_choice = true

	GameStateGlobal.set_state(GameStateGlobal.GameplayState.UPGRADE)
	get_tree().paused = true

	current_options = generate_upgrade_options(new_level)
	upgrade_options_ready.emit(current_options)

# =================================================
# GERAR OPÇÕES - v1.4.0 FASE 3
# =================================================
func generate_upgrade_options(level: int) -> Array[Dictionary]:
	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ LevelUpManager: Player não encontrado!")
		return []

	var attack_controller = player.get_node_or_null("AttackController")
	var powerup_controller = player.get_node_or_null("PowerUpController")

	if not attack_controller:
		push_error("❌ LevelUpManager: AttackController não encontrado!")
		return []

	if not powerup_controller:
		push_error("❌ LevelUpManager: PowerUpController não encontrado!")
		return []

	# Contar desbloqueados para verificar capacidade
	var unlocked_attacks := 0
	for upgrade_data in attack_controller.attack_upgrades:
		if upgrade_data and upgrade_data.current_level > 0:
			unlocked_attacks += 1

	var unlocked_powerups := 0
	for powerup_data in powerup_controller.powerups:
		if powerup_data and powerup_data.current_level > 0:
			unlocked_powerups += 1

	var attacks_full := unlocked_attacks >= attack_capacity
	var powerups_full := unlocked_powerups >= powerup_capacity

	if attacks_full:
		print("🔒 Ataques: %d/%d — novos desbloqueios bloqueados" % [unlocked_attacks, attack_capacity])
	if powerups_full:
		print("🔒 Powerups: %d/%d — novos desbloqueios bloqueados" % [unlocked_powerups, powerup_capacity])

	# Montar pool de upgrades disponíveis
	var attack_pool: Array[Dictionary] = []
	var powerup_pool: Array[Dictionary] = []

	for upgrade_data in attack_controller.attack_upgrades:
		if not upgrade_data:
			continue
		if upgrade_data.current_level >= upgrade_data.max_level:
			continue
		if attacks_full and upgrade_data.current_level == 0:
			continue

		var next_level = upgrade_data.current_level + 1
		attack_pool.append({
			"type": "attack",
			"id": upgrade_data.attack_id,
			"name": upgrade_data.attack_name,
			"current_level": upgrade_data.current_level,
			"next_level": next_level,
			"display_name": upgrade_data.get_display_name_for_level(next_level),
			"description": upgrade_data.get_description_for_level(next_level),
			"icon": attack_controller.find_attack_data(upgrade_data.attack_id).icon if attack_controller.find_attack_data(upgrade_data.attack_id) else null
		})

	for powerup_data in powerup_controller.powerups:
		if not powerup_data:
			continue
		if powerup_data.current_level >= powerup_data.max_level:
			continue
		if powerups_full and powerup_data.current_level == 0:
			continue

		var next_level = powerup_data.current_level + 1
		powerup_pool.append({
			"type": "powerup",
			"id": powerup_data.powerup_id,
			"name": powerup_data.powerup_name,
			"current_level": powerup_data.current_level,
			"next_level": next_level,
			"display_name": powerup_data.get_display_name_for_level(next_level),
			"description": powerup_data.get_description_for_level(next_level),
			"icon": powerup_data.icon
		})

	var pool: Array[Dictionary] = attack_pool + powerup_pool

	# Pool vazio → First Aid como única opção
	if pool.size() == 0:
		print("❤️ Nenhum upgrade disponível — oferecendo First Aid")
		return [_make_heal_option()]

	var max_options = min(options_count, pool.size())
	var options: Array[Dictionary] = []

	# Early game — garante ao menos 1 ataque até early_game_threshold
	if level <= early_game_threshold and attack_pool.size() > 0:
		attack_pool.shuffle()
		options.append(attack_pool[0])

		var remaining: Array[Dictionary] = []
		for item in pool:
			if item != options[0]:
				remaining.append(item)
		remaining.shuffle()

		for i in range(max_options - 1):
			if i < remaining.size():
				options.append(remaining[i])
	else:
		pool.shuffle()
		for i in range(max_options):
			options.append(pool[i])

	return options

# =================================================
# FIRST AID
# =================================================
func _make_heal_option() -> Dictionary:
	return {
		"type": "bonus",
		"id": 0,
		"name": "First Aid",
		"current_level": 0,
		"next_level": 0,
		"display_name": "First Aid",
		"description": "RECOVER +%d HP." % int(heal_amount),
		"icon": heal_icon
	}

# =================================================
# APLICAR UPGRADE
# =================================================
func apply_upgrade(choice_index: int) -> void:
	if choice_index < 0 or choice_index >= current_options.size():
		push_error("❌ Índice de escolha inválido: %d" % choice_index)
		return

	var choice = current_options[choice_index]

	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ Player não encontrado!")
		return

	_apply_upgrade(player, choice)

	upgrade_applied.emit(choice)

	is_waiting_for_choice = false
	current_options.clear()

	# FILA IMPLÍCITA: avisa o XPManager que o menu foi resolvido.
	# Se a sobra de XP conceder outro level, um novo menu abre
	# SINCRONAMENTE dentro desta chamada (via level_up →
	# _on_level_up), e is_waiting_for_choice volta a true.
	# Nesse caso, NÃO despausa — o jogo segue em UPGRADE.
	XPManagerGlobal.upgrade_selected()
	if is_waiting_for_choice:
		return

	GameStateGlobal.set_state(GameStateGlobal.GameplayState.COMBAT)
	get_tree().paused = false

# =================================================
# APLICAR UPGRADE - v1.3.26 | v1.3.27
# =================================================
func _apply_upgrade(_player: Node, choice: Dictionary) -> void:
	if choice.type == "bonus":
		GameStateGlobal.heal(heal_amount)
		return

	var controller_name = "AttackController" if choice.type == "attack" else "PowerUpController"

	if not _player.has_node(controller_name):
		push_error("❌ %s não encontrado no player!" % controller_name)
		return

	var controller = _player.get_node(controller_name)
	var level_before = _get_current_level(controller, choice)
	var success = controller.apply_upgrade(choice.id)

	if success:
		var action = "desbloqueado" if level_before == 0 else "upado"
		var type_emoji = "⚔️" if choice.type == "attack" else "⭐"
		print("%s %s %s!" % [type_emoji, choice.name, action])
	else:
		push_warning("⚠️ Falha ao aplicar upgrade: %s" % choice.name)


func _get_current_level(controller: Node, choice: Dictionary) -> int:
	if choice.type == "attack":
		var upgrade = controller.find_upgrade(choice.id)
		return upgrade.current_level if upgrade else 0
	else:
		var powerup = controller.get_powerup(choice.id)
		return powerup.current_level if powerup else 0

# =================================================
# UI CALLBACK
# =================================================
func _on_ui_option_selected(option_index: int) -> void:
	apply_upgrade(option_index)

# =================================================
# SIMULAÇÃO (DEBUG)
# =================================================
func simulate_choice(choice_index: int) -> void:
	if not is_waiting_for_choice:
		print("⚠️ Não há escolha pendente no momento")
		return
	print("🎲 Simulando escolha %d (debug)" % (choice_index + 1))
	apply_upgrade(choice_index)

# =================================================
# GETTERS
# =================================================
func is_upgrade_active() -> bool:
	return is_waiting_for_choice

func get_current_options() -> Array[Dictionary]:
	return current_options.duplicate()
