# T2-11 Desempenho: 10 sessões em paralelo (AC-608, AC-609, AR-702/703/704/705/706)

Data 2026-10-20, branch `slice4-b`. Máquina: Apple Silicon, 14 CPUs, macOS 27.0.1 (a de referência de 08 §7). Build Release, Metal ligado.
Nenhum modelo rodou: só shells (`yes`, `sleep`, `cat`). Nada do app, do daemon, do launchd nem dos dados do dono foi tocado: o bench sobe um `agentboxd`
próprio em `/tmp` e a medição ao vivo usa uma cópia do app com `AGENTBOX_HOME` temporário (`open -g -n`).

## Como foi medido

| Medida | Ferramenta | Comando |
|---|---|---|
| Eco de tecla (tecla → emulador alimentado), parada do main (timer de 2 ms), CPU e pegada do app (processo do bench com as views reais) e do daemon, custo de atualização da sidebar | `agentbox-bench` (views `TerminalHostView` + Metal reais, daemon real) | `scripts/bench.sh --ten` → `bench-ten.json`; `scripts/bench.sh` → `bench-standard.json` |
| CPU e memória do **app de verdade** e do daemon (RSS e `footprint`) com 10 sessões ociosas e +10 com saída alta | cópia isolada do `Racky.app` Release, `ctl session.launch` com `provider: custom`, `ps`/`footprint` | `scripts/perf-live.sh <Racky.app> <saida.json>` → `live-app.json` |
| Onde o app gasta CPU e memória | `sample`, `footprint` no app isolado | ver "Pontos quentes" |

Cenários do `--ten`: **A** 10 sessões com `yes` todas com view anexada (pior caso) + pane `cat` para o eco; **B** 4 visíveis com `yes` + 6 ocultas com `yes`
(sem view nem anexo, AR-406) + pane de eco; **C** 20 terminais ociosos (10 com view, 10 só no daemon), média de 60 s; **D** custo de uma atualização da sidebar
(snapshot novo aplicado + projeção lida) com 10, 20, 50 e 200 sessões. Janela de carga: 30 s.

Limites do que foi medido (honestidade):

- O cenário da AC-608 pede 15 terminais com TUI a 20 linhas/s e 6 computadores com miniatura (Docker). A carga aqui é **mais dura** (`yes`, sem limite de
  taxa) e sem computadores: miniaturas e viewer dependem de Docker e do `e2e.sh` (AR-706 completo fica com o dono, ver `docs/evidence/hardening/owner-approvals.md`).
- **Tempo de quadro não foi medido**: nesta sessão o renderer não reportou nenhum quadro apresentado (`onFramePresented` não dispara, também no `scripts/bench.sh`
  padrão; em T1-09 disparava). Em vez disso o bench mede a parada do main com um timer de 2 ms (`mainMaxGapMs`, `mainGapP99Ms`), que é o que causa quadro perdido.
  A latência de eco é tecla → emulador (sem o quadro). `xctrace` (Animation Hitches) não foi automatizado.
- "App" no bench é o processo do bench (views reais, sem a janela, a sidebar nem o Insights); os números do app inteiro vêm do `perf-live.sh`.

## Resultado contra os orçamentos (08 §7, 05 AC-608/609)

| Orçamento | Meta | Medido | Veredito |
|---|---|---|---|
| AR-702 eco em repouso (p95) | ≤ 16 ms | 0,85 ms (tecla → emulador) | passa (sem o quadro, ver acima) |
| AR-702 eco, 4 panes com 3 `cat` / `yes` | ≤ 33 ms | 0,48 / 0,26 ms | passa |
| AC-608/AR-702 eco com **10** sessões em `yes`, todas anexadas | ≤ 33 ms | p50 0,26, **p95 1,67**, p99 1,95, máx 2,34 ms, 0 perdidos | passa |
| AC-608 eco com 4 visíveis + 6 ocultas em `yes` | ≤ 33 ms | p95 0,63 ms | passa |
| AR-703 hitch do main com `cat` de 50 MB | ≤ 100 ms | máx 15,2 ms (92 MiB/s) | passa |
| AC-608 hitch do main com 10 `yes` / 4+6 `yes` | ≤ 50 ms | máx 2,55 / 2,61 ms (p99 2,4 ms) | passa |
| AR-704 view de terminal viva | ≤ 30 MB | 23,1 MiB | passa |
| AR-704 / AC-608 sessão no daemon (5 mil linhas) | ≤ 25 MB (AC-608: ≤ 40 MB com 10 mil) | 5,6 MiB (daemon com 20 sessões, 10 em fluxo: 170–186 MiB, ~9 MiB/sessão) | passa |
| AR-704 daemon com 20 sessões | ≤ 600 MB RSS | 184 MiB RSS (carga máxima) | passa |
| AR-704 app com 20 terminais | ≤ 600 MB RSS (AR-706: 800) | **420 MiB RSS** (20 sessões, 10 em `yes`); 284 MiB com 10 ociosas | passa (era 1,4 GiB, ver abaixo) |
| AR-705 20 ociosos, bench (app = processo do bench) | app ≤ 1 %, daemon ≤ 0,5 % | app 0,006 %, daemon 0,19 % (60 s) | passa |
| AR-705 / AC-609 app **real** com 10 ociosas (painel Insights aberto, padrão) | ≤ 1 % de um núcleo, média 60 s | **2,1 a 3,1 %** (era 3,8 a 7,6 %) | **não passa** |
| AR-705 / AC-609 app real com 10 ociosas e o painel direito fechado | ≤ 1 % | 0,05 % | passa |
| AR-705 daemon real com 10 ociosas | ≤ 0,5 % | 0,08 % | passa |
| AC-609 panes ocultos não recebem bytes | 0 | 0 (nenhum anexo, nenhum frame de saída roteado ao app; o app recebeu 46,6 MiB/s só dos 4 visíveis, 119,7 MiB/s com os 10 anexados) | passa |
| AR-706 sidebar a 120 Hz (8,3 ms/quadro; orçamento derivado: atualização com 20 sessões em meio quadro, 4,15 ms) | p95 ≤ 4,15 ms | 10 sessões p95 0,61 ms; **20: 0,72 ms**; 50: 1,85 ms; 200: 7,34 ms | passa (200 sessões já ocupa quase um quadro) |

Sem orçamento na spec, registrado: o **daemon em fluxo** consome 530 a 800 % de um núcleo com 10 `yes` ilimitados (≈ 45 ms de CPU por MiB: parse do
emulador headless, cold log e alocação por frame). Não afeta o eco nem o main (acima), mas é o próximo candidato se o dono quiser um orçamento de CPU do
daemon em carga.

## Pontos quentes encontrados e corrigidos (com teste)

| # | Sintoma medido no app real | Causa | Correção | Depois | Teste |
|---|---|---|---|---|---|
| 1 | **1,4 GiB de RSS** (741 MB de pegada) logo após abrir, sem nenhuma sessão, num Mac com 4,4 GB de transcripts | A primeira varredura do Insights (`JSONLReader`) fazia o parse de JSON numa `Task` desanexada sem pool: os objetos autoreleased só saíam no fim da varredura | `autoreleasepool` por bloco de 4 MiB em `JSONLReader.readLines` e `malloc_zone_pressure_relief` ao fim da varredura | pico 205 MiB RSS, 133 MiB de pegada estável; a primeira varredura passou de > 300 s sem acalmar para 15 s | `JSONLReaderMemoryTests` (80 MB de JSONL: 378 MiB de crescimento sem o pool, < 80 MiB com ele) |
| 2 | App parado com o painel Insights aberto a 7,6 % de CPU | `MachineSampler.readDisk` lia `volumeAvailableCapacityForImportantUsage` a cada tick de 1,5 s: ida e volta XPC **síncrona** ao CacheDelete (a maior pilha no `sample`) | capacidade do volume relida a cada 30 s e reaproveitada | contribuição do disco some do perfil | `MachineSamplerCapacityTests` (20 ticks → 1 leitura) |
| 3 | Enumeração de todos os processos a cada tick (`readProcesses`, 0,5 % de um núcleo) | listas "top" recalculadas a 1,5 s | listas "top" renovadas a cada 2,5 s (CPU e memória da máquina continuam a cada tick) | metade das enumerações | `MachineSamplerCapacityTests` (5 ticks → 3 leituras) |
| 4 | `DSTextStyle.nsFont` (descriptor + eixo variável) no perfil de cada `body` do Insights | fonte recriada a cada renderização | cache de `NSFont` por estilo no `DSTextStyle` | some do perfil | coberto pelos testes de snapshot do DesignSystem/UI (fonte idêntica) |

Também corrigido no caminho: `scripts/bench.sh` nunca funcionou em Release (o `agentboxd` de Release recusava o cliente ad-hoc do bench); agora compila o daemon
com `-DAGENTBOX_ALLOW_ADHOC_PEERS` (só vale se o próprio daemon é ad-hoc, S-03).

## O que ainda não fecha

1. **AR-705 com o painel Insights aberto: 2,1 a 3,1 % contra 1 %.** Os 4 itens acima tiraram o grosso (7,6 % → ~2 %), e o app inteiro com o painel fechado fica em
   0,05 %. O resto é a amostragem da máquina a cada 1,5 s e a re-renderização do painel. Opções que dependem do dono: amostrar a 3 s, ou abrir o app com o painel
   direito fechado por padrão (a spec não fixa a cadência).
2. Tempo de quadro e `xctrace`: precisam do Mac do dono com a tela ligada (item no checklist).
3. AR-706 completo (15 boxes + 2 desktop, miniaturas, `boxes_reserve` → `ready`) precisa de Docker e do `e2e.sh`.

Arquivos: `bench-ten.json`, `bench-standard.json`, `live-app.json` (esta pasta); código em `Packages/AgentBoxKit/Sources/AgentBoxBench`, `scripts/bench.sh`, `scripts/perf-live.sh`.
