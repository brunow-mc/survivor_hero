extends Node
class_name PowerUpController

# =================================================
# POWERUP CONTROLLER - v1.1.19 v3 | v1.3.2
# =================================================

signal powerup_unlocked(powerup_id: int, icon: Texture2D)  # v1.4.7: emitido por qualquer fonte

@export var powerups: Array[PowerUpData] = []

var player: PlayerBase = null

var player_base_values: Dictionary = {}


# =================================================
# READY
# =================================================
func _ready() -> void:
	print("\n🔷 PowerUpController: Initializing...")
	_duplicate_powerup_resources()
	
	await get_tree().process_frame
	
	player = get_parent() as PlayerBase
	
	if player:
		player_base_values = {
			"max_health": player.max_health,
			"move_speed": player.move_speed
		}
		
		print("✅ PowerUpController: Player reference acquired")
		print("   📊 Base Max Health: %.1f" % player_base_values["max_health"])
		print("   📊 Base Move Speed: %.1f" % player_base_values["move_speed"])
		
		_recalculate_all_stats()
	else:
		push_warning("⚠️ PowerUpController: Parent is not PlayerBase!")


func _duplicate_powerup_resources() -> void:
	var duplicated: Array[PowerUpData] = []
	
	for powerup in powerups:
		if powerup:
			var dup_powerup = powerup.duplicate(true)
			
			dup_powerup.max_health_flat_per_level = _duplicate_float_array(dup_powerup.max_health_flat_per_level)
			dup_powerup.max_health_percent_per_level = _duplicate_float_array(dup_powerup.max_health_percent_per_level)
			dup_powerup.move_speed_flat_per_level = _duplicate_float_array(dup_powerup.move_speed_flat_per_level)
			dup_powerup.move_speed_percent_per_level = _duplicate_float_array(dup_powerup.move_speed_percent_per_level)
			dup_powerup.damage_percent_per_level = _duplicate_float_array(dup_powerup.damage_percent_per_level)
			dup_powerup.armor_flat_per_level = _duplicate_float_array(dup_powerup.armor_flat_per_level)
			dup_powerup.magnet_range_flat_per_level = _duplicate_float_array(dup_powerup.magnet_range_flat_per_level)
			dup_powerup.cooldown_reduction_percent_per_level = _duplicate_float_array(dup_powerup.cooldown_reduction_percent_per_level)
			dup_powerup.projectile_speed_percent_per_level = _duplicate_float_array(dup_powerup.projectile_speed_percent_per_level)
			dup_powerup.knockback_percent_per_level = _duplicate_float_array(dup_powerup.knockback_percent_per_level)
			
			duplicated.append(dup_powerup)
		else:
			duplicated.append(null)
	
	powerups = duplicated
	print("🔄 PowerUpController: Resources duplicated for runtime")
	print("   ⚠️ Arrays duplicados MANUALMENTE (workaround Godot)")


func _duplicate_float_array(arr: Array[float]) -> Array[float]:
	var duplicated: Array[float] = []
	for value in arr:
		duplicated.append(value)
	return duplicated


# =================================================
# APPLY UPGRADE - v1.3.26 | v1.4.7
# =================================================
func apply_upgrade(powerup_id: int) -> bool:
	var powerup := _find_powerup(powerup_id)
	
	if not powerup:
		push_warning("⚠️ PowerUpController: PowerUp ID %d não encontrado" % powerup_id)
		return false
	
	var was_level = powerup.current_level
	
	if not powerup.level_up():
		return false
	
	if was_level == 0:
		print("\n✨ PowerUp UNLOCKED: '%s' (Level %d)" % [powerup.powerup_name, powerup.current_level])
		powerup_unlocked.emit(powerup_id, powerup.icon)  # v1.4.7
	else:
		print("\n⬆️ PowerUp UPGRADED: '%s' (Level %d → %d)" % [powerup.powerup_name, was_level, powerup.current_level])
	
	_recalculate_all_stats()
	return true


func apply_powerup(powerup_id: int) -> bool:
	"""DEPRECATED v1.3.26: Use apply_upgrade() instead."""
	return apply_upgrade(powerup_id)


func remove_powerup(powerup_id: int) -> bool:
	var powerup := _find_powerup(powerup_id)
	
	if not powerup:
		push_warning("⚠️ PowerUpController: PowerUp ID %d não encontrado" % powerup_id)
		return false
	
	if powerup.current_level == 0:
		print("ℹ️ PowerUp '%s' já está desativado" % powerup.powerup_name)
		return false
	
	powerup.current_level = 0
	print("🗑️ PowerUp REMOVED: '%s'" % powerup.powerup_name)
	
	_recalculate_all_stats()
	return true


func _find_powerup(id: int) -> PowerUpData:
	for powerup in powerups:
		if powerup and powerup.powerup_id == id:
			return powerup
	return null


func get_powerup(powerup_id: int) -> PowerUpData:
	return _find_powerup(powerup_id)


# =================================================
# RECALCULAR STATS
# =================================================
func _recalculate_all_stats() -> void:
	print("\n🔄 Recalculating all stats...")
	
	var total_max_health_flat := 0.0
	var total_max_health_percent := 0.0
	var total_move_speed_flat := 0.0
	var total_move_speed_percent := 0.0
	var total_damage_percent := 0.0
	var total_armor_flat := 0.0
	var total_magnet_flat := 0.0
	var total_global_cooldown_reduction := 0.0
	var total_projectile_speed_percent := 0.0
	var total_knockback_percent := 0.0
	
	for powerup in powerups:
		if not powerup or powerup.current_level == 0:
			continue
		
		var health_bonus = powerup.get_max_health_bonus()
		total_max_health_flat += health_bonus["flat"]
		total_max_health_percent += health_bonus["percent"]
		
		var speed_bonus = powerup.get_move_speed_bonus()
		total_move_speed_flat += speed_bonus["flat"]
		total_move_speed_percent += speed_bonus["percent"]
		
		var damage_bonus = powerup.get_damage_bonus()
		total_damage_percent += damage_bonus["percent"]
		
		var armor_bonus = powerup.get_armor_bonus()
		total_armor_flat += armor_bonus["flat"]
		
		var magnet_bonus = powerup.get_magnet_bonus()
		total_magnet_flat += magnet_bonus["flat"]
		
		var cd_bonus = powerup.get_cooldown_reduction_bonus()
		total_global_cooldown_reduction += cd_bonus["percent"]
		
		var proj_speed_bonus = powerup.get_projectile_speed_bonus()
		total_projectile_speed_percent += proj_speed_bonus["percent"]
		
		var knockback_bonus = powerup.get_knockback_bonus()
		total_knockback_percent += knockback_bonus["percent"]
		
		print("  📦 '%s' (Lv%d): HP+%.1f/+%.0f%%, Speed+%.1f/+%.0f%%, Dmg+%.0f%%, Armor+%.1f" % [
			powerup.powerup_name,
			powerup.current_level,
			health_bonus["flat"],
			health_bonus["percent"] * 100,
			speed_bonus["flat"],
			speed_bonus["percent"] * 100,
			damage_bonus["percent"] * 100,
			armor_bonus["flat"]
		])
	
	var stats = {
		"damage_multiplier": 1.0 + total_damage_percent,
		"max_health_bonus_flat": total_max_health_flat,
		"max_health_bonus_percent": total_max_health_percent,
		"move_speed_bonus_flat": total_move_speed_flat,
		"move_speed_bonus_percent": total_move_speed_percent,
		"armor": total_armor_flat,
		"magnet_range_bonus": total_magnet_flat,
		"global_cooldown_reduction": total_global_cooldown_reduction,
		"projectile_speed_multiplier": 1.0 + total_projectile_speed_percent,
		"knockback_multiplier": 1.0 + total_knockback_percent
	}
	
	PowerUpStatsGlobal.update_stats(stats)
	_apply_stats_to_player()


# =================================================
# APLICAR STATS
# =================================================
func _apply_stats_to_player() -> void:
	if not player:
		return
	
	print("\n🎯 Applying stats to player systems...")
	
	var new_max_health = (player_base_values["max_health"] + PowerUpStatsGlobal.max_health_bonus_flat) * (1.0 + PowerUpStatsGlobal.max_health_bonus_percent)
	
	var old_max = player.max_health
	player.max_health = new_max_health
	
	if new_max_health > old_max:
		var max_health_increase = new_max_health - old_max
		GameStateGlobal.player_max_health = new_max_health
		GameStateGlobal.player_health += max_health_increase
		if GameStateGlobal.player_health > new_max_health:
			GameStateGlobal.player_health = new_max_health
		GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
		print("  ❤️  Max Health: %.1f → %.1f (+%.1f HP)" % [old_max, new_max_health, max_health_increase])
	elif new_max_health < old_max:
		GameStateGlobal.player_max_health = new_max_health
		if GameStateGlobal.player_health > new_max_health:
			GameStateGlobal.player_health = new_max_health
			GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
			print("  ❤️  Max Health: %.1f → %.1f (HP capped to new max)" % [old_max, new_max_health])
		else:
			GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
			print("  ❤️  Max Health: %.1f → %.1f" % [old_max, new_max_health])
	else:
		print("  ❤️  Max Health: %.1f (unchanged)" % new_max_health)
	
	var new_speed = (player_base_values["move_speed"] + PowerUpStatsGlobal.move_speed_bonus_flat) * (1.0 + PowerUpStatsGlobal.move_speed_bonus_percent)
	player.move_speed = new_speed
	print("  🏃 Move Speed: %.1f" % new_speed)
	
	print("  💥 Damage Multiplier: ×%.2f (applied on hit)" % PowerUpStatsGlobal.damage_multiplier)
	
	var reduction = PowerUpStatsGlobal.get_armor_damage_reduction()
	print("  🛡️  Armor: %.1f (%.0f%% damage reduction)" % [PowerUpStatsGlobal.armor, reduction * 100])
	
	print("  🧲 Magnet Range: +%.1f (applied in XP items)" % PowerUpStatsGlobal.magnet_range_bonus)
	print("  ⚡ Global Cooldown Reduction: -%.0f%% (applied in timers)" % (PowerUpStatsGlobal.global_cooldown_reduction * 100))
	print("  🚀 Projectile Speed: ×%.2f (applied in powers)" % PowerUpStatsGlobal.projectile_speed_multiplier)
	print("  💫 Knockback: ×%.2f (applied on hit)" % PowerUpStatsGlobal.knockback_multiplier)
	
	print("✅ Stats applied!\n")


# =================================================
# HELPERS
# =================================================
func get_powerup_level(powerup_id: int) -> int:
	var powerup := _find_powerup(powerup_id)
	return powerup.current_level if powerup else 0

func list_active_powerups() -> void:
	print("\n📋 ACTIVE POWERUPS:")
	var has_active = false
	for powerup in powerups:
		if powerup and powerup.current_level > 0:
			print("  ✓ %s (Level %d/%d)" % [powerup.powerup_name, powerup.current_level, powerup.max_level])
			has_active = true
	if not has_active:
		print("  (none)")
	print("")
