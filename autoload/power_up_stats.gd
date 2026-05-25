extends Node

# =================================================
# POWERUP STATS GLOBAL - v1.2.6
# =================================================
# Centraliza TODOS os stats modificados por powerups.
# Qualquer sistema pode consultar valores aqui.
# =================================================

signal stats_changed

# =================================================
# CALIBRATION CONSTANTS
# =================================================

# Armor: Cap de redução de dano para evitar imortalidade
const ARMOR_CAP_PERCENT: float = 0.99  # 0.99 = 99% de redução máxima

# =================================================
# STATS CALCULADOS (valores finais)
# =================================================

# Damage
var damage_multiplier: float = 1.0

# Health
var max_health_bonus_flat: float = 0.0
var max_health_bonus_percent: float = 0.0

# Speed
var move_speed_bonus_flat: float = 0.0
var move_speed_bonus_percent: float = 0.0

# Armor (redução de dano)
var armor: float = 0.0

# Magnet (range de coleta)
var magnet_range_bonus: float = 0.0

# Attack Speed
var attack_speed_multiplier: float = 1.0

# Projectile Speed - NOVO v1.2.6 (Lethal Impact)
var projectile_speed_multiplier: float = 1.0

# Knockback - NOVO v1.2.6 (Lethal Impact)
var knockback_multiplier: float = 1.0


# =================================================
# UPDATE STATS
# =================================================
func update_stats(stats: Dictionary) -> void:
	"""
	Atualiza stats e emite signal.
	Chamado por PowerUpController após recalcular.
	"""
	damage_multiplier = stats.get("damage_multiplier", 1.0)
	max_health_bonus_flat = stats.get("max_health_bonus_flat", 0.0)
	max_health_bonus_percent = stats.get("max_health_bonus_percent", 0.0)
	move_speed_bonus_flat = stats.get("move_speed_bonus_flat", 0.0)
	move_speed_bonus_percent = stats.get("move_speed_bonus_percent", 0.0)
	armor = stats.get("armor", 0.0)
	magnet_range_bonus = stats.get("magnet_range_bonus", 0.0)
	attack_speed_multiplier = stats.get("attack_speed_multiplier", 1.0)
	projectile_speed_multiplier = stats.get("projectile_speed_multiplier", 1.0)
	knockback_multiplier = stats.get("knockback_multiplier", 1.0)
	
	stats_changed.emit()
	
	_print_stats_debug()


# =================================================
# DEBUG
# =================================================
func _print_stats_debug() -> void:
	print("\n═══════════════════════════════════════════════════")
	print("📊 POWERUP STATS GLOBAL - UPDATED")
	print("═══════════════════════════════════════════════════")
	print("💥 Damage Multiplier:      ×%.2f" % damage_multiplier)
	print("❤️  Max Health Flat:       +%.1f" % max_health_bonus_flat)
	print("❤️  Max Health Percent:    +%.0f%%" % (max_health_bonus_percent * 100))
	print("🏃 Move Speed Flat:        +%.1f" % move_speed_bonus_flat)
	print("🏃 Move Speed Percent:     +%.0f%%" % (move_speed_bonus_percent * 100))
	print("🛡️  Armor:                  %.1f" % armor)
	print("🧲 Magnet Range Bonus:     +%.1f" % magnet_range_bonus)
	print("⚡ Attack Speed Multiplier: ×%.2f" % attack_speed_multiplier)
	print("🚀 Projectile Speed Mult:  ×%.2f" % projectile_speed_multiplier)
	print("💫 Knockback Multiplier:   ×%.2f" % knockback_multiplier)
	print("═══════════════════════════════════════════════════\n")


# =================================================
# HELPERS
# =================================================
func get_damage_multiplier() -> float:
	return damage_multiplier

func get_armor_damage_reduction() -> float:
	"""
	Calcula redução de dano baseado em armor.
	v1.1.19 v4 FIX: Fórmula LINEAR ao invés de MOBA diminishing returns.
	
	FÓRMULA LINEAR:
	- 10 armor = 10% redução
	- 40 armor = 40% redução
	- 75 armor = 75% redução (cap máximo)
	
	Cap em 75% para evitar imortalidade (100% = imortal).
	"""
	var reduction = armor / 100.0
	return min(reduction, ARMOR_CAP_PERCENT)

func reset() -> void:
	"""Reset all stats to default"""
	damage_multiplier = 1.0
	max_health_bonus_flat = 0.0
	max_health_bonus_percent = 0.0
	move_speed_bonus_flat = 0.0
	move_speed_bonus_percent = 0.0
	armor = 0.0
	magnet_range_bonus = 0.0
	attack_speed_multiplier = 1.0
	projectile_speed_multiplier = 1.0
	knockback_multiplier = 1.0
	
	print("🔄 PowerUpStatsGlobal: Stats reset to default")
