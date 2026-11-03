extends Label

@export var damage_color := Color(1.0, 0.0, 0.0)

var base_color: Color
var last_health: float = -1.0
var blinking := false


func _ready() -> void:
	# Captura a cor definida no Inspector
	base_color = modulate

	GameStateGlobal.player_health_changed.connect(_on_health_changed)

	# Some em EXPLORATION (safe house): ali a vida não importa. Aplicado já
	# aqui, e não só no sinal, porque o jogador nasce na safe house com o modo
	# já declarado (StageConfig, em _enter_tree) — não há transição para avisar.
	GameStateGlobal.state_changed.connect(_on_state_changed)
	_on_state_changed(GameStateGlobal.current_state)


## Pelo estado específico, NUNCA por is_combat_allowed(): ele também é falso em
## PAUSED e UPGRADE, e esconder a vida ao pausar estaria errado.
func _on_state_changed(state: int) -> void:
	visible = state != GameStateGlobal.GameplayState.EXPLORATION


func _on_health_changed(current: float, _max_health: float) -> void:
	# Trunca o decimal (98.7 mostra "98"), mas NUNCA mostra "0" com o jogador
	# vivo: 0.37 de vida mostra "1". Mesmo critério da HealthBar, que com
	# vida > 0 sempre pinta ao menos 1px — a morte só acontece com vida <= 0.
	var shown: int = int(current)
	if current > 0.0:
		shown = maxi(1, shown)
	text = str(shown)

	# Primeira atualização (setup inicial)
	if last_health == -1.0:
		last_health = current
		return

	# Só reage se PERDEU vida
	if current < last_health:
		blink_damage()

	last_health = current


func blink_damage() -> void:
	if blinking:
		return

	blinking = true

	for i in range(2):
		modulate = damage_color
		await get_tree().create_timer(0.1, false).timeout
		modulate = base_color
		await get_tree().create_timer(0.1, false).timeout

	blinking = false
