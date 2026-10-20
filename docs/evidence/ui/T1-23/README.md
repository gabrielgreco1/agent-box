# T1-23: persistencia e reabertura (sem LaunchAgent)

Rodado: `open -g -n "Racky.app" --env RACKY_AUTOMATION=1 --env RACKY_SKIP_ONBOARDING=1 --env RACKY_HOME=/tmp/abev23`; sessao `session.launch` (custom, loop de ticks) + `pane.splitRight`. App e daemons encerrados por PID.

| Arquivo | O que mostra |
|---|---|
| `1-before-kill-two-panes-1440x900.png` | Sessao com 2 panes lado a lado (daemon filho pid 51650, 2 sessoes PTY) |
| `2-after-reopen-reattached-1440x900.png` | Depois de `kill -9` do app (pid 50974) e reabertura: mesma sessao selecionada, tab, split e foco; o MESMO daemon (pid 51650) seguiu vivo e os 2 panes reanexaram (sem Interrupted) |
| `3-daemon-killed-interrupted-1440x900.png` | `kill -9` no daemon com o app aberto: os 2 panes viram Interrupted (banner "This terminal stopped unexpectedly.", sidebar "Interrupted"), nada relancado. Panes `custom` mostram Restart/Close; agentes mostram Resume/Start Fresh/Close |

Limite: a captura AppKit (sem permissao TCC de ScreenCaptureKit) nao desenha a camada Metal do terminal, entao o scrollback esmaecido nao aparece nos PNGs; ele e verificado nos testes (`RestoreIntegrationTests` le o buffer do emulador).

Comportamento atual do daemon filho: o daemon e filho do app mas nao morre com ele (sem PDEATHSIG no macOS); `kill -9`/crash do app o reparenta ao launchd e as sessoes seguem vivas enquanto houver sessao viva (o idle-exit de 60 s so conta sem sessoes e sem clientes). Com automacao ou `RACKY_STOP_DAEMON_ON_QUIT=1` o app o encerra no quit. Reboot ou kill do daemon mata os PTYs. A T1-24 troca por LaunchAgent com socket do launchd (daemon reiniciado sob demanda, ⌘Q "Keep Running" como caminho normal).
