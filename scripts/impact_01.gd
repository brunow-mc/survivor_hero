extends Node2D



@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_02_sound: AudioStreamPlayer2D = $hit02_sound





func _ready() -> void:
	anim.play("impact")
	#hit_02_sound.play()


func _on_timer_timeout() -> void:
	queue_free()
