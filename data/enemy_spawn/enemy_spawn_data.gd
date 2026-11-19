class_name EnemySpawnData
extends Resource

## =================================================
## ENEMY SPAWN DATA
## =================================================
## Define as propriedades de spawn de cada tipo de inimigo.
## Este Resource é usado pelo SpawnManager para controlar
## quais inimigos spawnar, quando, e com que frequência.
## =================================================

# =================================================
# IDENTIFICAÇÃO
# =================================================
@export var enemy_name: String = "Enemy"
@export var enemy_scene: PackedScene

# =================================================
# SPAWN WEIGHT (Frequência Relativa)
# =================================================
## Peso relativo de spawn. Quanto maior, mais comum.
## Exemplo: weight 100 é 4x mais comum que weight 25
@export var spawn_weight: float = 100.0

# =================================================
# SPAWN COST (Custo em Budget)
# =================================================
## Quanto de "budget" este inimigo consome ao spawnar.
## Inimigos mais fortes devem custar mais.
## Exemplo: Gator = 1.0, Red Gator = 3.0
@export var spawn_cost: float = 1.0

# =================================================
# SPAWN FIT (encaixe físico no spawn/teleporte)
# =================================================
@export_group("Spawn Fit")
## Raio de folga de paredes exigido no spawn, medido no centro do corpo.
## Regra: pelo menos o raio da FAIXA de navegação do inimigo (raio do
## colisor arredondado para cima em NavmeshMerger.RADIUS_STEP). Assim o
## ponto aprovado já cai na malha do tamanho dele. Abaixo disso o inimigo
## pode nascer onde a malha dele não existe (corredor estreito demais).
##
## O offset do centro do corpo NÃO fica aqui: o SpawnManager lê o nó
## BodyCenter da própria cena do inimigo. Havia um body_center_offset
## neste grupo, cópia manual daquele nó, e as duas já divergiram.
@export var spawn_clearance_radius: float = 14.0

# =================================================
# TEMPO DE DISPONIBILIDADE
# =================================================
## Tempo mínimo de jogo (segundos) para este inimigo começar a spawnar
@export var min_game_time: float = 0.0

## Tempo máximo de jogo (segundos) após o qual este inimigo para de spawnar
## Use INF ou valor muito alto para spawnar sempre
@export var max_game_time: float = INF
