# T1-09: evidência de UI do TerminalSurface

Rodado: `open -g -n "Agent Box.app" --env AGENTBOX_AUTOMATION=1 --env AGENTBOX_SCREEN=terminal-demo --env AGENTBOX_HOME=/tmp/abdemo1 --env AGENTBOX_DEMO_SCRIPT=<script zsh>`; o app subiu um `agentboxd` filho, abriu zsh num PTY e digitou o script (origem `ctl`). `demo-status.json`: `metal: true`, 135x52 células, sessão viva. Fechado por PID (o daemon filho encerra junto, sem órfão).

## Limite: não há PNG do pane

O Stage Manager está ligado nesta máquina. Com `open -g` a janela do app em segundo plano vira a miniatura do Stage Manager (136x157 pt, em perspectiva), e `screencapture -x -o -l <windowID>` devolve essa miniatura (272x314 px), sem o conteúdo do terminal. O renderer Metal também não entra em `cacheDisplay` (a tentativa em processo saiu em branco), e o `ctl screenshot` cai no render AppKit, sem Metal (ScreenCaptureKit recusado pelo TCC). Ativar o app só para a captura foi evitado (instrução: segundo plano). Pendente com o dono: um PNG de zsh colorido e vim, capturado com o app em primeiro plano (ou Stage Manager desligado), para o [SxS] de fonte, cor e inset 4.

O que prova o comportamento sem imagem: `TerminalSurfaceTests` (tema, Metal ligado, inset 4, saída colorida na grade do emulador, colar, busca, zoom) e `docs/evidence/slice1/T1-09/`.
