# 05 · Lacunas nas funcionalidades centrais

Auditoria de 16/10/2026 sobre o checkout `gabrielgreco1/test-project-suite` (HEAD `c4418cc`). Objetivo: medir a distância entre o código atual e um app bom nas cinco funcionalidades que o dono considera centrais, para alimentar a spec da reconstrução. Nenhum código foi alterado.

Fontes lidas: `Sources/AgentBoxCore`, `Sources/AgentBox`, `Sources/AgentBoxMCP`, `runtime/boxes`, `runtime/hooks`, `docs/STATUS.md`, `docs/EXECUTION-PLAN.md`, `docs/spec/index.html`, `docs/spec/acceptance.json` (68 casos, **todos ainda `planned`**), `docs/spec/backlog.json` (M0–M10, **todos `not_started`**), `docs/tasks/AB-*`, `git log`. Referências no formato `arquivo:linha`.

Legenda de estado:

- **Ponta a ponta**: a UI chama o código real e o fluxo foi exercitado com processo/container real.
- **Parcial**: funciona com limites relevantes, ou só por um caminho.
- **Só modelo**: tipo, campo ou serviço sem UI ou sem integração.
- **Ausente**: não existe.

## Ambiente local verificado

| Item | Resultado |
|---|---|
| `claude` | `~/.local/bin/claude`, 2.1.302 |
| `codex` | `~/.local/bin/codex`, codex-cli 0.160.0 |
| `opencode` | `~/.local/bin/opencode`, 1.18.34 (instalado; o código ainda diz que não estava, `CLIConversationCatalog.swift:95`) |
| `gh` | `/opt/homebrew/bin/gh` 2.93.0, logado como `gabrielgreco1` via keyring, escopos `gist, read:org, repo, workflow` |
| `docker` | CLI 29.6.2; contexto ativo `desktop-linux`, **daemon parado** (socket ausente). `colima` não está no PATH nem em `~/.colima`, embora `STATUS.md:17` diga que foi instalado. Imagem `agentbox-browser:*` não existe localmente |
| `~/.claude/agents` | 13 agentes `.md` (data-engineer, llm-engineer, ocr-engineer, qa-engineer, rti-analyst, rti-crawler-builder, security-diff-reviewer, swift-desktop-optimizer, swiftui-ux-designer, ui-mockup-designer, web-scraper, webscraper-engineer, webscraping-expert) |
| `~/.claude/skills` | 133 entradas (pastas e alguns `.zip`), incluindo `agentbox`, `webscraping-expert`, família `hunt-*`, `rti-*`, `motion-designer` |
| `~/.agents/skills` | ~30 skills compartilhadas (padrão cross-harness) |
| `~/.codex/agents` | 12 agentes `.toml`, espelho dos agentes Claude |
| `~/.codex/skills` | `frontend-design`, `web-design-guidelines`, `webscraping-expert` (caminho antigo; o Codex atual lê `~/.agents/skills`) |
| Sessões nativas | `~/.claude/projects` com 36 pastas de projeto; `~/.codex/sessions/2026/{09,10}`; OpenCode em SQLite |
| Plugins Claude | `swift-lsp`, `vercel` (`~/.claude/plugins/installed_plugins.json`) |
| OpenCode | `~/.config/opencode/opencode.jsonc` + `plugins/` |
| CLI anterior | `~/orca/projects/agentbox` (`bin/agentbox`, `collect.py`, `timeline.py`, `image/Dockerfile`) com ~40 runs em `runs/`. É a ferramenta que o dono de fato usou para scraping |

Duas conclusões do ambiente valem para tudo abaixo:

1. O Docker não roda hoje e a imagem não existe. O app não constrói a imagem (nenhum `docker build` em `Sources/` ou `scripts/`; a tag fixa é `agentbox-browser:ab019-dev`, `BrowserComputerService.swift:259`). Um usuário novo não consegue criar um computador sem passos manuais fora do app.
2. O dono tem bibliotecas grandes e já organizadas nos formatos nativos (Claude, Codex, `~/.agents`). O app reimporta uma skill por vez, por seletor de arquivo.

## Resumo executivo

| # | Funcionalidade | Estado | Maior lacuna | Prioridade |
|---|---|---|---|---|
| a | Abrir terminal no agente escolhido | Parcial | Sem flags/modelo/permissão no diálogo; terminal não inicia sozinho; retomada exige colar ID; sem histórico de conversas; env do PTY descarta `SSH_AUTH_SOCK` e similares | P0 |
| b | Subagentes com Docker | Parcial (só Claude, só via biblioteca) | Sem shell no box, sem proxy, listener raso, stream MJPEG 4 fps, imagem não construída pelo app, Codex/OpenCode sem computador, nenhum aceite visual | P0 (núcleo) / P1 (resto) |
| c | Multi-terminal | Parcial | Morre no quit; não há apagar terminal/sessão; limite de 5 panes; sem scrollback persistente, sem título/cwd dinâmico, sem status "aguardando input" | P0 |
| d | GitHub | Ausente (Git local parcial) | Nenhuma chamada ao GitHub; sem PR/checks; worktree só cria, não lista/remove; sem projeto/repo como entidade | P1 |
| e | Biblioteca de agents/skills | Parcial | Não lê `~/.claude/agents` nem pastas de skills; agente salvo vira `--append-system-prompt-file`, não subagente nativo; Codex/OpenCode export-only | P1 |

Mais grave que qualquer lacuna isolada: o modelo do app gira em torno de "sessão → terminais" sem entidade de projeto/repositório (`Domain.swift:29-37`), e quase todo recurso avançado (computador, MCP, hooks, árvore de filhos) só existe no caminho "Biblioteca → revisar plano → lançar Claude". O terminal comum, que é o que o dono abre 90% das vezes, não tem nenhum desses recursos.

---

## (a) Abrir terminal direto no agente escolhido

### Estado atual

- **Modelo**: `TerminalRecord` tem `provider`, `cwd`, `arguments`, `agentDefinitionID`, `nativeConversation` (`Domain.swift:14-27`). Provedores fixos: `claude`, `codex`, `opencode`, `shell` (`Domain.swift:3-12`).
- **Diálogo "Novo terminal"** (`WorkspaceView.swift:1525-1577`): só cliente, título e pasta. **Não há campo de argumentos**, embora o modelo tenha `arguments`. O pasta padrão é o `cwd` do último terminal da sessão.
- **Criar ≠ iniciar**: `createTerminal` (`WorkspaceView.swift:~1438`) só grava o registro e o layout. O processo sobe quando o usuário aperta ▶ (`runtimeButton`, `WorkspaceView.swift:815`). Isso contradiz "abrir terminal direto no agente".
- **Resolução do executável**: `CLIExecutableResolver` procura no PATH, `~/.local/bin`, `~/.bun/bin`, nvm, Homebrew; aceita override (`CLIExecutableResolver.swift:31-46`). Sem UI de override.
- **Ambiente do PTY**: allowlist de 11 variáveis + PATH reconstruído (`TerminalRuntimeManager.swift:353-368`). Ficam de fora `SSH_AUTH_SOCK`, `GH_TOKEN`, `ANTHROPIC_*`, `OPENAI_API_KEY`, `NVM_DIR`, `JAVA_HOME`, proxies corporativos etc. Na prática `git push` via SSH e ferramentas que dependem de env do shell de login quebram dentro dos agentes. O shell recebe `-l` (`:227`), mas os CLIs de agente não passam por shell de login.
- **Login**: Configurações → Clientes locais consulta `claude auth status --json` e `codex login status` com timeout (`AppSettingsView.swift:75-80`). OpenCode aparece como "Credenciais não verificadas". Funciona, mas só nessa tela; o diálogo de novo terminal não avisa se o CLI está deslogado.
- **Retomada** (`ConversationResumeView.swift`, `CLIConversationCatalog.swift`):
  - Argumentos: Claude `--resume <id>`, Codex `resume <id>`, OpenCode `--session <id>` (`CLIConversationCatalog.swift:137-139`).
  - Descoberta só de sessões **ativas** do Claude, via `claude agents --json` (`:97-100`, `:151-193`). Codex e OpenCode exigem colar o ID. Não há lista de conversas passadas de nenhum cliente, apesar de `~/.claude/projects/<slug>/*.jsonl`, `~/.codex/sessions/AAAA/MM/DD/*.jsonl` e `opencode session list` existirem.
  - Reserva de escritor único por conversa e checagem de que o Claude não está com a conversa aberta em outro lugar (`TerminalRuntimeManager.swift:109-150`). Bom, mas só cobre Claude.
  - `TerminalRecord.nativeConversation` só é preenchido em retomada explícita. Um terminal Claude aberto normalmente não registra o ID da sessão que criou, então "retomar o que eu estava fazendo ontem neste terminal" não existe.
- **Agente salvo**: o caminho Biblioteca → `AgentLaunchView` gera plano revisável e materializa `--append-system-prompt-file`, `--plugin-dir`, `--mcp-config`, `--settings` (`AgentLaunchPlanner.swift:359-364`). Codex/OpenCode/shell são `exportOnly` (`:365-373`): o agente salvo não é ativado neles.
- **Flags comuns** (`--model`, `--permission-mode`, `--dangerously-skip-permissions`, `--add-dir`, `--effort`, `-n/--name`; Codex `-m`, `-s/--sandbox`, `-a`, `-p/--profile`, `-c`; OpenCode `-m`, `--agent`, `--continue`): nenhuma é exposta. Grep por `--model`/`permission-mode` em `Sources/` volta vazio.

### O que funciona ponta a ponta

PTY real com SwiftTerm para os quatro clientes, foco, resize, Ctrl-C (`STATUS.md:7`, evidência `docs/evidence/native-terminal.png`). Retomada por ID colado, com guarda de duplicata (AB-045). Lançamento revisado de agente Claude com contexto protegido.

### Só modelo / stub

`TerminalRecord.arguments` sem UI. `CLIAuthStatus` para OpenCode retorna `unrecognized` sempre (`CLIAuthStatus.swift:22-23`). Override de executável sem UI.

### Lacunas

1. Lançador rápido: escolher cliente + projeto e já estar digitando no agente em 1 passo (hoje: sessão → + → diálogo → criar → ▶).
2. Perfis de lançamento por cliente (modelo, permissão, flags extras, env) com padrão global/projeto e override por terminal.
3. Histórico de conversas por projeto, para os três clientes, com título/última mensagem/data, e "continuar última" (`claude -c`, `codex resume --last`, `opencode -c`).
4. Captura do ID de sessão nativo em todo terminal (hook `SessionStart` do Claude, arquivo de sessão do Codex, `opencode session list`), para que reabrir o app ofereça retomar no mesmo pane.
5. Herança do ambiente do shell de login do usuário (como Terminal.app/iTerm/Ghostty fazem), com lista de exclusão em vez de allowlist.
6. Aviso de login ausente e de versão incompatível no momento do lançamento.
7. Fork de conversa (`claude --fork-session`, `codex fork`, `opencode --fork`).

### Como outros resolvem

- **Orca**: roda mais de 30 CLIs de agente; cada agente é uma aba de terminal no worktree da tarefa, com estado ao vivo (trabalhando, esperando input, concluído, concluído-não-lido) e, para Claude/Codex, o nome da conversa no título da aba. Hibernação experimental relança agentes ociosos com `claude --resume <id>`/`codex resume <id>` reaproveitando comando, args e env originais.
- **Claude Code**: `-r/--resume [id|nome|arquivo.jsonl]` (sem argumento abre seletor); `-c` retoma a mais recente do diretório; `--session-id <uuid>` permite o app escolher o ID antes de lançar (resolve a captura do ID sem hook); `-n/--name`; `--fork-session`. Flags como `--mcp-config`, `--settings`, `--plugin-dir`, `--add-dir` **não** são restauradas no resume e precisam ser repassadas. `--permission-mode default|acceptEdits|plan|auto|dontAsk|bypassPermissions|manual`, `--model` com alias. Transcripts em `~/.claude/projects/<cwd-slug>/<session>.jsonl`, formato interno, retenção de 30 dias (`cleanupPeriodDays`). Hook `SessionStart` recebe `session_id`, `transcript_path`, `cwd`, `source`.
- **Codex**: `codex resume` (picker, `--last`, id/nome), `codex fork`, `codex archive/delete`; sessões em `~/.codex/sessions/AAAA/MM/DD/rollout-<ts>-<uuid>.jsonl` (confirmado localmente); `-C/--cd`, `-m`, `-s read-only|workspace-write|danger-full-access`, `-a`, `-p/--profile`, `-c chave=valor`, `--add-dir`.
- **OpenCode**: `-c/--continue`, `-s/--session`, `--fork`, `-m provider/model`, `--agent`, `--prompt`, `--auto`; `opencode session list`; sessões em SQLite (`~/.local/share/opencode/opencode.db`); `opencode serve`/`attach` expõe servidor HTTP com eventos.
- **Terminais nativos (iTerm2, Ghostty, Warp)**: herdam o ambiente de um shell de login e permitem perfis de lançamento com comando inicial.

### Proposta de comportamento ideal

**UX**

- `⌘T` abre um seletor compacto (estilo paleta): cliente (ícone), projeto/worktree, perfil (ex.: "Claude · Opus · plan mode", "Codex · full-auto"), e um campo opcional "primeiro prompt". Enter abre o pane já rodando.
- `⌘⇧T` = "Continuar conversa": lista unificada das conversas recentes do projeto atual nos três clientes, com ícone do cliente, título/primeira mensagem, data, ramo Git e indicação "aberta em outro lugar".
- Menu de contexto do pane: "Reiniciar com…" (troca modelo/permissão e relança com `--resume` do mesmo ID), "Fork desta conversa".
- Status do login visível no seletor (ícone de alerta + "rodar `claude /login`" que abre um pane já com o comando).

**Técnico**

- `LaunchProfile { provider, model?, permissionMode?, extraArgs[], env{}, addDirs[] }` com resolução global → projeto → terminal, convertido por um adapter por cliente (`ClaudeAdapter.args(profile)`, `CodexAdapter.args(profile)`…). Validar flags contra `--help`/versão do CLI em cache.
- `ConversationIndex` por cliente: leitura somente de metadados (nome do arquivo, mtime, cwd, primeira linha de usuário truncada) de `~/.claude/projects`, `~/.codex/sessions` e `opencode session list --format json` (validar formato). Nunca copiar transcript para o banco do app.
- Captura do ID: no Claude, gerar o UUID no app e lançar com `--session-id <uuid>` (sem depender de hook); no Codex, `notify` (`thread-id`) ou o rollout mais novo cujo `cwd` bate; no OpenCode, `session list`/servidor. Preencher `nativeConversation` automaticamente.
- Ao retomar, repassar as flags de lançamento originais (o Claude não as restaura sozinho).
- Ambiente: capturar uma vez `zsh -lic env -0` no startup (com timeout) e usar como base; remover só variáveis do próprio app.

### Dependências e riscos

- Formatos de sessão do Codex/OpenCode mudam entre versões; manter parser tolerante e versionado.
- Herdar env amplia o que o agente vê (tokens no env). É o comportamento esperado de um terminal; documentar e permitir exclusões.
- Flags com `--dangerously-skip-permissions` precisam de confirmação explícita e indicador visual permanente no pane.

### Prioridade

**P0**: lançador de 1 passo com início automático, perfis com modelo/permissão/flags, herança de env, "continuar última". **P1**: histórico unificado dos três clientes e captura automática do ID. **P2**: fork, validação de flags por versão.

---

## (b) Subagentes com Docker (sem e com GUI) e capacidades dos subagentes

### Estado atual

**Runtime do box** (`runtime/boxes/`): imagem Playwright Python 1.63 + Xvfb + Openbox + xdotool (`Dockerfile`). Servidor HTTP próprio em `:8765` com token (`server.py:73-150`). Modos `http` (sem browser), `headless` (Chromium completo headless, perfil persistente) e `desktop` (Xvfb + Chromium independente, controlado via CDP interno). Volume `/data` com `profile/` e `workspace/`. Hardening forte: read-only, cap-drop ALL, porta só em loopback (`runtime/boxes/README.md`).

**Serviço Docker** (`BrowserComputerService.swift`): cria volume e container rotulados por computador/terminal/agent-run (`:353-364`, `:690-702`), start/stop, recuperação de metadados, atualização de imagem de box parada com journal (`:412-518`). Conexão por contexto Docker escolhido (`DockerConnection.swift`). Token por box no Keychain.

**Ferramentas MCP** expostas ao Claude (`ComputerMCPProtocol.swift:90-105`, helper `Sources/AgentBoxMCP/main.swift`): `computer_status`, `computer_acquire`, `computer_screenshot`, `computer_page`, `computer_http_request` (GET/HEAD públicos, 1 MiB, sem redirect), `computer_mode`, `computer_navigate`, `computer_input` (X11, 1280×800), `computer_request_help`.

**Controle humano** (`ControlBroker.swift`, `ComputerControlBridge.swift`, `RemoteDesktopView.swift`): lease exclusivo com epoch; o viewer só aceita input após ACK de revogação do agente; pedido de ajuda pausa as escritas até "assumir/devolver". Stream é **MJPEG de `/v1/stream`, máximo 4 fps**, da tela Xvfb inteira (`server.py:96`, `RemoteDesktopView.swift:190`); se passar 4 s sem frame, desconecta (`:199-204`).

**Pedidos humanos** (`HumanRequestCenter.swift:51-84`): notificação macOS com som, deduplicada. Só para `computer_request_help`.

**Subagentes nativos** (`NativeAgentMonitor.swift`, `ClaudeHookInbox.swift`, `runtime/hooks/claude_event.py`): hooks Claude `SessionStart`, `SubagentStart`, `SubagentStop`, e `PreToolUse` para assinar a proveniência de chamadas MCP (`claude_event.py:14`, `:125`). Cada filho nativo pode adquirir a própria box; nunca usa a do pai (AB-043/044). Árvore terminal → filhos na sidebar (`WorkspaceView.swift:556-628`).

**Captura/listener** (`CaptureStore.swift`, `DatasetStore.swift`, `runtime/boxes/capture.py`): opt-in por box com allowlist de hosts; registra só metadados de requests do browser e campos JSON escalares escolhidos da ferramenta HTTP; ring em memória < 900 KB; exportação CSV/JSON com manifesto. Não cobre corpos do browser, websockets, curl, Python, sockets (`runtime/boxes/README.md`, seção capture).

**Restrições estruturais**:

- Computador + MCP **só para Claude e só em lançamento revisado da Biblioteca** (`AgentLaunchPlanner.swift:305-311`; `TerminalRuntimeManager.swift:100-104` recusa iniciar terminal com agente fora desse caminho; `AgentLaunchView.swift:297-309`). Terminal Claude comum, Codex e OpenCode não recebem computador.
- Filho só ganha box se o pai foi lançado com o agente "Web scraping" e a skill `webscraping-expert` (`TerminalRuntimeManager.swift:185-193`).
- Um box por terminal/filho; não há visão global de "todos os computadores".
- Sem shell no box: não existe `exec`; o agente não roda `curl`, `python`, `curl_cffi`, scripts próprios dentro do container. O README do runtime proíbe dar shell no mesmo container enquanto o plano de controle não for isolado.
- Sem proxy (grep por `zyte`/`proxy` em `Sources` e `runtime` não acha implementação).
- Docker: o app não instala nem inicia o daemon, nem constrói a imagem.

### Comparação com o CLI anterior (`~/orca/projects/agentbox`)

O skill `agentbox` que o dono usou de verdade (dezenas de runs em `runs/`) oferecia por box: terminal (`agentbox exec <box> -- …`), `curl`/`python3` com `requests`, `curl_cffi`, `openpyxl`; browser persistente com `open/text/html/click/fill/press/eval/cookies/shot`; `reqlog` com **todas** as requisições do browser, curl e Python (método, URL, corpo, status, trecho de resposta); `proxy on/off` via Zyte com orçamento rígido (US$ 1, HTTP 402 ao estourar); `render` pela API Zyte para desafios anti-bot; `collect` do transcript do subagente e `timeline --md` para conferir cada afirmação do `result.json` contra IDs de request; `agentbox note` (PLAN/DOING/FOUND/BLOCKED).

O app Swift ganhou isolamento, controle humano e desktop, mas **regrediu** em capacidade de trabalho: sem shell, sem `curl_cffi`, sem proxy, sem render remoto, listener com cobertura bem menor, sem timeline por evidência e sem diário do agente. Para o caso de uso declarado (scraping/pesquisa), o CLI antigo é mais útil hoje.

### O que funciona ponta a ponta

- Criar box, promover HTTP → desktop, ver stream ao vivo, assumir e devolver controle pela UI (`STATUS.md:27`).
- Fluxo não interativo: Claude real → filho nativo → MCP → box própria → pedido de ajuda → takeover pelas APIs → retomada → parada automática (AB-045, `docs/evidence/ab045-native-child-flow.json`).
- Perfil persistente sobrevive a recriação do container; atualização de imagem com rollback (AB-042).
- 172 testes Swift, 30 Python (`STATUS.md:118`).

### Só modelo / parcial sem prova

- Fluxo interativo pela TUI → sidebar → box ao vivo: nunca conferido visualmente (`STATUS.md:39-41`).
- Fila justa/idempotência de criação (AB-018 "Planejada"), quotas, sono/wake.
- Política de URLs; captura restaurada após relançar; MCP de acesso às capturas (AB-046 pendentes).
- Backup/restore de perfil (AC35).
- `DockerComputerService` antigo (`sleep infinity`, `DockerComputerService.swift:115`) convive com o `BrowserComputerService`; é resto do lote 1.

### Lacunas (o que um bom app de subagentes com computador precisa)

1. **Pré-requisitos resolvidos pelo app**: detectar Docker/Colima/OrbStack, oferecer iniciar o runtime, construir ou baixar a imagem versionada com progresso.
2. **Shell no box** para o agente (`exec argv` com cwd/timeout/cancel, e um pane de terminal humano dentro do box). Requer separar plano de controle (browser/lease) do espaço do agente: dois processos/usuários ou dois containers no mesmo pod de rede.
3. **Proxy** por box (Zyte ou outro) com orçamento, troca a quente e log de gasto.
4. **Listener real**: proxy MITM dentro do box (mitmproxy com CA do box) cobrindo browser, curl, Python, websockets, com corpos sob limite, filtros e redação. O desenho atual por eventos do Playwright não chega lá.
5. **Visão ao vivo melhor**: MJPEG a 4 fps serve para conferência, não para operar login/CAPTCHA. Precisa de 15–30 fps e baixa latência; teclado com layouts e clipboard.
6. **Painel de computadores** global: todos os boxes, dono (terminal/filho), modo, uso de CPU/RAM, último screenshot, estado do lease, gasto do proxy, botão "ver ao vivo" e "assumir".
7. **Grade de previews** dos boxes ativos da sessão (miniaturas atualizando) ao lado dos terminais.
8. **Computador para qualquer terminal e qualquer cliente**: MCP stdio funciona em Codex (`~/.codex/config.toml [mcp_servers]` ou `-c mcp_servers…`) e OpenCode (`opencode.jsonc "mcp"`); o gate atual de "só Claude revisado" é auto-imposto.
9. **Filhos de Codex/OpenCode**: hoje só Claude tem hooks de subagente. Codex tem `notify` e agentes em `~/.codex/agents/*.toml`; OpenCode tem servidor HTTP/eventos (`opencode serve`, `attach`). Precisa de adapter por cliente, com capability "sem identidade de filho" mostrada quando não houver.
10. **Ferramentas de navegação ricas**: `click/fill/press/eval/cookies/download/upload` por seletor, não só coordenadas X11. O CLI antigo tinha.
11. **Diário e evidências**: nota do agente (PLAN/DOING/FOUND/BLOCKED), timeline por box com request IDs, export de evidências, importação do transcript do filho.
12. **Reservas antecipadas**: o pai reservar N boxes para filhos ainda não criados (a spec prevê; não implementado).
13. **Recursos/limites visíveis** e encerramento automático por ociosidade com aviso.

### Como outros resolvem

- **Streaming de desktop em container**: noVNC + websockify sobre Xvfb + x11vnc/TigerVNC é simples e maduro, sem NAT/TURN, com encoding por CPU e mais lag em movimento; é o stack da referência de computer-use da Anthropic (`claude-quickstarts/computer-use-demo`, portas 5900/6080), onde takeover é só conectar no mesmo VNC. KasmVNC traz servidor web e cliente embutidos, sem websockify. Selkies (GStreamer, H.264 + Opus, WebSocket ou WebRTC) e neko (WebRTC multiusuário com "controle" passável entre usuários, encaixe natural para takeover) chegam a 10–50 ms, mas exigem encoder e, fora de loopback, TURN. Para app nativo em loopback, `WKWebView` com noVNC ou cliente RFB nativo resolve sem reinventar codecs.
- **Browser headless "ao vivo"**: CDP `Page.startScreencast` emite `Page.screencastFrame` (JPEG + metadados, exige ack por frame) e o input volta por `Input.dispatchMouseEvent/KeyEvent`; funciona em headless sem Xvfb, mas cobre só a viewport. Browserbase Live View devolve `debuggerFullscreenUrl` para iframe interativo (com `pointer-events:none` vira só leitura).
- **Takeover**: o padrão comum é pausar o agente com sinal explícito antes de liberar input humano, como o app já faz com lease/epoch/ACK. Essa parte do app está acima da média; o gargalo é o transporte de vídeo.
- **Orca**: Chromium embutido por worktree, controlado pelo agente via CLI (`orca snapshot/click/fill`), perfis de browser e importação de cookies do Chrome; Computer Use para apps desktop. Não usa Docker; isolamento não é o foco dele, e aqui é.
- **Listener**: mitmproxy em modo regular/transparent dentro do container, CA instalada no trust store do box e no NSS do Chromium; HAR por box.
- **Subagentes Claude Code**: definidos em `~/.claude/agents/*.md` ou `--agents '{json}'`; hooks `SubagentStart`/`SubagentStop`, `PreToolUse` e `Notification` dão identidade e estado; `--mcp-config` por lançamento.

### Proposta de comportamento ideal

**UX**

- Cada terminal tem um botão "Computador" que mostra: nenhum / HTTP / headless / desktop, com miniatura viva. Um clique em "Ver" abre o viewer em pane lateral ou janela separada; "Assumir" passa o controle após ACK e mostra faixa colorida "Você está no controle — Devolver (⌘⇧R)".
- Subagentes aparecem como filhos do terminal na sidebar, com ícone do box, estado (trabalhando/esperando você/terminado), gasto do proxy e acesso rápido ao viewer.
- Pedido de ajuda: notificação macOS + badge no Dock + item destacado na sidebar; clicar leva ao viewer certo já com "Assumir".
- Painel "Computadores" (⌘⇧C): tabela de todos os boxes com dono, modo, recursos, último uso, ações (parar, apagar, abrir shell, ver listener, exportar evidências).
- Aba "Rede" por box: listener com filtros (XHR, erros, host, fonte), detalhe da request, "copiar como curl".

**Técnico**

- Box = dois containers na mesma rede (ou um container com dois usuários e plano de controle fora do alcance do usuário do agente): `control` (browser, lease, stream, listener) e `work` (shell do agente, ferramentas, `curl_cffi`), com proxy MITM obrigatório para egress do `work` e do browser.
- Streaming: x11vnc/TigerVNC + websockify (noVNC) no `control`, publicado só em loopback com token; no app, `WKWebView` com noVNC ou cliente RFB nativo. Headless usa CDP screencast. Manter MJPEG como fallback de miniatura.
- MCP do computador servido por um único broker local do app para qualquer cliente (Claude, Codex, OpenCode), com identidade do chamador vinda do adapter do cliente; quando o cliente não informa identidade de filho, a capability "box por filho" fica indisponível com motivo.
- Ferramentas MCP adicionais: `computer_exec`, `browser_click/fill/press/eval/cookies`, `net_log_query`, `proxy_set`, `note`.
- Gestão de runtime: detector Docker Desktop/Colima/OrbStack; build da imagem a partir de `runtime/boxes` embutido no bundle, ou pull de registry com digest fixo.

### Dependências e riscos

- Shell + browser no mesmo container quebram o modelo de lease (o próprio README admite). A separação control/work é pré-requisito do shell.
- MITM exige CA confiável no box; sites com pinning falham; cuidado para não registrar segredos (redação antes de persistir).
- Proxy pago precisa de orçamento rígido no broker, não no prompt.
- WebRTC/noVNC aumentam superfície; publicar só em `127.0.0.1` com token de curta duração.
- Colima/Docker Desktop consomem RAM; parar boxes ociosos.
- O dono pode estar melhor servido, no curto prazo, reaproveitando o runtime do CLI antigo (shell, reqlog, proxy, render) dentro da nova UI do que portando o runtime Swift atual.

### Prioridade

**P0**: preparar Docker/imagem pelo app; computador disponível em qualquer terminal Claude (não só no plano revisado); viewer com fps decente e takeover confiável; shell no box com separação control/work; listener que cubra curl/Python/browser. **P1**: proxy com orçamento, painel global, miniaturas, MCP para Codex/OpenCode, ferramentas de browser por seletor, timeline/evidências. **P2**: reservas antecipadas, filhos de Codex/OpenCode, WebRTC.

---

## (c) Multi-terminal: tabs, splits, foco, persistência, sobrevivência a quit

### Estado atual

- **Layout**: árvore binária de splits por sessão (`WorkspaceStore.swift:7-81`), frações 0,2–0,8, **máximo 5 panes visíveis** (`:112`; também `WorkspaceView.swift:1199`, `:1417`, `:1445`). Foco persistido (`WorkspaceLayout.focusedTerminalID`). Snapshot JSON em `~/Library/Application Support/AgentBox/workspace.json` (`:180-201`), salvo a cada mudança (`WorkspaceView.swift:193-197`).
- **Tabs**: a barra lista **todos** os terminais da sessão (`WorkspaceView.swift:706-733`). Clicar troca o pane focado por aquele terminal (`WorkspaceLayout.show`, `WorkspaceStore.swift:101-109`). Não há tab como grupo de panes; tab = terminal.
- **Atalhos**: `⌘T` novo terminal, `⌘D`/`⌘⇧D` split, `⌘B` sidebar, `⌘K` busca, `⌘N` sessão, `⌘⌥[`/`⌘⌥]` largura da sidebar (`WorkspaceView.swift:739-802`). Sem navegação entre panes por teclado (`⌘⌥←→`), sem `⌘1…9`, sem maximizar pane, sem fechar terminal por atalho.
- **Fechar**: "Fechar pane" só remove do layout (`WorkspaceStore.swift:119-122`); o terminal continua na sessão. **Não existe apagar terminal nem apagar sessão** em nenhum lugar do código (grep por `terminals.remove`/`sessions.remove` vazio). A lista só cresce.
- **Runtime**: `TerminalRuntimeManager` mantém PTY e emulador por ID durante a vida do processo do app (`TerminalRuntimeManager.swift:15-18`). Trocar tab/pane não reinicia o processo.
- **Quit**: alerta "Sair encerra os processos deste app… os processos não continuam em segundo plano" e mata tudo com SIGTERM → 0,5 s → SIGKILL (`AgentBoxApp.swift:24-31`, `TerminalRuntimeManager.swift:262-282`). Ao relançar, os terminais aparecem parados e precisam de ▶; o conteúdo da tela se perde. Crash do app também mata todos os agentes (são filhos do processo).
- **Renderer**: scrollback 5.000 linhas, fonte monoespaçada do sistema 12 pt fixa, cores fixas (`TerminalRuntimeManager.swift:311-316`). Título dinâmico (OSC 0/2) e cwd (OSC 7) são ignorados (`:36-38`).
- **Estado do agente**: só `idle/starting/running/exited/failed` do processo (`:7-13`). Não há "trabalhando / esperando sua resposta / pedindo permissão / terminou".
- **Notificações**: só pedidos de computador (`HumanRequestCenter`). Agente que terminou ou espera aprovação não notifica.

### O que funciona ponta a ponta

Vários PTYs reais com PIDs/TTYs distintos, splits horizontais e verticais, redimensionar divisores, foco nativo, layout restaurado após relançar (`STATUS.md:7`, `docs/evidence/terminal-split-2026-10-16.png`). Encerrar com SIGTERM e forçar com SIGKILL por grupo de processos.

### Lacunas

1. Sobrevivência a quit/crash/atualização do app (daemon de PTY separado). É o requisito AC12/AB-028 e está "Planejada".
2. Restaurar o conteúdo visível (scrollback serializado) e reconectar a conversa nativa (`--resume`) quando o processo realmente morreu.
3. Apagar/arquivar terminal e sessão, com confirmação se houver processo.
4. Tabs como grupos de layout (como Ghostty/iTerm/Orca), não "um terminal por tab".
5. Limite de panes configurável; maximizar/zoom do pane (`⌘⇧↩`); navegação por teclado; arrastar pane para reorganizar.
6. Estado semântico do agente por pane e na sidebar (spinner trabalhando, ponto laranja "esperando você", check "concluído"), com notificação e som opcionais.
7. Título e cwd dinâmicos; busca no scrollback (`⌘F`); copiar/colar com bracketed paste confirmado; links clicáveis; fonte e tema configuráveis.
8. Desempenho: SwiftTerm em AppKit é aceitável, mas sem GPU; para muitas TUIs pesadas ao mesmo tempo, avaliar libghostty (renderer Metal) ou ao menos medir.

### Como outros resolvem

- **Orca** (referência mais próxima): daemon em background dono dos PTYs (no macOS via launchd, `src/main/daemon/*`). Cmd-Q, relaunch do auto-updater e crash do app não matam os agentes; ao reabrir faz "warm-reattach" com scrollback que inclui o output produzido com o app fechado. Reboot mata os processos; voltam layout, abas e último scrollback. Splits ilimitados (`⌘\`, `⌘⇧\`), renderização WebGL. Notifica quando o agente termina (working → idle), precisa de atenção ou erra, com inbox de não lidos. Estado vem de "agent status hooks" gerenciados pelo próprio Orca, sem tocar em `CLAUDE.md`/`AGENTS.md`.
- **VS Code**: `ptyHost` separado; no reload da janela reconecta ao mesmo processo; no restart completo restaura o output e **relança** o processo (o original morre).
- **iTerm2**: jobs em servidores de longa duração fora do app, sobrevivem a crash/upgrade; Cmd-Q os mata por padrão.
- **tmux/zellij**: servidor sobrevive ao app; tmux `-CC` (control mode, usado pelo iTerm2) dá integração nativa. Custo: camada extra de escape/redraw e conflito de atalhos.
- **Ghostty/Warp**: restauram layout/cwd, não processos.
- **Claude Code**: hook `Notification` com `notification_type` `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`, e `Stop`/`StopFailure`, dão o estado semântico sem parsear a tela. O próprio Claude tem `--bg` e `claude agents/attach/daemon` (supervisor de sessões em background), útil para conferir mas não substitui um daemon do app para os três clientes.
- **Codex**: `notify` em `config.toml` recebe JSON com `type=agent-turn-complete`, `thread-id`, `cwd`, `last-assistant-message`. Não há evento de "esperando aprovação" equivalente; seria estimado.

### Proposta de comportamento ideal

**UX**

- Fechar a janela ou sair do app não mata agentes por padrão. Ao sair: "3 agentes continuam rodando em segundo plano. [Continuar em segundo plano] [Encerrar todos]". Ícone na barra de menus mostra quantos estão rodando/esperando.
- Ao abrir: panes reaparecem com o buffer de antes e o processo vivo. Se o processo morreu (reboot), o pane mostra o último buffer esmaecido e o botão "Retomar conversa" (usa o ID nativo capturado).
- Tabs por sessão contendo layouts; `⌘1…9` troca tab; `⌘⌥←↑→↓` move foco; `⌘⇧↩` zoom; `⌘W` fecha pane com confirmação se rodando.
- Sidebar: cada terminal com ícone do cliente, título dinâmico, branch, e badge de estado (trabalhando/esperando/erro/concluído). Ordenar "esperando você" no topo.
- Apagar terminal/sessão com desfazer.

**Técnico**

- Daemon `agentbox-ptyd` (LaunchAgent opt-in ou helper lançado pelo app e desacoplado com `setsid`) que dona os PTYs e expõe socket Unix com protocolo de attach/detach, resize, input, replay de buffer e eventos de saída. O app vira cliente. Alternativa mais curta: tmux com socket próprio (`tmux -L agentbox`) e `control mode` (`-CC`) — robusto e testado, mas exige tmux instalado e lida pior com algumas TUIs.
- Buffer: ring por terminal no daemon (ex.: 10–50 MB) com serialização do estado do emulador ou reprocessamento do stream bruto.
- Estado do agente: hooks `Notification`/`Stop`/`SessionStart` do Claude e `notify` do Codex escrevendo no inbox do app; OpenCode por eventos do servidor. Fallback por heurística de inatividade de saída marcado como "estimado".
- Persistência em SQLite (sessões, terminais, conversas, layouts), não JSON único reescrito a cada mudança.

### Dependências e riscos

- Daemon de PTY é a peça mais difícil da reconstrução; precisa de versão de protocolo e migração quando o app atualizar com o daemon antigo vivo.
- Sandbox/assinatura: daemon fora do app bundle precisa de assinatura e de lidar com permissões de pasta (bookmarks hoje vivem no app, `WorkspaceDirectoryAccess.swift`).
- Agentes rodando sem janela consomem tokens/dinheiro; o indicador na barra de menus é obrigatório.

### Prioridade

**P0**: daemon de PTY com sobrevivência a quit/crash, apagar terminal/sessão, estado "esperando você" com notificação, navegação por teclado entre panes. **P1**: restauração de buffer, tabs como grupos, zoom, limite configurável, título/cwd dinâmicos, busca no scrollback. **P2**: renderer GPU, temas.

---

## (d) Conexão direta com GitHub

### Estado atual

- **Git local** (`GitWorkspaceInspector.swift:36-63`): `rev-parse`, `symbolic-ref`, `status --porcelain`, `remote`, `remote get-url`, com timeout de 5 s. Remote normalizado sem credenciais; URL web só para `github.com` (`:79-103`).
- **UI**: botão de branch no toolbar e popover de detalhes (`WorkspaceView.swift:836-890`); resumo "Várias branches" por sessão (`:1078-1092`); refresh ao ativar o app (`:189-191`).
- **Worktree** (`GitWorktreeManager.swift:31-55`): só `worktree add -b <nova-branch>` a partir de uma ref, com validação e rollback. A UI cria e abre um terminal do mesmo cliente no novo checkout (`WorkspaceView.swift:1094-1110`). Não lista, não remove, não faz prune, não mostra a qual worktree cada terminal pertence além do branch.
- **GitHub**: **nada**. Nenhuma chamada à API, ao `gh`, nenhum estado de PR, checks, reviews, issues. A spec limita a fase inicial a read-only (`docs/spec/index.html`, seção "Git e GitHub"; AC17).
- **Projeto/repositório não é entidade**: sessões não têm repo; o "projeto" é derivado do `cwd` de cada terminal (`computerPolicyContext`, `WorkspaceView.swift:1071-1076`).
- **Ambiente local**: `gh` está logado com escopos `repo` e `workflow`, ou seja, o caminho mais curto já está disponível na máquina.

### Lacunas

1. Projeto como primeira classe: adicionar repositório (pasta local ou clone de `owner/repo`), com lista de worktrees e terminais pendurados.
2. Worktree por tarefa: criar a partir de issue/branch/PR, nomear, listar, apagar (com checagem de dirty e de branch não publicada), abrir terminal de agente direto nele.
3. Status na sidebar por worktree: ahead/behind, dirty, PR vinculado (número, estado draft/open/merged), checks (passando/falhando/pendentes), review requerido, conflitos.
4. Ações: push, abrir PR (título/corpo gerados pelo agente ou template), abrir no navegador, checkout de PR em worktree novo (`gh pr checkout`), comentar, merge (separado e confirmado).
5. Diff viewer por worktree (o que o agente mudou), com stage/commit opcional.
6. Auth: reaproveitar `gh` quando existir; fluxo próprio quando não.

### Como outros resolvem

- **Orca**: cada tarefa é um `git worktree` real; o branch sai do nome do workspace ou de um PR/issue vinculado; "branch from" aceita ref, branch local/remota ou SHA. Arquivos ignorados entram por `.worktreeinclude`, `worktree.sharedDirectories` (symlink de `node_modules`) ou clone APFS. Archive, sleep, delete em lote com revisão de branches e checkpoints. Mesma tarefa em N agentes, um por worktree, para comparar. **Sem login próprio**: herda o `gh` (tokens `GH_TOKEN`/`GITHUB_TOKEN` têm precedência); em 403 de rate limit mantém o último status e pausa. Sidebar mostra PR open/merged/closed e chip vermelho quando Actions falham, com logs inline; aba do PR com checks, reviews e comentários; "Fix broken checks" manda as falhas ao agente; criar PR (base, título, draft), PRs empilhados, auto-merge.
- **gh CLI**: `gh auth token` devolve o token do keyring; `gh pr view --json number,state,isDraft,statusCheckRollup,reviewDecision,mergeable`, `gh pr checks`, `gh pr checkout`, `gh pr create`.
- **API**: GraphQL `pullRequest { commits(last:1){ nodes{ commit{ statusCheckRollup{ state contexts(first:100){...} } } } } reviewDecision mergeable mergeStateStatus }` resolve tudo em uma consulta. REST 5.000 req/h por usuário, GraphQL 5.000 pontos/h; ETag/`If-None-Match` (304 não conta). A cota é compartilhada com o `gh` e com os agentes do mesmo usuário.
- **Auth em app desktop**: OAuth device flow (código + `github.com/login/device`, sem client secret). GitHub App é o recomendado pelo GitHub (permissões por repo, token de usuário de 8 h com refresh); OAuth App usa scope `repo` amplo e token sem expiração. Para app pessoal, `gh` primeiro e device flow como fallback basta.
- **Claude Code**: `--from-pr` retoma sessão ligada a um PR; `-w/--worktree` cria worktree em `<repo>/.claude/worktrees/<nome>`. **OpenCode**: `opencode pr <n>` faz checkout do PR e abre o agente.

### Proposta de comportamento ideal

**UX**

- Sidebar em três níveis: Projeto (repo) → Worktree/branch → Terminais/agentes. Cada worktree mostra: branch, `↑2 ↓0`, ponto de dirty, chip do PR `#123` com cor do estado, ícone de checks (✓/✗/●) e de review.
- Clique no chip abre popover com checks e links; "Abrir no GitHub"; "Ver diff".
- "Nova tarefa" (⌘⇧N): nome → cria branch e worktree a partir de `main` (ou de uma issue/PR escolhida) → abre o agente escolhido no worktree com o primeiro prompt.
- "Criar PR" no worktree: faz push se preciso e abre `gh pr create` pré-preenchido; confirma antes.
- "Arquivar tarefa": verifica dirty/push, remove worktree, mantém ou apaga branch.

**Técnico**

- `GitHubProvider` com duas implementações: `GHCLIProvider` (usa `gh api graphql` ou `gh auth token` + URLSession) e `DeviceFlowProvider` (token próprio no Keychain). Detectar automaticamente e mostrar qual está ativo.
- Polling: uma consulta GraphQL por repositório a cada 30–60 s quando a janela está ativa, 5 min em segundo plano, com ETag; botão "atualizar agora". Webhooks não fazem sentido para app local.
- Git local via `git` CLI com `--porcelain=v2 --branch` (ahead/behind de graça) e `worktree list --porcelain`. FSEvents no `.git` para refresh barato.
- Ações de escrita (push, PR, merge) sempre explícitas e com confirmação; nada ao abrir sessão (mantém AC17).

### Dependências e riscos

- Depende da entidade Projeto, que mexe no modelo de dados inteiro; decidir isso antes da UI.
- Repositórios privados de organizações podem exigir SSO autorizado no token; mostrar erro claro.
- Apagar worktree com trabalho não publicado é destrutivo; exigir confirmação e checagem.
- SSH para push depende do `SSH_AUTH_SOCK` que hoje não chega ao PTY (ver item a).

### Prioridade

**P1** no conjunto, com uma parte **P0**: projeto/repo como entidade e worktree por tarefa com agente aberto nele (é o centro do modelo Orca que o dono quer). PR/checks na sidebar via `gh`: **P1**. Device flow próprio, diff viewer, merge: **P2**.

---

## (e) Biblioteca de agents e skills

### Estado atual

- **Modelo** (`LibraryModels.swift:3-152`): `SavedAgent` (nome, resumo, instruções, provider, skillIDs, memoryIDs, revisão, arquivado), revisões imutáveis, `AgentMemory` com escopo (agente/projeto/tarefa/preferência/perfil), tipo, validade e revisões; `SkillEntry` com caminho de origem, **conteúdo copiado** e SHA-256.
- **Persistência**: `LibraryRepository` em JSON no Application Support (`LibraryRepository.swift:19-31`).
- **Importação de skill**: um arquivo por vez via `NSOpenPanel` aceitando texto (`LibraryView.swift:167`), lido como dados (`LibraryRepository.swift:57-74`). Frontmatter lido só por `name:`/`description:` em linha simples. Não varre `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, plugins, nem `.claude/skills` do projeto.
- **Agentes**: criados à mão no app. **Não importa** `~/.claude/agents/*.md` (frontmatter `name`, `description`, `tools`, `model`) nem `~/.codex/agents/*.toml`. Único atalho: `createScrapingAgent`, que lê `~/.claude/skills/webscraping-expert/SKILL.md` direto do disco (`LibraryStore.swift:93-124`).
- **Ativação no Claude**: o agente salvo vira **prompt de sistema anexado** (`--append-system-prompt-file`) do terminal principal; skills viram um plugin temporário (`--plugin-dir`) com snapshot e hash, incluindo arquivos de apoio (`AgentLaunchPlanner.swift:316-341`, `:359-364`). Não usa `--agents` nem `--agent`, ou seja, o agente salvo não aparece como subagente nativo que o Claude possa delegar (`Task`/`Agent`).
- **Codex/OpenCode/shell**: `exportOnly` (`AgentLaunchPlanner.swift:365-373`). O Codex tem `~/.codex/agents/*.toml` e skills em `~/.codex/skills`; o OpenCode tem `--agent` e agentes em `opencode.jsonc`/`.opencode/agent/*.md`. Nada disso é usado.
- **Memória**: memórias do app entram no contexto anexado. Não há leitura/edição de `CLAUDE.md`, `AGENTS.md`, memória automática do Claude (`~/.claude/projects/*/memory`), nem de `~/.codex/memories`.
- **Histórico de execuções**: `LibraryMutations.recordRun`/`finishRun` (`LibraryMutations.swift:109-150`) ligam definição a sessão/terminal/computador. Bom para auditoria.
- **Acesso**: Biblioteca é uma sheet modal aberta pelo menu "…" (`WorkspaceView.swift:790`). Não há atalho, nem painel lateral, nem busca global de skills.

### O que funciona ponta a ponta

CRUD de agentes e memórias com revisões; importar um SKILL.md; lançar agente Claude com contexto revisado e plugin de skills; histórico de execuções (`STATUS.md:10-11`, AB-010/011/032).

### Lacunas

1. **Catálogo vivo** das fontes nativas: `~/.claude/agents`, `~/.claude/skills`, `.claude/agents` e `.claude/skills` do projeto, plugins instalados (`~/.claude/plugins/installed_plugins.json`), `~/.agents/skills`, `~/.codex/agents`, `~/.codex/skills`, agentes do OpenCode. Ler por referência (caminho + hash), sem copiar conteúdo para o JSON do app.
2. **Ativação nativa** por cliente:
   - Claude: subagentes via `--agents '{json}'` ou pasta `.claude/agents` gerada por lançamento; agente principal via `--agent <nome>`; skills via `--plugin-dir` (já existe) ou simplesmente deixar as globais ativas.
   - Codex: agentes `.toml` e skills nas pastas que o Codex lê; `-c` para overrides; `AGENTS.md` para instruções de projeto.
   - OpenCode: `--agent`, configuração de agentes no `opencode.jsonc` do projeto.
3. **Acesso rápido**: paleta "Inserir skill/agente" (⌘/ ou ⌘⇧A) que, no pane focado, digita `/skill-name` ou `@agent` no prompt do CLI, ou relança com o agente.
4. **Edição nos formatos nativos**: editar `~/.claude/agents/x.md` direto (com diff e backup), criar agente novo já no formato do cliente, converter Claude ↔ Codex (o dono mantém os dois espelhados à mão hoje: 13 `.md` vs 12 `.toml`).
5. **Memória e instruções**: editor de `CLAUDE.md`/`AGENTS.md` (global e do projeto) e visualizador da memória automática, em vez de um sistema de memória paralelo que só funciona no Claude via append.
6. **Sincronização/atualização**: detectar mudança no arquivo fonte (hash) e oferecer atualizar; hoje o snapshot fica velho silenciosamente até falhar (`AgentLaunchPlanner.swift:327-333`).
7. **Pacotes `.zip`** de skill (há vários em `~/.claude/skills`) e skills com scripts: mostrar arquivos antes de ativar.

### Como outros resolvem

- **Claude Code**: subagentes em Markdown em `~/.claude/agents` e `.claude/agents` (lidos recursivamente); prioridade managed > `--agents` > projeto > usuário > plugin. Frontmatter: `name` e `description` obrigatórios; opcionais `tools`, `disallowedTools`, `model` (inclui `inherit`), `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation: worktree`, `color`, `initialPrompt`. Isso cobre direto o que o app tenta fazer com "agente salvo + skills + MCP de computador": um subagente nativo pode declarar `skills` e `mcpServers` próprios. `--agents '{json}'` define agentes por sessão, `--agent` escolhe o principal. Skills em `~/.claude/skills/<nome>/SKILL.md`, `.claude/skills/`, ou `<plugin>/skills/` (namespaced `/plugin:skill`), carregadas sob demanda. `CLAUDE.md` em níveis e memória automática em `projects/<p>/memory/`.
- **Codex**: skills em `.agents/skills` (do cwd até a raiz do repo) e `~/.agents/skills`; `~/.codex/skills` é o caminho antigo. Invocação por `$skill` ou `/skills`. `AGENTS.md` global e por diretório. MCP em `[mcp_servers.<nome>]` do `config.toml` ou `codex mcp add`. `.codex/config.toml` de projeto só carrega em projeto confiável.
- **OpenCode**: agentes na chave `agent` do `opencode.json` (`mode: primary|subagent|all`, `model`, `prompt`, `permission`) ou em Markdown em `~/.config/opencode/agents/` / `.opencode/agents/`.
- **Orca**: a UI lê skills de Claude, Codex e Agent Skills sem symlink, oferece update automático e registro de MCP em Settings → Integrations; não reescreve `CLAUDE.md`/`AGENTS.md`, só os mostra. Instala as próprias skills com `npx skills add … --global`.
- **Padrão `~/.agents/skills`**: diretório compartilhado entre harnesses (Codex lê nativamente), já usado pelo dono com ~30 skills. É o melhor alvo para "uma skill, todos os clientes".

### Proposta de comportamento ideal

**UX**

- Painel lateral "Biblioteca" (⌘L) com abas Agentes / Skills / Instruções / Memória, filtro por cliente e fonte (global, projeto, plugin, app). Cada item mostra em quais clientes está disponível (ícones) e se está ativo no terminal focado.
- Ações por item: "Abrir terminal com este agente" (escolhe cliente compatível), "Usar no terminal atual" (digita o comando nativo ou relança), "Disponibilizar para Codex" (gera `.toml`), "Editar", "Ver diff da origem".
- Instruções: editor lado a lado de `CLAUDE.md` e `AGENTS.md` do projeto, com aviso quando divergirem.
- Importar: arrastar pasta/zip, ou "Adicionar fonte" (pasta vigiada).

**Técnico**

- `CatalogSource` por origem com watcher FSEvents; índice SQLite só com metadados (nome, descrição, caminho, hash, cliente, escopo). Conteúdo lido sob demanda.
- `ActivationAdapter` por cliente com capacidades declaradas (`supportsSubagents`, `supportsSkills`, `supportsMainAgent`) e verificação pós-lançamento (hook `SessionStart` do Claude, ou leitura do prompt de sistema efetivo quando o cliente expõe).
- Snapshot por execução continua útil para auditoria (já existe), mas como registro de hash, não como cópia obrigatória.
- Conversor Claude `.md` ↔ Codex `.toml` ↔ OpenCode com mapeamento explícito de campos e lista do que se perde.
- No Claude, trocar o "agente salvo como `--append-system-prompt-file`" por definição nativa: `--agents '{json}'` gerado por lançamento (ou `.claude/agents` do projeto) com `skills` e `mcpServers` próprios. Assim o agente de scraping vira um subagente que o Claude delega normalmente, já com a skill e o MCP do computador, sem o caminho especial de hooks que existe hoje para injetar contexto em filhos (`TerminalRuntimeManager.swift:185-193`). Validar na versão instalada antes de adotar.

### Dependências e riscos

- Escrever em `~/.claude` e `~/.codex` altera o comportamento de todos os terminais, inclusive fora do app. Toda escrita precisa de diff, backup e confirmação; preferir escopo de projeto ou de lançamento.
- Skills de terceiros podem conter scripts; ativar não pode executar nada, e a UI precisa mostrar os arquivos.
- O formato de agentes/skills do Codex e do OpenCode muda rápido; manter adapter versionado e testar contra a versão instalada.

### Prioridade

**P1**: catálogo das fontes nativas, ativação nativa no Claude (`--agents`/`--agent`), acesso rápido no terminal, editor de `CLAUDE.md`/`AGENTS.md`. **P2**: conversor Claude↔Codex↔OpenCode, edição nos formatos nativos com diff, memória paralela do app (avaliar se ainda faz sentido).

---

## Lacunas transversais

| Lacuna | Evidência | Efeito | Prioridade |
|---|---|---|---|
| Recursos avançados presos ao fluxo "Biblioteca → plano revisado → Claude" | `TerminalRuntimeManager.swift:100-104`, `AgentLaunchPlanner.swift:305-311`, `:349` | Terminal comum não tem computador, hooks, árvore de filhos nem estado | P0 |
| Env do PTY em allowlist | `TerminalRuntimeManager.swift:353-368` | `ssh`, `gh` via env, chaves de API e toolchains falham dentro dos agentes | P0 |
| Sem apagar terminal/sessão | grep vazio por `terminals.remove`/`sessions.remove` | Lista cresce para sempre | P0 |
| Quit mata tudo | `AgentBoxApp.swift:24-31` | Fechar o app derruba agentes longos | P0 |
| App não prepara Docker nem imagem | `BrowserComputerService.swift:259`; nenhum `docker build` | Computadores inutilizáveis sem passos manuais | P0 |
| Nenhum estado "esperando você" | hooks só `SessionStart/SubagentStart/SubagentStop/PreToolUse` (`claude_event.py:14`) | Usuário precisa varrer panes para ver quem parou | P0 |
| Python do host exigido pelos hooks | `runtime/hooks/claude_event.py` | Dependência frágil do `python3` do sistema | P1 |
| Aceite visual nunca feito | `acceptance.json`: 68/68 `planned`; `STATUS.md:39-47` | Não há prova de que a UI funciona para um humano | P0 (processo) |
| Persistência em JSON reescrito a cada mudança | `WorkspaceView.swift:193-197`, `LibraryRepository.swift:26-31` | Risco de corrupção e de perda em concorrência; difícil migrar | P1 |

## Backlog sugerido para a spec da reconstrução

**P0 (o app só é bom com isso)**

1. Entidade Projeto/Repo → Worktree → Terminal, com sidebar em três níveis.
2. Lançador de 1 passo (cliente + projeto/worktree + perfil + prompt opcional), início imediato.
3. Perfis de lançamento com modelo, modo de permissão e flags por cliente.
4. Ambiente herdado do shell de login.
5. Daemon de PTY: sobreviver a quit/crash, reanexar com buffer.
6. Estado semântico por agente (trabalhando/esperando/concluído) via hooks, com notificação e ordenação na sidebar.
7. Apagar/arquivar terminal, sessão e worktree.
8. Computador disponível a qualquer terminal Claude; Docker/imagem preparados pelo app.
9. Viewer ao vivo com fps decente (noVNC/RFB ou CDP screencast) e takeover já existente.
10. Shell no box com separação control/work e listener MITM cobrindo browser/curl/Python.

**P1**

11. "Continuar conversa" unificado (Claude/Codex/OpenCode) e captura automática do ID.
12. PR/checks/review na sidebar via `gh`; criar PR; checkout de PR em worktree.
13. Catálogo nativo de agents/skills/plugins e ativação nativa no Claude (`--agents`, `--agent`).
14. Paleta de skills/agentes no terminal focado.
15. Editor de `CLAUDE.md`/`AGENTS.md`.
16. Proxy com orçamento por box; painel global de computadores; miniaturas.
17. MCP de computador para Codex e OpenCode.
18. Ferramentas de browser por seletor; diário do agente e timeline com evidências.
19. Tabs como grupos, zoom de pane, busca no scrollback, título/cwd dinâmicos.
20. SQLite para estado do app.

**P2**

21. Device flow próprio do GitHub, diff viewer, merge.
22. Conversor de agentes entre clientes; edição nativa com diff.
23. Filhos de Codex/OpenCode com identidade; reservas antecipadas de boxes.
24. WebRTC para desktop; renderer GPU.

## Referências externas

Consultadas em 16/10/2026. Itens marcados como não verificados vieram de conhecimento geral e devem ser conferidos antes de entrar na spec.

- Orca: https://github.com/stablyai/orca · docs https://onorca.dev/docs · terminal https://onorca.dev/docs/terminal · hooks e memória https://www.onorca.dev/docs/agents/hooks-memory · worktrees https://onorca.dev/docs/model/worktrees · restauração de sessão https://onorca.dev/docs/model/session-restore · hibernação https://onorca.dev/docs/agents/hibernation · GitHub https://onorca.dev/docs/review/github e https://onorca.dev/docs/github-errors · notificações https://onorca.dev/docs/notifications · navegador https://onorca.dev/docs/browser/overview · skills https://onorca.dev/docs/cli/skills
- Claude Code: CLI https://code.claude.com/docs/en/cli-reference · sessões https://code.claude.com/docs/en/sessions · subagentes https://code.claude.com/docs/en/sub-agents · skills https://code.claude.com/docs/en/skills · hooks https://code.claude.com/docs/en/hooks · memória https://code.claude.com/docs/en/memory
- Codex CLI: comandos https://learn.chatgpt.com/docs/developer-commands?surface=cli · config https://learn.chatgpt.com/docs/config-file/config-advanced · skills https://learn.chatgpt.com/docs/build-skills.md · `AGENTS.override.md` (não verificado)
- OpenCode: agentes https://opencode.ai/docs/agents/ · flags conferidas com `opencode --help` 1.18.34 local
- GitHub: `gh auth token` https://cli.github.com/manual/gh_auth_token · device flow https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow · GitHub App vs OAuth App https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app · `StatusCheckRollup` https://docs.github.com/en/graphql/reference/objects#statuscheckrollup · rate limits https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api (limites secundários exatos não verificados)
- Streaming/takeover: computer-use demo https://github.com/anthropics/claude-quickstarts/tree/main/computer-use-demo · KasmVNC https://github.com/kasmtech/KasmVNC (detalhes de codec não verificados) · Selkies https://github.com/selkies-project/selkies · neko https://github.com/m1k1o/neko (latência: issue 339) · Browserbase Live View https://docs.browserbase.com/features/session-live-view · CDP screencast https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-startScreencast · Steel/Browser Use live view (não verificado)
- Persistência de terminal: VS Code https://code.visualstudio.com/docs/terminal/advanced · iTerm2 https://iterm2.com/restoration.html · Ghostty/Warp (não verificado)
