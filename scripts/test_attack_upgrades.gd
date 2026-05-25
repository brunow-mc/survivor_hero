extends Node

# =================================================
# TEST ATTACK UPGRADES - v1.3.0
# =================================================
# [E] Fire++    [F] Fire--
# [T] Ring++    [G] Ring--
# [Y] Elec++    [H] Elec--
# [U] Bo++      [J] Bo--
# [I] Gear++    [K] Gear--
# [O] Snow++    [L] Snow--
# [X] List Levels
# =================================================

var attack_controller: AttackController = null

func _ready() -> void:
	await get_tree().process_frame
	
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var player = players[0]
		attack_controller = player.get_node_or_null("AttackController")
		
		if attack_controller:
			print("\n✅ TestAttackUpgrades: AttackController encontrado!")
			print("🎮 CONTROLES:")
			print("   [E] Fire++    [F] Fire--")
			print("   [T] Ring++    [G] Ring--")
			print("   [Y] Elec++    [H] Elec--")
			print("   [U] Bo++      [J] Bo--")
			print("   [I] Gear++    [K] Gear--")
			print("   [O] Snow++    [L] Snow--")
			print("   [X] List Levels\n")


func _input(event: InputEvent) -> void:
	if not attack_controller or not event is InputEventKey or not event.pressed:
		return
	
	match event.keycode:
		KEY_E: _change(1, 1, "Fire")
		KEY_F: _change(1, -1, "Fire")
		KEY_T: _change(2, 1, "Ring")
		KEY_G: _change(2, -1, "Ring")
		KEY_Y: _change(3, 1, "Elec")
		KEY_H: _change(3, -1, "Elec")
		KEY_U: _change(4, 1, "Bo")
		KEY_J: _change(4, -1, "Bo")
		KEY_I: _change(5, 1, "Gear")
		KEY_K: _change(5, -1, "Gear")
		KEY_O: _change(6, 1, "Snow")
		KEY_L: _change(6, -1, "Snow")
		KEY_X: _list()


func _change(id: int, delta: int, attack_name: String) -> void:
	var upgrade = attack_controller.find_upgrade(id)
	
	if not upgrade:
		print("⚠️ '%s' (ID %d) sem upgrade configurado" % [attack_name, id])
		return
	
	var old_level = upgrade.current_level
	
	# v1.3.27: Usar apply_upgrade() unificado
	if delta > 0:
		# Incrementar level
		var success = attack_controller.apply_upgrade(id)
		if not success:
			print("⚠️ '%s' já está em max (Lv%d)" % [attack_name, upgrade.max_level])
			return
	else:
		# Decrementar level (manipulação direta - não tem método para isso)
		if old_level == 0:
			print("⚠️ '%s' já está em min (Lv0)" % attack_name)
			return
		
		upgrade.current_level -= 1
		
		if upgrade.current_level == 0:
			print("🔒 '%s' LOCKED" % attack_name)
		else:
			print("⬇️ '%s' Lv%d → %d" % [attack_name, old_level, upgrade.current_level])
	
	_show_bonuses(upgrade)


func _show_bonuses(up: AttackUpgradeData) -> void:
	if up.current_level == 0:
		return
	
	var b = []
	var p = up.get_projectile_count_bonus()
	var d = up.get_damage_bonus()
	var s = up.get_speed_bonus()
	var h = up.get_max_hits_bonus()
	var c = up.get_cooldown_reduction()
	
	if p > 0: b.append("+%d proj" % p)
	if d > 0: b.append("+%.0f%% dmg" % (d * 100))
	if s > 0: b.append("+%.0f%% spd" % (s * 100))
	if h > 0: b.append("+%d hits" % h)
	if c > 0: b.append("-%.0f%% cd" % (c * 100))
	
	if b.size() > 0:
		print("   📊 %s" % ", ".join(b))


func _list() -> void:
	print("\n═══════════════════════════════════════")
	print("📋 ATTACK LEVELS")
	print("═══════════════════════════════════════")
	
	if attack_controller.attack_upgrades.size() == 0:
		print("Nenhum upgrade configurado")
		print("═══════════════════════════════════════\n")
		return
	
	for up in attack_controller.attack_upgrades:
		if not up:
			continue
		
		var st = "🔒 LOCKED" if up.current_level == 0 else "🔓 Lv%d/%d" % [up.current_level, up.max_level]
		print("\n%s: %s" % [up.attack_name, st])
		
		if up.current_level > 0:
			var p = up.get_projectile_count_bonus()
			var d = up.get_damage_bonus()
			var s = up.get_speed_bonus()
			var h = up.get_max_hits_bonus()
			var c = up.get_cooldown_reduction()
			
			if p > 0: print("  • Proj: +%d" % p)
			if d > 0: print("  • Damage: +%.0f%%" % (d * 100))
			if s > 0: print("  • Speed: +%.0f%%" % (s * 100))
			if h > 0: print("  • Hits: +%d" % h)
			if c > 0: print("  • Cooldown: -%.0f%%" % (c * 100))
	
	print("═══════════════════════════════════════\n")
