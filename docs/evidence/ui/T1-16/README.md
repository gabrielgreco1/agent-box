# T1-16: fluxo de lançamento e estados do pane

Rodado: `open -g -n "Racky.app" --env RACKY_AUTOMATION=1 --env RACKY_SKIP_ONBOARDING=1 --env RACKY_HOME=/tmp/abev16`; cada estado vem de `racky ctl ui action session.launch set '<json>'` seguido de `racky ctl screenshot`. App e daemon filho encerrados por PID.

| Arquivo | Pedido | Estado |
|---|---|---|
| `ignition-1440x900.png` | `custom`: `sh -c "sleep 8; echo ready; exec cat"` | Ignição (> 300 ms sem byte): logo + halo, `Preparing launch` concluído, `Starting Terminal…` com spinner, Cancel |
| `claude-ignition-1440x900.png` | `claude --model haiku -p "reply OK"` real | Ignição com o logo do Claude e a linha pendente da sidebar trocando de fase (captura no meio da transição) |
| `running-shell-1440x900.png` | `shell` (zsh de login) | Running: terminal direto (sem ignição, M-506) |
| `exited-0-1440x900.png` | `sh -c "echo done; exit 0"` | Exited (código 0): banner neutro |
| `exited-code-2-1440x900.png` | `sh -c "echo failing; exit 2"` | Exited com erro: cartão `Terminal exited` com Close/Restart |
| `couldnt-start-spawn-1440x900.png` | executável inexistente | Couldn't start (spawn): erro do daemon com o caminho, Copy Details / Try Again |
| `couldnt-start-early-exit-1440x900.png` | `sh -c "exit 3"` | Couldn't start (saída precoce, código ≠ 0 antes de qualquer byte) |
| `claude-exited-0-1440x900.png` | `claude -p` real | Exited (0) depois do `OK`; o ID nativo (`--session-id`) ficou no terminal (`terminal.native_conversation_id`) |

Limites da captura: o fallback AppKit (ScreenCaptureKit sem permissão TCC) não desenha o terminal Metal nem animações em voo. Por isso o voo do chip (M-501) não aparece num quadro parado; ele está coberto por `CAAnimation` com os tokens `flight`, `arcLift` e `clickRing` e some com Reduce Motion. Em duas capturas durante a ignição do Claude o render do fallback levou de 13 a 30 s (logo em imagem dentro de camada com opacidade); só afeta a captura, não a tela.

Testes: `LaunchCoordinatorTests` e `LaunchTimelineTests` (fakes), `LaunchIntegrationTests` (zsh e `claude -p --model haiku "reply OK"` reais via `rackyd`, running -> exited; CLI ausente), `LaunchStatesIntegrationTests` (estados do pane com CLI falso no daemon real).
