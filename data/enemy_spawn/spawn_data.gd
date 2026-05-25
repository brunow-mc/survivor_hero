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
# TEMPO DE DISPONIBILIDADE
# =================================================
## Tempo mínimo de jogo (segundos) para este inimigo começar a spawnar
@export var min_game_time: float = 0.0

## Tempo máximo de jogo (segundos) após o qual este inimigo para de spawnar
## Use INF ou valor muito alto para spawnar sempre
@export var max_game_time: float = INF
