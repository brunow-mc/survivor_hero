extends BasePower
class_name Power05Gear

# =================================================
# NODES
# =================================================
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# =================================================
# CONFIGURAÇÃO DE ÓRBITA
# =================================================
var player: Node2D = null
var orbit_radius: float
var orbit_angle: float = 0.0
var orbit_speed: float = 0.0

# =================================================
# CENTER POSITION - v1.2.4
# =================================================
var center_position: Vector2
var center_initialized: bool = false
## Flag para capturar center_position no primeiro frame.

## Offset do centro da órbita em relação à origem do player (os pés).
## Capturado do BodyCenter do player em _ready — a órbita gira em torno
## do CORPO, não dos pés (convenção feet origin).
var _orbit_center_offset: Vector2 = Vector2.ZERO

# =================================================
# ROTAÇÃO VISUAL DO SPRITE
# =================================================
var visual_rotation_speed: float = 7.0

# =================================================
# CONTROLE DE HITS
# =================================================
var max_hits: int = 0
var hits_done: int = 0

# =================================================
# FADE IN/OUT
# =================================================
var fade_in_time: float = 0.1
var fade_out_time: float = 0.1
var is_fading_out: bool = false

# =================================================
# READY
# =================================================
func _ready() -> void:
	super._ready()
	
	player = get_tree().get_first_node_in_group("Player")

	if not player:
		print("⚠️ Power05Gear: Player não encontrado!")
		queue_free()
		return

	# Centro da órbita = BodyCenter do player. O gear é filho do player e
	# reescreve a própria position todo frame, então precisa do offset no
	# referencial LOCAL do player: o getter é global → to_local converte.
	_orbit_center_offset = player.to_local(player.get_body_center_position())
	
	# Fade in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in_time)

# =================================================
# PHYSICS PROCESS
# =================================================
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if is_fading_out:
		return
	
	# =================================================
	# CAPTURA CENTER_POSITION NO PRIMEIRO FRAME
	# =================================================
	if not center_initialized:
		# Sibling: snapshot do ponto de cast + offset do corpo — a órbita
		# fixa gira em torno de onde o CORPO do player estava.
		center_position = global_position + _orbit_center_offset
		center_initialized = true
	
	# =================================================
	# MOVIMENTO ORBITAL - CHILD/SIBLING
	# =================================================
	orbit_angle += orbit_speed * delta
	
	var offset = Vector2(
		cos(orbit_angle) * orbit_radius,
		sin(orbit_angle) * orbit_radius
	)
	
	# =================================================
	# DETECTA SE É CHILD OU SIBLING
	# =================================================
	if get_parent() == player:
		# ✅ CHILD (attach_to_player = true)
		# Usa position RELATIVA ao parent (player)
		# Player move → gear segue automaticamente
		# Órbita centrada no BodyCenter, não na origem (pés)
		position = _orbit_center_offset + offset
	else:
		# ✅ SIBLING (attach_to_player = false)
		# Usa center_position FIXO (snapshot do spawn)
		# Player move → gear fica parado
		global_position = center_position + offset
	
	# Rotação visual
	anim.rotation += visual_rotation_speed * delta

# =================================================
# COLISÃO
# =================================================
func _on_area_entered(area: Area2D) -> void:
	if is_fading_out:
		return
	
	if not area.is_in_group("EnemyHurtbox"):
		return
	
	super._on_area_entered(area)
	
	hits_done += 1
	
	if max_hits > 0 and hits_done >= max_hits:
		_start_fade_out()

# =================================================
# FIM DE VIDA POR TEMPO
# =================================================
func on_life_time_end() -> void:
	_start_fade_out()

# =================================================
# FADE OUT
# =================================================
func _start_fade_out() -> void:
	if is_fading_out:
		return
	
	is_fading_out = true
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_out_time)
	tween.finished.connect(queue_free)

# =================================================
# SETTERS
# =================================================
func set_projectile_index(index: int, total: int) -> void:
	var angle_step := TAU / float(total)
	orbit_angle = angle_step * index

func set_attack_data(data: AttackData) -> void:
	super.set_attack_data(data)
	max_hits = data.max_hits
	
	# Carrega configurações de órbita
	orbit_radius = data.orbit_radius
	
	# Upgrade de órbita específico do Gear entra com efeito pleno (sem effectiveness).
	# Powerup global de velocidade entra amortecido por orbit_speed_effectiveness,
	# pois velocidade orbital gera mais hits que velocidade linear.
	var powerup_bonus: float = (PowerUpStatsGlobal.projectile_speed_multiplier - 1.0) * data.orbit_speed_effectiveness
	var total_orbit_bonus: float = data.orbit_speed_upgrade_bonus + powerup_bonus
	orbit_speed = data.orbit_speed * (1.0 + total_orbit_bonus)
