extends Resource
class_name PowerUpData

# =================================================
# IDENTITY
# =================================================
@export_group("Identity")
@export var powerup_id: int = 0
@export var powerup_name: String = ""
@export var description: String = ""
@export var icon: Texture2D  # Null is OK - add later

# =================================================
# PROGRESSION (TOP for easy testing)
# =================================================
@export_group("Progression")
@export var current_level: int = 0  # 0 = not acquired, 1+ = acquired with levels
@export var max_level: int = 5

@export_group("UI Per Level")
@export var display_name_per_level: Array[String] = []  ## Ex: ["Vitality Lv1", "Vitality Lv2", ...]
@export var description_per_level: Array[String] = []    ## Ex: ["+20 Max Health", "+40 Max Health", ...]

# =================================================
# STATS - OPÇÃO C: Arrays de progressão por level
# =================================================
# Cada array representa valores por level (índice 0 = level 1, índice 1 = level 2, etc.)
# Arrays vazios = não afeta esse stat
# Pode afetar múltiplos stats ao mesmo tempo

@export_group("Max Health")
@export var max_health_flat_per_level: Array[float] = []
@export var max_health_percent_per_level: Array[float] = []

@export_group("Move Speed")
@export var move_speed_flat_per_level: Array[float] = []
@export var move_speed_percent_per_level: Array[float] = []

@export_group("Damage")
@export var damage_percent_per_level: Array[float] = []

@export_group("Armor")
@export var armor_flat_per_level: Array[float] = []

@export_group("Magnet Range")
@export var magnet_range_flat_per_level: Array[float] = []

@export_group("Attack Speed")
@export var attack_speed_percent_per_level: Array[float] = []

# NOVO v1.2.6 - Lethal Impact
@export_group("Projectile Speed")
@export var projectile_speed_percent_per_level: Array[float] = []

@export_group("Knockback")
@export var knockback_percent_per_level: Array[float] = []


# =================================================
# LEVEL CONTROL
# =================================================
func level_up() -> bool:
	"""Incrementa level. Retorna false se já está no max."""
	if current_level >= max_level:
		return false
	
	current_level += 1
	return true


# =================================================
# GET BONUSES (retorna valores do level ATUAL)
# =================================================
func get_max_health_bonus() -> Dictionary:
	return {
		"flat": _get_value(max_health_flat_per_level),
		"percent": _get_value(max_health_percent_per_level)
	}

func get_move_speed_bonus() -> Dictionary:
	return {
		"flat": _get_value(move_speed_flat_per_level),
		"percent": _get_value(move_speed_percent_per_level)
	}

func get_damage_bonus() -> Dictionary:
	return {
		"flat": 0.0,  # Damage só tem percent
		"percent": _get_value(damage_percent_per_level)
	}

func get_armor_bonus() -> Dictionary:
	return {
		"flat": _get_value(armor_flat_per_level),
		"percent": 0.0  # Armor só tem flat
	}

func get_magnet_bonus() -> Dictionary:
	return {
		"flat": _get_value(magnet_range_flat_per_level),
		"percent": 0.0  # Magnet só tem flat
	}

func get_attack_speed_bonus() -> Dictionary:
	return {
		"flat": 0.0,  # Attack Speed só tem percent
		"percent": _get_value(attack_speed_percent_per_level)
	}

# NOVO v1.2.6 - Lethal Impact
func get_projectile_speed_bonus() -> Dictionary:
	return {
		"flat": 0.0,  # Projectile Speed só tem percent
		"percent": _get_value(projectile_speed_percent_per_level)
	}

func get_knockback_bonus() -> Dictionary:
	return {
		"flat": 0.0,  # Knockback só tem percent
		"percent": _get_value(knockback_percent_per_level)
	}


# =================================================
# HELPER PRIVADO
# =================================================
func _get_value(arr: Array[float]) -> float:
	"""
	v1.3.6: MÉTODO ACUMULATIVO - soma valores de arr[0] até arr[current_level-1].
	
	Exemplo com arr = [20, 20, 20, 20, 20]:
	- Level 0: retorna 0 (não adquirido)
	- Level 1: retorna 20 (arr[0])
	- Level 2: retorna 40 (arr[0] + arr[1])
	- Level 3: retorna 60 (arr[0] + arr[1] + arr[2])
	- Level 4: retorna 80 (arr[0] + arr[1] + arr[2] + arr[3])
	- Level 5: retorna 100 (arr[0] + arr[1] + arr[2] + arr[3] + arr[4])
	
	Isso permite configurar incrementos intuitivos ("+20 por level")
	ao invés de valores absolutos substituídos.
	"""
	if current_level <= 0:
		return 0.0
	
	var total = 0.0
	var max_index = min(current_level, arr.size())
	
	for i in range(max_index):
		total += arr[i]
	
	return total


# =================================================
# UI HELPERS - v1.4.0
# =================================================
func get_display_name_for_level(level: int) -> String:
	"""Retorna display_name para um level específico"""
	if level < 1 or level > display_name_per_level.size():
		return powerup_name + " Lv" + str(level)  # Fallback
	return display_name_per_level[level - 1]  # Array é 0-indexed

func get_description_for_level(level: int) -> String:
	"""Retorna description para um level específico"""
	if level < 1 or level > description_per_level.size():
		return ""  # Fallback vazio
	return description_per_level[level - 1]  # Array é 0-indexed
