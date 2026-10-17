# 02 · Auditoria técnica da camada de lógica (Core, MCP, runtime, testes)

Data: 2026-10-16 · Worktree: `otter` (branch `gabrielgreco1/test-project-suite`, commit `c4418cc`) · Escopo: `Sources/AgentBoxCore`, `Sources/AgentBoxMCP`, `runtime/`, `scripts/`, `Package.swift`, `Tests/`, além da lógica que está dentro de `Sources/AgentBox` (Terminal, Computers, Docker stores, WorkspaceView).

Todo o código citado foi lido. Referências no formato `arquivo:linha`.

---

## 0. Resumo executivo

- **Tamanho**: Core ≈ 7,9 mil linhas Swift (13 módulos), helper MCP 150 linhas, runtime Python ≈ 2,3 mil linhas, UI ≈ 6,9 mil linhas, testes ≈ 6,5 mil linhas Swift + 35 testes Python.
- **Build e testes**: `swift test` compila sem warnings e passa **172 testes, 4 pulados, 0 falhas** (13,5 s). Os testes Python do runtime (30) e do hook (5) também passam.
- **Docker**: o CLI existe (`/usr/local/bin/docker`, Docker Desktop instalado), mas **o daemon não estava rodando** (`docker info` falha: socket `~/.docker/run/docker.sock` ausente). Os 4 testes Docker **não foram executados**. E mesmo com o daemon ligado eles falhariam aqui: todos fixam o contexto `colima-agentbox-dev` (Colima não está instalado) e esperam a imagem `agentbox-browser:ab019-dev` já construída. Nenhum script do repositório constrói essa imagem.
- **Swift 6**: o pacote declara `swiftLanguageModes: [.v5]` (`Package.swift:18`). Ele **não está em Swift 6**. Compilado com `-strict-concurrency=complete`, aparecem **121 avisos únicos que viram erro no modo Swift 6**: 38 no Core (`ComputerControlBridge` 20, `CLICommandProbe` 9, `BrowserComputerService` 5, runners 4) e 83 na UI.
- **Diagnóstico geral**: o código é cuidadoso e defensivo, mas exagera na cerimônia. Uma parte grande é verificação de hash, `lstat`/permissões, "journals" e máquinas de estado distribuídas para um app pessoal de um usuário só. A lógica de produto está mal distribuída: a orquestração de lançamento, o ciclo de vida das boxes e o roteamento MCP moram em classes `@MainActor` da UI. Há acoplamento forte com um caso pessoal (a skill `webscraping-expert` aparece hardcoded no Core e na UI). Várias features são cascas: Secrets nunca é consumido, a delegação parent→child do broker só existe em testes e `DockerComputerService` é legado.
- **O que vale reaproveitar**: `Workspaces` (modelo de layout), `Git` (inspector e worktree), `Processes` (resolver e catálogo de conversas), o núcleo de `Library` (modelos e mutações), o protocolo MCP stdio e o runtime Python do container (ideia e API). **Para reescrever**: lançamento de agentes, controle e lease, ciclo de vida de computadores, captura e Secrets.

Vereditos por módulo (detalhes abaixo):

| Módulo | Linhas | Veredito |
|---|---|---|
| Domain.swift | 43 | MANTER (expandir) |
| Workspaces | 218 | MANTER |
| Git | 356 | MANTER e estender (GitHub, diff, remoção de worktree) |
| Processes | 492 | REFATORAR (leve) |
| Library | 563 | REFATORAR |
| HumanRequests | 152 | REFATORAR (fundir com notificações) |
| AgentLaunch | 1035 | REESCREVER |
| AgentRegistry | 381 | REFATORAR (simplificar) |
| ComputerMCP + AgentBoxMCP | 954 | REFATORAR (protocolo fica, transporte e provenance simplificam) |
| BrowserRuntime | 395 | MANTER o cliente, REFATORAR para Sendable |
| Control | 709 | REESCREVER (bem mais simples) |
| Docker | 1478 | REESCREVER (ciclo de vida), MANTER o runner |
| Capture | 742 | Tirar do MVP (adiar ou descartar) |
| Secrets | 391 | REESCREVER quando houver consumidor real |
| runtime/boxes (Python) | ~1,9 mil | REFATORAR (ampliar a API de controle) |
| runtime/hooks | 163 | REFATORAR junto com AgentLaunch |

---

## 1. Build, dependências e infraestrutura

### Package.swift
- Targets: `AgentBoxCore` (sem dependências), `AgentBox` (UI, depende de SwiftTerm), `AgentBoxMCP` (helper stdio) e dois test targets. O split Core/UI está correto na intenção.
- `swiftLanguageModes: [.v5]` (`Package.swift:18`): a afirmação de "Swift 6" vale só para o toolchain. Concorrência estrita não é verificada. Ver §1.3.
- `AgentBoxRuntimeTests` depende do executável `AgentBox` (UI). Testar a orquestração exige carregar a camada de UI, o que é sintoma direto da lógica estar no lugar errado.

### Dependências externas
| Dependência | Uso | Observação |
|---|---|---|
| SwiftTerm 1.20.0 (exact) | `LocalProcessTerminalView` para o PTY e o emulador (`TerminalRuntimeManager.swift:312`) | O PTY fica preso a uma `NSView`. O processo não sobrevive ao app e não existe processo "headless" sem view. É a dependência certa para emular terminal, mas a posse do PTY deveria sair dela (ver §4). |
| swift-argument-parser 1.8.2 | Transitiva do SwiftTerm | Não é usada pelo app. |
| Docker CLI (externo) | Chamado via `Process` com argv (`DockerProcessRunner.swift:52`) | Nada usa a Docker Engine API (socket). Cada operação dispara de 5 a 15 processos `docker`. |
| Claude Code CLI | Flags `--append-system-prompt-file`, `--plugin-dir`, `--mcp-config`, `--settings`, hooks `SessionStart/SubagentStart/SubagentStop/PreToolUse` com `updatedInput`, `claude agents --json` | Fortemente acoplado a recursos específicos de versão (2.1.301 citado nos comentários). |
| Codex CLI | Só `resume <id>` e `login status` | Sem ativação de agente e sem MCP (ver §3). |
| Python 3 no host | Hook `claude_event.py` | Depende do `python3` do sistema no PATH do Claude. |
| Imagem Playwright `mcr.microsoft.com/playwright/python:v1.63.0-noble@sha256:…` | Runtime da box | Pinada por digest. A tag local `agentbox-browser:ab019-dev` precisa ser construída à mão. |
| Keychain (Security, LocalAuthentication, API legada `SecKeychain*`) | Tokens das boxes e Secrets | Usa API deprecada (`LegacyKeychainInteraction.swift:10-11`) para suprimir prompts. É complexidade desnecessária: um arquivo 0600 resolveria (ver Docker). |

### Concorrência estrita (Swift 6)
Build com `-Xswiftc -strict-concurrency=complete` em scratch separado: compila com **121 avisos únicos**. Os principais no Core:
- `ComputerControlBridge.swift:278-395`: `Transport` genérico não é `Sendable`, e `BrowserRuntimeRevocationAck`, `BrowserRuntimeClient` e `BrowserRuntimeEndpoint` também não. Envio através da fronteira do actor.
- `BrowserComputerService.swift:50-66`: `KeychainReadGate.shared`, um singleton não-Sendable com closures capturadas.
- `CLICommandProbe.swift:18-66`: vars capturadas e mutadas em closures concorrentes. Hoje elas são protegidas por lock, então não há race real, mas o modo 6 rejeita o código.
- `DockerProcessRunner.swift:69,74` e `GitProcessRunner.swift:65,69`: `BoundedOutput` não-Sendable dentro de closure `@Sendable`.
- Na UI, `BrowserComputerStore`, `AgentComputerAccess` e `CapturePanelStore` concentram 59 avisos.

Migrar para o modo 6 é viável: a maior parte é marcar structs como `Sendable` e trocar classes com lock por actors. Mesmo assim, migrar código que vai ser reescrito não compensa.

### scripts/
- `build_app.sh`: build release, monta o `.app`, copia `AgentBoxMCP` e `claude_event.py`, faz assinatura ad-hoc e cria um symlink para o cache. Funciona, mas **não constrói a imagem Docker**, então o recurso de computador não funciona "out of the box". O `Info.plist` vem inline no script. MANTER a ideia e acrescentar `docker build` (ou build sob demanda no app).
- `build_spec.py`: gera a especificação HTML (documentação). Não faz parte do produto.

---

## 2. Auditoria por módulo

### 2.1 Domain.swift (43 linhas)
**Faz**: define `CLIProvider` (claude/codex/opencode/shell), `TerminalRecord`, `WorkspaceSession` e `AppPaths`.
**Riscos**: `TerminalRecord.arguments` mistura argv do usuário com argv gerado pelo lançamento de agente. O campo vira contrato frágil, e `AgentLaunchPlanner.restore` compara o argv exato (`AgentLaunchPlanner.swift:510,534`). `CLIProvider.shell` usa `zsh` fixo (`Domain.swift:10`) e ignora `$SHELL`.
**Veredito: MANTER** como semente do domínio, mas separar "o que o usuário pediu" (provider, agente, cwd) de "como foi lançado" (argv).

### 2.2 Workspaces (218 linhas)
**Faz**: árvore de splits (`WorkspaceNode`), layout por sessão, normalização e persistência JSON (`workspace.json`).
**Real**: testado com 4 testes de unidade puros, o que é adequado para lógica pura.
**Riscos**: `WorkspaceRepository.save` não define permissões, ao contrário dos outros stores (`WorkspaceStore.swift:194-200`). O limite de 5 painéis é hardcoded (`:112`). `show()` substitui o painel focado em vez de abrir outro (`:101-109`), uma regra de UX escondida no Core.
**Qualidade**: boa, pequena e legível.
**Veredito: MANTER** (eventualmente mover os limites para a camada de apresentação).

### 2.3 Git (356 linhas)
**Faz**: `GitProcessRunner` executa argv com timeout e saída limitada. `GitWorkspaceInspector` lê raiz, branch, dirty e remote. `GitRemoteNormalizer` gera URL web só para github.com. `GitWorktreeManager.createWorktree` cria worktree com branch nova e faz rollback cuidadoso.
**Não existe**: listar ou remover worktrees, diff, status por arquivo, commit, push, fetch, PR, nenhuma integração com `gh` ou com a API do GitHub. "GitHub" hoje é apenas `webURL` (`GitWorkspaceInspector.swift:95-99`).
**Testes**: reais (criam repositórios com `git init` num tmp), o que é bom.
**Riscos**:
- `GitProcessRunner.swift:77-83`: em timeout, fecha o `fileHandleForReading` enquanto threads de drain ainda podem estar em `readData`. Isso pode lançar exceção ObjC (`NSFileHandleOperationException`) e derrubar o app. O mesmo padrão está em `DockerProcessRunner.swift:83`.
- Bloqueia uma thread por chamada (semáforo). Aceitável fora do main thread, mas a UI dispara `Task.detached` para cada terminal (`WorkspaceView.swift:1045`).
**Veredito: MANTER e estender**. A base é sólida. Trocar o runner por um `ProcessRunner` único e async (compartilhado com Docker) e adicionar o que falta para "git/GitHub" ponta a ponta.

### 2.4 Processes (492 linhas)
**Faz**: `CLIExecutableResolver` procura o CLI em PATH, nvm, bun, volta, asdf e homebrew. `CLICommandProbe` roda probes (`--version`, auth). `CLIAuthStatus` interpreta o login. `CLIConversationCatalog` lista sessões Claude ativas via `claude agents --json` e monta `--resume`/`resume`/`--session`. `CLIConversationWriteCoordinator` impede dois writers da mesma conversa dentro do app.
**Real vs mock**: os resolvers são testados com executáveis fixture reais. O catálogo é testado com JSON sintético. A descoberta real de conversas Codex e OpenCode **não existe** (`CLIConversationCatalog.swift:97-100`), que exige o ID manual.
**Riscos**:
- `CLIAuthStatus.swift:17-21`: detecta o login do Codex por substring ("logged in"). É frágil.
- `discoverActiveClaude` faz polling com `Thread.sleep` (`CLIConversationCatalog.swift:175-187`). Funciona, mas bloqueia a thread.
- Só lista sessões **ativas** do Claude. Retomar uma conversa antiga exige digitar o UUID (ver `ConversationResumeView`).
**Veredito: REFATORAR (leve)**. O resolver e o catálogo valem a pena. Unificar o runner de processos e adicionar listagem do histórico (`~/.claude/projects/*/…jsonl` e `~/.codex/sessions`) para retomada útil.

### 2.5 Library (563 linhas)
**Faz**: agentes salvos com revisões, memórias com escopo (agent/project/task/preference/profile) e revisões, skills importadas (conteúdo copiado + sha256), histórico de uso. `LibraryContext.prepare` gera o texto de contexto (instruções + memórias + skills). Persiste tudo num único `library.json`.
**Stub ou parcial**:
- A memória é só escrita pelo usuário. Não existe canal para o agente propor ou gravar memória (nenhuma ferramenta MCP de memória).
- Os escopos `project`, `task` e `profile` dependem de chaves que a UI quase nunca fornece. `LibraryContext.prepare` é chamado sem `projectKey`/`taskKey` na maior parte dos caminhos.
**Bugs e riscos**:
- `LibraryRepository.swift:117`: o **conteúdo inteiro de cada skill é colado no system prompt** e, ao mesmo tempo, a skill vai como plugin (`AgentLaunchPlanner.swift:318-342`). Isso duplica contexto, anula o carregamento progressivo de skills do Claude Code e esbarra no limite de 200 KB (`LibraryRepository.swift:120`).
- `SkillImporter` só lê um arquivo. O pacote (pasta) é copiado apenas no lançamento (`AgentLaunchPlanner.snapshotSupportFiles`), o que leva a erro tardio se a pasta mudou.
- O arquivo único cresce sem limite (`history`, `agentRevisions`, `memoryRevisions`). Cada `bumpAgent` grava uma revisão nova (`LibraryMutations.swift:151-160`).
- Não há sincronização com o que o Claude e o Codex já entendem nativamente (`~/.claude/agents/*.md`, `~/.claude/skills`, `CLAUDE.md`/`AGENTS.md`). A biblioteca é um mundo paralelo.
**Qualidade**: legível. As mutações são puras, o que é bom e testável (11 testes reais em memória).
**Veredito: REFATORAR**. Manter os modelos e as mutações puras. Trocar o JSON único por arquivos por entidade (ou SQLite). Integrar com os formatos nativos dos CLIs. Parar de colar skills no prompt.

### 2.6 HumanRequests (152 linhas)
**Faz**: pedidos de intervenção humana (pending → acknowledged → resolved), deduplicação de notificação e persistência.
**Riscos**: o motivo dado pelo agente é **descartado de propósito** (`ComputerMCPToolArguments.swift:4-5,79-84`), e o pedido recebe um texto fixo (`AgentComputerAccess.swift:361-363`). O usuário não sabe por que foi chamado.
**Veredito: REFATORAR**. A ideia é boa e o código é pequeno. Fundir com um serviço de notificações e passar o motivo sanitizado.

### 2.7 AgentLaunch (1035 linhas) + runtime/hooks
**Faz de verdade**: para **Claude** apenas, gera um diretório por plano (`LaunchContexts/<uuid>/`) com `context.md` (via `--append-system-prompt-file`), um plugin com as skills (`--plugin-dir`), `computer.mcp.json` + capability (`--mcp-config`) e `hooks.settings.json` + cópia de `claude_event.py` (`--settings`). Tudo passa por sha256, `O_EXCL|O_NOFOLLOW`, `lstat` em cada diretório pai, revalidação em `restore` e de novo em `start`.
**Stub ou export-only**: **Codex, OpenCode e shell não ativam agente** (`AgentLaunchPlanner.swift:365-373`). O plano vira `exportOnly` e o terminal não é criado (`:489-492`). Para Codex existem caminhos viáveis (`AGENTS.md` no cwd, `-c model_instructions_file=…`, `-c mcp_servers.*`), nenhum implementado. O computador via MCP é exclusivo do Claude (`:307`).
**Bugs e riscos**:
- Hardcode do caso pessoal: o nome `webscraping-expert` vira regra de produto no Core (`AgentLaunchPlanner.swift:344-347,433,613-619`). A UI ainda exige que o terminal pai tenha sido lançado com esse agente para que subagentes possam usar computador (`TerminalRuntimeManager.swift:185-193`, chamado por `AgentComputerAccess.swift:412`).
- `MaterializedAgentLaunch.binding` faz force-unwrap de `pluginDirectory!` (`AgentLaunchPlanner.swift:120`) e usa `Dictionary(uniqueKeysWithValues:)`, que trava o app se houver chave duplicada.
- `removeContextFile` aborta no primeiro `removeItem` que falhar (`:577-605`) e deixa a limpeza pela metade. Nada chama a limpeza de forma sistemática, então `LaunchContexts/` acumula.
- O contexto do subagente é injetado via hook `SubagentStart` em até 9 pedaços de 8 KB (`ClaudeHookLaunchSnapshot.swift:189-218`, `claude_event.py:20-59`). É engenhoso, mas frágil e específico de uma versão do Claude.
- `restore` exige que o argv persistido bata exatamente com o recomputado (`:534`). Qualquer mudança de flag invalida todos os terminais salvos.
- `ClaudeHookInboxConfiguration.create` (`ClaudeHookInbox.swift:12-38`) é usado **só em testes**. Em produção, o caminho é `prepareInvocation`. Os dois geram settings diferentes (o de teste não tem `PreToolUse`).
**Qualidade**: correto e muito defensivo, mas com custo alto de leitura. Cerca de 60% das linhas são validação de integridade contra um atacante local que já teria o mesmo UID. O modelo "plano → revisão por hash → materialização → binding → restore" é pesado para o fluxo "abrir terminal já no agente".
**Veredito: REESCREVER**. Um `LaunchSpec` por provider (adapter Claude, adapter Codex, shell), gerado no momento do start, sem cerimônia de hash, com diretório temporário por execução e limpeza no exit. Remover o caso scraping do Core.

### 2.8 AgentRegistry (381 linhas)
**Faz**: `AgentRunRegistry` (actor) grava as execuções de terminal e de subagentes nativos (`AgentRuns.json`). `ClaudeHookInbox` lê `events.jsonl` escrito pelo hook, verifica HMAC e admite os eventos `SessionStart`/`SubagentStart`/`SubagentStop`.
**Real**: o fluxo hook → inbox → registry é testado com o script Python real (`NativeAgentMonitorTests`, `AgentRegistryTests`). O subagente detectado é o subagente **nativo do Claude** (Task tool), que roda dentro do mesmo processo no host.
**Bugs e riscos**:
- A HMAC não é fronteira de segurança: o token fica no ambiente do processo Claude (`TerminalRuntimeManager.swift:364-366`), e o modelo pode lê-lo com `env` via Bash e forjar eventos ou route tokens. Serve para correlação, não para autenticação. Os comentários prometem mais do que entregam.
- Uma linha inválida no inbox lança erro sem avançar o cursor (`ClaudeHookInbox.swift:91-95`). O inbox fica preso para sempre naquela execução.
- O inbox é limitado a 1 MiB: o hook para de escrever em silêncio (`claude_event.py:148`) e o drain lança `oversizedInbox` (`ClaudeHookInbox.swift:82-86`).
- O registry cresce sem limite e reescreve o arquivo inteiro a cada evento (`AgentRunRegistry.swift:229-236`). Subagentes de execuções encerradas por crash ficam `running` para sempre (comentário em `:165`).
- `NativeAgentMonitor` relê o arquivo inteiro a cada 300 ms por terminal (`NativeAgentMonitor.swift:159-164`).
- `AgentIdentityCapability` (`AgentRegistry.swift:4-16`) é um valor estático que ninguém usa para decisão real.
**Veredito: REFATORAR**. O registry de execuções e a árvore de subagentes via hooks é a abordagem certa. Simplificar: socket local ou FIFO em vez de arquivo + polling, e sem HMAC teatral (ou admitir que é só correlação).

### 2.9 ComputerMCP (804 linhas) + AgentBoxMCP (150 linhas)
**Faz**:
- `ComputerMCPProtocol`: servidor JSON-RPC MCP (initialize, tools/list, tools/call) com 9 ferramentas (`computer_status/acquire/screenshot/page/http_request/mode/navigate/input/request_help`).
- `AgentBoxMCP/main.swift`: helper stdio que o Claude lança. Encaminha cada linha JSON-RPC para um socket Unix do app com uma capability.
- `LocalMCPChannel`: servidor de socket Unix com uma conexão por requisição, até 8 em paralelo, e timeouts.
- `ComputerCallProvenance`: valida o `route_token` HMAC que o hook `PreToolUse` injeta nos argumentos (via `updatedInput`) para saber se quem chama é o pai ou qual subagente.
- `ComputerMCPAccessPolicy`: decide connect/start/create para `computer_acquire`.
**Real**: o socket e o helper são testados com processos reais (`LocalMCPChannelTests`). O protocolo é testado em unidade. O fluxo completo com Claude real existe só no teste gated `NativeChildFlowDockerTests` (custa até US$ 0,25 e exige Docker), que **não foi executado**.
**Bugs e riscos**:
- `LocalMCPChannel.swift:286-297`: cada requisição bloqueia uma thread GCD num semáforo enquanto uma `Task` roda o handler. Com 60 s de timeout (`:27`), um `computer_acquire` que cria container, sobe o Chromium e tenta o endpoint 8×0,5 s (`AgentComputerAccess.swift:496-513`) pode estourar o prazo. O agente recebe "Handler timed out" enquanto a criação continua em segundo plano.
- Se o app fecha, o helper sai com código 3 (`main.swift:142,149`) e o Claude perde o servidor MCP sem reconexão.
- O `instructions` do MCP (`ComputerMCPProtocol.swift:40`) é um parágrafo longo com regras de produto embutidas.
- As ferramentas são limitadas: `click` não recebe coordenadas (exige `move` antes, ou seja, duas chamadas), e não há drag, double-click, digitação em seletor, espera, JS ou download. Em modo `headless` o agente só navega e lê texto (`engine.py:416-420`: "input requires desktop mode"). Não dá para preencher formulário sem desktop.
- O schema aceita `route_token` como propriedade (`:85`), um detalhe interno exposto ao modelo.
**Qualidade**: o protocolo é limpo. O transporte (helper + socket + capability + HMAC por chamada + nonce/replay) é sofisticado demais. Uma alternativa simples é o app servir MCP via HTTP/SSE em loopback com token por execução, ou o helper falar direto com o runtime da box.
**Veredito: REFATORAR**. Aproveitar `ComputerMCPProtocol` e `ComputerMCPToolArguments` (com a API ampliada). Simplificar o transporte. A identificação do subagente pode continuar via hook, mas sem exigir o lançamento "scraping".

### 2.10 BrowserRuntime (395 linhas)
**Faz**: cliente HTTP autenticado (Bearer) para a API da box em `127.0.0.1:<porta>`, com rotas de health, page, frame, navigate, input, mode, http/request, capture e grant/revoke. Valida a identidade (computerID e generation) em cada resposta e rejeita redirect.
**Real**: testado com `URLProtocol` fake (13 testes). Contra a box real, só nos testes Docker não executados.
**Riscos**: `page()` e `desktopFrame()` fazem um `health()` extra por chamada (`BrowserRuntimeClient.swift:279,315,326`). Os tipos não são `Sendable`. `capture()` usa force-unwrap de `URLComponents` (`:211`).
**Veredito: MANTER** o cliente (é a parte mais limpa do Core), marcar como `Sendable` e acompanhar a API ampliada do runtime.

### 2.11 Control (709 linhas)
**Faz**: `ControlBroker` (actor, persistido em `ControlBroker.json`) mantém um "writer" por computador, com epoch, revogação com ACK e manutenção. `ComputerControlBridge` coordena broker, lease do runtime e ticket local, e executa writes (input, navigate, mode, http).
**Stub ou dead code**: a delegação parent→child (`requestChild`, `revokeChild`, `delegatedFrom`; `ControlBroker.swift:179-223`) **não é usada em produção**, só nos testes. A persistência é quase inútil, porque no load tudo é zerado exceto `nextEpoch` (`:95-103`).
**Bugs e riscos**:
- Qualquer erro numa escrita (por exemplo, a URL não carregou e o runtime devolveu 409) chama `streamDisconnected()`, que **revoga o lease** (`ComputerControlBridge.swift:278-288`). Para o humano no viewer, um erro de input derruba o controle.
- `leaseOperationInProgress` faz chamadas concorrentes falharem com `transitionInProgress` em vez de entrar em fila (`:76,115,…`). Tool calls paralelas do Claude e um viewer abrindo ao mesmo tempo geram erros intermitentes.
- Cada `assumeAgent` faz de 2 a 3 `health()` e de 2 a 3 escritas atômicas de JSON no disco (`ControlBroker.persist`).
- A maior concentração de avisos Swift 6 do Core (20).
**Qualidade**: estado duplicado em três lugares (broker, bridge e runtime Python) que precisam concordar. Difícil de raciocinar.
**Veredito: REESCREVER**. Para um usuário só, basta isto: o runtime da box guarda quem controla (`agent` | `human`), e o app expõe "assumir" e "devolver" com uma única fonte de verdade (o próprio runtime), sem broker persistido.

### 2.12 Docker (1478 linhas)
**Faz**:
- `DockerProcessRunner`: argv + timeout + contexto Docker escolhido (`docker-connection.json`).
- `BrowserComputerService`: cria, inicia e para containers da imagem `agentbox-browser:ab019-dev` (`BrowserComputerService.swift:259`), com volume `/data` persistente, porta publicada só em loopback, hardening (`--read-only`, `--cap-drop ALL`, `no-new-privileges`, limites) e token por computador no Keychain passado via env-file temporário. Atualiza a imagem de box parada com journal de recuperação (`:427-504,799-872`).
- `ComputerPolicy`: política global com overrides por projeto/sessão/terminal/agente, que só podem restringir.
- `DockerComputerService`: box **legada** `python:3.12.8-slim … sleep infinity` sem browser (`DockerComputerService.swift:41,115`), ainda exposta em `DockerViews.swift:190-220`.
- `ScrapingBoxAssignmentStore`: amarra uma box ao agente "Web scraping".
**Stubs e lacunas**:
- **Não há remoção de computador**: nenhuma API faz `docker rm` ou `volume rm` de uma box (só o rollback de criação, `:391-392`). Cada subagente que chama `computer_acquire` cria **container + volume novos** (owner = run ID único, `:326-399`). Eles são parados, mas nunca apagados. Isso vaza disco e entradas de Keychain.
- O app não constrói a imagem. Sem build manual, `createAndStart` falha.
- Não há modo "subagente CLI dentro do Docker": a box é só um navegador/desktop controlado remotamente. O CLI do agente sempre roda no Mac.
**Bugs e riscos**:
- **Defaults incompatíveis**: a política padrão tem `creation = .disabled` (`ComputerPolicy.swift:71`) e `memoryMiB = 768` (`:13`), mas o browser exige ≥ 2048 MiB (`BrowserComputerService.swift:340`). Instalação nova, recurso desligado e, mesmo ligando, ele falha até a memória ser ajustada à mão.
- Desempenho: `list()` faz `docker inspect` por container (N+1, `:274-281`). `verifyCurrentOwnedComputer` faz inspect + mounts + volume inspect + leitura de metadata (`:583-593`). Um `acquire` dispara mais de 10 processos `docker`.
- `ComputerCreationLock` é um `NSRecursiveLock` global (`DockerComputerService.swift:3`) segurado durante chamadas Docker de até 120 s.
- O token fica no Keychain com contorno da API legada para evitar prompts (`:112-149`, `LegacyKeychainInteraction.swift`) e um "gate" que lança erro se houver leitura em voo (`:48-91`). É complexidade grande para um segredo efêmero de loopback.
- O risco de exceção ObjC no timeout do runner, citado em Git, vale aqui também (`DockerProcessRunner.swift:83`).
- O journal de atualização de imagem (≈ 250 linhas) é engenharia de banco de dados para um caso raro.
**Veredito: REESCREVER o ciclo de vida** (criar, iniciar, parar, **remover**, listar com um único `docker ps --format json`, build e pull da imagem, defaults coerentes, token em arquivo 0600 ou em memória). **MANTER** o runner (unificado) e os flags de hardening. Remover `DockerComputerService` e `ScrapingBoxAssignment`.

### 2.13 Capture (742 linhas)
**Faz**: puxa eventos de rede capturados na box (Playwright) com filtros de host, caminho e campos JSON, persiste com hash por evento e retenção, e gera "datasets" com colunas extraídas de campos JSON de topo, exportando CSV/JSON com manifest e proteção contra CSV injection.
**Real**: os stores são testados em disco real (7 testes). O fluxo com box real fica no teste Docker não executado.
**Riscos**: `load()` re-hasheia todos os registros a cada leitura (`CaptureStore.swift:166-171`). Com polling, isso é O(n) de JSON encoding por ciclo. O recurso é específico de scraping e não está na lista de funcionalidades principais.
**Veredito: tirar do MVP**. Se voltar, deve ser como plugin opcional.

### 2.14 Secrets (391 linhas)
**Faz**: importa `.env` com parser estrito, guarda valores no Keychain e metadados em JSON, e mantém "grants" por escopo/uso/destino.
**Stub**: **nenhum código de produção chama `SecretVault.resolve`** (verificado por grep). Os segredos nunca chegam ao ambiente de um terminal nem a uma ferramenta. É uma tela de cadastro sem efeito.
**Veredito: REESCREVER quando houver consumidor** (por exemplo, injeção explícita de variáveis no env do PTY por sessão). O `EnvFileParser` pode ser mantido.

### 2.15 runtime/boxes (Python, ≈ 1,9 mil linhas)
**Faz**: servidor HTTP (`server.py`) dentro do container com modos `http` (sem browser), `headless` (Playwright persistente) e `desktop` (Xvfb + Openbox + Chromium + xdotool). Expõe page text sanitizado, frame JPEG, MJPEG 4 fps, input X11, navigate, GET/HEAD público com bloqueio de IP privado e pinning de DNS (`public_http.py`), captura de rede e lease de controle.
**Real**: 30 testes Python com browser e display fakes passam. O smoke Docker (`smoke_docker.py`) é restrito ao contexto Colima.
**Riscos**:
- Todos os POSTs seguram `engine.lock` (`server.py:120`), e `frame()`/`page()` também (`engine.py:388,394`). Um `navigate` de até 15 s bloqueia screenshot e viewer.
- O servidor escuta em `0.0.0.0:8765` dentro do container (`server.py:174`). A publicação é só em loopback, mas qualquer outro container na rede `bridge` consegue alcançar a porta (o token protege).
- O viewer humano usa MJPEG a 4 fps. Não há VNC/noVNC nem áudio, e a latência fica alta para intervenção humana (login, CAPTCHA).
- A API de interação é mínima (ver §2.9).
**Veredito: REFATORAR**. A escolha de Playwright + Xvfb é boa. Ampliar as ações (click com coordenadas, type, wait, select, download e scroll em headless via Playwright), trocar o MJPEG por noVNC/WebRTC para o humano e tirar o lock global das leituras.

---

## 3. Lógica que está na UI e precisa ir para o Core

| Arquivo (UI) | Linhas | Lógica de domínio dentro | Destino no novo Core |
|---|---|---|---|
| `Terminal/TerminalRuntimeManager.swift` | 429 | Posse dos PTYs e do ciclo de vida do processo, env do processo filho (`:353-368`), sinais por process group (`:332-343`), decodificação de wait status, manutenção de computador, retomada de conversa, ligação com hooks | `SessionRuntime`/`PTYHost` no Core. A UI só anexa o renderer. Hoje o PTY é a própria `NSView` do SwiftTerm, então não há como testar ou rodar headless. |
| `Terminal/NativeAgentMonitor.swift` | 191 | Polling do inbox, reconciliação de execuções anteriores, verificação do caller | `AgentRunService` (Core) |
| `Computers/AgentComputerAccess.swift` | 516 | Roteamento MCP completo: verificação de provenance, resolução do caller, criação de box por subagente, lease, execução de ferramentas, cleanup e retirada, pedidos humanos | `ComputerAccessService` (Core). É o coração da feature e está num `@MainActor ObservableObject` (22 avisos Swift 6). |
| `Docker/BrowserComputerStore.swift` | 453 | Orquestração de criação, start e stop, atualização de imagem, reconexão, criação do agente padrão de scraping (`:159-169`) | `ComputerService` (Core) + view model fino |
| `Capture/CapturePanelStore.swift` | 483 | Polling de captura, configuração persistida, datasets e export | Plugin opcional (se for mantido) |
| `Workspace/WorkspaceView.swift` | 1682 | `launchSavedAgent` (`:1145-1257`): validação, persistência de bindings e workspace, registro MCP, start, ativação, gravação de histórico e rollback; `startTerminalValidated` (`:1287+`); `refreshGit` e `createWorktree` (`:1034-1112`); `computerPolicyContext` (`:1069-1074`) | `LaunchService`, `WorkspaceService`, `GitService` (Core). A View deve só chamar `launch(agent:in:)`. |
| `Workspace/AgentLaunchBindingStore.swift` | 34 | Persistência de bindings | Core (ou eliminado com a reescrita do launch) |
| `Workspace/WorkspaceDirectoryAccess.swift` | 119 | Bookmarks de pasta (security-scoped) | Core/Platform. O app não é sandboxed, então vale reavaliar se isso é necessário. |
| `Library/LibraryStore.swift` | 124 | `createScrapingAgent` lê `~/.claude/skills/webscraping-expert/SKILL.md` hardcoded (`:93-123`) | Remover o caso pessoal. Expor a importação genérica de skills no Core. |
| `Computers/HumanRequestCenter.swift`, `BrokerDesktopActions.swift`, `DesktopBrokerService` (`AgentComputerAccess.swift:7-38`) | ~230 | Singleton de bridges por computador, liberação de controle no quit, notificações | Core (`ComputerControlService`, `NotificationService`) |
| `App/AppSettingsView.swift` | 99 | Probes de versão e auth dos CLIs | Core (`CLIHealthService`) |

Padrão recorrente: singletons `@MainActor` (`AgentComputerAccess.shared`, `NativeAgentMonitor.shared`, `DesktopBrokerService`, `WorkspaceServices.terminalRuntime`, `HumanRequestCenter.shared`) acoplados entre si por Combine `sink`. Sem injeção de dependência, sem fronteira de testes.

---

## 4. O que é necessário para cada funcionalidade principal funcionar ponta a ponta

### 4.1 Abrir terminal já no agente escolhido
- **Hoje**: funciona só para **Claude**, depois de passar por plano → revisão → materialização → binding. Codex, OpenCode e shell ficam em `exportOnly` e o terminal não abre (`AgentLaunchPlanner.swift:365-373,489-492`).
- **Falta**:
  1. Um adapter por provider. Claude: `--append-system-prompt-file`, `--agents`/`.claude/agents`, `--plugin-dir`, `--mcp-config`. Codex: `AGENTS.md` no cwd ou `-c model_instructions_file`, `-c mcp_servers.*`, `--profile`. Shell: só o cwd e o env.
  2. Env completo do usuário (hoje a allowlist em `TerminalRuntimeManager.swift:355` remove `SSH_AUTH_SOCK`, proxies, `ANTHROPIC_*`, `OPENAI_*`, `GH_TOKEN` e afins, o que quebra `git push` via ssh e configurações por env), ou execução via login shell (`$SHELL -lc exec …`) para herdar o PATH e o rc do usuário.
  3. Skills por referência (plugin ou link), não coladas no prompt.
  4. Limpeza do diretório temporário no exit do processo.

### 4.2 Multi-terminal / PTY
- **Hoje**: SwiftTerm `LocalProcessTerminalView` por terminal, splits até 5 painéis e retenção do renderer entre trocas de painel. Funciona (testes PTY reais em `ProcessesPTYTests`).
- **Limites**: os processos morrem quando o app fecha (`shutdown`, `TerminalRuntimeManager.swift:262-282`), e no relaunch todos os terminais voltam `idle`. Não há reattach nem scrollback persistido. O PTY é uma `NSView`, então não há teste sem AppKit e nenhuma API para o Core escrever no PTY ou ler a saída.
- **Falta**: separar o PTY (`forkpty`/`posix_spawn` com `openpty`) do emulador. Opcionalmente, um daemon ou tmux para sobreviver ao restart da UI. Com isso vêm um buffer de saída no Core (para status e notificações), o resize e envio de input pelo Core, e o uso de `$SHELL` em vez de `zsh` fixo.

### 4.3 Spawn de subagente em Docker (headless e com GUI)
- **Hoje**: "subagente" significa o subagente **nativo do Claude** (Task tool), que roda no Mac dentro do processo do pai. O que vai para o Docker é **o computador do subagente** (navegador/desktop), criado sob demanda via `computer_acquire` quando a política é `automatic`. Exige que o pai tenha sido lançado com o agente "Web scraping" (`TerminalRuntimeManager.swift:185-193`).
- **Headless**: só navegar e ler texto/links/screenshot. Sem interação (`engine.py:416-420`).
- **GUI**: desktop Xvfb + Chromium, input xdotool por coordenadas e viewer MJPEG.
- **Falta**:
  1. Decidir se "subagente em Docker" significa rodar **o CLI do subagente dentro do container** (imagem com claude/codex, workspace montado, credenciais injetadas, PTY do container anexado como terminal no app via `docker exec -it`/attach). Isso **não existe hoje**.
  2. Build e pull da imagem pelo app.
  3. Defaults de política coerentes (`creation`, `memory`).
  4. Remoção de containers e volumes no fim.
  5. Desacoplar do caso scraping.
  6. Ações headless de verdade via Playwright.

### 4.4 Controle do computador pelo agente via MCP
- **Hoje**: Claude → `AgentBoxMCP` (stdio) → socket Unix → `AgentComputerAccess` (@MainActor) → `ComputerControlBridge` + `ControlBroker` → HTTP para a box. O roteamento pai/filho usa um token HMAC que o hook `PreToolUse` injeta via `updatedInput`. Isso só foi validado de ponta a ponta no teste gated que não rodou aqui.
- **Falta**:
  1. Suporte a Codex (MCP via `-c mcp_servers`).
  2. Um conjunto de ferramentas utilizável (click/type com coordenadas ou seletor, wait, scroll, download, `computer_use` compatível com a ferramenta de computer use da Anthropic).
  3. Timeouts compatíveis com a criação de box (acquire assíncrono com status).
  4. Reconexão do helper.
  5. Um controle humano/agente simples, sem revogar o lease em qualquer erro.

### 4.5 Git / GitHub
- **Hoje**: inspeção (branch, dirty, remote) e criação de worktree com branch nova. URL do GitHub apenas exibida.
- **Falta**: listar e remover worktrees, diff e status por arquivo, commit, push e fetch (com o env ssh do usuário, ver 4.1), integração `gh` (PRs, checks, review) e associação sessão ↔ worktree ↔ branch ↔ PR. Atualização reativa via FSEvents em vez de refresh manual.

### 4.6 Biblioteca de agentes, skills e memória
- **Hoje**: CRUD de agentes, memórias e skills com revisões, num único JSON. O contexto é gerado como texto. A memória só é escrita pelo usuário.
- **Falta**:
  1. Sincronizar com os formatos nativos (`~/.claude/agents`, `~/.claude/skills`, `CLAUDE.md`, `AGENTS.md`, `~/.codex`) em vez de um mundo paralelo.
  2. Ferramenta MCP para o agente ler e propor memória (com aprovação).
  3. Skills por referência.
  4. Armazenamento por arquivo ou SQLite.
  5. Escopos de memória que a UI realmente preencha (projeto = raiz git).

---

## 5. Os testes testam algo real?

| Categoria | Arquivos | Avaliação |
|---|---|---|
| **Reais (processo, disco, socket)** | `ProcessesPTYTests` (PTY real com scripts fixture), `LocalMCPChannelTests` (socket Unix + helper real), `GitWorkspaceTests` (git real), `AgentLaunchTests` (FS real + executável fixture), `NativeAgentMonitorTests`/`AgentRegistryTests` (hook Python real), `CaptureStoreTests`, `LibraryTests`, `WorkspaceStoreTests` | Bons e honestos. Cobrem a integridade dos arquivos e o fluxo hook → registry. |
| **Mock de fronteira externa** | `BrowserComputerServiceTests`, `BrowserImageUpdateTests`, `DockerComputerTests` (runner Docker fake que devolve stdout programado), `BrowserRuntimeTests` (URLProtocol fake), `ComputerControlBridgeTests` (transport fake), `SecretsTests` (Keychain em memória), `AgentComputerAccessRoutingTests` (resources fakes) | Testam a lógica do Swift contra **o que o autor supôs** que o Docker e o runtime respondem. Não pegam divergência real de CLI ou API. O update de imagem tem 12 testes de mock contra 1 real (gated). |
| **Gated, exigem Docker** | `BrowserChildControlDockerTests`, `BrowserImageUpdateDockerTests`, `CaptureDockerTests`, `NativeChildFlowDockerTests` (este chama o **Claude real**, `--model haiku`, até US$ 0,25) | **Não executados**: daemon parado. Além disso, fixam o contexto `colima-agentbox-dev` (inexistente nesta máquina) e a imagem `agentbox-browser:ab019-dev` (nenhum script a constrói). Não são portáveis. |
| **Unidade pura** | Policy, protocol, arguments, provenance, broker, human requests, scraping target | Corretos, mas parte testa código morto (delegação do broker). |

Conclusão: a suíte valida bem a **mecânica interna** (integridade de arquivos, parsing, máquinas de estado) e a fronteira PTY/socket/git. Ela **não valida os fluxos de produto** com as dependências reais (Docker, runtime, Claude), que ficam atrás de flags e de um ambiente específico do autor. Nada testa a UI nem a orquestração em `WorkspaceView`.

Resultados executados nesta auditoria:
- `swift test`: 172 executados, 4 pulados, 0 falhas, 0 warnings (13,5 s).
- `swift build -strict-concurrency=complete`: OK, com 121 avisos únicos de Swift 6.
- `python3 -m unittest` em `runtime/boxes`: 30 OK. Em `runtime/hooks`: 5 OK.
- Testes Docker (`AGENTBOX_TEST_CAPTURE_DOCKER`, `AGENTBOX_TEST_DOCKER_UPDATE`, `AGENTBOX_TEST_CHILD_CONTROL`, `AGENTBOX_TEST_NATIVE_CHILD_FLOW`): **não executados** (Docker Desktop instalado mas daemon parado; contexto Colima exigido não existe).

---

## 6. Lista consolidada de bugs e riscos concretos

| # | Severidade | Local | Problema |
|---|---|---|---|
| 1 | Alta | `ComputerPolicy.swift:13,71` + `BrowserComputerService.swift:340` | Defaults (`disabled`, 768 MiB) impedem a feature principal. Exigem ≥ 2048 MiB e ajuste manual. |
| 2 | Alta | `BrowserComputerService.swift` (sem `delete`) + `AgentComputerAccess.swift:424-443` | Cada subagente cria container + volume + token novos que nunca são removidos. Vaza disco e Keychain. |
| 3 | Alta | `TerminalRuntimeManager.swift:355` | A allowlist de env remove `SSH_AUTH_SOCK`, proxies e chaves de API do ambiente dos agentes. Quebra `git push` via ssh e configs por env. |
| 4 | Alta | `AgentLaunchPlanner.swift:365-373` | Codex, OpenCode e shell não abrem "no agente": só export. |
| 5 | Alta | `AgentLaunchPlanner.swift:344-347`, `TerminalRuntimeManager.swift:185-193`, `LibraryStore.swift:93-123` | A skill pessoal `webscraping-expert` está hardcoded como pré-requisito de produto. |
| 6 | Média | `LibraryRepository.swift:117` + `AgentLaunchPlanner.swift:318-342` | Skill duplicada no system prompt e no plugin. Contexto inflado e limite de 200 KB. |
| 7 | Média | `ComputerControlBridge.swift:278-324` | Qualquer erro numa escrita revoga o lease (agente ou humano perde o controle). |
| 8 | Média | `ComputerControlBridge.swift:76…` | Chamadas concorrentes falham (`transitionInProgress`) em vez de entrar em fila. |
| 9 | Média | `LocalMCPChannel.swift:27,286-297` | Timeout de 60 s com thread bloqueada. `computer_acquire` lento pode estourar e continuar em segundo plano. |
| 10 | Média | `DockerProcessRunner.swift:83`, `GitProcessRunner.swift:77-83` | `closeFile` no timeout com drain em andamento pode lançar exceção ObjC e derrubar o app. |
| 11 | Média | `ClaudeHookInbox.swift:91-95` | Linha inválida trava o inbox (cursor não avança). Limite de 1 MiB silencioso. |
| 12 | Média | `TerminalRuntimeManager.swift:364` + `ComputerCallProvenance` | O token HMAC fica no env do processo Claude. O modelo pode lê-lo, então a "autenticação" de caller não é fronteira real. |
| 13 | Média | `engine.py:416-420` | Headless sem interação. Formulários exigem modo desktop. |
| 14 | Média | Package/scripts | A imagem Docker não é construída pelo app nem pelos scripts. Os testes Docker fixam o contexto Colima. |
| 15 | Baixa | `AgentLaunchPlanner.swift:120` | Force-unwrap de `pluginDirectory!` e `Dictionary(uniqueKeysWithValues:)` podem travar o app. |
| 16 | Baixa | `AgentLaunchPlanner.swift:572-607` | Limpeza do launch para no primeiro erro, e `LaunchContexts/` acumula. |
| 17 | Baixa | `AgentRunRegistry.swift:229-236`, `LibraryMutations.swift:151-160` | Arquivos JSON únicos crescem sem limite e são reescritos inteiros a cada evento. |
| 18 | Baixa | `ComputerMCPToolArguments.swift:79-84` / `AgentComputerAccess.swift:361-363` | O motivo do pedido de ajuda é descartado, e o usuário recebe texto genérico. |
| 19 | Baixa | `Package.swift:18` | Modo de linguagem Swift 5. 121 diagnósticos impedem o modo 6. |
| 20 | Baixa | `server.py:120`, `engine.py:388-394` | Lock global: navegação longa bloqueia screenshot e viewer. |

---

## 7. Recomendação para a reconstrução

1. **Novo Core com serviços explícitos e testáveis**, todos actors `Sendable`, em Swift 6 estrito desde o início: `WorkspaceService`, `PTYHost` (PTY separado do emulador), `LaunchService` (adapters Claude/Codex/Shell), `AgentRunService` (hooks → árvore de subagentes), `ComputerService` (ciclo de vida Docker completo, incluindo remoção e build da imagem), `ComputerControlService` (fonte única de verdade = runtime da box), `MCPServerHost`, `GitService` (+ `gh`) e `LibraryService` (formatos nativos dos CLIs). A UI passa a consumir só view models.
2. **Copiar e adaptar** (não reescrever do zero): `Workspaces`, `Git`, `CLIExecutableResolver`, `CLIConversationCatalog`, `BrowserRuntimeClient`, `ComputerMCPProtocol`/`ToolArguments`, `EnvFileParser`, os modelos de `Library`, `LibraryMutations`, os flags de hardening do `docker create` e o runtime Python (ampliado).
3. **Descartar**: a cerimônia hash/review/binding do launch, `ControlBroker` persistido e delegação, journal de atualização de imagem, `DockerComputerService` legado, `ScrapingBoxAssignment`/`ScrapingLaunchTarget`, Keychain para tokens efêmeros e Capture (fora do MVP).
4. **Decisão de produto pendente** que muda a arquitetura: "subagente em Docker" significa (a) o subagente nativo do CLI no Mac usando um computador no container (o que existe hoje) ou (b) o próprio CLI rodando dentro do container, com terminal anexado no app (não existe). A opção (b) exige imagem com CLIs, montagem do workspace, injeção de credenciais e attach de PTY remoto.
5. **Testes**: manter os testes reais (PTY, socket, git) como padrão. Tornar os testes Docker portáveis (contexto atual ou `DOCKER_CONTEXT`, build da imagem no setup) e rodá-los em CI local. Criar testes de serviço para a orquestração que hoje está na `WorkspaceView`.
