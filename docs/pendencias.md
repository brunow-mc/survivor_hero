# Pendências

Trabalho em aberto do Survivor Hero. Atualizar quando um item surgir ou terminar.

## Reorganização da documentação (em andamento)

- Piloto do *Spawn system*: concluído (migrado, testado e conferido com o código).
- *Occlusion silhouette*: concluída (migrada, conferida com o código, corrigida e testada).
- *World objects*: concluída (Chambers, Barrier, cenas `@tool` e `RESET`, Portas e detalhes de troca de cena). Cada parte foi migrada, conferida com o código, corrigida e testada.
- *Context Steering*: concluída (migrada, conferida com o código, corrigida e testada).
- *Enemy system*: concluída (migrada, conferida com o código, corrigida e testada).
- `CLAUDE.md`, seção *Player*: a regra de ordem diz que o `SpawnManagerConfig` é quem exige o `PlayerSpawner` primeiro, mas ele espera um quadro antes de iniciar (`auto_start`). Quem depende da ordem é a `LoadoutBar`. Corrigir ao migrar *Player* e rever o item `SpawnManagerConfig` independente da ordem.
- Regra de trabalho: cada assunto migrado é conferido com o código, corrigido e testado antes do commit que o fecha.
- Destinos:
  - `CLAUDE.md` (meta medida em KB; hoje cerca de 100 KB): o que vale em qualquer tarefa.
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
- Tiles alternativos no TileSet: investigar para simplificar `building_02` / `building_02_front` (opcional)
- Árbitro de `modulate`

## Calibragem

- Silhuetas (`outline_color`, `fill_alpha`, `tolerance`), `start_hold_seconds`, `initial_spawn_delay`, `fallback_*` do snowflake, `FADE_*` da chamber, `swap_sound_*`, `HOLD_BEFORE_MOVE`/`HOLD_AFTER_MOVE`, `MAIN_MENU_FADE_*`
- `ARRIVAL_CLEARANCE` (6.0)
- `steer_enemy_clearance` do gator: falta calibrar. Antes disso, Claude explica ao usuário como esse valor funciona, pois ele ainda não ficou totalmente claro

## Fases, portas e personagens

- Room doors da stage_01: ajustar ao level design
- Horda segue o jogador entre salas: manter ou purgar
- Porta trancada
- Desbloqueio de fases
- Ponto de chegada na safe house conforme a porta de origem
- Desbloqueio de personagens via save
- Chamber: reinicializar a `LoadoutBar` na troca; retorno ao tocar chamber bloqueada; migração para `PlayerData`

## Sistemas de jogo

- **PRIORIDADE ALTA (acima da maioria das pendências):** mover o dano de contato (`_on_hitbox_area_entered/exited`) e o `queue_free()` de `dead_state()` de `enemy_chaser.gd` para `EnemyBase`. Inimigos são boa parte do jogo, e sem isso o primeiro inimigo com script próprio teria um problema sério: não sairia de cena ao morrer e não causaria dano de contato sem copiar código. Fazer antes de chegar nesse ponto.
- Alcance de ataques com o tempo parado (boss, hitstop)
- Dano de projéteis já lançados fora de COMBAT: adiado
- XP coletado após a morte: adiado
- Powerups futuros que agem no tempo devem consultar a retenção
- `SpawnManagerConfig` independente da ordem na árvore
- Spawn: polígono de navegação vazio conta como chão em `_get_nav_layer_data()`. Sem efeito hoje; só importaria num tile com colisão parcial e centro livre
- EXPLORATION: torneira/freio/purga
- Rever a necessidade de `_guard_against_position_jump()`: foi um remendo para os saltos de posição dos inimigos, e esses saltos talvez viessem do sistema de navegação antigo (RVO), que não existe mais. Hipótese ainda não confirmada
- Prioridade no steering
- Forma do `is_combat_allowed()`
- Menu de pausa: apertar Resume durante a espera do `Reload_Timer` não cancela o restart
