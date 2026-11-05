# Pendências

Trabalho em aberto do Survivor Hero. Atualizar quando um item surgir ou terminar.

## Reorganização da documentação (em andamento)

- Piloto do *Spawn system*: migrado, testado e conferido com o código. Falta o teste só com sintoma, em conversa nova.
- Teleporte pela distância do corpo: em `check_and_teleport_distant_enemies()` (`autoload/spawn_manager.gd`), trocar `enemy.global_position - player.global_position` por BodyCenter do inimigo menos BodyCenter do jogador, reaproveitando `_get_enemy_body_positions()` e ajustando o log de debug. Muda 2 a 3 px, só no eixo vertical. Depois, atualizar a frase sobre pés em `spawn.md`.
- `CLAUDE.md`, seção *Player*: a regra de ordem diz que o `SpawnManagerConfig` é quem exige o `PlayerSpawner` primeiro, mas ele espera um quadro antes de iniciar (`auto_start`). Quem depende da ordem é a `LoadoutBar`. Corrigir ao migrar *Player* e rever o item `SpawnManagerConfig` independente da ordem.
- Regra de trabalho: cada assunto migrado é conferido com o código logo depois, com correção em seguida.
- Destinos:
  - `CLAUDE.md` (meta medida em KB; hoje cerca de 137 KB): o que vale em qualquer tarefa.
  - `.claude/rules/<sistema>.md`: conhecimento de cada sistema, inclusive rejeições ainda válidas.
  - `.claude/skills/`: só procedimentos (nova fase, novo inimigo, novo poder), no projeto.
  - `docs/`: pendências e histórico real.
- Cuidados:
  - Mover sem resumir; nada se perde sem decisão do usuário.
  - Uma regra vive em um só lugar.
  - Regra que vale sempre fica no `CLAUDE.md`.
  - Um sistema por vez; arquivo novo e remoção do `CLAUDE.md` no mesmo commit.
  - Conferir o texto com o código durante a migração.

## Ferramentas e projeto

- `README.md`: talvez escrever uma descrição de verdade do projeto (futuro, opcional)
- Skills, agents e MCP: escolher quando for usar (MCP preferencialmente só para leitura; skill citando a Godot 4.7.2)
- Trocar `run/main_scene` para o menu principal quando existir; botão "Jogar" via `go_to_scene()`
- `remove_powerup()`/`list_active_powerups()`: sair junto com o `TestPowerups`

## Visual

- Silhueta: uma cor por tipo de inimigo; índice e mapa dos tiles da frente na primeira consulta (antecipar se engasgar); miolo mostrando o personagem; itens futuros com outro script
- Efeitos visuais futuros: usar a faixa de z 51–59
- Tiles alternativos no TileSet: investigar para simplificar `building02` / `building02_alpha` (opcional)
- Converter os demais `*_alpha` para opacos à medida que forem usados
- Árbitro de `modulate`

## Calibragem

- Silhuetas (`outline_color`, `fill_alpha`, `tolerance`), `start_hold_seconds`, `initial_spawn_delay`, `fallback_*` do snowflake, `FADE_*` da chamber, `swap_sound_*`, `HOLD_BEFORE_MOVE`/`HOLD_AFTER_MOVE`, `MAIN_MENU_FADE_*`
- `ARRIVAL_CLEARANCE` (6.0)

## Fases, portas e personagens

- Room doors da stage01: ajustar ao level design
- Horda segue o jogador entre salas: manter ou purgar
- Porta trancada
- Desbloqueio de fases
- Ponto de chegada na safe house conforme a porta de origem
- Desbloqueio de personagens via save
- Chamber: reinicializar a `LoadoutBar` na troca; retorno ao tocar chamber bloqueada; migração para `PlayerData`

## Sistemas de jogo

- Alcance de ataques com o tempo parado (boss, hitstop)
- Dano de projéteis já lançados fora de COMBAT: adiado
- XP coletado após a morte: adiado
- Powerups futuros que agem no tempo devem consultar a retenção
- `SpawnManagerConfig` independente da ordem na árvore
- EXPLORATION: torneira/freio/purga
- Prioridade no steering
- Forma do `is_combat_allowed()`
