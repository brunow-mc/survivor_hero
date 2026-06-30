extends Resource
class_name AttackData

# =================================================
# IDENTITY - NEW v1.1.18
# =================================================
@export_group("Identity")
@export var attack_id: int = 0
@export var attack_name: String = ""
@export var description: String = ""
@export var icon: Texture2D  # Null is OK - add later

# =================================================
# CORE
# =================================================
@export_group("Core")
@export var packed_scene: PackedScene
@export var hit_data: HitData

# -------------------------------------------------
# TIMING
# -------------------------------------------------
@export_group("Timing")
@export var interval: float = 1.0
@export var life_time: float = 5.0
@export var attack_delay: float = 0.0
@export var damage_interval: float = 0.5

@export var activation_delay: float = 0.0
## Tempo (em segundos) antes do ataque começar a causar dano.
## Usado para avisos visuais (beam do Snowflake, charge de outros ataques).

# NOVO v1.4.2
@export var start_immediately: bool = false
## Se true, dispara uma vez imediatamente ao ficar ativo
## (início do jogo OU desbloqueio por level up / debug).
## O timer segue seu ciclo normal após esse disparo inicial.
## Indicado para ataques com interval longo (ex: electricity 8s, gear 10s).

# -------------------------------------------------
# MOVEMENT
# -------------------------------------------------
@export_group("Movement")
@export var speed: float = 100.0
# Bônus de velocidade vindo do upgrade individual do ataque.
# Preenchido em runtime pelo attack_controller. Somado ao bônus global
# do powerup em cada power script para aplicação linear (aditiva).
@export var speed_upgrade_bonus: float = 0.0
# Bônus de orbit_speed vindo do upgrade individual do Gear.
# Preenchido em runtime pelo attack_controller. Entra sem passar por
# orbit_speed_effectiveness (upgrade específico do Gear, efeito pleno).
@export var orbit_speed_upgrade_bonus: float = 0.0

# -------------------------------------------------
# PROJECTILE
# -------------------------------------------------
@export_group("Projectile")
@export var projectile_count: int = 1
@export var projectile_angle_spread: float = 15.0
# NOVO v1.1.14: Delay entre disparos sequenciais (metralhadora)
# 0.0 = disparos simultâneos (padrão atual para power_01, power_05)
# > 0.0 = disparos sequenciais com delay entre cada um (power_02_ring)
@export var projectile_stagger_delay: float = 0.0

# -------------------------------------------------
# HITS
# -------------------------------------------------
@export_group("Hits")
@export var max_hits: int = 1

# -------------------------------------------------
# ATTACHMENT
# -------------------------------------------------
@export_group("Attachment")
@export var attach_to_player: bool = false

# -------------------------------------------------
# ORBIT (para power_05_gear)
# -------------------------------------------------
@export_group("Orbit")
@export var orbit_radius: float = 50.0
@export var orbit_speed: float = 3.0

## Efetividade do projectile_speed_multiplier em orbit_speed.
## 1.0 = 100% do efeito, 0.5 = 50% do efeito (recomendado para gear).
## Usado para evitar que gear fique muito rápido com speed powerups.
@export var orbit_speed_effectiveness: float = 0.5

# -------------------------------------------------
# ÁUDIO - NOVO v1.1.9
# -------------------------------------------------
@export_group("Audio")
@export var attack_sound: AudioStream
@export var attack_sound_volume_db: float = 0.0
@export var attack_sound_pitch_scale: float = 1.0
# NOVO v1.1.12: Flag para powers que gerenciam áudio em loop
# Powers com handles_own_audio = true criam seu próprio AudioStreamPlayer
# e impedem attack_controller de tocar áudio via AudioManager.
# Usado atualmente apenas por power_03_electricity (áudio em loop).
@export var handles_own_audio: bool = false

# =================================================
# ÁUDIO SECUNDÁRIO - NOVO v1.2.2
# =================================================
@export_group("Audio - Secondary (optional)")
@export var secondary_sound: AudioStream
## Som secundário opcional (ex: som de retorno do boomerang).
## Se null, não toca som secundário.

@export var secondary_sound_volume_db: float = 0.0
## Volume do som secundário em dB.

@export var secondary_sound_pitch_scale: float = 1.0
## Pitch do som secundário (1.0 = normal).

# -------------------------------------------------
# SCALE - NOVO v1.1.15
# -------------------------------------------------
@export_group("Scale")
# Escala do ataque (CollisionShape2D e AnimatedSprite2D)
# 1.0 = tamanho original (padrão)
# 0.65 = 65% do tamanho
# 1.35 = 135% do tamanho
@export var attack_scale: float = 1.0

# -------------------------------------------------
# COLLISION - NOVO v1.3.20
# -------------------------------------------------
@export_group("Collision")
@export var collision_area_size: float = 50.0
## Tamanho da área de colisão em pixels.
## Para formas circulares: diâmetro (raio = size/2).
## Usado por ataques que criam collision dinamicamente (Snowflake).
