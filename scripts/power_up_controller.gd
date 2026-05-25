extends Node
class_name PowerUpController

# =================================================
# POWERUP CONTROLLER - v1.1.19 v3 | v1.3.2
# =================================================
# Gerencia powerups do player (similar ao AttackController).
# Calcula stats e atualiza PowerUpStatsGlobal.
# =================================================

@export var powerups: Array[PowerUpData] = []

var player: PlayerBase = null

# Valores base do player (salvos no _ready)
# v1.3.4: Padronizado para Dictionary (mesmo padrão de AttackController)
var player_base_values: Dictionary = {}


# =================================================
# READY - DUPLICAR RESOURCES
# =================================================
func _ready() -> void:
	print("\n🔷 PowerUpController: Initializing...")
	_duplicate_powerup_resources()
	
	# Aguarda 1 frame para garantir que player já foi configurado
	await get_tree().process_frame
	
	player = get_parent() as PlayerBase
	
	if player:
		# CRITICAL: Salvar valores base ANTES de aplicar modificadores
		# v1.3.4: Guardados em Dictionary (padrão do AttackController)
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
	"""
	Cria cópias dos Resources em runtime.
	Reset automático: reload scene = novas cópias com valores originais.
	Mesmo padrão do AttackController.
	"""
	var duplicated: Array[PowerUpData] = []
	
	for powerup in powerups:
		if powerup:
			# Duplicar PowerUpData
			var dup_powerup = powerup.duplicate(true)
			
			# Duplicar arrays manualmente (workaround Godot)
			dup_powerup.max_health_flat_per_level = _duplicate_float_array(dup_powerup.max_health_flat_per_level)
			dup_powerup.max_health_percent_per_level = _duplicate_float_array(dup_powerup.max_health_percent_per_level)
			dup_powerup.move_speed_flat_per_level = _duplicate_float_array(dup_powerup.move_speed_flat_per_level)
			dup_powerup.move_speed_percent_per_level = _duplicate_float_array(dup_powerup.move_speed_percent_per_level)
			dup_powerup.damage_percent_per_level = _duplicate_float_array(dup_powerup.damage_percent_per_level)
			dup_powerup.armor_flat_per_level = _duplicate_float_array(dup_powerup.armor_flat_per_level)
			dup_powerup.magnet_range_flat_per_level = _duplicate_float_array(dup_powerup.magnet_range_flat_per_level)
			dup_powerup.attack_speed_percent_per_level = _duplicate_float_array(dup_powerup.attack_speed_percent_per_level)
			# NOVO v1.2.6 - Lethal Impact
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
# APPLY UPGRADE - v1.3.26: Unificado com AttackController
# =================================================
func apply_upgrade(powerup_id: int) -> bool:
	"""
	v1.3.26: MÉTODO UNIFICADO para unlock e upgrade.
	Incrementa level do powerup (0→1, 1→2, 2→3, etc).
	Retorna true se sucesso, false se já está no max_level.
	
	PADRÃO: Mesma assinatura de AttackController.apply_upgrade()
	"""
	var powerup := _find_powerup(powerup_id)
	
	if not powerup:
		push_warning("⚠️ PowerUpController: PowerUp ID %d não encontrado" % powerup_id)
		return false
	
	var was_level = powerup.current_level
	
	if not powerup.level_up():
		# v1.3.2: Removido push_warning (validação prévia em TestPowerups)
		return false
	
	if was_level == 0:
		print("\n✨ PowerUp UNLOCKED: '%s' (Level %d)" % [powerup.powerup_name, powerup.current_level])
	else:
		print("\n⬆️ PowerUp UPGRADED: '%s' (Level %d → %d)" % [powerup.powerup_name, was_level, powerup.current_level])
	
	_recalculate_all_stats()
	return true


func apply_powerup(powerup_id: int) -> bool:
	"""
	DEPRECATED v1.3.26: Use apply_upgrade() instead.
	Mantido para compatibilidade com scripts de teste.
	"""
	return apply_upgrade(powerup_id)


func remove_powerup(powerup_id: int) -> bool:
	"""
	Remove powerup (seta level para 0).
	Usado para testes ou reset.
	"""
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
	"""v1.3.2: Método público para acessar powerup (usado por TestPowerups)"""
	return _find_powerup(powerup_id)


# =================================================
# RECALCULAR STATS
# =================================================
func _recalculate_all_stats() -> void:
	"""
	Calcula TODOS os stats somando bonuses de TODOS os powerups ativos.
	Atualiza PowerUpStatsGlobal.
	"""
	print("\n🔄 Recalculating all stats...")
	
	# Soma todos os bonuses
	var total_max_health_flat := 0.0
	var total_max_health_percent := 0.0
	var total_move_speed_flat := 0.0
	var total_move_speed_percent := 0.0
	var total_damage_percent := 0.0
	var total_armor_flat := 0.0
	var total_magnet_flat := 0.0
	var total_attack_speed_percent := 0.0
	var total_projectile_speed_percent := 0.0  # NOVO v1.2.6
	var total_knockback_percent := 0.0  # NOVO v1.2.6
	
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
		
		var aspd_bonus = powerup.get_attack_speed_bonus()
		total_attack_speed_percent += aspd_bonus["percent"]
		
		# NOVO v1.2.6 - Lethal Impact
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
	
	# Calcula multiplicadores finais
	var stats = {
		"damage_multiplier": 1.0 + total_damage_percent,
		"max_health_bonus_flat": total_max_health_flat,
		"max_health_bonus_percent": total_max_health_percent,
		"move_speed_bonus_flat": total_move_speed_flat,
		"move_speed_bonus_percent": total_move_speed_percent,
		"armor": total_armor_flat,
		"magnet_range_bonus": total_magnet_flat,
		"attack_speed_multiplier": 1.0 + total_attack_speed_percent,
		"projectile_speed_multiplier": 1.0 + total_projectile_speed_percent,
		"knockback_multiplier": 1.0 + total_knockback_percent
	}
	
	# Atualiza global
	PowerUpStatsGlobal.update_stats(stats)
	
	# Aplica nos sistemas
	_apply_stats_to_player()


# =================================================
# APLICAR STATS NOS SISTEMAS
# =================================================
func _apply_stats_to_player() -> void:
	"""
	Aplica stats calculados no player e outros sistemas.
	"""
	if not player:
		return
	
	print("\n🎯 Applying stats to player systems...")
	
	# ===== MAX HEALTH =====
	# v1.3.4: Usar player_base_values Dictionary (padrão do AttackController)
	var new_max_health = (player_base_values["max_health"] + PowerUpStatsGlobal.max_health_bonus_flat) * (1.0 + PowerUpStatsGlobal.max_health_bonus_percent)
	
	var old_max = player.max_health
	player.max_health = new_max_health
	
	# v1.1.19 v3 FIX: HP aumenta pelo valor EXATO do aumento (não proporção!)
	if new_max_health > old_max:
		# HP máximo AUMENTOU
		var max_health_increase = new_max_health - old_max
		
		GameStateGlobal.player_max_health = new_max_health
		GameStateGlobal.player_health += max_health_increase  # Adiciona diferença!
		
		# Cap no novo máximo (se ultrapassar)
		if GameStateGlobal.player_health > new_max_health:
			GameStateGlobal.player_health = new_max_health
		
		GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
		print("  ❤️  Max Health: %.1f → %.1f (+%.1f HP)" % [old_max, new_max_health, max_health_increase])
	
	elif new_max_health < old_max:
		# HP máximo DIMINUIU (reset)
		GameStateGlobal.player_max_health = new_max_health
		
		# Se HP atual está acima do novo máximo, ajustar (cap)
		if GameStateGlobal.player_health > new_max_health:
			GameStateGlobal.player_health = new_max_health
			GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
			print("  ❤️  Max Health: %.1f → %.1f (HP capped to new max)" % [old_max, new_max_health])
		else:
			# HP atual está OK, só emite signal
			GameStateGlobal.player_health_changed.emit(GameStateGlobal.player_health, GameStateGlobal.player_max_health)
			print("  ❤️  Max Health: %.1f → %.1f" % [old_max, new_max_health])
	
	else:
		# Max health não mudou (edge case)
		print("  ❤️  Max Health: %.1f (unchanged)" % new_max_health)
	
	# ===== MOVE SPEED =====
	# v1.3.4: Usar player_base_values Dictionary (padrão do AttackController)
	var new_speed = (player_base_values["move_speed"] + PowerUpStatsGlobal.move_speed_bonus_flat) * (1.0 + PowerUpStatsGlobal.move_speed_bonus_percent)
	player.move_speed = new_speed
	print("  🏃 Move Speed: %.1f" % new_speed)
	
	# ===== DAMAGE (aplicado em BasePower ao dar hit) =====
	print("  💥 Damage Multiplier: ×%.2f (applied on hit)" % PowerUpStatsGlobal.damage_multiplier)
	
	# ===== ARMOR =====
	var reduction = PowerUpStatsGlobal.get_armor_damage_reduction()
	print("  🛡️  Armor: %.1f (%.0f%% damage reduction)" % [PowerUpStatsGlobal.armor, reduction * 100])
	
	# ===== MAGNET =====
	print("  🧲 Magnet Range: +%.1f (applied in XP items)" % PowerUpStatsGlobal.magnet_range_bonus)
	
	# ===== ATTACK SPEED =====
	print("  ⚡ Attack Speed: ×%.2f (applied in timers)" % PowerUpStatsGlobal.attack_speed_multiplier)
	
	# ===== PROJECTILE SPEED - NOVO v1.2.6 =====
	print("  🚀 Projectile Speed: ×%.2f (applied in powers)" % PowerUpStatsGlobal.projectile_speed_multiplier)
	
	# ===== KNOCKBACK - NOVO v1.2.6 =====
	print("  💫 Knockback: ×%.2f (applied on hit)" % PowerUpStatsGlobal.knockback_multiplier)
	
	print("✅ Stats applied!\n")


# =================================================
# HELPERS
# =================================================
func get_powerup_level(powerup_id: int) -> int:
	var powerup := _find_powerup(powerup_id)
	return powerup.current_level if powerup else 0

func list_active_powerups() -> void:
	"""Debug: lista powerups ativos"""
	print("\n📋 ACTIVE POWERUPS:")
	var has_active = false
	for powerup in powerups:
		if powerup and powerup.current_level > 0:
			print("  ✓ %s (Level %d/%d)" % [powerup.powerup_name, powerup.current_level, powerup.max_level])
			has_active = true
	
	if not has_active:
		print("  (none)")
	print("")
