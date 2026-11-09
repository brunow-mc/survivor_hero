# Pendências

Trabalho em aberto do Survivor Hero. Atualizar quando um item surgir ou terminar.

## Reorganização da documentação (em andamento)

- Piloto do *Spawn system*: concluído (migrado, testado e conferido com o código).
- *Occlusion silhouette*: concluída (migrada, conferida com o código, corrigida e testada).
- *World objects*: concluída (Chambers, Barrier, cenas `@tool` e `RESET`, Portas e detalhes de troca de cena). Cada parte foi migrada, conferida com o código, corrigida e testada.
- *Context Steering*: concluída (migrada, conferida com o código, corrigida e testada).
- *Enemy system*: concluída (migrada, conferida com o código, corrigida e testada).
- *Attack system* e *PowerUp system*: concluída (migrada, conferida com o código, corrigida e testada).
- *Entity anatomy*: concluída (migrada, conferida com o código, corrigida e testada).
- *Player*: concluída (migrada, conferida com o código, corrigida e testada).
- *NavmeshMerger* e *Performance budget*: concluída (migrada, conferida com o código, corrigida e testada).
- *Brief holds*: concluída (migrada, conferida com o código, corrigida e testada).
- *XP & Level-up flow*: concluída (migrada, conferida com o código, corrigida e testada).
- Regra de trabalho: cada assunto migrado é conferido com o código, corrigido e testado antes do commit que o fecha.
- Destinos:
  - `CLAUDE.md` (meta medida em KB; hoje cerca de 60 KB): o que vale em qualquer tarefa.
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
- Código e recurso sem uso, avaliar remoção: `get_attack_stats_with_upgrades()`, `apply_powerup()`, `level_down()`, `get_damage_multiplier()`, `PowerUpStatsGlobal.reset()`, `BasePower.get_hit_data()`/`get_attack_data()`, `LevelUpManager.get_current_options()`, `PRIMARY_01_fire.tres`
- Sorteio das opções do menu por raridade: é para isso que existem `common_weight`, `uncommon_weight`, `rare_weight` e `epic_weight` no `LevelUpManager`. Hoje nenhum código os lê: as opções são sorteadas sem peso. A ideia é preliminar
- `HoldGlobal.hold_for()`: sem chamador hoje, mantido de propósito para pausas que terminam só por tempo
- Comentários de código: buscar e limpar as menções a versões como `v1.3.28`, de antes do uso do GitHub
- Identificadores de shapes nas fases: F5 pode salvar `stage_01`/`safe_house_01` trocando só os ids das shapes com `resource_local_to_scene = true`. É inofensivo, mas confunde os commits. Investigar o que fazer

## Visual

- Silhueta: uma cor por tipo de inimigo; índice e mapa dos tiles da frente na primeira consulta (antecipar se engasgar); miolo mostrando o personagem; itens futuros com outro script
- Efeitos visuais futuros: usar a faixa de z 51–59
- Tiles alternativos no TileSet: investigar para simplificar `building_02` / `building_02_front` (opcional)
- Árbitro de `modulate`
- Silhueta: medir o custo. Cada inimigo e item roda `_process()` copiando propriedades e chamando `FrontTiles.rect_touches()`, mesmo com a cópia invisível, e o custo de render não foi medido depois dela

## Calibragem

- Silhuetas (`outline_color`, `fill_alpha`, `tolerance`), `start_hold_seconds`, `initial_spawn_delay`, `fallback_*` do snowflake, `FADE_*` da chamber, `swap_sound_*`, `HOLD_BEFORE_MOVE`/`HOLD_AFTER_MOVE`, `MAIN_MENU_FADE_*`, `orbit_speed_effectiveness`
- `ARRIVAL_CLEARANCE` (6.0)
- `steer_enemy_clearance` do gator: falta calibrar. Antes disso, Claude explica ao usuário como esse valor funciona, pois ele ainda não ficou totalmente claro

## Fases, portas e personagens

- Room doors da stage_01: ajustar ao level design
- Horda segue o jogador entre salas: manter ou purgar
- Porta trancada
- Desbloqueio de fases
- Ponto de chegada na safe house conforme a porta de origem
- Safe house sem `NavmeshMerger`: decidir se entra. Ele uniria as camadas navegáveis, mas também esconderia sobreposições de navegação entre tiles
- Desbloqueio de personagens via save
- Chamber: reinicializar a `LoadoutBar` na troca; retorno ao tocar chamber bloqueada; migração para `PlayerData`

## Sistemas de jogo

- Alcance de ataques com o tempo parado (boss, hitstop)
- Dano de projéteis já lançados fora de COMBAT: adiado
- XP coletado após a morte: adiado
- Powerups futuros que agem no tempo devem consultar a retenção
- Spawn: polígono de navegação vazio conta como chão em `_get_nav_layer_data()`. Sem efeito hoje; só importaria num tile com colisão parcial e centro livre
- EXPLORATION: torneira/freio/purga
- Rever a necessidade de `_guard_against_position_jump()`: foi um remendo para os saltos de posição dos inimigos, e esses saltos talvez viessem do sistema de navegação antigo (RVO), que não existe mais. Hipótese ainda não confirmada
- Knockback: rever o desalinhamento entre `Hurtbox` e `BodyCenter` nos inimigos. O acerto é detectado na `Hurtbox`, mas a direção do empurrão usa o `BodyCenter`. Tolerado por ora; o design ainda não está concluído
- `enemy-steering.md`: rever "cheapest navigation lever" e os ~370 µs, medidos antes do `NavmeshMerger`. `performance.md` diz que `path_recalc_interval` não é alavanca de desempenho
- Prioridade no steering
- Forma do `is_combat_allowed()`
- Menu de pausa: apertar Resume durante a espera do `Reload_Timer` não cancela o restart
