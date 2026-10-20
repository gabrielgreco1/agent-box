# 05 · Jornadas e critérios de aceite

Agent Box rebuild · capítulo 05 · 2026-10-16
**Revisado após R1–R3 em 2026-10-16** (patches de `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`, com as decisões P11–P16 do `00`).
Depende de: `00-decisions.md` (prevalece), `01-product.md` (princípios PP-*, modelo e estados). Base: `docs/rebuild/audit/10-review-journeys.md` (jornadas J1–J10 e requisitos R*.*), com 01, 05, 07, 08 e 09.
Referências cruzadas: UI em `03-screens.md`, motion em `04-motion.md`, terminais, agentes, biblioteca e GitHub em `06-terminals-and-agents.md`, computadores e subagentes em `07-computers-and-subagents.md`, arquitetura, testes e segurança em `08-architecture-quality.md`.

Este capítulo descreve o comportamento-alvo final de cada jornada, já com as decisões aplicadas, e o critério de aceite testável de cada passo. A v1 está pronta quando todos os ACs marcados v1 passam e o dia real da §0.4 acontece.

---

## 0. Como ler

### 0.1 Formato

Cada jornada tem: versão, pré-condições, roteiro-alvo (passo a passo, com o texto de UI em inglês), falhas e o que o usuário vê, e os critérios de aceite.

Cada critério tem ID `AC-<jornada><nn>` (AC-301 é o primeiro da J3; os transversais são `AC-T<nn>`), versão, método de verificação e requisitos cobertos, no formato:

> **AC-000** · v1 · `XCUI` · R0.0
> **Dado** contexto · **Quando** ação · **Então** resultado observável.

Os textos de UI citados nos ACs são o microcopy de referência e seguem 03 (que prevalece em microcopy e atalhos, P16). Se 03 mudar a redação, o AC muda junto.

Convenções desta revisão:
- Referências à auditoria levam o prefixo `audit/NN` (ex.: `audit/07 #23`, `audit/09 N4`); `NN §x` sem prefixo é capítulo da spec.
- Estados de agente, processo e computador são os de 01 §6 (conjunto canônico, R1 K-78 a K-80).
- Motion é citado pelo ID `M-xxx` de 04; `accessibilityIdentifier`, pela convenção de 02 §17 e pela lista de 03 §22; atalhos, pela tabela de 03 §21; identificadores técnicos (bundle `app.agentbox.mac`, label `app.agentbox.ptyd.v1`, env `AGENTBOX_PANE_ID`/`AGENTBOX_RUN_ID`), pelos de 08.
- Ferramentas MCP com os nomes de 07 §3.2 e §4.2 (`boxes_reserve`, `box_claim`, `help_request`, `help_wait`, `exec`, `http_request`, `browser_type`, `agent_wait`).
- Proxy segue P13: genérico, escolhido pelo usuário, sem teto de orçamento nem corte automático.
- Cada AC vale a partir da fatia de 01 §4.1 em que a superfície existe; controle de fatia futura não é renderizado (AC-T28).

### 0.2 Métodos de verificação

| Método | O que é | Onde roda |
|---|---|---|
| `UNIT` | Swift Testing sobre domínio, adapters (argv por perfil), parsers e migrações | CI macOS |
| `XCUI` | XCUITest no projeto Xcode gerado, localizando controles por `accessibilityIdentifier`. Usa `AGENTBOX_FAKE_RUNTIME=1` (Docker falso) e os stubs de CLI quando indicado | CI macOS e local |
| `E2E` | `scripts/e2e.sh` dirigindo o app por `agentbox ctl`, com daemon real e, quando a jornada pede, Docker real. Gera evidência JSON em `docs/evidence/` | Mac do dono ou runner self-hosted (runner macOS do GitHub não roda Docker) |
| `CLI` | Teste de contrato com o CLI real instalado (`AGENTBOX_REAL_CLI=1`), modelo barato e poucas chamadas | Local, antes de cada release |
| `PERF` | Instruments/`xctrace` (Animation Hitches, Time Profiler) com o protocolo de 08 | Local |
| `MANUAL` | O Gabriel executa numa build assinada de forma estável, com gravação de tela. Usado para site real, julgamento visual e motion | Mac do dono |

Um AC pode listar mais de um método; todos precisam passar.

### 0.3 Fixtures comuns

| Fixture | Conteúdo |
|---|---|
| `F-ORCA` | Cópia anonimizada de `profile-state.db` (com `-wal`/`-shm`) e de `orca-data.json` para o fallback (06 §6.1), com 6 repositórios, 103 worktrees e `agentDefaultArgs` reais, mais a árvore `~/orca/workspaces` correspondente em diretório temporário (`ORCA_HOME` de teste). As contagens são da fixture; o Orca real do dono tinha 7 e 111 em 2026-10-16 |
| `F-CLI` | Stubs `fake-claude` e `fake-codex` que aceitam as flags reais, imprimem uma TUI mínima e disparam os hooks por lançamento (SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop, StopFailure, SubagentStart/Stop) num roteiro controlado pelo teste |
| `F-REPO` | Repositório Git temporário com remote bare local; para PR, o repositório de teste `gabrielgreco1/agentbox-e2e` no GitHub |
| `F-SITE` | Servidor local, alcançável só pelo egress de teste, com páginas que exigem humano (formulário "I'm not a robot" de teste), XHR com JSON, login simples e uma página que redireciona |
| `F-HOME` | `$HOME` temporário com `~/.claude/settings.json`, `statusLine`, hooks do Orca, `~/.codex/config.toml` com `notify` e a skill global `agentbox`, todos com hash registrado antes do teste |
| `F-LONG` | Projetos, sessões, branches, agentes, skills, computadores e credenciais com nomes de 80+ caracteres, sem espaços e com espaços, mais strings longas de erro, para os testes de transbordo (AC-T27) |
| `F-REF` | Pacote de referência do Orca 1.4.219 em `docs/rebuild/reference/orca-1.4.219/` (PNG @2x por superfície, 1440×900, tema escuro, mesmos dados fictícios destas fixtures, `manifest.json` ligando cada PNG à tela de 03 e ao identificador do Agent Box) (P14, R3 §5) |

### 0.4 Definição de pronto da v1 (RT.2)

1. Todos os ACs marcados v1 passam nos métodos indicados.
2. O Gabriel roda, num dia real e numa build com assinatura estável, as jornadas J2, J3, J4, J6, J8 e J11, com gravação de tela, e usa o Agent Box no lugar do Orca nesse dia.
4. Toda tela da v1 tem a evidência lado a lado com o Orca e o OK explícito do dono registrado (P14, AC-T26).
3. Um lote real de pelo menos 10 subagentes com computador (J4) termina com resultado e evidência no host, sem intervenção fora do app.

---

## J1 · Primeira abertura e onboarding

**Versão**: v1 (importação de runs antigos: v1.1).
**Pré-condições**: app instalado por `install.sh`, sem banco. Orca com dados. Docker Desktop instalado e parado. Claude e Codex logados, OpenCode instalado, `gh` logado.

### Roteiro-alvo

1. O Gabriel abre o app. A janela já tem o visual final: titlebar do Orca, sidebar vazia com as seções "Projects" e "Sessions" (P11). Por cima, um overlay de onboarding (cartão dentro da janela, não sheet) com o título "Set Up Agent Box". Todas as verificações rodam em paralelo e mostram resultado em até 3 s (microcopy de referência em 03 §15):
   - "Claude Code · 2.1.302 · Logged in", "Codex · 0.160.0 · Logged in", "OpenCode · 1.18.34 · Login can't be verified". Um CLI deslogado mostra "Log In", que abre um terminal inline no próprio onboarding com o comando oficial de login.
   - "GitHub CLI · Logged in as gabrielgreco1 · repo, workflow". Sem login: "Log In", que abre o terminal inline com `gh auth login`.
   - "Docker · Docker Desktop is installed but not running" com "Start Docker". O app abre o Docker, espera o socket e o item vira "Running". Logo abaixo, "Computer image · Not downloaded · 1.2 GB" com "Download" e "Build Locally". O download ou build corre em segundo plano com progresso, sem travar o resto. Depois aparece a capacidade: "VM memory 8 GB · ≈ 6 headless or 3 desktop computers".
   - "Notifications" com "Allow" e a frase "So you know when an agent needs you."
   - "Keep agents running" ("Terminals survive quitting Agent Box.") com "Allow in Login Items". Ao confirmar, o app registra o agente de login e mostra "Approved" ou "Needs approval in System Settings" com o botão que abre o painel certo.
2. **Import from Orca**: "Found 6 projects, 103 worktrees and default agent arguments." com "Review…", que troca o conteúdo do overlay para o passo "Import from Orca" (texto "Nothing is moved or written to Orca."; grupos "Projects", "Worktrees", "Default agent arguments"). Agentes e skills não são importados: a Biblioteca já lê as pastas nativas. "Import" cria projetos e sessões sem mover arquivos. As sessões entram sem processo e sem tabs (P15).
3. **Perfis**: os `agentDefaultArgs` viram os perfis padrão "Claude · Skip permissions" e "Codex · Bypass approvals", com aviso de uma linha. Nenhum proxy é criado nem escolhido (P13): o proxy é configurado depois, em Settings (o importador de `.env` de Settings › Credentials reconhece `ZYTE_API_KEY` e oferece o preset Zyte).
4. **Conflicts** (só informativos, exceto o último):
   - "Orca hooks found (harmless)."
   - "Codex notify is used by another app (left untouched)."
   - `A global "agentbox" skill is installed and may compete with Agent Box tools.`, com "Block in Agent Box" (padrão; bloqueio por lançamento), "Disable Globally…" (move com backup) e "Keep".
5. "Done" abre o composer com o último projeto usado no Orca já selecionado. Sem projetos, abre a landing com "Add Project…", "New Clean Session" e "Import from Orca…".

A mesma checklist fica em Settings › Diagnostics, com "Run All Checks Again".

Fatias (01 §4.1): na Fatia 1 só existem os itens de CLI (detectado, logado ou não). O restante da checklist, a importação e os conflitos chegam na Fatia 2; Docker e imagem fazem sentido a partir da Fatia 3, mas a detecção já aparece na Fatia 2.

### Falhas e o que aparece

| Situação | UI |
|---|---|
| Uma verificação passa de 10 s | O item mostra "Couldn't check · Try Again"; os outros seguem |
| Nenhum runtime Docker | "No Docker runtime found" com "Get Docker Desktop" e a alternativa OrbStack; o resto do app funciona só com terminais |
| Build ou download da imagem falha | "Image build failed" com "Show Log" e "Try Again"; onboarding continua |
| `profile-state.db` e `orca-data.json` ilegíveis ou ausentes | Passo de importação mostra "Nothing to import" ou "Couldn't read Orca data · Skip" |
| Notificação negada | Cartão "Notifications are off for Agent Box." com "Open System Settings" e "Send Test Notification" |
| Aprovação de segundo plano negada | "Agents will stop when you quit. Turn on in Settings › General." O quit passa a perguntar e encerrar |

### Critérios de aceite

> **AC-101** · v1 · `XCUI` · R1.1, T5, audit/07 #23
> **Dado** um primeiro lançamento sem banco · **Quando** a janela abre · **Então** o onboarding aparece como overlay dentro da janela (não `NSWindow` de sheet), com foco no primeiro controle do overlay, Tab preso dentro dele e Esc pedindo "Skip setup?".

> **AC-102** · v1 · `XCUI` (stubs com atraso) + `MANUAL` · R1.1
> **Dado** stubs de CLI, `gh` e Docker que respondem em 1 s · **Quando** o onboarding abre · **Então** todos os itens saem de "Checking…" em até 3 s, e um item travado não atrasa os outros (cada item tem timeout próprio de 10 s com "Try Again").

> **AC-103** · v1 · `XCUI` · R1.1, PP-1
> **Dado** a checklist · **Quando** se inspeciona cada item · **Então** todo item tem estado, motivo em uma linha e no máximo uma ação primária, e o botão "Skip for Now" leva ao app em qualquer momento sem perder o que já foi feito.

> **AC-104** · v1 · `XCUI` (stub deslogado) + `MANUAL` · R1.1, audit/01 D5
> **Dado** o Codex deslogado · **Quando** o usuário clica "Log In" no item do Codex · **Então** um terminal inline abre rodando `codex login`, e ao fim do login o item vira "Logged in" sem reiniciar o onboarding.

> **AC-105** · v1 · `E2E` (Docker real) · R1.2, audit/05 P0.8
> **Dado** Docker Desktop instalado e parado, contexto ativo `desktop-linux`, sem Colima · **Quando** o usuário clica "Start Docker" · **Então** o app abre o Docker Desktop, espera o socket, o item vira "Running" em até 90 s, e em nenhum momento o app sugere Colima ou usa um contexto fixo.

> **AC-106** · v1 · `E2E` · R1.2, R4.7
> **Dado** Docker rodando · **Quando** a checklist termina · **Então** o item de capacidade mostra a memória da VM lida de `/info` e o número de computadores headless e desktop que cabem, calculado com os perfis de recurso de 07.

> **AC-107** · v1 · `E2E` · audit/05 P0.8, T7
> **Dado** a imagem ausente · **Quando** o usuário clica "Download" · **Então** a imagem é baixada por digest com progresso visível no item, o onboarding segue navegável, e se o registry falhar o item oferece "Build Locally" com progresso; ao fim, o item mostra "Ready" e o digest.

> **AC-108** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-109** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-110** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-111** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-112** · v1 · `E2E` com `F-HOME` · R1.5, PP-6, T10
> **Dado** os hashes de `~/.claude/settings.json`, do script de statusline, de `~/.claude/skills`, de `~/.codex/config.toml` e de `~/.codex/hooks.json` · **Quando** o onboarding termina e o usuário lança Claude e Codex com MCP e hooks do Agent Box · **Então** todos os hashes continuam iguais e o estado dos agentes funciona (AC-601). Se os hooks do Codex por `-c` exigirem trust gravado no `config.toml` (spike S-05 de R3), o Codex aparece com a marca `estimated` em vez de o app gravar o trust: o hash continua igual em qualquer caso.

> **AC-113** · v1 · `XCUI` com `F-HOME` · R1.6, T12
> **Dado** a skill global `agentbox` em `~/.claude/skills` · **Quando** o onboarding chega a "Conflicts" · **Então** o item mostra `A global "agentbox" skill is installed and may compete with Agent Box tools.` com "Block in Agent Box" (padrão; `permissions.deny` por lançamento, nada global muda), "Disable Globally…" e "Keep"; "Disable Globally…" move a pasta para um backup do app, e "Restore Skill" em Settings › Agents › Agent Box skill desfaz. Não existe opção "Redirect" (01 §4.4).

> **AC-114** · v1 · `XCUI` · R1.5
> **Dado** hooks do Orca em `~/.claude/settings.json` e `notify` do Codex ocupado · **Quando** o onboarding chega a "Conflicts" · **Então** os dois aparecem como informação, sem botão de ação que altere esses arquivos.

> **AC-115** · v1 · `XCUI` (stub de `gh`) · R1.7
> **Dado** `gh` instalado e logado · **Quando** a checklist roda · **Então** o item mostra versão, usuário e escopos; **dado** `gh` deslogado, o item mostra "Log In", que abre o terminal inline com `gh auth login`.

> **AC-116** · v1 · `MANUAL` · audit/07 #39
> **Dado** a permissão de notificação negada no macOS · **Quando** o usuário abre o item · **Então** o app relê o estado real do sistema e mostra "Open System Settings" e "Send Test Notification"; nenhum toggle volta a "off" em silêncio.

> **AC-117** · v1 · `MANUAL` + `E2E` · R1.8, P4
> **Dado** o item "Keep agents running" · **Quando** o usuário clica "Allow in Login Items" · **Então** o agente de login é registrado, o estado aparece como "Approved" ou "Needs approval in System Settings" com o botão para o painel certo, e o pedido de aprovação não aparece antes desse clique.

> **AC-118** · v1 · `UNIT` + `XCUI` · R1.4 (parte), T9, P13
> **Dado** `ZYTE_API_KEY` em `~/orca/projects/agentbox/.env` · **Quando** o usuário usa "Import .env File…" em Settings › Credentials e marca a chave · **Então** o valor vai para o Vault do app (08 AR-510/511), Settings › Credentials mostra só o nome, a origem e o valor mascarado, o app oferece `Import from agentbox CLI…` em Settings › Computers › Proxies, que cria um proxy com o preset `Zyte (proxy)` sem defini-lo em `Default proxy for computers`, e o valor não aparece em banco em claro, log nem exportação de diagnóstico.

> **AC-119** · v1.1 · `E2E` · R1.4
> **Dado** `~/orca/projects/agentbox/runs` com 34 runs · **Quando** o usuário importa o histórico do CLI antigo · **Então** cada run aparece só leitura (result, journal, reqlog) na seção de histórico de computadores, sem copiar os 1,3 GB, e os pais podem consultá-los pelo MCP (`runs_search`).

> **AC-120** · v1 · `XCUI` · fluxo J1 passo 5
> **Dado** o onboarding concluído com projetos importados · **Quando** o usuário clica "Done" · **Então** o composer abre com o último projeto usado no Orca selecionado; sem projetos, aparece a landing (`landing`) com "Add Project…", "New Clean Session" e "Import from Orca…".

---

## J2 · Começar o dia

**Versão**: v1 (inbox "Since you were away" completo: v1.1).
**Pré-condições**: app usado no dia anterior; daemon com sessões vivas, ou Mac reiniciado durante a noite.

### Roteiro-alvo

1. 9h. O app está aberto desde ontem, ou o daemon segurou os processos com o app fechado. A sidebar mostra cada sessão com o estado agregado, a última frase do agente e o tempo:
   - `rti-platform / stacktax-pr-bronze` · Claude · "Done" · 7h · "Opened PR #412; 2 checks failing" (texto do agente).
   - `arizona / sandperch` · Codex · "Needs input" · "Which table, permits_2024 or permits_v2?"
   - `permits-oct` (sessão limpa) · 2 computers stopped.
2. A Inbox (⇧⌘I) abre a lista de eventos recentes e pedidos, agrupada como em 03 §9.1. Clicar num evento leva ao pane certo com o rim flash (M-309).
3. Se o Mac reiniciou, cada pane volta com o último scrollback esmaecido e "Resume". "Resume Agents…" no menu da sessão abre o overlay "Resume interrupted agents?" com a lista (CLI, modelo, última mensagem), checkboxes e o botão "Resume 6". Nada retoma sozinho.
4. O card de cada sessão tem a nota de status na linha 3 ("Reproduced the bug; testing fix"), que o usuário edita por "Edit Note…" ou duplo clique na linha da nota, e o agente atualiza por MCP.
5. A aba "Conversations" do painel direito (⇧⌘H) lista as conversas recentes do projeto (Claude e Codex), com "Resume in New Tab", "Copy Resume Command" e "Copy Conversation ID".
6. (v1.1) "Since you were away" na Inbox resume eventos de agente, PR e checks, computadores e uso do proxy desde a última abertura, com "Mark All as Read".

### Critérios de aceite

> **AC-201** · v1 · `XCUI` + `F-CLI` · R2.1
> **Dado** um terminal Claude cujo stub disparou `Stop` com uma última mensagem de 300 caracteres · **Quando** a sidebar renderiza · **Então** a linha do agente mostra a mensagem truncada em uma linha, com o tempo relativo ("7h"), e o hover mostra o texto completo.

> **AC-202** · v1 · `CLI` · R2.1, T10
> **Dado** Claude 2.1.302 e Codex 0.160.0 reais lançados pelo app · **Quando** cada um termina um turno · **Então** a última mensagem chega ao app pelos hooks por lançamento (Claude: `Stop`, ou a última entrada do `transcript_path` se o campo não existir; Codex: `Stop`) em até 2 s.

> **AC-203** · v1 · `UNIT` + `CLI` · R2.2, audit/05 P0.12
> **Dado** qualquer terminal Claude criado pelo app · **Quando** o processo nasce · **Então** o argv contém `--session-id <uuid>` gerado pelo app e já gravado no banco antes do spawn; **e dado** um terminal Codex, o ID da conversa é capturado do hook `SessionStart` ou do rollout correspondente ao cwd em até 10 s do primeiro turno.

> **AC-204** · v1 · `XCUI` · R2.3 (simples), audit/04 §5.4
> **Dado** eventos de "Done", "Needs input" e um pedido de ajuda em sessões diferentes · **Quando** o usuário abre a Inbox (⇧⌘I) · **Então** a lista agrupa como em 03 §9.1, pedidos e "Needs input" aparecem primeiro, e clicar num item seleciona a sessão, foca o pane do agente e dispara o rim flash (M-309).

> **AC-205** · v1 · `XCUI` + `CLI` · audit/05 (a) P0 "continue last", audit/07 #49
> **Dado** conversas Claude e Codex anteriores no cwd do projeto · **Quando** o usuário abre a aba "Conversations" · **Então** a lista mostra provider, título ou primeira mensagem, data e "Open in another terminal" quando a conversa está ativa em outro processo; "Resume in New Tab" abre um terminal com `--resume <id>` (Claude) ou `resume <id>` (Codex) e as flags do perfil, "Copy Resume Command" e "Copy Conversation ID" copiam o texto certo, e nada do transcript vai para o banco.

> **AC-206** · v1 · `E2E` · R2.5, PP-2
> **Dado** sessões com 6 agentes vivos e um reboot simulado (daemon morto com `kill -9` e sessões descartadas) · **Quando** o app abre · **Então** cada pane mostra o último scrollback esmaecido, o estado "Interrupted" e o botão "Resume", e nenhum processo de agente existe até o usuário clicar.

> **AC-207** · v1 · `XCUI` · R2.5
> **Dado** a situação da AC-206 · **Quando** o usuário escolhe "Resume Agents…" · **Então** o overlay "Resume interrupted agents?" lista CLI, modelo e última mensagem de cada um, todos marcados; desmarcar dois e clicar "Resume 4" relança só quatro.

> **AC-208** · v1 · `XCUI` + `CLI` · R2.4
> **Dado** uma sessão · **Quando** o usuário edita a nota ("Edit Note…" ou duplo clique na linha da nota) ou o agente chama `session_set_status("Reproduced the bug; testing fix")` · **Então** a linha 3 do card mostra o texto, com o autor e o tempo no hover; texto vazio remove a nota.

> **AC-209** · v1 · `E2E` + `F-CLI` · R2.1, audit/05 P0.6
> **Dado** um agente que termina o turno com o app fechado · **Quando** o app abre · **Então** o agente aparece "Done" e não lido, com a última mensagem daquele turno; nenhum evento de hook emitido com o app fechado se perde (mecanismo em 06/08).

> **AC-210** · v1.1 · `XCUI` · R2.3
> **Dado** 14 h fora com turnos concluídos, um PR mergeado, um check falhando e uso de proxy informado pelo provedor · **Quando** o usuário abre "Since you were away" · **Então** os eventos aparecem agrupados por sessão com tipo e hora, e "Mark All as Read" zera os não lidos.

---

## J3 · Nova sessão num repositório, com worktree nova e agente já rodando

**Versão**: v1 (cópia de ignorados e script de setup: v1.1).
**Pré-condições**: projeto `rti-platform` importado, perfil padrão Claude com skip permissions.

### Roteiro-alvo

1. ⌘N abre o composer como overlay (não sheet). O foco vai para o campo "Prompt"; o terminal de trás não recebe teclas.
2. "Project": o projeto da sessão atual, com type-ahead e "Add a new project" no fim. Sem projeto, a sessão vira sessão limpa (seção "Sessions").
3. "Where" (por contexto, 03 §6.1): com projeto, "New Worktree" (padrão), "Existing Worktree" ou "Main Checkout"; sem projeto, "New Folder" ou "Choose Folder…".
4. "Create from": `origin/main` por padrão. Aceita branch, `#123` ou URL de PR/issue. Se o branch já existe, aparece "Reuse existing branch".
5. "Agent": "Claude Code" (padrão), "Codex", "OpenCode", "Blank Terminal". "Profile": "Claude · Skip permissions" (padrão), filtrado pelo agente.
6. "Prompt": várias linhas. Some com "Blank Terminal".
7. "Advanced" (fechado): "Session name", "Branch name". Se ficarem vazios, saem do prompt (título "Fix ArcGIS pagination", branch `gabrielgreco1/fix-arcgis-pagination`). Colisão vira sufixo `-2`.
8. ⌘↵. O overlay fecha na hora (M-102, chip M-501). A sidebar mostra a linha pendente com a fase ("Fetching origin…", "Creating worktree…", M-204). `git fetch` e `git worktree add` rodam em segundo plano.
9. Uma tab abre com o Claude rodando no cwd da worktree, com `--session-id <uuid>`, as flags do perfil, as injeções por lançamento de 06 §2.8 e o prompt como último argumento. A ignição (M-503) só aparece se o primeiro byte passar de 300 ms (M-506).
10. Se algo falha (branch existe, fetch sem rede), o erro aparece no card pendente com "Try Again" e "Use Existing Branch" ou "Create Without Fetching". Nada parcial fica no disco.
11. Numa sessão existente, ⌥⌘N abre o Quick Launch (agente, perfil, prompt opcional) e Enter já abre a tab rodando. ⌥⌘T abre o agente padrão direto; ⌘T abre um shell (03 §21).
12. (v1.1) Na worktree nova, o app copia os arquivos de `.worktreeinclude` (ou `.env*`, se o projeto pedir) e roda o script de setup numa tab "Setup", esperando ou não conforme a política do projeto.

### Critérios de aceite

> **AC-301** · v1 · `XCUI` · audit/07 #23, T5
> **Dado** um terminal com foco · **Quando** o usuário aperta ⌘N e digita "abc" · **Então** "abc" aparece no campo "Prompt" do composer e o terminal não recebe nenhum byte (verificado por `ctl terminal screen`); Esc fecha e devolve o foco ao mesmo pane.

> **AC-302** · v1 · `XCUI` · audit/04 §5.2
> **Dado** a sessão atual em `rti-platform` · **Quando** o composer abre · **Então** "Project" vem preenchido com `rti-platform`, "Where" com "New Worktree", "Create from" com o base ref detectado, "Agent" com o agente padrão e "Profile" com o perfil padrão desse agente.

> **AC-303** · v1 · `UNIT` + `XCUI` · R3.2
> **Dado** o prompt "Fix ArcGIS pagination when offset > 2000" e nome vazio · **Quando** o usuário cria · **Então** a sessão se chama "Fix ArcGIS pagination", o branch é `gabrielgreco1/fix-arcgis-pagination` e a pasta fica em `<worktreeRoot>/rti-platform/fix-arcgis-pagination`; se já existir, o sufixo vira `-2`.

> **AC-304** · v1 · `UNIT` + `E2E` · R3.2
> **Dado** um projeto importado do Orca · **Quando** se cria uma worktree · **Então** ela nasce sob `~/orca/workspaces/<repo>/` (padrão de transição, P15), e trocar "Worktree folder" em Settings › General muda o destino das próximas; o `worktreeRoot` do projeto (01 §5.2), quando importado, tem precedência.

> **AC-305** · v1 · `XCUI` · R3.3, P10, P11
> **Dado** o composer · **Quando** o usuário deixa "Project" sem projeto e escolhe "New Folder" em "Where" · **Então** a sessão é criada como sessão limpa em `~/AgentBox/sessions/<nome>` (sem projeto, na seção "Sessions"), sem campos de Git; "Choose Folder…" e "Existing Worktree" usam o caminho escolhido sem copiar nada.

> **AC-306** · v1 · `XCUI` + `E2E` · RT.3, PP-8
> **Dado** um fetch que leva 5 s · **Quando** o usuário aperta ⌘↵ · **Então** o overlay fecha em menos de 100 ms, a linha pendente aparece na sidebar com a fase atual e, no fim, a sessão fica ativa com a tab do agente.

> **AC-307** · v1 · `UNIT` + `E2E` + `F-CLI` · R3.1, P9, T11
> **Dado** a criação com o prompt "hello" e o perfil padrão · **Quando** o processo nasce · **Então** o argv é igual ao golden file do adapter Claude para essa fatia (06 §2): começa com `claude`, contém `--session-id <uuid>` (gravado no banco antes do spawn) e `--dangerously-skip-permissions`, contém só as injeções por lançamento listadas em 06 §2.8 para a fatia (`--settings`, `--mcp-config`, `--plugin-dir`, `--agents`; nenhuma na Fatia 1), e termina com `hello` como um único argumento; nenhum argumento fora do golden; o cwd é a worktree; o daemon registra zero bytes escritos no PTY pelo app antes do primeiro input humano.

> **AC-308** · v1 · `UNIT` · R3.1
> **Dado** prompts de 16 KiB, de 16 KiB + 1 byte, de 40 KB e um prompt curto que começa com `-` · **Quando** o lançamento é montado · **Então** o de 16 KiB vai no argv; os outros três vão para `run/launch/<runID>/prompt.md` (`0600`) e o argv referencia o arquivo, sem truncar (limiar único de 01 §5.7).

> **AC-309** · v1 · `UNIT` + `CLI` · R3.1
> **Dado** os perfis Codex e OpenCode · **Quando** a sessão é criada com prompt · **Então** o argv é `codex [flags do perfil] "<prompt>"` e `opencode [flags] --prompt "<prompt>"`, ambos rodando já com o prompt.

> **AC-310** · v1 · `XCUI` (stub com atraso) · P8, M-503, M-506
> **Dado** um CLI que imprime o primeiro byte em 150 ms · **Quando** a tab abre · **Então** não aparece placeholder de ignição (M-506); **dado** 2 s de atraso, o placeholder M-503 aparece com as etapas reais e some no primeiro byte (M-504).

> **AC-311** · v1 · `E2E` · RT.3, audit/01 F3
> **Dado** um branch que já existe · **Quando** o usuário cria · **Então** o card pendente mostra "Branch already exists" com "Use Existing Branch" e "Try Again"; **dado** fetch sem rede, mostra "Couldn't fetch origin" com "Try Again" e "Create Without Fetching"; em ambos os casos nenhuma pasta ou worktree parcial fica no disco.

> **AC-312** · v1 · `E2E` · audit/05 P0.4, audit/09 §5.6
> **Dado** `$SHELL` do usuário com `PATH` do nvm, `SSH_AUTH_SOCK` e uma variável `FOO=bar` no profile · **Quando** um agente é lançado · **Então** o env do processo contém essas variáveis, capturadas uma vez do shell de login pela ordem de 06 §1.7 (`-l -i -c` em PTY oculto com marcador e timeout de 5 s, depois `-l -c` com 3 s, depois env do launchd), sem as variáveis internas do app e sem nenhuma `ORCA_*`.

> **AC-313** · v1 · `XCUI` · audit/05 P0.2, PP-4
> **Dado** uma sessão ativa · **Quando** o usuário aperta ⌥⌘N, escolhe "New Codex Tab" no Quick Launch e Enter · **Então** uma tab nova abre com o Codex rodando no cwd da sessão; ⌥⌘T abre o agente padrão sem seletor; ⌘T abre um shell na pasta da sessão.

> **AC-314** · v1 · `XCUI` · audit/01 D2, PP-1
> **Dado** o Codex deslogado ou ausente · **Quando** o usuário escolhe Codex no composer · **Então** o item mostra "Not logged in" com "Log In" (ou "Not installed", desabilitado com o motivo) antes de criar, e criar mesmo assim abre a tab com o erro real do CLI.

> **AC-315** · v1 · `XCUI` · audit/05 P0.1
> **Dado** projetos com sessões e agentes · **Quando** a sidebar renderiza · **Então** a hierarquia é Project → card da sessão → linhas de agente (e linhas filhas de subagente), com seleção e expansão como ações separadas (chevron expande, rótulo seleciona).

> **AC-316** · v1 · `XCUI` · audit/05 P0.3
> **Dado** o campo "Profile" · **Quando** o usuário escolhe um perfil · **Então** a linha de resumo mostra modelo, modo de permissão e flags extras, e o indicador "Skip permissions" (`ShieldOff`, tooltip `Skip permissions (<flag exata>)`) aparece na tab e no header do pane enquanto o processo roda.

> **AC-317** · v1.1 · `E2E` · R3.4
> **Dado** um repositório com `.worktreeinclude` listando `.env` · **Quando** a worktree é criada · **Então** `.env` é copiado da worktree primária para a nova antes do agente iniciar; sem `.worktreeinclude`, o projeto com "Copy .env files" ligado copia `.env*`.

> **AC-318** · v1.1 · `E2E` · R3.5
> **Dado** `orca.yaml` com `scripts.setup: pnpm install` e política "Wait" · **Quando** a sessão é criada · **Então** uma tab "Setup" mostra a saída, e o agente só inicia quando o script termina com código 0; com código ≠ 0, o card mostra "Setup failed" com "Start agent anyway" e "Show output".

---

## J4 · "Spawn 2 subagents for Phoenix and Austin" (modo leve)

A jornada que justifica o app. O Gabriel já fez isso com o CLI antigo em lotes de 15 cidades.

**Versão**: v1 (modo leve). O modo isolado está na J4b, v1.1.
**Pré-condições**: Docker rodando, imagem pronta, um proxy configurado em Settings e escolhido para a sessão (opcional, P13), skill global `agentbox` tratada com "Block in Agent Box" ou "Disable Globally…".

### Roteiro-alvo

1. **Sessão** `permits-oct` (sessão limpa, J11). O Claude pai foi lançado pelo Agent Box, então já tem o MCP do app e a skill de orquestração, injetados por lançamento.
2. O Gabriel digita: "spawn 2 subagents for Phoenix and Austin; map permit systems (zoning, building), endpoints and coverage; output result.json".
3. O pai monta o brief de cada filho (tarefa, o que já se sabe, spec de saída), seguindo o template da skill de orquestração.
4. O pai chama `boxes_reserve(names: ["phoenix-az", "austin-tx"], display: "headless")`. O app checa capacidade, cria os dois computadores em paralelo com o proxy da sessão e responde na hora com o estado de cada um, sem esperar o Chromium. Na sidebar, sob o terminal pai, nascem duas linhas filhas com o glifo de provisionamento (M-601).
5. O pai dispara dois subagentes nativos em background, cada um com o brief e o rótulo do computador. Na primeira chamada, o filho reivindica o computador pelo rótulo (`box_claim(name: "phoenix-az")`). A linha da sidebar passa a mostrar o filho e o computador juntos.
6. **Ver ao vivo**: a aba "Computers" do painel direito (⇧⌘C) mostra duas miniaturas: URL atual, última nota do diário e uso do proxy quando disponível. Hover amplia (M-612). Clique abre o viewer como pane ao lado dos terminais, a ≥ 20 fps (07 CS-401).
7. **Captcha em Phoenix**: o filho chama `help_request(kind: "captcha", reason: "hCaptcha on Accela search")`. A chamada volta na hora com um `request_id`, e o filho passa a chamar `help_wait`. Notificação: título "permits-oct — phoenix-az needs you", corpo "Captcha on aca-prod.accela.com". O clique abre o viewer com "Take Over" em destaque.
8. Ele assume (M-606). Phoenix fica pausado; Austin segue. Um selo mostra "Keyboard captured · ⌃⌥ to release". Ele resolve o captcha e clica "Hand Back" (⇧⌘R), com a nota "Solved, session logged in". O filho recebe a URL atual, as abas e a nota, e continua.
9. **Evidência**: cada linha filha abre o detalhe com as abas "Activity", "Network" (request log com filtro XHR e erros, corpo completo, "Copy as cURL"), "Journal" (PLAN, DOING, FOUND, BLOCKED), "Commands", "Files" (o `work/`), "Timeline" e "Result" (07 CS-320).
10. **Resultado volta ao pai**: o subagente nativo devolve a resposta final ao pai, como o Claude já faz. O run folder `~/AgentBox/runs/permits-oct/phoenix-az/` tem `work/result.json` e `logs/`, atualizados ao vivo. O pai chama `box_collect("phoenix-az")` e recebe timeline e resultado. Cada afirmação sem ID de request aparece como "Not verified" na aba "Result".
11. **Fim**: os computadores param sozinhos quando o filho termina, e os perfis ficam. O card mostra a duração ("18 min") e, quando o provedor do proxy informa, o uso por computador. "Archive Computers" remove containers e mantém run folders e perfis.

### Falhas e o que aparece

| Situação | UI e resposta ao agente |
|---|---|
| Memória da VM insuficiente | Linha filha "Queued" (longo: "Waiting for memory · 3 of 15 queued", M-602); a ferramenta devolve `queued` com posição |
| Docker parado | AttentionItem "Docker isn't running · Start Docker"; a ferramenta devolve erro `runtime_unavailable` com a ação pedida ao humano |
| Rótulo já reivindicado por outro filho | A ferramenta devolve `already_claimed`, com o dono atual no payload; nada muda na UI |
| Proxy recusa ou falha (credencial inválida, crédito do provedor esgotado) | O request aparece em "Network" com o status real do proxy, e o agente recebe esse status; o app não corta nada nem cria teto (P13) |
| Computador morre (OOM) | Linha "Failed · Out of memory" com "Restart Computer"; o filho recebe erro e o pai vê o estado em `box_status` |
| Filho termina sem soltar o computador | O app para o computador no `SubagentStop`; na próxima abertura, sobras viram "Orphaned" com "Clean Up" |

### Critérios de aceite

> **AC-401** · v1 · `CLI` + `E2E` · R4.1, audit/05 P0.8, T10
> **Dado** um terminal Claude comum criado pelo composer (sem Biblioteca) · **Quando** o usuário roda `/mcp` · **Então** o servidor `agentbox` aparece com as ferramentas de computador, a skill de orquestração aparece entre as skills da sessão, e nenhum arquivo global foi alterado (AC-112).

> **AC-402** · v1 · `CLI` com `F-HOME` · R1.6, R4.1
> **Dado** a skill global `agentbox` tratada com "Block in Agent Box" · **Quando** o usuário escreve "spawn 2 subagents for Phoenix and Austin" · **Então** o transcript mostra chamadas às ferramentas do Agent Box (`boxes_reserve`, `box_claim`) e nenhuma execução de `bin/agentbox`.

> **AC-403** · v1 · `E2E` · R4.2, R4.7
> **Dado** dois rótulos pedidos por `boxes_reserve` · **Quando** a chamada é feita · **Então** ela retorna em até 2 s com o estado de cada computador (`provisioning` ou `queued`), os dois containers são criados em paralelo, e as linhas filhas aparecem na sidebar sob o pai com o glifo de provisionamento.

> **AC-404** · v1 · `E2E` + `CLI` · R4.2, audit/08 cap.4
> **Dado** dois filhos nativos do mesmo tipo rodando em paralelo · **Quando** cada um chama `box_claim` com o próprio rótulo · **Então** cada computador fica com o dono certo (identidade vinda do processo MCP por filho ou do `agent_id` do hook), a sidebar mostra filho e computador juntos, e um terceiro filho que pede um rótulo já reivindicado recebe `already_claimed` com o dono atual.

> **AC-405** · v1 · `E2E` · R4.7, audit/08 N2
> **Dado** uma VM Docker com memória para 4 computadores headless · **Quando** o pai reserva 15 · **Então** 4 provisionam, 11 ficam "Queued" com posição visível na aba "Computers" e na resposta da ferramenta, a fila anda em ordem FIFO conforme computadores param, e nenhuma chamada falha por concorrência.

> **AC-406** · v1 · `E2E` + `PERF` · audit/08 N2, R6.3
> **Dado** uma VM Docker com 28 GiB (≥ a recomendação de 07 CS-132 para 15 + 2) e os perfis de recurso padrão de 07 · **Quando** um lote reserva 15 computadores headless e 2 desktop · **Então** todos ficam "Ready" em até 5 min sem nenhum ficar "Queued", o app continua respondendo (nenhum hitch acima de 100 ms no thread principal durante o lote) e o pai consegue chamar ferramentas em todos. Com uma VM abaixo da recomendação, o critério é o de AC-405 (fila, sem falha).

> **AC-407** · v1 · `XCUI` (runtime falso) + `MANUAL` · R4.8
> **Dado** uma sessão com dois computadores ativos · **Quando** a aba "Computers" do painel direito renderiza · **Então** cada miniatura mostra URL atual, última nota do diário e uso do proxy (ou nada, se o provedor não informa), ordenadas com "needs you" primeiro; hover amplia (M-612) e clique abre o viewer como pane ao lado dos terminais.

> **AC-408** · v1 · `E2E` + `MANUAL` · audit/05 P0.9, T8
> **Dado** um computador desktop com o viewer aberto · **Quando** a página anima continuamente · **Então** o viewer (noVNC) mantém pelo menos 20 fps medidos, com p95 de input < 100 ms (07 CS-401), abrir ou fechar o viewer não muda o modo do computador, e fechar o viewer não para o computador.

> **AC-409** · v1 · `E2E` · R4.3
> **Dado** um filho com computador · **Quando** ele chama `help_request(kind: "captcha", reason: "hCaptcha on Accela search")` · **Então** a chamada retorna em menos de 1 s com `request_id`; `help_wait(request_id)` faz long-poll com progresso, pode ser repetida sem criar outro pedido, e nenhuma chamada MCP fica bloqueada além de 50 s (07 §3.1).

> **AC-410** · v1 · `E2E` + `MANUAL` · R4.3, audit/07 #38
> **Dado** o pedido da AC-409 com o app sem foco · **Quando** o pedido nasce · **Então** em até 2 s aparece a notificação do macOS com título "permits-oct — phoenix-az needs you" e corpo "Captcha on aca-prod.accela.com" (só nome, tipo e host, 07 CS-433), o badge do Dock incrementa, e clicar na notificação abre o viewer daquele computador com "Take Over" em destaque.

> **AC-411** · v1 · `E2E` com `F-SITE` · audit/08 cap.27, audit/01 O5
> **Dado** Phoenix e Austin trabalhando · **Quando** o usuário clica "Take Over" em Phoenix · **Então** as escritas do agente em Phoenix são recusadas com `human_in_control` enquanto durar o takeover, e as chamadas de Austin no mesmo intervalo continuam passando.

> **AC-412** · v1 · `E2E` com `F-SITE` · R4.4
> **Dado** um computador "headless" com uma página que guardou um marcador no DOM e um cookie · **Quando** o usuário assume o controle · **Então** a tela mostra a mesma página, sem recarregar (marcador do DOM presente), com os mesmos cookies; nenhum navegador é reiniciado.

> **AC-413** · v1 · `E2E` · R4.9, audit/01 O3
> **Dado** o usuário no controle · **Quando** ele clica "Hand Back" com a nota "Solved, session logged in" · **Então** `help_wait` retorna com `resolved`, URL atual, lista de abas e a nota, e o agente volta a ter escrita.

> **AC-414** · v1 · `XCUI` + `MANUAL` · audit/07 #40
> **Dado** o viewer com o teclado capturado · **Quando** o usuário aperta ⌘W, ⌘Q, ⌘⎋ e ⌃⌥ · **Então** o selo "Keyboard captured · ⌃⌥ to release" está visível, ⌘⎋ e ⌃⌥ soltam o teclado, ⌘Q sempre chega ao app e nenhuma combinação reservada vai para o computador.

> **AC-415** · v1 · `E2E` com `F-SITE` · audit/08 cap.12–15, T12
> **Dado** um filho com computador · **Quando** ele usa `exec` com `curl`, `python3 -c 'import curl_cffi'` e `jq`, faz um POST com headers e cookies por `http_request`, e usa `browser_click`, `browser_type` e `browser_eval` por seletor · **Então** tudo funciona dentro do container, cada comando aparece na aba "Commands" com hora, exit, duração e saída, e nada roda no Mac.

> **AC-416** · v1 · `E2E` com `F-SITE` · audit/08 cap.19, audit/05 P0.10
> **Dado** requests feitos pelo navegador, por `curl` e por Python no computador · **Quando** o usuário abre "Network" · **Então** todos aparecem com fonte, método, URL, status e corpo completo até o limite de 07; os filtros "XHR" e "Errors" funcionam; "Copy as cURL" gera um comando que reproduz o request; e o agente consulta o mesmo log por `reqlog_query`.

> **AC-417** · v1 · `E2E` · audit/08 N9, T9, P13
> **Dado** um computador com um proxy configurado (credencial de usuário e senha) · **Quando** o agente roda `env`, `cat /proc/*/environ`, procura arquivos com o nome do provedor, "proxy" ou "usage" e tenta escrever nos logs · **Então** a credencial do proxy não aparece, os logs de request e de uso não são graváveis por ele, e apagar o que estiver em `work/` não muda nenhum registro.

> **AC-418** · v1 · `E2E` · P13, T9, T12
> **Dado** dois proxies cadastrados em Settings › Computers › Proxies (um HTTP com credencial e geo `us`, outro SOCKS5) e um computador sem proxy (`None`) · **Quando** o usuário escolhe o HTTP para a sessão (`Computer proxy` no composer) e o SOCKS5 para `austin-tx` (`Proxy ▸` no viewer) · **Então** os requests de `phoenix-az` saem pelo HTTP e os de `austin-tx` pelo SOCKS5 (conferido no servidor de `F-SITE`), o computador sem proxy sai direto pelo egress, "Network" mostra qual proxy cada request usou, a coluna `Proxy` da página Computers mostra nome e uso, o uso aparece só quando o provedor o informa (senão "Usage unavailable"), e em nenhum momento existe teto, aviso de 80% ou corte automático.

> **AC-419** · v1 · `E2E` · audit/09 N8, T9
> **Dado** um computador · **Quando** o agente navega ou faz request para `host.docker.internal`, `192.168.1.1`, `169.254.169.254` ou a porta de outro computador · **Então** o egress bloqueia, o request aparece em "Network" como "Blocked by policy", e um site público funciona.

> **AC-420** · v1 · `E2E` · R4.5, audit/08 N11
> **Dado** um filho escrevendo `result.json` e arquivos em `work/` · **Quando** o run está em andamento · **Então** `~/AgentBox/runs/permits-oct/phoenix-az/work/` mostra os arquivos ao vivo no Finder, e "Open Run Folder" na linha abre o run folder.

> **AC-421** · v1 · `E2E` · R4.5, audit/08 N8
> **Dado** um `result.json` com 5 afirmações, 3 citando IDs de request existentes, 1 citando um ID inexistente e 1 sem citação · **Quando** o pai chama `box_collect("phoenix-az")` e o usuário abre "Result" · **Então** a ferramenta devolve timeline e resultado, e a UI marca 3 como "Verified" (com link para o request), 1 como "Cited request not found" e 1 como "Not verified".

> **AC-422** · v1 · `E2E` · audit/08 cap.43, audit/01 SC28
> **Dado** um filho que termina (`SubagentStop`) · **Quando** o evento chega · **Então** o computador dele para, o perfil do navegador e o run folder ficam, e o card da sessão mostra a duração total e, quando o provedor informa, o uso do proxy por computador.

> **AC-423** · v1 · `E2E` · R4.5, audit/08 N27
> **Dado** dois computadores parados numa sessão · **Quando** o usuário clica "Archive Computers" e confirma · **Então** containers e volumes de trabalho saem (conferido por `docker ps -a` e `docker volume ls` com o label `agentbox.owner=<installId>`), e run folders e perfis ficam.

> **AC-424** · v1 · `E2E` · audit/09 N1, N18, T9
> **Dado** um computador ativo · **Quando** se roda `docker inspect` no container e se lê o env de Xvfb, Openbox e xdotool · **Então** o token do computador não aparece em `Config.Env` nem em nenhum desses processos; ele está só no arquivo montado só leitura.

> **AC-425** · v1 · `E2E` · R6.1 (ver AC-607)
> **Dado** o pai que terminou o turno com os dois filhos rodando · **Quando** o `Stop` do pai chega · **Então** o pai fica "Waiting on subagents", e só vira "Done" quando o último filho termina.

> **AC-426** · v1.1 · `E2E` + `F-CLI` · R4.10
> **Dado** um filho sem chamada de ferramenta nem nota de diário há 10 minutos (limite configurável) · **Quando** o limite passa · **Então** a linha mostra "Stalled?" e nasce um item na Inbox; qualquer atividade nova limpa o estado.

> **AC-427** · v1.1 · `E2E` · R4.11
> **Dado** um filho no modo leve · **Quando** o usuário escolhe "Ask Parent to Steer…" e escreve a orientação · **Então** o app cola no prompt do pai "Tell phoenix-az: <texto>" por ação explícita, sem Enter (R5.1); no modo isolado, digitar na tab do filho entrega direto.

> **AC-428** · v1 · `UNIT` + `CLI` com `F-SITE` · PP-15, audit/01 R9
> **Dado** a skill de orquestração e o template de brief entregues por lançamento · **Quando** se lê o texto injetado e um filho encontra em `F-SITE` uma página com "Buy now", um formulário de contato e "Change account settings" · **Então** o texto contém as regras do worker (preferir APIs e dados oficiais; nunca comprar, mandar mensagem, criar conta ou alterar conta), e o filho não clica nenhum desses controles e abre `help_request(kind: "choice")` em vez disso.

> **AC-429** · v1 · `E2E` + `XCUI` · audit/08 N21, 07 CS-323/324
> **Dado** um lote (`Batch`) com 5 filhos, 4 concluídos e 1 falho · **Quando** o último termina · **Então** nasce um único AttentionItem `batchDone` e uma notificação com resumo ("5 subagents finished · 1 failed · 18 min", mais uso do proxy quando informado); clicar abre o consolidado do lote; nenhuma notificação por filho além das de falha.

---

## J4b · Mesma jornada no modo isolado

**Versão**: v1.1 (P5, P6). O roteiro é o da J4, com estas diferenças:

1. O pai chama `agent_spawn({mode: "isolated", harness: "claude", brief, computer: "headless", label: "phoenix-az"})`, ou o usuário escolhe "In Container" em "Subagent computers" no composer (03 §6.2). O app cria container, workspace e CLI juntos e devolve `child_id`.
2. Cada filho aparece como **tab de terminal real** pendurada no pai, com o selo de container (audit/07 #42). Enquanto o container sobe, a tab mostra as fases reais: "Pulling image 42%", "Creating container", "Mounting workspace", "Signing in", com "Cancel".
3. O CLI já entra logado, sem login manual (P7): o token de longa duração do `claude setup-token` chega por arquivo só leitura; nada de refresh token do Mac nem token do `gh`.
4. Git dentro do container passa pelo broker do app, que só atende o remote da sessão.
5. O humano pode digitar na tab do filho, inclusive aprovar permissões.
6. O pai espera com `agent_wait`; o resultado volta em `agent_wait` (`finished[].result`) e em `box_collect`. Para orientar um filho que ele criou, o pai usa `agent_message`, que entrega a mensagem com Enter e a registra na timeline do filho (P12).
7. Fechar o app não mata o filho: o CLI roda sob `dtach` no container e o app reanexa ao abrir.

> **AC-451** · v1.1 · `XCUI` · audit/07 #42, P5
> **Dado** o composer ou o spawn pela UI · **Quando** o usuário escolhe o modo · **Então** "Subagent computers" oferece "Off", "On This Mac" e "In Container", o modo efetivo aparece no resumo antes de criar, terminais isolados mostram o selo de container na tab e na sidebar (tooltip `Runs in a container`), e no modo leve o selo fica no computador. Na v1 a opção "In Container" não aparece.

> **AC-452** · v1.1 · `E2E` · audit/07 #43
> **Dado** um spawn isolado com a imagem do agente ausente · **Quando** a tab nasce · **Então** ela mostra as fases reais com progresso e "Cancel" ("Pulling image 42%"…); se o container parar depois, o pane mostra "Container stopped" com "Restart Container", diferente de "Exited".

> **AC-453** · v1.1 · `E2E` + `CLI` · P7, audit/08 §1
> **Dado** o token de `claude setup-token` guardado no Vault do app (chave no Keychain, 01 §5.13) · **Quando** um filho isolado nasce · **Então** `claude auth status --json` dentro do container mostra logado sem nenhuma ação humana, e o token não aparece em argv, `docker inspect`, imagem nem env de outros processos.

> **AC-454** · v1.1 · `E2E` (8 h) · audit/08 §1.7
> **Dado** 15 filhos Claude isolados e 3 Codex isolados por 8 h, com renovação forçada do Codex e o Mac usando os dois CLIs ao mesmo tempo · **Quando** o teste termina · **Então** nenhum logout aconteceu no Mac nem nos containers.

> **AC-455** · v1.1 · `E2E` · audit/08 §1.5, P7
> **Dado** um filho isolado com acesso ao repositório da sessão · **Quando** ele faz `git push` para o remote da sessão e depois para outro repositório · **Então** o primeiro passa pelo broker e fica registrado, o segundo é negado com registro, e `env`, `/proc/*/environ` e uma busca por "credential" no container não mostram o token do `gh`.

> **AC-456** · v1.1 · `E2E` · audit/08 N1, N16
> **Dado** um pai com MCP do app · **Quando** ele chama `agent_spawn` e depois `agent_wait` · **Então** o filho aparece como tab pendurada no pai, o humano consegue digitar nela, pedidos de permissão do filho entram na fila com a origem, e `agent_wait` devolve em `finished[].result` o `result.json` com evidências (o mesmo que `box_collect`).

> **AC-457** · v1.1 · `E2E` · audit/08 N13, audit/09 N16
> **Dado** dois filhos isolados de código no mesmo projeto · **Quando** cada um trabalha · **Então** cada um tem a própria worktree montada no mesmo caminho absoluto do host (git funciona dentro do container), nunca dois filhos na mesma worktree, e o diff de cada um aparece no app antes de mesclar.

> **AC-458** · v1.1 · `E2E` · audit/08 N20
> **Dado** um filho isolado trabalhando · **Quando** o app sai e reabre · **Então** a tab reanexa ao mesmo processo do CLI dentro do container (mesmo PID no container), com a saída produzida nesse intervalo.

> **AC-459** · v1.1 · `E2E` · R8.5, audit/08 cap.42
> **Dado** um filho isolado com conversa em andamento · **Quando** o container é recriado · **Então** "Resume" retoma a conversa, porque o estado do CLI vive no volume da box.

> **AC-460** · v1.1 · `XCUI` + `E2E` · audit/08 N12, N24
> **Dado** skills e agentes escolhidos para o filho · **Quando** o container nasce · **Então** eles estão montados só leitura, a skill `webscraping-expert` está carregada sem intake, e a tela do filho mostra "Loaded in this run" com cada item e a fonte.

> **AC-461** · v1.1 · `E2E` · audit/08 N14, C12
> **Dado** hooks HTTP do CLI no container apontando para o app · **Quando** o app está aberto · **Então** os estados chegam em até 2 s; **quando** o app está fechado, os eventos ficam enfileirados e são entregues ao reabrir, sem quebrar o filho.

> **AC-462** · v1.1 · `E2E` · audit/09 §2.7
> **Dado** um filho isolado · **Quando** ele tenta ler o token do runtime, acessar `/var/run/docker.sock` ou listar `$HOME` do Mac · **Então** nada disso existe ou é legível no container (uid diferente, sem socket Docker, sem mount de `$HOME`).

> **AC-463** · v1.1 · `XCUI` · audit/08 §1.3
> **Dado** o setup-token a 30 dias de vencer · **Quando** o app abre · **Então** nasce o item "Claude token expires in 30 days" com "Generate New Token", que abre um terminal com `claude setup-token` e troca o token guardado ao fim.

> **AC-464** · v1.1 · `E2E` · P12, T11
> **Dado** um pai com um filho isolado que ele criou e um terminal de outra sessão · **Quando** o pai chama `agent_message` para o filho e depois para o outro terminal · **Então** a mensagem chega ao filho com Enter e aparece na "Timeline" do filho com origem e hora; a chamada para o terminal que não é filho dele é recusada (`not_your_child`) e nada é escrito nele; o log de origem de escrita do daemon (AC-505) registra a primeira como `parentMessage`.

---

## J5 · Revisar alterações, abrir PR e ver checks

**Versão**: v1 (chip de PR e checks, "Create PR", "Open in…", lista de alterações na aba Source Control); v1.1 (diff em linha na aba Source Control, "Send failures to agent", eventos de PR e checks).
**Pré-condições**: sessão de worktree com commits locais; `gh` logado.

### Roteiro-alvo

1. O card da sessão mostra branch, "↑3" e o ponto de alterações. Depois do push, aparece o chip "#412" com o estado dos checks.
2. "Open in…" (menu da sessão e header) leva ao editor configurado (Cursor, VS Code, Zed), ao Finder, a um terminal externo ou ao GitHub.
3. Na maioria das vezes ele pede ao agente: "commit and open the PR". O app só observa e atualiza o chip.
4. Quando prefere fazer pelo app: "Create PR" faz push (se preciso) e abre um overlay com título, corpo e base pré-preenchidos, que roda `gh pr create` ao confirmar.
5. ⇧⌘G abre a aba "Source Control" do painel direito: na v1, arquivos alterados contra o base ref, que abrem no editor; (v1.1) diff em linha, só leitura.
6. (v1.1) Checks falham: notificação "rti-platform · 2 checks failing on #412". "Send failures to agent" cola no prompt do agente os nomes dos checks e o trecho do log (`gh run view --log-failed`). Ele revisa e aperta Enter.

### Critérios de aceite

> **AC-501** · v1 · `E2E` com `F-REPO` · audit/05 (d), R5.4 (parte)
> **Dado** uma worktree com 3 commits locais e um arquivo alterado · **Quando** o card renderiza · **Então** mostra branch, "↑3" e o ponto de alterações; depois de um push e de um PR aberto fora do app, o chip "#<n>" aparece em até 60 s com a janela ativa.

> **AC-502** · v1 · `XCUI` · R5.2
> **Dado** uma sessão · **Quando** o usuário escolhe "Open in… › Cursor", "Finder", "Terminal" e "GitHub" · **Então** cada um abre o destino certo no diretório da sessão (GitHub só aparece quando há remote GitHub; o editor padrão é configurável em Settings).

> **AC-503** · v1 · `E2E` com `F-REPO` · audit/01 F6, PP-2
> **Dado** uma branch sem push · **Quando** o usuário clica "Create PR" · **Então** o overlay mostra título, corpo, base e "Draft" pré-preenchidos; nada é enviado até "Create"; ao confirmar, o app faz push e roda `gh pr create`, e o chip aparece com o número.

> **AC-504** · v1 · `E2E` · R5.4
> **Dado** 6 projetos com PRs abertos · **Quando** a janela está ativa por 10 min e depois em segundo plano por 10 min · **Então** o app faz no máximo uma consulta por repositório a cada 30–60 s em primeiro plano e a cada 5 min em segundo plano, usando ETag; num 403 de rate limit, o chip mantém o último estado com "Paused · rate limit" no hover.

> **AC-505** · v1 · `E2E` + `XCUI` · R5.1, T11, P12
> **Dado** um texto preparado pelo app e um agente com prompt vazio · **Quando** o usuário clica "Paste into Claude" · **Então** o texto chega ao prompt por bracketed paste, sem Enter, e o agente não executa nada até o usuário apertar Enter; nenhum outro caminho do app escreve no PTY (auditoria: o daemon registra a origem de cada escrita, e todas vêm de input humano, de uma ação "Paste into…" ou, na v1.1, de `agent_message` do pai para um filho que ele criou, P12).

> **AC-506** · v1 · `E2E` · audit/08 C2
> **Dado** um repositório com remote HTTPS e `credential.helper = !gh auth git-credential` · **Quando** o agente roda `git push` num terminal do app · **Então** o push funciona sem pedir credencial.

> **AC-507** · v1.1 · `XCUI` · R5.3
> **Dado** uma worktree com alterações · **Quando** o usuário aperta ⇧⌘G · **Então** a aba "Source Control" lista os arquivos alterados contra o base ref com diff em linha, só leitura, e "Open in…" por arquivo.

> **AC-508** · v1.1 · `E2E` · R5.4, R5.5
> **Dado** um PR com 2 checks falhando · **Quando** o estado muda · **Então** nasce a notificação "2 checks failing on #412"; "Send failures to agent" cola no agente da sessão os nomes, os links e o trecho de `gh run view --log-failed`, sem Enter.

---

## J6 · Dez ou mais sessões em paralelo

**Versão**: v1 (prioridade por tipo, menu bar com ações, dormir sessão: v1.1).
**Pré-condições**: 12 agentes trabalhando em 10 sessões, 6 computadores ativos.

### Roteiro-alvo

1. A sidebar é densa. Cada card mostra o pior estado da sessão (§6.3 do 01). Sessões não lidas ficam em negrito. As linhas de agente mostram a última frase e o tempo.
2. Ele está focado em `rti-platform`. Uma notificação do sistema avisa que `arizona / sandperch` fez uma pergunta. Se ele já estivesse olhando aquele pane, a notificação não apareceria.
3. ⇧⌘A ("Next Needing Attention") percorre a fila em ordem de espera, com rim flash no pane (M-309). ⌘J lista tudo com "Needs input" no topo. ⌘1…9 trocam de sessão; ⌥⌘← volta à sessão anterior (histórico); ⌘] e ⌘[ andam entre panes.
4. O Dock mostra o número de pendências de prioridade 1–2 (01 §5.12). O item da barra de menus mostra quantos agentes estão trabalhando e quantos precisam dele.
5. Pedido de ajuda de computador tem prioridade sobre fim de turno. (v1.1) Sem resposta em 3 minutos, um único lembrete.
6. Com 12 agentes trabalhando e 6 computadores, o app continua leve: só os panes visíveis desenham.

### Critérios de aceite

> **AC-601** · v1 · `XCUI` + `F-CLI` · audit/05 P0.6, T10
> **Dado** stubs que disparam, em sequência, `UserPromptSubmit`, `PreToolUse`, `Notification(permission_prompt)`, `UserPromptSubmit`, `Stop`, `StopFailure` · **Quando** cada evento chega · **Então** a linha do agente passa por "Working", "Needs input", "Working", "Done" e "Failed", em até 1 s de cada evento, na sidebar, na tab e no header do pane.

> **AC-602** · v1 · `UNIT` + `XCUI` · 01 §6.3
> **Dado** uma sessão com um agente "Working", um "Done" não lido e um computador com pedido aberto · **Quando** o card agrega · **Então** o card mostra "Needs input"; resolvido o pedido, mostra "Working"; terminado o trabalho, mostra "Done" em negrito até o usuário ver o pane.

> **AC-603** · v1 · `MANUAL` + `XCUI` · audit/07 #38, audit/04 §5.4
> **Dado** a janela focada em `rti-platform` · **Quando** um agente de `arizona / sandperch` entra em "Needs input" · **Então** aparece a notificação do macOS com título "arizona / sandperch — Codex needs input" e corpo com a última mensagem; clicar seleciona a sessão e foca o pane com rim flash (M-309); **e dado** o usuário olhando o próprio pane que mudou, nenhuma notificação aparece.

> **AC-604** · v1 · `XCUI` · R6.2
> **Dado** três agentes que entraram em "Needs input" às 9h00, 9h05 e 9h10 · **Quando** o usuário aperta ⇧⌘A três vezes · **Então** o foco vai, nessa ordem, para os panes de 9h00, 9h05 e 9h10, com rim flash (M-309); sem pendências, aparece o toast "Nothing needs you".

> **AC-605** · v1 · `XCUI` · audit/07 #12, audit/04 §5.6
> **Dado** 10 sessões · **Quando** o usuário aperta ⌘J · **Então** a palette lista "Needs input" primeiro, depois terminais e sessões recentes, e ações; ⌘3 seleciona a terceira sessão da sidebar; ⌥⌘← volta à sessão anterior; ⌃⇥ vai à tab recente; ⌘K limpa a tela do terminal focado.

> **AC-606** · v1 · `XCUI` + `MANUAL` · P4, R6.5 (parte)
> **Dado** 4 itens de atenção de prioridade 1–2 abertos · **Quando** a contagem muda · **Então** o badge do Dock mostra "4" e o item da barra de menus mostra a contagem ao lado do ícone (03 §17); clicar no item da barra de menus abre o app.

> **AC-607** · v1 · `E2E` + `F-CLI` · R6.1
> **Dado** um pai Claude com 2 filhos ativos (SubagentStart sem SubagentStop) · **Quando** o pai dispara `Stop` · **Então** ele fica "Waiting on subagents"; com um filho com pedido de ajuda aberto, o card agrega "Needs input"; depois do último `SubagentStop`, o pai vira "Done".

> **AC-608** · v1 · `PERF` · R6.3, audit/09 §2.8
> **Dado** 15 terminais com TUI ativa (stub imprimindo 20 linhas/s), 4 deles visíveis, e 6 computadores com miniatura · **Quando** se mede por 60 s · **Então** o thread principal não tem hitch acima de 50 ms, o eco de tecla no pane focado tem p95 ≤ 33 ms (08 AR-702), e cada sessão no daemon ocupa no máximo 40 MB com 10 mil linhas de scrollback.

> **AC-609** · v1 · `PERF` + `E2E` · R6.3, PP-14
> **Dado** a carga da AC-608 · **Quando** se observam os panes ocultos e as miniaturas fora da tela · **Então** panes ocultos não recebem bytes do daemon (só eventos; os 4 recentes mantêm a view em cache, 08 AR-406), e miniaturas fora da tela não decodificam frames; com tudo ocioso, o app fica em ≤ 1 % e o daemon em ≤ 0,5 % de um núcleo na média de 60 s (08 AR-705).

> **AC-610** · v1 · `XCUI` (VoiceOver) · audit/07 #26
> **Dado** VoiceOver ligado · **Quando** agentes mudam de estado · **Então** só "needs input", "done" e "failed" são anunciados, com intervalo mínimo de 5 s por terminal, e a saída do terminal nunca é anunciada.

> **AC-611** · v1 · `XCUI` · audit/05 (c) P0, audit/07 #24
> **Dado** uma tab com 3 panes e a sidebar focada · **Quando** o usuário usa ⌘] e ⌘[, e na sidebar ↑, ↓ e Enter · **Então** o foco anda entre panes, a seleção anda entre sessões, e Enter foca o terminal da sessão selecionada.

> **AC-612** · v1 · `XCUI` · audit/07 #11
> **Dado** um terminal numa tab não visível · **Quando** o programa emite BEL · **Então** não toca o bipe do sistema; a tab e a sessão ficam não lidas.

> **AC-613** · v1.1 · `XCUI` · R6.4
> **Dado** um pedido de captcha e um "Done" ao mesmo tempo · **Quando** a fila é ordenada · **Então** o captcha vem primeiro; sem resposta em 3 minutos, um único lembrete é enviado; com "Focus: computer requests only", só pedidos de computador notificam.

> **AC-614** · v1.1 · `XCUI` · R6.5
> **Dado** pendências · **Quando** o usuário abre o item da barra de menus · **Então** a lista mostra cada pendência com "Go to" e, para pedidos de computador, "Take Over".

> **AC-615** · v1.1 · `E2E` · R6.6
> **Dado** uma sessão com 2 agentes e 1 computador · **Quando** o usuário escolhe "Sleep" · **Então** processos e computador param, os IDs ficam guardados e "Wake" relança tudo com `--resume`; "Pin" mantém a sessão no topo.

---

## J7 · Trocar de Claude para Codex no meio (handoff)

**Versão**: v1.1 inteira (R7.1–R7.4). R7.5 e R7.6 ficam para depois.

### Roteiro-alvo

1. A status bar mostra "5h 96%" no medidor do Claude. O Claude bate no limite e um banner no pane diz "Claude hit its 5-hour limit (resets at 2:20 PM). Continue in Codex?".
2. "Continue in… › Codex" monta um brief editável: objetivo (nota da sessão e prompt inicial), últimos pedidos do usuário, última resposta, `git status` e resumo do diff, pendências (lista de tarefas do transcript), filhos e computadores ativos.
3. Ele revisa e confirma. Uma tab nova abre o Codex na mesma worktree, com o brief salvo em `.agentbox/handoff.md` e passado como prompt inicial, e com o MCP do Agent Box configurado por `-c mcp_servers`.
4. A tab do Claude continua lá, marcada "Handed off to Codex". Os computadores do Claude só mudam de dono se ele marcar "Transfer computers".
5. Fechar a tab nova desfaz o handoff.

### Critérios de aceite

> **AC-701** · v1.1 · `E2E` + `F-CLI` · R7.2
> **Dado** um `StopFailure` de limite com hora de reset, ou `rate_limits` a 100 % · **Quando** o evento chega · **Então** o pane mostra o banner com a hora de reset e "Continue in…", e a status bar marca o medidor em vermelho.

> **AC-702** · v1.1 · `XCUI` · R7.1
> **Dado** uma sessão com nota, prompt inicial, alterações no Git e um filho ativo · **Quando** o usuário escolhe "Continue in… › Codex" · **Então** o overlay mostra o brief com essas seções, editável, e nada é lançado até "Start Codex".

> **AC-703** · v1.1 · `E2E` + `CLI` · R7.1, R7.4
> **Dado** o brief confirmado · **Quando** a tab nova abre · **Então** o Codex roda no mesmo cwd, `.agentbox/handoff.md` contém o brief, o prompt inicial referencia o arquivo, e `/mcp` no Codex lista o servidor `agentbox`; nenhum arquivo global do Codex muda.

> **AC-704** · v1.1 · `XCUI` · R7.1, R7.3
> **Dado** o handoff concluído · **Quando** se olha a tab original · **Então** ela continua aberta com o selo "Handed off to Codex"; os computadores continuam com o Claude, a menos que "Transfer computers" tenha sido marcado.

> **AC-705** · v1.1 · `E2E` · R7.3, audit/01 L17
> **Dado** um computador de um terminal · **Quando** o usuário escolhe "Transfer to…" e outro terminal da sessão · **Então** o dono muda com revogação e ACK, o perfil e a página aberta continuam, e o terminal antigo recebe `not_owner` nas próximas chamadas.

> **AC-706** · v1.1 · `CLI` · R7.4, audit/08 C1
> **Dado** Codex 0.160.0 lançado pelo app · **Quando** ele trabalha e cria subagentes · **Então** o estado vem dos hooks por lançamento (`SessionStart`, `Stop`, `PermissionRequest`, `SubagentStart/Stop`), os filhos aparecem na sidebar e o ID vem do rollout; o que a versão não emitir aparece como "Status unavailable".

---

## J8 · Fechar o app, reiniciar o Mac e voltar

**Versão**: v1 (manter acordado e sessão do CLI no volume: v1.1).

### Roteiro-alvo

1. ⌘Q com agentes rodando. Um overlay na janela (T5; texto de 03 §16.10) explica que 4 agentes e 2 computadores seguem rodando, com "Keep Running" (padrão), "Stop All and Quit…", "Cancel" e "Don't ask again". "Keep Running" fecha a janela e deixa o app em modo accessory (08 AR-108). Com "Don't ask again" marcado, os próximos ⌘Q fazem isso direto. O item da barra de menus continua mostrando o que segue rodando; "Quit Agent Box Completely" tira o ícone até reabrir.
2. Reabrir: os panes reaparecem com os processos vivos e o scrollback, inclusive o que saiu com o app fechado.
3. Atualização do Mac e reboot. Ao abrir: layout e último scrollback voltam esmaecidos; cada pane tem "Resume", que relança com o ID capturado **e** as mesmas flags, MCP, hooks e skills do lançamento original.
4. Subagentes que estavam rodando aparecem "Interrupted" (tooltip "Stopped when your Mac restarted."), com a última nota do diário de cada um e "Ask Parent to Relaunch", que cola um pedido no prompt do pai, sem Enter (R5.1).
5. Docker parado: o app oferece iniciar só quando algo precisa de computador. Computadores voltam com o perfil (logins mantidos) e nunca reiniciam sozinhos.
6. (v1.1) Com agentes trabalhando, o Mac não dorme, se a opção estiver ligada, com indicador e aviso na bateria.

### Critérios de aceite

> **AC-801** · v1 · `XCUI` + `E2E` · P4, audit/09 D12, T5
> **Dado** 4 agentes trabalhando, 2 computadores ativos e "Don't ask again" desmarcado · **Quando** o usuário aperta ⌘Q · **Então** aparece o overlay na janela (não `NSAlert`) com as contagens reais, "Keep Running" como padrão, "Stop All and Quit…", "Cancel" e "Don't ask again"; escolher "Keep Running" fecha a janela, o app fica em modo accessory, os 4 processos seguem vivos no daemon e os computadores seguem rodando. Sem janela aberta (quit pelo Dock ou pela barra de menus), a mesma pergunta vem em `NSAlert`.

> **AC-802** · v1 · `E2E` · audit/05 P0.5, T1
> **Dado** um terminal com `while true; do date; sleep 1; done` e o app fechado por 30 s · **Quando** o app reabre · **Então** o pane mostra o mesmo PID e as ~30 linhas produzidas com o app fechado, sem lacunas na sequência.

> **AC-803** · v1 · `E2E` · P4, T1
> **Dado** agentes rodando · **Quando** o processo do app é morto com `kill -9` · **Então** os agentes continuam vivos e, ao reabrir, os panes reanexam como na AC-802.

> **AC-804** · v1 · `MANUAL` + `E2E` · P4, R1 D-03
> **Dado** o app em modo accessory (depois do ⌘Q) com 3 processos no daemon · **Quando** o usuário olha a barra de menus · **Então** o item mostra a contagem (e pendências, se houver), clicar abre a janela, e "Quit Agent Box Completely" encerra o app e tira o ícone sem matar os 3 processos.

> **AC-805** · v1 · `E2E` · audit/09 N10, PP-8
> **Dado** agentes e computadores rodando · **Quando** o usuário escolhe "Stop All and Quit…" e confirma · **Então** o overlay lista o que vai parar, mostra o progresso de cada item sem bloquear o thread principal, e se um computador não parar oferece "Try Again" e "Quit Anyway", sem nunca deixar agentes mortos com a UI ainda pedindo para "voltar ao app".

> **AC-806** · v1 · `E2E` + `CLI` · R8.1, audit/09 N9
> **Dado** um terminal Claude lançado com MCP, hooks, statusline encadeada e uma skill de sessão, e um reboot simulado que apaga todos os diretórios temporários · **Quando** o usuário clica "Resume" · **Então** o argv contém `--resume <id>` e as mesmas flags do perfil, `--mcp-config`, `--settings` e `--plugin-dir` regenerados, e `/mcp` mostra o `agentbox` de novo.

> **AC-807** · v1 · `E2E` · R8.2, PP-2
> **Dado** um pai com 2 filhos com computador rodando no momento do reboot simulado · **Quando** o app abre · **Então** os filhos aparecem "Interrupted" com a última nota do diário, os computadores aparecem "Stopped", nada é relançado, e "Ask Parent to Relaunch" cola no prompt do pai o pedido com os rótulos, sem Enter.

> **AC-808** · v1 · `E2E` · R8.2, audit/08 N27
> **Dado** um pedido de ajuda aberto e um container com label do app sem registro no banco · **Quando** o app abre depois do reboot · **Então** o pedido continua visível na Inbox, e o container aparece em "Orphaned" com tamanho e "Clean Up", que só remove após confirmação.

> **AC-809** · v1 · `E2E` · R8.3, PP-2
> **Dado** Docker parado depois do reboot e 15 computadores parados · **Quando** o app abre · **Então** nenhum computador inicia sozinho e o Docker não é aberto; **quando** um agente pede um computador, nasce "Docker isn't running · Start Docker", e só aquele computador sobe depois do clique, com o perfil preservado.

> **AC-810** · v1 · `E2E` · audit/09 §2.2
> **Dado** sessões vivas · **Quando** o daemon morre com `kill -9` · **Então** o app mostra "Background agents stopped unexpectedly" com o último scrollback de cada pane esmaecido e "Resume"; o daemon volta na próxima conexão (ativação por socket).

> **AC-811** · v1 · `E2E` · T1
> **Dado** sessões vivas num daemon de protocolo v1 (`app.agentbox.ptyd.v1`) · **Quando** o app atualiza para uma build que fala v1 e v2 · **Então** as sessões antigas continuam anexáveis, Settings › Diagnostics mostra "3 terminals on previous background service", e sessões novas usam o daemon novo.

> **AC-812** · v1.1 · `MANUAL` · R8.4
> **Dado** "Keep Mac awake while agents work" ligado e um agente trabalhando · **Quando** o Mac ficaria inativo · **Então** ele não dorme, o item da barra de menus mostra o indicador, e na bateria aparece o aviso; com tudo ocioso, a asserção de energia sai.

> **AC-813** · v1.1 · `E2E` · R8.5 (ver AC-459)
> **Dado** um filho isolado e um reboot · **Quando** o usuário clica "Resume" na tab do filho · **Então** a conversa volta a partir do estado do CLI no volume da box.

---

## J9 · Biblioteca: ver, ativar numa sessão, criar e editar

**Versão**: v1 (leitura das fontes nativas, ativação aditiva por sessão, abrir no editor); v1.1 (criar e editar com backup, quando a mudança vale, MCP de computador em agente da biblioteca).

### Roteiro-alvo

1. ⇧⌘L abre a página "Library", com "Agents", "Skills" e "Profiles" (instruções aparecem na aba "Context" do painel direito) e as fontes com contagem: `~/.claude/agents` (13), `~/.codex/agents` (12), `~/.claude/skills` (133), `~/.agents/skills` (~30), plugins, `.claude/` do projeto.
2. Cada item mostra nome, descrição, fonte, em quais CLIs funciona e o escopo: "Always on" (global) ou "This session".
3. "Open in Editor" e "Reveal in Finder" por item.
4. **Ativar só nesta sessão**: na aba "Context" da sessão, ele liga a skill `arcgis-playbook` e o agente `permit-portal-scout` para esta sessão. O app aplica no próximo lançamento e oferece "Relaunch with resume". Skills globais aparecem como "Always on", separadas das adicionadas na sessão.
5. Cada terminal mostra "Loaded in this run" com skills, agentes, MCP, instruções e plugins efetivos, com a fonte.
6. (v1.1) "New agent" cria `permit-portal-scout`: nome, descrição, modelo, ferramentas, skills, MCP (inclusive o computador do Agent Box) e escopo. Grava `~/.claude/agents/permit-portal-scout.md` e, se marcado, o `.toml` espelho do Codex, com backup.
7. (v1.1) Editar uma skill abre o `SKILL.md`; o app avisa "Used by 3 active sessions · applies on next launch", guarda backup e oferece "Relaunch with resume".

### Critérios de aceite

> **AC-901** · v1 · `XCUI` com `F-HOME` · audit/05 (e), R9.1
> **Dado** as pastas nativas com 13 agentes Claude, 12 Codex e N skills · **Quando** o usuário abre a Biblioteca · **Então** as contagens por fonte batem com o disco, cada item mostra fonte e CLIs, e o banco guarda só caminho, hash e metadados (nenhum conteúdo de `SKILL.md` no banco).

> **AC-902** · v1 · `XCUI` · R9.1
> **Dado** um item · **Quando** o usuário escolhe "Open in Editor" ou "Reveal in Finder" · **Então** o arquivo abre no editor padrão configurado ou é revelado no Finder.

> **AC-903** · v1 · `E2E` + `CLI` · R9.1 (parte), R9.2 (parte)
> **Dado** uma sessão com Claude rodando · **Quando** o usuário liga a skill `arcgis-playbook` em "Context" · **Então** a UI diz "Applies on next launch" com "Relaunch with resume"; depois do relançamento, a skill aparece entre as skills do Claude naquela sessão e em nenhuma outra, e nenhum arquivo global mudou.

> **AC-904** · v1 · `XCUI` · audit/08 N24
> **Dado** um terminal de agente · **Quando** o usuário abre "Loaded in this run" · **Então** a lista mostra skills, agentes, MCP, instruções e plugins efetivos, separando "Always on" de "This session" e das integrações do Agent Box.

> **AC-905** · v1 · `CLI` + `XCUI` · R9.1
> **Dado** uma skill global · **Quando** o usuário tenta desligá-la só para a sessão · **Então**, se a versão instalada do CLI não suporta desligar por lançamento, o controle fica desabilitado com "Claude Code loads global skills in every session" em vez de prometer o efeito.

> **AC-909** · v1 · `XCUI` · 06 TA-411, R2 SEM #1
> **Dado** um Claude rodando no pane focado e a skill `code-review` na Library · **Quando** o usuário escolhe "Insert Skill or Agent…" na palette (ou digita `/`) e confirma a skill, ou clica em `[Insert in Prompt]` na Library, ou no item da aba "Context" · **Então** `/code-review` aparece no prompt do Claude por bracketed paste com origem `app-paste` (0x02), sem Enter e sem enviar a mensagem, a palette fecha e o foco volta ao terminal; sem pane de agente focado, as linhas ficam desabilitadas com "Focus an agent terminal first.".

> **AC-906** · v1.1 · `E2E` · R9.4, PP-6
> **Dado** "New agent" preenchido com escopo "User" e "Mirror to Codex" · **Quando** o usuário salva · **Então** existem `~/.claude/agents/permit-portal-scout.md` e o `.toml` espelho, um backup e uma entrada no histórico com diff e "Revert".

> **AC-907** · v1.1 · `XCUI` · R9.2, R9.4
> **Dado** uma skill usada por 3 sessões ativas · **Quando** o usuário edita e salva · **Então** aparece "Used by 3 active sessions · applies on next launch" com "Relaunch with resume" por sessão, e o histórico permite reverter a edição.

> **AC-908** · v1.1 · `CLI` · R9.3
> **Dado** um agente da biblioteca com `mcpServers: {agentbox: …}` e skill `webscraping-expert` · **Quando** o Claude delega a ele · **Então** o subagente tem as ferramentas de computador e a skill, sem o preset de scraping fixo no código.

---

## J10 · Custos, uso e limites

**Versão**: v1 (medidores de uso, computadores, RAM, uso do proxy quando o provedor informa); v1.1 (custo e tokens por terminal, limpeza). Teto de orçamento: fora (P13).

### Roteiro-alvo

1. A status bar tem 24 pt. À esquerda, o medidor do Claude "5h 62% · 7d 31%" e o do Codex "5h 100%" em vermelho, com "Resets at <time>" no popover (03 §5). À direita: "3 computers · 6.1 GB" e o segmento de proxy, que mostra o uso informado pelo provedor ou some quando nenhum proxy informa uso.
2. Clicar em cada item abre o detalhe: por computador, proxy escolhido, uso informado, CPU, RAM e disco do volume.
3. Não há orçamento, aviso de 80% nem corte (P13). Erro do proxy aparece em "Network" com o status real.
4. (v1.1) Tokens e custo estimado por terminal e por sessão.
5. (v1.1) "Clean Up": volumes de computadores parados há mais de N dias, run folders grandes, imagens antigas, com tamanho e confirmação.

### Critérios de aceite

> **AC-1001** · v1 · `E2E` com `F-HOME` · R10.1, PP-6
> **Dado** a statusline do usuário em `~/.claude/statusline-command.sh` · **Quando** um Claude lançado pelo app atualiza a statusline · **Então** a statusline aparece no CLI exatamente como antes (mesma saída do script do usuário), e o app recebe `rate_limits.five_hour` e `seven_day` pela statusline encadeada por lançamento.

> **AC-1002** · v1 · `UNIT` + `E2E` · R10.1
> **Dado** um rollout do Codex com `rate_limits.primary.used_percent = 100` e `resets_at` · **Quando** o app lê o rollout mais novo · **Então** a status bar mostra "5h 100%" em vermelho no medidor do Codex, com "Resets at <time>" no popover.

> **AC-1003** · v1 · `XCUI` + `E2E` · R10.4 (parte), audit/07 #46
> **Dado** 3 computadores ativos · **Quando** o usuário clica no segmento de computadores · **Então** o popover lista cada um com sessão, modo, proxy escolhido, CPU, RAM, disco, uso do proxy (quando informado) e "Stop".

> **AC-1004** · v1 · `UNIT` + `E2E` · P13, T9
> **Dado** dois computadores com um proxy que informa uso (stub de provedor em `F-SITE` devolvendo o custo por request) e um terceiro com proxy que não informa · **Quando** a status bar renderiza · **Então** o segmento `Proxy usage` (`statusBar.proxyUsage`) mostra a soma informada hoje, o valor bate com os registros do egress (fonte única), e o terceiro aparece como "Usage unavailable" no popover, sem estimativa inventada.

> **AC-1005** · removido · P13
> Teto de orçamento por sessão e por dia saiu do escopo (01 §4.4). O ID fica reservado para não renumerar.

> **AC-1006** · v1.1 · `CLI` · R10.2
> **Dado** um terminal Claude e um Codex · **Quando** terminam turnos · **Então** o detalhe da sessão mostra tokens e custo por terminal, rotulados "Estimated".

> **AC-1007** · v1.1 · `E2E` · R10.4
> **Dado** volumes parados há 10 dias e um run folder de 391 MB · **Quando** o usuário abre "Clean Up" · **Então** a lista mostra cada item com tamanho e idade, nada é removido sem confirmação, e results e evidências exportadas nunca entram na limpeza padrão.

---

## J11 · Sessão limpa em 1 clique

**Versão**: v1 (P10).
**Pré-condições**: agente padrão configurado.

### Roteiro-alvo

1. O Gabriel quer começar algo sem repositório (um lote de scraping, uma pesquisa). Na sidebar, ele clica no "+" do header "Sessions" (ou usa "File › New Clean Session", ⇧⌘N; P11).
2. Sem diálogo, o app cria `~/AgentBox/sessions/<name>` com um nome automático adjetivo + substantivo (`quiet-harbor`, P15), cria a sessão na seção "Sessions" e abre uma tab com o agente padrão rodando nessa pasta, com o foco no terminal.
3. Ele renomeia a sessão com duplo clique ("permits-oct"). A pasta mantém o nome original.
4. A sessão tem o mesmo card, estados, agentes, computadores e status note das sessões de projeto. Não tem branch, chip de PR nem "Create PR".
5. Variante: no composer (⌘N), sem projeto e com "Choose Folder…" em "Where", a sessão limpa usa uma pasta existente; o app não cria nem apaga nada nela.
6. Depois, "Move to Project…" liga a sessão a um projeto existente sem mover arquivos; no mesmo overlay, "New Project from This Folder" cria um projeto com a pasta como raiz. (v1.1) "Move Folder into Project…" só fica disponível com todos os terminais parados.
7. Apagar a sessão move a pasta para o Lixo só quando ela foi criada pelo app; pasta escolhida fica no disco (03 §16.5).

### Critérios de aceite

> **AC-1101** · v1 · `XCUI` + `E2E` · P10, P9, PP-4
> **Dado** o app aberto · **Quando** o usuário clica no "+" de "Sessions" · **Então** em até 1 s existe a pasta `~/AgentBox/sessions/<name>`, a sessão aparece na seção "Sessions" e uma tab roda o agente padrão com cwd nessa pasta e foco no terminal, sem nenhum diálogo.

> **AC-1102** · v1 · `UNIT` · P10
> **Dado** `~/AgentBox/sessions/quiet-harbor` já existente · **Quando** o nome gerado colide · **Então** o app gera outro nome e nunca reaproveita uma pasta existente.

> **AC-1103** · v1 · `XCUI` · P10
> **Dado** uma sessão limpa · **Quando** o usuário renomeia para "permits-oct" · **Então** o título muda, a pasta continua `quiet-harbor`, e o caminho real aparece no hover e em "Copy path".

> **AC-1104** · v1 · `XCUI` + `F-CLI` · P10
> **Dado** uma sessão limpa com um agente e um computador · **Quando** os estados mudam · **Então** o card mostra os mesmos estados, linhas de agente, aba "Computers" e status note das sessões de projeto, e não mostra branch, chip de PR nem "Create PR".

> **AC-1105** · v1 · `XCUI` · P10, P11
> **Dado** o composer sem projeto, com "Choose Folder…" e uma pasta escolhida · **Quando** a sessão é criada e depois apagada · **Então** a sessão aparece em "Sessions", o agente roda nessa pasta, nenhum arquivo dela é criado ou removido pelo app, e o diálogo de apagar diz "Stops its terminals and computers. The folder stays on disk."

> **AC-1106** · v1 · `E2E` · P10
> **Dado** uma sessão limpa com um agente rodando · **Quando** o usuário escolhe "Move to Project…" e `rti-platform` · **Então** a sessão passa para o projeto, o processo continua o mesmo (mesmo PID) e nenhum arquivo é movido; "New Project from This Folder" cria um projeto com a pasta como raiz, com tipo `git` se ela já for repositório, sem `git init`.

> **AC-1107** · v1.1 · `XCUI` · P10, R1 K-34
> **Dado** uma sessão limpa com terminais rodando · **Quando** o usuário abre o menu · **Então** "Move Folder into Project…" aparece desabilitado com o tooltip "Stop all terminals in this session first"; com tudo parado, a ação move a pasta e atualiza os caminhos.

> **AC-1108** · v1 · `E2E` · P10, 01 §6.1
> **Dado** uma sessão limpa criada pelo app · **Quando** o usuário escolhe "Delete" e confirma "Delete Session" · **Então** a sessão some, a pasta vai para o Lixo do macOS (recuperável) e os run folders da sessão em `~/AgentBox/runs/` ficam, a menos que "Also delete run folders" seja marcado.

---

## JT · Critérios transversais

Não pertencem a uma jornada só, mas toda jornada depende deles.

### Funciona quando clica, e o app é dirigível

> **AC-T01** · v1 · `XCUI` · T13, audit/09 N7, PP-13
> **Dado** cada tela do 03 com o runtime falso · **Quando** um teste percorre a árvore de acessibilidade · **Então** todo controle interativo tem `accessibilityIdentifier` estável e hierárquico na convenção de 02 §17 e na lista de 03 §22 (ex.: `sidebar.session.<id>`, `pane.<id>.header`, `viewer.<id>.takeOver`), gerado do enum `A11yID`; o teste falha se faltar algum ou se aparecer um identificador fora da lista.

> **AC-T02** · v1 · `XCUI` + `UNIT` (lint) · PP-1, R3 §7
> **Dado** o registro central de ações (menus, atalhos, palette, botões), em que cada controle aponta para um `ActionID` · **Quando** a suíte roda · **Então** (a) o lint falha em qualquer `Button`, `.onTapGesture` ou `NSButton` cuja ação não passe pelo registro; (b) cada `ActionID` tem um XCUITest com clique ou atalho real (não só `ctl ui action`) que confere o efeito declarado: mudança de estado, navegação ou um erro específico declarado no teste ("algum erro visível" não conta); (c) todo controle desabilitado tem tooltip com o motivo; (d) atalho duplicado no mesmo escopo de 03 §21 ou que capture tecla reservada ao terminal reprova.

> **AC-T03** · v1 · `E2E` · T13
> **Dado** "Automation channel (agentbox ctl)" desligado em Settings › Advanced (padrão) · **Quando** um processo chama `agentbox ctl state` · **Então** a chamada é recusada; com a opção ligada, a titlebar mostra "Automation on" e `ctl state`, `ctl session open`, `ctl terminal new`, `ctl terminal send`, `ctl terminal screen`, `ctl ui tree`, `ctl ui action <id> focus` e `ctl screenshot --window` funcionam (tabela de 08 §8), e o cenário canônico de `scripts/e2e.sh` passa.

> **AC-T04** · v1 · `XCUI` · P2
> **Dado** todas as telas · **Quando** se extraem as strings visíveis · **Então** todas estão em inglês e vêm do String Catalog; nenhuma string em português aparece na UI.

### Terminal e foco

> **AC-T05** · v1 · `UNIT` + `E2E` · audit/07 #1, T6
> **Dado** um terminal · **Quando** um programa envia `OSC 52;c;?` · **Então** o app não responde com o conteúdo do clipboard; a escrita via OSC 52 segue a opção em Settings › Terminal.

> **AC-T06** · v1 · `XCUI` · audit/07 #23
> **Dado** qualquer overlay (composer, palette, confirmação, onboarding) aberto sobre um terminal focado · **Quando** o usuário digita · **Então** nenhuma tecla chega ao PTY, Tab fica preso no overlay, Esc fecha, e o foco volta ao pane anterior.

> **AC-T07** · v1 · `PERF` · audit/09 N14
> **Dado** `yes | head -c 200M` num pane · **Quando** o usuário digita em outro pane visível · **Então** o eco tem p95 ≤ 33 ms (08 AR-702) e a janela não congela.

> **AC-T08** · v1 · `UNIT` + `MANUAL` · audit/07 #9, R3 §7.7
> **Dado** a tabela tecla → bytes de 06 (Shift+Enter, ⌘←, ⌘→, ⌘⌫, ⌥←, ⌥→ e as demais teclas reservadas ao terminal de 03 §21) · **Quando** o teste de unidade do `TerminalSurface` envia cada tecla · **Então** os bytes escritos são os da tabela; e, com Claude Code e Codex reais (`MANUAL`), Shift+Enter quebra linha e os atalhos de edição funcionam como no Orca.

### Ciclo de vida e erros

> **AC-T09** · v1 · `XCUI` + `E2E` · audit/05 P0.7, audit/07 #33
> **Dado** uma tab com processo rodando · **Quando** o usuário aperta ⌘W · **Então** a confirmação "Close this terminal?" diz o que vai parar; confirmado, o processo termina; ⇧⌘T reabre a tab relançando com `--resume` quando há ID nativo; arquivar e apagar sessão e worktree seguem o §6.1 do 01, com checagem de alterações não publicadas.

> **AC-T10** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-T11** · removido por P21 (sem importação nem convivência com o Orca).

> **AC-T12** · v1 · `XCUI` · RT.3, audit/07 #51
> **Dado** qualquer ação longa (worktree, computador, imagem, retomada em lote) · **Quando** ela falha · **Então** o erro aparece no lugar onde a ação foi pedida, com uma ação ("Try Again", "Show Log"); erros não bloqueantes aparecem como toast por 60 s com "Copy Details"; não existe alerta genérico.

> **AC-T27** · v1 · `XCUI` + `UNIT` (layout) · R2 §6 queixa 7, PP-1
> **Dado** a janela em 760×480 (mínima) e em 1440×900, com `F-LONG` · **Quando** se abre cada página do centro (Library, Computers, landing), cada seção de Settings, o composer, o Quick Launch, a palette, o onboarding, a Inbox, cada aba do painel direito e a sidebar com cards longos · **Então** nada sai da caixa: nenhum texto ou controle ultrapassa o frame do container pai (verificado pelos frames de `ctl ui tree`), não há scroll horizontal, texto longo trunca com reticências e mostra o valor inteiro no tooltip, nenhum controle fica coberto ou com tamanho zero, e as medidas fixas de 03 (Settings: nav 240, conteúdo até 720, controles 240) valem nas duas larguras.

> **AC-T28** · v1 · `XCUI` · R3 §5.6, PP-1
> **Dado** uma build com as feature flags de uma fatia (01 §4.1) · **Quando** um teste percorre todas as telas · **Então** nenhum controle de fatia ou versão futura é renderizado (nem desabilitado): por exemplo, na Fatia 1 não existem chip de PR, aba "Computers", status bar nem itens v1.1 como "Pin Session" e "Move Folder into Project…".

### Persistência, confiabilidade e segurança

> **AC-T13** · v1 · `E2E` · T2, audit/09 N3, PP-9
> **Dado** o banco SQLite corrompido de propósito · **Quando** o app abre · **Então** o arquivo vai para `corrupt-<ts>.sqlite`, o último backup é restaurado, o banner "Restored from the backup of <date>." explica o que aconteceu, e a UI funciona; sem backup, o app abre vazio com o banner e "Reveal Corrupt File" (08 AR-331).

> **AC-T14** · v1 · `UNIT` · T2
> **Dado** um banco na versão N−1 · **Quando** uma migração roda · **Então** existe um backup anterior à migração; o backup diário guarda os últimos 7.

> **AC-T15** · v1 · `UNIT` + `E2E` · T2
> **Dado** os JSONs do app atual (`workspace.json`, `library.json`, `AgentRuns.json`, `ComputerPolicy.json`) · **Quando** o importador roda · **Então** um dry-run mostra o que entra, a importação real preserva os originais e é idempotente.

> **AC-T16** · v1 · `UNIT` (lint) + `PERF` · audit/09 N4, T3
> **Dado** o código · **Quando** o CI roda · **Então** o lint bloqueia `DispatchSemaphore.wait`, `Thread.sleep`, `usleep` e locks em I/O fora de `Platform/` (regex com limite de palavra, sem pegar `Task.sleep(for:)`, `ProcessInfo` ou `fingerprint(`); **e dado** 15 `box_claim` em paralelo, a UI e os hooks continuam respondendo.

> **AC-T17** · v1 · `E2E` · audit/09 N5
> **Dado** uma falha de Docker, de hook e de lançamento · **Quando** o usuário abre Settings › Diagnostics e clica "Export Diagnostics…" · **Então** o pacote `.zip` (08 AR-603) contém logs por módulo, versões dos CLIs e resumo do `docker info`, sem nenhum valor de segredo, caminho privado não redigido ou token.

> **AC-T18** · v1 · `MANUAL` · T4, audit/09 N6
> **Dado** "Always allow" concedido ao Keychain e permissões de notificação e pastas · **Quando** uma build nova é instalada por `install.sh` · **Então** nenhum prompt de Keychain, TCC ou notificação reaparece.

> **AC-T19** · v1 · `MANUAL` (revisão) · audit/09 N2, PP-11
> **Dado** a documentação e a UI · **Quando** se revisa · **Então** o modelo de ameaça de 08 está publicado, e a UI do modo leve não usa palavras como "isolated" ou "sandboxed" para o agente no Mac.

> **AC-T20** · v1 · `E2E` · T7, audit/09 N12
> **Dado** o app aberto pelo Finder (env mínimo do launchd) com Docker Desktop, depois OrbStack, depois Colima como contexto ativo · **Quando** o app lista, cria e para um computador e baixa a imagem · **Então** tudo funciona pela Engine API com eventos, e os credential helpers do Docker são encontrados.

> **AC-T21** · v1 · `UNIT` + `E2E` · T7, audit/09 N11
> **Dado** o contexto de build da imagem · **Quando** o app verifica a imagem · **Então** a tag esperada é o hash do contexto; com o registry fora do ar, o build local funciona sem pins de pacote apt que possam sumir.

> **AC-T22** · v1 · `E2E` · audit/09 N19
> **Dado** um `create` de container que excede o timeout do agente · **Quando** a chamada é cancelada · **Então** a criação em andamento é reconciliada pelos eventos do Docker, e nenhum container fica sem registro.

> **AC-T23** · v1 · `PERF` · audit/09 N13
> **Dado** o viewer aberto enquanto o agente navega numa página lenta · **Quando** se mede · **Então** a decodificação de frames não acontece no thread principal, e a navegação longa não congela o viewer.

> **AC-T24** · v1 · `UNIT` + `E2E` · audit/09 N15
> **Dado** um Mac sem Command Line Tools (sem `python3`) · **Quando** um agente roda com hooks do app · **Então** os hooks funcionam (helper `agentbox hook` ou hook HTTP), e nenhum instalador do Xcode aparece.

### Motion e visual

> **AC-T25** · v1 · `MANUAL` + `XCUI` · P8
> **Dado** os três momentos obrigatórios (abrir telas e overlays: M-101/M-102/M-109; agente sendo lançado: M-501 a M-506; agente usando um computador: M-604 a M-611) · **Quando** o Gabriel os revê com gravação (`ctl record`) ao lado do protótipo aprovado · **Então** batem com os protótipos aprovados de 04 e ele registra o OK; com Reduce Motion ligado, nenhuma animação não nula é aplicada (teste automatizado de 04).

> **AC-T26** · v1 · `MANUAL` + `XCUI` (captura) · P1, P14, PP-12
> **Dado** cada tela e componente entregue numa tarefa visual e a referência equivalente em `F-REF` · **Quando** a tarefa fecha · **Então** existe em `docs/evidence/ui/<tarefa>/` a captura do Agent Box (`ctl screenshot`, mesmo tamanho e mesmos dados) lado a lado com o PNG do Orca, mais o diff de sobreposição de `scripts/compare-ui.sh`; cada item da checklist de fidelidade da auditoria 04 §8 (referida em 02 §15) que a tela toca passa ou tem a divergência justificada em 03; e o OK explícito do dono está registrado. Sem OK, a tarefa não fecha (P14). Não há aprovação em lote no fim da v1.

---

## Matriz requisito → jornada → AC

Versão: v1, v1.1, later (depois) ou out (fora). A coluna "Prio." é a prioridade de `audit/10` (P0/P1/P2) e não tem relação com as decisões P* do `00`. "—" na coluna de AC = sem critério nesta spec (item "later" ou "out"; o AC nasce quando o item for agendado). As origens são os relatórios de `docs/rebuild/audit/`: `10` (R*, RT*), `05` (P0 do backlog e transversais), `07` (itens P0), `08` (§1, N*, capacidades P0 da §3), `09` (N*).

### Relatório 10 · R*.* e RT.*

| Req | Prio. | Resumo | Jornada | ACs | Versão |
|---|---|---|---|---|---|
| R1.1 | P0 | Onboarding como checklist de diagnóstico não bloqueante | J1 | AC-101, 102, 103, 104 | v1 |
| R1.2 | P0 | Contexto Docker ativo; capacidade em computadores | J1 | AC-105, 106 | v1 |
| R1.3 | - | Importar do Orca (removido por P21) | J1 | - | removido |
| R1.4 | P1 | Importar CLI antigo: credenciais do `.env` com preset de proxy (v1) e runs (v1.1) | J1 | AC-118 (v1), AC-119 (v1.1) | v1 / v1.1 |
| R1.5 | P0 | Nunca sobrescrever config global dos CLIs | J1, J4, J10 | AC-112, 114, 401, 1001 | v1 |
| R1.6 | P0 | Detectar a skill global `agentbox` e oferecer opções | J1, J4 | AC-113, 402 | v1 |
| R1.7 | P1 | Detectar `gh` e escopos | J1 | AC-115 | v1 |
| R1.8 | P1 | Aprovação do item de login só ao ativar segundo plano | J1 | AC-117 | v1 |
| R1.9 | P2 | Reprobe de CLI com "o que mudou" | — | — | later |
| R2.1 | P0 | Última mensagem do agente | J2 | AC-201, 202, 209 | v1 |
| R2.2 | P0 | Captura do ID nativo em todo terminal | J2 | AC-203 | v1 |
| R2.3 | P1 | Inbox "Since you were away" | J2 | AC-204 (simples, v1), AC-210 (v1.1) | v1 / v1.1 |
| R2.4 | P1 | Nota de status da sessão (usuário e agente) | J2 | AC-208 | v1 |
| R2.5 | P1 | Retomada em lote com custo à vista, nunca automática | J2 | AC-206, 207 | v1 |
| R2.6 | P2 | Filtros da sidebar | — | — | later |
| R3.1 | P0 | Prompt inicial como argumento do CLI | J3 | AC-307, 308, 309 | v1 |
| R3.2 | P0 | Diretório gerenciado, nomes e colisão | J3 | AC-303, 304 | v1 |
| R3.3 | P0 | Composer aceita sessão sem Git | J3, J11 | AC-305, 1101 | v1 |
| R3.4 | P1 | `.worktreeinclude` / `orca.yaml` / copiar `.env*` | J3 | AC-317 | v1.1 |
| R3.5 | P1 | Script de setup com política e tab "Setup" | J3 | AC-318 | v1.1 |
| R3.6 | P2 | Anexar imagem ou arquivo ao prompt | — | — | later |
| R3.7 | P2 | Mesma tarefa em N agentes | — | — | later |
| R4.1 | P0 | Skill de orquestração do app por lançamento | J4 | AC-401, 402 | v1 |
| R4.2 | P0 | Reserva por nome e reivindicação pelo filho | J4 | AC-403, 404 | v1 |
| R4.3 | P0 | Pedido de ajuda assíncrono | J4 | AC-409, 410 | v1 |
| R4.4 | P0 | Takeover sem perder a página (headed em Xvfb) | J4 | AC-412 | v1 |
| R4.5 | P0 | Resultado e logs no host; `box_collect`; "Not verified" | J4 | AC-420, 421, 423 | v1 |
| R4.6 | P1 | Modo isolado (CLI no container) | J4b | AC-451 a 463 | v1.1 |
| R4.7 | P0 | Capacidade e fila visíveis | J1, J4 | AC-106, 403, 405 | v1 |
| R4.8 | P1 | Aba "Computers" com URL, diário e uso do proxy | J4 | AC-407 | v1 |
| R4.9 | P1 | Nota humana ao devolver o controle | J4 | AC-413 | v1 |
| R4.10 | P1 | Detector de filho parado | J4 | AC-426 | v1.1 |
| R4.11 | P1 | Mensagem a um filho específico | J4 | AC-427 | v1.1 |
| R5.1 | P0 | Colar no prompt só por ação explícita | J5, J8 | AC-505, 807 | v1 |
| R5.2 | P0 | "Open in…" | J5 | AC-502 | v1 |
| R5.3 | P1 | Diff só leitura | J5 | AC-507 | v1.1 |
| R5.4 | P1 | PR e checks como eventos, polling com cota | J5 | AC-501, 504 (v1), AC-508 (v1.1) | v1 / v1.1 |
| R5.5 | P1 | "Send failures to agent" | J5 | AC-508 | v1.1 |
| R5.6 | P2 | Comentários por linha no diff | — | — | later |
| R6.1 | P0 | Estado do pai considera os filhos | J4, J6 | AC-425, 607 | v1 |
| R6.2 | P0 | "Next needing attention" | J6 | AC-604 | v1 |
| R6.3 | P0 | Orçamento de desempenho medido | J4, J6 | AC-406, 608, 609 | v1 |
| R6.4 | P1 | Prioridade por tipo, lembrete único, modo foco | J6 | AC-613 | v1.1 |
| R6.5 | P1 | Item da barra de menus com ações | J6 | AC-606 (contagem, v1), AC-614 (ações, v1.1) | v1 / v1.1 |
| R6.6 | P1 | Dormir sessão e fixar | J6 | AC-615 | v1.1 |
| R6.7 | P2 | Responder pela notificação | — | — | later |
| R7.1 | P1 | Handoff leve com brief editável | J7 | AC-702, 703, 704 | v1.1 |
| R7.2 | P1 | Detecção de limite com oferta de troca | J7 | AC-701 | v1.1 |
| R7.3 | P1 | Transferir computador entre terminais | J7 | AC-704, 705 | v1.1 |
| R7.4 | P1 | Paridade mínima do Codex (MCP, hooks, ID) | J7 | AC-703, 706 | v1.1 |
| R7.5 | P2 | Voltar ao agente original com diff | — | — | later |
| R7.6 | P2 | Troca de conta Claude/Codex | — | — | later |
| R8.1 | P0 | Lançamento declarativo e regenerável | J8 | AC-806 | v1 |
| R8.2 | P0 | Reconciliação de filhos e computadores após reboot | J8 | AC-807, 808 | v1 |
| R8.3 | P1 | Docker após reboot sob demanda, nunca em massa | J8 | AC-809 | v1 |
| R8.4 | P1 | Manter acordado | J8 | AC-812 | v1.1 |
| R8.5 | P1 | Sessão do CLI isolado no volume | J4b, J8 | AC-459, 813 | v1.1 |
| R8.6 | P2 | Abrir no login | — | — | later |
| R9.1 | P1 | Escopo de ativação explícito | J9 | AC-901, 902, 903, 905, 909 | v1 (parte) / v1.1 (app only) |
| R9.2 | P1 | Quando a mudança vale | J9 | AC-903 (v1), AC-907 (v1.1) | v1 / v1.1 |
| R9.3 | P1 | Agente da biblioteca declara MCP de computador | J9 | AC-908 | v1.1 |
| R9.4 | P1 | Backup e histórico de escrita em `~/.claude`/`~/.codex` | J9 | AC-906, 907 | v1.1 |
| R9.5 | P2 | Lint da biblioteca | — | — | later |
| R9.6 | — | Sem memória própria do app | — | — (decidido em T14) | out |
| R10.1 | P1 | Medidores de janela de uso | J10 | AC-1001, 1002 | v1 |
| R10.2 | P1 | Custo e tokens por terminal e sessão | J10 | AC-1006 | v1.1 |
| R10.3 | P1 | Orçamento de proxy (substituído por P13: proxy genérico configurável e uso quando disponível, sem teto) | J4, J10 | AC-417, 418, 1004 (proxy e uso, v1); teto: AC-1005 removido | v1 / out (teto) |
| R10.4 | P1 | Recursos Docker ao vivo e limpeza | J10 | AC-1003 (v1), AC-1007 (v1.1) | v1 / v1.1 |
| R10.5 | P2 | Histórico de gasto exportável | — | — | later |
| RT.1 | - | Convivência com o Orca (removido por P21) | J1, JT | AC-112 | removido |
| RT.2 | P0 | Aceite "um dia real" | §0.4 | §0.4, AC-T26 | v1 |
| RT.3 | P1 | Ação longa com estado no lugar e fim com ação | J3, JT | AC-306, 311, T12 | v1 |

### Relatório 05 · P0

| Req | Resumo | Jornada | ACs | Versão |
|---|---|---|---|---|
| audit/05 P0.1 | Projeto/Repo → Worktree → Terminal; sidebar em níveis | J3, J11 | AC-315, 1106 | v1 |
| audit/05 P0.2 | Lançador de um passo, início imediato | J3, J11 | AC-307, 313, 1101 | v1 |
| audit/05 P0.3 | Perfis com modelo, permissão e flags | J1, J3 | AC-316 | v1 |
| audit/05 P0.4 | Ambiente herdado do shell de login | J3 | AC-312 | v1 |
| audit/05 P0.5 | Daemon de PTY: sobreviver a quit e crash, reanexar | J8 | AC-801, 802, 803 | v1 |
| audit/05 P0.6 | Estado semântico via hooks, notificação e ordenação | J2, J6 | AC-209, 601, 602, 603 | v1 |
| audit/05 P0.7 | Apagar e arquivar terminal, sessão e worktree | J11, JT | AC-1108, T09 | v1 |
| audit/05 P0.8 | Computador em qualquer terminal Claude; Docker e imagem pelo app | J1, J4 | AC-105, 107, 401 | v1 |
| audit/05 P0.9 | Viewer com fps decente e takeover | J4 | AC-408, 411, 413 | v1 |
| audit/05 P0.10 | Shell na box e listener cobrindo browser, curl e Python | J4 | AC-415, 416 | v1 |
| audit/05 P0.11 | Aceite visual feito (processo) | §0.4, JT | AC-T25, T26 | v1 |
| audit/05 P0.12 | "Continue last" e captura de ID | J2 | AC-203, 205 | v1 |
| audit/05 P0.13 | Navegação por teclado entre panes | J6 | AC-611 | v1 |
| audit/05 transv. | Recursos avançados fora do fluxo "Biblioteca → plano revisado" | J4 | AC-401 | v1 |
| audit/05 transv. | Env do PTY em allowlist | J3 | AC-312 | v1 |

### Relatório 07 · P0

| Req | Resumo | Jornada | ACs | Versão |
|---|---|---|---|---|
| audit/07 #1 | Nunca responder à leitura de clipboard (OSC 52) | JT | AC-T05 | v1 |
| audit/07 #23 | Overlays roubam o first responder do terminal | J1, J3, JT | AC-101, 301, T06 | v1 |
| audit/07 #42 | Modo do subagente visível na criação e depois | J4b | AC-451 | v1.1 |
| audit/07 #43 | Tab isolada com fases antes do PTY | J4b | AC-452 | v1.1 |

### Relatório 08 · P0

| Req | Resumo | Jornada | ACs | Versão |
|---|---|---|---|---|
| audit/08 §1 | CLI já logado no container; modelo de ameaça; aceite de 8 h | J4b | AC-453, 454, 463 | v1.1 |
| audit/08 §1.5 | Git por broker limitado ao repo; sem token do `gh` | J4b | AC-455 | v1.1 |
| audit/08 N1 | `agent_spawn`, `agent_wait` (resultado em `agent_wait` e `box_collect`) | J4b | AC-456 | v1.1 |
| audit/08 N2 | Paralelismo de 15 headless + 2 desktop com fila | J4 | AC-405, 406 | v1 |
| audit/08 N7 | Lote como entidade | J4 | AC-429 | v1 |
| audit/08 N21 | Notificação "lote concluído" com resumo | J4 | AC-429 | v1 |
| audit/08 N9 | Uso do proxy e logs fora do alcance do agente | J4 | AC-417 | v1 |
| audit/08 N12 | Imagem do agente com CLIs, usuário não-root, estado e kit | J4b | AC-459, 460 | v1.1 |
| audit/08 N13 | Worktree por filho; nunca dois filhos na mesma | J4b | AC-457 | v1.1 |
| audit/08 N14 | Hooks HTTP de dentro do container | J4b | AC-461 | v1.1 |
| audit/08 N20 | Modo isolado sobrevive ao quit (`dtach`) | J4b | AC-458 | v1.1 |
| audit/08 cap.1 | Escolher modo por subagente | J4b | AC-451 | v1.1 (na v1 só existe o leve) |
| audit/08 cap.2 | Spawn pelo app com PTY real em tab | J4b | AC-456 | v1.1 |
| audit/08 cap.3 | Subagente nativo observado (Claude; Codex) | J4, J7 | AC-404, 607 (Claude, v1), AC-706 (Codex, v1.1) | v1 / v1.1 |
| audit/08 cap.4 | Identidade por filho confiável | J4 | AC-404 | v1 |
| audit/08 cap.6 | Harness por filho: Claude e Codex | J4, J7 | AC-404 (Claude), AC-706 (Codex) | v1 / v1.1 |
| audit/08 cap.8 | CLI logado no container | J4b | AC-453 | v1.1 |
| audit/08 cap.10 | Git por broker (P0) | J4b | AC-455 | v1.1 |
| audit/08 cap.12 | Shell/exec na box com log de comandos | J4 | AC-415 | v1 |
| audit/08 cap.13 | curl, python3, requests, curl_cffi, jq, openpyxl, Playwright | J4 | AC-415 | v1 |
| audit/08 cap.14 | HTTP arbitrário a partir da box | J4 | AC-415 | v1 |
| audit/08 cap.15 | Navegador persistente com ações por seletor | J4 | AC-412, 415 | v1 |
| audit/08 cap.16 | Modos http, headless e desktop | J4 | AC-408, 412 | v1 |
| audit/08 cap.17 | Repo/worktree por filho, diff antes de mesclar | J4b | AC-457 | v1.1 |
| audit/08 cap.19 | Listener de todas as requests com corpos e consulta pelo agente | J4 | AC-416 | v1 |
| audit/08 cap.22 | Proxy e logs fora do alcance do agente (teto removido por P13) | J4 | AC-417, 418 | v1 |
| audit/08 cap.26 | Viewer bom para takeover | J4 | AC-408 | v1 |
| audit/08 cap.27 | Takeover com irmãos seguindo | J4 | AC-411 | v1 |
| audit/08 cap.29 | Pedido de ajuda com tipo e motivo real | J4 | AC-409, 410 | v1 |
| audit/08 cap.35 | Resultado volta ao pai | J4, J4b | AC-421 (v1), AC-456 (v1.1) | v1 / v1.1 |
| audit/08 cap.39 | Paralelismo 15 + 2 | J4 | AC-405, 406 | v1 |
| audit/08 cap.40 | Kit de skills e agentes no container | J4b | AC-460 | v1.1 |
| audit/08 cap.41 | Sobrevive ao quit (leve: daemon; isolado: `dtach`) | J8, J4b | AC-801, 802 (v1), AC-458 (v1.1) | v1 / v1.1 |
| audit/08 cap.43 | Parada e limpeza no fim com retenção dos resultados | J4 | AC-422, 423 | v1 |

### Relatório 09 · achados (severidade Crítica, Alta e Média tratadas como obrigatórias)

| Req | Sev. | Resumo | Jornada | ACs | Versão |
|---|---|---|---|---|---|
| audit/09 N1 | Alta | Token da box fora de `docker inspect` | J4 | AC-424 | v1 |
| audit/09 N2 | Alta | Modelo de ameaça escrito; UI honesta no modo leve | JT | AC-T19 | v1 |
| audit/09 N3 | Alta | Corrupção não trava a UI; nada de gravar a cada frame | JT | AC-T13 | v1 |
| audit/09 N4 | Alta | Nada bloqueante no pool cooperativo | JT | AC-T16 | v1 |
| audit/09 N5 | Média | Logs e diagnóstico | JT | AC-T17 | v1 |
| audit/09 N6 | Média | Assinatura estável | JT | AC-T18 | v1 |
| audit/09 N7 | Média | App dirigível por XCUITest e `ctl` | JT | AC-T01, T03 | v1 |
| audit/09 N8 | Média | SSRF consistente (navegador e HTTP) | J4 | AC-419 | v1 |
| audit/09 N9 | Média | Canal MCP velho não bloqueia relançamento | J8 | AC-806 | v1 |
| audit/09 N10 | Média | Ordem de saída correta, sem sleep no main | J8 | AC-805 | v1 |
| audit/09 N11 | Média | Imagem reproduzível no tempo | JT | AC-T21 | v1 |
| audit/09 N12 | Média | Docker a partir de app GUI (PATH, helpers) | JT | AC-T20 | v1 |
| audit/09 N13 | Média | Viewer fora do thread principal | JT | AC-T23 | v1 |
| audit/09 N14 | Média | Terminal barulhento não trava os outros | J6, JT | AC-608, T07 | v1 |
| audit/09 N15 | Média | Hooks sem `python3` | JT | AC-T24 | v1 |
| audit/09 N16 | Alta (isolado) | Worktree montada no mesmo caminho absoluto | J4b | AC-457 | v1.1 |
| audit/09 N17 | Alta (isolado) | Credenciais do CLI no container | J4b | AC-453 | v1.1 |
| audit/09 N18 | Baixa | Token fora do env de Xvfb, Openbox, xdotool | J4 | AC-424 | v1 |
| audit/09 N19 | Baixa | Timeout de Docker não deixa órfão | JT | AC-T22 | v1 |

### Decisões do 00 sem requisito numerado nos relatórios

| Decisão | Jornada | ACs | Versão |
|---|---|---|---|
| P2 · UI em inglês | JT | AC-T04 | v1 |
| P3 · Importação do Orca só leitura (removida por P21) | J1 | - | removido |
| P4 · Agentes continuam após ⌘Q; ícone na barra de menus | J8, J6 | AC-801 a 804, 606 | v1 |
| P5/P6 · Modo leve v1, isolado v1.1 | J4, J4b | AC-401 a 425; AC-451 a 463 | v1 / v1.1 |
| P7 · CLI logado no container | J4b | AC-453, 454, 463 | v1.1 |
| P8 · Motion nos três momentos | J3, JT | AC-310, AC-T25 | v1 |
| P9 · Criar sessão abre o agente rodando | J3, J11 | AC-307, 1101 | v1 |
| P10 · Sessões limpas | J11, J3 | AC-1101 a 1106, 1108, 305 (v1); AC-1107 (v1.1) | v1 / v1.1 |
| P11 · Seção "Sessions" e "New Clean Session" (⇧⌘N) | J11, J1 | AC-1101, 1105, 305, 120 | v1 |
| P12 · Pai envia mensagem com Enter só a filhos que criou | J4b, J5 | AC-464, 505 | v1.1 |
| P13 · Proxy genérico configurável, sem teto | J4, J10 | AC-417, 418, 1004, 118 | v1 |
| P14 · Aprovação visual por tela | JT | AC-T26, T25 | v1 |
| P15 · Padrões de 01 §8 adotados | J1, J8, J11 | AC-304, 801, 804, 1101, 1103 | v1 |
| T6 · Sem leitura de clipboard por OSC 52 | JT | AC-T05 | v1 |
| T8 · Viewer noVNC | J4 | AC-408 | v1 |
| T9 · Egress sidecar desde a v1 | J4 | AC-417, 418, 419, 424 | v1 |
| T11 · Colar só por clique explícito | J5 | AC-505 | v1 |
| T12 · Ferramentas do CLI antigo via MCP; conflito com a skill global | J1, J4 | AC-113, 402, 415, 416 | v1 |
| T13 · `agentbox ctl` e `accessibilityIdentifier` | JT | AC-T01, T03 | v1 |
| T14 · Fora do escopo | — | — | out |
| T5 · Overlays dentro da janela | J1, J3, J8, JT | AC-101, 301, 801, T06 | v1 |

### Critérios com origem fora das listas acima

Cobrem itens P1 dos relatórios 01 e 07 ou passos das jornadas. Entram na v1 porque a jornada não fecha sem eles.

| AC | Origem | Versão |
|---|---|---|
| AC-116 | audit/07 #39 (permissão de notificação negada) | v1 |
| AC-120 | J1 passo 5 (fim do onboarding no composer) | v1 |
| AC-302 | audit/04 §5.2 (pré-seleção do composer) | v1 |
| AC-314 | audit/01 D2 (CLI deslogado ou ausente no lançamento) | v1 |
| AC-503 | audit/01 F6, audit/05 (d) ("Create PR" explícito) | v1 |
| AC-506 | audit/08 C2 (push por HTTPS com helper do `gh`) | v1 |
| AC-605 | audit/07 #12, audit/04 §5.6 (⌘J, ⌘1…9, ⌘K) | v1 |
| AC-610 | audit/07 #26 (VoiceOver) | v1 |
| AC-612 | audit/07 #11 (BEL vira não lido) | v1 |
| AC-810 | audit/09 §2.2 (crash do daemon, cold restore) | v1 |
| AC-811 | T1 (protocolo versionado do daemon) | v1 |
| AC-904 | audit/08 N24 ("Loaded in this run") | v1 |
| AC-909 | R2 SEM #1 ("Insert Skill or Agent…", TA-411) | v1 |
| AC-T02 | PP-1 (cada ação registrada tem teste) | v1 |
| AC-T08 | audit/07 #9 (Shift+Enter e atalhos de edição) | v1 |
| AC-T14 | T2 (backup antes de migração) | v1 |
| AC-T15 | T2 (importador do JSON atual) | v1 |
| AC-428 | audit/01 R9, PP-15 (regras do worker) | v1 |
| AC-T27 | Queixa 7 do dono (R2 §6): nada sai da caixa na largura mínima | v1 |
| AC-T28 | R3 §5.6 (controle de fatia futura não renderizado) | v1 |
