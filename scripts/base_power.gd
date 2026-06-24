extends Area2D
class_name BasePower


# IMPORTANTE:
# Se uma classe filha sobrescrever _physics_process,
# ela DEVE chamar super._physics_process(delta)


# -------------------------------------------------
# DADOS DE ATAQUE
# -------------------------------------------------
var hit_data: HitData
var attack_data: AttackData
var damage_interval: float = 0.0


# -------------------------------------------------
# TEMPO DE VIDA
# -------------------------------------------------
var life_time: float = 0.0
var max_life_time: float = 0.0


# -------------------------------------------------
# CONTROLE DE DANO POR INIMIGO
# -------------------------------------------------
# enemy : last_hit_time (em segundos)
var enemies_last_hit: Dictionary = {}


# -------------------------------------------------
# CICLO DE VIDA BASE
# -------------------------------------------------
func _ready() -> void:
	add_to_group("Power")


func _physics_process(delta: float) -> void:
	_update_life_time(delta)


# -------------------------
# LIFE TIME
# -------------------------
func _update_life_time(delta: float) -> bool:
	if max_life_time <= 0.0:
		return false

	life_time += delta
	if life_time >= max_life_time:
		on_life_time_end()
		return true

	return false


# -------------------------
# EVENTO DE FIM DE VIDA
# -------------------------
# Cada Power decide o que fazer (fade, explode, etc)
func on_life_time_end() -> void:
	queue_free()


# -------------------------------------------------
# COLISÃO BASE (DANO)
# -------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("EnemyHurtbox"):
		return

	var enemy := area.get_parent()
	if enemy == null or not enemy.has_method("receive_hit"):
		return

	var now := Time.get_ticks_msec() / 1000.0

	# já foi atingido recentemente?
	if enemies_last_hit.has(enemy):
		var last_time: float = enemies_last_hit[enemy]
		if now - last_time < damage_interval:
			return

	# registra o hit
	enemies_last_hit[enemy] = now

	var modified_hit_data = hit_data.duplicate(true)

	# Soma linear: upgrade individual + powerup global, aplicados uma vez só.
	# damage_upgrade_bonus vem do attack_controller (upgrade por ataque).
	# (damage_multiplier - 1.0) é o percentual acumulado dos powerups globais.
	var total_damage_bonus: float = hit_data.damage_upgrade_bonus + (PowerUpStatsGlobal.damage_multiplier - 1.0)
	modified_hit_data.damage = hit_data.damage * (1.0 + total_damage_bonus)

	# v1.2.6: Aplicar knockback multiplier global
	modified_hit_data.knockback_force = hit_data.knockback_force * PowerUpStatsGlobal.knockback_multiplier

	# aplica dano
	enemy.receive_hit(modified_hit_data, global_position)


# -------------------------------------------------
# INTERFACE COM ATTACK CONTROLLER
# -------------------------------------------------
func set_attack_data(data: AttackData) -> void:
	attack_data = data
	hit_data = data.hit_data
	max_life_time = data.life_time
	damage_interval = data.damage_interval
	
	# NOVO v1.1.15: Aplicar escala do ataque
	_apply_attack_scale()


# -------------------------------------------------
# SCALE - NOVO v1.1.15
# -------------------------------------------------
func _apply_attack_scale() -> void:
	"""
	Aplica attack_scale aos nodes relevantes (CollisionShape2D e AnimatedSprite2D).
	Genérico para todos os powers que herdam BasePower.
	"""
	if not attack_data:
		return
	
	var scale_vec := Vector2(attack_data.attack_scale, attack_data.attack_scale)
	
	for child in get_children():
		if child is CollisionShape2D or child is AnimatedSprite2D:
			child.scale = scale_vec


# -------------------------
# GETTERS
# -------------------------
func get_hit_data() -> HitData:
	return hit_data


func get_attack_data() -> AttackData:
	return attack_data


# -------------------------------------------------
# HELPER: CÁLCULO DE ÂNGULOS DE DISPERSÃO (v1.1.7)
# -------------------------------------------------
# Calcula ângulos para dispersão de projéteis em padrão de "leque"
# Usado por poderes que disparam múltiplos projéteis com ângulos diferentes
#
# LÓGICA:
# - Ímpar (1, 3, 5...): Tem projétil central (0°) + simétricos
# - Par (2, 4, 6...): Sem central, todos simétricos
#
# EXEMPLOS (spread_angle = 30°):
# count=1: [0]
# count=2: [-15, +15]
# count=3: [-30, 0, +30]
# count=4: [-45, -15, +15, +45]
# count=5: [-60, -30, 0, +30, +60]
func calculate_projectile_spread_angles(count: int, spread_angle: float) -> Array:
	var angles: Array = []
	
	if count == 1:
		angles.append(0.0)
		return angles
	
	# ÍMPAR: Tem centro (0°)
	if count % 2 == 1:
		var half_count = floori((count - 1.0) / 2.0)
		angles.append(0.0)  # Centro
		
		for i in range(1, half_count + 1):
			var angle = spread_angle * i
			angles.append(-angle)  # Baixo (negativo)
			angles.append(angle)   # Cima (positivo)
	
	# PAR: Sem centro
	else:
		var half_count = floori(count / 2.0)
		var start_angle = spread_angle / 2.0  # Começa em ±spread/2
		
		for i in range(half_count):
			var angle = start_angle + (spread_angle * i)
			angles.append(-angle)  # Baixo
			angles.append(angle)   # Cima
	
	angles.sort()
	return angles


# =================================================
# ENEMY TARGETING - NOVO v1.3.16
# =================================================

func find_nearest_enemy_on_screen(margin: float = 50.0) -> Node2D:
	"""
	v1.3.16: Encontra inimigo mais próximo DENTRO da tela visível.
	
	Usado por ataques teleguiados (Ring, Boomerang) para evitar mirar 
	em inimigos muito distantes fora da tela.
	
	Retorna null se não houver inimigos na tela.
	"""
	var viewport = get_viewport()
	if not viewport:
		return null
	
	var camera = viewport.get_camera_2d()
	if not camera:
		return _find_nearest_enemy_global()  # Fallback
	
	# Calcular área visível com margem
	var viewport_size = viewport.get_visible_rect().size
	var screen_center = camera.get_screen_center_position()
	var screen_rect = Rect2(
		screen_center - viewport_size / 2 - Vector2(margin, margin),
		viewport_size + Vector2(margin * 2, margin * 2)
	)
	
	# Filtrar inimigos na tela e encontrar o mais próximo
	var enemies = get_tree().get_nodes_in_group("Enemy")
	var nearest: Node2D = null
	var nearest_dist = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Verificar se está dentro da área visível
		if not screen_rect.has_point(enemy.global_position):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	
	return nearest


func find_random_enemy_on_screen(margin: float = 50.0) -> Node2D:
	"""
	v1.3.21b: Encontra inimigo ALEATÓRIO dentro da tela visível.
	
	Usa TargetTrackerGlobal para evitar repetição excessiva:
	- Prioriza inimigos NÃO recentemente targetados
	- Permite repetição se todos já foram usados recentemente
	- Reset automático entre batches (passa interval para detecção)
	
	Usado por ataques de área direcionada (Snowflake) que precisam
	escolher um alvo aleatório na tela.
	
	Retorna null se não houver inimigos na tela.
	"""
	var viewport = get_viewport()
	if not viewport:
		return null
	
	var camera = viewport.get_camera_2d()
	if not camera:
		return null
	
	# Calcular área visível com margem
	var viewport_size = viewport.get_visible_rect().size
	var screen_center = camera.get_screen_center_position()
	var screen_rect = Rect2(
		screen_center - viewport_size / 2 - Vector2(margin, margin),
		viewport_size + Vector2(margin * 2, margin * 2)
	)
	
	# Coletar todos inimigos na tela
	var enemies = get_tree().get_nodes_in_group("Enemy")
	var on_screen: Array[Node2D] = []
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		if screen_rect.has_point(enemy.global_position):
			on_screen.append(enemy)
	
	# Se não há inimigos, retornar null
	if on_screen.size() == 0:
		return null
	
	# v1.3.21b: SISTEMA DE EXCLUSÃO TEMPORÁRIA COM AUTO-RESET
	# Tentar evitar inimigos recentemente targetados
	var available = TargetTrackerGlobal.get_non_recent_enemies(on_screen)
	
	var chosen: Node2D = null
	
	if available.size() > 0:
		# Preferir inimigos não usados recentemente
		chosen = available.pick_random()
	else:
		# Se todos foram usados, permitir repetição
		chosen = on_screen.pick_random()
	
	# Marcar escolhido como recentemente targetado
	# v1.3.21b: Passa interval para detecção automática de novo batch
	if chosen and attack_data:
		TargetTrackerGlobal.add_target(chosen, attack_data.interval)
	elif chosen:
		TargetTrackerGlobal.add_target(chosen)
	
	return chosen


func _find_nearest_enemy_global() -> Node2D:
	"""
	Busca global sem filtro de tela (fallback).
	Usado quando não há câmera ou como alternativa.
	"""
	var enemies = get_tree().get_nodes_in_group("Enemy")
	if enemies.is_empty():
		return null
	
	var nearest: Node2D = null
	var nearest_dist = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	
	return nearest
