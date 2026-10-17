# Auditoria 01 — Inventário de funcionalidades pedidas e especificadas

Data: 16/10/2026 · Escopo: só documentação e histórico. Nenhum código foi alterado. As ressalvas declaradas pelas próprias docs vêm reproduzidas sem verificação independente.

## Fontes lidas por completo

| Sigla | Arquivo | Natureza |
|---|---|---|
| README | `README.md` | Resumo do estado (desatualizado, ver §3) |
| STATUS | `docs/STATUS.md` | Registro de checkpoints AB-032…AB-046 |
| IMPL | `docs/IMPLEMENTATION.md` | Lotes 1–4 |
| PLAN | `docs/EXECUTION-PLAN.md` | Tabela AB-001…AB-031 com estado |
| SPEC1 | `docs/spec/index.html` | Spec v1, 18 capítulos, contrato vigente |
| AC | `docs/spec/acceptance.json` | AC01–AC68 (todos `planned`) |
| BL | `docs/spec/backlog.json` | Marcos M0–M10 (todos `not_started`) |
| BASE | `docs/spec/baseline.json` | Hashes do protótipo v0.4 |
| EV | `docs/evidence/*.json` | Evidências AB-041…AB-046, hooks, validação inicial |
| T-xxx | `docs/tasks/AB-xxx*.md`, `PARALLEL-CONTRACT.md` | Entregas por feature |
| SPEC04 | `design/docs/spec.html` | Spec v0.4 (19 capítulos, “direção inicial”) |
| REV04 | `design/docs/review.html` | Revisão do protótipo v0.4 |
| DREADME | `design/README.txt` | Guia do protótipo v0.4 |
| GIT | `git log --stat` (16 commits, 2e595c4 → c4418cc) | Os commits só têm título, sem corpo |
| SKILL0 | `~/.claude/skills/agentbox/SKILL.md`, `~/orca/projects/agentbox/{README.md,templates/subagent-prompt.md}` | Skill **original** do Gabriel, que a SPEC1 cap. 02 manda migrar (rev. `1b3e84ac`). É a fonte mais concreta das capacidades de subagente |

A conversa em que o Gabriel listou as capacidades ao Codex **não está no repositório**. Também não apareceu em `~/.codex/sessions` nem em `~/Library/Application Support/Codex`; a busca por texto não achou nada. As capacidades da §2 foram reconstruídas de SKILL0, SPEC04 cap. 13 (ToolBroker), SPEC1 caps. 07–12 e das tasks AB-036/037/039/041/044. **Confirme com o Gabriel se falta algo da conversa original.**

### Legenda de status (como a doc declara)

- **feito**: a doc declara entregue e verificado, inclusive em fluxo real.
- **parcial**: código existe, com limites declarados ou só parte do requisito.
- **não validado**: código existe, mas a doc diz que falta prova real, visual, na TUI ou com daemon.
- **pendente**: planejado, sem implementação.
- **fora de escopo v1**: a spec exclui explicitamente.

Nenhum dos 68 ACs foi marcado como aceito (AC: `status: planned` em todos, `checked_at: null`). Os status abaixo vêm do texto de STATUS, PLAN e das tasks.

---

## 1. Inventário por domínio

### 1.A Contrato do produto e princípios

| # | Funcionalidade / regra | Fonte | Status | Aceite |
|---|---|---|---|---|
| A1 | App pessoal macOS (SwiftUI/AppKit) para organizar **sessões com vários terminais reais** e computadores Docker opcionais | SPEC1 cap.01; README:3 | parcial | AC03, AC10 |
| A2 | Hierarquia **projeto/pasta → sessão → terminais → execuções de agentes/subagentes → computadores opcionais**; biblioteca de agentes independente da árvore | SPEC1 cap.01/03; PLAN:7; README:5 | parcial (árvore até subagente Claude existe; projeto como entidade não) | AC04 |
| A3 | Preservar o **harness original** (TUI do CLI em PTY); nenhum chat próprio nem loop LLM substituto | SPEC1 cap.01; SPEC04 cap.01/05 | feito (princípio seguido) | AC10 |
| A4 | CLI roda no Mac e ferramentas de trabalho rodam na box. Containers compartilham o runtime Docker (não é VM por agente) | SPEC1 cap.01 | feito | — |
| A5 | O **principal de cada terminal decide** delegação e computador, dentro da política; a sessão não é um orquestrador extra | SPEC1 cap.01 | parcial (há `computer_acquire`; a delegação vem do harness) | AC19–24 |
| A6 | Todo estado exibido vem de **observação real**; sem fixtures/demos como fallback. Ausente/desconhecido/reconectando/não suportado são estados reais | SPEC1 cap.01, cap.18 (regra de texto) | parcial | AC05, AC08 |
| A7 | Direção visual inspirada no **Orca** (densidade, árvore, abas, painéis), com marca própria e logos oficiais; sem copiar conteúdo do Orca | SPEC1 cap.01/04; DREADME | parcial (Gabriel considera o resultado ruim) | AC05, AC06 |
| A8 | Biblioteca, memória e skills inspiradas no **Maestrum** | SPEC1 cap.13; README:17 | parcial | AC61–68 |
| A9 | Foco inicial: **pesquisa, coleta e validação de dados** com intervenção humana no mesmo navegador | SPEC1 cap.01; SPEC04 cap.01 | parcial | — |
| A10 | Fora de escopo v1: billing, marketplace, SaaS, colaboração multiusuário, runtime remoto | SPEC1 cap.01; SPEC04 cap.01 | fora de escopo v1 | — |
| A11 | Não prometer: contexto interno portável, PTY de filho inexistente, retomada exata após crash, captura universal de rede, desbloqueio por GUI, login eterno, custo exato | SPEC1 cap.01; SPEC04 cap.01 | regra | AC22, AC51 |
| A12 | Escopo posterior (v0.4): agendamentos recorrentes, presets de crawlers, execução remota, múltiplos computadores, automação de apps gráficos além do browser, gravação completa de sessão, modelos locais, marketplace de skills | SPEC04 cap.16 | fora de escopo v1 | — |
| A13 | Decisões “fechadas pelo usuário”: Docker; app Swift; CLIs originais; sessões multi-terminal; agentes e computadores opcionais; execução adaptativa; settings no primeiro uso; listener; .env/credenciais; OpenCode; logos reais; sidebar ajustável/recolhível; sem rótulos demo | SPEC1 cap.18 | decisão | — |

### 1.B Sessões, workspace e layout

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| B1 | Criar sessão avulsa ou a partir de pasta; sessão **funciona sem Git/projeto** | SPEC1 cap.03/05; T-003 | feito (metadados) | AC10, AC16 |
| B2 | **Renomear** sessão (título local), sem alterar native_session_id nem branch | SPEC1 cap.03/06; T-003 | feito | AC18 |
| B3 | Sessão: arquivar/restaurar (`session.create/rename/archive/restore`) | SPEC1 cap.14/15 | pendente (archive/restore não aparecem nas tasks) | — |
| B4 | **Até 5 terminais** por sessão, com splits H/V e abas; foco independente | SPEC1 cap.05; T-003 | parcial (código; aceite visual pendente) | AC03 |
| B5 | Layout padrão com 3 panes: principal grande à esquerda e dois à direita | SPEC1 cap.05 | pendente (não citado nas tasks) | — |
| B6 | Árvore de splits persistida (orientação, proporção, folhas); restaurar ao relançar; **redimensionar/recolher/maximizar/trocar aba não recria PTY** | SPEC1 cap.03; T-003 | feito (JSON atômico) | AC11 |
| B7 | Um terminal não aparece duas vezes com input independente | SPEC1 cap.03 | não validado | — |
| B8 | Encerrar terminal não apaga sessão, worktree, perfil ou histórico; fechar pane só remove a visualização | SPEC1 cap.03/06; T-003 | feito | AC13, AC16 |
| B9 | Pane encerrado conserva saída e exit code; **Reabrir** explícito | SPEC1 cap.05 | parcial | — |
| B10 | Restaurar última sessão ao abrir; **sem reexecutar comandos** | SPEC1 cap.04; README:34; T-003 | feito | AC12 |
| B11 | Janela estreita: maximizar o pane focado e manter os outros em abas; nunca reduzir a fonte | SPEC1 cap.04; T-003 | feito (código) | AC07 |
| B12 | Árvore da sidebar com sessões/terminais/agentes, atividade agregada e pedidos de ajuda; busca | SPEC1 cap.04/05; T-040 | parcial | AC04 |
| B13 | Selecionar e expandir são ações distintas (chevron expande, rótulo seleciona) | SPEC1 cap.04 | declarado em T-003 | AC04 |
| B14 | Menu contextual: renomear, mover, fechar/parar; nunca “apagar tudo” como ação primária | SPEC1 cap.04 | pendente/não validado | — |
| B15 | **Hover** (~250 ms) mostra prévia da execução; fecha em ~200 ms; foco/teclado equivalente; prévia read-only | SPEC1 cap.04/09; SPEC04 cap.06 | pendente | AC08 |
| B16 | Breadcrumb para árvores profundas; nomes não são identidade (dois “Pesquisador” separados) | SPEC1 cap.03 | parcial | AC04 |
| B17 | Nome de sessão, título OSC e título da conversa nativa são campos diferentes; OSC nunca substitui nome escolhido | SPEC1 cap.05 | parcial | AC18 |
| B18 | Inspector opcional e status discreto | SPEC1 cap.05 | parcial (inspector Git/computador) | — |
| B19 | Fechar a sessão arquiva metadados e confirma o efeito nos processos; sem exclusão em cascata | SPEC1 cap.15 | pendente | — |
| B20 | Sessões persistentes entre relançamentos; o PTY não sobrevive ao quit | README:34; T-003 | parcial | AC12 |

### 1.C Terminais (PTY) e multi-terminal

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| C1 | PTY real com SwiftTerm 1.20.0; ANSI, 256/truecolor, alternate screen, bracketed paste, Unicode, scrollback e TUIs | SPEC1 cap.06; T-002 | feito (testes PTY + smoke) | AC09 |
| C2 | Resize/SIGWINCH, Ctrl-C para o grupo foreground | SPEC1 cap.06; T-002; STATUS:7 | feito | AC09 |
| C3 | Iniciar/parar/forçar parada **explícitos**; SIGTERM ao grupo; SIGKILL só por ação explícita | T-002; T-003 | feito | AC13 |
| C4 | Resolver executável (override, PATH, NVM, diretórios comuns) sem depender do PATH do Finder | SPEC1 cap.06; T-002; T-007 | feito | AC14 |
| C5 | argv sem interpolação de shell; ambiente filtrado; `zsh -l`; TERM/COLORTERM | SPEC1 cap.06; T-002 | feito | — |
| C6 | Renderer guardado por ID (remontar view não relança) | T-002; PARALLEL-CONTRACT | feito | AC11 |
| C7 | **Serviço PTY separado** que sobrevive ao fechamento/crash do app, com reanexação por PTY ID/geração (PTYHost fora da View) | SPEC1 cap.06/14; PLAN AB-028 | pendente (o PTY vive no app) | AC12, AC58 |
| C8 | Ring buffer de scrollback com limite configurável; captura persistente de terminal só com opt-in | SPEC1 cap.06/10 | parcial (5.000 linhas fixas, em memória) | — |
| C9 | Ao sair do app, perguntar se encerra os processos; v1: política de continuar em segundo plano via serviço do usuário | SPEC1 cap.14; README:34 | parcial (só cancelar/encerrar) | — |
| C10 | Foco nativo e first responder ao selecionar pane/aba | T-007; T-006 | feito (código) | AC07 |
| C11 | Cores do emulador (#272b33 / #dadce2) sem reestilizar a saída da TUI | T-007; SPEC1 cap.04 | feito | — |
| C12 | Clipboard, seleção, menus e acessibilidade via AppKit | SPEC1 cap.06 | não documentado | AC07 |
| C13 | ⌘W fecha a superfície focada, com confirmação se encerrar trabalho ativo | SPEC1 cap.05 | pendente | — |
| C14 | Fonte monoespaçada configurável no PTY | SPEC1 cap.04 | pendente | — |
| C15 | Shell puro funciona sem projeto; “outro CLI” com executável/argv configuráveis | SPEC1 cap.06; SPEC04 cap.07 | parcial (só shell; “outro CLI” genérico não aparece) | AC10, A43 |

### 1.D CLIs: detecção, autenticação e lançamento direto do agente escolhido

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| D1 | **Novo terminal com CLI escolhido**: Claude Code, Codex, OpenCode ou shell; pasta herdada ou escolhida; worktree opcional; definição/skills compatíveis; modelo inicial quando suportado | SPEC1 cap.05; SPEC04 J2; T-003; README:9 | parcial (sem modelo inicial nem definição no fluxo básico) | AC10 |
| D2 | Distinguir: executável ausente, pasta inválida, branch colidindo, CLI sem login | SPEC1 cap.05 | parcial | AC10, AC14 |
| D3 | Probe de versão e de status de login oficial, com timeout e fora da main thread; nunca ler/copiar tokens | SPEC1 cap.06; SPEC04 cap.07; T-002; T-007 | feito para Claude/Codex; **OpenCode “não verificado”** | AC14 |
| D4 | Estados de auth: missing, unknown, configured, authenticated, expired, error, com origem e data; “Não verificado” quando não consultado | SPEC1 cap.06/15 | parcial (estados resumidos) | AC14 |
| D5 | Sem “Conectar conta” nem OAuth próprio; “Abrir terminal para autenticar” leva ao fluxo oficial | SPEC1 cap.06; SPEC04 cap.07; REV04 | parcial (não há botão “abrir terminal p/ login” documentado) | AC14, A29 |
| D6 | Tela **Clientes locais**: instalação, versão, login, verificar de novo, abrir terminal do CLI | SPEC04 cap.04 (tela 08) | parcial (fica em Configurações) | — |
| D7 | **OpenCode** é cliente de primeira classe: TUI, retomada por sessão, credenciais via comando oficial; não ler auth.json | SPEC1 cap.06 | parcial (lança e retoma por ID; sem probe de auth, sem adapter) | AC10 |
| D8 | `AdapterCapabilities` por CLI/versão (supported/unsupported/unverified + evidência + data) | SPEC1 cap.07 | parcial (`AgentIdentityCapability` só para identidade) | AC23 |
| D9 | Catálogo de modelos com dados oficiais do cliente; disponibilidade desconhecida marcada; nomes de modelo de mock nunca viram opção real | SPEC1 cap.06; SPEC04 cap.07 | pendente | AC56, A25 |
| D10 | Mais de um terminal não implica mais de uma conta; perfil de credencial independente só se o cliente suportar | SPEC1 cap.06 | regra | — |
| D11 | Lançamento de **agente salvo direto num terminal** (Claude), com plano revisável — ver 1.J | T-011/012 | parcial | AC61–68 |
| D12 | Lançamento no **mesmo terminal da box** (relançar agente sem recriar container) | T-038 | feito (código + testes PTY) | — |

### 1.E Conversas nativas: descoberta e retomada

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| E1 | Separar conversas **Descobertas no CLI / Abertas neste app / Arquivadas** | SPEC1 cap.06 | pendente (só a lista ativa do Claude) | AC15 |
| E2 | Descoberta via API/comando público; leitura limitada, sem varrer transcripts nem credenciais | SPEC1 cap.06; T-013 | parcial (só `claude agents --json`, sessões ativas) | AC15 |
| E3 | **Retomar conversa por ID** (Claude `--resume`, Codex `resume`, OpenCode `--session`) no menu, com seleção de CLI/pasta | T-013; T-045; STATUS:55 | parcial (a retomada de históricos reais nos 3 CLIs está pendente) | AC15, AC18, AC23 |
| E4 | Não sequestrar PTY de outro app (Orca etc.); conversa ativa externa só com ações suportadas (observar, attach público, fork, retomar quando encerrada) | SPEC1 cap.06 | parcial (bloqueia segundo writer interno) | AC15 |
| E5 | Reserva de escrita exclusiva por conversa até a saída do processo; duplicata recusada | T-013; T-045 | feito (dentro do processo do app) | AC15 |
| E6 | Lock entre processos e contra writer externo | T-013 | pendente (limite declarado) | AC15 |
| E7 | Persistir native_session_id, provider, cwd, tentativa e capacidades; identidade separada do título | SPEC1 cap.06; T-013 | parcial | AC18 |
| E8 | Renomear a conversa nativa é operação distinta (se o CLI suportar) | SPEC1 cap.06 | pendente | AC18 |
| E9 | Tratar `/clear` e resume que mudam o native session ID | T-040 | pendente | — |
| E10 | Contexto de agente salvo não é anexado silenciosamente a uma conversa externa retomada | T-013; T-045 | feito (regra) | — |

### 1.F Git, GitHub, worktrees e acesso a pastas

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| F1 | Pasta comum, worktree e avulso como modos de primeira classe | SPEC1 cap.06; SPEC04 cap.05 | feito | AC16, A32 |
| F2 | Branch efetiva por terminal, dirty state, remote normalizado sem credenciais; “Várias branches” na sessão | SPEC1 cap.06; T-008; T-009 | feito (código/testes) | AC16 |
| F3 | **Criar worktree** explícito (ref, nova branch, destino vazio, rollback de criação incompleta); caminhos com espaços/metacaracteres | T-008; T-009 | feito (testes) / visual pendente | AC16 |
| F4 | Sem stash/reset/clean automático; fechar terminal não remove worktree; sem fetch/push ao abrir sessão | SPEC1 cap.06; T-008 | feito | AC16, AC17 |
| F5 | **GitHub read-only**: identificar remote GitHub, consultar a auth existente, link do repo e **PR resolvido** | SPEC1 cap.06 | parcial (só link do repo; sem auth GitHub nem PR) | AC17 |
| F6 | Criar branch, push, PR e merge como ações separadas e explícitas | SPEC1 cap.06 | pendente | AC17 |
| F7 | Escolha de branch/ref existente na UI de worktree; detectar branch já usada, worktree existente e conflitos | SPEC04 cap.05; T-008 | parcial | AC16 |
| F8 | Remoção segura de worktree (T3 v0.4) | SPEC04 cap.16 T3 | pendente | — |
| F9 | Watcher de filesystem para o estado Git | T-009 (não existe) | pendente (só refresh manual/foco) | — |
| F10 | Acesso explícito a pastas protegidas (TCC/Documents) via NSOpenPanel + **bookmark** de escopo; “Reautorizar pasta…” | T-031; STATUS:47 | não validado (persistência após relançar sem conferência) | AC09, AC16, AC58 |

### 1.G Biblioteca de agentes salvos

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| G1 | Área permanente, independente das sessões; lista compacta com **busca, favoritos e filtros por compatibilidade** | SPEC1 cap.13 | parcial (favoritos/filtros não documentados) | — |
| G2 | **Criar** agente: nome, descrição, instruções, CLI/modelo preferidos, skills padrão, política de memória, recursos permitidos; salvar não inicia execução | SPEC1 cap.13; T-005 | parcial (modelo, política de memória e recursos não aparecem) | AC61 |
| G3 | **Editar/duplicar/arquivar** com revisão imutável; execuções em andamento continuam na revisão antiga | SPEC1 cap.13; T-005; T-010 | feito (código/testes) | AC61, AC67 |
| G4 | Abas **Instruções, Memória, Skills, Histórico** na página do agente | SPEC1 cap.13; SPEC04 cap.09 (Memória/Histórico/Boxes/Skills) | parcial | — |
| G5 | **Histórico navegável**: sessões, terminais, execuções, computadores, perfis, resultados e revisão que rodou; vazio fica vazio | SPEC1 cap.13; T-010; T-012 | parcial (registro só após `.running`; abre sessão/terminal) | AC64, A36 |
| G6 | **Usar agente**: escolher sessão/terminal, nova tarefa ou retomada, revisar memória/skills e lançar no harness original | SPEC1 cap.13; T-012 | parcial (só Claude; “retomada” do agente não existe) | AC68 |
| G7 | **Promover execução a agente salvo** (só instruções e memória revisadas) | SPEC1 cap.13 | pendente | — |
| G8 | Importar definições existentes (Claude/Codex/OpenCode) preservando origem/hash; converter só o que o adapter entende | SPEC1 cap.13; SPEC04 cap.09 | pendente (importa skills, não agentes) | AC25, A37 |
| G9 | Definição não ganha computador automaticamente | SPEC1 cap.13 | regra | — |
| G10 | Avatar escolhido para agente pessoal, sem logo falso de provedor | SPEC1 cap.04 | pendente | AC06 |
| G11 | Preset **Web scraping** (cria ou abre agente Claude com `webscraping-expert`) | T-036 | feito (código) | — |
| G12 | “Usar novamente” = nova tarefa ou retomada suportada; não promete ressuscitar o processo | SPEC1 cap.13 | parcial | AC68 |

### 1.H Memória (AI memory)

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| H1 | Memória com título, conteúdo, **tipo** (preferência, conhecimento verificado, procedimento, nota de tarefa), **escopo** (agente, projeto, tarefa, preferência global, perfil), fonte, autor, datas, validade, revisão | SPEC1 cap.13; T-010 | feito (modelo/UI) | AC62 |
| H2 | Criar, editar, pesquisar, selecionar, arquivar, excluir; revisões imutáveis | SPEC1 cap.13; T-005; T-010 | feito (pesquisa não documentada) | AC62 |
| H3 | Escopo respeitado: memória de outro projeto/perfil não entra sem seleção | SPEC1 cap.13; T-010 | feito (Core) | AC26, AC63, A38 |
| H4 | **Preview do contexto** antes do lançamento, com remoção individual; limite (200 KB) com erro explícito, sem truncar | SPEC1 cap.13; T-010; T-011 | feito | AC63 |
| H5 | **Fila de revisão de sugestões do agente** (nada vira instrução global automaticamente) | SPEC1 cap.13 | pendente | — |
| H6 | Resumo que preserva links para a fonte quando passa do limite | SPEC1 cap.13 | pendente | — |
| H7 | Excluir impede reuso futuro, mas não promete apagar o que já foi enviado | SPEC1 cap.13; T-010 | feito | AC62 |
| H8 | Escopos projeto/tarefa/perfil vêm de IDs verificados do workspace (hoje a chave é digitada pelo usuário) | T-010 | parcial | AC26 |
| H9 | **Memória da tarefa** (TaskContext: objetivo, critérios, decisões, fatos com evidência, progresso/cursor, artefatos, perguntas, estado do browser, próximos passos) | SPEC04 cap.09 | pendente (não migrou para a SPEC1 como entidade de UI) | — |
| H10 | Evidência de sites, cookies e segredos nunca viram memória/instrução | SPEC1 cap.13; SPEC04 cap.09 | regra | — |

### 1.I Skills

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| I1 | Catálogo com nome, descrição, origem, versão/hash, compatibilidade por harness | SPEC1 cap.13; PLAN “Skills” | parcial (compatibilidade por harness não mostrada) | AC25 |
| I2 | **Importar SKILL.md** como dados (sem executar scripts/hooks), SHA-256 | T-005 | feito | AC65 |
| I3 | Importar pasta e descobrir diretórios autorizados | SPEC1 cap.13 | parcial (pacote auxiliar só no preset de scraping, T-036) | AC65 |
| I4 | Visualizar SKILL.md e recursos referenciados antes de ativar | SPEC1 cap.13 | parcial | — |
| I5 | Seleção padrão na definição e ajustável por execução, mostrando a origem da seleção | SPEC1 cap.13 | parcial | — |
| I6 | Skill removida ou incompatível bloqueia ou exige retirar a seleção explicitamente | SPEC1 cap.13 | não documentado | — |
| I7 | **Ativação nativa** no Claude via `--plugin-dir` (snapshot por execução, `/agentbox-<run>:<name>`) | T-032 | não validado (catálogo interativo real não testado) | AC66 |
| I8 | Pacote completo (arquivos auxiliares) congelado por hash, com limites e filtro de segredos | T-036 | feito (testes) | — |
| I9 | Skills no **Codex e OpenCode** | T-011; T-032; STATUS:44 | pendente (export-only) | AC66 |
| I10 | UI distingue “salvo / exportável” de “ativado no CLI” | SPEC1 cap.13 | parcial | AC66 |
| I11 | Skill entregue ao **contexto inicial de subagentes Claude** (SubagentStart additionalContext, partes de 8 KB) | T-036; T-043; EV ab043-child-skill-context | feito (probe real `-p`), TUI não validada | — |

### 1.J Lançamento revisado de agente salvo

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| J1 | `AgentLaunchPlan` com argv, env, texto integral, SHA-256, revisão, proveniência de memórias/skills; o usuário revisa antes de iniciar | T-011; T-012 | feito (código) | AC63 |
| J2 | Contexto materializado em `context.md` 0600, com digest conferido; Claude via `--append-system-prompt-file` | T-011 | feito | — |
| J3 | Binding persistido; restart explícito revalida hash, executável e argv; nunca autorestart | T-011; T-012 | feito | AC67 |
| J4 | Histórico gravado só após `.running(pid:)`; rollback em falha | T-012; T-038 | feito | AC64 |
| J5 | Codex/OpenCode/shell: só export/copiar contexto, com motivo exibido | T-011; T-012 | parcial (por decisão) | AC66 |
| J6 | Nenhuma API digita texto num PTY já ativo | T-011; PARALLEL-CONTRACT | regra | AC56 |
| J7 | Revisão cabe em 1000×650 (sheet de 550 pt) | T-006; T-045 | não validado (só inspeção estática) | AC07 |

### 1.K Subagentes: identidade, árvore e eventos

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| K1 | Registrar filhos por **eventos verificáveis do harness** (nunca texto do terminal) | SPEC1 cap.07; T-016; T-034 | feito (Claude) | AC19, AC22 |
| K2 | **Gate de identidade**: dois filhos do mesmo tipo em paralelo, chamadas atribuídas ao filho certo; senão “Identidade por subagente indisponível” | SPEC1 cap.07; BL M5 | parcial (Claude: hook PreToolUse assinado; teste com 2 filhos em Docker; TUI não validada) | AC19, AC20 |
| K3 | Hooks Claude SessionStart/SubagentStart/SubagentStop com HMAC por execução, inbox 0600, opt-in “Observar subagentes do Claude” | T-034; T-040; EV claude-native-hooks | feito (smoke real) | — |
| K4 | **Sidebar sessão → terminal → subagente**, só com filhos autenticados; detalhe com ID nativo, origem, horários e navegação até o pai | T-040 | não validado (sem conferência visual) | AC04, AC22 |
| K5 | Filho sem PTY próprio aparece como atividade, nunca como terminal digitável | SPEC1 cap.05/07 | feito (regra no código) | AC22 |
| K6 | **Worker independente** (CLI separado com PTY e relação declarada) como alternativa | SPEC1 cap.07 | pendente | AC24 |
| K7 | Subagentes **Codex** (hooks/app-server threads) e **OpenCode** | SPEC1 cap.07; T-016; EV ab044 | pendente | AC19, AC23 |
| K8 | Reserva de capacidade pelo principal para filhos ainda não criados (expira) | SPEC1 cap.07 | pendente | — |
| K9 | Fim do subagente: registrar resultado, revogar controle, aplicar política de parada; pedido de ajuda pendente não é descartado | SPEC1 cap.07; T-044 | parcial (revoga e para a box auto-iniciada; “resultado” não é registrado) | AC21 |
| K10 | Intervir num filho não pausa os irmãos; parar o principal respeita o cancelamento real do harness e mostra filhos ainda ativos | SPEC1 cap.07; T-044 | parcial | AC40 |
| K11 | Controle individual, steering (`childSteering`) e troca de harness por filho | SPEC1 cap.07; T-040 | pendente | — |
| K12 | Reconciliação de pais “ativos” após relançar; inbox cheio/rotação | T-040; T-034 | parcial | AC58 |
| K13 | Exibir modelo confirmado, tarefa, recursos efetivos, atividade e computador do agente/subagente | SPEC1 cap.05 | parcial (modelo/tarefa ausentes) | — |

### 1.L Computadores Docker: runtime, política e ciclo de vida

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| L1 | Detectar runtime (Docker Desktop, Colima…) e arquitetura; probe com timeout; o app usa conexão Docker própria (contexto `colima-agentbox-dev`) | SPEC1 cap.08; T-004; STATUS:13,17 | feito (Colima dev) | — |
| L2 | Instalação, downloads e termos visíveis no setup; licença não aceita por checkbox genérico | SPEC1 cap.08 | pendente (instalação foi manual, via Homebrew) | AC44 |
| L3 | Container HTTP por terminal (python slim, hardening, labels de ownership) | T-004 | feito; depois substituído/complementado pela imagem browser | AC29 |
| L4 | Imagem browser `agentbox-browser` (Playwright 1.63, Chromium, Xvfb/Openbox, XTEST), ARM64, base fixada por digest | T-019/020; runtime README | feito (smoke arm64) | AC30, AC37 |
| L5 | Volume `/data` por computador (profile, workspace, downloads, checkpoint); parar preserva | T-019/020; T-021 | feito | AC34, AC35 |
| L6 | Hardening: read-only, cap-drop ALL, no-new-privileges, PIDs/shm/CPU/mem, porta só em loopback, sem socket Docker | T-021; runtime README; SPEC1 cap.08/14 | feito | AC50 |
| L7 | Token bearer por computador no Keychain, entregue por env-file temporário | T-021 | feito | AC49 |
| L8 | Criar/iniciar/parar **explícitos**, ownership por labels, sem remoção automática | T-004; T-021 | feito | — |
| L9 | **Criação idempotente** (`computer.request` com idempotency_key; repetir devolve a mesma box) | SPEC1 cap.07; PLAN AB-018 | pendente | AC27 |
| L10 | **Fila justa, cancelável e persistente**, com teto (10 pedidos com teto 2) | SPEC1 cap.08; PLAN AB-018; STATUS:13,40 | pendente (só serialização em memória) | AC28 |
| L11 | Preflight de memória/disco que explica a fila | SPEC1 cap.08 | pendente | AC28 |
| L12 | Health por componente; ready só com health real; timeout não grava sucesso | SPEC1 cap.08/15; SPEC04 cap.15 | parcial | AC37 |
| L13 | **Atualizar imagem de box parada** preservando volume, IDs e token; journal; rollback | T-042 | feito (Docker real); visual pendente | AC59 (parcial) |
| L14 | Reconstruir metadados a partir de labels; recusar conflitos | T-021 | feito | — |
| L15 | **Parada ociosa** configurável sem parar box com intervenção/download | SPEC1 cap.10 | parcial (só auto-stop da box de filho) | — |
| L16 | Box por terminal **e** box por subagente (dono distinto) | T-043; T-044 | feito (dispatcher + Docker; TUI pendente) | AC19–21 |
| L17 | Transferir box do pai para o filho | T-043 | pendente | — |
| L18 | Docker indisponível: terminais continuam e boxes ficam em erro/espera; sem desktop simulado | SPEC1 cap.15 | parcial | AC44 |
| L19 | Reconexão após troca de build, sem travar no Keychain | T-035; STATUS:27,46 | não validado | — |
| L20 | Exec de comando/shell **na box** (`exec(argv)` versus `shell(command)`, cwd, timeout, cancelamento) | SPEC1 cap.02; SPEC04 cap.13 (BoxRuntime.exec, ToolBroker exec/read_file/write_file); SKILL0 | **pendente / removido**. Não há rota de exec no runtime e T-039 diz “o canal não oferece shell arbitrário” | — |
| L21 | Arquivos da box visíveis no host (`/work` → `runs/<box>/`) | SKILL0 | pendente (o volume é Docker nomeado; sem navegação de arquivos) | — |
| L22 | Uma imagem para os três modos, com componentes sob demanda | SPEC1 cap.08 | feito | — |

### 1.M Modos HTTP / headless / desktop e transições

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| M1 | Modo **http** sem browser nem display | SPEC1 cap.08 | feito | AC29 |
| M2 | **headless** com Chromium completo e JS | SPEC1 cap.08; T-037 | feito (smoke) | AC30 |
| M3 | **desktop** com Chromium headed em Xvfb, mesmo perfil para agente e humano | SPEC1 cap.08; T-037; SPEC04 cap.01 | feito (smoke + UI ao vivo) | AC31 |
| M4 | Política **Adaptativo** (prefere sem UI) ou **Sempre gráfico** | SPEC1 cap.08/10; T-004; T-014 | parcial | AC31 |
| M5 | Escalonamento http→headless→desktop: transitioning, drenar, checkpoint, lock do perfil, nova geração/epoch, invalidar comandos antigos; erro mantém checkpoint | SPEC1 cap.08 | parcial (mode muda geração e reinicia browser; sem checkpoint de tarefa nem reconciliação de ação incerta) | AC32, AC33 |
| M6 | Histerese/inatividade para não alternar modos sem parar | SPEC1 cap.08 | pendente | — |
| M7 | Troca de cookies entre o cliente HTTP e o browser só explícita e autorizada | SPEC1 cap.08 | regra (o HTTP não usa cookies) | — |
| M8 | Desligar streaming é diferente de virar headless | SPEC1 cap.08 | feito (fechar o viewer não para a box) | AC36 |

### 1.N Browser, desktop, streaming e viewer

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| N1 | **Viewer nativo** do computer_id selecionado (MJPEG em NSView; a spec propunha noVNC em WKWebView) | SPEC1 cap.09; T-020-023 | feito (UI ao vivo, STATUS:27) | AC36 |
| N2 | Estados conectado/atrasado/reconectando/erro; frame antigo com horário; stream caído não aceita input | SPEC1 cap.09/15; T-020-023 | feito (código) | AC43, A40 |
| N3 | Input mouse/teclado/arraste/scroll/atalhos; Cmd/Ctrl→Ctrl, Option→Alt; letterbox | T-033 | não validado (smoke ao vivo pendente; correção de Shift sem conferência visual) | AC38, A23 |
| N4 | Layout ABNT2, acentos, colar Unicode, teclas down/up liberadas no fim | SPEC04 cap.06 | pendente | A23 |
| N5 | **Clipboard e upload/download** como capacidades independentes, escopadas e opt-in | SPEC1 cap.09; SPEC04 cap.06 | pendente | — |
| N6 | Fullscreen do desktop sem mudar dono | SPEC1 cap.05/09 | pendente | — |
| N7 | Resolução dinâmica / renegociação de resize | SPEC04 cap.06; T-033 | pendente (1280×800 fixo) | — |
| N8 | **Miniaturas/thumbnails** (1 stream focado + até 2 thumbnails ativas); prévias por hover | SPEC1 cap.09; SPEC04 cap.05/06 | pendente | AC08 |
| N9 | Replay/gravação de sessão identificada (opt-in) | SPEC04 cap.06 | fora de escopo v1 | — |
| N10 | “Abrir desktop” na tela de computador | SPEC1 cap.05 | feito | — |
| N11 | Metas: input remoto p95 < 200 ms, feedback de UI < 100 ms | SPEC1 cap.09 | pendente (não medido) | AC60 |
| N12 | Stream de 4 fps máx. (MJPEG) | runtime README | feito (limitação) | — |
| N13 | Navegador **utilizável manualmente**, com sessões persistentes (pedido explícito do usuário) | T-037 | feito (smoke) | AC35 (parcial) |
| N14 | Perfil próprio por box, sem copiar o Chrome pessoal nem override de user agent | T-037; T-041 | feito | — |
| N15 | Acessibilidade do viewer limitada (pixels não viram VoiceOver); atalho para soltar o foco do teclado | SPEC1 cap.09; SPEC04 cap.14 | pendente | AC07 |

### 1.O Controle exclusivo, takeover e broker

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| O1 | Um writer por computador; `ControlBroker` com epoch monotônico, paths (http_request, navigate, input, mode) | SPEC1 cap.09; T-017 | feito (testes) | AC38 |
| O2 | **Assumir**: revoga, espera ACK e só então habilita input humano; epoch antigo rejeitado | SPEC1 cap.09; T-017; STATUS:22 | feito (smoke + UI ao vivo sem agente concorrente) | AC38 |
| O3 | **Devolver**: reconcilia URL, abas, arquivos e downloads; resumo de estado ao executor, sem segredos | SPEC1 cap.09 | parcial (devolução existe; reconciliação de abas/arquivos não) | AC41 |
| O4 | Bloquear **todos os caminhos de escrita** (browser actions, CDP, input, subprocessos) durante human | SPEC1 cap.07/09; AC39 | parcial (rotas da API sim; um processo dentro do container não, como declarado) | AC39 |
| O5 | Irmãos com outras boxes continuam durante o takeover | SPEC1 cap.09; T-044 | feito (Docker real) | AC40 |
| O6 | Queda de stream: input suspenso; reconectar não resolve o pedido nem autoriza o agente | SPEC1 cap.09 | feito (código) | AC43 |
| O7 | Delegação pai→filho com revogação/ACK (`requestChild`/`revokeChild`) | T-017; T-044 | feito (testes) | AC21 |
| O8 | Ao reiniciar o app, todos os boxes carregam suspensos, preservando o próximo epoch | T-017 | feito | AC58 |
| O9 | **Modo privado** (“Ocultar entrada dos agentes”): sem screenshots ao modelo, sem captura de teclas/bodies; `paused_private` na captura | SPEC04 cap.06; SPEC1 cap.09/15 | pendente | A05 |
| O10 | Faixa/borda âmbar “Você no controle” | SPEC04 cap.03/14 | pendente/não documentado | — |
| O11 | Ação longa com ID, cancelamento, timeout e resultado incerto registrado; não repetir efeitos externos | SPEC1 cap.14; SPEC04 cap.06 | parcial (prazos de 60 s; sem registro de resultado incerto) | AC33, A03 |

### 1.P Pedidos humanos, notificações e atenção

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| P1 | `ask_user` / `computer_request_help` cria request_id, motivo, run, computer e contexto sanitizado | SPEC1 cap.09; T-039; T-044 | feito (fluxo real não interativo AB-045) | AC42 |
| P2 | Tipos: login, verificação/CAPTCHA, download, escolha/clarificação, mudança de escopo, provider_auth | SPEC1 cap.09; SPEC04 cap.06 | parcial (descrição genérica; tipos não discriminados) | A42 |
| P3 | Pedido aparece no filho, no terminal e na sessão por agregação; **badge global e por sessão/terminal** | SPEC1 cap.09; T-020-023 | feito (código); visual pendente | AC04 |
| P4 | **Um som por request_id** (sem repetir na reconexão); deduplicação | SPEC1 cap.09/15; T-020-023 | feito (testes) | AC42, A41 |
| P5 | Notificação do macOS opt-in, pedida ao ativar; falha mantém o alerta interno; som configurável | SPEC1 cap.09/10; T-020-023 | parcial (visual não provado, STATUS:41) | AC42 |
| P6 | **Fila de pedidos** (tela Atividade/Pedidos de ação) por urgência/tempo; abrir alvo, assumir, devolver; resolvido em outro painel sai da fila | SPEC1 cap.05; SPEC04 tela 10 | parcial (`HumanRequestsView`) | AC42 |
| P7 | Pedido permanece em desconexão; só se resolve por ação explícita e reconciliação | SPEC1 cap.05/09; SPEC04 cap.06 | feito (código) | AC43, A42 |
| P8 | Notificação sem dados sensíveis na tela bloqueada | SPEC04 cap.06 | não documentado | — |
| P9 | “Testar ping / Testar som” | DREADME | só no protótipo | — |
| P10 | Ícone/indicador na **menu bar** com tarefas em andamento | SPEC04 cap.04/16 (M4) | pendente | — |
| P11 | Fechar o viewer não resolve o pedido nem autoriza a retomada | T-039; T-044 | feito | — |

### 1.Q MCP do computador (ferramentas expostas ao CLI)

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| Q1 | Servidor MCP stdio por lançamento (`--mcp-config`), helper `AgentBoxMCP` empacotado, sem tocar a configuração global | T-039 | feito; uso pelo modelo provado só em `-p` | — |
| Q2 | Token do container nunca chega ao CLI; socket Unix 0600 por plano, UID do peer, capability | T-039 | feito | AC49, AC50 |
| Q3 | Ferramentas: `computer_acquire`, `computer_status`, `computer_screenshot`, `computer_mode`, `computer_navigate`, `computer_input`, `computer_request_help`, `computer_http_request`, `computer_page` | T-039; T-041; T-044 | feito (código); a TUI interativa não foi validada | — |
| Q4 | Proveniência assinada por chamada (PreToolUse com nonce, sem replay) para rotear pai ou filho | T-043; T-044 | feito (probe real) | AC19, AC20 |
| Q5 | MCP para Codex/OpenCode | T-039 | pendente | — |
| Q6 | Ferramenta MCP para ler capturas/datasets | T-046 | pendente | — |
| Q7 | Ferramentas `checkpoint`, `record_evidence`, `export_artifact`, `read_file`/`write_file`, `exec` | SPEC04 cap.13 ToolBroker | pendente | — |
| Q8 | Política de destinos de URL (allow/deny) para o navegador | STATUS:40; T-039 | pendente | — |

### 1.R Scraping (preset e ferramentas de extração)

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| R1 | **Skill `webscraping-expert` padrão** em toda box nova (atribuição pendente até o lançamento revisado) | T-036; STATUS:73 | feito (código); a ativação pelo modelo não foi provada | — |
| R2 | Ações “Revisar e iniciar agente” e “Definir agente de scraping padrão” no painel da box | T-036 | feito (código) | — |
| R3 | Filhos Claude só acessam computador se o pai foi lançado com o contexto de scraping revisado | T-044 | feito (**restrição**, ver §3) | — |
| R4 | `computer_http_request`: só GET/HEAD público, sem cookies/headers/redirect, 1 MiB, anti-SSRF | T-041 | feito (smoke) | — |
| R5 | `computer_page`: URL, título, texto e links, sem campos de formulário; limites | T-041 | feito (smoke) | — |
| R6 | Conteúdo de site é dado não confiável, nunca instrução | SPEC1 cap.13; SPEC04 cap.09; T-041 | regra | A22 |
| R7 | Diante de CAPTCHA/login: parar e pedir takeover; sem solver | T-036; T-041; SPEC04 J3 | regra | — |
| R8 | Diagnóstico do CAPTCHA do Google observado | T-036; T-037; STATUS:76,112 | pendente (causa indeterminada) | — |
| R9 | Preferir APIs oficiais; não fazer compras/mensagens/alterações em contas | SPEC04 cap.11 | regra | — |
| R10 | Migrar boxes antigas para a imagem nova | STATUS:76; T-042 | parcial (atualização manual existe; nenhuma box foi migrada) | — |

### 1.S Listener, captura, evidências e datasets

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| S1 | Listener = observação de rede (não microfone); permissões separadas para metadados, conteúdo e interferência | SPEC1 cap.11 | parcial (só observação) | — |
| S2 | Captura **opt-in por box**, desligada por padrão, com hosts exatos, prefixos de path, retenção e limites | T-046 | feito (smoke) | AC53, AC54 |
| S3 | Fonte **browser**: requests/responses/falhas, páginas novas, redirects; gaps declarados (workers, websockets, cache, bodies) | SPEC1 cap.11; T-046 | parcial | AC51 |
| S4 | Fonte **HTTP tools**: JSON escalar selecionado | T-046 | parcial | AC52 |
| S5 | Fontes **curl / Python requests / curl_cffi** (adapters existentes no skill original) | SPEC1 cap.02/11; AC52 | pendente (fora da cobertura declarada) | AC52 |
| S6 | Fonte **proxy** (bytes/rota/estimativas) | SPEC1 cap.11 | pendente | — |
| S7 | Filtros: método, status, MIME, tamanho, inclusão de body, frequência | SPEC1 cap.11; T-046 | pendente (só host/path/campos) | AC53 |
| S8 | **Bodies de resposta do browser** (preset “JSON de domínios escolhidos”) | SPEC1 cap.11; EV ab046 `not_proved` | pendente | AC51 |
| S9 | Sanitização antes de persistir e antes do LLM (Authorization, Cookie, tokens em URL, formulários) | SPEC1 cap.11; T-046 | feito (por exclusão) | AC53 |
| S10 | Backpressure, fila com limite de memória, gaps visíveis, coleta degradada | SPEC1 cap.11; T-046 | parcial | AC54 |
| S11 | Coleta restaurada automaticamente após relançar; corte atômico ao mudar filtros | T-046; STATUS:43 | pendente | AC54 |
| S12 | Herança de política de listener (global/projeto/agente) | T-046 | pendente | AC45 |
| S13 | Painel **Capturas e dados** (histórico offline, configurar, limpar) | T-046 | não validado (visual) | — |
| S14 | **Dataset** com schema por tarefa, normalização, dedup, referência por campo/linha à evidência; null com motivo | SPEC1 cap.11; T-046 | parcial (campos escalares de topo; sem dedup por chave de negócio, sem JSON aninhado, sem edição) | AC55 |
| S15 | **Exportar CSV/JSON** com manifesto, hashes e proveniência; proteção contra fórmula no CSV | SPEC1 cap.11; T-046 | feito | AC55, A18 |
| S16 | Exportar **XLSX** (segunda entrega) | SPEC04 J7 | pendente | — |
| S17 | Apagar capturas não apaga resultados | SPEC1 cap.11; T-046 | feito | — |
| S18 | Tabela de resultados com filtros (fonte, status, campos faltantes), inspector de evidência (trecho, URL, horário, processo) | SPEC1 cap.05; SPEC04 J7, telas 07/11 | pendente/parcial | — |
| S19 | Eventos com capture_source, coverage_version, request_id, run/terminal/session/computer IDs | SPEC1 cap.11 | parcial | — |
| S20 | Interceptação/reescrita de tráfego (com permissão separada) | SPEC1 cap.11; T-046 | pendente (por decisão) | — |
| S21 | **Journal do agente** (PLAN/DOING/FOUND/BLOCKED), log de comandos, timeline combinada, `collect` de transcript, “toda afirmação cita request id” | SKILL0 | **pendente / não migrado** | — |

### 1.T Proxy e orçamento

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| T1 | Proxy (**Zyte**) por box, `proxy on/off/status`, a box inteira incluindo o browser | SKILL0 | **pendente / não migrado** (o HTTP tool ignora proxies de ambiente) | — |
| T2 | **Budget rígido** por box (padrão US$ 1; HTTP 402 ao estourar), medido versus estimado, reserva e reconciliação | SKILL0; SPEC1 cap.02/11; SPEC04 cap.11 | pendente | A20 |
| T3 | `render` via Zyte API (browserHtml, `--capture` de XHR) para Cloudflare/Incapsula/DataDome | SKILL0 | pendente / não migrado | — |
| T4 | Gateway de proxy com políticas por perfil/tarefa | SPEC04 cap.05/11 | pendente | — |

### 1.U Credenciais, .env e Keychain

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| U1 | Tela **Credenciais e variáveis**: importar `.env` como dados (sem source/eval/expansão), adicionar manualmente, reusar conjuntos por projeto | SPEC1 cap.12; T-015 | feito (reuso por projeto não documentado) | AC47 |
| U2 | Valores no **Keychain**; banco/JSON só com referências | SPEC1 cap.12; T-015 | feito (testes com backend falso) | AC49 |
| U3 | **Grants** com escopo, uso (ferramenta/env), destino, `delegable`, prazo, revisão; revogação | SPEC1 cap.12; T-015 | feito (Core/UI) | AC48 |
| U4 | **Injeção** de segredo em env do processo/container selecionado; `.env` temporário para ferramenta | SPEC1 cap.12; T-015 | pendente (“ainda não há injeção”) | AC48 |
| U5 | Broker resolve o segredo para operação autorizada | SPEC1 cap.12; STATUS:42 | parcial (“grants conectados ao broker”) | AC48 |
| U6 | Mostrar nomes, referência, destinatários, modo de entrega, último uso e **rotação** | SPEC1 cap.05 | parcial | — |
| U7 | Nunca registrar valores em eventos, histórico, crash reports ou exports | SPEC1 cap.12 | regra | AC47, AC49 |
| U8 | Erro de Keychain recuperável (sem spinner infinito); assinatura estável entre builds | SPEC1 cap.12; T-035 | não validado | AC49 |
| U9 | Login do CLI fica no cliente oficial; o app não copia token para o container | SPEC1 cap.12 | regra | AC14 |

### 1.V Perfis de navegador

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| V1 | **BrowserProfile** como entidade separada da imagem e da box, com lock de um gravador (owner/geração) | SPEC1 cap.03/12; SPEC04 cap.02/10 | parcial (o perfil é o `/data/profile` da box, sem entidade própria) | AC34 |
| V2 | **Biblioteca de perfis**: criar perfil, abrir em controle humano para login, marcar sites, “última verificação” por site | SPEC04 J1, telas 05/12 | pendente | A09 |
| V3 | Perfil ocupado: fila ou outro perfil; nada de clonar identidade para 10 agentes | SPEC1 cap.12 | pendente | AC34, A07 |
| V4 | **Clonar** perfil autenticado como ação explícita | SPEC1 cap.12 | pendente | — |
| V5 | **Backup/restore** (browser parado, manifesto, checksums, restore testado) | SPEC1 cap.12; PLAN AB-021; STATUS:45 | pendente | AC35, A08 |
| V6 | Proteção em repouso (volume/imagem cifrada) | SPEC1 cap.12; SPEC04 cap.10 | pendente | — |
| V7 | Migração de perfil em update de browser, com backup e retorno | SPEC1 cap.12 | pendente | AC59, A27 |
| V8 | Persistência de localStorage/cookies entre restart e recriação | T-019/020; T-037 | feito (smoke com fixture local) | AC35 (parcial) |
| V9 | Perfil corrompido: recuperação sem recriar vazio com o mesmo nome | SPEC1 cap.15 | pendente | — |
| V10 | Login de site **não é** memória/segredo textual | SPEC1 cap.12 | regra | — |

### 1.W Configurações, primeiro uso e políticas efetivas

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| W1 | **Setup de 3 passos** (computadores, acessos, revisão), retomável e reusando os componentes de Configurações | SPEC1 cap.05/10 | parcial (onboarding existe, EV validation.json; retomada citada em T-014) | AC44 |
| W2 | Modo só-terminal sem Docker | SPEC1 cap.10 | feito | AC44 |
| W3 | Criação de computador: automático dentro de limites / perguntar / manual (nunca por timeout) | SPEC1 cap.10; T-014; T-044 | parcial (**“perguntar” não aparece**; o automático só vale para filho) | AC45 |
| W4 | Recursos (CPU, memória, teto de boxes), rede, pastas, listener, credenciais, notificações, privacidade/retenção | SPEC1 cap.10 | parcial (CPU/mem/teto/rede existem) | AC45 |
| W5 | Herança **global → projeto → sessão → terminal → agente** com tetos (filho não amplia) e origem visível | SPEC1 cap.10; T-014 | feito (Core); UI mostra camadas no painel | AC45 |
| W6 | Mostrar “Aplicado agora / Na próxima execução / Requer reinício” | SPEC1 cap.10 | pendente | AC46 |
| W7 | Salvar versionado e atômico; inválido preserva o anterior; migração com backup | SPEC1 cap.10; T-014 | feito | AC46 |
| W8 | Configurações com categorias, busca, escopo e fonte do valor; schemas versionados | SPEC1 cap.05/10 | parcial | AC46 |
| W9 | Tela **Recursos do agente** (qual computador, modo, listener, credenciais, pastas, ferramentas e origem de cada permissão) | SPEC1 cap.10 | pendente | — |
| W10 | Rede: internet para a tarefa separada do acesso à rede local/host | SPEC1 cap.10 | parcial (anti-SSRF só na rota HTTP) | — |
| W11 | Arquivos: workspace selecionado; outras pastas por concessão específica (mounts) | SPEC1 cap.10 | pendente (sem mounts do host) | — |
| W12 | A política não é sandbox do macOS; distinguir “controlado pelo broker” de isolamento real | SPEC1 cap.07/10; T-014 | regra | AC50 |

### 1.X Modelo e handoff entre harnesses

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| X1 | **Seletor de modelo** por terminal/execução, pendente até confirmação, sem digitar `/model` em prompt errado nem alterar o padrão global | SPEC1 cap.13; SPEC04 cap.07; PLAN AB-026 | pendente | AC56, A34, A35 |
| X2 | **Handoff Claude↔Codex↔OpenCode** transacional (validar destino → pausar → checkpoint → revogar → iniciar → associar → validar → concluir), com rollback | SPEC1 cap.13; SPEC04 cap.08; PLAN AB-027 | pendente | AC57, A10, A11, A13 |
| X3 | Checkpoint com objetivo, critérios, decisões, próximos passos, artefatos, linhas do dataset, evidências, estado da box e memória permitida; sem raciocínio privado nem credenciais | SPEC1 cap.13; SPEC04 cap.08/09 | pendente | — |
| X4 | Filhos ativos bloqueiam a troca, ou são encerrados/aguardados por escolha explícita | SPEC1 cap.13 | pendente | — |
| X5 | “Recibo” do que será preservado (tela Trocar agente) | SPEC04 J5, tela 04 | pendente (só no protótipo) | — |
| X6 | Provedor sem limite: salvar o estado e oferecer troca explícita | SPEC1 cap.15; SPEC04 cap.12 | pendente | — |

### 1.Y Tarefas, checkpoints e artefatos (herdado da v0.4)

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| Y1 | Entidade **Pesquisa/Tarefa** com objetivo, critérios, estados (draft…archived) | SPEC04 cap.02/12; SPEC1 cap.03 (Task/Evidence/Checkpoint) | pendente | — |
| Y2 | Checkpoints versionados (troca, pausa humana, lote, desligamento) | SPEC04 cap.09 | pendente | — |
| Y3 | Tela **Memória da tarefa** (objetivo, fatos, decisões, próximos passos, origem das afirmações) | SPEC04 tela 06 | pendente | — |
| Y4 | Artefatos com hash/manifesto; caminhos validados contra `../` e symlinks | SPEC04 cap.09 | parcial (export) | — |
| Y5 | “Voltar amanhã” (J6): reanexar/recriar box, health leve, sessão expirada pede login, checkpoint evita recoletar | SPEC04 J6 | parcial | — |
| Y6 | Horários exibidos em America/Sao_Paulo | SPEC04 cap.09 | não documentado | — |

### 1.Z Confiabilidade, recuperação e uso diário

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| Z1 | Serviço local (`AgentBoxService`) com IPC autenticado (XPC/socket), SQLite, event stream com seq/replay | SPEC1 cap.14 | pendente (tudo no processo do app, com JSONs) | AC58 |
| Z2 | Recuperação após UI/serviço/Docker cair; sleep/wake renova concessões | SPEC1 cap.15; PLAN AB-028 | pendente | AC58, A15 |
| Z3 | Migração versionada de banco/config/perfis com backup | SPEC1 cap.14; PLAN AB-028 | parcial (migração de política v1→v2) | AC59 |
| Z4 | **60 min de carga sustentada** sem vazamento de processos/streams | SPEC1 cap.16; STATUS:45 | pendente | AC60 |
| Z5 | Disco cheio: bloquear gravações sem apagar perfis | SPEC1 cap.15 | pendente | A28 |
| Z6 | Quit explícito encerra PTYs e espera a limpeza das boxes; confirmação lista computadores pendentes | T-044 | feito (código) | — |
| Z7 | Estados formais por objeto (Terminal, AgentRun, Computer, Control, Capture, Auth, Profile) | SPEC1 cap.15 | parcial | — |
| Z8 | Diretório `Application Support/AgentBox/{database,workspaces,profiles,evidence,checkpoints,diagnostics}` | SPEC1 cap.14 | parcial (JSONs soltos) | — |
| Z9 | Diagnósticos/logs sanitizados exportáveis | SPEC1 cap.08/14 | pendente | — |

### 1.AA Visual, UX, acessibilidade, atalhos e marca

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| AA1 | Sidebar padrão 288 pt, arrastável entre 224 e 480, recolhível, restaura largura e seleção; teclado em passos; duplo clique restaura | SPEC1 cap.04; T-003; T-006; T-045 | feito (código); visual pendente | AC01, AC02 |
| AA2 | Controles de janela nativos, toolbar compacta (38–44 pt), abas 34–38 pt, linhas 28–32 pt | SPEC1 cap.04; T-006 | parcial | AC05 |
| AA3 | Sem glow, cards de dashboard, semáforos falsos ou rótulos demo; cor só para estado | SPEC1 cap.04/18 | parcial | AC05 |
| AA4 | Fonte do sistema 13 pt; regular predominante | SPEC1 cap.04; T-006 | feito | — |
| AA5 | Tokens de cor (#252526 sidebar, #18191B/#141517 canvas…) | SPEC1 cap.04 | **divergente** (T-006 usa #272B33/#282828/#191919) | — |
| AA6 | Logos oficiais (Claude, Codex, OpenCode) com peso óptico comparável em 16/18/24/32 pt | SPEC1 cap.04; T-003 | parcial | AC06 |
| AA7 | Acessibilidade: teclado, foco visível 2 pt, rótulos, Reduce Motion, 1000×650 sem ações inacessíveis | SPEC1 cap.04; T-006 | não validado | AC07 |
| AA8 | Atalhos ⌘N, ⌘T, ⌘D, ⌘⇧D, ⌘B, ⌘, e ⌘K (busca/command palette); maximizar e próximo pane; atalhos configuráveis | SPEC1 cap.05; SPEC04 cap.14 | parcial (⌘K e ⌘, citados) | AC07 |
| AA9 | Motion: expansão 120–160 ms, painel 160–200 ms; sem vídeo decorativo | SPEC1 cap.04; T-006 | parcial | — |
| AA10 | Marca própria Agent Box (ícone/Dock) | docs/branding/PROVENANCE.md; T-030 | feito | — |
| AA11 | Janela mínima de 1000×650, alvos de 1440×900 e 1728×1117 | SPEC1 cap.04 | não validado | AC07 |
| AA12 | Tabelas/listas com inspector contextual no lugar de galerias de cards | SPEC1 cap.04 | parcial | — |

### 1.AB Build e desenvolvimento

| # | Funcionalidade | Fonte | Status | Aceite |
|---|---|---|---|---|
| AB1 | Build SPM reprodutível, separado do design; `scripts/build_app.sh`; assinatura ad hoc verificada | README:19–31; STATUS:33; T-045 | feito | — |
| AB2 | Bundle no cache `~/Library/Caches/AgentBox/Builds/<chave>` com link em `build/` (contorno do File Provider) | T-045 | feito | — |
| AB3 | Distribuição/instalador/assinatura estável | PLAN:3; BL M10 | pendente (fora de prioridade) | — |

---

## 2. Capacidades de subagentes (lista consolidada)

A origem principal é o skill `agentbox` original do Gabriel (SKILL0), que a SPEC1 manda migrar. Lá cada subagente tinha **a própria box com terminal, listener, browser persistente e proxy com orçamento**. A coluna “Estado no app atual” compara com o que a doc declara (MCP AB-039/041/044 e runtime AB-019/046).

| # | Capacidade de subagente | Fonte | Estado no app atual |
|---|---|---|---|
| SC1 | **Uma box por subagente**, isolada; o orquestrador cria a box antes de criar o filho e entrega o nome dela | SKILL0; SPEC1 cap.07 | Parcial. O filho Claude cria a box por `computer_acquire`, sob política automática e só com o preset de scraping |
| SC2 | Identidade do filho autenticada por chamada; `box_id` do modelo nunca autoriza | SPEC1 cap.07; SPEC04 cap.13 | Feito para Claude (hook assinado); Codex/OpenCode pendentes |
| SC3 | **Terminal na box**: `exec <box> -- <cmd>` com curl, python3, jq, requests, curl_cffi, openpyxl | SKILL0; SPEC1 cap.02 (exec vs shell); SPEC04 ToolBroker `exec` | **Ausente.** Não há exec/shell; só GET/HEAD controlado |
| SC4 | **curl_cffi / impersonação TLS** | SKILL0; skill webscraping-expert | Ausente |
| SC5 | **Browser persistente** (sessão sobrevive entre comandos) | SKILL0; SPEC1 cap.08 | Feito (perfil /data por box) |
| SC6 | Comandos de browser: `open`, `text`, `html`, `click <seletor>`, `fill <seletor> <valor>`, `press`, `eval '<js>'`, `cookies`, `shot` | SKILL0; SPEC04 ToolBroker (`browser_navigate/state/action`, `read_screen/click/type/key/scroll`) | Parcial: navigate, page (texto/links), screenshot, input por coordenada. **Sem** seletor CSS, `fill`, `eval` JS, HTML bruto, cookies (excluídos de propósito) |
| SC7 | Modos HTTP / headless / desktop escolhidos pelo agente dentro da política | SPEC1 cap.08 | Feito (`computer_mode`, `computer_acquire(mode)`) |
| SC8 | Requisições HTTP arbitrárias (POST, headers, cookies, follow redirects) para reusar endpoints de API descobertos | SKILL0 (curl/python); escalonamento “reuse endpoints with curl” | **Ausente.** Só GET/HEAD público, sem headers/cookies/redirect, 1 MiB |
| SC9 | **Request listener** que loga toda chamada (browser, curl, python), com falhas e **bodies completos**; `reqlog --xhr/--errors/--grep/--full` para achar APIs escondidas | SKILL0 | Parcial e só para o humano: captura opt-in por box com metadados; **sem bodies do browser**, sem curl/python; **o agente não lê as capturas** (sem MCP) |
| SC10 | **Proxy Zyte** `proxy on/off/status`, cobrindo browser e curl, budget rígido de US$ 1 por box (402) | SKILL0 | Ausente |
| SC11 | **`render` via Zyte API** para Cloudflare/Incapsula/DataDome, com `--capture` de XHR | SKILL0 | Ausente |
| SC12 | Escada de escalonamento direto → proxy → render → pedir ajuda; nunca contornar login | SKILL0; T-041 | Parcial (pedir ajuda existe; proxy/render não) |
| SC13 | **Pedir ajuda humana** (login, CAPTCHA, download, escolha) com takeover no mesmo navegador e retomada | SPEC1 cap.09; SPEC04 J3; T-039/044/045 | Feito (fluxo real não interativo); visual/TUI pendente |
| SC14 | Controle exclusivo por box; takeover de um filho não pausa os irmãos | SPEC1 cap.09; AC40 | Feito (Docker real) |
| SC15 | **Journal obrigatório** `note PLAN/DOING/FOUND/BLOCKED` | SKILL0 (template) | Ausente |
| SC16 | **Log de comandos** (hora, comando, exit, duração, saída completa) | SKILL0; SPEC04 cap.11 (Terminal) | Ausente (não há exec) |
| SC17 | **Timeline** combinada (journal + comandos + requests) e `collect` do transcript do subagente | SKILL0 | Ausente |
| SC18 | **result.json com evidência**: toda afirmação cita request id/arquivo, senão “not verified” | SKILL0; SPEC1 cap.11 (dataset por evidência) | Parcial (datasets com evidence hash feitos pelo usuário; o agente não registra evidência; sem `record_evidence`) |
| SC19 | **Workspace `/work`** da box acessível no host (`runs/<box>/`); runs nunca apagados, arquivados em `runs/_archive` | SKILL0 | Parcial (volume `/data/workspace` persiste; sem visão no host nem arquivamento de runs) |
| SC20 | Skill **webscraping-expert carregada** em todo subagente, pulando o intake | SKILL0; T-036; T-043 | Feito para filhos Claude do lançamento de scraping (additionalContext) |
| SC21 | Brief do orquestrador por subagente (tarefa, o que já sabemos, spec de saída) | SKILL0 template | Ausente como funcionalidade do app (fica no harness) |
| SC22 | Downloads no browser da box | SPEC1 cap.09; T-037 | Parcial (diretório existe; downloads via CDP não validados) |
| SC23 | Ler/escrever arquivos e exportar artefato | SPEC04 ToolBroker | Ausente |
| SC24 | `checkpoint` e `record_evidence` como ferramentas | SPEC04 ToolBroker | Ausente |
| SC25 | Credenciais concedidas por grant (env ou ferramenta), nunca implícitas; delegáveis só se marcadas | SPEC1 cap.10/12 | Parcial (sem injeção) |
| SC26 | Perfil com login reaproveitado com exclusividade; fila se ocupado | SPEC1 cap.12 | Pendente (perfil = box) |
| SC27 | Recursos por box (CPU/mem/PIDs/shm) e teto agregado | SPEC1 cap.08 | Feito (teto sem fila) |
| SC28 | Parada automática da box do filho quando ele termina, preservando o perfil | T-044 | Feito |
| SC29 | Rede: só internet pública na rota HTTP; política de destinos do browser | T-041; STATUS:40 | Parcial |
| SC30 | Worker independente (CLI próprio com PTY) quando não há identidade nativa | SPEC1 cap.07 | Pendente |
| SC31 | Steering/controle individual do filho e modelo por filho | SPEC1 cap.07/13 | Pendente |
| SC32 | Paralelismo de filhos (helper com até 8 chamadas simultâneas) | T-044 | Feito |

**Leitura.** O app novo cobre bem identidade, takeover e isolamento por box, que eram os gates de risco da spec. Ficaram de fora as ferramentas de **trabalho** de scraping que o Gabriel já tinha no skill original: exec/terminal na box, curl_cffi, POST/headers, reqlog com bodies lido pelo agente, proxy Zyte com budget, render, journal/timeline e evidência citada pelo agente. Para o caso de uso declarado (“achar endpoints escondidos, validar fontes, construir crawlers”), isso é uma **regressão funcional** em relação ao skill de 09/10/2026.

---

## 3. Contradições entre docs e “feito com ressalva”

### 3.1 Contradições diretas

1. **README desatualizado vs STATUS.** README:13 diz que o Docker “não foi validado com daemon real, pois Docker não está instalado” e que browser, desktop, streaming, subagentes, `.env`/Keychain e handoff “continuam pendentes”. README:15 cita 23 testes. O STATUS registra Colima instalado, smoke arm64 real, desktop com streaming, Keychain, subagentes Claude e 172 testes.
2. **acceptance.json e backlog.json congelados.** Os 68 ACs estão `planned` e os marcos M0–M10 `not_started`, enquanto o PLAN marca AB-002…AB-046 como parcial/em integração e cita ACs como “parcial” (T-009: AC16/17/18 parciais). Os JSONs de controle não refletem nada.
3. **backlog.json com erros de cópia.** M3 repete exatamente os aceites de M2 (AC09–AC18). M9 inclui AC19–AC26 (de M5) e AC56–AC60 (de M10). M0 lista módulos `source/Package.swift` e `docs/ADR/`, que não existem no app novo.
4. **Duas specs com decisões opostas.** A SPEC04 (design/) diz: Manrope, sidebar 220 pt, mínimo 1200×800, “terminal e desktop lado a lado”, sidebar com Agora/Agentes/Boxes/Resultados/Clientes locais, fechar janela mantém tarefas com ícone na menu bar, box sempre com desktop. A SPEC1 diz o oposto: fonte do sistema, 288 pt, 1000×650, desktop opcional, sem dashboard “Agora” e quit perguntando. A SPEC1 declara que substitui a v0.4, mas a v0.4 continua no repo sem marca de obsoleta e é a única fonte de Perfis, Tarefas/Checkpoints, modo privado, XLSX e Zyte.
5. **Tokens de cor.** SPEC1 cap.04 propõe #252526/#18191B/#141517; T-006 implementa #272B33 (canvas), #282828 (sidebar) e #191919 (toolbar), copiados do print do Orca. Nenhuma doc atualiza a spec.
6. **Viewer.** A SPEC1 decidiu “noVNC em WKWebView” para a primeira prova. A implementação usa MJPEG nativo a 4 fps + XTEST (T-020-023, runtime README). A troca não foi registrada como decisão.
7. **Persistência.** A SPEC1 cap.14 decide SQLite e um serviço local dono dos PTYs. A implementação usa JSONs em Application Support (`workspace.json`, `library.json`, `computer-policy.json`, `secret-references.json`, `AgentRuns.json`, `directory-bookmarks.json`) e o PTY dentro do processo do app.
8. **Exec/shell na box.** SPEC1 cap.02 e SPEC04 cap.13 pedem `exec(argv)` e `shell(command)` na box; T-039 diz “o canal não oferece shell arbitrário” e o runtime não tem rota de exec. A mudança de escopo não foi registrada.
9. **Política “sempre gráfico”.** T-014 diz que ela “impede iniciar container HTTP, pois desktop ainda não está integrado” e que “o seletor de criação automática permanece indisponível”. T-044 implementa criação automática (só para filhos) e o desktop existe. T-014 não foi atualizado.
10. **T-020-023** diz que o painel “ainda é HTTP apenas; não mostra botão de desktop”. O STATUS:27 diz que a UI promoveu HTTP para desktop e exibiu o streaming. **T-034** diz que o inbox não está ligado ao lançamento; T-040 liga. **T-003** diz que “nenhuma árvore de subagentes” existe; T-040 a cria. **T-004** descreve a box HTTP python sem browser como “a box”. As tasks antigas não marcam o que foi superado (só T-016/T-043/T-034 têm nota de “integração posterior”).
11. **Contagem de testes** aparece com 11 valores diferentes (23, 70, 82, 103, 110, 113, 123, 135, 152, 160, 172) em lugares diferentes; PLAN:69 (“82 testes”) e STATUS:31 (“152 testes”) estão defasados em relação ao checkpoint AB-046 (172).
12. **Computador “por subagente” virou “por subagente de scraping”.** A SPEC1 cap.07 trata o computador do filho como capacidade genérica, sob política. T-044 condiciona qualquer acesso do filho a computador ao pai ter sido lançado com `webscraping-expert`, e T-036 faz toda box nova nascer com o preset de scraping. Uma tarefa não-scraping não consegue dar box a um filho.
13. **Box ligada ao terminal vs decisão do principal.** PARALLEL-CONTRACT diz “Box lógica sempre ligada a terminal selecionado”. A SPEC1 diz que o principal decide e que a box pertence a um `ComputerBinding` de run. Hoje existem dois donos (terminal e filho), sem transferência.
14. **Escopo de idioma e numeração.** A SPEC1 se diz “18 capítulos”. A SPEC04 tem 19, mas termina com “Fim da especificação v0.1”. T-013, T-019/020, T-036 e T-046 estão em inglês e o resto em português.
15. **“Criação automática … perguntar/manual”.** A SPEC1 cap.10 exige três opções. T-004/T-014/T-044 só citam desativado/manual/automático; “perguntar” não existe.
16. **Hover/preview e thumbnails.** São centrais na SPEC04 (hover 220–300 ms) e na SPEC1 (AC08), mas nenhuma task cobre.
17. **OpenCode.** A SPEC1 o trata como cliente de primeira classe desde o início. T-013 diz que “OpenCode não estava instalado localmente”, e o status de auth fica “não verificado”. O README diz “pode ser lançado se instalado”. Nenhum fluxo dele foi exercitado.
18. **Agentes do protótipo.** DREADME/REV04 mostram seletor de modelo (“Opus”), troca Claude→Codex com checkpoint e Perfis com login. São tidos como “ilustrativos”, mas o Gabriel os viu como features; nenhum existe no app.

### 3.2 Itens declarados “feitos” com ressalva

| Item | Ressalva declarada | Fonte |
|---|---|---|
| Fluxo Claude → filho → box → ajuda → takeover → retomada | Só em modo **`-p` não interativo**, takeover **programático** (sem clique humano), sem TUI, **sem aceite visual** (Mac bloqueado) | STATUS:53; EV ab045 |
| Árvore sessão → terminal → subagente | Smoke real dos hooks; **conferência visual da sidebar nunca feita** | T-040; STATUS:90–92 |
| Viewer + assumir/devolver | Exercitado pela UI **sem agente concorrente**; correção de Shift sem conferência visual | STATUS:27,41 |
| Reconexão Keychain após troca de build | Mitigação no código; **recuperação real não comprovada**; API legada depreciada em uso | T-035; STATUS:46,76 |
| Skills nativas Claude (`--plugin-dir`) | **Catálogo interativo nunca executado**; prova = doc + testes de layout | T-032; STATUS:65 |
| Skill para filhos | Probe `-p` com fixture sintética; settings montados à mão, não pelo planner | EV ab043-child-skill-context |
| MCP do computador | Uso na TUI interativa e prompts de permissão não validados | T-039; EV ab043-native-routing-probe |
| Docker/boxes | Só no contexto Colima `agentbox-dev`; outras arquiteturas e runtimes (Docker Desktop) não testados; pacotes apt podem sumir | runtime README; T-019/020 |
| Perfil persistente | Prova com localStorage de fixture local, **sem login real em site**, sem backup/restore | T-037; EV ab046 `not_proved` |
| Captura | **Sem bodies do browser**, sem curl/python, sem restauração após relançar, perda possível ao trocar filtro, painel não visto | T-046; EV ab046 |
| Atualização de imagem | Nenhuma box do usuário migrada; teste de crash sintético; UI não vista | EV ab042 |
| Bookmarks de pasta | Implementado depois do bloqueio, **sem conferência após relançar** | T-031; STATUS:47 |
| Keychain/.env/grants | Testes com backend **em memória**; **sem injeção** em processos | STATUS:12; T-015 |
| Retomada de conversa | Testada com **fixture de CLI**; históricos reais dos 3 CLIs não | T-013; T-045 |
| Workspace/visual Orca | T-006 “nenhum app, build ou teste iniciado”; tabela de comparação só estática | T-006 |
| Acessibilidade 1000×650, passos de 24 pt, ⌘K | “inspeção estática apenas” | T-006 |
| CAPTCHA do Google | Causa indeterminada, sem promessa | T-036/037/041; STATUS:112,120 |
| Dois filhos concorrentes | Docker real + dispatcher com **transporte URLProtocol fixture**; um único filho real no fluxo nativo | EV ab044, ab045 |
| Broker de controle | “Não é fronteira de segurança do host”; processo dentro do container escapa do lease | T-017; runtime README |
| Política efetiva | Fila e lock só no processo; não é sandbox do Mac | T-014 |

---

## 4. Sugestões: ausentes da doc, mas óbvias para este app

Todas marcadas **sugestão**. Nenhuma foi pedida explicitamente.

1. **Sugestão**: command palette completa (⌘K) com ações, sessões, terminais, agentes e boxes, no estilo do Orca, e não só busca.
2. **Sugestão**: indicadores por terminal de “agente trabalhando / ocioso / aguardando input / esperando permissão”, a partir dos hooks (Notification/Stop do Claude), como o Orca faz nas abas.
3. **Sugestão**: notificação quando um agente **termina** ou fica ocioso esperando o usuário. Hoje só há pedido de ajuda da box.
4. **Sugestão**: busca/scrollback search dentro do terminal (⌘F) e links clicáveis (URLs/arquivos) no PTY.
5. **Sugestão**: drag-and-drop de arquivos/imagens para o terminal (colar caminho), comum em Claude Code/Codex.
6. **Sugestão**: diff/visão de alterações Git por terminal/worktree e ação “abrir no editor/Finder”.
7. **Sugestão**: limpeza de worktrees órfãos e de boxes/volumes parados, com tamanho em disco e confirmação.
8. **Sugestão**: painel de uso de recursos (CPU/RAM/disco por box e do runtime Colima), além de iniciar/parar o próprio Colima pelo app.
9. **Sugestão**: templates/presets de sessão (ex.: “Claude + Codex + shell no mesmo worktree”) e de layout.
10. **Sugestão**: duplicar terminal/sessão e reabrir terminal fechado recentemente.
11. **Sugestão**: arquivo de log/diagnóstico do app exportável (sem segredos) para depurar falhas.
12. **Sugestão**: tema claro e preferências de fonte/tamanho do terminal.
13. **Sugestão**: indicador de custo/tokens por execução quando o CLI expõe (Claude `-p` reporta `costUSD`; hooks/statusline).
14. **Sugestão**: ver o transcript/eventos de um subagente nativo (o que ele fez) no detalhe do filho, já que ele não tem PTY.
15. **Sugestão**: exec/shell **controlado** na box (argv, com log e sujeito ao lease) para recuperar a paridade com o skill original. Opcionalmente, permitir ao agente ler as próprias capturas (reqlog).
16. **Sugestão**: proxy por box com budget (Zyte ou genérico) e `render`, migrando o skill original.
17. **Sugestão**: ver/baixar arquivos do workspace da box (`/data/workspace`, downloads) pelo app.
18. **Sugestão**: atalho global/menu bar para pedidos pendentes e agentes ativos.
19. **Sugestão**: atualização automática das definições quando o SKILL.md de origem muda (hoje um hash divergente bloqueia sem oferecer reimportar).
20. **Sugestão**: suporte a outros CLIs configuráveis (Gemini CLI, Aider etc.) via “outro CLI” genérico com argv/ícone.
21. **Sugestão**: atualizar automaticamente `acceptance.json`/`backlog.json` a partir das evidências, para evitar a divergência da §3.1.
22. **Sugestão**: notas/descrição por sessão (objetivo), para retomar contexto no dia seguinte sem a entidade Tarefa completa.

---

## 5. Anexos rápidos

### 5.1 ACs da SPEC1 com status inferido das tasks

| Faixa | Tema | Inferência a partir das docs |
|---|---|---|
| AC01–AC02 | Sidebar | código feito; visual/relançar não validado |
| AC03 | 5 terminais | código + teste de store; visual não validado |
| AC04 | Hierarquia | parcial (filhos Claude) |
| AC05–AC07 | Chrome/marcas/acessibilidade | parcial, não validado |
| AC08 | Preview/hover | pendente |
| AC09, AC11, AC13 | PTY | feito (testes PTY) |
| AC10 | 3 CLIs | parcial (OpenCode nunca exercitado) |
| AC12 | Reattach | parcial (só dentro do processo) |
| AC14 | Login existente | feito para Claude/Codex |
| AC15, AC18 | Conversa externa / rename+restore | parcial |
| AC16 | Git/worktree | feito (testes); visual pendente |
| AC17 | GitHub | parcial (sem auth/PR) |
| AC19–AC21 | Identidade/vínculo/cancelamento | parcial (Claude; TUI pendente) |
| AC22 | Sem PTY de filho | feito |
| AC23 | Capability ausente | parcial |
| AC24 | Worker independente | pendente |
| AC25–AC26 | Skills/memória por escopo | parcial/feito |
| AC27–AC28 | Idempotência/fila | pendente |
| AC29–AC31 | HTTP/headless/gráfico | feito (smoke) |
| AC32–AC33 | Escalonamento/estado volátil | parcial |
| AC34–AC35 | Perfil exclusivo/restore | parcial (sem backup/restore) |
| AC36–AC37 | Stream/health | feito/parcial |
| AC38–AC43 | Controle/notificação | parcial (sem prova visual/humana concorrente) |
| AC44–AC50 | Configuração/segredos | parcial |
| AC51–AC55 | Captura/dataset | parcial (AB-046 declara não completar) |
| AC56–AC57 | Modelo/handoff | pendente |
| AC58–AC60 | Crash/migração/carga | pendente |
| AC61–AC65, AC67 | Biblioteca | feito (código/testes) |
| AC66 | Ativação verificável | não validado (Claude), pendente (Codex/OpenCode) |
| AC68 | Reutilização | parcial |

### 5.2 Critérios da v0.4 (A01–A43) sem equivalente na SPEC1

A05 (modo privado), A08 (backup/restore de perfil), A09 (sessão de site expirada), A10/A11/A13 (troca de agente e checkpoint), A20 (budget do proxy), A21 (ferramenta tenta host/box errada), A22 (injeção de instruções por site), A25 (modelo Alpha indisponível), A27 (atualização do runtime com rollback), A28 (disco insuficiente), A35 (seleção de modelo só da sessão), A39–A40 (hover/replay). Parte foi diluída nos ACs da SPEC1; modo privado, proxy/budget e A22 ficaram sem AC.

### 5.3 Commits (GIT) e mapeamento

| Commit | Título | Tasks |
|---|---|---|
| 2e595c4 | Add existing Agent Box design and consolidated implementation spec | design/, SPEC1 |
| 653a0b0 | Implement native terminal workspace and persistent agent library | AB-001…005 |
| 1666d8f | Package dependency resources and verify local app signature | AB-030 |
| 951dff3 | docs: split full specification into 30 implementation tasks | PLAN |
| bea46b9 | Integrate agent library, native skills, Docker desktops and control broker | AB-006…034 (89 arquivos) |
| b86e5e1 | Record live desktop verification and Keychain reconnect follow-up | AB-035 |
| 5276351 | Add scraping skill packages and persistent desktop Chromium launch | AB-036/037 |
| 713bc93 | Reuse box terminal for reviewed agents and bound Keychain reconnects | AB-038, AB-035 |
| e88a8eb | Connect native Claude launches to assigned computers through local MCP | AB-039 |
| a74e55f | Observe native Claude subagents per terminal and recover legacy Keychain reads | AB-040, AB-035 |
| c9a179e | Add assigned-box page extraction and bounded HTTP tools for native Claude | AB-041 |
| 4de2b40 | Update stopped computer images with persistent profiles and recoverable swaps | AB-042 |
| ccbdaf9 | Deliver reviewed scraping context to native children and isolate computer ownership | AB-043 |
| 0aff7eb | Route native child computer calls with independent control and cleanup | AB-044 |
| 82e1337 | Add explicit native conversation resume and verify Claude child computer flow | AB-045, AB-013 |
| c4418cc | Add opt-in box capture and evidence-backed dataset exports | AB-046 |

Todos os commits são de 16/10/2026, das 10:19 às 14:02. As tasks AB-018, AB-022 (parcial via 017), AB-024…AB-029 não têm task file próprio. AB-026, AB-027 e AB-028 estão “Planejada” no PLAN.
