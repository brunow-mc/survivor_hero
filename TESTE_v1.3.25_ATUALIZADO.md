# 🧪 GUIA DE TESTE - v1.3.25 FASE 1 (ATUALIZADO)

## ⚡ **TESTE RÁPIDO (3 MINUTOS):**

---

## 🎮 **TECLAS DE TESTE:**

### **Level Up (durante upgrade):**
```
[Z] = Escolher opção 1
[C] = Escolher opção 2
[V] = Escolher opção 3
```

**ATENÇÃO:** Teclas 1-8 são para PowerUps (já existentes)

---

## 📋 **PASSO A PASSO:**

### **1. Abrir e rodar o jogo:**
```
1. Descompactar survivor_hero-1.3.25.zip
2. Abrir projeto no Godot 4.x
3. Pressionar F5 (rodar jogo)
```

### **2. Ver mensagens de inicialização (console Output):**
```
✅ LevelUpManager: Conectado ao XPManagerGlobal
✅ LevelUpDebug: Sistema de teste ativado!
🎮 CONTROLES DE LEVEL UP:
   [Z] = Escolher opção 1
   [C] = Escolher opção 2
   [V] = Escolher opção 3

🎮 XPManager inicializado!
   Level: 1 | XP necessário: 10
```

### **3. Coletar XP (matar inimigos):**
```
📈 XPManager: +2 XP | Total: 2/10
📈 XPManager: +2 XP | Total: 4/10
📈 XPManager: +2 XP | Total: 6/10
📈 XPManager: +2 XP | Total: 8/10
📈 XPManager: +2 XP | Total: 10/10
```

### **4. LEVEL UP! (jogo pausa automaticamente):**
```
==================================================
🎉 LEVEL UP DETECTADO!
==================================================
📊 Novo Level: 2
⏸️ Pausando jogo...
🎮 Estado do jogo: UPGRADE
🎮 Jogo pausado: true

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
```

**✅ VERIFICAR:**
- Jogo está pausado ✅
- Player não se move ✅
- Ataques param de spawnar ✅

### **5. ESCOLHER UPGRADE (pressionar Z, C ou V):**

**Exemplo: Pressionar [Z] para escolher Fire:**

```
🎮 Tecla [Z] pressionada - Escolhendo opção 1...

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

**✅ VERIFICAR:**
- Jogo despausa ✅
- Player volta a se mover ✅
- Fire agora ataca mais forte (Level 2) ✅

---

## 🔄 **TESTAR MÚLTIPLOS LEVELS:**

```
1. Continuar jogando
2. Coletar mais 10 XP (Level 2 → 3)
3. Jogo pausa novamente
4. Escolher com [Z], [C] ou [V]
5. Repetir várias vezes
```

---

## 📊 **EXEMPLO COMPLETO DE OUTPUT:**

```
[INICIALIZAÇÃO]
✅ LevelUpManager: Conectado ao XPManagerGlobal
✅ LevelUpDebug: Sistema de teste ativado!
🎮 XPManager inicializado!

[COLETANDO XP]
📈 XPManager: +2 XP | Total: 2/10
📈 XPManager: +2 XP | Total: 4/10
...
📈 XPManager: +2 XP | Total: 10/10

[LEVEL UP!]
==================================================
🎉 LEVEL UP DETECTADO!
==================================================
📊 Novo Level: 2
⏸️ Pausando jogo...

--------------------------------------------------
📋 OPÇÕES DE UPGRADE GERADAS:
--------------------------------------------------
  [1] ⚔️ Fire (Lv1 → Lv2)
  [2] ⭐ Speed Boost (NOVO!)
  [3] ⚔️ Ring (NOVO!)
--------------------------------------------------

⏳ Aguardando escolha do player...

[PRESSIONAR TECLA C]
🎮 Tecla [C] pressionada - Escolhendo opção 2...

🎲 SIMULANDO ESCOLHA (DEBUG)...

==================================================
✅ UPGRADE SELECIONADO!
==================================================
📦 Opção escolhida: [2] Speed Boost
📊 Tipo: powerup | ID: 1
🔓 Powerup desbloqueado: Speed Boost (Level 0 → 1)

⏯️ Despausando jogo...
🎮 Voltando para estado: COMBAT

[JOGO CONTINUA NORMALMENTE]
```

---

## ✅ **CHECKLIST DE TESTE:**

### **Inicialização:**
- [ ] Console mostra "LevelUpManager: Conectado" ✅
- [ ] Console mostra "LevelUpDebug: Sistema ativado" ✅
- [ ] Controles [Z] [C] [V] listados ✅

### **Level Up:**
- [ ] XP acumula corretamente ✅
- [ ] Jogo pausa ao atingir 10 XP ✅
- [ ] 3 opções aparecem no console ✅
- [ ] Player para de se mover ✅
- [ ] Ataques param de spawnar ✅

### **Escolha:**
- [ ] Tecla [Z] escolhe opção 1 ✅
- [ ] Tecla [C] escolhe opção 2 ✅
- [ ] Tecla [V] escolhe opção 3 ✅
- [ ] Upgrade é aplicado ✅
- [ ] Jogo despausa ✅
- [ ] Player volta a se mover ✅

### **Múltiplos Levels:**
- [ ] Level 2 → 3 funciona ✅
- [ ] Level 3 → 4 funciona ✅
- [ ] Processo se repete sem bugs ✅

---

## 🎯 **DIFERENÇAS DESTA VERSÃO:**

### **✅ JÁ INTEGRADO:**
- Script de debug já ativado (não precisa criar)
- Teclas Z, C, V já configuradas
- AutoLoad já registrado

### **❌ REMOVIDO:**
- Instruções para criar arquivo manualmente
- Passo de registrar autoload
- Complexidade extra

**Agora é só rodar e testar com [Z] [C] [V]!** 🚀

---

## 📝 **APÓS TESTAR:**

**Copie TODO o output do console e me envie!**

Vou validar:
- ✅ Se está pausando corretamente
- ✅ Se opções estão corretas
- ✅ Se upgrades funcionam
- ✅ Se há erros/warnings

---

## ⚠️ **LEMBRETES:**

1. **Teclas Z, C, V** - escolha de upgrades
2. **Teclas 1-8** - powerups (não use durante level up!)
3. **Sistema é temporário** - será substituído por UI na FASE 2

**Bom teste!** 🎮✨
