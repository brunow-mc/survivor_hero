extends Node
class_name AttackController

signal primary_attack_started

var player: CharacterBody2D
var attack_position_right: Node2D
var attack_position_left: Node2D

## ID do ataque primário deste personagem (fica ativo desde o início)
@export var primary_attack_id: int = 1

@export var attacks: Array[AttackData]
@export var attack_upgrades: Array[AttackUpgradeData] = []

var attack_timers: Dictionary = {}
var upgrade_last_levels: Dictionary = {}  ## Rastrear último level de cada upgrade

# -------------------------------------------------
# READY - v1.3.24: Sistema simplificado
# -------------------------------------------------
func _ready():
	_duplicate_and_initialize_upgrades()  # v1.3.24: Duplica upgrades + aplica primary_attack_id
	_apply_initial_upgrades()  # Aplica upgrades dos ataques ativos
	_initialize_upgrade_tracking()  # Rastreia mudanças de level
	
	# Conecta ao signal de mudança de stats para atualizar timers
	PowerUpStatsGlobal.stats_changed.connect(_on_stats_changed)


# -------------------------------------------------
# DUPLICATE AND INITIALIZE - v1.3.24
# -------------------------------------------------
func _duplicate_and_initialize_upgrades() -> void:
	"""
	v1.3.24: Duplica APENAS AttackUpgradeData e aplica configuração inicial.
	
	AttackData NÃO é duplicado - permanece compartilhado (apenas leitura).
	AttackUpgradeData É duplicado - cada player tem cópias isoladas.
	
	primary_attack_id define qual ataque começa ativo (Level 1).
	"""
	if attack_upgrades.size() == 0:
		print("⚠️ AttackController: No attack upgrades configured")
		return
	
	var duplicated: Array[AttackUpgradeData] = []
	
	for upgrade in attack_upgrades:
		if upgrade:
			var dup = upgrade.duplicate(true)
			
			# Duplicar arrays manualmente (workaround Godot)
			dup.projectile_count_per_level = _dup_int_arr(dup.projectile_count_per_level)
			dup.damage_bonus_per_level = _dup_float_arr(dup.damage_bonus_per_level)
			dup.speed_bonus_per_level = _dup_float_arr(dup.speed_bonus_per_level)
			dup.max_hits_per_level = _dup_int_arr(dup.max_hits_per_level)
			dup.cooldown_reduction_per_level = _dup_float_arr(dup.cooldown_reduction_per_level)
			dup.projectile_angle_spread_per_level = _dup_float_arr(dup.projectile_angle_spread_per_level)
			dup.life_time_bonus_per_level = _dup_float_arr(dup.life_time_bonus_per_level)
			dup.attack_scale_bonus_per_level = _dup_float_arr(dup.attack_scale_bonus_per_level)
			dup.projectile_stagger_delay_per_level = _dup_float_arr(dup.projectile_stagger_delay_per_level)
			dup.orbit_radius_per_level = _dup_float_arr(dup.orbit_radius_per_level)
			dup.orbit_speed_bonus_per_level = _dup_float_arr(dup.orbit_speed_bonus_per_level)
			
			# v1.3.24: Aplicar configuração inicial baseado em primary_attack_id
			if dup.attack_id == primary_attack_id:
				dup.current_level = 1  # Ataque primário começa ativo
			else:
				dup.current_level = 0  # Outros desligados
			
			duplicated.append(dup)
		else:
			duplicated.append(null)
	
	attack_upgrades = duplicated
	print("🔄 AttackController: Upgrade resources duplicated")
	print("   ✅ Primary attack ID %d set to Level 1" % primary_attack_id)


# -------------------------------------------------
# APPLY INITIAL UPGRADES - v1.3.7 | v1.3.11
# -------------------------------------------------
func _apply_initial_upgrades() -> void:
	"""
	v1.3.11: Aplica upgrades iniciais para attacks que começam com level > 0.
	Usa apenas upgrade.current_level (fonte única).
	"""
	for upgrade in attack_upgrades:
		if not upgrade or upgrade.current_level == 0:
			continue
		
		# Aplicar upgrades iniciais
		apply_upgrades_to_attack(upgrade.attack_id)
		print("⚡ Applied initial upgrades for '%s' (Lv%d)" % [upgrade.attack_name, upgrade.current_level])

# -------------------------------------------------
# INITIALIZE UPGRADE TRACKING - v1.3.10
# -------------------------------------------------
func _initialize_upgrade_tracking() -> void:
	"""
	v1.3.10: Inicializa Dictionary de rastreamento de levels de upgrades.
	Guarda o level inicial de cada upgrade para detecção de mudanças.
	"""
	for upgrade in attack_upgrades:
		if not upgrade:
			continue
		upgrade_last_levels[upgrade.attack_id] = upgrade.current_level
	
	print("🔄 AttackController: Upgrade tracking initialized")

func _dup_int_arr(arr: Array[int]) -> Array[int]:
	var dup: Array[int] = []
	for val in arr: dup.append(val)
	return dup

func _dup_float_arr(arr: Array[float]) -> Array[float]:
	var dup: Array[float] = []
	for val in arr: dup.append(val)
	return dup

func find_upgrade(attack_id: int) -> AttackUpgradeData:
	"""v1.3.0: Busca upgrade por attack_id (PÚBLICO para TestAttackUpgrades)"""
	for upgrade in attack_upgrades:
		if upgrade and upgrade.attack_id == attack_id:
			return upgrade
	return null

func find_attack_data(attack_id: int) -> AttackData:
	"""v1.3.0: Busca AttackData por attack_id (PÚBLICO para TestAttackUpgrades)"""
	for attack in attacks:
		if attack and attack.attack_id == attack_id:
			return attack
	return null

func apply_upgrades_to_attack(attack_id: int) -> void:
	"""
	v1.3.24: Calcula valores finais dinamicamente quando spawna ataque.
	
	NÃO modifica AttackData (permanece valores base).
	Retorna objeto temporário com valores calculados (base + upgrade bonuses).
	NOTA: Esta função agora é apenas para atualizar timers.
	Cálculo real acontece em get_attack_stats_with_upgrades().
	"""
	var attack_data = find_attack_data(attack_id)
	if not attack_data:
		return
	
	var upgrade = find_upgrade(attack_id)
	
	# Atualizar timer com interval correto
	var final_interval: float
	if upgrade and upgrade.current_level > 0:
		final_interval = attack_data.interval * (1.0 - upgrade.get_cooldown_reduction())
	else:
		final_interval = attack_data.interval
	
	var timer = attack_timers.get(attack_id)
	if timer:
		timer.wait_time = final_interval / PowerUpStatsGlobal.attack_speed_multiplier


func get_attack_stats_with_upgrades(attack_data: AttackData) -> Dictionary:
	"""
	v1.3.24: NOVA FUNÇÃO - Calcula stats finais em tempo real.
	
	Retorna Dictionary com valores base + upgrade bonuses.
	Usado no momento do spawn para aplicar upgrades sem modificar AttackData.
	"""
	var upgrade = find_upgrade(attack_data.attack_id)
	
	# Se não tem upgrade OU level = 0 → retorna valores base
	if not upgrade or upgrade.current_level == 0:
		return {
			"projectile_count": attack_data.projectile_count,
			"interval": attack_data.interval,
			"damage": attack_data.hit_data.damage,
			"speed": attack_data.speed,
			"max_hits": attack_data.max_hits,
			"projectile_angle_spread": attack_data.projectile_angle_spread,
			"life_time": attack_data.life_time,
			"attack_scale": attack_data.attack_scale,
			"projectile_stagger_delay": attack_data.projectile_stagger_delay,
			"orbit_radius": attack_data.orbit_radius,
			"orbit_speed": attack_data.orbit_speed
		}
	
	# TEM upgrade E level > 0 → calcular com bonuses
	return {
		"projectile_count": attack_data.projectile_count + upgrade.get_projectile_count_bonus(),
		"interval": attack_data.interval * (1.0 - upgrade.get_cooldown_reduction()),
		"damage": attack_data.hit_data.damage * (1.0 + upgrade.get_damage_bonus()),
		"speed": attack_data.speed * (1.0 + upgrade.get_speed_bonus()),
		"max_hits": attack_data.max_hits + upgrade.get_max_hits_bonus(),
		"projectile_angle_spread": attack_data.projectile_angle_spread + upgrade.get_projectile_angle_spread_bonus(),
		"life_time": attack_data.life_time + upgrade.get_life_time_bonus(),
		"attack_scale": attack_data.attack_scale * (1.0 + upgrade.get_attack_scale_bonus()),
		"projectile_stagger_delay": attack_data.projectile_stagger_delay + upgrade.get_projectile_stagger_delay_bonus(),
		"orbit_radius": attack_data.orbit_radius + upgrade.get_orbit_radius_bonus(),
		"orbit_speed": attack_data.orbit_speed * (1.0 + upgrade.get_orbit_speed_bonus())
	}


func create_attack_data_with_upgrades(attack_data: AttackData) -> AttackData:
	"""
	v1.3.24: Cria cópia TEMPORÁRIA do AttackData com upgrades aplicados.
	
	Esta cópia existe apenas durante o spawn e é passada para o power.
	O AttackData original permanece intocado.
	"""
	var temp_copy = attack_data.duplicate(true)
	
	# Duplicar HitData manualmente (workaround Godot)
	if temp_copy.hit_data:
		temp_copy.hit_data = temp_copy.hit_data.duplicate(true)
	
	var upgrade = find_upgrade(attack_data.attack_id)
	
	# Se não tem upgrade OU level = 0 → retorna cópia com valores base
	if not upgrade or upgrade.current_level == 0:
		return temp_copy
	
	# Aplicar upgrades na cópia temporária
	temp_copy.projectile_count = attack_data.projectile_count + upgrade.get_projectile_count_bonus()
	temp_copy.interval = attack_data.interval * (1.0 - upgrade.get_cooldown_reduction())
	temp_copy.hit_data.damage = attack_data.hit_data.damage * (1.0 + upgrade.get_damage_bonus())
	temp_copy.speed = attack_data.speed * (1.0 + upgrade.get_speed_bonus())
	temp_copy.max_hits = attack_data.max_hits + upgrade.get_max_hits_bonus()
	temp_copy.projectile_angle_spread = attack_data.projectile_angle_spread + upgrade.get_projectile_angle_spread_bonus()
	temp_copy.life_time = attack_data.life_time + upgrade.get_life_time_bonus()
	temp_copy.attack_scale = attack_data.attack_scale * (1.0 + upgrade.get_attack_scale_bonus())
	temp_copy.projectile_stagger_delay = attack_data.projectile_stagger_delay + upgrade.get_projectile_stagger_delay_bonus()
	temp_copy.orbit_radius = attack_data.orbit_radius + upgrade.get_orbit_radius_bonus()
	temp_copy.orbit_speed = attack_data.orbit_speed * (1.0 + upgrade.get_orbit_speed_bonus())
	
	return temp_copy

# -------------------------------------------------
# SETUP - v1.3.11
# -------------------------------------------------
func setup(
	_player: CharacterBody2D,
	_right: Node2D,
	_left: Node2D
) -> void:
	player = _player
	attack_position_right = _right
	attack_position_left = _left

	for attack_data in attacks:
		_create_attack_timer(attack_data)

# -------------------------------------------------
# PHYSICS PROCESS - v1.3.11
# -------------------------------------------------
func _physics_process(_delta: float) -> void:
	_check_upgrade_changes()  # v1.3.10/v1.3.11: Detecta mudanças em upgrades

# -------------------------------------------------
# CHECK UPGRADE CHANGES - v1.3.10 | v1.3.11
# -------------------------------------------------
func _check_upgrade_changes() -> void:
	"""
	v1.3.11: Detecta mudanças em upgrade.current_level (ÚNICA fonte de verdade).
	
	RESPONSABILIDADES:
	- Detecta mudanças em upgrade.current_level
	- Liga/desliga timers baseado no level
	- Aplica upgrades automaticamente
	
	FUNCIONA PARA:
	- Mudanças via código (test_attack_upgrades.gd)
	- Mudanças no Remote Inspector
	- Qualquer outra fonte de mudança
	"""
	for upgrade in attack_upgrades:
		if not upgrade:
			continue
		
		var attack_id = upgrade.attack_id
		var last_level = upgrade_last_levels.get(attack_id, upgrade.current_level)
		var current_level = upgrade.current_level
		
		# Detecta mudança
		if current_level != last_level:
			upgrade_last_levels[attack_id] = current_level
			
			# Controlar timer baseado no level
			var timer = attack_timers.get(attack_id)
			if timer:
				if current_level > 0 and last_level == 0:
					# Passou de 0 para > 0 → LIGAR timer
					timer.start()
					print("✅ Attack '%s' timer started (Lv0 → Lv%d)" % [upgrade.attack_name, current_level])
					# v1.4.2: start_immediately — disparo único imediato, timer segue normal
					var att_data = find_attack_data(attack_id)
					if att_data and att_data.start_immediately:
						_spawn_attack.call_deferred(att_data)
						print("⚡ Attack '%s' fired immediately (start_immediately)" % upgrade.attack_name)
				elif current_level == 0 and last_level > 0:
					# Passou de > 0 para 0 → DESLIGAR timer
					timer.stop()
					print("🛑 Attack '%s' timer stopped (Lv%d → Lv0)" % [upgrade.attack_name, last_level])
			
			# Aplicar upgrades com novos valores
			apply_upgrades_to_attack(attack_id)
			
			# Log para debug
			if current_level == 0:
				print("🔒 Upgrade '%s' LOCKED (auto-detected)" % upgrade.attack_name)
			elif last_level == 0:
				print("🔓 Upgrade '%s' UNLOCKED at Lv%d (auto-detected)" % [upgrade.attack_name, current_level])
			else:
				var arrow = "⬆️" if current_level > last_level else "⬇️"
				print("%s Upgrade '%s' Lv%d → Lv%d (auto-detected)" % [arrow, upgrade.attack_name, last_level, current_level])

# -------------------------------------------------
# SPAWN - v1.3.24
# -------------------------------------------------
func _spawn_attack(attack_data: AttackData) -> void:
	# Consultar upgrade.current_level (única fonte de verdade)
	var upgrade = find_upgrade(attack_data.attack_id)
	if not upgrade or upgrade.current_level <= 0:
		return
	
	if not is_instance_valid(player):
		return

	if not GameStateGlobal.is_combat_allowed():
		return

	if attack_data.attack_id == primary_attack_id:
		primary_attack_started.emit()

	if attack_data.attack_delay > 0.0:
		await get_tree().create_timer(attack_data.attack_delay, false).timeout

	if not is_instance_valid(player):
		return

	if not GameStateGlobal.is_combat_allowed():
		return

	# v1.3.24: Criar cópia TEMPORÁRIA com upgrades aplicados
	# AttackData original permanece intocado (valores base)
	var attack_with_upgrades = create_attack_data_with_upgrades(attack_data)

	# Sistema genérico de disparo sequencial/simultâneo
	# - Se projectile_stagger_delay = 0.0: disparo simultâneo (todos ao mesmo tempo)
	# - Se projectile_stagger_delay > 0.0: disparo sequencial (metralhadora)
	
	if attack_with_upgrades.projectile_stagger_delay > 0.0:
		# DISPARO SEQUENCIAL (metralhadora)
		for i in range(attack_with_upgrades.projectile_count):
			# TOCAR ÁUDIO no momento do spawn
			if attack_with_upgrades.attack_sound and not attack_with_upgrades.handles_own_audio:
				AudioManagerGlobal.play_sound(
					attack_with_upgrades.attack_sound,
					attack_with_upgrades.attack_sound_volume_db,
					attack_with_upgrades.attack_sound_pitch_scale
				)
			
			# SPAWNAR PROJÉTIL
			_spawn_single_projectile(attack_with_upgrades, i)
			
			# AGUARDAR antes do próximo (exceto no último)
			if i < attack_with_upgrades.projectile_count - 1:
				await get_tree().create_timer(attack_with_upgrades.projectile_stagger_delay, false).timeout
	else:
		# DISPARO SIMULTÂNEO (todos ao mesmo tempo)
		for i in range(attack_with_upgrades.projectile_count):
			# TOCAR ÁUDIO no momento do spawn (AudioManager limita automaticamente)
			if attack_with_upgrades.attack_sound and not attack_with_upgrades.handles_own_audio:
				AudioManagerGlobal.play_sound(
					attack_with_upgrades.attack_sound,
					attack_with_upgrades.attack_sound_volume_db,
					attack_with_upgrades.attack_sound_pitch_scale
				)
			
			# SPAWNAR PROJÉTIL
			_spawn_single_projectile(attack_with_upgrades, i)

# -------------------------------------------------
# SPAWN SINGLE PROJECTILE
# -------------------------------------------------
# SPAWN SINGLE PROJECTILE - v1.3.0: SIMPLIFICADO
# -------------------------------------------------
func _spawn_single_projectile(attack_data: AttackData, index: int) -> void:
	# v1.3.0: Upgrades já aplicados em _spawn_attack
	var attack = attack_data.packed_scene.instantiate()

	if attack_data.attach_to_player:
		player.add_child(attack)
	else:
		player.add_sibling(attack)

	if not attack_data.attach_to_player:
		if attack.has_method("set_power_direction"):
			var dir: int = int(player.facing_direction)
			if dir < 0:
				attack.global_position = attack_position_left.global_position
			else:
				attack.global_position = attack_position_right.global_position
			attack.set_power_direction(dir)
		else:
			attack.global_position = player.global_position

	if attack.has_method("set_attack_data"):
		attack.set_attack_data(attack_data)
	
	if attack.has_method("set_projectile_index"):
		attack.set_projectile_index(index, attack_data.projectile_count)

# -------------------------------------------------
# TIMER - v1.3.11
# -------------------------------------------------
func _create_attack_timer(attack_data: AttackData) -> void:
	"""
	Cria timer que só roda quando enabled = true.
	Timer inicia do ZERO quando enabled muda para true.
	v1.2.1: Aplica attack_speed_multiplier do PowerUpStatsGlobal.
	v1.3.11: Consulta upgrade.current_level (fonte única).
	"""
	var timer := Timer.new()
	# v1.2.1: Divide interval por attack_speed_multiplier
	# Exemplo: interval 2.0s, multiplier 1.5 → wait_time 1.33s (50% mais rápido!)
	timer.wait_time = attack_data.interval / PowerUpStatsGlobal.attack_speed_multiplier
	timer.one_shot = false
	timer.autostart = false
	
	timer.timeout.connect(func():
		_spawn_attack(attack_data)
	)
	
	add_child(timer)
	
	# v1.3.11: Inicia timer APENAS se upgrade já começa ativo (current_level > 0)
	var upgrade = find_upgrade(attack_data.attack_id)
	if upgrade and upgrade.current_level > 0:
		timer.start()
		# v1.4.2: start_immediately — disparo único imediato, timer segue normal
		if attack_data.start_immediately:
			_spawn_attack.call_deferred(attack_data)
			print("⚡ Attack '%s' fired immediately on game start (start_immediately)" % attack_data.attack_name)
	
	attack_timers[attack_data.attack_id] = timer

# -------------------------------------------------
# CONTROL - v1.1.18 | v1.3.11: Sistema de levels | v1.3.26: Unificado
# -------------------------------------------------
func apply_upgrade(attack_id: int) -> bool:
	"""
	v1.3.26: MÉTODO UNIFICADO para unlock e upgrade.
	Incrementa level do ataque (0→1, 1→2, 2→3, etc).
	Retorna true se sucesso, false se já está no max_level.
	
	PADRÃO: Mesma assinatura de PowerUpController.apply_upgrade()
	"""
	var upgrade = find_upgrade(attack_id)
	if not upgrade:
		push_warning("AttackController: Upgrade not found for attack_id %d" % attack_id)
		return false
	
	if upgrade.current_level >= upgrade.max_level:
		push_warning("⚠️ Attack '%s' already at max level %d" % [upgrade.attack_name, upgrade.max_level])
		return false
	
	var was_level = upgrade.current_level
	upgrade.current_level += 1
	
	if was_level == 0:
		print("✅ Attack '%s' unlocked (level %d)" % [upgrade.attack_name, upgrade.current_level])
	else:
		print("⬆️ Attack '%s' upgraded to level %d" % [upgrade.attack_name, upgrade.current_level])
	
	return true


func enable_attack(attack_id: int) -> void:
	"""
	DEPRECATED v1.3.26: Use apply_upgrade() instead.
	Mantido para compatibilidade com scripts de teste.
	"""
	apply_upgrade(attack_id)

func disable_attack(attack_id: int) -> void:
	"""
	v1.3.11: Bloqueia ataque (level → 0).
	Modifica upgrade.current_level (fonte única).
	Timer será parado automaticamente por _check_upgrade_changes().
	"""
	var upgrade = find_upgrade(attack_id)
	if not upgrade:
		push_warning("AttackController: Upgrade not found for attack_id %d" % attack_id)
		return
	
	upgrade.current_level = 0
	print("🛑 Attack '%s' locked" % upgrade.attack_name)

func upgrade_attack(attack_id: int) -> bool:
	"""
	DEPRECATED v1.3.26: Use apply_upgrade() instead.
	Mantido para compatibilidade com scripts de teste.
	"""
	return apply_upgrade(attack_id)


# -------------------------------------------------
# v1.2.1: ATTACK SPEED - Atualiza timers em tempo real
# -------------------------------------------------
func _on_stats_changed() -> void:
	"""
	Chamado quando PowerUpStatsGlobal muda (ex: powerup aplicado).
	Atualiza wait_time de todos os timers para refletir novo attack_speed_multiplier.
	"""
	for attack_data in attacks:
		if not attack_data:
			continue
		
		var timer = attack_timers.get(attack_data.attack_id)
		if not timer:
			continue
		
		# Recalcula wait_time com novo multiplier
		var new_wait_time = attack_data.interval / PowerUpStatsGlobal.attack_speed_multiplier
		
		# Só atualiza se realmente mudou (evita spam de atualizações)
		if abs(timer.wait_time - new_wait_time) > 0.001:
			timer.wait_time = new_wait_time
