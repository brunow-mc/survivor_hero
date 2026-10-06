extends CanvasLayer

# =================================================
# FADE (autoload em forma de CENA: autoload/fade.tscn)
# =================================================
# Escurece e clareia a tela. É uma CENA, e não só um script, porque precisa
# de um nó visual que SOBREVIVA à troca de cena: a porta de fase vai escurecer
# na safe house e clarear já na fase seguinte.
#
# Camada 50: acima do HUD (1) e abaixo dos menus de pausa e game over (90) e
# do level-up (100). Pausar no meio de uma travessia mostra o menu por cima
# do preto.
#
# NÃO congela nada. Quem precisa do jogador parado durante o escuro pede ao
# HoldGlobal; o fade só cobre a tela. Um boss pode reter sem escurecer, e
# isso fica possível justamente por serem duas peças.
#
# As durações vêm de quem chama, como no HoldGlobal.
#
# O tween é preso a este nó, que herda a pausa da árvore: com o menu de pausa
# aberto, o escurecer espera junto — igual às esperas do HoldGlobal.
# =================================================

@onready var overlay: ColorRect = $Overlay

var _tween: Tween = null


func _ready() -> void:
	clear()


## Escurece até preto total. Use com await para esperar terminar.
func fade_out(duration: float) -> void:
	await _fade_to(1.0, duration)


## Clareia até transparente. Use com await para esperar terminar.
func fade_in(duration: float) -> void:
	await _fade_to(0.0, duration)
	overlay.visible = false


## Volta ao estado limpo na hora. Chamado em toda troca de cena: um fade
## interrompido (restart no meio de uma travessia) deixaria a tela preta para
## sempre na cena seguinte.
func clear() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	overlay.modulate.a = 0.0
	overlay.visible = false


func _fade_to(alpha: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	overlay.visible = true

	if duration <= 0.0:
		overlay.modulate.a = alpha
		return

	_tween = create_tween()
	_tween.tween_property(overlay, "modulate:a", alpha, duration)
	await _tween.finished
