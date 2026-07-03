class_name ItemDropData
extends Resource

## =================================================
## ITEM DROP DATA
## =================================================
## Define uma entrada da drop table de um inimigo:
## qual item pode cair e com que peso relativo.
## Usado por EnemyBase para sorteio ponderado no drop.
## Mesmo padrão de EnemySpawnData no spawn de inimigos.
## =================================================

# =================================================
# ITEM
# =================================================
## Cena do item a ser instanciado no drop (ex: xp_item_01.tscn)
@export var item_scene: PackedScene

# =================================================
# SPAWN WEIGHT (Frequência Relativa)
# =================================================
## Peso relativo de sorteio dentro da drop table. Quanto maior, mais comum.
## Exemplo: weight 100 é ~3x mais comum que weight 30.
@export var spawn_weight: float = 100.0
