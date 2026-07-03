extends Area2D
class_name XPItem

# ======================================
# CONFIGURAÇÕES
# ======================================
@export var xp_value: int = 1
@export var move_speed: float = 200.0
@export var magnet_range: float = 25.0
@export var auto_collect_range: float = 10.0

# ======================================
# ÁUDIO
# ======================================
@export_group("Audio")
@export var collect_sound: AudioStream
@export var collect_volume: float = 0.0
@export var collect_pitch: float = 1.0

# ======================================
# ESTADO
# ======================================
enum ItemState {
	IDLE,
	ATTRACTED,
	COLLECTED
}

var state: ItemState = ItemState.IDLE
var player: CharacterBody2D = null

# ======================================
# READY
# ======================================
func _ready() -> void:
	add_to_group("XPItems")
	area_entered.connect(_on_area_entered)
	player = get_tree().get_first_node_in_group("Player")

# ======================================
# FÍSICA
# ======================================
func _physics_process(delta: float) -> void:
	match state:
		ItemState.IDLE:
			_check_for_player_proximity()

		ItemState.ATTRACTED:
			_move_towards_player(delta)

		ItemState.COLLECTED:
			pass

# ======================================
# PROXIMIDADE DO PLAYER
# ======================================
func _check_for_player_proximity() -> void:
	if not is_instance_valid(player):
		return

	var distance := global_position.distance_to(player.global_position)
	var effective_range := magnet_range + PowerUpStatsGlobal.magnet_range_bonus

	if distance <= effective_range:
		state = ItemState.ATTRACTED

# ======================================
# MOVIMENTO DE ATRAÇÃO
# ======================================
func _move_towards_player(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var distance := global_position.distance_to(player.global_position)

	if distance <= auto_collect_range:
		collect()
		return

	var direction := (player.global_position - global_position).normalized()
	global_position += direction * move_speed * delta

# ======================================
# COLISÃO COM PLAYER
# ======================================
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("PlayerHurtbox"):
		collect()

# ======================================
# COLETA
# ======================================
func collect() -> void:
	if state == ItemState.COLLECTED:
		return
	# Não coleta XP com player morto — evita level up póstumo
	if not GameStateGlobal.is_combat_allowed():
		return
	state = ItemState.COLLECTED
	XPManagerGlobal.add_xp(xp_value)
	_play_collect_sound()
	queue_free()

# ======================================
# TOCAR SOM DE COLETA
# ======================================
func _play_collect_sound() -> void:
	if collect_sound:
		AudioManagerGlobal.play_sound(collect_sound, collect_volume, collect_pitch)
