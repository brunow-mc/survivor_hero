extends Node
class_name LevelUpManager

# =================================================
# LEVEL UP MANAGER - v1.3.28 FASE 2
# =================================================
# Orquestra o sistema de level up:
# - Escuta XPManagerGlobal.level_up
# - Gera opções de upgrade (ataques + powerups)
# - Muda para GameplayState.UPGRADE
# - Exibe UI visual com 3 opções
# =================================================

# -------------------------------------------------
# UI
# -------------------------------------------------
const LEVEL_UP_UI_SCENE = preload("res://ui/level_up_ui.tscn")
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
var heal_icon: Texture2D = preload("res://sprites/icons/bonus_icons/first_aid.png")

# -------------------------------------------------
# CONFIGURAÇÃO DE PESOS (preparado para FASE 4)
# -------------------------------------------------
@export_group("Weight System")
@export var common_weight: float = 1.0      ## Peso para upgrades comuns
@export var uncommon_weight: float = 0.7    ## Peso para upgrades incomuns
@export var rare_weight: float = 0.3        ## Peso para upgrades raros
@export var epic_weight: float = 0.1        ## Peso para upgrades épicos

@export_group("Options")
@export var options_count: int = 3          ## Quantas opções oferecer por level up

## Até esse level, garante ao menos 1 ataque nas opções.
## 0 = desligado. @export mantido para futura config por cena.
@export var early_game_threshold: int = 3

## Máximo de ataques que o Player pode desbloquear.
## Upgrades de ataques já possuídos continuam disponíveis após o limite.
@export var attack_capacity: int = 5

## Máximo de powerups que o Player pode desbloquear.
## Upgrades de powerups já possuídos continuam disponíveis após o limite.
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

	print("✅ LevelUpManager: UI instanciada e conectada")

# =================================================
# LEVEL UP
# =================================================
func _on_level_up(new_level: int) -> void:
	print("\n" + "=".repeat(50))
	print("🎉 LEVEL UP DETECTADO!")
	print("=".repeat(50))
	print("📊 Novo Level: %d" % new_level)
	print("⏸️ Pausando jogo...")

	is_waiting_for_choice = true

	GameStateGlobal.set_state(GameStateGlobal.GameplayState.UPGRADE)
	get_tree().paused = true

	print("🎮 Estado do jogo: UPGRADE")
	print("🎮 Jogo pausado: %s" % str(get_tree().paused))

	current_options = generate_upgrade_options(new_level)

	upgrade_options_ready.emit(current_options)

	print("\n" + "-".repeat(50))
	print("📋 OPÇÕES DE UPGRADE GERADAS:")
	print("-".repeat(50))

	for i in current_options.size():
		var opt = current_options[i]
		var type_icon = "❤️" if opt.type == "bonus" else ("⚔️" if opt.type == "attack" else "⭐")
		var level_info = "First Aid" if opt.type == "bonus" else (
			"NOVO!" if opt.current_level == 0 else ("Lv%d → Lv%d" % [opt.current_level, opt.current_level + 1])
		)
		print("  [%d] %s %s (%s)" % [i + 1, type_icon, opt.name, level_info])
		print("      ID: %d | Type: %s" % [opt.id, opt.type])

	print("-".repeat(50))
	print("\n⏳ Aguardando escolha do player via UI...")
	print("\n" + "=".repeat(50) + "\n")

# =================================================
# GERAR OPÇÕES - v1.4.0 FASE 3
# =================================================
func generate_upgrade_options(level: int) -> Array[Dictionary]:
	"""
	FASE 3: Consulta controllers reais e sorteia opções disponíveis.
	Filtra por max_level e retorna até 3 opções aleatórias.
	v1.4.7: Garante ao menos 1 ataque nas opções até early_game_threshold.
	v1.4.7: Respeita attack_capacity e powerup_capacity.
	v1.4.7: Pool vazio → oferece First Aid como única opção.
	"""

	print("\n🔧 Gerando opções de upgrade (FASE 3)...")
	print("   Level do player: %d" % level)

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
		print("   🔒 Ataques: %d/%d — novos desbloqueios bloqueados" % [unlocked_attacks, attack_capacity])
	if powerups_full:
		print("   🔒 Powerups: %d/%d — novos desbloqueios bloqueados" % [unlocked_powerups, powerup_capacity])

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
	print("   📦 Pool total: %d upgrades disponíveis (%d ataques, %d powerups)" % [pool.size(), attack_pool.size(), powerup_pool.size()])

	# Pool vazio → First Aid como única opção (outros 2 botões ficam invisíveis)
	if pool.size() == 0:
		print("   ❤️ Nenhum upgrade disponível — oferecendo First Aid")
		return [_make_heal_option()]

	var max_options = min(options_count, pool.size())
	var options: Array[Dictionary] = []

	# v1.4.7: Early game — garante ao menos 1 ataque até early_game_threshold
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

		print("   🎯 Early game (Lv%d ≤ %d): ataque garantido nas opções" % [level, early_game_threshold])
	else:
		pool.shuffle()
		for i in range(max_options):
			options.append(pool[i])

	print("   ✅ %d opções sorteadas" % options.size())

	return options

# =================================================
# FIRST AID — monta dicionário da opção de cura
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

	print("\n" + "=".repeat(50))
	print("✅ UPGRADE SELECIONADO!")
	print("=".repeat(50))
	print("📦 Opção escolhida: [%d] %s" % [choice_index + 1, choice.name])
	print("📊 Tipo: %s | ID: %d" % [choice.type, choice.id])

	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ Player não encontrado!")
		return

	_apply_upgrade(player, choice)

	upgrade_applied.emit(choice)

	is_waiting_for_choice = false
	current_options.clear()

	print("\n⏯️ Despausando jogo...")
	print("🎮 Voltando para estado: COMBAT")

	GameStateGlobal.set_state(GameStateGlobal.GameplayState.COMBAT)
	get_tree().paused = false

	print("🎮 Jogo pausado: %s" % str(get_tree().paused))
	print("\n" + "=".repeat(50) + "\n")

# =================================================
# APLICAR UPGRADE - v1.3.26 | v1.3.27
# =================================================
func _apply_upgrade(_player: Node, choice: Dictionary) -> void:
	# First Aid — delega ao GameStateGlobal que encapsula a lógica de cura
	if choice.type == "bonus":
		GameStateGlobal.heal(heal_amount)
		return

	# Attacks e Powerups — via controllers
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
		print("⚠️ Falha ao aplicar upgrade: %s" % choice.name)


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
	print("\n🖱️ Opção selecionada na UI: [%d]" % (option_index + 1))
	apply_upgrade(option_index)

# =================================================
# SIMULAÇÃO (DEBUG - FASE 1)
# =================================================
func simulate_choice(choice_index: int) -> void:
	if not is_waiting_for_choice:
		print("⚠️ Não há escolha pendente no momento")
		return

	print("\n🎲 SIMULANDO ESCOLHA (DEBUG)...")
	apply_upgrade(choice_index)

# =================================================
# GETTERS
# =================================================
func is_upgrade_active() -> bool:
	return is_waiting_for_choice

func get_current_options() -> Array[Dictionary]:
	return current_options.duplicate()
