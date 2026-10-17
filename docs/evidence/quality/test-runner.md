# Test runner (scripts/test.sh)

## Problema

`swift test` roda os ~1480 testes de todos os alvos em um só processo, em paralelo. Suítes de integração (agentboxd real, zsh, vim,
Docker, LaunchAgent) e suítes de UI (main actor) competiam: timeouts de 30 a 65 s, testes pendurados e `agentboxd --idle-exit 0` órfãos.

## Estrutura

- Tag `integration` (`IntegrationTag.swift` em cada alvo) + `.serialized` + `.timeLimit(.minutes(1))` em 23 suítes: `Daemon*`
  (todas as de `DaemonTests`), `*IntegrationTests`, `Live*` (Docker, `.timeLimit(.minutes(10))`, desligadas sem `AGENTBOX_TEST_DOCKER=1`),
  `RestoreTests`, `LaunchStatesIntegrationTests`, `WorkspaceIntegrationTests`, `WorkspaceModelTests`, `LaunchdSocketTests`,
  `PeerAuthDaemonTests`, `LoginShellEnvRealShellTests`. `ReattachTests` tem teto de 3 min (vim/zsh 20 repetições).
- `scripts/test.sh unit|all|integration [--no-build]`: a lista de suítes vem do próprio código (`.tags(.integration)`).
  `unit` = `--skip` das suítes de integração, em paralelo; `integration` = `--no-parallel --filter`; `all` = unit e depois integration.
  Teto de relógio por fase (240 s / 480 s), resumo curto, log completo em `Packages/AgentBoxKit/.build/test-logs/`, exit 0/1/2.
- Daemons: `DaemonHarness` (dois alvos) nunca usa `--idle-exit 0` (vira 5 s), registra o PID, mata no `defer { harness.terminateNow() }`,
  no `deinit` e num `atexit`. `scripts/test.sh` falha e mata qualquer `agentboxd` do checkout que sobrou vivo depois da fase.
  `terminateNow` não usa `waitUntilExit` (travava numa thread sem run loop e o `.timeLimit` não resgata).
- Higiene de tela: `OffscreenAppKit` (trait `.offscreenAppKit` em todas as suítes de UI) põe a política em `.accessory` (sem Dock),
  cria janelas em (-20000, -20000) sem nunca ordená-las; `MainWindowController.orderingEnabled = false` e
  `TooltipController.orderingEnabled = false` nos testes. `MenuBarController` recebe `StatusBarProviding`; fora do `.app` o
  `AppEnvironment` usa `InMemoryStatusBar` (nunca um `NSStatusItem` real). Gravação de Tela: só `CGPreflightScreenCaptureAccess`.
- Lint (`scripts/lint.sh`): `test-window` (orderFront/makeKeyAndOrderFront/activate em Tests/ fora do helper), `status-bar`
  (`NSStatusBar.system` fora de `MenuBarController.swift`), `screen-capture` (`CGRequestScreenCaptureAccess` proibido; testes sem ScreenCaptureKit).
- Bugs achados no caminho: o seletor "New Clean Session in Folder" abria um `NSOpenPanel` real nos testes (duplicata do seletor do
  composer; agora um só); `ComputerEvent.unclaimed` sem tratamento no `ComputersModel`.

## Resultados (máquina do dono, Xcode 26 / Swift 6.2.4)

| Antes | Depois |
|---|---|
| `swift test` completo: travava (>11 min, 3 timeouts reais, 3 testes pendurados) | `scripts/test.sh all`: ver abaixo |

| Modo | Testes | Tempo |
|---|---|---|
| unit | 1377 testes, 221 suítes | 40 a 48 s |
| integration (em série) | 101 testes, 23 suítes | 241 a 244 s |
| all | 1478 testes | 286 a 292 s |

Execuções consecutivas de `scripts/test.sh all`: ver a seção "Três execuções seguidas" abaixo.

## Três execuções seguidas

`scripts/test.sh all --no-build`: 292 s, 284 s e 285 s, todas exit 0 (1377 unit + 101 integration), zero `agentboxd` vazado ao fim.
Antes disso, duas execuções interrompidas por erro nosso (windows polling pesado e kill externo) e um hang real de
`waitUntilExit` (corrigido) mostraram por que o teto de relógio por fase existe.

## Pendente

- Verificação de janelas/status items por `CGWindowListCopyWindowInfo` foi feita só nas fases unit e em `AttentionIntegrationTests`
  (nenhuma janela nem status item do processo de teste); a fase integration inteira não foi observada ao vivo.
- `ChildDaemon` em produção usa `--idle-exit 60` e os testes que passam por `TerminalRuntime` o herdam (sobram no máximo 60 s).
