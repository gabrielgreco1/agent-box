# T1-27 arquivar, apagar e "Open in…"

Rodado: `open -g -n "Racky.app" --env RACKY_AUTOMATION=1 --env RACKY_SKIP_ONBOARDING=1 --env RACKY_HOME=/tmp/abev27/home --env RACKY_APP_SOCK=/tmp/abev27/app.sock`, projeto `rti-platform` temporário (repo com `origin` local e dois worktrees em `/tmp/abev27/ws`; `dev/permits-crawler` com 3 arquivos alterados, 3 não rastreados e 1 commit não publicado). App encerrado por PID.

| Arquivo | O que mostra |
|---|---|
| `delete-worktree-with-changes-1180x760.png` | `session.delete` no worktree sujo: aviso destructive `6 uncommitted files and 1 unpushed commit will be lost.`, lista dos arquivos, `Keep the branch`, sem `Don't ask again` |
| `delete-worktree-clean-1180x760.png` | worktree limpo: texto com a branch que será apagada, `Don't ask again` disponível |
| `delete-worktree-keep-branch-1180x760.png` | `Keep the branch` marcado: o texto passa a dizer que a branch fica |
| `archive-confirm-1040x680.png` | `Archive "<session>"?` |
| `archive-toast-undo-1040x680.png` | sessão some da lista e toast `Session archived.` com `Undo` e barra de tempo |
| `open-in-menu-1040x680.png` | `Open in…`: Finder, Terminal e os editores instalados (aqui só Cursor) |

Tamanhos fora de 1440x900: o fallback AppKit da captura (sem TCC de ScreenCaptureKit) leva 20 a 30 s por quadro com o scrim desfocado e estoura o timeout de 30 s do `ctl` em 1440x900; por isso as capturas usam janelas menores. Sem comparação lado a lado com o Orca (gate P14 fica para a revisão da fatia).

Testes: `SessionRemovalTests` (Core, repos temporários: sujo bloqueia sem force, limpo remove, branch -d, worktree ausente, main nunca), `SessionRemovalFlowTests` (arquivar/restaurar/Undo, apagar worktree/pasta, trabalho novo após o overlay não é apagado, Open in… com detecção por bundle id e NSWorkspace trocado por dublê).

Não feito: XCUITest com clique real (o alvo `AppUITests` segue placeholder; cobertura via `ActionRegistry`, como nas tarefas anteriores); `Open in Editor`/`Reveal` no menu da tab (§3.5); editor/terminal configuráveis em Settings (usa o último editor escolhido, senão o primeiro detectado); `git branch -D` com segunda confirmação; Undo ao apagar worktree ou pasta movida ao Lixo (só o registro seria restaurado).
