# Painel direito: contêiner e módulo Files (10-right-panel)

Rodado em segundo plano: `open -g -n "Racky.app" --env RACKY_AUTOMATION=1 --env RACKY_HOME=/tmp/abrp --env RACKY_APP_SOCK=/tmp/abrp/app.sock --env RACKY_SCREEN=workspace-demo`, com `racky ctl` no mesmo socket isolado. Uma sessão `rp-demo` (shell) aponta para um repositório de fixture em `/tmp/racky-rp-demo` (alterados: `main.swift` M, `notes.md` e `Extra.swift` U; `build/` e `node_modules/` ignorados). App e daemon encerrados por PID no fim.

Captura pelo fallback AppKit (ScreenCaptureKit sem permissão de Gravação de Tela para o app): o corpo Metal do terminal aparece vazio.

| Arquivo | O que mostra |
|---|---|
| `01-files-insights-1440x900.png` | Files (2/3) em cima com chip `Following Terminal`, Insights (placeholder) embaixo, botões Files · Insights · painel na faixa de topo à direita |
| `02-expanded-status-marks.png` | Pastas expandidas, M/U nas linhas, ponto amarelo nas pastas com alterações |
| `03-viewer-search-gutter.png` | Visualizador: realce, número de linha, calha do git (barra verde = linha nova), busca `1 of 2` |
| `04-swapped-modules.png` | Header arrastado/trocado: Insights em cima (`rightPanel.swap`) |
| `05-insights-minimized.png` | Insights minimizado: Files ocupa o painel |
| `06-compact-280.png` | Painel de 280: modo compacto (títulos e chip só com ícone) |
| `07-panel-closed.png` | Painel fechado (⌥⌘0): terminal em tela cheia, botões no mesmo canto |
| `08-760x480-collapsed.png` | Janela mínima: painel recolhido sozinho (<1100), botões dentro da caixa |
| `09-1440x900-restored.png` | Painel fechado/aberto via ações |

Não coberto aqui: o arrasto do mouse (header, divisor, borda) e o motion de recorte são ações/animações de runtime; as ações equivalentes (`rightPanel.move`, `setSplit`, `setWidth`) têm teste. Seguir o cwd é coberto por `FilesControllerTests` (OSC 7 e hook `cwd` entram por `noteCwd`); o `cwd` por hook só chega com `RACKY_SLICE=2` (ActivityService).
