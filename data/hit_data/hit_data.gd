extends Resource
class_name HitData

@export var damage: float = 1.0
@export var knockback_force: float = 150.0

# Bônus de dano vindo do upgrade individual do ataque.
# Preenchido em runtime pelo attack_controller — não editável no Inspector.
# Somado ao bônus global do powerup em base_power.gd para aplicação linear.
var damage_upgrade_bonus: float = 0.0

# =================================================
# ÁUDIO - HIT
# =================================================
@export_group("Hit Audio")
@export var hit_sound: AudioStream
@export var hit_sound_volume_db: float = -3.0
@export var hit_sound_pitch_scale: float = 1.0

# =================================================
# ÁUDIO - DEATH
# =================================================
@export_group("Death Audio")
@export var death_sound: AudioStream
@export var death_sound_volume_db: float = 0.0
@export var death_sound_pitch_scale: float = 1.0
