extends Node

# =================================================
# LEVEL UP DEBUG - v1.3.25 FASE 1
# =================================================
# Script temporário para testar sistema de Level Up.
# Permite escolher upgrades com teclado.
# 
# TECLAS:
# [Z] = Escolhe opção 1
# [C] = Escolhe opção 2
# [V] = Escolhe opção 3
#
# ATENÇÃO: Será removido na FASE 2 (quando UI estiver pronta)
# =================================================

func _ready() -> void:
	# CRÍTICO: Precisa processar mesmo com jogo pausado!
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	print("\n✅ LevelUpDebug: Sistema de teste ativado!")
	print("🎮 CONTROLES DE LEVEL UP:")
	print("   [Z] = Escolher opção 1")
	print("   [C] = Escolher opção 2")
	print("   [V] = Escolher opção 3\n")


func _input(event: InputEvent) -> void:
	# Só funciona se está aguardando escolha
	if not LevelUpManagerGlobal.is_upgrade_active():
		return
	
	if not event is InputEventKey or not event.pressed:
		return
	
	# Escolher com teclas Z, C, V
	match event.keycode:
		KEY_Z:
			print("\n🎮 Tecla [Z] pressionada - Escolhendo opção 1...")
			LevelUpManagerGlobal.simulate_choice(0)
		
		KEY_C:
			print("\n🎮 Tecla [C] pressionada - Escolhendo opção 2...")
			LevelUpManagerGlobal.simulate_choice(1)
		
		KEY_V:
			print("\n🎮 Tecla [V] pressionada - Escolhendo opção 3...")
			LevelUpManagerGlobal.simulate_choice(2)
