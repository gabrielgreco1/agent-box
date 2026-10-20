# 01 · Produto

Racky rebuild · capítulo 01 · 2026-10-16
**Revisado após R1–R3 em 2026-10-16** (patches de `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`, com as decisões P11–P16 do `00`).
Depende de: `00-decisions.md` (prevalece sobre este capítulo). Fontes: `docs/rebuild/audit/01..10`, principalmente `10-review-journeys.md`.
Capítulos irmãos: `02-design-system.md`, `03-screens.md` (UI), `04-motion.md`, `05-journeys-and-acceptance.md` (jornadas e aceite), `06-terminals-and-agents.md` (daemon, lançamento, estados, biblioteca, git/GitHub), `07-computers-and-subagents.md`, `08-architecture-quality.md`.

Convenção: a spec é em português. Todo texto que aparece na interface vem em inglês, entre aspas ou em `código` (P2). Os IDs `P*` e `T*` são as decisões do `00`. Os IDs `R*.*` e `RT.*` são requisitos de `audit/10`. `PP-*` são os princípios de produto definidos aqui. Referências à auditoria levam o prefixo `audit/NN` (ex.: `audit/07 #33`, `audit/08 N3`); `NN §x` sem prefixo aponta para um capítulo da spec; `§x` sozinho, para este capítulo. Versões: `v1`, `v1.1`, `later` (depois) e `out` (fora). Atalhos na notação de 03 §21 (⇧⌘X), que é a referência.

---

## 1. Visão

O Racky é o app macOS nativo e pessoal do Gabriel para trabalhar com vários agentes de código ao mesmo tempo. Cada **sessão** junta terminais reais (Claude Code, Codex, OpenCode ou shell) num diretório: uma worktree de um repositório, um checkout existente, uma pasta comum ou uma pasta nova criada pelo app. Quando um agente precisa de um navegador, ele delega para **subagentes**, e cada subagente ganha o próprio **computador** Docker, com navegador persistente, terminal, captura de rede, proxy configurável e um viewer onde o Gabriel assume o controle quando aparece um captcha ou um login.

A v1 tem dois objetivos, e só vale se cumprir os dois:

1. **Substituir o Orca no dia a dia.** Worktree por tarefa, agente já rodando ao criar a sessão, estado de cada agente visível, notificação quando alguém precisa dele, agentes que continuam vivos quando o app fecha.
2. **Fazer o lote de scraping melhor que o CLI `racky` antigo.** Quinze subagentes em paralelo, cada um com o próprio computador, com evidência de cada afirmação, logs e uso de proxy que o agente não consegue adulterar e takeover sem perder a página.

O que justifica sair do Orca é o que o Orca não tem: computador Docker por subagente, takeover que pausa só o filho afetado, reqlog e diário como evidência, proxy configurável por computador e os dois modos de subagente (leve e isolado). Essa parte não pode chegar pela metade.

## 2. Para quem

Um usuário: o Gabriel. Não há contas, times, billing, marketplace nem sincronização.

O perfil de uso, medido na máquina dele (`audit/10 §0`), define os padrões do produto:

| Sinal | Consequência no produto |
|---|---|
| 7 repositórios e 111 worktrees no Orca em 2026-10-16 (6 e 103 na auditoria), em `~/orca/workspaces/<repo>/<nome>` | Worktree por tarefa é o fluxo central. A primeira abertura importa isso do Orca (P3). |
| Claude roda com `--dangerously-skip-permissions`, Codex com `--dangerously-bypass-approvals-and-sandbox` | O perfil padrão herda essas flags, com indicador visível. "Needs input" quase sempre é fim de turno ou pergunta, raramente permissão. |
| Automations, SSH, Mobile, Chat UI e hibernação desligados | Ficam fora da v1 (T14). |
| O Codex bate 100 % da janela de 5 h | Medidor de uso na v1; troca Claude ↔ Codex na v1.1. |
| 15 boxes criadas em 12 minutos com o CLI antigo; runs de até 391 MB | Capacidade, fila e retenção são requisitos, não detalhes. Meta de carga: 15 headless + 2 desktop numa VM Docker de 28 GiB (07 CS-132). |
| Mac com 48 GB, 14 núcleos; Docker Desktop instalado e parado; sem Colima | Usar o contexto Docker ativo e oferecer iniciar o Docker. |
| Git por HTTPS com `gh auth git-credential`; `ssh-agent` vazio | Push no host funciona pelo helper; dentro do container não há credencial (v1.1 resolve com broker). |
| Statusline própria do Claude lê `rate_limits`; `notify` do Codex ocupado pelo Codex Computer Use; hooks globais do Orca em `~/.claude/settings.json` | A configuração global dos CLIs pertence a outros donos e nunca é alterada. |

## 3. Princípios de produto

São regras de decisão. Quando um capítulo técnico ou de UI tiver dúvida, estes princípios desempatam, sempre abaixo das decisões do `00`.

**PP-1 · Tudo que clica funciona.** Nenhum controle visível é decorativo. Cada botão, item de menu e atalho executa a ação que o rótulo promete ou fica desabilitado com o motivo no tooltip e, quando existir, a ação que destrava ("Docker isn't running · Start Docker"). Não há "em breve", fixtures, dados de demonstração nem estados fingidos. Estados desconhecidos aparecem como desconhecidos ("Status unavailable"). Controle de uma fatia ou versão futura não é renderizado; desabilitar não basta. Toda interação passa por uma ação do registro central (`ActionID`), com efeito declarado e um teste com clique ou atalho real (AC-T02). Origem: queixa do dono ("tudo que eu clico parece que não funciona"), `audit/01 A6`, R3 §7.

**PP-2 · Nada automático sem clique explícito.** O app nunca:
- digita ou cola no PTY de um agente por conta própria. Colar no prompt só acontece quando o usuário clica num botão que diz isso, como "Paste into Claude", com bracketed paste e sem Enter (T11, R5.1). Única exceção (P12, v1.1): o agente pai envia uma mensagem completa, com Enter, a um subagente que ele mesmo criou (`agent_message`), e cada envio fica na timeline do filho. Para qualquer outro terminal vale T11;
- retoma agentes depois de reboot ou crash do daemon (R2.5);
- sobe computadores em massa ao abrir, nem depois de reboot (R8.3);
- faz push, abre PR, faz merge, apaga worktree ou branch sem confirmação;
- escreve em configuração global dos CLIs (PP-6).

Criar uma sessão e ver o agente começar a rodar (P9) **é** o clique explícito. O prompt inicial vai como argumento do CLI, não por digitação (T11, R3.1).

**PP-3 · O harness original é preservado.** O agente roda na TUI oficial do CLI, num PTY real. O app não tem chat próprio, não reescreve a saída e não substitui o loop do modelo (`audit/01 A3`).

**PP-4 · Um passo do pedido ao agente rodando.** Criar sessão abre o terminal com o agente escolhido já rodando (P9). Criar terminal numa sessão idem. Sessão limpa sai em um clique, sem diálogo ("New Clean Session", ⇧⌘N; P10, P11).

**PP-5 · Agentes não morrem com o app.** ⌘Q, crash da UI ou atualização do app não matam agentes (P4). O que segue rodando fica visível num item da barra de menus. Reboot mata os processos; o app devolve layout, último scrollback e um botão "Resume" por pane.

**PP-6 · A configuração global dos CLIs é do usuário.** `~/.claude/settings.json`, `statusLine`, hooks, skills globais, `~/.codex/config.toml`, `notify` e `hooks.json` não são tocados. Tudo que o Racky precisa entra por lançamento: `--settings`, `--mcp-config`, `--plugin-dir`, `--session-id`, `-c` (T10, R1.5). A única escrita em pastas globais acontece por ação explícita na Biblioteca (criar ou editar agente/skill, v1.1) ou ao desativar a skill `racky` concorrente, sempre com backup e desfazer.

**PP-7 · Convivência com o Orca.** Os dois apps rodam juntos por semanas. A importação é só leitura. Nenhum arquivo do Orca é escrito. Os hooks globais do Orca ficam inertes nos terminais do Racky porque as variáveis `ORCA_*` não chegam a eles. Apagar uma worktree que o Orca também registra exige aviso (P3, RT.1).

**PP-8 · Ação longa tem estado no lugar onde foi pedida.** Criar worktree, provisionar computador, construir imagem e retomar em lote mostram progresso no próprio card, linha ou pane, e terminam em sucesso ou em erro com uma ação ("Try Again", "Use Existing Branch"). Nada de spinner sem fim nem alerta genérico (RT.3).

**PP-9 · Uma falha local não derruba a janela.** Banco corrompido é restaurado do backup com um banner. Um painel com erro mostra "Try Again" no próprio painel. A UI nunca fica inteira desabilitada (T2).

**PP-10 · Evidência antes de afirmação.** Resultado de subagente com dado coletado cita o request ou o arquivo de onde veio. O que não tem evidência aparece marcado como "Not verified". Logs e uso do proxy são gravados por um processo fora do alcance do agente (T9).

**PP-11 · Segurança honesta.** O modelo de ameaça fica escrito e a UI não promete mais do que entrega. Um agente no Mac (modo leve) tem os mesmos poderes do usuário, e o app não finge isolá-lo. O container protege o Mac do navegador e, no modo isolado, do próprio agente. Detalhe em `08-architecture-quality.md`.

**PP-12 · Orca como referência, inglês na UI.** O visual, as interações e o microcopy seguem o Orca (P1, P2). Divergir do Orca pede um motivo escrito na spec. Toda tela só fecha com captura do Racky lado a lado com a referência versionada do Orca e OK explícito do dono (P14, AC-T26).

**PP-13 · Teclado primeiro e app dirigível.** Toda ação frequente tem atalho e entra na palette (⌘J). Todo controle tem `accessibilityIdentifier`, e existe um canal de automação opt-in (`racky ctl`) para testes e agentes dirigirem o app ponta a ponta (T13).

**PP-14 · Barato por padrão.** Panes ocultos não desenham. Miniaturas fora da tela param. Lotes usam headless. Computador de subagente é efêmero, mas o perfil de navegador fica. Nada roda em segundo plano sem aparecer no item da barra de menus.

**PP-15 · O worker não age em nome do dono.** Subagentes e workers preferem APIs e dados oficiais a raspar telas, e nunca compram, pagam, mandam mensagem a terceiros, criam conta ou alteram configuração de conta. Quando a tarefa parece exigir isso, o worker para e abre um pedido de ajuda (`help_request`, `kind: choice`). A regra vai na skill de orquestração e no template de brief entregues por lançamento (07). Origem: `audit/01 R9`, R2 §3 item 5.

---

## 4. Escopo

Critério (`audit/10 §13`): a v1 entra em uso quando substitui o Orca **e** supera o CLI antigo. A v1 sai em uma fatia 0 de fechamento e quatro fatias de produto, e cada fatia de produto termina com um dia de uso real. As decisões P6, P13 e T14 fixam o resto. O recorte das fatias segue a recomendação de `review/R3-implementability.md` §9–§10 (P16).

Regras que valem para todas as fatias:
- **Controle de fatia futura não é renderizado.** Cada fatia liga suas superfícies por feature flag. Desabilitar não basta (PP-1).
- **Aprovação visual por tela (P14).** Toda tarefa visual só fecha com captura do Racky lado a lado com a referência do Orca e OK explícito do dono, registrado em `docs/evidence/ui/<tarefa>/` (AC-T26).
- Cada tarefa entrega o que a Definition of Done de 08 pede, e o canal `ctl` mínimo existe desde a primeira tarefa (Fatia 1).

### 4.1 v1

**Fatia 0 · Fechamento** (antes da primeira linha de código)
- Errata aplicada: nomes canônicos, IDs de motion `M-xxx`, `accessibilityIdentifier` de 02 §17 / 03 §22, atalhos de 03 §21 (P16).
- Pacote de referência do Orca 1.4.219 versionado em `docs/rebuild/reference/orca-1.4.219/` (screenshots por superfície, `manifest.json` ligando cada PNG à tela de 03 e ao identificador do Racky), extraído por script e nunca de um scratchpad (P14).
- Tabela de ações da Fatia 1 (ID, rótulo, atalho, efeito, estado desabilitado com motivo, teste). Controle sem linha na tabela sai da UI.
- Spikes S-01 a S-07 de R3 §6.1 (launchd com socket no home, SwiftTerm, peer auth em dev e CI, reattach, hooks por lançamento do Claude e do Codex, env de login, `ctl screenshot`), com evidência em `docs/evidence/spikes/`.
- `design/` antigo e código antigo fora do caminho do build; versões fixadas (XcodeGen, SwiftTerm, GRDB, Geist com `OFL.txt`).

**Fatia 1 · Casca, terminais e sessões limpas** (permite largar o Orca em trabalho sem computadores)
- Janela, sidebar (seções "Projects" e "Sessions"), tab row, splits, overlays, design system. Motion dos momentos 1 e 2 de P8: overlays M-101/M-102/M-103, toast M-110, linha pendente M-204, tabs M-301/M-302/M-304, split M-306/M-307, ignição M-503/M-504/M-506, com Reduce Motion primeiro. O momento 3 (agente usando computador) entra na Fatia 3.
- Projeto → Sessão → Tabs → Panes → Terminais. Arquivar e apagar terminal, sessão e worktree. "Open in…" (R5.2).
- **Sessões limpas** em um clique ("New Clean Session", ⇧⌘N, ou o "+" da seção "Sessions"), promovíveis com "Move to Project…" (P10, P11).
- Composer (⌘N): com projeto, "New Worktree", "Existing Worktree" ou "Main Checkout"; sem projeto, "New Folder" ou "Choose Folder…". Agente já rodando com o prompt como argumento (P9, R3.1–R3.3). Quick Launch (⌥⌘N), ⌘T para shell, ⌥⌘T para o agente padrão.
- Perfis de lançamento para Claude, Codex, OpenCode e shell, mais "Custom Command"; ambiente do shell de login; padrão sem permissões.
- Daemon `rackyd`: na fatia nasce como filho do app, com o mesmo protocolo (modo degradado de 06). LaunchAgent, sobrevivência a ⌘Q e crash e item na barra de menus entram na última tarefa da fatia, se o spike S-01 passar (P4, T1).
- Captura do ID nativo; reabertura com "Interrupted" e "Resume" com flags regeneradas (R2.2, R8.1).
- Sem hooks nesta fatia: o card mostra o estado do processo, e a atividade do agente aparece como `unknown` ("Status unavailable").
- Onboarding mínimo: CLI detectado, logado ou não.
- `racky ctl` mínimo (`state`, `ui tree`, `ui action`, `ui wait`, `screenshot`), registro de ações e `accessibilityIdentifier` em todo controle desde a primeira tarefa (T13).

**Fatia 2 · Atenção, GitHub e convivência com o Orca**
- Estado de agente via hooks por lançamento: Claude completo; Codex com os eventos que os hooks dele oferecem, ou marcado `estimated` se o spike S-05 não fechar sem escrita global (T10). Estado do pai considera os filhos (R6.1). Última mensagem por terminal (R2.1).
- Notificações do sistema, Inbox (⇧⌘I) com lista simples de eventos, badge no Dock, "Next Needing Attention" (⇧⌘A, R6.2), ⌘J, ⌘1…9.
- Chip de PR e estado dos checks via `gh`; "Create PR" com `gh pr create` (`audit/05 d`, R5.4 parcial). Nota de status da sessão (R2.4).
- Colar no prompt por ação explícita (R5.1).
- Retomada em lote ("Resume Agents…", R2.5). Aba "Conversations" (⇧⌘H) com Resume.
- Importação do Orca (P3, R1.3) e convivência (RT.1).
- Onboarding completo como checklist de diagnóstico (R1.1), com detecção de CLIs, `gh`, Docker e conflitos (R1.5–R1.8).
- Orçamento de desempenho medido (R6.3).

**Fatia 3 · Computadores, modo leve** (supera o CLI antigo)
- Docker e imagem preparados pelo app, contexto ativo, capacidade e fila (R1.2, R4.7, T7).
- MCP do computador em qualquer terminal Claude; skill de orquestração do app entregue por lançamento; conflito com a skill global `racky` resolvido (R4.1, R1.6, T12).
- Reserva de computador por nome (`boxes_reserve`) e reivindicação pelo filho (`box_claim`) (R4.2). Navegador headed em Xvfb (R4.4). Pedido de ajuda assíncrono (`help_request`, `help_wait`) (R4.3).
- Runtime com as ferramentas do CLI antigo: `exec`, `curl_cffi`, `http_request`, navegador por seletor, reqlog com corpos, diário, proxy configurável e render quando o proxy escolhido suportar (T12, P13).
- Egress sidecar por computador: aplica o proxy escolhido para aquele computador, grava reqlog e uso do proxy, bloqueia SSRF e mantém o token fora do env (T9). Sem teto de gasto e sem corte automático (P13).
- Viewer noVNC a ≥ 20 fps (07 CS-401) com "Take Over" e "Hand Back" e nota ao devolver (T8, R4.9). Aba "Computers" do painel direito (⇧⌘C) (R4.8). Momento 3 de motion (M-601 a M-612).
- Resultado e logs no host, `box_collect`, validação de evidência; parada, remoção e arquivamento de computadores (R4.5).
- Regras do worker na skill de orquestração e no brief (PP-15).
- Lote (fan-out) como entidade própria (`Batch`), com tabela de alvos, consolidado e notificação "lote concluído" com resumo (`audit/08` N7, N21). Fica na v1 porque 07 o especifica como v1 (CS-323/324, `batch_*`); isso substitui a recomendação R1 D-06 (v1.1).

**Fatia 4 · Uso e biblioteca mínima**
- Status bar com janelas de uso do Claude e do Codex, computadores, RAM e uso do proxy quando o provedor informar (R10.1, R10.4 parcial).
- Biblioteca só leitura das fontes nativas, ativação aditiva por sessão (R9.1 parcial), "Open in Editor".
- "Insert Skill or Agent…" na palette (03 §8): cola a referência no prompt do pane focado, por colagem com clique e sem Enter (`audit/05 e3`, T11). Decisão final: v1, Fatia 4, junto da Library.

**Transversal à v1**: `racky ctl` e `accessibilityIdentifier` (T13), SQLite com backup (T2), Swift 6 estrito (T3), assinatura estável (T4), logs e diagnóstico local (08), aprovação visual por tela (P14).

### 4.2 v1.1

- **Modo isolado** (P5, P6): CLI no container como tab do app, CLI já logado (P7), `agent_spawn` e `agent_wait` (o resultado volta em `agent_wait` e em `box_collect`), worktree por filho, broker de git, kit de skills e agentes só leitura, estado do CLI em volume, sobrevivência a quit com `dtach` (R4.6, R8.5, `audit/08` N1, N12–N17, N20).
- Mensagem do pai ao filho que ele criou, com Enter, registrada na timeline (`agent_message`, P12). Worker leve do app (`agent_spawn` com `mode: "light"`), `agent_stop` e `ask_parent` (R1 D-07).
- Handoff leve "Continue in…", detecção de limite, transferência de computador, paridade do Codex (MCP por `-c`, filhos por hooks) (R7.1–R7.4).
- Diff só leitura na aba Source Control (a lista de alterações já existe na v1, 03 §10.2); "Send failures to agent"; eventos e notificações de PR e checks (R5.3–R5.5).
- Criar e editar agentes e skills com backup e histórico; quando a mudança vale (R9.2–R9.4).
- Inbox "Since you were away" completo (R2.3).
- Custo e tokens por terminal (R10.2). Assistente de limpeza (R10.4).
- Dormir sessão e fixar; item da barra de menus com ações; prioridade por tipo de pedido e lembrete único (R6.4–R6.6).
- Manter o Mac acordado (R8.4).
- `.worktreeinclude`/`orca.yaml` e script de setup (R3.4, R3.5). Clonar repositório. `git init` ao criar projeto a partir da pasta de uma sessão limpa. "Move Folder into Project…".
- Importar runs do CLI antigo como histórico (R1.4).
- Detector de filho parado (10 min, configurável); mensagem a um filho específico (R4.10, R4.11).

### 4.3 later

Reprobe com "o que mudou" quando um CLI atualiza (R1.9). Filtros da sidebar (R2.6). Anexos no composer (R3.6). Mesma tarefa em N agentes (R3.7). Comentários por linha no diff (R5.6). Comentar em PR (`audit/05 d4`). Responder pela notificação (R6.7). "Back to original agent" com diff (R7.5). Troca de conta Claude/Codex (R7.6). Abrir no login (R8.6). Lint da biblioteca (R9.5). Histórico de uso do proxy exportável (R10.5). Lotes agendados. `claude --remote-control` como alternativa ao mobile. Hibernação automática. Página de tarefas. OpenCode com paridade (computador, filhos). Conversor de agentes entre clientes. XLSX. Biblioteca de perfis de navegador com backup e restore. Modo privado. WebRTC. Tema claro (os tokens já nascem em pares, ver 02). Settings por projeto (`audit/04 F7b`; na v1, `worktreeRoot` e perfil padrão do projeto vêm da importação e do composer). Templates de sessão e de layout (`audit/01` sug. 9). Arrastar pane para reorganizar e arrastar tab até a borda para fazer split (`audit/05 c5`, `audit/04 F5c`). Fixar e colorir tab, terminal flutuante e kanban de agentes (`audit/07` #35, #50). Visualizador da memória automática do Claude (`audit/05 e5`). Renomear a conversa nativa (`audit/01 E8`). Promover uma execução a agente salvo (`audit/01 G7`). Sparse checkout e parent workspace no composer (`audit/04 F2b`). "Create from" com URL de GitLab, Linear ou Jira (`audit/04 F2c`).

### 4.4 Fora

Do `00` (T14): Orca Mobile, Automations, Chat UI, SSH remoto, captura e datasets da v1 atual, cerimônia de hash e revisão de lançamento, handoff transacional, sistema de memória próprio.

Do `00` (P13): teto de orçamento de proxy em qualquer nível (computador, sessão, lote, dia, mês), corte automático por gasto, botão "Add $1.00" e avisos de 80 %. O app só configura o proxy e mostra o uso quando disponível. Reabrir só por decisão do dono.

Também fora (`audit/10 §11` e `§13`): painel de Source Control com stage e commit, navegador embutido e design mode, computer use de apps macOS, orchestration do Orca, editor Monaco e Quick Open de arquivos, tela de grants de credencial por UUID, `ControlBroker` persistido e journal de atualização de imagem. Multiusuário, billing, marketplace e runtime remoto (`audit/01 A10`). Gravação ou replay da sessão do computador (`audit/01 N9`; o reqlog, o diário e a timeline já servem de evidência). Opção "Redirect" da skill global antiga, que escreveria fora do app (R1 D-11).

---

## 5. Modelo de domínio

### 5.1 Visão geral

```
Project (git | folder) ──1:N── Worktree
   │                              │
   └──0:N── Session ──0..1────────┘          Session sem projeto = clean session, seção "Sessions" (P10, P11)
              │
              ├──1:N── Tab ──1:1── Layout (árvore de splits) ──1:N── Pane
              │                                                       │ conteúdo: Terminal | ComputerViewer
              ├──1:N── Terminal ──1:1── LaunchSpec ──N:1── LaunchProfile
              │           │
              │           └──1:N── AgentRun (main) ──0:N── AgentRun (filho, recursivo)
              │                                                │
              ├──0:N── Computer ──0..1── owner AgentRun ───────┘
              │           ├── HelpRequest (0:N)
              │           └── RunFolder: result, journal, request log, command log
              ├──0:N── SessionActivation ──N:1── CatalogItem (agente, skill, instrução)
              └──0:N── AttentionItem / InboxEvent

Secret (Vault)   ProxyProfile   UsageMeter   OrcaImport   Setting
```

Regras de identidade: todo objeto tem um UUID estável. Nome nunca é identidade (dois filhos "Researcher" são dois objetos). O que aparece na UI é sempre um título, separado do identificador nativo do CLI e do título OSC (`audit/01 B16, B17`).

A persistência é SQLite (T2). Os nomes de tabela e coluna finais ficam em `08-architecture-quality.md`; aqui ficam os campos que o produto precisa.

### 5.2 Project

Um repositório Git ou uma pasta raiz que agrupa sessões.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | UUID | |
| `kind` | `git` \| `folder` | `folder` serve para pastas sem Git que o usuário quer agrupar |
| `name` | texto | Padrão: nome da pasta; editável |
| `rootPath` | caminho | Para `git`, o checkout primário |
| `gitRemote` | URL normalizada, sem credencial | Detectada; habilita chip de PR |
| `defaultBaseRef` | ref | Detectada (`origin/main`); usada pelo composer |
| `worktreeRoot` | caminho | Onde nascem worktrees novas. Padrão: `~/orca/workspaces/<repo>/` durante a transição (R3.2) |
| `branchPrefix` | texto | Padrão: usuário Git (`gabrielgreco1/`) |
| `defaultProfileId` | ref LaunchProfile? | Sobrepõe o padrão global |
| `copyIgnoredFiles` | lista de padrões | v1.1 (R3.4): `.env*` e `.worktreeinclude` |
| `setupScript` | comando + política `wait`/`parallel` | v1.1 (R3.5) |
| `importedFromOrca` | bool + id de origem | P3 |
| `pinned`, `sortOrder`, `collapsed` | | UI persistida |
| `createdAt`, `archivedAt` | datas | Arquivar projeto esconde sem apagar nada do disco |

Invariantes: `rootPath` é único entre projetos ativos. Remover um projeto do app nunca apaga arquivos.

### 5.3 Session

A unidade de trabalho que o usuário vê na sidebar: um diretório e os terminais e computadores que trabalham nele.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | UUID | |
| `projectId` | ref Project? | `nil` = **clean session** (P10) |
| `kind` | `worktree` \| `checkout` \| `folder` \| `clean` | `clean` = pasta gerenciada pelo app ou pasta escolhida sem projeto. O schema de 08 usa estes quatro valores (R1 K-81) |
| `title` | texto | Visível; renomeável inline |
| `titleSource` | `auto` \| `user` | Título automático vem do prompt ou de nome gerado; vazio volta ao automático |
| `directoryPath` | caminho | cwd padrão dos terminais |
| `worktreeId` | ref Worktree? | Para `kind = worktree` ou `checkout` |
| `managedDirectory` | bool | `true` quando o app criou a pasta (`~/Racky/sessions/<nome>` ou worktree nova). Só pasta gerenciada pode ir para o Lixo pelo app |
| `statusNote` | texto curto + autor (`user` \| run id) + data | R2.4. Linha 3 do card (03 §2.6) |
| `initialPrompt` | texto? | O prompt do composer, guardado para handoff e resumo |
| `origin` | `composer` \| `cleanQuick` \| `orcaImport` \| `promoted` | Para diagnóstico |
| `lifecycle` | ver §6.1 | |
| `aggregateState` | derivado | Pior estado entre os agentes e computadores (§6.3) |
| `unread` | bool | Algo terminou ou mudou desde a última vez que o usuário olhou |
| `lastViewedAt`, `lastActivityAt` | datas | Ordenação e "há 7 h" |
| `pinned` | bool | v1.1 (R6.6) |
| `proxyProfileId` | ref ProxyProfile? | Proxy padrão para os computadores da sessão; `nil` herda o padrão global (§5.15, P13) |
| `createdAt`, `archivedAt`, `deletedAt` | datas | |

Invariantes:
- Uma sessão tem pelo menos um diretório válido. Se a pasta sumir do disco, a sessão fica em `missing` com "Locate…".
- Duas sessões ativas podem apontar para o mesmo diretório (por exemplo, dois checkouts escolhidos), mas o composer avisa.
- Sessões limpas aparecem na seção "Sessions" da sidebar, separada de "Projects", com o mesmo card, estados e agentes (P11). Nome automático sem prompt: adjetivo + substantivo (`quiet-harbor`); renomear a sessão não renomeia a pasta (P15). Com prompt, o título é legível ("Fix ArcGIS pagination") e pasta e branch usam o slug kebab-case.
- Promover uma sessão limpa (v1): "Move to Project…" liga a sessão a um projeto existente sem mover arquivos; no mesmo overlay, "New Project from This Folder" cria um projeto `folder` (ou `git`, se a pasta já for repositório) com a pasta como raiz. Na v1.1: "Move Folder into Project…", só com todos os terminais da sessão parados, e `git init` opcional ao criar o projeto (R1 K-34).

### 5.4 Worktree

| Campo | Tipo | Notas |
|---|---|---|
| `id`, `projectId` | | |
| `path` | caminho | |
| `branch`, `baseRef` | | `baseRef` = de onde foi criada; base do diff |
| `isPrimary` | bool | O checkout original; nunca apagável pelo app |
| `createdByApp` | bool | Só worktree criada pelo app é removível sem aviso extra |
| `registeredInOrca` | bool | Lido na importação e reconferido; dispara aviso ao apagar (PP-7) |
| `git` | derivado | ahead/behind, dirty, conflito, detached |
| `pr` | derivado | número, estado (`draft`, `open`, `merged`, `closed`), checks (`passing`, `failing`, `pending`), review |
| `archivedAt` | data | |

### 5.5 Tab, Layout e Pane

- **Tab** (`id`, `sessionId`, `order`, `title`, `titleSource`, `layout`). Cada sessão tem as próprias tabs; trocar de sessão troca o conjunto de tabs, como no Orca.
- **Layout**: árvore binária de splits (orientação, proporção) cujas folhas são panes. Persistido ao fim do gesto, nunca a cada frame.
- **Pane** (`id`, `tabId`, `content`). `content` é `terminal(terminalId)` ou `computerViewer(computerId)`. O painel direito (Source Control, Checks, Computers, Conversations, Context) e as páginas (Library, Computers, Settings) não são panes.

Invariantes: um terminal aparece em no máximo um pane por vez (`audit/01 B7`). Fechar um pane que contém terminal encerra o processo, com confirmação se ele estiver rodando, e ⇧⌘T reabre a tab fechada, relançando com `--resume` quando houver ID nativo (`audit/07 #33`). Redimensionar, recolher, maximizar ou trocar de tab nunca recria o PTY.

### 5.6 Terminal

| Campo | Tipo | Notas |
|---|---|---|
| `id`, `sessionId` | | |
| `provider` | `claude` \| `codex` \| `opencode` \| `shell` \| `custom(argv)` | `custom` = "Custom Command" (argv livre, sem estado de agente; 06 §2) |
| `title`, `titleSource` | | Título do usuário; o título OSC é campo à parte e nunca sobrescreve o do usuário |
| `oscTitle`, `oscCwd` | derivado | Do PTY |
| `launchSpec` | LaunchSpec | O que foi pedido (§5.7) |
| `resolvedArgv`, `resolvedEnvKeys` | | Como foi lançado de fato (sem valores de segredo) |
| `cwd` | caminho | |
| `placement` | `local` \| `container(computerId)` | `container` só no modo isolado (v1.1) |
| `ptySessionId`, `daemonProtocol` | | Vínculo com o `rackyd` |
| `nativeConversationId` | texto? | Capturado em todo lançamento (R2.2) |
| `processState` | ver §6.2 | |
| `exitCode`, `exitedAt` | | |
| `envSecretCount` | inteiro | O pane mostra "env: 2 secrets" quando > 0 |
| `fontSize` | número? | Zoom por pane (`audit/07 #6`) |
| `createdAt`, `deletedAt` | | |

### 5.7 LaunchSpec (lançamento declarativo)

O que o usuário pediu, salvo antes do processo nascer e usado para regerar tudo na retomada (R8.1). Nenhum lançamento depende de um diretório temporário sobreviver.

| Campo | Notas |
|---|---|
| `provider`, `profileId` | |
| `model`, `permissionMode`, `effort` | Sobreposições do perfil |
| `extraArgs`, `envOverrides` | |
| `initialPrompt` ou `initialPromptFile` | Vai como argumento (`claude "<prompt>"`, `codex "<prompt>"`, `opencode --prompt`). Acima de 16 KiB, ou quando começa com `-`, vai por arquivo `0600` (`run/launch/<runID>/prompt.md`) referenciado no argumento (R3.1). Limiar único para 01, 05 e 06 (R1 K-12) |
| `nativeSessionId` | Claude: UUID gerado pelo app e passado em `--session-id` |
| `resumeOf` | ID nativo a retomar, quando for retomada |
| `agentDefinition` | ref CatalogItem? (`--agent`, `--agents`) |
| `sessionActivations` | Snapshot das skills e agentes ativados na sessão no momento do lançamento |
| `appIntegrations` | MCP do Racky, hooks de estado, skill de orquestração, statusline encadeada. Regerados por lançamento (T10) |
| `secrets` | Refs de Secret injetadas no env por opt-in do perfil |

### 5.8 LaunchProfile

| Campo | Notas |
|---|---|
| `id`, `name` | Ex.: "Claude · Opus · Skip permissions" |
| `provider` | |
| `model`, `permissionMode` | `dangerous = true` quando o perfil pula permissões; o pane e a tab mostram o indicador |
| `extraArgs`, `env`, `addDirs` | |
| `secretRefs` | Segredos injetados no env (opt-in) |
| `scope` | `global` \| `project(projectId)` |
| `isDefault` | Um padrão por provider e escopo |
| `importedFromOrca` | `agentDefaultArgs` do Orca viram perfis na importação: "Claude · Skip permissions" e "Codex · Bypass approvals", com o detalhe "Imported from Orca" |

Resolução: terminal → projeto → global. O adapter de cada CLI converte o perfil em argv e valida as flags contra a versão instalada (06).

### 5.9 AgentRun

Uma conversa de agente observada pelo app. O agente principal de um terminal é um AgentRun; cada subagente também.

| Campo | Notas |
|---|---|
| `id` | |
| `terminalId` | O terminal onde o run principal vive; para filhos nativos, o terminal do pai |
| `parentRunId` | Recursivo; profundidade > 1 suportada no modelo (`audit/08 N3`) |
| `kind` | `main` \| `nativeSubagent` \| `teammate` \| `appWorkerLight` \| `appWorkerIsolated` (os dois últimos são v1.1 para spawn pelo app) |
| `harness` | `claude` \| `codex` \| `opencode` |
| `providerSessionId`, `providerAgentId`, `agentType` | Do hook (`agent_id`, `agent_type`) |
| `label` | Nome humano ("phoenix-az"), quando houver |
| `activity` | ver §6.3 |
| `lastMessage`, `lastMessageAt` | R2.1 |
| `lastJournal` | Última nota DOING/BLOCKED do diário (subtítulo da linha do filho) |
| `computerId` | Computador que ele controla, quando houver |
| `resultRef`, `verification` | Caminho do `result.json` e resumo da validação (`verified`, `partial`, `notVerified`) |
| `resumedFromRunId` | Retomada cria um run novo ligado ao anterior, com o mesmo `providerSessionId` |
| `startedAt`, `endedAt`, `endReason` | `completed`, `failed`, `stopped`, `interrupted` |

**Subagente** não é uma entidade separada: é um AgentRun com `parentRunId`. O que muda por modo:

| | Modo leve (v1) | Modo isolado (v1.1) |
|---|---|---|
| Onde roda o CLI | No Mac, dentro do processo do pai (subagente nativo) | No container, como processo próprio |
| Aparece como | Linha filha na sidebar e no card; não é terminal digitável | Tab de terminal real, pendurada no pai |
| Computador | Container com navegador (headless ou desktop), controlado via MCP | Na mesma box do CLI, em container irmão, com o lease fora do alcance do CLI (07 §6.1; "mesmo container" de P5 lido como "mesma box", R1 D-08) |
| Quem cria | O pai, com as ferramentas do Racky (`boxes_reserve`; o subagente nativo reivindica com `box_claim`) | O pai via `agent_spawn` ou o usuário pela UI |
| Login do CLI | O do Mac | Já logado no container (P7) |
| Mensagens do pai | Não se aplica (o filho nativo vive no processo do pai) | `agent_message` com Enter, só para filhos que o pai criou, registrado na timeline (P12) |

Detalhe em `07-computers-and-subagents.md`.

### 5.10 Computer (box)

Na UI o termo é **"Computer"** ("Container" no modo isolado). "Box" aparece só em nomes de ferramentas MCP, logs e pastas (`boxes_reserve`, `box_claim`, `~/Racky/runs/<sessão>/<computer>/`) (P15).

| Campo | Notas |
|---|---|
| `id` | |
| `label` | Nome humano único na sessão ("phoenix-az"); é o que o pai e o filho usam |
| `sessionId` | Toda máquina pertence a uma sessão |
| `reservedByRunId`, `ownerRunId` | Quem reservou e quem reivindicou (R4.2). Sem dono = disponível para o primeiro `box_claim` com o rótulo |
| `subagentMode` | `light` \| `isolated` |
| `display` | `http` \| `headless` \| `desktop`. "Headless" = navegador headed em Xvfb sem stream (R4.4). É o nome do parâmetro nas ferramentas de 07 |
| `streaming` | bool, separado do modo: fechar o viewer não muda o modo (`audit/01 M8`) |
| `lifecycle` | ver §6.4 |
| `control` | `agent` \| `human` \| `none`, com `epoch` |
| `imageDigest`, `containers` | `runtime`, `work` (v1, `exec`) ou `agent` (isolado, v1.1, substitui `work`), `egress` (R1 K-66) |
| `profileVolume` | Perfil do navegador; sobrevive à remoção do container |
| `runFolder` | `~/Racky/runs/<sessão>/<label>/` com `work/` (inclui `result.json`), `logs/`, `transcript/` e `box.json` (07 §2.8) |
| `proxyProfileId` | ref ProxyProfile? escolhido para este computador (sobrepõe sessão e global); `nil` = saída direta pelo egress (§5.15, P13) |
| `proxyUsage` | Uso informado pelo provedor, quando disponível; sem teto (P13) |
| `resources` | CPU e memória pedidos; uso medido |
| `ephemeral` | `true` para computador de subagente: o container sai no fim, o perfil fica |
| `createdAt`, `lastUsedAt`, `stoppedAt`, `removedAt` | |

**HelpRequest** (pedido de ajuda humana):

| Campo | Notas |
|---|---|
| `id`, `computerId`, `runId` | |
| `kind` | `captcha` \| `login` \| `mfa` \| `download` \| `choice` \| `permission` \| `other` |
| `reason`, `url` | O motivo real escrito pelo agente vai para a notificação (corrige `audit/02 #18`) |
| `state` | `open` → `takenOver` → `resolved`; `open` → `declined` \| `cancelled` \| `expired` (07 CS-432) |
| `humanNote` | Nota ao devolver (R4.9) |
| `createdAt`, `takenAt`, `resolvedAt`, `reminderSentAt` | Lembrete único é v1.1 (R6.4) |

**Registros do run** (gravados pelo sidecar, só leitura para o agente, PP-10): `JournalEntry` (`kind` PLAN/DOING/FOUND/BLOCKED, `text`, `evidenceIds`, `at`), `RequestLogEntry` (`id`, `source` browser/curl/python/render, método, URL, status, tamanho, referência ao corpo), `CommandLogEntry` (comando, exit, duração, saída), `ProxyUsage` (quando o provedor informa).

### 5.11 CatalogItem (Biblioteca: agentes, skills, instruções)

A Biblioteca indexa os formatos nativos por referência. Conteúdo é lido sob demanda e nunca copiado para o banco.

| Campo | Notas |
|---|---|
| `id` | Derivado de fonte + caminho |
| `kind` | `agent` \| `skill` \| `instruction` (`CLAUDE.md`, `AGENTS.md`) \| `plugin` |
| `source` | `~/.claude/agents`, `~/.codex/agents`, `~/.claude/skills`, `~/.agents/skills`, plugins instalados, `.claude/` do projeto, `appOnly` |
| `clients` | Em quais CLIs funciona |
| `path`, `hash`, `name`, `description`, `meta` | Frontmatter relevante (model, tools, skills, mcpServers) |
| `activation` | `alwaysOn` (global, carregado pelo próprio CLI) \| `session` (aditivo, por lançamento) \| `appOnly` (guardado fora das pastas globais, v1.1) |
| `usedBySessions` | Derivado das SessionActivations ativas |

**SessionActivation** (`sessionId`, `catalogItemId`, `addedAt`, `appliesFrom: nextLaunch`): liga um item a uma sessão. Vale a partir do próximo lançamento; o app oferece "Relaunch with resume" (R9.1, R9.2). Se a versão instalada do CLI não permite desligar um item global por lançamento, a UI diz isso em vez de prometer.

A skill de orquestração do Racky e o MCP do computador **não** são CatalogItems do usuário: entram sempre por lançamento como `appIntegrations`.

### 5.12 AttentionItem e InboxEvent (notificações)

**AttentionItem** é algo que pede ação do usuário. Alimenta o badge do Dock (que conta só prioridade 1–2), o item da barra de menus, "Next Needing Attention" e as notificações do sistema.

| Campo | Notas |
|---|---|
| `id`, `kind` | Ver tabela abaixo |
| `priority` | 1 (mais alta) a 4 |
| `sessionId`, `terminalId`, `runId`, `computerId` | Para navegar ao pane certo |
| `title`, `body` | Inglês; corpo sem dado sensível na tela bloqueada |
| `createdAt`, `seenAt`, `resolvedAt` | Resolver em qualquer lugar tira o item de todas as superfícies |
| `systemNotified` | Se virou notificação do macOS (suprimida quando a janela está focada naquele pane) |

| `kind` | Prioridade | Versão |
|---|---|---|
| `helpRequest` (captcha, login, MFA, download, choice) | 1 | v1 |
| `needsInput` (pergunta ou permissão do agente) | 2 | v1 |
| `failed` (agente, processo com exit ≠ 0, computador morto ou OOM) | 2 | v1 |
| `dockerStopped` quando algo precisa de computador | 2 | v1 |
| `done` (turno concluído, não lido) | 3 | v1 |
| `childBlocked` (BLOCKED no diário) | 2 | v1 |
| `checksFailed` | 2 | v1.1 |
| `usageLimitReached` | 2 | v1.1 |
| `tokenExpiring` (setup-token a 30 dias) | 3 | v1.1 |
| `childStalled` | 3 | v1.1 |
| `batchDone` (resumo: concluídos, falhos, duração, uso do proxy; `audit/08 N21`) | 3 | v1 |

A prioridade ordena a fila e a palette na v1. A política por tipo (modo foco, lembrete único em 3 minutos) é v1.1 (R6.4).

**InboxEvent** (v1 simples, v1.1 completo): registro de "o que aconteceu" para a Inbox e para "Since you were away": turnos concluídos, perguntas, computadores parados e uso do proxy. PR e checks entram na v1.1 (R5.4); na v1 o chip atualiza sem evento. Tem `readAt` e agrupa por sessão.

### 5.13 Secret

Valores ficam cifrados no banco (AES-GCM) com a chave mestra num único item do Keychain (Vault, 08 AR-510/511); nenhum valor em claro no disco. "Token no Keychain" de P7 é lido como "protegido pela chave do Keychain" (R1 D-10).

| Campo | Notas |
|---|---|
| `id`, `name` | Ex.: "ZYTE_API_KEY", "BRIGHTDATA_PROXY" |
| `kind` | `proxyCredential` \| `envVar` \| `claudeSetupToken` (v1.1) \| `codexBoxIdentity` (v1.1, volume) \| `githubPAT` (v1.1) \| `boxMasterKey` (interno) |
| `scope` | `global` \| `project` |
| `delivery` | `sidecarOnly` (credencial de proxy: nunca chega ao agente) \| `profileEnv` (opt-in por perfil) \| `boxFileReadOnly` (v1.1) |
| `createdAt`, `lastUsedAt`, `expiresAt` | |
| `importedFrom` | Ex.: `~/orca/projects/racky/.env` |

Regras: nenhum valor em evento, log, histórico, crash report ou export. Nunca copiar refresh tokens do Mac nem montar o token do `gh` (P7). O token de cada computador é derivado da chave mestra e entregue por arquivo `0400` montado só leitura, nunca por env (T9, 08 AR-512).

### 5.14 Outros objetos

- **UsageMeter** (`provider`, `window` 5h/7d, `percent`, `resetsAt`, `source`, `observedAt`): alimentado pela statusline encadeada do Claude e pelos `rate_limits` dos rollouts do Codex (R10.1).
- **OrcaImport** (`sourcePath`, `importedAt`, contagens, mapa id Orca → id Racky): torna a importação repetível sem duplicar.
- **ConversationIndexEntry** (`provider`, `nativeId`, `cwd`, `title` ou primeira mensagem, `updatedAt`, `openElsewhere`): só metadados dos transcripts dos CLIs, para a lista "Conversations". Transcript nunca é copiado.
- **Batch** (v1, `audit/08 N7`, 07 CS-323/324): alvos, template de brief, consolidado `results.jsonl`, resumo ao concluir. Um lote pertence a uma sessão; os computadores do lote levam `batch_id`.

### 5.15 ProxyProfile (P13)

Na UI o termo é "Proxy"; no domínio e em 07, `ProxyProfile`.

O proxy é configuração do usuário, não do app. Nenhum provedor é padrão; Zyte é só um preset.

| Campo | Notas |
|---|---|
| `id`, `name` | Ex.: "Zyte API", "Residential US" |
| `type` | `http` \| `https` \| `socks5` \| `providerApi` (modo API de um provedor; preset Zyte, inclusive render, quando configurado) |
| `host`, `port` | |
| `credentialRef` | ref Secret (`proxyCredential`); nunca entra no container |
| `geo` | Opcional (país ou região, quando o provedor aceita) |
| `capabilities` | `render` (o modo API renderiza página), `usageReporting` (o provedor informa uso) |
| `isDefault` | No máximo um padrão global; sem padrão, computadores saem direto pelo egress |

Resolução: computador → sessão → padrão global. O agente pede um computador; quem escolhe o proxy é o usuário (Settings, composer ou menu do computador), e o pai pode citar um proxy pelo nome em `boxes_reserve` quando o usuário o liberou para agentes. O egress aplica o proxy e registra o uso que o provedor informar; quando não há informação, a UI diz "Usage unavailable". Sem teto, sem corte automático, sem "Add $1.00" (P13).

---

## 6. Máquinas de estado

Os estados abaixo são o contrato entre domínio e UI. Os sinais que causam cada transição (hooks, eventos do daemon, eventos Docker) estão em 06 e 07. Rótulos entre aspas são o texto de UI.

### 6.1 Sessão (ciclo de vida)

```
            ⌘N / clean "+" / import
                     │
                     ▼
  ┌──────────── creating ────────────┐  (worktree: preparing → fetching → creating → launching)
  │ erro              │ ok           │
  ▼                   ▼              │
failedToCreate ──► active ◄──────────┘
 "Try Again"        │  ▲ "Wake"(v1.1)
 "Use Existing      │  │
  Branch"           ▼  │
                 sleeping (v1.1)
                    │
         "Archive"  ▼
                 archived ──"Restore"──► active
                    │
         "Delete"   ▼
                 deleted (registro some; arquivos só com escolha explícita)

active ── pasta sumiu ──► missing ──"Locate…"──► active
```

| Estado | Rótulo | Significado | Saídas |
|---|---|---|---|
| `creating` | linha pendente com fase ("Fetching origin…", "Creating worktree…", "Starting Claude…") | O composer fechou; trabalho em segundo plano | `active`, `failedToCreate` |
| `failedToCreate` | erro no card + ações | Nada parcial fica para trás (rollback de worktree incompleta) | "Try Again", "Use Existing Branch", "Create Without Fetching", "Discard" |
| `active` | — | Estado normal | `sleeping`, `archived`, `missing` |
| `sleeping` (v1.1) | "Sleeping" | Processos parados, computadores parados, IDs guardados para retomar | "Wake" relança com `--resume` |
| `archived` | some da lista principal; aparece em "Archived" | Processos e computadores parados após confirmação; worktree, arquivos, perfis e run folders mantidos | "Restore", "Delete" |
| `missing` | "Folder not found" | O diretório não existe mais | "Locate…", "Delete" |
| `deleted` | — | Registro removido. Para worktree criada pelo app, oferece remover worktree e branch, com checagem de dirty e de branch não publicada e aviso "This worktree is also open in Orca." (03 §16.5). Para pasta gerenciada de sessão limpa, move a pasta para o Lixo. Pasta escolhida pelo usuário nunca é apagada. | — |

Arquivar ou apagar uma sessão com processos rodando pede confirmação listando agentes e computadores afetados.

### 6.2 Terminal (processo)

```
          create
            │
            ▼
        launching ──(isolado, v1.1)──► containerPhases: pullingImage → creatingContainer → mounting → signingIn
            │ primeiro byte                                                  │
            ▼                                                                ▼
         running   (app reaberto: a view reanexa com snapshot + stream; reanexar não é estado)
            │
   ┌────────┼───────────────┬───────────────────┐
   ▼        ▼               ▼                   ▼
exited(0) exited(n≠0)    killed           interrupted
"Exited"  "Exited with   "Stopped"        (daemon perdeu o PTY: reboot ou crash)
          code <n>"                        último scrollback esmaecido + "Resume"

launching ── erro de spawn ou de injeção ──► failedToStart "Couldn't start"
   │        │               │                   │
   └────────┴──"Restart"/"Resume"───────────────┘──► launching
```

| Estado | Rótulo | Notas |
|---|---|---|
| `launching` | placeholder de ignição M-503 (só se o primeiro byte passar de 300 ms; senão M-506) | Checklist com as etapas reais |
| `failedToStart` | "Couldn't start" | Erro de spawn ou de injeção; ações "Try Again", "Open Agent Settings", "Copy Details" (03 §4.6) |
| `containerPhases` (v1.1) | "Pulling image 42%", "Creating container", "Mounting workspace", "Signing in" + "Cancel" | Só modo isolado (`audit/07 #43`) |
| `running` | — | Processo vivo no daemon. Com o app fechado, continua `running` |
| `exited(0)` | ponto cinza "Exited" | Saída preservada |
| `exited(n≠0)` | ponto vermelho "Exited with code <n>" + overlay "Terminal exited" com "Close", "Restart" e "Resume Conversation" | Só para código ≠ 0 (`audit/07 #10`) |
| `killed` | "Stopped" (pelo usuário) ou "Killed (<SIGNAME>)" (sinal externo) | |
| `interrupted` | "Interrupted" + "Resume" | Nada retoma sozinho (PP-2) |
| `containerStopped` (v1.1) | "Container stopped" + "Restart Container" | Diferente de processo que saiu |

Fechar o app não muda o estado do processo. A view é que se desanexa e reanexa. "Daemon indisponível" é estado de UI (banner "Lost connection to the background service. Reconnecting…"), não de processo. O schema de 08 usa estes nomes em `snake_case` (R1 K-79).

### 6.3 Agente (atividade)

Vale para o AgentRun principal de cada terminal de agente e para cada subagente. Shell e "Custom Command" não têm atividade. Este é o conjunto canônico para todos os capítulos (R1 K-78): 02, 04, 06, 07 e o schema de 08 (`snake_case`) usam estes nomes. `estimated` não é estado: é uma marca para OpenCode e para o Codex sem hooks confiáveis.

| Estado | Rótulo de UI | Entra quando | Sai quando |
|---|---|---|---|
| `starting` | "Starting" | Processo lançado, sem evento de sessão ainda | Primeiro evento de sessão |
| `working` | "Working" | Prompt enviado ou ferramenta em uso | Fim de turno, pedido de input, falha |
| `needsInput` | "Needs input" (subtipo: `question`, `permission` ou `other`) | O agente pergunta ou pede permissão | O usuário responde (novo prompt ou permissão concedida) |
| `waitingOnSubagents` | "Waiting on subagents" | O turno terminou, mas há filhos rodando ou computador com pedido de ajuda aberto (R6.1) | Último filho termina → `done`; algum filho pede ajuda → continua aqui e o filho fica `needsInput` |
| `done` | "Done" (não lido em negrito até ser visto) | Turno concluído sem filhos ativos | Novo prompt → `working` |
| `failed` | "Failed" | Erro do agente, limite de uso atingido (`StopFailure`), processo com exit ≠ 0 | Novo prompt ou relançamento |
| `blocked` | "Blocked" | Subagente com `BLOCKED` no diário (07 CS-260) | Nova nota DOING ou fim |
| `interrupted` | "Interrupted" (tooltip "Stopped when your Mac restarted.") | O processo morreu por reboot ou crash do daemon; filho interrompido no reboot | "Resume" ou "Ask Parent to Relaunch" |
| `idle` | sem rótulo, ponto neutro | `done` visto e sem atividade há 30 min, ou agente recém-iniciado sem prompt (após `SessionStart`) | Novo prompt |
| `unknown` | "Status unavailable" (tooltip com o motivo) | O CLI ou a versão não emitem os eventos necessários, os hooks ficaram calados além da janela de 06, ou a fatia ainda não tem hooks (Fatia 1) | Evento de hook válido |
| `stalled` (v1.1) | "Stalled?" | Filho sem chamada de ferramenta nem nota de diário há 10 min, configurável (R4.10) | Qualquer atividade |

Subagente no modo leve: `starting` no `SubagentStart`, `working` nas chamadas, `needsInput` quando o computador dele tem pedido de ajuda aberto, `blocked` com `BLOCKED` no diário, `done` ou `failed` no `SubagentStop`. O estado do computador (`queued`, `provisioning`…) aparece ao lado, na linha do computador (§6.4).

**Agregação** (card da sessão, linha do projeto, badge): pior estado vence, na ordem
`needsInput` > `failed`/`blocked` > `working` > `waitingOnSubagents` > `done` não lido > `interrupted` > `starting` > `done` lido > `idle` > `unknown`.
Pedido de ajuda de computador entra como `needsInput` com prioridade 1.

### 6.4 Computer (box)

Dois eixos: ciclo de vida do container e controle.

**Ciclo de vida**

```
reserve/claim
      │
      ▼
   queued ("Waiting for memory · 3 of 15 queued") ──cancel──► removed
      │ capacidade livre
      ▼
 provisioning (image → container → browser ready)
      │ ok                      │ erro
      ▼                         ▼
    ready ◄────────────┐      failed ("Try Again", "Show Log")
      │  agente usa    │
      ▼                │
    inUse ─────────────┘ (sem atividade)
      │ dono terminou / "Stop"
      ▼
   stopped (perfil e run folder mantidos) ──"Start"──► provisioning
      │ efêmero ou "Remove"
      ▼
   removed (container e volume de trabalho saem; perfil sai só por ação explícita; run folder fica)

Qualquer estado ── reconciliação ao abrir sem registro ──► orphan (listado com tamanho, "Clean Up")
```

| Estado | Rótulo | Notas |
|---|---|---|
| `queued` | "Queued"; longo: "Waiting for memory · 3 of 15 queued" | A ferramenta MCP devolve esse estado ao pai (R4.7) |
| `provisioning` | caixa isométrica com fases (M-601; fila: M-602) | Etapas reais expostas pelo serviço |
| `ready` | "Ready" | |
| `inUse` | "In use by <agente>" | Borda viva no viewer (M-604) |
| `stopped` | "Stopped" | Docker parado também leva para `stopped` com aviso; nada reinicia sozinho |
| `failed` | "Failed" + motivo (OOM, exit, health) | Gera AttentionItem. É `failed` em todos os capítulos (nunca `error`) |
| `removed` | — | |
| `orphan` | "Orphaned" | Encontrado por label sem registro no banco; nada apagado sem confirmação, exceto efêmeros marcados (`audit/09 §2.5`) |

**Controle**

| Estado | Rótulo | Transições |
|---|---|---|
| `agent` | "<Agent> is using this computer" | "Take Over" → `revoking` |
| `revoking` | "Requesting control…" | ACK do runtime → `human` |
| `human` | "You're in control" + "Hand Back" (⇧⌘R) | "Hand Back" com nota opcional → `agent` |
| `helpRequested` | "Needs you · <kind>: <reason>" | é `agent` com HelpRequest aberto; "Take Over" → `revoking`; "Decline…" → `agent` |
| `none` | "Idle" (pill) | Sem dono |

Tomar o controle de um computador pausa só o agente dono dele. Irmãos seguem (`audit/01 O5`). Fechar o viewer não resolve o pedido nem devolve o controle (`audit/01 P11`).

### 6.5 Pedido de ajuda

`open` → ("Take Over") → `takenOver` → ("Hand Back") → `resolved`. `open` → ("Decline…", com motivo) → `declined`. `open` → (agente terminou ou cancelou) → `cancelled`. `open` → (prazo do pedido vencido, 07) → `expired`. Reconectar o viewer não resolve nada. Depois de reboot, pedidos abertos continuam visíveis (R8.2).

---

## 7. Glossário

Termo de UI em inglês, com a definição usada em toda a spec. Termos técnicos (hook, adapter, broker, sidecar, PTY, daemon) não aparecem na UI fora de "Diagnostics" e "Advanced". Rótulos de botão e menu seguem Title Case (02 §18); a microcopy exata de cada tela está em 03.

| Termo de UI | Definição |
|---|---|
| **Project** | Repositório Git ou pasta raiz que agrupa sessões. |
| **Session** | Um diretório de trabalho com seus terminais, agentes e computadores. Aparece como card na sidebar. |
| **Clean session** | Sessão sem projeto e sem Git (`kind = clean`), criada em um clique por "New Clean Session" (⇧⌘N) numa pasta gerenciada (`~/Racky/sessions/<name>`) ou, pelo composer, numa pasta escolhida ("Choose Folder…"). Fica na seção "Sessions" (P11). O termo "Scratch" não é usado. |
| **Projects / Sessions** (seções da sidebar) | "Projects" lista projetos com suas sessões; "Sessions" lista as sessões limpas (P11). |
| **Worktree** | Worktree Git criada para uma tarefa. Mantém o termo do Git. |
| **Primary** | O checkout original de um projeto; nunca é apagado pelo app. |
| **Composer** | Overlay de criação de sessão (⌘N): "Project", "Where", "Create from", "Agent", "Profile", "Prompt" e "Advanced" (03 §6). |
| **Create from** | Base da worktree nova: ref, branch, `#123` ou URL de PR/issue. |
| **Where** | Onde a sessão trabalha. Com projeto: "New Worktree", "Existing Worktree", "Main Checkout". Sem projeto: "New Folder", "Choose Folder…" (03 §6.1). |
| **Quick Launch** | Popover do "+" da tab row (⌥⌘N) que abre um agente ou perfil numa tab nova, já rodando. ⌘T abre shell; ⌥⌘T, o agente padrão. |
| **Tab** | Grupo de panes dentro de uma sessão. |
| **Pane** | Uma área da tab com um terminal ou o viewer de um computador. |
| **Split** | Divisão de um pane (⌘D à direita, ⇧⌘D abaixo). |
| **Terminal** | Um PTY real rodando um CLI de agente, um shell ou um "Custom Command". |
| **Agent** | O CLI de IA rodando num terminal: Claude Code, Codex ou OpenCode. |
| **Subagent** | Agente filho criado por um agente. No modo leve, é linha filha na sidebar; no isolado, é tab própria. |
| **Light mode** ("On This Mac") | Subagente com CLI no Mac e só o computador no container. v1. |
| **Isolated mode** ("In Container") | Subagente com CLI e computador na mesma box (containers irmãos), como tab do app, já logado. v1.1. |
| **Computer** | Container Docker com navegador persistente, terminal, captura de rede e proxy, usado por um agente. "Box" só em ferramentas, logs e pastas (P15). |
| **Headless / Desktop / HTTP** | Modos do computador (`display`): navegador headed em Xvfb sem stream, navegador com tela ao vivo, só requisições HTTP. |
| **Viewer** | Pane que mostra a tela de um computador ao vivo. |
| **Computers** (aba do painel direito, ⇧⌘C) | Miniaturas dos computadores da sessão com URL atual, última nota do diário e uso do proxy (03 §10.4). A página global "Computers" lista todos. |
| **Take Over** | Assumir o controle do navegador de um computador (⇧⌘R). Pausa só o agente dono. |
| **Hand Back** | Devolver o controle ao agente (⇧⌘R), com nota opcional. |
| **Help request** | Pedido do agente para o humano agir (captcha, login, MFA, download, escolha, permissão). O humano pode recusar com "Decline…". |
| **Launch profile** | Configuração salva de lançamento: CLI, modelo, modo de permissão, flags, env. Perfis importados: "Claude · Skip permissions", "Codex · Bypass approvals". |
| **Skip permissions** | Indicador de perfil que pula prompts de permissão do CLI (ícone `ShieldOff` na tab e no header do pane). |
| **Ignition** | Animação e checklist de um agente sendo lançado (M-503), mostrada só se o primeiro byte passar de 300 ms (M-506). |
| **Starting / Working / Needs input / Waiting on subagents / Done / Failed / Blocked / Interrupted** | Estados de atividade do agente (§6.3). |
| **Status unavailable** | O app não consegue observar o estado daquele agente (`unknown`). |
| **Unread** | Algo mudou desde a última vez que o usuário olhou; nome em negrito. |
| **Last message** | Última frase do agente, mostrada na linha do terminal e completa no hover. |
| **Status note** | Nota curta de objetivo e progresso da sessão (linha 3 do card), editável pelo usuário e pelo agente. |
| **Resume** | Relançar uma conversa nativa pelo ID capturado, com as mesmas flags, MCP, hooks e skills. "Resume Agents…" faz isso em lote. |
| **Conversations** | Aba do painel direito (⇧⌘H) com as conversas recentes do projeto nos CLIs, com "Resume in New Tab". |
| **Next Needing Attention** | Ação (⇧⌘A) que leva ao próximo agente ou computador que precisa do usuário, em ordem de espera. |
| **Inbox** | Feed de eventos recentes e pedidos na sidebar (⇧⌘I, 03 §9.1). Na v1.1 ganha "Since you were away". |
| **Paste into <Agent>** | Ação explícita que cola um texto no prompt do agente, sem Enter. |
| **Open in…** | Abre a sessão no editor, Finder, terminal externo ou GitHub. |
| **Create PR** | Push e `gh pr create` pré-preenchido, com confirmação. |
| **Checks** | Estado dos checks do PR (passing, failing, pending). |
| **Library** | Página (⇧⌘L) com agentes, skills e perfis de lançamento; instruções e ativação por sessão ficam na aba "Context" do painel direito. |
| **Always on / This session / App only** | Escopos de ativação de um item da biblioteca. |
| **Journal** | Diário estruturado do subagente: PLAN, DOING, FOUND, BLOCKED. |
| **Network** | Aba com o request log do computador (browser, curl, Python), com corpos e "Copy as cURL". |
| **Timeline** | Visão combinada de diário, comandos, requests e mensagens do pai de um computador. |
| **Result** | O `result.json` do subagente, com cada afirmação ligada à evidência. |
| **Not verified** | Afirmação de resultado sem request ou arquivo que a sustente. |
| **Run folder** | Pasta no Mac com resultado e logs de um computador: `~/Racky/runs/<session>/<computer>/`. |
| **Proxy** | Configuração de saída escolhida pelo usuário (HTTP/HTTPS/SOCKS ou modo API de um provedor, como o preset Zyte) e dada a um computador (entidade `ProxyProfile`, P13, §5.15). |
| **Proxy usage** | Uso informado pelo provedor do proxy, quando ele informa. Não há teto nem corte automático (P13). |
| **Usage** | Medidores das janelas de uso do Claude e do Codex na status bar. |
| **Archive / Delete** | Arquivar esconde e para processos e computadores sem apagar arquivos; apagar remove o registro e oferece remover a worktree ou mover a pasta gerenciada para o Lixo. |
| **Sleep** (v1.1) | Para processos e computadores da sessão, guardando os IDs para retomar. |
| **Background agents** | O que segue rodando com o app fechado. O processo que os mantém aparece na UI como "background service" (mensagens de erro e Diagnostics). |
| **Import from Orca** | Importação só leitura de projetos, worktrees e args padrão do Orca. |
| **Diagnostics** | Checklist de ambiente (CLIs, `gh`, Docker, notificações, conflitos) e "Export Diagnostics…" (pacote sanitizado). |
| **Custom Command** | Terminal com argv livre, sem estado de agente (06). |
| **Continue in…** (v1.1) | Handoff leve: abre outro agente na mesma sessão com um brief editável. |

---

## 8. Padrões adotados pelo dono (P15)

Estes pontos não estavam no `00` original. O dono os adotou em P15; os itens 4 e 5 seguem a recomendação dos revisores (R1 D-03 e D-12, por P16), e o item 7 foi reescrito por P13.

1. **Raiz de worktrees novas**: `~/orca/workspaces/<repo>/<nome>` durante a transição, configurável por projeto (R3.2; pergunta 6 de `audit/10`).
2. **Termo de UI**: "Computer" na interface, "box" só em ferramentas, logs e pastas (`audit/07` #53 adaptado ao inglês). No modo isolado, o que o usuário vê é "Container".
3. **Sessões importadas do Orca** entram sem processo rodando; a sidebar mostra as 5 mais recentes por projeto e "Show N more".
4. **Item da barra de menus com o app fechado**: depois do ⌘Q o app continua em modo accessory só com o item da barra de menus (08 AR-108); "Quit Racky Completely" remove o ícone até reabrir. Não há helper separado.
5. **⌘Q com agentes rodando** mostra um overlay na janela (T5) com "Keep Running" (padrão), "Stop All and Quit…", "Cancel" e "Don't ask again" (`audit/09 D12`). Com "Don't ask again" marcado, ⌘Q fecha a janela e deixa o app em modo accessory. `NSAlert` só quando não há janela aberta.
6. **Nome automático de sessão limpa**: adjetivo + substantivo (`quiet-harbor`), um gerador só para sessões limpas e worktrees sem prompt; renomear a sessão não renomeia a pasta.
7. **Proxy**: nenhum proxy vem configurado por padrão (P13). Ao importar um `.env` em Settings › Credentials ("Import .env File…"), uma chave `ZYTE_API_KEY` é reconhecida e o app oferece criar um proxy com o preset Zyte. A importação dos runs antigos fica na v1.1 (R1.4).
