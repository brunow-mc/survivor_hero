extends BasePower

# -------------------------------------------------
# NODES
# -------------------------------------------------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D


# =================================================
# CONFIGURAÇÃO DO BO - v1.2.2
# =================================================
var speed: float = 0.0
var current_speed: float = 0.0
var direction: int = 1

@export_group("Movement")
@export var forward_distance: float = 168.0
## Alcance máximo TOTAL do boomerang (ida + desaceleração).
## O boomerang sempre para e retorna ao atingir esta distância,
## independente da velocidade. Este é o LIMITE ABSOLUTO de alcance.

@export var slow_down_start_distance: float = 80.0
## Distância em que o boomerang inicia a desaceleração.
## Deve ser menor que forward_distance.
## Exemplo: 80px de ida rápida + 88px desacelerando = 168px total.

@export var return_accel_time: float = 0.35
## Tempo de aceleração no retorno (em segundos).

@export var return_speed_factor: float = 1.5
## Multiplicador de velocidade no retorno.
## 1.5 = retorna 50% mais rápido que foi.

@export var arrive_distance: float = 16.0
## Distância mínima ao player para considerar "chegou" e destruir.

@export var screen_edge_tolerance: float = 10.0
## Distância em pixels além das bordas da tela onde inimigos ainda podem ser detectados.


# -------------------------------------------------
# ESTADO DE MOVIMENTO
# -------------------------------------------------
enum BoState {
	GOING_FORWARD,
	SLOWING_DOWN,
	RETURNING
}

var state: BoState = BoState.GOING_FORWARD


# -------------------------------------------------
# MOVIMENTO - v1.3.18
# -------------------------------------------------
var move_direction: Vector2 = Vector2.ZERO
var traveled_distance: float = 0.0
var return_traveled_distance: float = 0.0
var player_ref: Node2D = null
var tween: Tween = null


# -------------------------------------------------
# CONTROLE DE HITS
# -------------------------------------------------
var max_hits: int = -1
var hits_done: int = 0


# =================================================
# DANO CONTÍNUO
# =================================================
# Dictionary: enemy → Timer
var enemies_in_contact: Dictionary = {}


# =================================================
# ESCALA DINÂMICA - v1.1.15 | v1.3.13 | v1.3.18
# =================================================
var current_scale: float = 1.0
var max_forward_distance: float = 0.0
var initial_player_distance: float = 0.0
var target_scale: float = 1.0  # v1.3.13: Snapshot do scale no spawn


# -------------------------------------------------
# READY
# -------------------------------------------------
func _ready() -> void:
	add_to_group("Power")

	player_ref = get_tree().get_first_node_in_group("Player")

	await get_tree().process_frame
	define_initial_direction()
	
	# Calcular distância total para sistema de escala
	_calculate_max_forward_distance()
	
	# Guardar distância inicial ao player (para cálculo de volta)
	if is_instance_valid(player_ref):
		initial_player_distance = global_position.distance_to(player_ref.global_position)

	# =================================================
	# ÁUDIO DE IDA - v1.2.2
	# =================================================
	# Toca som primary do AttackData (ida)
	if attack_data and attack_data.attack_sound:
		AudioManagerGlobal.play_sound_2d(
			attack_data.attack_sound,
			global_position,
			attack_data.attack_sound_volume_db,
			attack_data.attack_sound_pitch_scale
		)


# -------------------------------------------------
# PROCESS
# -------------------------------------------------
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Atualizar escala baseada em progresso
	_update_scale()
	
	# Limpa inimigos mortos do Dictionary a cada frame
	_cleanup_freed_enemies()

	match state:
		BoState.GOING_FORWARD:
			process_forward(delta)
		BoState.SLOWING_DOWN:
			process_slow_down(delta)
		BoState.RETURNING:
			process_return(delta)


# =================================================
# ESCALA DINÂMICA - v1.1.15 | v1.3.13 | v1.3.18
# =================================================
func _calculate_max_forward_distance() -> void:
	"""
	v1.2.2: Agora forward_distance JÁ É o alcance total.
	Esta função apenas garante que max_forward_distance = forward_distance.
	Mantida para compatibilidade com sistema de escala.
	"""
	max_forward_distance = forward_distance


func _update_scale() -> void:
	"""
	v1.3.18: Suaviza APENAS o scale final (não a distância).
	
	Lê distância real ao player, mas aplica lerp no scale para evitar saltos.
	Um único lerp garante convergência e mantém suavidade visual.
	
	v1.3.13: Usa target_scale (snapshot) ao invés de ler attack_data continuamente.
	Chamada a cada _physics_process.
	"""
	if not attack_data:
		return
	
	match state:
		BoState.GOING_FORWARD, BoState.SLOWING_DOWN:
			# IDA: Cresce de 1.0 até target_scale
			var progress = 0.0
			if max_forward_distance > 0:
				progress = min(traveled_distance / max_forward_distance, 1.0)
			
			var desired_scale = lerp(1.0, target_scale, progress)
			current_scale = lerp(current_scale, desired_scale, 0.2)
		
		BoState.RETURNING:
			# VOLTA: Lê distância real, mas suaviza apenas o scale
			if not is_instance_valid(player_ref):
				return
			
			# Distância REAL (sem lerp na distância)
			var current_dist = global_position.distance_to(player_ref.global_position)
			
			# Calcula qual scale deveria ser
			var progress = 0.0
			if max_forward_distance > 0:
				progress = 1.0 - clamp(current_dist / max_forward_distance, 0.0, 1.0)
			
			var desired_scale = lerp(target_scale, 1.0, progress)
			
			# Suaviza APENAS o scale (convergirá para o alvo)
			current_scale = lerp(current_scale, desired_scale, 0.2)
	
	# Aplicar escala aos nodes
	_apply_current_scale()


func _apply_current_scale() -> void:
	"""
	Aplica current_scale ao CollisionShape2D e AnimatedSprite2D.
	"""
	var scale_vec := Vector2(current_scale, current_scale)
	
	for child in get_children():
		if child is CollisionShape2D or child is AnimatedSprite2D:
			child.scale = scale_vec


# -------------------------------------------------
# DIREÇÃO INICIAL - v1.3.16
# -------------------------------------------------
func define_initial_direction() -> void:
	# v1.3.16: Usa find_nearest_enemy_on_screen() do BasePower
	var enemy := find_nearest_enemy_on_screen(screen_edge_tolerance)

	if enemy:
		move_direction = (enemy.global_position - global_position).normalized()
	else:
		move_direction = Vector2(direction, 0).normalized()


# =================================================
# MOVIMENTO — IDA
# =================================================
func process_forward(delta: float) -> void:
	var displacement := move_direction * current_speed * delta
	global_position += displacement
	traveled_distance += displacement.length()

	# Inicia desaceleração ao atingir slow_down_start_distance
	if traveled_distance >= slow_down_start_distance:
		start_slow_down()


# =================================================
# DESACELERAÇÃO - v1.2.2 SOLUÇÃO 3
# =================================================
func start_slow_down() -> void:
	"""
	v1.2.2: Tween baseado em DISTÂNCIA, não tempo.
	Calcula matematicamente o tempo necessário para desacelerar
	de current_speed até 0 percorrendo exatamente a distância restante
	até forward_distance.
	"""
	state = BoState.SLOWING_DOWN

	# Distância restante até o limite absoluto
	var remaining_distance = forward_distance - traveled_distance
	
	# Proteção: se já passou do limite (edge case), volta imediatamente
	if remaining_distance <= 0:
		current_speed = 0.0
		traveled_distance = forward_distance
		start_return()
		return
	
	# Proteção: se velocidade muito baixa, evita divisão por zero
	if current_speed < 1.0:
		current_speed = 0.0
		start_return()
		return
	
	# ════════════════════════════════════════════════════════════════
	# MATEMÁTICA: Movimento Uniformemente Variado (desaceleração)
	# ════════════════════════════════════════════════════════════════
	# Fórmula: distance = (v_initial + v_final) / 2 * time
	# 
	# Sabemos:
	# - distance = remaining_distance (distância a percorrer)
	# - v_initial = current_speed (velocidade atual)
	# - v_final = 0 (queremos parar)
	# 
	# Resolvendo para time:
	# remaining_distance = (current_speed + 0) / 2 * time
	# remaining_distance = (current_speed / 2) * time
	# time = remaining_distance / (current_speed / 2)
	# time = (2 * remaining_distance) / current_speed
	# ════════════════════════════════════════════════════════════════
	
	var tween_duration = (2.0 * remaining_distance) / current_speed
	
	# Limita duração mínima e máxima para evitar valores absurdos
	tween_duration = clamp(tween_duration, 0.1, 2.0)
	
	if tween:
		tween.kill()

	tween = create_tween()
	tween.tween_property(self, "current_speed", 0.0, tween_duration)


func process_slow_down(delta: float) -> void:
	"""
	v1.2.2: Move durante desaceleração com limite HARD.
	Mesmo que tween não termine, para forçadamente ao atingir forward_distance.
	"""
	var displacement := move_direction * current_speed * delta
	global_position += displacement
	traveled_distance += displacement.length()
	
	# ════════════════════════════════════════════════════════════════
	# LIMITE HARD: Para forçadamente ao atingir forward_distance
	# ════════════════════════════════════════════════════════════════
	# Garante que NUNCA ultrapassa o limite, mesmo com:
	# - Velocidades muito altas
	# - Frame rate baixo (delta grande)
	# - Erros de cálculo do tween
	# ════════════════════════════════════════════════════════════════
	if traveled_distance >= forward_distance:
		current_speed = 0.0
		traveled_distance = forward_distance  # Força exatidão
		
		# Mata tween se ainda estiver rodando
		if tween and tween.is_running():
			tween.kill()
		
		start_return()
		return
	
	# Para também se velocidade chegou a zero naturalmente (tween terminou)
	if current_speed <= 1.0:
		start_return()


# =================================================
# RETORNO (ACELERAÇÃO) - v1.3.18
# =================================================
func start_return() -> void:
	state = BoState.RETURNING
	current_speed = 0.0
	return_traveled_distance = 0.0

	if tween:
		tween.kill()

	tween = create_tween()
	tween.tween_property(
		self,
		"current_speed",
		speed * return_speed_factor,
		return_accel_time
	)
	
	# =================================================
	# ÁUDIO DE RETORNO - v1.2.2
	# =================================================
	# Delay curto antes de tocar (mesma lógica do áudio anterior)
	await get_tree().create_timer(0.09, false).timeout
	
	# Toca som SECONDARY do AttackData (volta)
	# Se secondary_sound for null, não toca nada
	if attack_data and attack_data.secondary_sound:
		AudioManagerGlobal.play_sound_2d(
			attack_data.secondary_sound,
			global_position,
			attack_data.secondary_sound_volume_db,
			attack_data.secondary_sound_pitch_scale
		)


# =================================================
# MOVIMENTO — VOLTA (TELEGUIADO) - v1.3.18
# =================================================
func process_return(delta: float) -> void:
	if not is_instance_valid(player_ref):
		queue_free()
		return

	var to_player := player_ref.global_position - global_position
	var distance := to_player.length()

	if distance <= arrive_distance:
		queue_free()
		return

	var return_dir := to_player.normalized()
	var displacement := return_dir * current_speed * delta
	global_position += displacement
	
	return_traveled_distance += displacement.length()


# =================================================
# COLISÃO - SISTEMA HÍBRIDO COM RESET
# =================================================
func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("EnemyHurtbox"):
		return

	var enemy := area.get_parent()
	if enemy == null or not is_instance_valid(enemy):
		return

	# PRIMEIRO HIT (via BasePower)
	# BasePower verificará enemies_last_hit automaticamente
	super._on_area_entered(area)

	hits_done += 1

	if max_hits != -1 and hits_done >= max_hits:
		queue_free()
		return

	# Inicia dano contínuo (se ainda não estiver ativo)
	_start_continuous_damage(enemy, area)


# =================================================
# DANO CONTÍNUO
# =================================================
func _start_continuous_damage(enemy: Node, area: Area2D) -> void:
	# Já está recebendo ticks
	if enemies_in_contact.has(enemy):
		return

	# Validação extra
	if not is_instance_valid(enemy):
		return

	# Cria timer de dano contínuo
	var t := Timer.new()
	t.wait_time = damage_interval
	t.one_shot = false

	t.timeout.connect(func():
		# Valida se inimigo ainda existe
		if not is_instance_valid(enemy):
			if is_instance_valid(t):
				t.stop()
				t.queue_free()
			return
		
		# Valida se área ainda existe
		if not is_instance_valid(area):
			if is_instance_valid(t):
				t.stop()
				t.queue_free()
			return

		# Força nova tentativa de dano
		super._on_area_entered(area)
		
		hits_done += 1
		
		# Verifica max_hits
		if max_hits != -1 and hits_done >= max_hits:
			queue_free()
	)

	add_child(t)
	enemies_in_contact[enemy] = t
	t.start()


func _on_area_exited(area: Area2D) -> void:
	if not area.is_in_group("EnemyHurtbox"):
		return

	var enemy := area.get_parent()
	if enemy == null:
		return

	# Para o timer contínuo
	_stop_continuous_damage(enemy)
	
	# RESETA O TIMER DE DAMAGE_INTERVAL
	# Isso permite que o próximo area_entered seja
	# tratado como "primeiro hit", independente do tempo
	_reset_damage_interval_for_enemy(enemy)


func _stop_continuous_damage(enemy: Node) -> void:
	if not enemies_in_contact.has(enemy):
		return
	
	var t = enemies_in_contact.get(enemy)
	if is_instance_valid(t):
		t.stop()
		t.queue_free()
	
	enemies_in_contact.erase(enemy)


# =================================================
# RESET DE DAMAGE INTERVAL
# =================================================
func _reset_damage_interval_for_enemy(enemy: Node) -> void:
	"""
	Remove o inimigo do enemies_last_hit (do BasePower).
	Isso faz com que o próximo area_entered seja tratado
	como um novo "primeiro hit", independente do damage_interval.
	"""
	if not is_instance_valid(enemy):
		return
	
	# Acessa o Dictionary herdado de BasePower
	if enemies_last_hit.has(enemy):
		enemies_last_hit.erase(enemy)


# =================================================
# LIMPEZA DE INIMIGOS MORTOS
# =================================================
func _cleanup_freed_enemies() -> void:
	# Cria lista de chaves para iterar com segurança
	var keys_to_remove: Array = []
	
	# Itera sobre uma cópia das chaves
	for enemy in enemies_in_contact.keys():
		# Verifica se o inimigo foi destruído
		if not is_instance_valid(enemy):
			keys_to_remove.append(enemy)
	
	# Remove as chaves inválidas
	for enemy in keys_to_remove:
		var t = enemies_in_contact.get(enemy)
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
		enemies_in_contact.erase(enemy)


func _clear_all_continuous_timers() -> void:
	# Cria lista de chaves para iterar com segurança
	var all_enemies: Array = []
	for enemy in enemies_in_contact.keys():
		all_enemies.append(enemy)
	
	# Para e remove cada timer
	for enemy in all_enemies:
		# Valida se ainda existe no dictionary
		if not enemies_in_contact.has(enemy):
			continue
		
		var t = enemies_in_contact.get(enemy)
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
	
	# Limpa o dictionary
	enemies_in_contact.clear()


# =================================================
# SETTERS - v1.3.13
# =================================================
func set_power_direction(player_direction: int) -> void:
	direction = player_direction
	anim.flip_h = direction < 0


func set_attack_data(data: AttackData) -> void:
	"""
	v1.3.13: Faz snapshot do attack_scale no momento do spawn.
	Isso padroniza o comportamento com os outros powers.
	"""
	# Chama BasePower EXCETO _apply_attack_scale()
	attack_data = data
	hit_data = data.hit_data
	max_life_time = data.life_time
	damage_interval = data.damage_interval
	
	# v1.3.13: SNAPSHOT do scale no spawn
	target_scale = data.attack_scale
	
	# IMPORTANTE: NÃO chamar super._apply_attack_scale()
	# pois power_04 usa escala dinâmica, não fixa
	
	# Configurações específicas do Bo
	# v1.2.6: Aplicar projectile_speed_multiplier
	speed = data.speed * PowerUpStatsGlobal.projectile_speed_multiplier
	current_speed = speed
	max_hits = data.max_hits


# =================================================
# DESTRUIÇÃO
# =================================================
func _exit_tree() -> void:
	# Garante limpeza dos timers ao destruir
	_clear_all_continuous_timers()
