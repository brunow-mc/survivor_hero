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
# CONFIGURAÇÃO DE PESOS (preparado para FASE 4)
# -------------------------------------------------
@export_group("Weight System")
@export var common_weight: float = 1.0      ## Peso para upgrades comuns
@export var uncommon_weight: float = 0.7    ## Peso para upgrades incomuns
@export var rare_weight: float = 0.3        ## Peso para upgrades raros
@export var epic_weight: float = 0.1        ## Peso para upgrades épicos

@export_group("Options")
@export var options_count: int = 3  ## Quantas opções oferecer por level up

# v1.4.7: Até esse level, garante ao menos 1 ataque nas opções.
# @export mantido para futura integração com sistema de configuração por cena.
@export var early_game_threshold: int = 3

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

	# Conectar ao XPManager
	if XPManagerGlobal:
		XPManagerGlobal.level_up.connect(_on_level_up)
		print("✅ LevelUpManager: Conectado ao XPManagerGlobal")
	else:
		push_error("❌ LevelUpManager: XPManagerGlobal não encontrado!")

	# Instanciar UI
	level_up_ui = LEVEL_UP_UI_SCENE.instantiate()
	add_child(level_up_ui)

	# Conectar ao sinal de escolha da UI
	level_up_ui.option_selected.connect(_on_ui_option_selected)

	print("✅ LevelUpManager: UI instanciada e conectada")

# =================================================
# LEVEL UP
# =================================================
func _on_level_up(new_level: int) -> void:
	"""
	Chamado quando player sobe de level.
	Pausa jogo e oferece opções de upgrade.
	"""
	print("\n" + "=".repeat(50))
	print("🎉 LEVEL UP DETECTADO!")
	print("=".repeat(50))
	print("📊 Novo Level: %d" % new_level)
	print("⏸️ Pausando jogo...")

	# Marcar que está aguardando escolha
	is_waiting_for_choice = true

	# Mudar para estado UPGRADE (pausa o jogo)
	GameStateGlobal.set_state(GameStateGlobal.GameplayState.UPGRADE)
	get_tree().paused = true

	print("🎮 Estado do jogo: UPGRADE")
	print("🎮 Jogo pausado: %s" % str(get_tree().paused))

	# Gerar opções de upgrade
	current_options = generate_upgrade_options(new_level)

	# Emitir signal (UI vai receber e exibir menu)
	upgrade_options_ready.emit(current_options)

	print("\n" + "-".repeat(50))
	print("📋 OPÇÕES DE UPGRADE GERADAS:")
	print("-".repeat(50))

	for i in current_options.size():
		var opt = current_options[i]
		var type_icon = "⚔️" if opt.type == "attack" else "⭐"
		var level_info = "NOVO!" if opt.current_level == 0 else ("Lv%d → Lv%d" % [opt.current_level, opt.current_level + 1])

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
	"""

	print("\n🔧 Gerando opções de upgrade (FASE 3)...")
	print("   Level do player: %d" % level)

	# Buscar player
	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ LevelUpManager: Player não encontrado!")
		return []

	# Buscar controllers
	var attack_controller = player.get_node_or_null("AttackController")
	var powerup_controller = player.get_node_or_null("PowerUpController")

	if not attack_controller:
		push_error("❌ LevelUpManager: AttackController não encontrado!")
		return []

	if not powerup_controller:
		push_error("❌ LevelUpManager: PowerUpController não encontrado!")
		return []

	# Montar pool de upgrades disponíveis
	var attack_pool: Array[Dictionary] = []
	var powerup_pool: Array[Dictionary] = []

	# Adicionar ataques ao pool
	for upgrade_data in attack_controller.attack_upgrades:
		if not upgrade_data:
			continue

		var next_level = upgrade_data.current_level + 1

		if upgrade_data.current_level >= upgrade_data.max_level:
			continue

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

	# Adicionar powerups ao pool
	for powerup_data in powerup_controller.powerups:
		if not powerup_data:
			continue

		var next_level = powerup_data.current_level + 1

		if powerup_data.current_level >= powerup_data.max_level:
			continue

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

	if pool.size() == 0:
		push_warning("⚠️ LevelUpManager: Nenhum upgrade disponível!")
		return []

	var max_options = min(options_count, pool.size())
	var options: Array[Dictionary] = []

	# v1.4.7: Early game — garante ao menos 1 ataque até early_game_threshold
	if level <= early_game_threshold and attack_pool.size() > 0:
		attack_pool.shuffle()
		options.append(attack_pool[0])

		# Monta o restante do pool sem o ataque já escolhido e sorteia
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
		# Comportamento padrão: shuffle total
		pool.shuffle()
		for i in range(max_options):
			options.append(pool[i])

	print("   ✅ %d opções sorteadas" % options.size())

	return options

# =================================================
# APLICAR UPGRADE
# =================================================
func apply_upgrade(choice_index: int) -> void:
	"""
	Aplica o upgrade escolhido pelo player.

	Args:
		choice_index: Índice da opção (0, 1 ou 2)
	"""

	if choice_index < 0 or choice_index >= current_options.size():
		push_error("❌ Índice de escolha inválido: %d" % choice_index)
		return

	var choice = current_options[choice_index]

	print("\n" + "=".repeat(50))
	print("✅ UPGRADE SELECIONADO!")
	print("=".repeat(50))
	print("📦 Opção escolhida: [%d] %s" % [choice_index + 1, choice.name])
	print("📊 Tipo: %s | ID: %d" % [choice.type, choice.id])

	# Buscar player
	var player = get_tree().get_first_node_in_group("Player")
	if not player:
		push_error("❌ Player não encontrado!")
		return

	# Aplicar upgrade (UNIFICADO v1.3.26)
	_apply_upgrade(player, choice)

	# Emitir signal
	upgrade_applied.emit(choice)

	# Limpar estado
	is_waiting_for_choice = false
	current_options.clear()

	# Despausar e voltar para COMBAT
	print("\n⏯️ Despausando jogo...")
	print("🎮 Voltando para estado: COMBAT")

	GameStateGlobal.set_state(GameStateGlobal.GameplayState.COMBAT)
	get_tree().paused = false

	print("🎮 Jogo pausado: %s" % str(get_tree().paused))
	print("\n" + "=".repeat(50) + "\n")

# =================================================
# APLICAR UPGRADE - v1.3.26: Unificado | v1.3.27: Bug fix no log
# =================================================
func _apply_upgrade(player: Node, choice: Dictionary) -> void:
	"""
	v1.3.26: Método UNIFICADO para aplicar upgrade.
	v1.3.27: Corrigido log para verificar level real (não choice.current_level).
	Funciona para Attack E PowerUp usando mesma interface.
	"""

	var controller_name = "AttackController" if choice.type == "attack" else "PowerUpController"

	if not player.has_node(controller_name):
		push_error("❌ %s não encontrado no player!" % controller_name)
		return

	var controller = player.get_node(controller_name)

	var level_before = _get_current_level(controller, choice)

	var success = controller.apply_upgrade(choice.id)

	if success:
		var action = "desbloqueado" if level_before == 0 else "upado"
		var type_emoji = "⚔️" if choice.type == "attack" else "⭐"
		print("%s %s %s!" % [type_emoji, choice.name, action])
	else:
		print("⚠️ Falha ao aplicar upgrade: %s" % choice.name)


func _get_current_level(controller: Node, choice: Dictionary) -> int:
	"""
	v1.3.27: Obtém level atual real do upgrade/powerup.
	Usado para log correto (desbloqueado vs upado).
	"""
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
	"""
	Chamado quando player escolhe opção na UI.
	"""
	print("\n🖱️ Opção selecionada na UI: [%d]" % (option_index + 1))
	apply_upgrade(option_index)

# =================================================
# SIMULAÇÃO (DEBUG - FASE 1)
# =================================================
func simulate_choice(choice_index: int) -> void:
	"""
	FASE 1: Simula escolha via console.
	FASE 2: Será chamado pela UI.

	Use no console:
	LevelUpManagerGlobal.simulate_choice(0)  # Escolhe opção 1
	LevelUpManagerGlobal.simulate_choice(1)  # Escolhe opção 2
	LevelUpManagerGlobal.simulate_choice(2)  # Escolhe opção 3
	"""

	if not is_waiting_for_choice:
		print("⚠️ Não há escolha pendente no momento")
		return

	print("\n🎲 SIMULANDO ESCOLHA (DEBUG)...")
	apply_upgrade(choice_index)

# =================================================
# GETTERS
# =================================================
func is_upgrade_active() -> bool:
	"""Retorna true se está aguardando escolha de upgrade"""
	return is_waiting_for_choice

func get_current_options() -> Array[Dictionary]:
	"""Retorna opções atuais disponíveis"""
	return current_options.duplicate()
