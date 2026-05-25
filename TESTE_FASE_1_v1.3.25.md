# 🧪 GUIA DE TESTE - v1.3.25 FASE 1

## ⚡ **TESTE COMPLETO (5-10 minutos):**

---

## 📋 **PREPARAÇÃO:**

### **1. Abrir projeto no Godot:**
```
1. Descompactar survivor_hero-1.3.25.zip
2. Abrir no Godot 4.x
3. Aguardar imports terminarem
✅ Pronto para testar
```

### **2. Verificar console:**
```
Ao iniciar o projeto, deve aparecer no Output (console):

✅ LevelUpManager: Conectado ao XPManagerGlobal
🎮 XPManager inicializado!
   Level: 1 | XP necessário: 10

Se aparecer, sistema está funcionando!
```

---

## 🎮 **TESTE 1: Level Up Automático**

### **Passo a passo:**

```
1. Rodar o jogo (F5)
2. Matar inimigos até coletar XP suficiente
3. Quando XP chegar a 10/10, vai subir de level automaticamente
```

### **O que observar no CONSOLE:**

```
📈 XPManager: +2 XP | Total: 8/10
📈 XPManager: +2 XP | Total: 10/10

==================================================
🎉 LEVEL UP DETECTADO!
==================================================
📊 Novo Level: 2
⏸️ Pausando jogo...
🎮 Estado do jogo: UPGRADE
🎮 Jogo pausado: true

🔧 Gerando opções de upgrade...
   Level do player: 2
   Opções a gerar: 3
   ✅ 3 opções geradas (FASE 1: fixas)

--------------------------------------------------
📋 OPÇÕES DE UPGRADE GERADAS:
--------------------------------------------------
  [1] ⚔️ Fire (Lv1 → Lv2)
      ID: 1 | Type: attack
  [2] ⭐ Speed Boost (NOVO!)
      ID: 1 | Type: powerup
  [3] ⚔️ Ring (NOVO!)
      ID: 2 | Type: attack
--------------------------------------------------

⏳ Aguardando escolha do player...
   (FASE 1: Use console para simular escolha)
   (FASE 2: UI será criada para escolha visual)

==================================================
```

### **✅ RESULTADO ESPERADO:**
- Jogo PAUSA ✅
- Console mostra 3 opções ✅
- Player não consegue se mover ✅
- Ataques param de spawnar ✅

---

## 🎲 **TESTE 2: Simular Escolha (Console)**

### **Com o jogo pausado após level up:**

```
1. Ir na aba "Depurador" (Debugger) do Godot
2. Clicar em "Console"
3. Digitar um dos comandos:
```

### **COMANDOS DISPONÍVEIS:**

```gdscript
# Escolher opção 1 (Fire Lv1 → Lv2):
LevelUpManagerGlobal.simulate_choice(0)

# Escolher opção 2 (Speed Boost NOVO):
LevelUpManagerGlobal.simulate_choice(1)

# Escolher opção 3 (Ring NOVO):
LevelUpManagerGlobal.simulate_choice(2)
```

### **O que observar no CONSOLE após comando:**

```
🎲 SIMULANDO ESCOLHA (DEBUG)...

==================================================
✅ UPGRADE SELECIONADO!
==================================================
📦 Opção escolhida: [1] Fire
📊 Tipo: attack | ID: 1
⬆️ Ataque upado: Fire (Level 1 → 2)

⏯️ Despausando jogo...
🎮 Voltando para estado: COMBAT
🎮 Jogo pausado: false

==================================================
```

### **✅ RESULTADO ESPERADO:**
- Jogo DESPAUSA ✅
- Upgrade aplicado (Fire agora Level 2) ✅
- Player volta a se mover ✅
- Ataques voltam a spawnar ✅

---

## 🔄 **TESTE 3: Múltiplos Level Ups**

### **Testar progressão:**

```
1. Continuar jogando
2. Subir para Level 3 (10 XP adicionais)
3. Repetir simulação de escolha
4. Subir para Level 4
5. Repetir...
```

### **✅ VERIFICAR:**
- Cada level up pausa o jogo ✅
- Opções aparecem sempre (FASE 1: fixas) ✅
- Escolhas funcionam repetidamente ✅
- Jogo sempre despausa após escolha ✅

---

## 🐛 **TESTE 4: Casos Especiais**

### **Tentar escolher sem level up pendente:**

```
Console (com jogo rodando normalmente):
LevelUpManagerGlobal.simulate_choice(0)

Deve aparecer:
⚠️ Não há escolha pendente no momento
```

### **Tentar índice inválido:**

```
Console (com level up ativo):
LevelUpManagerGlobal.simulate_choice(99)

Deve aparecer:
❌ Índice de escolha inválido: 99
```

---

## 📊 **CHECKLIST COMPLETO:**

### **Inicialização:**
- [ ] Autoload conectado ✅
- [ ] Console mostra mensagens de init ✅

### **Level Up:**
- [ ] XP acumula corretamente ✅
- [ ] Jogo pausa ao atingir XP necessário ✅
- [ ] Estado muda para UPGRADE ✅
- [ ] Opções aparecem no console ✅

### **Escolha:**
- [ ] simulate_choice(0) funciona ✅
- [ ] simulate_choice(1) funciona ✅
- [ ] simulate_choice(2) funciona ✅
- [ ] Upgrade é aplicado corretamente ✅
- [ ] Jogo despausa após escolha ✅

### **Múltiplos Levels:**
- [ ] Level 2 → 3 funciona ✅
- [ ] Level 3 → 4 funciona ✅
- [ ] Processo se repete sem bugs ✅

### **Validações:**
- [ ] Escolha sem level up → aviso ✅
- [ ] Índice inválido → erro ✅

---

## 🎯 **EXEMPLO DE OUTPUT COMPLETO:**

### **Sequência esperada:**

```
[INÍCIO DO JOGO]
✅ LevelUpManager: Conectado ao XPManagerGlobal
🎮 XPManager inicializado!

[COLETANDO XP]
📈 XPManager: +2 XP | Total: 2/10
📈 XPManager: +2 XP | Total: 4/10
📈 XPManager: +2 XP | Total: 6/10
📈 XPManager: +2 XP | Total: 8/10
📈 XPManager: +2 XP | Total: 10/10

[LEVEL UP!]
==================================================
🎉 LEVEL UP DETECTADO!
==================================================
📊 Novo Level: 2
⏸️ Pausando jogo...
🎮 Estado do jogo: UPGRADE
🎮 Jogo pausado: true

[OPÇÕES]
--------------------------------------------------
📋 OPÇÕES DE UPGRADE GERADAS:
--------------------------------------------------
  [1] ⚔️ Fire (Lv1 → Lv2)
  [2] ⭐ Speed Boost (NOVO!)
  [3] ⚔️ Ring (NOVO!)
--------------------------------------------------

[ESCOLHA NO CONSOLE]
> LevelUpManagerGlobal.simulate_choice(1)

[APLICAÇÃO]
==================================================
✅ UPGRADE SELECIONADO!
==================================================
📦 Opção escolhida: [2] Speed Boost
🔓 Powerup desbloqueado: Speed Boost (Level 0 → 1)

⏯️ Despausando jogo...
🎮 Voltando para estado: COMBAT

[JOGO CONTINUA NORMALMENTE]
```

---

## ✅ **SE TUDO FUNCIONAR:**

**FASE 1 COMPLETA!** 🎉

Próximo passo: **FASE 2** (criar UI visual para escolha)

---

## ❌ **SE ALGO FALHAR:**

### **Erro: "XPManagerGlobal não encontrado"**
→ Verificar se autoload está registrado no project.godot

### **Erro: "AttackController não encontrado"**
→ Verificar se player tem node AttackController

### **Jogo não pausa**
→ Verificar se GameStateGlobal.set_state está sendo chamado

### **Escolha não aplica upgrade**
→ Copiar mensagem de erro e enviar para análise

---

## 📝 **OBSERVAÇÕES:**

1. **FASE 1 não tem UI visual** - tudo via console
2. **Opções são FIXAS** - sempre as mesmas 3
3. **Serve para validar LÓGICA** antes de criar visual
4. **Próxima fase** criará interface gráfica

---

**Teste e envie o output do console para análise!** 🎯
