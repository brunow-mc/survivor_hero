extends Node

# =================================================
# TEST ATTACK UPGRADES - v1.3.0
# =================================================
# [E] Fire+   [T] Ring+   [Y] Elec+
# [U] Bo+     [I] Gear+   [O] Snow+
# [X] List Levels
#
# SÓ SOBE NÍVEL, e sempre por attack_controller.apply_upgrade() — a mesma
# porta que o menu de level-up usa. Existiu um par de teclas para BAIXAR
# nível que escrevia `upgrade.current_level -= 1` direto no recurso, sem
# passar por validação nenhuma: era o único ponto do projeto que produzia
# um estado que o jogo real não alcança, e nunca teve uso. Se algum dia
# baixar nível virar mecânica de jogo, ela nasce no AttackController com
# validação própria, e esta ferramenta só chama.
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
			print("   [E] Fire+   [T] Ring+   [Y] Elec+")
			print("   [U] Bo+     [I] Gear+   [O] Snow+")
			print("   [X] List Levels\n")


func _input(event: InputEvent) -> void:
	if not attack_controller or not event is InputEventKey or not event.pressed:
		return
	
	match event.keycode:
		KEY_E: _raise(1, "Fire")
		KEY_T: _raise(2, "Ring")
		KEY_Y: _raise(3, "Elec")
		KEY_U: _raise(4, "Bo")
		KEY_I: _raise(5, "Gear")
		KEY_O: _raise(6, "Snow")
		KEY_X: _list()


func _raise(id: int, attack_name: String) -> void:
	var upgrade = attack_controller.find_upgrade(id)

	if not upgrade:
		print("⚠️ '%s' (ID %d) sem upgrade configurado" % [attack_name, id])
		return

	# v1.3.27: Usar apply_upgrade() unificado — mesma porta do menu de level-up.
	if not attack_controller.apply_upgrade(id):
		print("⚠️ '%s' já está em max (Lv%d)" % [attack_name, upgrade.max_level])
		return

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
