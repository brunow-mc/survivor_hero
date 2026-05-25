extends BasePower

# -------------------------------------------------
# ÁUDIO - v1.1.12
# -------------------------------------------------
# NOTA: Este power cria AudioStreamPlayer2D dinamicamente para áudio em loop.
# A flag handles_own_audio no AttackData impede attack_controller de tocar via AudioManager.
var audio_player: AudioStreamPlayer2D

# -------------------------------------------------
# CONTROLE DE INIMIGOS EM CONTATO
# -------------------------------------------------
# enemy : Timer
var enemies_in_contact: Dictionary[Node, Timer] = {}

# -------------------------------------------------
# SETUP - v1.1.12
# -------------------------------------------------
func set_attack_data(data: AttackData) -> void:
	super.set_attack_data(data)
	_setup_audio()

func _setup_audio() -> void:
	"""
	Cria AudioStreamPlayer2D dinamicamente e configura áudio em loop.
	Stream vem do AttackData.attack_sound (PADRÃO).
	Loop já configurado no import do MP3.
	"""
	if not attack_data or not attack_data.attack_sound:
		return
	
	# Criar AudioStreamPlayer2D dinamicamente
	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)
	
	# Configurar com AttackData
	audio_player.stream = attack_data.attack_sound
	audio_player.volume_db = attack_data.attack_sound_volume_db
	audio_player.pitch_scale = attack_data.attack_sound_pitch_scale
	audio_player.bus = "SFX"
	
	# Iniciar áudio (loop automático do MP3)
	audio_player.play()


# -------------------------------------------------
# CICLO DE VIDA
# -------------------------------------------------
func _physics_process(delta: float) -> void:
	super._physics_process(delta)


# -------------------------------------------------
# COLISÕES — DANO CONTÍNUO
# -------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("EnemyHurtbox"):
		return

	var enemy := area.get_parent()
	if enemy == null:
		return

	# já está recebendo ticks
	if enemies_in_contact.has(enemy):
		return

	# 🔹 PRIMEIRO HIT (via BasePower)
	super._on_area_entered(area)

	# cria timer de dano contínuo
	var t := Timer.new()
	t.wait_time = damage_interval
	t.one_shot = false

	t.timeout.connect(func():
		if is_instance_valid(enemy):
			# força nova tentativa de dano
			super._on_area_entered(area)
		else:
			t.queue_free()
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
 
	if not enemies_in_contact.has(enemy):
		return

	var t: Timer = enemies_in_contact[enemy]
	if is_instance_valid(t):
		t.stop()
		t.queue_free()

	enemies_in_contact.erase(enemy)


# -------------------------------------------------
# FIM DE VIDA - MODIFICADO v1.1.12
# -------------------------------------------------
func on_life_time_end() -> void:
	# PARAR ÁUDIO ANTES de destruir
	if audio_player:
		audio_player.stop()
	
	# Limpar timers de dano contínuo
	for enemy in enemies_in_contact.keys():
		var t := enemies_in_contact[enemy]
		if is_instance_valid(t):
			t.stop()
			t.queue_free()

	enemies_in_contact.clear()
	queue_free()
