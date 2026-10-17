# Feedback do dono — sessão de teste do app (2026-10-17)

Build testada: commit `e7336da` (cópia em `/private/tmp/claude-501/abview`).

| # | Feedback | Origem | Onde corrigir | Estado |
|---|---|---|---|---|
| F1 | O logo do app sumiu. Restaurar o ícone do app (Dock/Finder, `legacy/Sources/AgentBox/Resources/Brands/AgentBox.icns`) e a marca dentro da janela (`agentbox.png`) ao lado do nome na faixa de topo | Dono | `project.yml` (ícone), AgentBoxDesignSystem/Resources, TitlebarStrip | aberto |
| F2 | Scrim do overlay não escurece o fundo direito; "New Clean Session" da sidebar vaza cortado atrás do diálogo; texto da landing aparece por baixo | Gerente (screenshot) | OverlayHost (scrim cobrindo a janela inteira, incluindo sidebar) | aberto |
| F3 | Logo do OpenCode aparece como quadrado branco | Gerente | DSAgentLogo / Resources/AgentLogos (keying do fundo) | aberto |
| F5 | Settings: topo bugado — a faixa da titlebar (cor e largura da sidebar do app, ~280 pt, com toggle da sidebar e ←/→ que não fazem sentido em Settings) não casa com a navegação de Settings (outra cor, outra largura); fica um degrau/emenda visível entre faixa e nav, e o lado direito da faixa é preto. A faixa de topo em Settings deve ter a mesma cor e largura da nav de Settings, sem degrau, e só mostrar o que vale ali | Dono (screenshot) | SettingsView + TitlebarStrip (modo página inteira) | aberto |
| F6 | Settings › Agents: rótulo "Default agent" duplicado (título da seção e da linha) | Gerente (screenshot do dono) | AgentsSettingsView | aberto |
| F4 | Onboarding grande demais para a proporção do Orca (texto e diálogo) | Gerente | OnboardingView: largura/escala tipográfica conforme 02/03 | aberto |
| F12 | Pedi "spawna um sub agent pra estudar o site de permits de Houston" e o Claude criou um subagente comum no Mac (WebFetch); nenhuma VM subiu. Falta o atributo por sessão "Subagent computers" (Off/Ask/Full access) com toggle no card, no composer e no header; ligado, o lançamento injeta MCP + skill + workers; Ask mostra card de aprovação; hook PreToolUse no spawn como trava de segurança | Dono | `docs/evidence/fixes/subagent-computers/` | corrigido |
| F13 | O app roda com a feature flag da Fatia 1 e esconde tudo das Fatias 2 e 3 já implementadas | Dono | `SliceFlags` (padrão = Fatias 1 a 3; `AGENTBOX_SLICE` restringe), `ActionRegistry` | corrigido |

