extends Resource
class_name AttackUpgradeData

# =================================================
# ATTACK UPGRADE DATA - v1.3.0
# =================================================
# Define progressão de upgrades por ataque.
# Arrays são 0-indexed: arr[0] = level 1, arr[1] = level 2, etc.
# Valores são ACUMULADOS (level 3 = arr[0] + arr[1] + arr[2])
# =================================================

@export_group("Identity")
@export var attack_id: int = 0
@export var attack_name: String = ""
@export var description: String = ""

@export_group("Progression")
@export var current_level: int = 0  ## 0 = locked, 1+ = unlocked
@export var max_level: int = 5

@export_group("UI Per Level")
@export var display_name_per_level: Array[String] = []  ## Ex: ["Fire Power Lv1", "Fire Power Lv2", ...]
@export var description_per_level: Array[String] = []    ## Ex: ["Unlock Fire Power", "+10% Damage\n-5% Cooldown", ...]

@export_group("Upgrades Per Level")
@export var projectile_count_per_level: Array[int] = []
@export var damage_bonus_per_level: Array[float] = []
@export var speed_bonus_per_level: Array[float] = []
@export var max_hits_per_level: Array[int] = []
@export var cooldown_reduction_per_level: Array[float] = []
# v1.3.8:
@export var projectile_angle_spread_per_level: Array[float] = []
@export var life_time_bonus_per_level: Array[float] = []
@export var attack_scale_bonus_per_level: Array[float] = []
# NOVOS v1.3.9:
@export var projectile_stagger_delay_per_level: Array[float] = []
@export var orbit_radius_per_level: Array[float] = []
@export var orbit_speed_bonus_per_level: Array[float] = []


func level_up() -> bool:
	if current_level >= max_level:
		return false
	current_level += 1
	return true

func level_down() -> bool:
	if current_level <= 0:
		return false
	current_level -= 1
	return true


# Retorna valores ACUMULADOS do level atual
func get_projectile_count_bonus() -> int:
	return _sum_int(projectile_count_per_level)

func get_damage_bonus() -> float:
	return _sum_float(damage_bonus_per_level)

func get_speed_bonus() -> float:
	return _sum_float(speed_bonus_per_level)

func get_max_hits_bonus() -> int:
	return _sum_int(max_hits_per_level)

func get_cooldown_reduction() -> float:
	return _sum_float(cooldown_reduction_per_level)

# v1.3.8:
func get_projectile_angle_spread_bonus() -> float:
	return _sum_float(projectile_angle_spread_per_level)

func get_life_time_bonus() -> float:
	return _sum_float(life_time_bonus_per_level)

func get_attack_scale_bonus() -> float:
	return _sum_float(attack_scale_bonus_per_level)

# NOVOS v1.3.9:
func get_projectile_stagger_delay_bonus() -> float:
	return _sum_float(projectile_stagger_delay_per_level)

func get_orbit_radius_bonus() -> float:
	return _sum_float(orbit_radius_per_level)

func get_orbit_speed_bonus() -> float:
	return _sum_float(orbit_speed_bonus_per_level)


func _sum_int(arr: Array[int]) -> int:
	if current_level <= 0:
		return 0
	var total = 0
	for i in range(min(current_level, arr.size())):
		total += arr[i]
	return total

func _sum_float(arr: Array[float]) -> float:
	if current_level <= 0:
		return 0.0
	var total = 0.0
	for i in range(min(current_level, arr.size())):
		total += arr[i]
	return total


# =================================================
# UI HELPERS - v1.4.0
# =================================================
func get_display_name_for_level(level: int) -> String:
	"""Retorna display_name para um level específico"""
	if level < 1 or level > display_name_per_level.size():
		return attack_name + " Lv" + str(level)  # Fallback
	return display_name_per_level[level - 1]  # Array é 0-indexed

func get_description_for_level(level: int) -> String:
	"""Retorna description para um level específico"""
	if level < 1 or level > description_per_level.size():
		return ""  # Fallback vazio
	return description_per_level[level - 1]  # Array é 0-indexed
