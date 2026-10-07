extends Node

# =================================================
# HOLD (retenção breve)
# =================================================
# Congela partes específicas do jogo por um instante — o direcional do
# jogador numa travessia de porta, por exemplo. Padrão para TODA pausa breve
# do jogo (portas, início de fase, surgimento de boss, troca na estátua),
# para não nascer uma pausa exclusiva de cada situação.
#
# NÃO se chama "pausa" de propósito: no projeto essa palavra já significa o
# estado PAUSED e a árvore pausada (get_tree().paused). Esses dois continuam
# com o GameStateGlobal; a retenção é uma terceira coisa, mais fina:
#   - get_tree().paused  → congela TUDO (menu de pausa, menu de level-up)
#   - is_combat_allowed() → ninguém fere ninguém (safe house, diálogo)
#   - HoldGlobal          → congela ALGO específico, por um instante
#
# Mora num autoload, e não numa flag do jogador, porque precisa sobreviver à
# destruição do jogador (a troca na estátua recria o jogador no meio da
# retenção).
#
# COMO FUNCIONA
#   - Cada pedido diz O QUE congela (um ou mais Scope) e recebe uma SENHA.
#   - Pedidos se sobrepõem: um alcance só volta a ficar livre quando TODOS os
#     pedidos que o retêm forem devolvidos. Com um booleano simples, o
#     primeiro a terminar destravaria tudo enquanto outro ainda segura.
#   - Dois jeitos de pedir: hold() + release(senha) quando o fim depende de
#     um evento; hold_for() quando é só tempo.
#   - Os NÚMEROS (durações) ficam com quem pede, nunca aqui. O padrão é a
#     forma de pedir; a duração é de cada situação.
#
# SEGURANÇA
#   - clear() é chamado em toda troca de cena (GameStateGlobal._end_current_scene). Sem isso,
#     um pedido cujo dono fosse destruído antes de devolver congelaria o
#     jogador para sempre na cena seguinte.
#   - Senhas nunca se repetem, nem depois de clear(): um hold_for() antigo
#     que expire depois não consegue devolver um pedido novo.
#   - As esperas não usam process_always: durante o menu de pausa (ou de
#     level-up) o cronômetro da retenção espera junto.
#
# ALCANCES: SÓ EXISTE NO CÓDIGO O QUE TEM CONSUMIDOR. Um alcance declarado
# que ninguém consulta seria uma promessa vazia — alguém pede "inimigos" e
# nada acontece, em silêncio. O mapa completo planejado (inimigos, relógio do
# spawn, ataques) está no CLAUDE.md; cada um entra aqui JUNTO com o seu
# consumidor.
# =================================================

## O que pode ser retido. Valores em bits, para combinar com |.
enum Scope {
	## Direcional do jogador. Consumidor: PlayerBase.move().
	PLAYER_INPUT = 1,
}

## O que uma TRAVESSIA (porta) retém. Quem atravessa pede este conjunto, e
## não uma lista própria: quando um alcance novo for implementado (inimigos,
## relógio do spawn, ataques), ele entra AQUI e toda porta passa a retê-lo
## sem tocar no script dela.
const TRANSITION: int = Scope.PLAYER_INPUT

var _holds: Dictionary = {}   # senha (int) -> { "scopes": int, "reason": String }
var _held_mask: int = 0       # união dos alcances de todos os pedidos ativos
var _next_id: int = 1


## Retém os alcances até release(senha). Devolve a senha.
func hold(scopes: int, reason: String) -> int:
	var id := _next_id
	_next_id += 1
	_holds[id] = { "scopes": scopes, "reason": reason }
	_recompute_mask()
	return id


## Devolve um pedido. Senha desconhecida (já devolvida ou limpa) é ignorada.
func release(id: int) -> void:
	if _holds.erase(id):
		_recompute_mask()


## Retém por um tempo e devolve sozinho. Para quando o fim é só tempo.
func hold_for(scopes: int, seconds: float, reason: String) -> void:
	var id := hold(scopes, reason)
	await get_tree().create_timer(seconds, false).timeout
	release(id)


## Pergunta dos consumidores. Barata: um E de bits, pode rodar todo frame.
func is_held(scope: int) -> bool:
	return (_held_mask & scope) != 0


## Zera tudo. Chamado em toda troca de cena.
func clear() -> void:
	_holds.clear()
	_held_mask = 0


func _recompute_mask() -> void:
	_held_mask = 0
	for entry in _holds.values():
		_held_mask |= entry["scopes"]
