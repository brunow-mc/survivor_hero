@tool
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

@export_group("Visual")
## Frames da animação, na ordem (índice 0 = frame 1 / repouso). Chamados
## pelos métodos _frame_01()..._frame_12() via AnimationPlayer.
@export var frames: Array[Texture2D] = []:
	set(value):
		frames = value
		_set_frame(_current_frame)  # reaplica o frame atual com os novos frames
## Mantém a arte de cada tile sempre "em pé", mesmo com a barreira
## rotacionada. Desligue para objetos cuja arte deva girar junto com a
## geometria (ex.: uma barreira de dano direcional).
@export var lock_visual_rotation: bool = true:
	set(value):
		lock_visual_rotation = value
		_apply_size()

@export_group("Audio")
@export var close_sound: AudioStream
@export var open_sound: AudioStream

# ---------------- NODES ----------------
@onready var blocker: CollisionShape2D = $Blocker
@onready var pass_sensor: Area2D = $PassSensor
@onready var enemy_sensor: Area2D = $EnemyPhaseSensor
@onready var anim: AnimationPlayer = $AnimationPlayer

# ---------------- STATE ----------------
var is_closed: bool = false
var _entry_side: float = 0.0          # sinal do X local do player na entrada
var _overlapping_enemies: Array = []  # inimigos sobre a barreira (p/ o efeito)
var _current_frame: int = 1           # frame atual, aplicado a todos os tiles

signal closed
signal opened

var _last_rotation: float = 0.0  # p/ detectar giro manual (ver _process)

func _ready() -> void:
	_apply_size()
	_last_rotation = rotation
	if Engine.is_editor_hint():
		return
	# --- daqui pra baixo, só no jogo ---
	# Nasce ABERTA: colisor desligado; os tiles mostram o frame 1 (_current_frame
	# = 1 por padrão), o frame de repouso — ex.: barrier_01, a marca no chão.
	blocker.disabled = true
	is_closed = false
	pass_sensor.body_entered.connect(_on_pass_entered)
	pass_sensor.body_exited.connect(_on_pass_exited)
	enemy_sensor.body_entered.connect(_on_enemy_entered)
	enemy_sensor.body_exited.connect(_on_enemy_exited)

# Detecta giro manual (Inspector/gizmo) comparando a rotação a cada frame.
# NOTIFICATION_TRANSFORM_CHANGED não se mostrou confiável em contexto @tool/
# editor — polling é mais simples e garantido aqui (custo desprezível: uma
# comparação de float por frame). Roda no editor E no jogo.
func _process(_delta: float) -> void:
	if rotation != _last_rotation:
		_last_rotation = rotation
		_refresh_tile_rotation()

func _refresh_tile_rotation() -> void:
	if not lock_visual_rotation:
		return
	var container := get_node_or_null("Tiles") as Node2D
	if container == null:
		return
	for child in container.get_children():
		(child as Node2D).global_rotation = 0.0

# ---------------- GEOMETRIA (roda no editor via @tool) ----------------
func _apply_size() -> void:
	# Busca os nós NA HORA (get_node_or_null) em vez de depender de @onready:
	# num script @tool o @onready pode capturar null se rodar antes de os filhos
	# existirem e não se atualiza. Buscar aqui torna o preview do editor robusto.
	var blk := get_node_or_null("Blocker") as CollisionShape2D
	var pass_shape := get_node_or_null("PassSensor/CollisionShape2D") as CollisionShape2D
	var enemy_shape := get_node_or_null("EnemyPhaseSensor/CollisionShape2D") as CollisionShape2D
	var tiles_container := get_node_or_null("Tiles") as Node2D
	if blk == null or pass_shape == null or enemy_shape == null or tiles_container == null:
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

	# Sensor de passagem: mais largo em X (folga nas duas faces).
	pass_rect.size = Vector2(w + 2.0 * pass_margin, h)
	pass_shape.position = Vector2(0.0, h / 2.0)

	# Sensor de inimigos: cobre a pegada da barreira.
	enemy_rect.size = Vector2(w, h)
	enemy_shape.position = Vector2(0.0, h / 2.0)

	_rebuild_tiles(tiles_container, w)

# Recria a grade de tiles (length_tiles × thickness_tiles) dentro de `Tiles`.
# Cada tile é um Sprite2D independente — não um único retângulo esticado —
# para poder ficar "em pé" (lock_visual_rotation) sem deformar o desenho.
func _rebuild_tiles(container: Node2D, w: float) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	var tex := _frame_texture(_current_frame)
	for row in length_tiles:
		for col in thickness_tiles:
			var tile := Sprite2D.new()
			tile.centered = true
			tile.texture = tex
			container.add_child(tile)
			tile.position = Vector2(
				-w / 2.0 + TILE / 2.0 + col * TILE,
				TILE / 2.0 + row * TILE
			)
			if lock_visual_rotation:
				tile.global_rotation = 0.0

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
		AudioManagerGlobal.play_sound_2d(close_sound, global_position)

func _play_open_sfx() -> void:
	if open_sound:
		AudioManagerGlobal.play_sound_2d(open_sound, global_position)

# ---------------- FRAMES (chamados pela AnimationPlayer via call-method) ----------------
# 12 métodos SEM argumento (mesmo motivo de _enable_blocker/_disable_blocker):
# a faixa de método só precisa escolher o nome, sem editar argumento na chave.
func _frame_01() -> void: _set_frame(1)
func _frame_02() -> void: _set_frame(2)
func _frame_03() -> void: _set_frame(3)
func _frame_04() -> void: _set_frame(4)
func _frame_05() -> void: _set_frame(5)
func _frame_06() -> void: _set_frame(6)
func _frame_07() -> void: _set_frame(7)
func _frame_08() -> void: _set_frame(8)
func _frame_09() -> void: _set_frame(9)
func _frame_10() -> void: _set_frame(10)
func _frame_11() -> void: _set_frame(11)
func _frame_12() -> void: _set_frame(12)

func _set_frame(n: int) -> void:
	_current_frame = n
	var tex := _frame_texture(n)
	var container := get_node_or_null("Tiles") as Node2D
	if container == null:
		return
	for child in container.get_children():
		if child is Sprite2D:
			child.texture = tex

func _frame_texture(n: int) -> Texture2D:
	if frames.is_empty():
		return null
	return frames[clampi(n - 1, 0, frames.size() - 1)]

# ---------------- EFEITO DE FANTASMA (inimigos atravessando) ----------------
# Enquanto a barreira está FECHADA, quem estiver sobre ela fica
# semitransparente (EnemyBase.set_phasing / phase_alpha).
# _overlapping_enemies existe porque os sinais só avisam TRANSIÇÕES: quem já
# estava sobrepondo quando close()/open() acontece não recebe sinal nenhum,
# e precisa ser reconciliado (ver _reconcile_phasing).
func _on_enemy_entered(body: Node2D) -> void:
	if not _overlapping_enemies.has(body):
		_overlapping_enemies.append(body)
	if is_closed and body.has_method("set_phasing"):
		body.set_phasing(true)

func _on_enemy_exited(body: Node2D) -> void:
	_overlapping_enemies.erase(body)
	if is_instance_valid(body) and body.has_method("set_phasing"):
		body.set_phasing(false)

# Aplica o estado atual a quem já está sobrepondo. Chamado por close()/open(),
# pois a mudança de estado da barreira não gera sinal de entrada/saída.
func _reconcile_phasing() -> void:
	for e in _overlapping_enemies:
		if is_instance_valid(e) and e.has_method("set_phasing"):
			e.set_phasing(is_closed)
