extends Node

# =================================================
# TEST POWERUPS - v1.2.6 | v1.3.2
# =================================================
# Sistema de debug para testar powerups com teclas.
# [1-8] = Aplica powerups
# [R] = Reset (remove todos)
# [L] = Lista powerups ativos
# [S] = Mostra stats atuais
# =================================================

var powerup_controller: PowerUpController = null

func _ready() -> void:
	# Aguarda player estar pronto
	await get_tree().process_frame
	
	# Busca PowerUpController
	var players = get_tree().get_nodes_in_group("Player")  # Case-sensitive!
	if players.size() > 0:
		var player = players[0]
		powerup_controller = player.get_node_or_null("PowerUpController")
		
		if powerup_controller:
			print("\n✅ TestPowerups: PowerUpController encontrado!")
			print("🎮 CONTROLES:")
			print("   [1] = Vitality (Max Health)")
			print("   [2] = Swift Feet (Move Speed)")
			print("   [3] = Raw Power (Damage)")
			print("   [4] = Iron Skin (Armor)")
			print("   [5] = Warrior's Might (HP + Damage)")
			print("   [6] = Magnetic Field (Magnet Range)")
			print("   [7] = Rapid Fire (Attack Speed)")
			print("   [8] = Lethal Impact (Speed + Knockback + Damage)")
			print("   [R] = Reset All Powerups")
			print("   [L] = List Active Powerups")
			print("   [S] = Show Current Stats\n")
		else:
			print("⚠️ TestPowerups: PowerUpController não encontrado no player!")
	else:
		print("⚠️ TestPowerups: Player não encontrado!")


func _input(event: InputEvent) -> void:
	if not powerup_controller:
		return
	
	if not event is InputEventKey or not event.pressed:
		return
	
	match event.keycode:
		KEY_1:
			print("\n🔑 KEY [1] PRESSED")
			_try_apply(1, "Vitality")
		
		KEY_2:
			print("\n🔑 KEY [2] PRESSED")
			_try_apply(2, "Swift Feet")
		
		KEY_3:
			print("\n🔑 KEY [3] PRESSED")
			_try_apply(3, "Raw Power")
		
		KEY_4:
			print("\n🔑 KEY [4] PRESSED")
			_try_apply(4, "Iron Skin")
		
		KEY_5:
			print("\n🔑 KEY [5] PRESSED")
			_try_apply(5, "Warrior's Might")
		
		KEY_6:
			print("\n🔑 KEY [6] PRESSED")
			_try_apply(6, "Magnetic Field")
		
		KEY_7:
			print("\n🔑 KEY [7] PRESSED")
			_try_apply(7, "Rapid Fire")
		
		KEY_8:
			print("\n🔑 KEY [8] PRESSED")
			_try_apply(8, "Lethal Impact")
		
		KEY_R:
			print("\n🔑 KEY [R] PRESSED - RESET ALL")
			_reset_all_powerups()
		
		KEY_L:
			print("\n🔑 KEY [L] PRESSED - LIST ACTIVE")
			powerup_controller.list_active_powerups()
		
		KEY_S:
			print("\n🔑 KEY [S] PRESSED - SHOW STATS")
			_show_current_stats()


func _try_apply(powerup_id: int, powerup_name: String) -> void:
	"""
	v1.3.2: Validação prévia antes de aplicar powerup
	v1.3.27: Usa apply_upgrade() unificado
	"""
	var powerup = powerup_controller.get_powerup(powerup_id)
	
	if not powerup:
		print("⚠️ '%s' (ID %d) não encontrado" % [powerup_name, powerup_id])
		return
	
	if powerup.current_level >= powerup.max_level:
		print("⚠️ '%s' já está no max level %d" % [powerup_name, powerup.max_level])
		return
	
	powerup_controller.apply_upgrade(powerup_id)


func _reset_all_powerups() -> void:
	"""Remove todos os powerups ativos"""
	print("🔄 Removing all powerups...")
	for i in range(1, 9):  # 1 a 8 (CORRIGIDO: inclui Lethal Impact)
		powerup_controller.remove_powerup(i)
	print("✅ All powerups removed\n")


func _show_current_stats() -> void:
	"""Mostra stats atuais do PowerUpStatsGlobal"""
	print("\n═══════════════════════════════════════════════════")
	print("📊 CURRENT PLAYER STATS")
	print("═══════════════════════════════════════════════════")
	print("💥 Damage Multiplier:      ×%.2f" % PowerUpStatsGlobal.damage_multiplier)
	print("❤️  Max Health Flat:       +%.1f" % PowerUpStatsGlobal.max_health_bonus_flat)
	print("❤️  Max Health Percent:    +%.0f%%" % (PowerUpStatsGlobal.max_health_bonus_percent * 100))
	print("🏃 Move Speed Flat:        +%.1f" % PowerUpStatsGlobal.move_speed_bonus_flat)
	print("🏃 Move Speed Percent:     +%.0f%%" % (PowerUpStatsGlobal.move_speed_bonus_percent * 100))
	print("🛡️  Armor:                  %.1f (%.0f%% reduction)" % [PowerUpStatsGlobal.armor, PowerUpStatsGlobal.get_armor_damage_reduction() * 100])
	print("🧲 Magnet Range Bonus:     +%.1f" % PowerUpStatsGlobal.magnet_range_bonus)
	print("⚡ Attack Speed Multiplier: ×%.2f" % PowerUpStatsGlobal.attack_speed_multiplier)
	print("🚀 Projectile Speed Mult:  ×%.2f" % PowerUpStatsGlobal.projectile_speed_multiplier)
	print("💫 Knockback Multiplier:   ×%.2f" % PowerUpStatsGlobal.knockback_multiplier)
	print("═══════════════════════════════════════════════════\n")
