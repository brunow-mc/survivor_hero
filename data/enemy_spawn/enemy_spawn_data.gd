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
## = raio do colisor do inimigo + pequena margem.
## Gator (colisor r13): 14 | Red Gator (r16): 17.
## Corredor mínimo spawnável para este inimigo ≈ 2x este valor.
@export var spawn_clearance_radius: float = 14.0

## Offset do centro do corpo em relação à origem da cena (os pés).
## Deve coincidir com o node BodyCenter da cena do inimigo.
## Gator: (0,-11) | Red Gator: (0,-16).
@export var body_center_offset: Vector2 = Vector2(0, -11)

# =================================================
# TEMPO DE DISPONIBILIDADE
# =================================================
## Tempo mínimo de jogo (segundos) para este inimigo começar a spawnar
@export var min_game_time: float = 0.0

## Tempo máximo de jogo (segundos) após o qual este inimigo para de spawnar
## Use INF ou valor muito alto para spawnar sempre
@export var max_game_time: float = INF
