extends Label

@export var damage_color := Color(1.0, 0.0, 0.0)

var base_color: Color
var last_health: float = -1.0
var blinking := false


func _ready() -> void:
	# Captura a cor definida no Inspector
	base_color = modulate

	GameStateGlobal.player_health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, _max_health: float) -> void:
	# Arredonda para display (trunca decimal)
	text = str(int(current))

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
