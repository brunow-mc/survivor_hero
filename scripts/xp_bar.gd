extends CanvasLayer
class_name XPBar

# ======================================
# NODES
# ======================================
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var level_label: Label = $LevelLabel
@onready var xp_label: Label = $XPLabel

# ======================================
# CONFIGURAÇÃO
# ======================================
@export var show_numbers: bool = true
@export var animate_fill: bool = true
@export var fill_speed: float = 10.0

# ======================================
# ESTADO
# ======================================
var target_value: float = 0.0
var current_visual_value: float = 0.0
var is_animating_level_up: bool = false

# ======================================
# READY
# ======================================
func _ready() -> void:
	# Imune à pausa: animações (tweens/lerp) concluem mesmo com o jogo
	# pausado pelo level_up_ui. Valores não mudam durante a pausa porque
	# add_xp é bloqueado por is_combat_allowed() no estado UPGRADE.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Garante que está sempre visível
	show()
	
	# Configura o pivot do LevelLabel para o centro (sem await)
	level_label.pivot_offset = level_label.size / 2.0
	
	# Conecta aos signals do XPManager
	XPManagerGlobal.xp_changed.connect(_on_xp_changed)
	XPManagerGlobal.level_up.connect(_on_level_up)
	
	# Inicializa valores
	_update_display()
	
	print("📊 XPBar inicializada!")

# ======================================
# PROCESS (ANIMAÇÃO)
# ======================================
func _process(delta: float) -> void:
	if not animate_fill:
		return
	
	if is_animating_level_up:
		return  # Não atualiza durante animação de level up
	
	# Anima a barra suavemente
	if abs(current_visual_value - target_value) > 0.01:
		current_visual_value = lerp(
			current_visual_value,
			target_value,
			fill_speed * delta
		)
		progress_bar.value = clamp(current_visual_value, 0.0, 100.0)

# ======================================
# SIGNALS DO XPMANAGER
# ======================================
func _on_xp_changed(_current: int, _required: int) -> void:
	# Não processa se estiver animando level up
	if is_animating_level_up:
		return
	
	# Calcula porcentagem (0-100)
	var progress_ratio := XPManagerGlobal.get_xp_progress_ratio()
	target_value = clamp(progress_ratio * 100.0, 0.0, 100.0)
	
	if not animate_fill:
		current_visual_value = target_value
		progress_bar.value = target_value
	
	_update_display()

func _on_level_up(_new_level: int) -> void:
	# CRÍTICO: Bloqueia IMEDIATAMENTE
	is_animating_level_up = true
	
	# Sincroniza current_visual_value com a barra ATUAL
	current_visual_value = progress_bar.value
	
	# Inicia sequência de animação de level up
	_animate_level_up_sequence(_new_level)

# ======================================
# ANIMAÇÃO SEQUENCIAL DE LEVEL UP
# ======================================
func _animate_level_up_sequence(_new_level: int) -> void:
	# PASSO 0: Troca o texto do level e dispara o pulse/flash JUNTOS.
	# _play_level_up_animation roda em paralelo (não é awaited) —
	# o pulse do Label acontece enquanto a barra enche.
	level_label.text = "LEVEL %d" % _new_level
	_play_level_up_animation()

	# PASSO 1: Completar a barra até 100% (em paralelo com o pulse)
	var fill_tween := create_tween()
	fill_tween.tween_property(progress_bar, "value", 100.0, 0.2)
	fill_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await fill_tween.finished

	# Garante que está em exatamente 100
	progress_bar.value = 100.0
	current_visual_value = 100.0

	# Pequena pausa para o flash ser visível.
	# process_always = true: este timer NÃO congela com o jogo pausado,
	# senão a sequência travaria aqui até o menu de upgrade fechar.
	await get_tree().create_timer(0.3, true).timeout
	
	# PASSO 3: Resetar a barra para 0
	progress_bar.value = 0.0
	current_visual_value = 0.0
	
	# PASSO 4: Calcular novo target (para o overflow)
	var progress_ratio := XPManagerGlobal.get_xp_progress_ratio()
	target_value = clamp(progress_ratio * 100.0, 0.0, 100.0)
	
	# PASSO 5: Atualizar display com novos valores
	_update_display()
	
	# PASSO 6: Libera para animação normal
	is_animating_level_up = false

# ======================================
# DISPLAY
# ======================================
func _update_display() -> void:
	# Level
	level_label.text = "LEVEL %d" % XPManagerGlobal.get_level()
	
	# XP atual / necessário (só se show_numbers estiver ativado)
	if show_numbers:
		xp_label.text = "%d/%d" % [
			XPManagerGlobal.get_current_xp(),
			XPManagerGlobal.get_xp_to_next_level()
		]
		xp_label.show()
	else:
		xp_label.hide()

# ======================================
# ANIMAÇÃO DE LEVEL UP
# ======================================
func _play_level_up_animation() -> void:
	var original_label_color := level_label.modulate
	var original_scale := level_label.scale
	
	await get_tree().process_frame
	level_label.pivot_offset = level_label.size / 2.0
	
	# ========================================
	# CRESCER + BRILHAR (tudo simultâneo)
	# ========================================
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(progress_bar, "modulate", Color(1.3, 1.3, 1.3), 0.1)
	tween.tween_property(level_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(level_label, "modulate", Color.YELLOW, 0.1)
	
	await tween.finished
	
	# ========================================
	# VOLTAR AO NORMAL
	# ========================================
	var tween2 := create_tween()
	tween2.set_parallel(true)
	
	tween2.tween_property(level_label, "scale", original_scale, 0.2)
	tween2.tween_property(level_label, "modulate", original_label_color, 0.2)
	tween2.tween_property(progress_bar, "modulate", Color.WHITE, 0.2)
	tween2.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween2.finished
	
	level_label.pivot_offset = Vector2.ZERO
	level_label.position = level_label.position
