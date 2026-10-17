# T1-06 · agentboxd núcleo (filho do app)

Data: 2026-10-17. SwiftTerm 1.20.0 (pin atual; a 1.99.0 entra na T1-09, P20).

## O que foi entregue
- `agentboxd` (`Sources/agentboxd`): servidor UDS (`UDSListener` + `FramedConnection` da T1-04) em `$AGENTBOX_HOME/run/ptyd-v1.sock`; PTY por `openpty` + `posix_spawn` (`POSIX_SPAWN_SETSID`, `CLOEXEC_DEFAULT`, slave aberto por caminho vira o tty de controle; `pgid == pid`); env exatamente o do `create` (mais `TERM`); `create` idempotente; `list/attach/detach/resize/signal/kill/subscribe/textSnapshot/forget/drainWhenIdle/ping`; leitura do PTY por `DispatchSource` na fila da sessão (nada no main nem no pool cooperativo); coalescência (primeiro byte após silêncio sai na hora; depois 16 ms ou 64 KiB); fila por cliente de 2 MiB (`OutboundQueue`) com `resyncRequired`; replay do ring com contrapressão direta do socket; cold log 2 x 8 MiB + `meta.json` (só nomes de env); saída por ociosidade (60 s) e por `drainWhenIdle`.
- `AgentBoxTerminalCore`: `RingBuffer`, `VTTracker` (cortes, modos, título, OSC 7, OSC 133, bell), `ReplayIndex` (corte mais recente, senão checkpoint de 64 KiB, senão início do ring com `ESC c`; mitigação do S-04), `HeadlessEmulatorHost` (SwiftTerm `Terminal` em fila própria, atrás do stream; pausa a leitura do PTY acima de 8 MiB de backlog), `QueryReplyFilter` (AR-105: o headless nunca responde OSC 52, OSC 4/10/11/12 nem DECRQSS; só responde DA/DSR sem cliente anexado).
- `AgentBoxCore/PTY/PTYClient` (actor): handshake, demultiplexação por sessão, `PTYAttachment.updates` (`.snapshot/.output/.event/.disconnected`), validação de `seq`, resync automático (`resyncRequired`, buraco), reconexão com backoff e reattach por `sinceSeq` (snapshot se o ring não alcança; `sessionGone` se a sessão não existe mais).
- Pendente fora desta tarefa: peer auth (T1-07), LaunchAgent/socket ativado (T1-24), lançamento pelo app (T1-23/24; aqui os testes sobem o binário real como processo filho).

## Testes (`swift test`, 379 testes; `DaemonTests` e `TerminalCoreTests` novos)
Log completo: `swift-test.log`. `DaemonTests` sobe o `agentboxd` real com socket temporário em `/tmp/abd-*`:
- create/attach/input/output, create idempotente, `inputBytesByOrigin`, `textSnapshot`, `ping`.
- Reattach (cliente A morto, cliente B novo, observador O conectado o tempo todo), 20 repetições cada, em duas etapas (S-04): (a) o replay antes do redraw reproduz a tela de A; (b) depois do redraw `cols-1`/`cols` B iguala O; e o `textSnapshot` do daemon iguala o emulador do cliente. Cenários: `vim` (`/usr/bin/vim`), TUI de teste (alt-screen, mouse, bracketed paste, cursor oculto, título), zsh interativo com texto digitado.
- `alt-screen` com 3 MiB de saída e ring de 1 MiB sem `2J`: replay começa num checkpoint e mantém `alt=true`/mouse.
- kill (graceful e force) sem órfãos (três processos do grupo), cliente lento -> `resyncRequired` -> novo `attach` retoma o stream, duas conexões, cold log com rotação 2 x 8 MiB e permissões 0600, env exato, erros tipados (`unknownSession`, `spawnFailed` com errno e path), AR-105 (DA respondido sem cliente, OSC 52/OSC 11/DECRQSS nunca), reconexão por `sinceSeq`, daemon reiniciado -> `sessionGone`, saída por ociosidade e `drainWhenIdle`.
- Unitários: ring (modelo aleatório), rastreador (sequências partidas entre chunks, ESC dentro de CSI), índice de replay, filtro de respostas, emulador.

## Resultado
Reattach 20/20 em todos os cenários acima (texto e modos). A falha do S-04 (`alt-overflow`) está coberta e resolvida pelos checkpoints. Pendências do S-04 mantidas: vídeo e Claude/Codex autenticados (rodada agendada); comparação por atributo de célula.

## Riscos conhecidos
- SwiftTerm 1.20.0 parseia ~4 MiB/s de texto simples; o emulador headless fica atrás do stream e a leitura do PTY pausa acima de 8 MiB de backlog (limita vazão de floods; a 1.99.0 da P20 remove o limite).
- `textSnapshot` espera o emulador alcançar o stream (pode levar segundos sob flood).
