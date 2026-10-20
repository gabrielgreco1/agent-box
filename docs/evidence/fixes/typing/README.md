# Fix: terminal que nao aceita digitacao (build e7336da)

## Causa raiz
Clicar no terminal nao devolvia o first responder a `TerminalSurfaceView`: o clique cai na subview Metal do SwiftTerm
(`TerminalMetalLayerView`, nao aceita first responder) e o `mouseDown` do SwiftTerm nao chama `makeFirstResponder`.
Qualquer coisa que roubasse o foco (botao Done do onboarding, tab row, sidebar, Settings oculto, NSOpenPanel) deixava
o foco numa `ChromeHostingView`/`KeyViewProxy` e o clique no pane nao o trazia de volta. Alem disso,
`OverlayFocusCoordinator.restore()` na primeira abertura (nada guardado) devolvia o foco a `contentView`, nao ao terminal,
e fechar o Settings nao devolvia o foco (a view oculta ficava como first responder).

## Correcao
- `TerminalSurfaceView.mouseDown`: sempre `makeFirstResponder(self)` (overlay aberto engole o clique no hit test).
- `OverlayFocusCoordinator.restore()`: responder guardado que seja janela, contentView ou `ChromeHostingView` nao vale; cai em `fallbackFocus` (terminal do pane focado).
- `MainWindowController`: fechar Settings e `windowDidBecomeKey` (volta de NSOpenPanel/sheet/outro app) devolvem o foco ao terminal; `RackyWindow.keyDown` e o watchdog: tecla sem tratador loga `keyDown reached the window but no terminal accepts it` (categoria `focus`) ou refoca o terminal e reenvia.
- `ctl state` expoe `firstResponder` e `blocksTerminalInput`.
- Bug 2: `EnvFilter.default` bloqueia `CLAUDE_CODE_*` (exceto OAUTH_TOKEN/USE_BEDROCK/VERTEX/FOUNDRY), `CLAUDECODE*`, `CLAUDE_AGENT_*`, `CODEX_THREAD*`/`CODEX_SANDBOX*`/`CODEX_SESSION*`/`CODEX_CI`, alem de `ORCA_`, `RACKY_`, `TERM_PROGRAM*` ja existentes.
- Bug 3: `TooltipController` esconde na hora em `didResignKey` da janela do tooltip, `willBeginSheet`, app inativo, miniaturizar/fechar e ao abrir overlay/popover; nao abre em janela que nao e key.

## Testes
- `TypingFocusTests` (daemon real, zsh, `NSEvent` real via `NSWindow.sendEvent`, bytes `.key` contados pelo daemon): tecla direta, clique no pane apos a chrome roubar o foco e arrasto de tab cancelado, tecla sem tratador roteada ao terminal, fechar overlay de primeira abertura. O teste do clique falha sem o override de `mouseDown` (verificado).
- `inheritedParentAgentSessionMarkersAreDropped`, `windowLosingKeyHidesTheTooltipImmediately`.
- `app-state-drive.txt` / `drive.sh`: app real em segundo plano; onboarding aberto = `OverlayHostingView`/bloqueado, apos Done = nao bloqueado.
