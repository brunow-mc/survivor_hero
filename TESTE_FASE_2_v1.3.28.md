# GUIA DE TESTE - v1.3.28 FASE 2

## 🎯 OBJETIVO
Testar o menu visual de Level Up com navegação por mouse e teclado.

## ✅ CHECKLIST DE TESTE

### 1️⃣ MENU APARECE CORRETAMENTE
- [ ] Subir de level (matar inimigos para ganhar XP)
- [ ] Menu de Level Up aparece automaticamente
- [ ] Jogo pausa quando menu aparece
- [ ] Overlay escuro semi-transparente está visível
- [ ] Fundo amarelo do menu está correto
- [ ] Título "LEVEL UP!" aparece no topo

### 2️⃣ OPÇÕES EXIBIDAS
- [ ] 3 opções aparecem em coluna vertical
- [ ] Opção 1: "Fire Power Lv2" com descrição
- [ ] Opção 2: "Swift Feet Lv1" com descrição
- [ ] Opção 3: "Ring Attack Lv1" com descrição
- [ ] Placeholders cinzas 32x32 à esquerda de cada opção
- [ ] Nomes em fonte maior que descrições

### 3️⃣ NAVEGAÇÃO POR TECLADO
- [ ] Seta ↑ move seleção para cima
- [ ] Seta ↓ move seleção para baixo
- [ ] Enter confirma a escolha
- [ ] Primeira opção já vem com focus ao abrir

### 4️⃣ NAVEGAÇÃO POR MOUSE
- [ ] Hover visual funciona (botão muda ao passar mouse)
- [ ] Clicar no ícone cinza funciona
- [ ] Clicar no texto funciona
- [ ] Clicar em qualquer parte do botão funciona

### 5️⃣ APLICAÇÃO DO UPGRADE
- [ ] Escolher Fire: Fire Power sobe de Lv1 → Lv2
- [ ] Escolher Swift Feet: PowerUp Swift Feet é desbloqueado
- [ ] Escolher Ring: Ring Attack é desbloqueado
- [ ] Console mostra mensagem de upgrade aplicado
- [ ] Menu desaparece após escolha
- [ ] Jogo retoma automaticamente

### 6️⃣ MÚLTIPLOS LEVEL UPS
- [ ] Subir de level novamente
- [ ] Menu aparece novamente
- [ ] Mesmas 3 opções (FASE 2 é fixo)
- [ ] Processo se repete normalmente

## 🐛 BUGS CONHECIDOS (ESPERADOS)

### Limitações da FASE 2:
- Opções são sempre as mesmas (Fire/Swift/Ring)
- Descrições não refletem level atual real
- Sem ícones (só placeholders)
- Sem animações ou sons
- Fire sempre mostra "Lv2" mesmo se já está em outro level

## 🔍 VERIFICAÇÕES VISUAIS

### Layout esperado:
```
┌─────────────────────────────────┐
│        LEVEL UP!                │
│                                 │
│  ┌──┐ Fire Power Lv2           │
│  │░░│ +10% Damage               │
│  └──┘ -5% Cooldown              │
│                                 │
│  ┌──┐ Swift Feet Lv1           │
│  │░░│ +100 Move Speed           │
│  └──┘                           │
│                                 │
│  ┌──┐ Ring Attack Lv1          │
│  │░░│ +1 Projectile             │
│  └──┘                           │
└─────────────────────────────────┘
```

### Cores:
- Overlay: Preto com 62.7% transparência
- Fundo menu: Amarelo (R:1.0, G:0.72, B:0.0)
- Placeholders: Cinza médio (50% cinza)
- Texto: Branco (padrão do tema)

## 📝 CONSOLE OUTPUT ESPERADO

Ao subir de level:
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
  [2] ⭐ Swift Feet (NOVO!)
      ID: 2 | Type: powerup
  [3] ⚔️ Ring (NOVO!)
      ID: 2 | Type: attack
--------------------------------------------------

⏳ Aguardando escolha do player via UI...
==================================================
```

Ao escolher:
```
🖱️ Opção selecionada na UI: [1]

==================================================
✅ UPGRADE SELECIONADO!
==================================================
📦 Opção escolhida: [1] Fire
📊 Tipo: attack | ID: 1
⚔️ Fire upado!

⏯️ Despausando jogo...
🎮 Voltando para estado: COMBAT
🎮 Jogo pausado: false

==================================================
```

## ✅ SUCESSO!
Se todos os itens acima funcionarem, a FASE 2 está completa e pronta para FASE 3!
