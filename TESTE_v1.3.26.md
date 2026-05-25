# 🧪 TESTE v1.3.26 - UNIFICAÇÃO ATTACK/POWERUP

## ✅ OBJETIVO:

Validar que a unificação funcionou e nada quebrou.

---

## 🎮 TESTE 1: SCRIPTS ANTIGOS (Compatibilidade)

### **Teclas existentes devem continuar funcionando:**

```
[E] Fire++     → Deve upar Fire
[2] Swift Feet → Deve ativar Swift Feet
[6] Magnet     → Deve ativar Magnet
```

**Resultado esperado:**
- ✅ Tudo funciona igual a v1.3.25
- ✅ Nenhum erro no console

---

## 🎮 TESTE 2: LEVEL UP SYSTEM (Novo método)

### **Passo a passo:**

1. F5 (rodar jogo)
2. Coletar XP até 10/10 (Level 2)
3. Jogo pausa + mostra opções
4. Pressionar [Z], [C] ou [V]

**Output esperado:**

```
[ESCOLHER Z - Fire]
✅ Attack 'Fire' upgraded to level 2
⚔️ Fire upado!

[ESCOLHER C - Swift Feet]
✨ PowerUp UNLOCKED: 'Swift Feet' (Level 1)
⭐ Swift Feet desbloqueado!

[ESCOLHER V - Ring]
✅ Attack 'Ring' unlocked (level 1)
⚔️ Ring desbloqueado!
```

**Resultado esperado:**
- ✅ Todas as 3 opções funcionam
- ✅ Upgrades aplicados corretamente
- ✅ Jogo despausa normalmente

---

## 🎮 TESTE 3: MÚLTIPLOS LEVELS

1. Continuar jogando
2. Subir para Level 3, 4, 5...
3. Escolher diferentes opções

**Resultado esperado:**
- ✅ Sistema funciona repetidamente
- ✅ Sem travamentos ou erros

---

## ✅ CHECKLIST COMPLETO:

- [ ] Teclas E/F/T/G funcionam (attacks)
- [ ] Teclas 1-8 funcionam (powerups)
- [ ] Level up pausa o jogo
- [ ] [Z] aplica upgrade
- [ ] [C] aplica upgrade
- [ ] [V] aplica upgrade
- [ ] Jogo despausa após escolha
- [ ] Nenhum erro no console

---

## 📊 SE TUDO FUNCIONAR:

**v1.3.26 = SUCESSO!** ✅

Próximo passo: **FASE 2 (UI visual)**

---

## ⚠️ SE ALGO FALHAR:

Copie o erro do console e me envie!
