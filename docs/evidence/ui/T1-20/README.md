# T1-20: composer ⌘N real

Rodado: `open -g -n "Racky.app" --env RACKY_AUTOMATION=1 --env RACKY_SKIP_ONBOARDING=1 --env RACKY_HOME=/tmp/abev20/home --env RACKY_APP_SOCK=/tmp/abev20/app.sock`, projeto = repositório temporário `otter` (com `origin` local), worktrees em `/tmp/abev20/orca-workspaces`, sessões limpas em `/tmp/abev20/sessions`, prefixo de branch `gabrielgreco1`. Tudo via `racky ctl ui action` (as mesmas ações dos cliques) e `racky ctl screenshot`. App e daemon encerrados por PID. Perfil de usuário "Claude · Haiku" (`--model haiku`) para a corrida real; prompt `reply OK`.

| Arquivo | Estado |
|---|---|
| `composer-new-worktree-1440x900.png` / `-760x480.png` | Where = New Worktree, Create from vazio, resumo do comando |
| `composer-existing-worktree-1440x900.png` | Existing Worktree com o combobox de worktrees |
| `composer-main-checkout-1440x900.png` | Main Checkout |
| `composer-advanced-open-1440x900.png` | Advanced aberto (nome, branch padrão como placeholder, localização + Change…) |
| `composer-create-from-branch-exists-1440x900.png` | Create from reconhece branch existente (chip + Reuse existing branch) |
| `composer-create-from-error-1440x900.png` | Create from com branch inexistente (erro no campo, botão desabilitado) |
| `composer-branch-exists-error-1440x900.png` | Advanced › Branch já existe: caixa de erro com `Reuse it` |
| `composer-no-project-new-folder-1440x900.png` | Sem projeto: New Folder |
| `composer-choose-folder-empty-1440x900.png`, `composer-choose-folder-1440x900.png` | Choose Folder… sem pasta (botão desabilitado) e com pasta |
| `composer-blank-terminal-1440x900.png` | Blank Terminal: campos Profile e Prompt somem |
| `composer-discard-confirm-1440x900.png` | Esc com texto: `Discard this session?` inline |
| `pending-immediately-1440x900.png` | Logo depois do submit: overlay fechado, chip voando, linha pendente, PhaseList no centro |
| `pending-error-fetch-1440x900.png` | Fetch falho: erro na linha e no centro com Discard / Create Without Fetching / Try Again |
| `result-running-1440x900.png` | Sessão criada: card selecionado, tab com Claude Code rodando |
| `result-create-without-fetching-1440x900.png` | Depois de Create Without Fetching |
| `composer-new-worktree-vs-prototype-*.png` | Lado a lado, overlay 50% e diff contra `T1-12/composer-prototype-A-keyframe.png` (o fundo difere: o protótipo mostra a landing) |

Limites: o fallback AppKit da captura (sem permissão de Gravação de Tela) não desenha o terminal Metal, então a prova de que o agente roda vem do processo real: `claude --session-id … --model haiku --dangerously-skip-permissions reply OK` com cwd na worktree (`ps`/`lsof`). O voo do chip aparece num quadro de `pending-immediately`. Em `pending-error-fetch` o card "reply OK" está vermelho porque o Claude daquela execução foi encerrado por mim.

Testes: `ComposerDraftTests` (nomes, branch, caminho, validação, resumo, pedido), `SessionCreationTests` (repo temporário: worktree com fetch, colisões, adoção da sessão não iniciada, branch em uso, fetch falho, pastas limpas), `ComposerFlowTests` (fluxo completo por ações, overlay fecha na hora, linha pendente, Create More, erros e Try Again), `ComposerLaunchIntegrationTests` (worktree criada e `zsh` / `claude -p --model haiku "reply OK"` reais no `rackyd`, `AB_REAL_CLI=1`).
