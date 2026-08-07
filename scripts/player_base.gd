extends CharacterBody2D
class_name PlayerBase

# =================================================
# PLAYER STATE MACHINE
# =================================================
enum PlayerState {
	idle,
	walk,
	attack,
	dead
}

# =================================================
# CONFIGURAÇÕES GERAIS
# =================================================
@export var max_health: float = 100.0
@export var move_speed: float = 90.0
@export var hit_post_delay: float = 0.2

# =================================================
# ÁUDIO — DADOS
# =================================================
@export var hit_sound: AudioStream
@export var death_sound: AudioStream

@export var hit_volume_db: float = 0.0
@export var hit_pitch_scale: float = 1.0

@export var death_volume_db: float = 0.0
@export var death_pitch_scale: float = 1.0

# =================================================
# VISUAL EFFECTS
# =================================================
@export_group("Visual Effects")
@export var flash_count: int = 2
@export var flash_duration: float = 0.1
@export var flash_color: Color = Color.RED

# =================================================
# ÁUDIO — PLAYERS INTERNOS
# =================================================
var audio_hit: AudioStreamPlayer
var audio_death: AudioStreamPlayer

# =================================================
# ESTADO
# =================================================
var status: PlayerState = PlayerState.idle

# Direção de movimento (2D completo, pode ser diagonal ou zero)
var movement_direction := Vector2.ZERO

# Direção que o sprite está olhando (apenas horizontal: 1.0 ou -1.0)
var facing_direction: float = 1.0

# =================================================
# VISUAL (configurado por classes filhas)
# =================================================
var sprite_node: CanvasItem

# =================================================
# MARCADORES DE POSIÇÃO (nós da cena do player)
# Todos com get_node_or_null: se faltarem, os consumidores degradam
# graciosamente (fallback → BodyCenter → origem) em vez de spammar erros de
# null. A ausência é avisada uma vez pelo AttackController.setup().
# =================================================
# Centro do corpo. Referência canônica de "onde está o corpo do player"
# — ver get_body_center_position().
@onready var body_center: Node2D = get_node_or_null("BodyCenter") as Node2D
# Origem lateral dos projéteis (esquerda/direita conforme facing_direction).
# Repassados ao AttackController pela classe concreta no _ready().
@onready var attack_position_right: Node2D = get_node_or_null("AttackPositionRight")
@onready var attack_position_left: Node2D = get_node_or_null("AttackPositionLeft")

# =================================================
# ÁUDIO HIT (CONTROLE)
# =================================================
var can_play_hit_sound := true
var hit_stop_timer: Timer

# =================================================
# READY
# =================================================
func _ready() -> void:
	_register_player()
	_setup_audio()
	_setup_hit_timer()
	_validate_scene_setup()

# Guard de inicialização: sem o grupo, os Hitbox dos inimigos não reconhecem
# o player e o dano por contato simplesmente nunca acontece — falha grave e
# 100% silenciosa. Roda uma vez, no _ready do player.
func _validate_scene_setup() -> void:
	var hurtbox: Node = get_node_or_null("Hurtbox")
	if hurtbox == null:
		push_warning("PlayerBase: nó 'Hurtbox' não encontrado — o player NÃO vai receber dano de contato dos inimigos.")
	elif not hurtbox.is_in_group("PlayerHurtbox"):
		push_warning("PlayerBase: Hurtbox fora do grupo 'PlayerHurtbox' — o player NÃO vai receber dano de contato dos inimigos.")

## Posição global do CENTRO DO CORPO do player (o marcador BodyCenter). É a
## referência canônica para qualquer sistema que precise saber "onde está o
## corpo do player": câmera, nascimento de ataques, centro de órbita, alvo de
## perseguição dos inimigos. NÃO usar `global_position` para isso — a origem
## da cena são os PÉS, o que desloca tudo para baixo.
## Fallback: BodyCenter → origem (pés). A ausência do marcador é avisada uma
## vez pelo AttackController.setup().
func get_body_center_position() -> Vector2:
	if is_instance_valid(body_center):
		return body_center.global_position
	return global_position

# -------------------------------------------------
# SETUPS
# -------------------------------------------------
func _register_player() -> void:
	GameStateGlobal.register_player(max_health)
	GameStateGlobal.state_changed.connect(_on_game_state_changed)

func _setup_hit_timer() -> void:
	hit_stop_timer = Timer.new()
	hit_stop_timer.one_shot = true
	hit_stop_timer.wait_time = hit_post_delay
	hit_stop_timer.timeout.connect(_on_hit_delay_finished)
	add_child(hit_stop_timer)

func _setup_audio() -> void:
	if hit_sound:
		audio_hit = AudioStreamPlayer.new()
		audio_hit.stream = hit_sound
		audio_hit.volume_db = hit_volume_db
		audio_hit.pitch_scale = hit_pitch_scale
		audio_hit.bus = "SFX"
		audio_hit.finished.connect(_on_hit_audio_finished)
		add_child(audio_hit)

	if death_sound:
		audio_death = AudioStreamPlayer.new()
		audio_death.stream = death_sound
		audio_death.volume_db = death_volume_db
		audio_death.pitch_scale = death_pitch_scale
		audio_death.bus = "SFX"
		add_child(audio_death)

# =================================================
# PROCESS
# =================================================
func _physics_process(_delta: float) -> void:
	if status == PlayerState.dead:
		return

	_process_state()
	move_and_slide()

func _process_state() -> void:
	match status:
		PlayerState.idle:
			idle_state()
		PlayerState.walk:
			walk_state()
		PlayerState.attack:
			attack_state()

# =================================================
# FSM — TRANSIÇÕES
# =================================================
func go_to_idle_state() -> void:
	status = PlayerState.idle

func go_to_walk_state() -> void:
	status = PlayerState.walk

func go_to_attack_state() -> void:
	if status == PlayerState.dead:
		return
	status = PlayerState.attack

func go_to_dead_state() -> void:
	if status == PlayerState.dead:
		return

	status = PlayerState.dead

	can_play_hit_sound = false
	hit_stop_timer.stop()

	if audio_hit and audio_hit.playing:
		audio_hit.stop()

	if audio_death:
		audio_death.play()

	velocity = Vector2.ZERO
	set_physics_process(false)

	_disable_collision()
	_on_death_animation()

# =================================================
# STATES (BASE)
# =================================================
func idle_state() -> void:
	move()
	if velocity != Vector2.ZERO:
		go_to_walk_state()

func walk_state() -> void:
	move()
	if velocity == Vector2.ZERO:
		go_to_idle_state()

func attack_state() -> void:
	move()

# =================================================
# MOVIMENTO
# =================================================
func move() -> void:
	movement_direction.x = Input.get_axis("left", "right")
	movement_direction.y = Input.get_axis("up", "down")

	if movement_direction.length() < 0.2:
		movement_direction = Vector2.ZERO

	velocity = movement_direction.normalized() * move_speed

# =================================================
# DANO
# =================================================
func take_damage(amount: float) -> void:
	if status == PlayerState.dead:
		return

	if not GameStateGlobal.is_combat_allowed():
		return

	# v1.1.19: Aplicar armor (redução de dano)
	var damage_reduction = PowerUpStatsGlobal.get_armor_damage_reduction()
	var final_damage = amount * (1.0 - damage_reduction)
	
	GameStateGlobal.apply_damage(final_damage)

	if can_play_hit_sound and audio_hit:
		can_play_hit_sound = false
		audio_hit.play()

	flash_red()

func _on_hit_audio_finished() -> void:
	hit_stop_timer.start()

func _on_hit_delay_finished() -> void:
	can_play_hit_sound = true

# =================================================
# FLASH DAMAGE BASE
# =================================================
func flash_red() -> void:
	if not sprite_node:
		return

	for i in range(flash_count):
		sprite_node.modulate = flash_color
		await get_tree().create_timer(flash_duration, false).timeout
		sprite_node.modulate = Color.WHITE
		await get_tree().create_timer(flash_duration, false).timeout

# =================================================
# GAME STATE
# =================================================
func _on_game_state_changed(state: int) -> void:
	if state == GameStateGlobal.GameplayState.PLAYER_DEAD:
		go_to_dead_state()

# =================================================
# HOOKS (para filhos)
# =================================================
func _disable_collision() -> void:
	pass

func _on_death_animation() -> void:
	pass
