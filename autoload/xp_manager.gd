extends Node
class_name XPManager

# ======================================
# SIGNALS
# ======================================
signal xp_gained(amount: int)
signal xp_changed(current: int, required: int)
signal level_up(new_level: int)
signal ready_for_upgrade()

# ======================================
# PROGRESSÃO
# ======================================
var current_level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 5

# ======================================
# CONFIGURAÇÃO DE CURVA
# ======================================
var base_xp_requirement: int = 5
var xp_scaling_factor: float = 1.35
var xp_scaling_type: ScalingType = ScalingType.EXPONENTIAL

enum ScalingType {
	LINEAR,
	EXPONENTIAL,
	FIXED
}

# ======================================
# ESTADO
# ======================================
var is_waiting_for_upgrade: bool = false

# ======================================
# READY
# ======================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_calculate_xp_requirement()
	print("🎮 XPManager inicializado!")
	print("   Level: %d | XP necessário: %d" % [current_level, xp_to_next_level])

# ======================================
# ADICIONAR XP
# ======================================
func add_xp(amount: int) -> void:
	if is_waiting_for_upgrade:
		print("⏸️ XPManager: Aguardando upgrade, XP não contabilizado")
		return
	
	current_xp += amount
	print("📈 XPManager: +%d XP | Total: %d/%d" % [amount, current_xp, xp_to_next_level])
	
	xp_gained.emit(amount)
	xp_changed.emit(current_xp, xp_to_next_level)
	
	# Checa level up
	_check_level_up()

# ======================================
# LEVEL UP
# ======================================
func _check_level_up() -> void:
	while current_xp >= xp_to_next_level:
		_level_up()

func _level_up() -> void:
	# Incrementa level
	current_level += 1
	
	# Remove XP usado (overflow continua)
	current_xp -= xp_to_next_level
	
	print("⭐ LEVEL UP! Nível %d alcançado!" % current_level)
	
	# Recalcula próximo requirement
	_calculate_xp_requirement()
	
	print("   Próximo level precisa de %d XP" % xp_to_next_level)
	
	# Notifica
	level_up.emit(current_level)
	xp_changed.emit(current_xp, xp_to_next_level)
	
	# TODO: Pausa para upgrade (implementar depois)
	# _trigger_upgrade_screen()

# ======================================
# CÁLCULO DE XP NECESSÁRIO
# ======================================
func _calculate_xp_requirement() -> void:
	match xp_scaling_type:
		ScalingType.LINEAR:
			xp_to_next_level = base_xp_requirement * current_level
		
		ScalingType.EXPONENTIAL:
			xp_to_next_level = int(
				base_xp_requirement * pow(xp_scaling_factor, current_level - 1)
			)
		
		ScalingType.FIXED:
			xp_to_next_level = base_xp_requirement

# ======================================
# UPGRADE SCREEN (preparar para futuro)
# ======================================
func _trigger_upgrade_screen() -> void:
	is_waiting_for_upgrade = true
	ready_for_upgrade.emit()
	print("🎁 Pronto para upgrade!")
	
	# TODO: Pausar jogo quando tiver tela de upgrade
	# GameStateGlobal.pause_game()

func upgrade_selected() -> void:
	"""Será chamado quando player escolher um upgrade"""
	is_waiting_for_upgrade = false
	print("✅ Upgrade selecionado, XP reiniciado")
	
	# TODO: Despausar quando tiver tela de upgrade
	# GameStateGlobal.resume_game()

# ======================================
# RESET
# ======================================
func reset() -> void:
	current_level = 1
	current_xp = 0
	is_waiting_for_upgrade = false
	_calculate_xp_requirement()
	xp_changed.emit(current_xp, xp_to_next_level)
	print("🔄 XPManager resetado!")

# ======================================
# GETTERS
# ======================================
func get_xp_progress_ratio() -> float:
	"""Retorna 0.0 a 1.0 para preencher a barra de XP"""
	if xp_to_next_level == 0:
		return 0.0
	return float(current_xp) / float(xp_to_next_level)

func get_level() -> int:
	return current_level

func get_current_xp() -> int:
	return current_xp

func get_xp_to_next_level() -> int:
	return xp_to_next_level
