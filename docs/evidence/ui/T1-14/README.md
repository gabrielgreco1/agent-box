# T1-14: tabs e panes

Rodado: `open -g -n "Agent Box.app" --env AGENTBOX_AUTOMATION=1 --env AGENTBOX_SCREEN=workspace-demo --env AGENTBOX_HOME=/tmp/abev1`; `agentbox ctl ui action pane.splitRight` e `pane.splitDown` montaram a sessão de 3 panes (`three-panes-*.png`). O app subiu o `agentboxd` filho; matei o app por PID e o daemon seguiu vivo (P4); ao reabrir com o mesmo home os 3 panes religaram nas mesmas sessões do daemon (`reattached-1440x900.png`; `terminal.pty_session_id` iguais). Daemon e app encerrados por PID no fim.

Captura pelo fallback AppKit (ScreenCaptureKit sem permissão TCC): o renderer Metal do terminal não entra, então o corpo dos terminais aparece vazio. O conteúdo é coberto por `WorkspaceIntegrationTests` (zsh real no daemon).

`tabrow-vs-orca.png`: tab row do Orca (cima) e do Agent Box (baixo), recortes de escalas diferentes.

Não coberto nesta entrega: hover card da tab, Esc para cancelar o arrasto de tab, rim flash (M-309).
