# Handoff — 2026-10-17 (fim da sessão por limite de uso)

Branch: `gabrielgreco1/test-project-suite` (sem push). Build: `scripts/bootstrap.sh --fonts && scripts/build.sh` → `build/Racky/Racky.app` (assina com a identidade Apple Development do dono). Testes: `scripts/test.sh unit|integration|all`.

## Feito e mergeado
- Fatia 0 inteira; Fatia 1 quase toda (falta T1-22 menus/atalhos completos e T1-25 fechamento).
- Fatia 2: T2-01/02/03 hooks e injeção, T2-04 atenção/Inbox/notificações, T2-05 núcleo GitHub, T2-10 vault/catálogo. (T2-08 Orca import removido por P21.)
- Fatia 3: T3-01 Docker, T3-02 egress, T3-03 MCP, T3-04 orquestração, T3-05 viewer; F12 toggle "Subagent computers" Ask/Full + spawn guard + linhas de subagente com preview (testado com Docker + haiku real).
- Extras pedidos pelo dono: painel direito (Files + Insights com limites exatos via endpoint OAuth do /usage), arrastar tab/pane para split (F11), clone do GitHub (F24), remoção total do Orca (P21), fix do --resume ao relançar.

## Em aberto (prioridade)
1. **F27 — teclado não chega no terminal no app real.** Pistas: log "Text input context … nil context" ao digitar (teclas indo para um NSTextInputClient invisível — captador do DSMenuPanel/PopoverLayer?); F11 corrigiu PaneAreaView que tirava o foco a cada layout (pode ser parte da causa). Trabalho parcial do agente de foco/navegação na worktree `/Users/gabriel/orca/agent-box/.claude/worktrees/agent-a54f48918d0a663fe` (branch `worktree-agent-a54f48918d0a663fe`, NÃO mergeada) — inclui também F25 (voltar do viewer, Esc/⌘W, reconexão VNC). Revisar, terminar, mergear e testar digitando de verdade no app.
2. Resto da lista de feedback do dono: `docs/evidence/slice1/OWNER-FEEDBACK.md` (F1 logo, F2–F6 visual, F10 órfãos, F16 fechar app, F17 menus de contexto DSMenuPanel, F18 polimento, F20 permissões uma vez, F26 um container por computador — P24).
3. Depois: B (T1-22, T1-25) → C (T2-05 UI, T2-06, T2-07, T2-09, T2-11) → D (T3-06, T3-07, T3-08, T3-09, proxy na reserva) → E (Fatia 4) → v1.1. Roadmap em `docs/rebuild/spec/09-roadmap.md`.

## Regras de operação aprendidas
- Um agente por vez, na pasta principal (CrowdStrike + recompilação do zero por worktree fritam a máquina); worktree e branch apagadas logo após o merge.
- Agentes nunca abrem instâncias do app nem janelas visíveis; testes offscreen, activation policy .prohibited, sem status item real, daemons de teste com --idle-exit 5; nunca pkill/killall amplo; nunca pedir permissão de tela/Keychain automaticamente (P23).
- Subagentes: Haiku para mecânico, Sonnet para código; tarefas pequenas com prazo, sem empilhar pedidos num agente em andamento.
