@tool
class_name Barrier
extends StaticBody2D

const TILE := 16  # tamanho do tile do jogo (px)

# ---------------- EXPORTS ----------------
@export var length_tiles: int = 1:          # comprimento da barreira, EM TILES
	set(value):
		length_tiles = max(1, value)
		_apply_size()
@export var thickness_tiles: int = 1:       # espessura, EM TILES (default 1 = 16px)
	set(value):
		thickness_tiles = max(1, value)
		_apply_size()

## Fecha sozinha quando o player atravessa (entra por um lado, sai pelo outro).
@export var auto_close_on_pass: bool = true
## Inverte qual lado local é o "de fora" (por padrão o player entra pelo -X local).
@export var flip_entry_side: bool = false
## Folga do sensor de passagem além de cada face, para registrar entrada/saída
## fora do colisor de bloqueio.
@export var pass_margin: float = float(TILE)

@export_group("Audio")
@export var close_sound: AudioStream
@export var open_sound: AudioStream

# ---------------- NODES ----------------
@onready var blocker: CollisionShape2D = $Blocker
@onready var visual: TextureRect = $Visual
@onready var pass_sensor: Area2D = $PassSensor
@onready var pass_sensor_shape: CollisionShape2D = $PassSensor/Shape
@onready var enemy_sensor: Area2D = $EnemyPhaseSensor
@onready var enemy_sensor_shape: CollisionShape2D = $EnemyPhaseSensor/Shape
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sfx: AudioStreamPlayer2D = $Sfx

# ---------------- STATE ----------------
var is_closed: bool = false
var _entry_side: float = 0.0          # sinal do X local do player na entrada
var _overlapping_enemies: Array = []  # inimigos sobre a barreira (p/ o efeito)

signal closed
signal opened

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	# --- daqui pra baixo, só no jogo ---
	blocker.disabled = true       # nasce ABERTA
	visual.modulate.a = 0.0       # visual invisível enquanto aberta
	is_closed = false
	pass_sensor.body_entered.connect(_on_pass_entered)
	pass_sensor.body_exited.connect(_on_pass_exited)
	enemy_sensor.body_entered.connect(_on_enemy_entered)
	enemy_sensor.body_exited.connect(_on_enemy_exited)

# ---------------- GEOMETRIA (roda no editor via @tool) ----------------
func _apply_size() -> void:
	# Busca os nós NA HORA (get_node_or_null) em vez de depender de @onready:
	# num script @tool o @onready pode capturar null se rodar antes de os filhos
	# existirem e não se atualiza. Buscar aqui torna o preview do editor robusto.
	var blk := get_node_or_null("Blocker") as CollisionShape2D
	var vis := get_node_or_null("Visual") as TextureRect
	var pass_shape := get_node_or_null("PassSensor/Shape") as CollisionShape2D
	var enemy_shape := get_node_or_null("EnemyPhaseSensor/Shape") as CollisionShape2D
	if blk == null or vis == null or pass_shape == null or enemy_shape == null:
		return
	var block_rect := blk.shape as RectangleShape2D
	var pass_rect := pass_shape.shape as RectangleShape2D
	var enemy_rect := enemy_shape.shape as RectangleShape2D
	if block_rect == null or pass_rect == null or enemy_rect == null:
		return

	var w := float(thickness_tiles * TILE)
	var h := float(length_tiles * TILE)

	# Colisor de bloqueio: (w, h), centrado em X, ocupando Y de 0 a h.
	block_rect.size = Vector2(w, h)
	blk.position = Vector2(0.0, h / 2.0)

	# Visual: canto sup-esq em (-w/2, 0), tamanho (w, h).
	vis.position = Vector2(-w / 2.0, 0.0)
	vis.size = Vector2(w, h)

	# Sensor de passagem: mais largo em X (folga nas duas faces).
	pass_rect.size = Vector2(w + 2.0 * pass_margin, h)
	pass_shape.position = Vector2(0.0, h / 2.0)

	# Sensor de inimigos: cobre a pegada da barreira.
	enemy_rect.size = Vector2(w, h)
	enemy_shape.position = Vector2(0.0, h / 2.0)

# ---------------- PASSAGEM DO PLAYER ----------------
func _on_pass_entered(body: Node2D) -> void:
	if is_closed:
		return
	_entry_side = signf(to_local(body.global_position).x)

func _on_pass_exited(body: Node2D) -> void:
	if is_closed or _entry_side == 0.0:
		return
	var exit_side := signf(to_local(body.global_position).x)
	if exit_side == _entry_side:
		return  # saiu pelo mesmo lado → voltou, não fecha
	var outside := 1.0 if flip_entry_side else -1.0
	if _entry_side != outside:
		return  # entrou pelo lado "de dentro" → ignora
	if auto_close_on_pass:
		close()

# ---------------- API ABRIR/FECHAR ----------------
func close() -> void:
	if is_closed:
		return
	is_closed = true
	if anim.has_animation("close"):
		anim.play("close")   # a animação liga o colisor + som via call-method
	else:
		_enable_blocker()
		_play_close_sfx()
	_reconcile_phasing()
	closed.emit()

func open() -> void:
	if not is_closed:
		return
	is_closed = false
	if anim.has_animation("open"):
		anim.play("open")
	else:
		_disable_blocker()
		_play_open_sfx()
	_reconcile_phasing()
	opened.emit()

# Métodos chamados pela AnimationPlayer (call-method track). SEM argumento,
# para a faixa de método só precisar escolher o método (mais fácil de editar).
func _enable_blocker() -> void:    # liga o colisor (barreira fechada)
	blocker.set_deferred("disabled", false)

func _disable_blocker() -> void:   # desliga o colisor (barreira aberta)
	blocker.set_deferred("disabled", true)

func _play_close_sfx() -> void:
	if close_sound:
		sfx.stream = close_sound
		sfx.play()

func _play_open_sfx() -> void:
	if open_sound:
		sfx.stream = open_sound
		sfx.play()

# ---------------- INFRA DO EFEITO DE INIMIGO (visual entra depois) ----------------
func _on_enemy_entered(body: Node2D) -> void:
	if not _overlapping_enemies.has(body):
		_overlapping_enemies.append(body)
	if is_closed and body.has_method("set_phasing"):
		body.set_phasing(true)

func _on_enemy_exited(body: Node2D) -> void:
	_overlapping_enemies.erase(body)
	if body.has_method("set_phasing"):
		body.set_phasing(false)

func _reconcile_phasing() -> void:
	for e in _overlapping_enemies:
		if is_instance_valid(e) and e.has_method("set_phasing"):
			e.set_phasing(is_closed)
