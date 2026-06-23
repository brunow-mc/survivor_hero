extends Node

# =================================================
# POWERUP STATS GLOBAL - v1.2.6
# =================================================
signal stats_changed

# =================================================
# CALIBRATION CONSTANTS
# =================================================

# Armor: Cap de redução de dano para evitar imortalidade
const ARMOR_CAP_PERCENT: float = 0.99

# =================================================
# STATS CALCULADOS (valores finais)
# =================================================

var damage_multiplier: float = 1.0

var max_health_bonus_flat: float = 0.0
var max_health_bonus_percent: float = 0.0

var move_speed_bonus_flat: float = 0.0
var move_speed_bonus_percent: float = 0.0

var armor: float = 0.0

var magnet_range_bonus: float = 0.0

# Redução global de cooldown vinda de powerups.
# Armazenado como percentual direto (0.25 = 25% de redução).
# Somado ao cooldown_reduction individual de cada ataque antes de aplicar.
var global_cooldown_reduction: float = 0.0

var projectile_speed_multiplier: float = 1.0

var knockback_multiplier: float = 1.0


# =================================================
# UPDATE STATS
# =================================================
func update_stats(stats: Dictionary) -> void:
	damage_multiplier = stats.get("damage_multiplier", 1.0)
	max_health_bonus_flat = stats.get("max_health_bonus_flat", 0.0)
	max_health_bonus_percent = stats.get("max_health_bonus_percent", 0.0)
	move_speed_bonus_flat = stats.get("move_speed_bonus_flat", 0.0)
	move_speed_bonus_percent = stats.get("move_speed_bonus_percent", 0.0)
	armor = stats.get("armor", 0.0)
	magnet_range_bonus = stats.get("magnet_range_bonus", 0.0)
	global_cooldown_reduction = stats.get("global_cooldown_reduction", 0.0)
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
	print("⚡ Global Cooldown Reduction: -%.0f%%" % (global_cooldown_reduction * 100))
	print("🚀 Projectile Speed Mult:  ×%.2f" % projectile_speed_multiplier)
	print("💫 Knockback Multiplier:   ×%.2f" % knockback_multiplier)
	print("═══════════════════════════════════════════════════\n")


# =================================================
# HELPERS
# =================================================
func get_damage_multiplier() -> float:
	return damage_multiplier

func get_armor_damage_reduction() -> float:
	var reduction = armor / 100.0
	return min(reduction, ARMOR_CAP_PERCENT)

func reset() -> void:
	damage_multiplier = 1.0
	max_health_bonus_flat = 0.0
	max_health_bonus_percent = 0.0
	move_speed_bonus_flat = 0.0
	move_speed_bonus_percent = 0.0
	armor = 0.0
	magnet_range_bonus = 0.0
	global_cooldown_reduction = 0.0
	projectile_speed_multiplier = 1.0
	knockback_multiplier = 1.0
	
	print("🔄 PowerUpStatsGlobal: Stats reset to default")
