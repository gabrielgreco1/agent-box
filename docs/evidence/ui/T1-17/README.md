# T1-17 sessões limpas e T1-21 Quick Launch e ⌘T

Rodado: `open -g -n "Agent Box.app" --env AGENTBOX_AUTOMATION=1 --env AGENTBOX_SKIP_ONBOARDING=1 --env AGENTBOX_HOME=/tmp/abev17 --env AGENTBOX_APP_SOCK=/tmp/abev17/app.sock`. Com `AGENTBOX_HOME` isolado, as pastas das sessões ficam em `<home>/AgentBox/sessions` (padrão de produção: `~/AgentBox/sessions`). App e daemon filho encerrados por PID.

| Arquivo | Como | O que mostra |
|---|---|---|
| `T1-17/landing-new-clean-session-1440x900.png` | app vazio | Landing com `Add Project…` e `New Clean Session`; sidebar vazia com os dois botões empilhados |
| `T1-17/clean-session-agent-running-1440x900.png` | `session.newClean press` (um clique, sem diálogo) | Seção "Sessions" com `icy-outpost`, pasta `/tmp/abev17/sessions/icy-outpost`, Claude Code em ignição na tab |
| `T1-17/sessions-section-1440x900.png` | três sessões; uma é `claude -p --model haiku "reply OK"` renomeada `permits-oct` (pasta `gentle-thicket`) | Cards de sessão limpa, pasta no card, estado Exited da sessão haiku (o log do daemon tem `OK`, exit 0) e o Quick Launch aberto |
| `T1-21/quick-launch-1440x900.png` | `tab.quickLaunch` | Popover de 300 pt no "+": campo, agentes (⌥⌘T no padrão, ⌘T no terminal), perfis com flags em mono, Agent Settings…, rodapé de teclas |

Limite conhecido: o fallback AppKit da captura (sem TCC de ScreenCaptureKit) não desenha o terminal Metal.
Testes: `CleanSessionFoldersTests`, `CleanSessionTests` (AC-1101…1106, 1108, AC-313), `QuickLaunchModelTests`, `MenuNavigatorActivationTests`, `LaunchIntegrationTests` (zsh e `claude -p --model haiku` reais na pasta de uma sessão limpa, `AB_REAL_CLI=1`).
