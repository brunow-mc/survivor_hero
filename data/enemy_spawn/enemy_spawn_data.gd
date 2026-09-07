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
## Referência: o raio do colisor do inimigo. Um pouco abaixo dele é
## calibragem legítima — permite 1-3px de sobreposição que a física
## resolve no primeiro quadro, e ganha corredores estreitos.
##
## Raios reais em uso: Gator 10 | Red Gator 15.
## Calibragem em stage01: Gator 7 | Red Gator 16.
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
