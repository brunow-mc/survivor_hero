extends Node

# =================================================
# TARGET TRACKER GLOBAL - v1.3.21b
# =================================================
# Sistema genérico de rastreamento de alvos para evitar
# repetição excessiva em ataques teleguiados/direcionados.
#
# v1.3.21b: Detecção automática de novo batch por tempo
# - Lista zera automaticamente entre batches de ataques
# - Mantém distribuição uniforme DENTRO de cada batch
# - Reset automático quando passa interval do ataque
# =================================================


# -------------------------------------------------
# CONFIGURAÇÃO
# -------------------------------------------------
@export var max_recent_targets: int = 5
## Quantidade máxima de alvos recentes rastreados.


# -------------------------------------------------
# DADOS
# -------------------------------------------------
var recently_targeted: Array[Node2D] = []
## Lista de alvos recentemente escolhidos (FIFO).


# -------------------------------------------------
# CONTROLE DE BATCH (v1.3.21b)
# -------------------------------------------------
var last_add_time: float = 0.0
## Timestamp do último add_target (para detectar novo batch).


# -------------------------------------------------
# ESTATÍSTICAS (debug/analytics)
# -------------------------------------------------
var total_targets_tracked: int = 0
var total_batch_resets: int = 0


# =================================================
# API PRINCIPAL
# =================================================

func add_target(enemy: Node2D, batch_interval: float = 0.0) -> void:
	"""
	Adiciona um alvo à lista de recentemente targetados.
	
	v1.3.21b: Detecção automática de novo batch (OPCIONAL):
	- batch_interval = 0.0 (padrão): comportamento simples, sem reset
	- batch_interval > 0.0: detecta novo batch e limpa lista automaticamente
	
	Args:
		enemy: Inimigo que foi escolhido como alvo
		batch_interval: Intervalo do ataque em segundos (0 = sem detecção de batch)
	"""
	if not is_instance_valid(enemy):
		return
	
	# v1.3.21b: DETECÇÃO AUTOMÁTICA DE NOVO BATCH (se batch_interval > 0)
	if batch_interval > 0.0:
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_since_last = current_time - last_add_time
		
		# Se passou tempo >= interval, é um NOVO BATCH
		if last_add_time > 0.0 and time_since_last >= batch_interval:
			clear_recent_targets()
			total_batch_resets += 1
		
		last_add_time = current_time
	
	# Limpar inválidos antes de adicionar
	_cleanup_invalid_targets()
	
	# Adicionar à lista
	recently_targeted.append(enemy)
	total_targets_tracked += 1
	
	# Manter apenas os últimos N
	if recently_targeted.size() > max_recent_targets:
		recently_targeted.pop_front()


func is_recently_targeted(enemy: Node2D) -> bool:
	"""
	Verifica se um inimigo foi targetado recentemente.
	"""
	if not is_instance_valid(enemy):
		return false
	
	_cleanup_invalid_targets()
	return recently_targeted.has(enemy)


func get_non_recent_enemies(enemies: Array[Node2D]) -> Array[Node2D]:
	"""
	Filtra lista de inimigos removendo os recentemente targetados.
	"""
	_cleanup_invalid_targets()
	
	var available: Array[Node2D] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not is_recently_targeted(enemy):
			available.append(enemy)
	
	return available


func clear_recent_targets() -> void:
	"""
	Limpa completamente a lista de alvos recentes.
	"""
	recently_targeted.clear()


# =================================================
# LIMPEZA AUTOMÁTICA
# =================================================

func _cleanup_invalid_targets() -> void:
	"""
	Remove alvos inválidos/mortos da lista.
	"""
	var valid_targets: Array[Node2D] = []
	
	for enemy in recently_targeted:
		if is_instance_valid(enemy):
			valid_targets.append(enemy)
	
	recently_targeted = valid_targets


# =================================================
# UTILITÁRIOS (debug/analytics)
# =================================================

func get_recent_count() -> int:
	_cleanup_invalid_targets()
	return recently_targeted.size()


func get_stats() -> Dictionary:
	_cleanup_invalid_targets()
	
	return {
		"recent_count": recently_targeted.size(),
		"max_capacity": max_recent_targets,
		"total_tracked": total_targets_tracked,
		"batch_resets": total_batch_resets,
		"utilization": float(recently_targeted.size()) / max_recent_targets if max_recent_targets > 0 else 0.0
	}


func print_stats() -> void:
	var stats = get_stats()
	print("\n═══════════════════════════════════════")
	print("📊 TARGET TRACKER GLOBAL STATS")
	print("═══════════════════════════════════════")
	print("Recent targets: %d / %d" % [stats.recent_count, stats.max_capacity])
	print("Total tracked: %d" % stats.total_tracked)
	print("Batch resets: %d" % stats.batch_resets)
	print("Utilization: %.1f%%" % (stats.utilization * 100))
	print("═══════════════════════════════════════\n")


# =================================================
# LIFECYCLE
# =================================================

func _ready() -> void:
	print("✅ TargetTrackerGlobal initialized (max_recent: %d, auto-reset: ON)" % max_recent_targets)
