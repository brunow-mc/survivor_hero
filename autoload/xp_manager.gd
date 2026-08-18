extends Node
class_name XPManager

# ======================================
# SIGNALS
# ======================================
signal xp_gained(amount: int)
signal xp_changed(current: int, required: int)
signal level_up(new_level: int)

# ======================================
# PROGRESSÃO (estado — muda em runtime)
# ======================================
var current_level: int = 1     # Nível atual (começa em 1).
var current_xp: int = 0        # XP acumulado rumo ao próximo nível; a sobra vira fila implícita.
var xp_to_next_level: int = 0  # SAÍDA: recalculado pela curva a cada nível. Não editar — é sobrescrito no _ready.

# ======================================
# CONFIGURAÇÃO DE CURVA (entradas — definem a forma da progressão)
# ======================================
var base_xp_requirement: int = 4     # XP do 1º level-up e base de TODOS os modos (nível 1 = este valor).
var xp_scaling_factor: float = 1.2  # Só EXPONENTIAL usa: razão do crescimento geométrico (composta por nível).
var xp_power_exponent: float = 1.25   # Só POWER usa: expoente polinomial (1.0≈linear, ~1.5 rampa suave, 2.0 quadrática).
var xp_scaling_type: ScalingType = ScalingType.POWER  # Modo de progressão (ver enum).

enum ScalingType {
	LINEAR,       # base × nível           — incremento constante, nunca acelera.
	EXPONENTIAL,  # base × fator^(nível-1)  — geométrico: começo colado + explosão tardia. Usa xp_scaling_factor.
	FIXED,        # base                    — custo constante em todo nível.
	POWER,        # base × nível^expoente   — polinomial: rampa crescente sem explodir. Usa xp_power_exponent.
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
	# FILA IMPLÍCITA: concede no máximo 1 level por vez.
	# A sobra de XP permanece em current_xp e funciona como fila:
	# quando o menu de upgrade é resolvido, upgrade_selected()
	# chama este método de novo — se a sobra cobrir outro level,
	# novo level up, novo menu, até esgotar.
	if is_waiting_for_upgrade:
		return

	if current_xp >= xp_to_next_level:
		_level_up()

func _level_up() -> void:
	current_level += 1
	current_xp -= xp_to_next_level
	_calculate_xp_requirement()

	# Bloqueia novos level ups (e add_xp) até o menu ser resolvido.
	is_waiting_for_upgrade = true

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

		ScalingType.POWER:
			xp_to_next_level = int(
				base_xp_requirement * pow(current_level, xp_power_exponent)
			)

# ======================================
# UPGRADE SCREEN
# ======================================
func upgrade_selected() -> void:
	# Chamado pelo LevelUpManager quando o player confirma a escolha.
	# Re-checa a sobra de XP: se cobrir outro level, abre novo menu
	# (fila implícita — ver _check_level_up).
	is_waiting_for_upgrade = false
	_check_level_up()

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
