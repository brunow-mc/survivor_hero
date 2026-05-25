extends Node
class_name AudioManager


var sound_max_distance: float = 1000.0
var sound_attenuation: float = 1.0

# ======================================
# POOL DE AUDIO PLAYERS
# ======================================
const POOL_SIZE_GLOBAL: int = 40  # Para sons não-posicionais (UI, XP, etc)
const POOL_SIZE_2D: int = 60      # Para sons posicionais (hits, deaths, explosões)

var audio_pool_global: Array[AudioStreamPlayer] = []
var active_players_global: Array[AudioStreamPlayer] = []

var audio_pool_2d: Array[AudioStreamPlayer2D] = []
var active_players_2d: Array[AudioStreamPlayer2D] = []

# ======================================
# SOUND LIMITER (integrado v1.1.12)
# ======================================
const MIN_INTERVAL: float = 0.04
var last_play_time: Dictionary = {}

# ======================================
# SONS PRÉ-CARREGADOS (OPCIONAL)
# ======================================
var sound_library: Dictionary = {}

# ======================================
# READY
# ======================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_audio_pools()
	print("🔊 AudioManager inicializado:")
	print("   - %d players globais no pool" % POOL_SIZE_GLOBAL)
	print("   - %d players 2D no pool" % POOL_SIZE_2D)
	print("   - Intervalo mínimo entre sons: %0.3fs" % MIN_INTERVAL)

# ======================================
# CRIAR POOLS
# ======================================
func _create_audio_pools() -> void:
	# Pool de AudioStreamPlayer (sons globais)
	for i in range(POOL_SIZE_GLOBAL):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.process_mode = Node.PROCESS_MODE_PAUSABLE  # v1.4.6: para durante pause
		player.finished.connect(_on_global_player_finished.bind(player))
		add_child(player)
		audio_pool_global.append(player)
	
	# Pool de AudioStreamPlayer2D (sons posicionais)
	for i in range(POOL_SIZE_2D):
		var player := AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.process_mode = Node.PROCESS_MODE_PAUSABLE  # v1.4.6: para durante pause
		
		# Configurações espaciais (ajuste para testes)
		player.max_distance = sound_max_distance  # Distância máxima audível (pixels)
		player.attenuation = sound_attenuation      # Curva de atenuação (1.0 = linear)
		
		player.finished.connect(_on_2d_player_finished.bind(player))
		add_child(player)
		audio_pool_2d.append(player)

# ======================================
# VERIFICAÇÃO DE INTERVALO (integrado)
# ======================================
func _can_play_sound(sound: AudioStream) -> bool:
	if sound == null:
		return false
	
	var now: float = Time.get_ticks_msec() / 1000.0
	
	if not last_play_time.has(sound):
		last_play_time[sound] = now
		return true
	
	var elapsed: float = now - float(last_play_time[sound])
	
	if elapsed >= MIN_INTERVAL:
		last_play_time[sound] = now
		return true
	
	return false

# ======================================
# TOCAR SOM GLOBAL (NÃO-POSICIONAL)
# ======================================
func play_sound(sound: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not sound:
		push_warning("⚠️ AudioManager: Som nulo passado para play_sound()")
		return
	
	# Verificação de intervalo mínimo
	if not _can_play_sound(sound):
		return
	
	var player := _get_available_global_player()
	
	if not player:
		push_warning("⚠️ AudioManager: Pool global esgotado! Considere aumentar POOL_SIZE_GLOBAL.")
		return
	
	# Configura o player
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	
	# Toca
	player.play()
	
	# Move para lista de ativos
	audio_pool_global.erase(player)
	active_players_global.append(player)

# ======================================
# TOCAR SOM 2D (POSICIONAL)
# ======================================
func play_sound_2d(sound: AudioStream, position: Vector2, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not sound:
		push_warning("⚠️ AudioManager: Som nulo passado para play_sound_2d()")
		return
	
	# Verificação de intervalo mínimo
	if not _can_play_sound(sound):
		return
	
	var player := _get_available_2d_player()
	
	if not player:
		push_warning("⚠️ AudioManager: Pool 2D esgotado! Considere aumentar POOL_SIZE_2D.")
		return
	
	# Configura o player
	player.stream = sound
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	
	# Toca
	player.play()
	
	# Move para lista de ativos
	audio_pool_2d.erase(player)
	active_players_2d.append(player)

# ======================================
# TOCAR SOM POR PATH
# ======================================
func play_sound_path(sound_path: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not sound_library.has(sound_path):
		var sound := load(sound_path) as AudioStream
		if not sound:
			push_error("❌ AudioManager: Não foi possível carregar som: %s" % sound_path)
			return
		sound_library[sound_path] = sound
	
	play_sound(sound_library[sound_path], volume_db, pitch_scale)

func play_sound_2d_path(sound_path: String, position: Vector2, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not sound_library.has(sound_path):
		var sound := load(sound_path) as AudioStream
		if not sound:
			push_error("❌ AudioManager: Não foi possível carregar som: %s" % sound_path)
			return
		sound_library[sound_path] = sound
	
	play_sound_2d(sound_library[sound_path], position, volume_db, pitch_scale)

# ======================================
# PEGAR PLAYERS DISPONÍVEIS
# ======================================
func _get_available_global_player() -> AudioStreamPlayer:
	if audio_pool_global.is_empty():
		return null
	return audio_pool_global[0]

func _get_available_2d_player() -> AudioStreamPlayer2D:
	if audio_pool_2d.is_empty():
		return null
	return audio_pool_2d[0]

# ======================================
# QUANDO PLAYERS TERMINAM
# ======================================
func _on_global_player_finished(player: AudioStreamPlayer) -> void:
	active_players_global.erase(player)
	if not audio_pool_global.has(player):
		audio_pool_global.append(player)

func _on_2d_player_finished(player: AudioStreamPlayer2D) -> void:
	active_players_2d.erase(player)
	if not audio_pool_2d.has(player):
		audio_pool_2d.append(player)

# ======================================
# UTILITÁRIOS
# ======================================
func stop_all_sounds() -> void:
	for player in active_players_global:
		player.stop()
		audio_pool_global.append(player)
	active_players_global.clear()
	
	for player in active_players_2d:
		player.stop()
		audio_pool_2d.append(player)
	active_players_2d.clear()

func get_active_sounds_count() -> int:
	return active_players_global.size() + active_players_2d.size()

func get_available_players_count() -> int:
	return audio_pool_global.size() + audio_pool_2d.size()

func get_stats() -> Dictionary:
	return {
		"global_active": active_players_global.size(),
		"global_available": audio_pool_global.size(),
		"2d_active": active_players_2d.size(),
		"2d_available": audio_pool_2d.size(),
		"total_active": get_active_sounds_count(),
		"total_available": get_available_players_count()
	}
