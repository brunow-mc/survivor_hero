extends Node
class_name PerfProbe

# =====================================================================
# [TEMPORARIO] MEDIDOR MINIMO DE NAVEGACAO — apagar quando a decisao
# entre os caminhos A/B/C/D fechar.
#
# Responde UMA pergunta: quanto custa a navegacao por inimigo, e o
# custo acompanha 'path_recalc_interval'?
#
# 'move_and_slide' esta aqui como CONTROLE, nao como alvo: se ele cair
# junto com a navegacao, os inimigos pararam de andar e a comparacao
# esta contaminada (foi o que estragou o teste de 30 s).
#
# Pontos instrumentados:
#   enemy_base.gd  base_move()       -> "navegacao"
#   enemy_base.gd  _finish_movement()-> "move_and_slide"
#
# Instanciado em spawn_manager_config.gd _ready().
# Relatorio: F10 (nunca imprime por quadro — o console custa caro).
# =====================================================================

static var _acc: Dictionary = {}

## Soma o tempo decorrido desde `inicio_usec` no balde `nome`.
static func probe(nome: String, inicio_usec: int) -> void:
	_acc[nome] = _acc.get(nome, 0) + (Time.get_ticks_usec() - inicio_usec)

# Amostras por balde, em ms por quadro de fisica.
# Array comum, NAO PackedFloat32Array: Packed* sao tipos de VALOR e o
# append iria para uma copia descartada.
var _baldes: Dictionary = {}
var _inimigos: Array = []      # contagem de inimigos, 1 amostra/segundo
var _proxima_amostra: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_acc.clear()

func _process(_delta: float) -> void:
	# Pausa nao e jogo: a fisica para e o quadro fica artificialmente leve.
	if get_tree().paused:
		_acc.clear()
		return

	# Só fecha o quadro quando a fisica rodou (o jogo desenha mais rapido
	# que 60 Hz, entao muitos quadros nao tem tique de fisica nenhum).
	if not _acc.is_empty():
		for nome in _acc:
			if not _baldes.has(nome):
				_baldes[nome] = []
			_baldes[nome].append(_acc[nome] / 1000.0)
		_acc.clear()

	var agora: int = Time.get_ticks_msec()
	if agora >= _proxima_amostra:
		_proxima_amostra = agora + 1000
		_inimigos.append(get_tree().get_nodes_in_group("Enemy").size())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_relatorio()

func _exit_tree() -> void:
	_relatorio()

func _relatorio() -> void:
	if _baldes.is_empty():
		print("[PERF] nada medido.")
		return

	var media_inimigos: float = 0.0
	for n in _inimigos:
		media_inimigos += n
	media_inimigos = media_inimigos / maxf(_inimigos.size(), 1.0)

	print("──── PERF: navegacao ────")
	print("inimigos (media) %.1f | amostras %d" % [media_inimigos, _inimigos.size()])
	for nome in _baldes:
		var v: Array = _baldes[nome]
		v.sort()
		var soma: float = 0.0
		for x in v:
			soma += x
		var media: float = soma / v.size()
		var p95: float = v[mini(int(v.size() * 0.95), v.size() - 1)]
		var por_inimigo: float = (media * 1000.0) / maxf(media_inimigos, 1.0)
		print("  %-16s media %6.3f ms | p95 %6.3f | max %6.3f | %5.1f us/inimigo | quadros %d" % [
			nome, media, p95, v[v.size() - 1], por_inimigo, v.size()
		])
	print("─────────────────────────")
