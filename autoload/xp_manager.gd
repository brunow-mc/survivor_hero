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
	print("🎮 XPManager inicializado! Level: %d | XP necessário: %d" % [current_level, xp_to_next_level])

# ======================================
# ADICIONAR XP
# ======================================
func add_xp(amount: int) -> void:
	if is_waiting_for_upgrade:
		return
	# Backup: não processa XP fora de combate (inclui PLAYER_DEAD)
	if not GameStateGlobal.is_combat_allowed():
		return

	current_xp += amount

	xp_gained.emit(amount)
	xp_changed.emit(current_xp, xp_to_next_level)

	_check_level_up()

# ======================================
# LEVEL UP
# ======================================
func _check_level_up() -> void:
	while current_xp >= xp_to_next_level:
		_level_up()

func _level_up() -> void:
	current_level += 1
	current_xp -= xp_to_next_level
	_calculate_xp_requirement()

	print("⭐ LEVEL UP! Nível %d | Próximo: %d XP" % [current_level, xp_to_next_level])

	level_up.emit(current_level)
	xp_changed.emit(current_xp, xp_to_next_level)

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
# UPGRADE SCREEN (preparado para futuro)
# ======================================
func _trigger_upgrade_screen() -> void:
	is_waiting_for_upgrade = true
	ready_for_upgrade.emit()

func upgrade_selected() -> void:
	is_waiting_for_upgrade = false

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
	if xp_to_next_level == 0:
		return 0.0
	return float(current_xp) / float(xp_to_next_level)

func get_level() -> int:
	return current_level

func get_current_xp() -> int:
	return current_xp

func get_xp_to_next_level() -> int:
	return xp_to_next_level
