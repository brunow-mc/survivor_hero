extends Node
class_name AttackController

signal primary_attack_started
signal attack_unlocked(attack_id: int, icon: Texture2D)  # v1.4.7: emitido por qualquer fonte

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
# CALIBRATION CONSTANTS
# -------------------------------------------------
# Cap de redução de cooldown por upgrade de ataque individual.
# Garante que o intervalo nunca zere ou inverta, mesmo com valores absurdos.
# Separado do ATTACK_SPEED_CAP_PERCENT de power_up_stats.gd porque são
# fontes distintas: este é por ataque, aquele é global (powerup).
const COOLDOWN_REDUCTION_CAP: float = 0.99

# Intervalo mínimo absoluto (segundos) — piso de segurança do timer.
const MIN_ATTACK_INTERVAL: float = 0.05

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
	NOTA: Esta função agora é apenas para atualizar timers.
	Cálculo real acontece em get_attack_stats_with_upgrades().
	"""
	var attack_data = find_attack_data(attack_id)
	if not attack_data:
		return
	
	var upgrade = find_upgrade(attack_id)
	
	var final_interval: float
	if upgrade and upgrade.current_level > 0:
		final_interval = attack_data.interval * (1.0 - minf(upgrade.get_cooldown_reduction(), COOLDOWN_REDUCTION_CAP))
	else:
		final_interval = attack_data.interval
	
	var timer = attack_timers.get(attack_id)
	if timer:
		timer.wait_time = _calc_wait_time(final_interval)


func get_attack_stats_with_upgrades(attack_data: AttackData) -> Dictionary:
	"""
	v1.3.24: NOVA FUNÇÃO - Calcula stats finais em tempo real.
	
	Retorna Dictionary com valores base + upgrade bonuses.
	Usado no momento do spawn para aplicar upgrades sem modificar AttackData.
	"""
	var upgrade = find_upgrade(attack_data.attack_id)
	
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
	
	return {
		"projectile_count": attack_data.projectile_count + upgrade.get_projectile_count_bonus(),
		"interval": attack_data.interval * (1.0 - minf(upgrade.get_cooldown_reduction(), COOLDOWN_REDUCTION_CAP)),
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
	
	if temp_copy.hit_data:
		temp_copy.hit_data = temp_copy.hit_data.duplicate(true)
	
	var upgrade = find_upgrade(attack_data.attack_id)
	
	if not upgrade or upgrade.current_level == 0:
		return temp_copy
	
	temp_copy.projectile_count = attack_data.projectile_count + upgrade.get_projectile_count_bonus()
	temp_copy.interval = attack_data.interval * (1.0 - minf(upgrade.get_cooldown_reduction(), COOLDOWN_REDUCTION_CAP))
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
	_check_upgrade_changes()

# -------------------------------------------------
# CHECK UPGRADE CHANGES - v1.3.10 | v1.3.11
# -------------------------------------------------
func _check_upgrade_changes() -> void:
	"""
	v1.3.11: Detecta mudanças em upgrade.current_level (ÚNICA fonte de verdade).
	v1.4.7: Emite attack_unlocked para qualquer fonte de desbloqueio.
	"""
	for upgrade in attack_upgrades:
		if not upgrade:
			continue
		
		var attack_id = upgrade.attack_id
		var last_level = upgrade_last_levels.get(attack_id, upgrade.current_level)
		var current_level = upgrade.current_level
		
		if current_level != last_level:
			upgrade_last_levels[attack_id] = current_level
			
			var timer = attack_timers.get(attack_id)
			if timer:
				if current_level > 0 and last_level == 0:
					timer.start()
					print("✅ Attack '%s' timer started (Lv0 → Lv%d)" % [upgrade.attack_name, current_level])
					var att_data = find_attack_data(attack_id)
					if att_data and att_data.start_immediately:
						_spawn_attack.call_deferred(att_data)
						print("⚡ Attack '%s' fired immediately (start_immediately)" % upgrade.attack_name)
					attack_unlocked.emit(attack_id, att_data.icon if att_data else null)
				elif current_level == 0 and last_level > 0:
					timer.stop()
					print("🛑 Attack '%s' timer stopped (Lv%d → Lv0)" % [upgrade.attack_name, last_level])
			
			apply_upgrades_to_attack(attack_id)
			
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

	var attack_with_upgrades = create_attack_data_with_upgrades(attack_data)

	if attack_with_upgrades.projectile_stagger_delay > 0.0:
		for i in range(attack_with_upgrades.projectile_count):
			if attack_with_upgrades.attack_sound and not attack_with_upgrades.handles_own_audio:
				AudioManagerGlobal.play_sound(
					attack_with_upgrades.attack_sound,
					attack_with_upgrades.attack_sound_volume_db,
					attack_with_upgrades.attack_sound_pitch_scale
				)
			_spawn_single_projectile(attack_with_upgrades, i)
			if i < attack_with_upgrades.projectile_count - 1:
				await get_tree().create_timer(attack_with_upgrades.projectile_stagger_delay, false).timeout
	else:
		for i in range(attack_with_upgrades.projectile_count):
			if attack_with_upgrades.attack_sound and not attack_with_upgrades.handles_own_audio:
				AudioManagerGlobal.play_sound(
					attack_with_upgrades.attack_sound,
					attack_with_upgrades.attack_sound_volume_db,
					attack_with_upgrades.attack_sound_pitch_scale
				)
			_spawn_single_projectile(attack_with_upgrades, i)

# -------------------------------------------------
# SPAWN SINGLE PROJECTILE
# -------------------------------------------------
func _spawn_single_projectile(attack_data: AttackData, index: int) -> void:
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
	var timer := Timer.new()
	timer.wait_time = _calc_wait_time(attack_data.interval)
	timer.one_shot = false
	timer.autostart = false
	
	timer.timeout.connect(func():
		_spawn_attack(attack_data)
	)
	
	add_child(timer)
	
	var upgrade = find_upgrade(attack_data.attack_id)
	if upgrade and upgrade.current_level > 0:
		timer.start()
		if attack_data.start_immediately:
			_spawn_attack.call_deferred(attack_data)
			print("⚡ Attack '%s' fired immediately on game start (start_immediately)" % attack_data.attack_name)
	
	attack_timers[attack_data.attack_id] = timer

# -------------------------------------------------
# CONTROL - v1.3.26: Unificado
# -------------------------------------------------
func apply_upgrade(attack_id: int) -> bool:
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
	"""DEPRECATED v1.3.26: Use apply_upgrade() instead."""
	apply_upgrade(attack_id)

func disable_attack(attack_id: int) -> void:
	var upgrade = find_upgrade(attack_id)
	if not upgrade:
		push_warning("AttackController: Upgrade not found for attack_id %d" % attack_id)
		return
	upgrade.current_level = 0
	print("🛑 Attack '%s' locked" % upgrade.attack_name)

func upgrade_attack(attack_id: int) -> bool:
	"""DEPRECATED v1.3.26: Use apply_upgrade() instead."""
	return apply_upgrade(attack_id)


# -------------------------------------------------
# ATTACK SPEED - cálculo centralizado
# -------------------------------------------------
func _calc_wait_time(base_interval: float) -> float:
	"""
	Calcula o wait_time final do timer a partir do intervalo base.
	
	Aplica a redução de attack speed vinda de powerups como percentual
	linear direto: interval * (1 - percent).
	
	O clamp e a conversão de multiplier→percent ficam em
	PowerUpStatsGlobal.get_attack_speed_reduction().
	
	Nota: cooldown_reduction dos upgrades de ataque NÃO entra aqui —
	deve ser aplicado em base_interval ANTES de chamar esta função,
	pois é específico de cada ataque.
	"""
	var aspd_reduction: float = PowerUpStatsGlobal.get_attack_speed_reduction()
	return maxf(base_interval * (1.0 - aspd_reduction), MIN_ATTACK_INTERVAL)

func _on_stats_changed() -> void:
	"""Atualiza timers de todos os ataques quando powerup de attack speed muda."""
	for attack_data in attacks:
		if not attack_data:
			continue
		
		var timer = attack_timers.get(attack_data.attack_id)
		if not timer:
			continue
		
		var upgrade = find_upgrade(attack_data.attack_id)
		var base_interval: float
		if upgrade and upgrade.current_level > 0:
			base_interval = attack_data.interval * (1.0 - minf(upgrade.get_cooldown_reduction(), COOLDOWN_REDUCTION_CAP))
		else:
			base_interval = attack_data.interval
		
		var new_wait_time = _calc_wait_time(base_interval)
		
		if abs(timer.wait_time - new_wait_time) > 0.001:
			timer.wait_time = new_wait_time
