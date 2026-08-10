extends Control
class_name HealthBar

# ======================================
# NODES
# ======================================
@onready var background_bar: ProgressBar = $BackgroundBar
@onready var delay_bar: ProgressBar = $DelayBar
@onready var health_bar: ProgressBar = $HealthBar

# ======================================
# CONFIGURAÇÃO
# ======================================
@export_group("Animation")
@export var damage_animation_speed: float = 10.0
@export var delay_bar_wait_time: float = 0.5
@export var delay_bar_speed: float = 5.0

@export_group("Visual Effects")
@export var enable_shake: bool = true
@export var shake_intensity: float = 2.0
@export var shake_duration: float = 0.15

@export var enable_flash: bool = true
@export var flash_duration: float = 0.1

@export_group("Health Colors")
@export var color_high_health: Color = Color(1.0, 0.725, 0.0, 1.0)
@export var color_mid_health: Color = Color(1.0, 0.294, 0.0, 1.0)
@export var color_low_health: Color = Color(0.822, 0.0, 0.0, 1.0)
@export var mid_health_threshold: float = 0.75
@export var low_health_threshold: float = 0.35

# ======================================
# ESTADO
# ======================================
var current_health: float = 100.0
var max_health: float = 100.0
var target_health: float = 100.0

var delay_bar_current: float = 100.0
var delay_bar_target: float = 100.0
var delay_timer: float = 0.0
var is_delay_active: bool = false

var original_position: Vector2

# ======================================
# READY
# ======================================
func _ready() -> void:
	original_position = position
	GameStateGlobal.player_health_changed.connect(_on_health_changed)
	_initialize_bars()

# ======================================
# INICIALIZAÇÃO
# ======================================
func _initialize_bars() -> void:
	max_health = GameStateGlobal.player_max_health
	current_health = GameStateGlobal.player_health
	target_health = current_health
	delay_bar_current = current_health
	delay_bar_target = current_health
	
	background_bar.max_value = max_health
	background_bar.value = max_health
	
	delay_bar.max_value = max_health
	delay_bar.value = current_health
	
	health_bar.max_value = max_health
	health_bar.value = _display_value(current_health)

	_update_health_color()

# ======================================
# VALOR EXIBIDO (piso de 1 pixel)
# A barra tem ~25px para 100 de vida (1px a cada 4 pontos), então valores
# baixos arredondam para ZERO pixel e a barra some — o jogador acha que
# morreu com 1-3 de vida. Com vida > 0, eleva ao mínimo que ainda pinta 1px.
# Só afeta o DESENHO: current_health/target_health seguem com o valor real,
# e a cor continua sendo calculada pela vida verdadeira.
# ======================================
func _display_value(value: float) -> float:
	if value <= 0.0:
		return 0.0
	var bar_width: float = health_bar.size.x
	if bar_width <= 0.0:
		return value
	return maxf(value, max_health / bar_width)

# ======================================
# PROCESS (ANIMAÇÃO)
# ======================================
func _process(delta: float) -> void:
	# Anima barra verde
	if abs(current_health - target_health) > 0.1:
		current_health = lerp(current_health, target_health, damage_animation_speed * delta)
		health_bar.value = _display_value(current_health)
		_update_health_color()
	elif current_health != target_health:
		# ASSENTA o valor final: lerp é assintótico e o laço acima para com
		# ~0.1 de resíduo, então o alvo exato nunca era atribuído.
		current_health = target_health
		health_bar.value = _display_value(current_health)
		_update_health_color()
	
	# Timer da DelayBar
	if is_delay_active:
		delay_timer -= delta
		if delay_timer <= 0:
			is_delay_active = false
			delay_bar_target = target_health
	
	# Anima barra laranja
	if abs(delay_bar_current - delay_bar_target) > 0.1:
		delay_bar_current = lerp(delay_bar_current, delay_bar_target, delay_bar_speed * delta)
		delay_bar.value = delay_bar_current

# ======================================
# SIGNAL DO GAMESTATE
# ======================================
func _on_health_changed(new_health: float, new_max_health: float) -> void:
	var old_health := target_health
	
	max_health = new_max_health
	target_health = new_health
	
	background_bar.max_value = max_health
	delay_bar.max_value = max_health
	health_bar.max_value = max_health
	
	# Se tomou dano
	if new_health < old_health:
		_on_damage_taken()
	
	# Se curou
	elif new_health > old_health:
		_on_health_gained()

# ======================================
# QUANDO TOMA DANO
# ======================================
func _on_damage_taken() -> void:
	is_delay_active = true
	delay_timer = delay_bar_wait_time
	
	if enable_shake:
		_play_shake_effect()
	
	if enable_flash:
		_play_flash_effect()

# ======================================
# QUANDO CURA
# ======================================
func _on_health_gained() -> void:
	delay_bar_current = target_health
	delay_bar_target = target_health
	delay_bar.value = target_health
	is_delay_active = false

# ======================================
# ATUALIZAR COR DA BARRA (VERDE → AMARELO → VERMELHO)
# ======================================
func _update_health_color() -> void:
	var health_ratio := current_health / max_health
	var new_color: Color
	
	if health_ratio > mid_health_threshold:
		new_color = color_high_health
	elif health_ratio > low_health_threshold:
		var t := (health_ratio - low_health_threshold) / (mid_health_threshold - low_health_threshold)
		new_color = color_mid_health.lerp(color_high_health, t)
	else:
		var t := health_ratio / low_health_threshold
		new_color = color_low_health.lerp(color_mid_health, t)
	
	var fill_style := health_bar.get_theme_stylebox("fill")
	if fill_style is StyleBoxFlat:
		fill_style.bg_color = new_color

# ======================================
# EFEITO DE SHAKE
# ======================================
func _play_shake_effect() -> void:
	var tween := create_tween()
	
	for i in range(3):
		tween.tween_property(self, "position", original_position + Vector2(shake_intensity, 0), shake_duration / 6.0)
		tween.tween_property(self, "position", original_position + Vector2(-shake_intensity, 0), shake_duration / 6.0)
	
	tween.tween_property(self, "position", original_position, shake_duration / 6.0)

# ======================================
# EFEITO DE FLASH
# ======================================
func _play_flash_effect() -> void:
	var tween := create_tween()
	tween.tween_property(health_bar, "modulate", Color(2.0, 0.5, 0.5), flash_duration)
	tween.tween_property(health_bar, "modulate", Color.WHITE, flash_duration)
