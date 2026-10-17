# 08 · Arquitetura, dados, segurança e qualidade

> **Revisado após R1–R3 em 2026-10-16.** Patches de `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md` aplicados; mudanças e itens não aplicados em `review/E-06-08-changelog.md`. A **§0 Identificadores canônicos** é a tabela única que todos os capítulos citam para nomes que viram código. A **§11 Spikes e verificações** consolida todos os "(verificar)" e os spikes S-01…S-08.

Capítulo técnico da spec de rebuild do Agent Box. Data: 2026-10-16. Base: `00-decisions.md` (prevalece; P1–P16, T1–T14), revisões `review/R1..R3`, auditorias `02-core-audit.md` e `09-review-architecture.md` (centrais), `05`, `07` (achados de segurança do terminal), `08`, e o código no commit `c4418cc` (`Package.swift`, `Sources/`, `Tests/`, `scripts/`, `runtime/`).

Este capítulo define **como** o app é construído. O que o usuário vê e faz fica nos capítulos de produto; quando há sobreposição (por exemplo, o comportamento do ⌘Q), este capítulo fixa só a mecânica.

## Convenções

- Requisito: `AR-NNN [Prioridade · Versão]`. Prioridade: **P0** bloqueia a v1 ou é risco de segurança/perda de dados; **P1** necessário para a qualidade "parece o Orca"; **P2** melhoria. Versão: **v1** (modo leve), **v1.1** (modo isolado), **later** (depois; R1 K-73). `ptyd.v2` é major de protocolo, não versão do produto.
- "Aceite" descreve como verificar. Quando não há aceite explícito, o requisito é verificado por revisão de código ou lint.
- Referências: `00 T6` = decisão T6. Referências à **auditoria** levam o prefixo `audit/`: `audit/09 N3`, `audit/02 #10`, `audit/07 item 1`, `audit/08 C1`, `audit/10 R6.3` neste capítulo são sempre `audit/09 N3`, `audit/02 #10` etc. (R1 X-21). `NN §x` sem número de achado é capítulo da spec.

---

## 0. Identificadores canônicos

Tabela única para tudo que vira código, teste ou caminho em disco. Os outros capítulos citam "`08 §0`". Se um capítulo divergir desta tabela, vale a tabela; quem achar divergência corrige o capítulo, não a tabela (mudar a tabela é decisão do dono). `AB` = `~/Library/Application Support/AgentBox`.

### 0.1 Produto, processos e caminhos

| Coisa | Valor canônico | Origem |
|---|---|---|
| Bundle ID do app | `app.agentbox.mac` | R1 K-70 |
| Identificadores de assinatura | app `app.agentbox.mac`, daemon `app.agentbox.ptyd`, helper `app.agentbox.cli`; mesma identidade local "Agent Box Local Signing" (AR-530) | — |
| Daemon de PTY | executável `Contents/MacOS/agentboxd`; label launchd `app.agentbox.ptyd.v<major>` (v1: `app.agentbox.ptyd.v1`); plist `Contents/Library/LaunchAgents/app.agentbox.ptyd.v1.plist` (`BundleProgram` = `Contents/MacOS/agentboxd-launch`, launcher estável que faz `exec` do `agentboxd`; S-01/T1-24); testes: `app.agentbox.ptyd.test-<n>` | R1 K-70 |
| Socket do daemon (LaunchAgent) | `Sockets` com `SecureSocketWithKey = AGENTBOX_PTYD_SOCK_V1`; caminho escolhido pelo launchd; o app lê com `launchctl getenv AGENTBOX_PTYD_SOCK_V1`. **Nunca** `SockPathName` com caminho no home (plist estático não expande `~`) | R3 §1, S-01 |
| Socket do daemon (degradado, testes, plano B do S-01) | `AB/run/ptyd-v1.sock` (`$AGENTBOX_HOME/run/ptyd-v1.sock` nos testes), `bind` feito pelo próprio daemon | 06 §1.2 |
| Socket do app | `AB/run/app.sock` (`0600`), serviços `mcp`, `hook`, `ctl` | AR-106 |
| Quem conecta no daemon | **Só o app**. `agentbox ctl`, `mcp` e `hook` falam com `app.sock` | R1 K-95 |
| Helper | `Contents/MacOS/agentbox`, subcomandos `hook`, `mcp`, `ctl` | — |
| Subsystems de log | `app.agentbox`, `app.agentbox.ptyd`, `app.agentbox.cli` | AR-601 |
| Item do Keychain | serviço `app.agentbox.vault`, conta `master-v1` (único) | AR-510 |
| `installId` | UUID gerado na primeira abertura, `setting.install_id`; nos testes, um por `AGENTBOX_HOME` | R1 K-70 |
| Diretório de dados | `AB` (`0700`; arquivos `0600`) | AR-301 |
| Sessões limpas | `~/AgentBox/sessions/<nome>`; nome automático adjetivo-substantivo (`quiet-harbor`) | P10, P15 |
| Raiz de worktrees | `~/orca/workspaces/<repo>/<slug>` quando importado do Orca (P15), senão `~/AgentBox/worktrees/<repo>/<slug>` | 06 §5.2 |
| Dados de execução de computadores | `~/AgentBox/runs/<session>/<computer>/` com `work/`, `logs/`, `transcript/`, `box.json` | R1 K-98/K-99 |
| Menu bar com app fechado | Sem helper de login. Depois do ⌘Q o app fica em `.accessory` com o `MenuBarExtra`; "Quit Agent Box Completely" tira o ícone até reabrir | R1 D-03, P16 |
| Onde vivem MCP, Docker, computadores, git, hooks, banco | No processo do app (`AgentBoxCore`). O daemon só hospeda PTYs (inclusive `docker exec -it agent dtach …` na v1.1) | R1 K-75 |

### 0.2 Execução, hooks e lançamento

| Coisa | Valor canônico |
|---|---|
| Env da execução (entra em todo terminal) | `AGENTBOX_PANE_ID` (= `terminal.id`), `AGENTBOX_RUN_ID` (id da execução; novo a cada start ou resume), `AGENTBOX_APP_SOCK` (caminho absoluto de `app.sock`). Nenhuma outra `AGENTBOX_*` chega ao terminal (denylist). Não existem `AGENTBOX_TERMINAL_ID`, `_HOOK_SOCKET`, `_HOOK_TOKEN`, `_SESSION` |
| Env só de desenvolvimento e teste | `AGENTBOX_HOME`, `AGENTBOX_AUTOMATION=1`, `AGENTBOX_FAKE_RUNTIME=1`, `AGENTBOX_REAL_CLI=1`, `AGENTBOX_DOCKER_CONTEXT`, `AGENTBOX_TEST_CORRUPT_DB=1`, `AGENTBOX_HOOK_TIMEOUT_MS` (prazo de entrega do `agentbox hook`; só testes, padrão 200) |
| Comando de hook | `"<bundle>/Contents/MacOS/agentbox" hook --provider <claude\|codex> --event <Evento>` |
| Entrega do hook | frame ao serviço `hook` de `app.sock`, timeout **200 ms**; p95 do helper ≤ 30 ms; `timeout` do hook nas settings do CLI: 5 s |
| Spool de hooks | `AB/run/spool/hooks/<runID>.jsonl` (`0600`), 4 MiB por arquivo com marcador `truncated`; consumo por kqueue |
| Diretório de lançamento | `AB/run/launch/<runID>/` (`0700`), apagado no `exit`, varrido no boot |
| Prompt em arquivo | acima de **16 KiB** (bytes UTF-8) ou começando com `-`: `AB/run/launch/<runID>/prompt.md` (`0600`), argumento `Read and follow the task in <caminho>` |
| argv | Segmentos `executable · identity · profile · injected · prompt`; "argv exato" nos ACs compara tudo **menos** `injected`; Fatia 1 sem injeções (06 §2.4.1) |
| Captura do env de login | `$SHELL -l -i -c` num PTY oculto com marcador, timeout 5 s → `-l -c` com 3 s → env do launchd + PATH conhecido; nunca `zsh` fixo (06 §1.7; S-06) |
| Codex sem hooks confiáveis | Baseline: tail do rollout, `estimated`; nunca gravar em `~/.codex`, nunca `--dangerously-bypass-hook-trust` (06 §3.3.1) |

### 0.3 Protocolo do daemon (detalhe em 06 §1.3; fonte normativa: `AgentBoxProtocol` + fixtures)

| Coisa | Valor canônico |
|---|---|
| Frame | `u32 len BE \| u8 kind \| payload`, máx. 1 MiB; kinds `0x01` control (JSON), `0x02` output (`sessionID 16 B \| seq u64 \| bytes`), `0x03` input (`sessionID 16 B \| origin u8 \| bytes`) |
| `seq` | offset em bytes desde o início da sessão |
| `origin` do input | `0x00` tecla · `0x01` colagem do usuário · `0x02` colagem do app por clique (T11) · `0x03` `ctl` · `0x04` pai → filho (P12) · `0x05` resposta a consulta do terminal |
| Ops | `hello`/`helloAck`, `create`, `list`, `attach{mode: snapshot\|sinceSeq}`, `detach`, `resize`, `signal`, `kill`, `subscribe`, `textSnapshot`, `forget`, `drainWhenIdle`, `ping` (input por frame `0x03`) |
| Eventos | `exit`, `title`, `cwd`, `bell`, `prompt`, `altScreen`, `modes`, `idle`, `stillAlive`, `resyncRequired`, `sessionGone` |
| Erros | `protocolMajorMismatch`, `badRequest`, `unknownSession`, `sessionExited`, `spawnFailed`, `frameTooLarge`, `notCapable`, `peerRejected`, `internal` |
| Capabilities iniciais | `coldLog`, `osc133`, `textSnapshot`, `inputOrigin`, `drainWhenIdle` |
| Backpressure | **2 MiB** por cliente no daemon → `resyncRequired`. Do lado do app: backlog de 4 MiB por pane (AR-406) |
| Coalescência | 16 ms ou 64 KiB por frame |
| Ring | 4 MiB por sessão (configurável 1–32 MiB) |
| Cold log | `AB/sessions/<ptySessionID>/output.log`, **2 × 8 MiB**; `meta.json` = `terminalID`, `runID`, `argv`, `cwd`, `envKeys` (só nomes), `pid`, `startedAt`, `exit`; apagado com `forget` ou 7 dias depois do `exit` |

### 0.4 Dados e estados

| Coisa | Valor canônico |
|---|---|
| Retenção de `agent_event` | 30 dias **e** 10 mil eventos por execução |
| Debounce de layout e estado transitório | 300 ms (e no fim do gesto) |
| `session.kind` | `worktree` · `checkout` · `folder` · `clean` |
| Estado de atividade do agente (Swift / banco) | `starting` · `idle` · `working` · `needsInput(question\|permission\|other)` / `needs_input` + `status_kind` · `waitingOnSubagents(n)` / `waiting_on_subagents` · `done` · `failed` · `blocked` · `interrupted` · `unknown` · `stalled` (v1.1). `estimated` é flag, não estado. Rótulos: "Needs input", "Status unavailable" |
| Estado do processo/terminal (Swift / banco) | `notStarted` / `not_started` (sessão importada sem processo, P15) · `launching` · `running` · `exited` · `killed` · `failedToStart` / `failed_to_start` · `interrupted` · `containerStopped` / `container_stopped` (v1.1). `daemonUnavailable` é só estado de UI |
| Estado do computador | `queued` · `provisioning` · `ready` · `inUse` / `in_use` · `stopped` · `failed` · `removing` · `removed` · `orphan` |
| Tipo do computador (`display`) | `http` · `headless` · `desktop` |
| Papéis de container | `runtime`, `work` (v1, `exec`), `egress` (sidecar; nunca `gate`), `agent` (v1.1, CLI isolado) |
| Rótulos Docker | `agentbox.owner=<installId>`, `agentbox.computer=<computerId>`, `agentbox.computer_name`, `agentbox.role=runtime\|work\|egress\|agent` |
| Rede por computador | `agentbox-<computerId>` (`internal`) |
| Endpoints do egress | proxy `egress:3128`; API `egress:8790` (`/mcp`, `/hooks/<provider>`, `/git`, `/llm`); admin publicado em `127.0.0.1` |
| Imagens | `ghcr.io/gabrielgreco1/agentbox-box`, `-egress`, `-agent` (v1.1), por digest |
| Proxy | Genérico e configurado pelo usuário (P13): tabela `proxy`; Zyte é só preset. Sem tabela nem coluna de orçamento/teto |
| Nomes de ferramentas MCP | Dono: 07 §3.2/§4.2 (`boxes_reserve`, `box_claim`, `help_request`, `help_wait`, `exec`, `http_request`, `browser_type`, `agent_wait`…) |

### 0.5 Código, UI e ferramentas

| Coisa | Valor canônico |
|---|---|
| Módulo de design system | alvo SPM **`AgentBoxDesignSystem`** em `Packages/AgentBoxKit/Sources/AgentBoxDesignSystem/` (não `AgentBoxDesign`, não `Sources/AgentBoxUI/Design/`) |
| Fonte dos tokens | `design/tokens/*.json` (cor, tipo, espaço, raio, sombra) e `design/motion/tokens.json`; gerados por `scripts/gen-tokens.py` em `AgentBoxDesignSystem/Tokens/*.generated.swift` (`DS.Color`, `DS.Font`, `DS.Space`, `DS.Radius`, `Motion`) e `tokens.js`. O `design/` atual é legado e vai para `legacy/design/` (AR-202) |
| `A11yID` e `ActionID` | enums em `AgentBoxProtocol/Automation/` (Foundation pura), gerados da lista de 03 §22 + convenção de 02 §17; `docs/automation-ids.md` gerado deles |
| Registro de ações | protocolo `ActionDispatching` no Core (`AgentBoxCore/Control/`), implementado pelo `ActionRegistry` da UI e injetado no boot (sem import Core → UI; AR-134) |
| Comandos `ctl` | tabela da AR-806 (`ctl app quit` = Keep Running; `--completely`; foco por `ctl ui action <id> focus`; screenshot por `ctl screenshot --window`) |
| SwiftTerm | **1.20.0 exato** (rev `5d14406`); 1.99/2.x só depois do spike S-02 |
| GRDB | 7.x, versão exata fixada no `Package.resolved` em F0-7 |
| XcodeGen | **2.46.0**, zip do release com SHA-256 conferido pelo `bootstrap.sh` |
| Geist | versão e SHA-256 fixados em F0-7; `OFL.txt` no bundle (AR-122) |
| Swift | `swift-tools-version: 6.2`, Swift 6 estrito, macOS 15 mínimo |

---

## 1. Arquitetura-alvo

### 1.1 Processos

| Processo | Onde roda | Vida | Responsabilidade | Não faz |
|---|---|---|---|---|
| **Agent Box.app** (`AgentBox`) | Mac, sessão GUI do usuário | Aberto pelo usuário; ao ⌘Q com sessões vivas fica só na barra de menus (ver AR-108) | UI, domínio (Core), SQLite, Docker (Engine API), serviço de computadores, git, catálogo, hooks recebidos, servidor MCP do modo leve, canal `ctl`, `MenuBarExtra` (sem helper de login) | Não é dono de PTY |
| **agentboxd** | Mac, LaunchAgent ativado por socket | Sobe na primeira conexão; sai após 60 s sem sessões e sem clientes | PTYs, emulador headless por sessão, ring de saída, log bruto para cold restore, eventos de processo | Não abre banco, não fala com Docker, MCP, git nem hooks |
| **agentbox mcp** | Mac, filho do CLI do agente (stdio) | Vida do CLI | Ponte stdio MCP → UDS do app | Não tem lógica de ferramenta |
| **agentbox hook** | Mac, filho efêmero do CLI do agente | Um evento por execução (≤ 30 ms) | Lê o JSON do hook no stdin, anexa a identidade do pane, entrega ao app por UDS ou grava no spool | Não decide nada; nunca bloqueia o agente por falha do app |
| **agentbox ctl** | Mac, chamado por humano, teste ou agente | Uma chamada | Automação do app (abrir sessão, digitar, ler tela, screenshot, estado) via `app.sock` | Não fala com o daemon (AR-503) |
| **box-runtime** (container) | Docker | Vida do computador | Chromium/Playwright, Xvfb, VNC + websockify, API HTTP de controle, lease agente/humano | Não tem saída direta para a internet |
| **egress** (container sidecar) | Docker | Vida do computador | Proxy de saída (direto ou o proxy que o usuário configurou, P13), listener de requests com bodies, contagem de uso do proxy (sem teto), bloqueio de SSRF, relay de hooks/MCP do modo isolado | Não executa código do agente |
| **work** (container, v1) | Docker | Vida do computador | Shell e HTTP do agente (`exec`, `http_request`, Playwright próprio), `/work` do run, saída só pelo egress | Sem acesso ao CDP nem ao lease do runtime |
| **agent** (container, v1.1) | Docker | Vida do subagente isolado | CLI do agente (claude/codex) sob `dtach`, worktree montado (substitui `work`) | Sem socket Docker, sem `$HOME` do Mac |

### 1.2 Diagrama

```
┌──────────────────────── Agent Box.app (assinada, hardened runtime, sem App Sandbox) ───────────────────────┐
│ AgentBoxApp (@main fino, menus, MenuBarExtra)                                                             │
│  └─ AgentBoxUI (@MainActor) ── DesignSystem ── TerminalSurface (SwiftTerm, Metal)                         │
│        │ view models chamam só serviços do Core                                                            │
│  AgentBoxCore (actors, Swift 6, sem AppKit)                                                               │
│   Workspace · Launch(adapters) · AgentRuns · Computers · Git/GH · Catalog · Attention · Importers         │
│   ├ PTYClient ──────────────┐  ├ MCPHost/HookIngest/CtlServer (UDS) ┐  ├ DockerClient (Engine API, UDS) ┐ │
│  AgentBoxStore (GRDB 7)     │  │                                    │  │                                │ │
│  AgentBoxPlatform (ProcessRunner async, Vault/Keychain, Logger, LoginShellEnv, BlockingIOExecutor)       │ │
│  Contents/MacOS/{AgentBox, agentboxd, agentbox} · Contents/Library/LaunchAgents/app.agentbox.ptyd.v1.plist│ │
└─────────────────────────────┼───────────────────────────────────────┼─────────────────────────────────┼───┘
      UDS ptyd-v1 (§0.1)       │        UDS run/app.sock               │ UDS docker.sock do contexto ativo│
      (frames binários,        │        (MCP, hooks, ctl)              │ + HTTP 127.0.0.1:<porta> p/ boxes│
       peer uid + assinatura)  │              ▲         ▲              ▼                                  │
┌──────────────────────────────▼──┐   agentbox mcp  agentbox hook   ┌──────── Docker (Desktop | OrbStack | Colima) ───────┐
│ agentboxd (LaunchAgent)          │   (stdio do CLI) (hook do CLI)  │ rede agentbox-<computador> (internal)               │
│  Session × N                     │                                 │  runtime ◄── work (v1: exec) / agent (v1.1: CLI)    │
│   PTY master · HeadlessTerminal  │── argv local, ou                │       │               │                             │
│   ring 4 MiB · seq · log bruto   │   `docker exec -it agent dtach` │       └──────► egress ◄──┘ ──► internet             │
└──────────────────────────────────┘   (v1.1)                        │  portas publicadas só em 127.0.0.1 (API, VNC, admin)│
                                                                     └─────────────────────────────────────────────────────┘
```

### 1.3 Requisitos de processos e IPC

**AR-101 [P0 · v1] Daemon único de PTY.** `agentboxd` é registrado com `SMAppService.agent(plistName:)`. O plist (em `Contents/Library/LaunchAgents/`) usa `BundleProgram=Contents/MacOS/agentboxd`, `AssociatedBundleIdentifiers=[app.agentbox.mac]`, `ProcessType=Interactive`, `AbandonProcessGroup=true`, `KeepAlive=false` e a chave `Sockets` com `SecureSocketWithKey=AGENTBOX_PTYD_SOCK_V1` (`00 T1`; `audit/09 §2.2`). **Não** usar `SockPathName` com caminho no home: o plist é estático no bundle e `launchd.plist(5)` não expande `~` nem variáveis (R3 §1). O launchd cria o socket num diretório privado e publica o caminho em `AGENTBOX_PTYD_SOCK_V1` no domínio do usuário; o app lê com `launchctl getenv` após o `register()`. O daemon obtém o fd com `launch_activate_socket`. Plano B, se o spike S-01 reprovar: `RunAtLoad=false`, o app acorda o daemon com `launchctl kickstart` e o daemon faz `bind` em `AB/run/ptyd-v1.sock` (exige registrar exceção a T1 no 00). Detalhe em 06 §1.2. Um host por sessão fica para later, se crash ou upgrade do daemon virar problema (`audit/09` D2).
- Aceite: com o app fechado por completo, `launchctl print gui/$UID/app.agentbox.ptyd.v1` mostra o job e `launchctl getenv AGENTBOX_PTYD_SOCK_V1` devolve o caminho; conectar no socket sobe o daemon; 60 s sem sessão nem cliente, ele sai.

**AR-102 [P0 · v1] Protocolo do daemon.** Um protocolo só, descrito em 06 §1.3 e resumido em §0.3; a fonte normativa é o módulo `AgentBoxProtocol` com fixtures JSON em `Tests/ProtocolTests/Fixtures/`, escritas antes do daemon (T-04). Frames `u32 len BE | u8 kind | payload` (máx. 1 MiB): control JSON, output `sessionID(16) | seq(u64) | bytes` (`seq` = offset em bytes), input `sessionID(16) | origin(u8) | bytes`. Handshake `hello{protocol{major,minor}, client{kind:"app", build}, capabilities}` → `helloAck{protocol, daemon{build,pid,startedAt,binary}, capabilities, sessions}`. Ops: `create`, `list`, `attach{sessionID, cols, rows, mode: snapshot|sinceSeq}`, `detach`, `resize`, `signal`, `kill`, `subscribe`, `textSnapshot`, `forget`, `drainWhenIdle`, `ping`. Snapshot vai como `attachSnapshot{startSeq,endSeq,modesPreamble}` seguido de frames `output` (nunca um JSON gigante). Contadores `inputBytesByOrigin` em `list` permitem provar que o app não escreveu no PTY. Recurso novo entra como `capability`; só quebra de compatibilidade sobe o `major`.
- Backpressure: fila limitada por cliente (**2 MiB**). Estourou: o daemon descarta e envia `resyncRequired`; o cliente refaz `attach` em modo `snapshot`.
- Sessões não visíveis no app não recebem bytes, só eventos (`audit/09 §2.2`).
- Aceite: testes de protocolo da §8 (reattach após matar o cliente, seq sem buracos, `resyncRequired`, cliente N-1).

**AR-103 [P0 · v1] Env vem do app.** O daemon herda o env mínimo do launchd. O app captura o ambiente do shell de login do usuário (conforme 06 §1.7: `-l -i -c` num PTY oculto com marcador e timeout de 5 s, depois `-l -c` com 3 s, depois env do launchd mais PATH conhecido; nunca `zsh` fixo) uma vez por boot e quando o usuário pede "Reload Shell Environment", e envia o env completo em cada `create` (`audit/09 §5 item 6`). Não há allowlist que remova `SSH_AUTH_SOCK`, proxies, `*_API_KEY` etc. (`audit/02 #3`).

**AR-104 [P0 · v1] Restauração de tela.** Por sessão, um `SwiftTerm.Terminal` headless numa fila serial própria, mais um ring de bytes brutos de 4 MiB reaplicado num emulador novo no `attach`, cortando no último `ESC c`, `CSI 2J`/`3J` ou troca de alt-screen (`audit/09 D3`). Cold restore: log bruto rotativo `sessions/<ptySessionID>/output.log` (2 × 8 MiB, 06 §1.5) + `meta.json` (`terminalID`, `runID`, `argv`, `cwd`, `envKeys` só com nomes, **nunca valores**, `pid`, `startedAt`, `exit`). Depois de reboot ou crash do daemon, o terminal vira `interrupted`, o app mostra o último buffer esmaecido e [Resume] quando há ID nativo.
- Um serializador de células (opção (a) do `audit/09 §2.2`) só entra se aparecerem artefatos visuais (later).

**AR-105 [P0 · v1] Respostas a consultas do terminal.** Só **um** emulador responde a consultas do programa (DA1/DA2, DSR, tamanho da janela): o da UI quando há cliente anexado em modo interativo; o headless do daemon quando nenhum cliente está anexado. O headless **nunca** responde OSC 52 (leitura), consultas de cor (OSC 4/10/11) nem DECRQSS. Isso evita respostas duplicadas e vazamento por um emulador sem UI.

**AR-106 [P0 · v1] Canal do app (`run/app.sock`).** Um único servidor UDS no app, `0600`, com três serviços multiplexados por handshake: `mcp` (helper stdio do modo leve), `hook` (eventos de hooks) e `ctl` (automação, desligado por padrão, AR-806). Framing `u32 len | JSON`. Sem limite artificial de 8 conexões (`audit/08 C3`); cada chamada é uma `Task` cancelável, sem semáforo (`audit/02 #9`).

**AR-107 [P0 · v1] Sem XPC; sem listener TCP no host.**
- **Decisão:** toda IPC local é UDS. XPC (com `setCodeSigningRequirement`) foi considerado e rejeitado: o mesmo protocolo precisa servir o app, o helper `agentbox`, os testes de protocolo e o `ctl`, e frames binários de alto volume são mais simples em socket. A autenticação do peer que o XPC daria vem de `LOCAL_PEERTOKEN` + `SecCodeCopyGuestWithAttributes` (AR-503).
- O app **não** abre porta TCP no Mac. Containers não alcançam o app (no Docker Desktop, serviços em `127.0.0.1` do Mac podem ser alcançados por `host.docker.internal`; `audit/09 §5 item 4`). Toda conversa app ↔ box é **iniciada pelo app** para portas publicadas em `127.0.0.1` (API do runtime, VNC, admin do egress). Hooks e chamadas de ferramenta vindos de dentro da box (v1.1) ficam numa fila no egress, que o app consome por SSE.

**AR-108 [P0 · v1] Ciclo de vida do app versus agentes (P4).** Fechar a janela ou dar ⌘Q **com sessões vivas** (Keep Running) solta as views de terminal, os observadores pesados e as conexões de dados do daemon, e muda a política de ativação para `.accessory`: o processo continua com o `MenuBarExtra` (estado dos agentes, "Open Agent Box", "Quit Agent Box Completely"), hooks, MCP e computadores. **Não há helper de login**: o ícone é do próprio app (R1 D-03, fechado por P16). "Quit Agent Box Completely" encerra o processo do app e tira o ícone até reabrir; o daemon segue com os PTYs. O aviso aparece no primeiro ⌘Q com agentes vivos, com "Don't ask again" marcado por padrão (P15; overlay T5; microcopy em 03 §16.10 e 06 §1.9).
- Ordem de saída corrigida (`audit/09 N10`): nunca matar terminais antes de decidir o destino das boxes; nada de `usleep` no main thread.
- Aceite: `ctl app quit` → PID do `claude` igual após `ctl app launch`, buffer restaurado (cenário E2E, §8.3).

**AR-109 [P0 · v1] Entrega de hooks sem o app.** `agentbox hook` tenta `run/app.sock` com timeout de 200 ms. Se falhar, grava o evento (JSONL, `0600`) em `run/spool/hooks/<runID>.jsonl` (4 MiB por arquivo, marcador `truncated`) e sai com código 0. O app consome o spool ao abrir e enquanto roda (kqueue/`DispatchSource` no diretório, nunca polling de 300 ms; `audit/09 N15`). Uma linha inválida é registrada e pulada; o cursor sempre avança (`audit/02 #11`).

**AR-110 [P0 · v1] Helper MCP resiliente.** Se `run/app.sock` não existir, `agentbox mcp` abre o app em segundo plano (`open -g -j -b app.agentbox.mac`), espera até 10 s e reconecta. Sem app, responde ao CLI com erro de ferramenta legível ("Agent Box is not running; retrying") em vez de sair com código 3 (`audit/02 §2.9`). Canais por execução não usam diretórios determinísticos criados com `mkdir` exclusivo (`audit/09 N9`): o socket é único e a execução se identifica no handshake.

**AR-111 [P0 · v1] Identidade da execução.** Cada terminal lançado recebe `AGENTBOX_PANE_ID` (= `terminal.id`), `AGENTBOX_RUN_ID` (novo a cada start ou resume) e `AGENTBOX_APP_SOCK` (caminho absoluto de `app.sock`) no env, e nenhuma outra `AGENTBOX_*` (§0.2). Esses valores servem para **correlação**, não autenticação (`audit/09 §2.7`). Não existe HMAC de caller nem `route_token` exposto no schema das ferramentas (`audit/02 §2.9`); a identidade de subagente vem de `agent_id` dos hooks e de um processo MCP por filho (`mcpServers` inline; `audit/08 N18`).

**AR-112 [P0 · v1] Hooks por lançamento (`00 T10`).** Claude: arquivo `--settings` gerado em `run/launch/<runID>/` (`0700`) com hooks `type: "command"` chamando `"<bundle>/Contents/MacOS/agentbox" hook --provider claude --event <Evento>`. Codex: os hooks exigem *trust* por hash gravado em `~/.codex/config.toml`; a estratégia sem violar T10 (rollout `estimated` como baseline; hooks por `-c` só se o spike S-05 provar que rodam sem trust ou se o dono aceitar o trust gravado pelo próprio Codex) está em 06 §3.3.1. **Fatia 1 não injeta nada** (agentes aparecem `unknown`). Nunca escrever em `~/.claude/settings.json` nem `~/.codex/*` (convivência com os hooks globais do Orca). O diretório do lançamento é apagado quando a sessão termina, com limpeza que continua após erro (`audit/02 #16`).

**AR-113 [P1 · v1.1] Hooks e MCP de dentro do container.** No modo isolado, o CLI usa hooks `type: "http"` para `http://egress:8790/hooks/<provider>` e MCP por HTTP em `http://egress:8790/mcp` (o egress repassa ao runtime as ferramentas de computador e enfileira para o app as que dependem dele; 07 CS-540/541). Ferramentas que precisam do app (`agent_spawn`, `ask_parent` etc.) entram na fila do egress e o app responde pelo canal admin. Nenhum binário Swift roda no Linux. Comportamento com o app fechado: a fila retém por até 15 min e responde "app unavailable, retry" ao CLI (`audit/08 C12`).

**AR-114 [P0 · v1] Docker pela Engine API.** Cliente HTTP/1.1 mínimo sobre UDS (Network.framework, sem SwiftNIO) para `_ping`, `version`, `info`, `containers/*`, `networks/*`, `volumes/*`, `images/*` e `/events?filters={"label":["agentbox.owner=<installId>"]}` (`00 T7`; `audit/09 §2.5`). `exec` com stdin (ferramenta `exec`, v1; PTY do modo isolado, v1.1) usa `POST /containers/{id}/exec` + `POST /exec/{id}/start` com conexão **hijacked** (`Connection: Upgrade`, `Upgrade: tcp`) e stream multiplexado; nenhum capítulo usa `docker exec`/`docker context ls` do CLI (R3 §11.10). O CLI `docker` só é usado para `build` e `pull`, com PATH aumentado (`/usr/local/bin`, `/opt/homebrew/bin`, `~/.orbstack/bin`, `/Applications/Docker.app/Contents/Resources/bin`) para os credential helpers (`audit/09 N12`). Operações canceladas são reconciliadas pelos eventos (`audit/09 N19`).

### 1.4 Módulos, alvos e projeto Xcode

**AR-120 [P0 · v1] Projeto Xcode gerado com XcodeGen.**
- **Decisão: XcodeGen**, não Tuist. Motivos: manifesto YAML único (`project.yml`), sem runtime próprio, sem cache nem serviço remoto, e o código fica em pacotes SPM locais (que é o que o XcodeGen referencia bem). Tuist traria um toolchain e um modelo de projeto a mais para um app de um dono só.
- `project.yml` na raiz; o `.xcodeproj` gerado **não** é versionado (`.gitignore`). `scripts/gen.sh` gera. **Versão fixada: XcodeGen 2.46.0.** O Homebrew não fixa versão de fórmula, então `scripts/bootstrap.sh` baixa `https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip` para `.tools/xcodegen/2.46.0/` (fora do git), confere o SHA-256 registrado em `scripts/tool-versions.txt` (preenchido em F0-7) e falha com qualquer outra versão ou hash. `gen.sh` usa só esse binário, nunca o do PATH (R3 §1).
- O projeto existe por três motivos: app bundle com LaunchAgent e helpers embutidos, assinatura, e alvo de XCUITest (`audit/09 N7`).

**AR-121 [P0 · v1] Pacote SPM local `Packages/AgentBoxKit`** (`swift-tools-version: 6.2`, `platforms: [.macOS(.v15)]`, `00 T3`) com estes alvos:

| Alvo | Tipo | Depende de | Conteúdo |
|---|---|---|---|
| `AgentBoxProtocol` | lib | — (só Foundation) | DTOs `Sendable`, framing, versões e capabilities do daemon, mensagens do `app.sock` (mcp/hook/ctl); `Automation/` com os enums `A11yID` e `ActionID` e os DTOs do `ctl` (árvore de UI, resultado de ação) |
| `AgentBoxPlatform` | lib | Protocol | `ProcessRunner` async, `BlockingIOExecutor`, `Vault` (Keychain + CryptoKit), `LogFacade` (Logger + arquivo), `LoginShellEnv`, `FileWatch` (kqueue/FSEvents), `UDSServer`/`UDSClient`, peer auth, `SMAppService` |
| `AgentBoxTerminalCore` | lib | SwiftTerm (só `Terminal`, sem views) | Ring de saída, corte para restore, filtro de consultas (AR-105), política OSC, sanitização de paste |
| `AgentBoxStore` | lib | Platform, GRDB | Schema, migrações, records, observações, backup, verificação de integridade |
| `AgentBoxDocker` | lib | Platform, Protocol | Engine API, `RuntimeDetector`, imagens (tag por hash, GHCR por digest, build local), eventos |
| `AgentBoxCore` | lib | Protocol, Platform, Store, Docker | Serviços de domínio (§1.1), adapters de CLI, MCP host, ingestão de hooks, servidor `ctl` e o protocolo `ActionDispatching` (AR-134), importadores |
| `AgentBoxDesignSystem` | lib | Protocol (só `A11yID`), SwiftUI/AppKit | Em `Packages/AgentBoxKit/Sources/AgentBoxDesignSystem/`: `Tokens/*.generated.swift` (`DS.Color/Font/Space/Radius`, `Motion`) gerados de `design/tokens/*.json` e `design/motion/tokens.json`, componentes, ícones, fontes (§0.5) |
| `AgentBoxUI` | lib | Core, DesignSystem, TerminalCore, SwiftTerm | Telas, view models, `TerminalSurface`, overlays, `KeyBindingRegistry` (com escopo e teste anti-conflito), `ActionRegistry` (implementa `ActionDispatching`) |
| `agentboxd` | exe | Protocol, Platform, TerminalCore | Daemon de PTY |
| `agentbox` | exe | Protocol, Platform, swift-argument-parser | `mcp`, `hook`, `ctl` |
| Testes | ver §8 | | `ProtocolTests`, `StoreTests`, `CoreTests`, `DockerTests` (gated), `TerminalCoreTests`, `DaemonTests`, `UISnapshotTests`, `AgentBoxUITests` (XCUITest) |

O alvo `AgentBox` (app) fica no `project.yml` e só contém `@main`, `Info.plist`, assets e entitlements.

**AR-122 [P0 · v1] Dependências externas (todas com versão exata e `Package.resolved` versionado).**

| Dependência | Uso | Regra |
|---|---|---|
| SwiftTerm **1.99.0 exato** (rev `2dad6a1`, P20, T1-09) | Emulador na UI (Metal) e headless no daemon | Pré-release da v2: a troca para a 2.0 final exige decisão escrita aqui; `Package.resolved` fixa a revisão. `feed(byteArray:)` e `send(data:)` são `nonisolated` (fora do main; não chamar de callback do delegate); `terminal` não é público na view. Paridade com a 1.20.0 explicada em `docs/evidence/spikes/S-02/parity`. Na UI, só `TerminalView` com delegate próprio; **proibido `LocalProcessTerminalView`** (devolve o pasteboard em `clipboardRead`, violando T6) e a find bar privada `TerminalFindBarView`/`performFindPanelAction` (a busca usa a API pública, 02 §16). Sem fork; patch vai upstream com revisão fixada |
| GRDB 7.x | SQLite, migrações, `ValueObservation`, backup | Única dependência de persistência |
| swift-argument-parser | CLI `agentbox` | Declarada explicitamente no `Package.swift` (hoje é pin órfão `1.8.2` no `Package.resolved`, R3 §1) |
| swift-snapshot-testing | Só em testes | — |
| noVNC (JS, versão fixada, vendorizado com hash) | Viewer de desktop em `WKWebView` (`00 T8`) | Servido do bundle do app por `WKURLSchemeHandler`, nunca carregado do container |
| XcodeGen 2.46.0 (ferramenta) | Gerar o projeto | Zip do release com SHA-256, AR-120 |
| Fonte Geist (SIL OFL 1.1) | Tipografia da UI (02) | Release de `github.com/vercel/geist-font` com versão, URL e SHA-256 fixados em F0-7 (nome upstream `Geist[wght].ttf`, não `Geist-Variable.ttf`). Embutida em `Contents/Resources/Fonts/` com **`OFL.txt` ao lado** (exigência da OFL), registrada por `ATSApplicationFontsPath = Fonts`; licença exibida no About › Acknowledgements. Teste: `NSFont(name:)` e `Font.custom("Geist")` resolvem a família registrada |

Proibido sem decisão registrada neste capítulo: SwiftNIO/AsyncHTTPClient, Sparkle (`00 T4`), Realm/SwiftData/Core Data, Combine em código novo de domínio, qualquer SDK de telemetria remota.
- `swift-subprocess` é reavaliado quando chegar a 1.0; até lá, `ProcessRunner` próprio sobre `Process` + `terminationHandler` + leitura por `DispatchIO`, com `AsyncStream` de saída.

### 1.5 Regras de camadas (verificadas)

**AR-130 [P0 · v1] O grafo SPM é a primeira barreira.** Um módulo só importa o que declara. Em especial:
- `AgentBoxCore`, `AgentBoxStore`, `AgentBoxDocker`, `AgentBoxPlatform`, `AgentBoxProtocol` não importam AppKit, SwiftUI nem SwiftTerm.
- `agentboxd` não depende de Core, Store nem Docker (o daemon é pequeno e muda pouco; `audit/09 §2.1`).
- `agentbox` não depende de Core (inicialização rápida: o hook tem orçamento de 30 ms, AR-707).
- `AgentBoxDesignSystem` não depende de Core.
- Core não importa UI nem DesignSystem; a UI chega ao Core só por protocolos injetados (AR-134).

**AR-131 [P0 · v1] Lint de proibições (`scripts/lint.sh`, com `rg`, roda no CI e no pre-commit).** Cada padrão é uma regex com limite de palavra (ex.: `\bsleep\(` não pega `Task.sleep(for:)`; `\bProcess\(` não pega `ProcessInfo`; `\bprint\(` não pega `fingerprint(`) e tem um teste de lint com um caso que deve falhar e um que deve passar (R3 §11.8). As regras de UI (`.sheet(`, `List(`, literais fora de `DS.*`, `Button` fora do registro) ficam em `scripts/lint-ui.sh` (dono do conteúdo: 02; mecânica de registro: AR-805). Falha o build se encontrar, fora das exceções listadas:

| Proibido | Onde | Exceção |
|---|---|---|
| `DispatchSemaphore`, `DispatchGroup.wait`, `Thread.sleep`, `usleep`, `sleep(` | Todo o código | `AgentBoxPlatform/Blocking*` e `agentboxd` |
| `NSLock`, `NSRecursiveLock`, `os_unfair_lock`, `OSAllocatedUnfairLock` | Todo o código | Platform e TerminalCore, com comentário `// LOCK:` explicando que nenhum I/O ocorre segurando o lock |
| `Process(`, `posix_spawn`, `forkpty` | Todo o código | `AgentBoxPlatform/ProcessRunner*` e `agentboxd` |
| `import GRDB` | Fora de `AgentBoxStore` | — |
| `FileManager`, `URLSession`, `Process` | `AgentBoxUI`, `AgentBoxDesignSystem` | — |
| `.sheet(`, `NSToolbar`, `.toolbar {` | UI | Nenhuma (`00 T5`) |
| `print(`, `NSLog(`, `debugPrint(` | Todo o código | Testes |
| `@unchecked Sendable`, `nonisolated(unsafe)` | Todo o código | Com comentário `// SAFETY:` e teste de stress citado |
| `Task.detached` | Todo o código | Com comentário `// DETACHED:` |
| `DispatchQueue.main.sync` | Todo o código | Nenhuma |
| `try!`, `fatalError(` | Código de produção | `fatalError` só em `required init?(coder:)` |
| `UserDefaults` | Todo o código | `AgentBoxStore/LegacyDefaults` (importação) |
| Strings `webscraping-expert`, `colima-agentbox-dev`, `ab019` | Código de produção | Nenhuma (`audit/02 #5`, `audit/02 §5`) |
| `setUseMetal(false)` | UI | Fallback com log de erro |
| `LocalProcessTerminalView`, `LocalProcess(`, `TerminalFindBarView`, `performFindPanelAction` | Todo o código | Nenhuma (T6; PTY é do daemon; AR-122) |

**AR-132 [P0 · v1] Zero lógica de domínio em views (`00 T3`).** Views chamam métodos de view model; view models chamam serviços do Core e expõem estado `@Observable`. Nada de persistência, processo, Docker ou git a partir de uma `View`. Revisão de PR confere; o lint pega os símbolos acima.

**AR-134 [P0 · v1] Registro de ações sem ciclo Core → UI.** O servidor `ctl` vive no Core, o registro de ações na UI e os IDs em `AgentBoxProtocol/Automation`. O Core declara `protocol ActionDispatching: Sendable { func perform(_ id: ActionID, _ arg: ActionArgument?) async throws -> ActionResult; func uiTree(root: A11yID?) async -> UITreeSnapshot; func screenshot(_ target: ScreenshotTarget) async throws -> Data }`; o `ActionRegistry` (`@MainActor`, AgentBoxUI) implementa e é injetado no `CtlServer` pelo `AppEnvironment` no boot (R3 §11.7). O registro é a fonte do índice de ações (ID, rótulo, atalho, fatia, pré-condição, efeito, motivo de desabilitado) e do teste de cobertura registro × testes.

**AR-133 [P0 · v1] Injeção de dependência explícita.** Nada de singletons `.shared` acoplados por Combine (`audit/02 §3`). Um `AppEnvironment` (struct de serviços) é montado no `@main` e passado aos view models. Testes montam o ambiente com fakes (`FakeDockerClient`, `FakePTYClient`, `InMemoryStore`).

---

## 2. Reaproveitamento do código atual

Vereditos: **MANTER** (copiar quase igual), **REFATORAR** (copiar e mudar a forma), **REESCREVER** (usar só como referência de comportamento), **DESCARTAR** (não entra). A UI atual é toda descartada (`00 P1`); a coluna "lógica a extrair" diz o que sai de cada arquivo de UI para o Core antes do descarte.

**AR-201 [P0 · v1]** Nenhum arquivo é copiado sem passar pelo modo Swift 6 estrito e pelo lint (AR-131). Código copiado recebe testes no novo alvo antes do merge.

**AR-202 [P0 · v1] Onde o código antigo vive durante o rebuild (F0-6).** Na Fatia 0, antes da T-01, um único commit move com `git mv` o `Package.swift`, `Package.resolved`, `Sources/`, `Tests/`, `runtime/`, `scripts/` e `design/` atuais para `legacy/` (`legacy/design/` inclusive: os `screens/01-16` em PT-BR com Manrope **não** são referência visual). O build novo (`project.yml`, `Packages/AgentBoxKit`, `scripts/`, `runtime/box`, `runtime/egress`) nunca referencia `legacy/`; os vereditos MANTER/REFATORAR abaixo copiam de `legacy/` para o destino novo. `legacy/` sai do repositório depois da release 1.0. Proposta dos revisores (R3 F0-6), adotada por P16; o dono pode trocar o destino, não a regra de "fora do caminho do build".

### 2.1 `Sources/AgentBoxCore`

| Arquivo atual | Linhas | Veredito | Destino e mudança |
|---|---|---|---|
| `Domain.swift` | 43 | REFATORAR | `Core/Model`. `CLIProvider` ganha `custom`; shell usa `$SHELL`. `TerminalRecord.arguments` se divide em `launch_spec` (o pedido) e `resolved_argv` (como lançou) (`audit/02 §2.1`). `WorkspaceSession` vira `Session` com `kind` (P10). `AppPaths` vai para Platform |
| `Workspaces/WorkspaceStore.swift` | 218 | REFATORAR | `WorkspaceNode`/árvore de splits vira `Core/Layout` (puro, serializado em `tab.layout_json`). Sai o limite fixo de 5 panes e a regra `show()` que substitui o pane focado. `WorkspaceRepository` (JSON) é descartado; vira o importador |
| `Git/GitProcessRunner.swift` | 106 | REESCREVER | Substituído pelo `ProcessRunner` único (corrige o `closeFile` no timeout, `audit/02 #10`) |
| `Git/GitWorkspaceInspector.swift` | 103 | MANTER | `Core/Git`, sobre o runner async. Amplia para status por arquivo e worktrees |
| `Git/GitWorktreeManager.swift` | 147 | MANTER | `Core/Git`. Ganha listar e remover worktree |
| `Processes/CLIExecutableResolver.swift` | 81 | MANTER | `Core/CLI`. Inclui `~/.local/bin` e `~/.orbstack/bin` |
| `Processes/CLICommandProbe.swift` | 109 | REFATORAR | `Core/CLI/CLIHealthService` (actor), sem vars mutadas em closures concorrentes |
| `Processes/CLIAuthStatus.swift` | 26 | REESCREVER | Ler `claude auth status --json`; Codex por saída estruturada, não por substring (`audit/02 §2.4`) |
| `Processes/CLIConversationCatalog.swift` | 203 | REFATORAR | `Core/Conversations`. Sem `Thread.sleep`; amplia para histórico em `~/.claude/projects`, `~/.codex/sessions` e OpenCode |
| `Processes/CLIConversationWriteCoordinator.swift` | 73 | REFATORAR | Vira regra do `LaunchService` (um writer por conversa), como actor |
| `Library/LibraryModels.swift` | 271 | REFATORAR | Só o necessário para o catálogo por referência (`catalog_item`). Memórias e revisões próprias saem (`00 T14`) |
| `Library/LibraryMutations.swift` | 161 | REFATORAR | Mutações puras reaproveitadas para perfis de lançamento; revisões removidas |
| `Library/LibraryRepository.swift` | 131 | DESCARTAR | Colava skill inteira no prompt (`audit/02 #6`). Vira importador |
| `HumanRequests/HumanRequestStore.swift` | 152 | REFATORAR | `Core/Attention` (tabela `attention`), com o motivo real do agente (`audit/02 #18`) |
| `AgentLaunch/AgentLaunchPlanner.swift` | 726 | REESCREVER | `Core/Launch` com um adapter por provider (`LaunchSpec` → argv/env/arquivos), diretório temporário por execução e limpeza no exit. Sem hash, revisão nem binding (`00 T14`; `audit/02 §2.7`) |
| `AgentLaunch/ClaudeHookLaunchSnapshot.swift` | 265 | DESCARTAR | Contexto em pedaços via `SubagentStart`; substituído por `--agents`/`mcpServers` inline |
| `AgentLaunch/ScrapingLaunchTarget.swift` | 44 | DESCARTAR | Caso pessoal no Core (`audit/02 #5`) |
| `AgentRegistry/AgentRunRegistry.swift` | 237 | REFATORAR | `Core/AgentRuns` (actor) sobre `agent_run`/`agent_event`, com reconciliação de execuções presas em `running` |
| `AgentRegistry/ClaudeHookInbox.swift` | 144 | REESCREVER | `Core/HookIngest` (socket + spool, AR-109), sem HMAC |
| `ComputerMCP/ComputerMCPProtocol.swift` | 109 | REFATORAR | `Core/MCP`. JSON-RPC mantido; `instructions` curtas; ferramentas ampliadas (capítulo de computadores) |
| `ComputerMCP/ComputerMCPToolArguments.swift` | 115 | REFATORAR | `Core/MCP`. Remove `route_token`; mantém o motivo do pedido de ajuda |
| `ComputerMCP/LocalMCPChannel.swift` | 366 | REFATORAR | Framing e validação de socket vão para `Platform/UDSServer`; handler vira async sem semáforo (`audit/02 #9`) |
| `ComputerMCP/ComputerMCPConfiguration.swift` | 53 | REESCREVER | Configuração MCP gerada pelo adapter; sem `/private/tmp/ab-<planID>` (`audit/09 N9`) |
| `ComputerMCP/ComputerMCPAccessPolicy.swift` | 40 | REFATORAR | Regra de criação de computador no `ComputerScheduler` |
| `ComputerMCP/ComputerCallProvenance.swift` | 121 | DESCARTAR | HMAC como autenticação não é fronteira (`audit/09 §2.7`) |
| `BrowserRuntime/BrowserRuntimeClient.swift` | 395 | MANTER | `Core/Computers/RuntimeClient`, `Sendable`, sem `health()` extra por chamada, sem force-unwrap (`audit/02 §2.10`) |
| `Control/ControlBroker.swift` | 302 | DESCARTAR | Broker persistido e delegação nunca usada (`audit/02 §2.11`) |
| `Control/ComputerControlBridge.swift` | 407 | REESCREVER | `ComputerControlService` fino: o runtime da box é a única fonte de quem controla; erro de escrita não revoga lease (`audit/02 #7`); chamadas concorrentes entram em fila (`audit/02 #8`) |
| `Docker/BrowserComputerService.swift` | 948 | REESCREVER | `Core/Computers/ComputerService` sobre `AgentBoxDocker`. Aproveitar só os flags de hardening do `docker create` (`--read-only`, `--cap-drop ALL`, `no-new-privileges`, limites). Ganha remover, GC, rede `internal`, egress e token por arquivo |
| `Docker/DockerProcessRunner.swift` | 109 | REESCREVER | Engine API (AR-114) + `ProcessRunner` só para build/pull |
| `Docker/DockerConnection.swift` | 31 | REFATORAR | `Docker/RuntimeDetector` (contexto ativo, sockets conhecidos) |
| `Docker/ComputerPolicy.swift` | 146 | REFATORAR | Defaults coerentes (criação automática, 2 GiB desktop) em `setting`; overrides só restringem |
| `Docker/DockerComputerService.swift` | 174 | DESCARTAR | Box legada `python:slim … sleep infinity` |
| `Docker/ScrapingBoxAssignmentStore.swift` | 48 | DESCARTAR | Caso pessoal |
| `Docker/LegacyKeychainInteraction.swift` | 22 | DESCARTAR | Contorno de API deprecada; desnecessário com Vault (AR-510) |
| `Capture/CaptureStore.swift`, `CaptureModels.swift`, `DatasetStore.swift` | 742 | DESCARTAR | Fora do escopo (`00 T14`). O listener de requests do egress substitui a captura |
| `Secrets/SecretVault.swift` | 178 | REESCREVER | `Platform/Vault` (item único) + `Core/Secrets` com consumidor real (injeção no env do PTY) |
| `Secrets/SecretModels.swift` | 112 | REFATORAR | Modelos de `secret`/`secret_binding`; grants por destino descartados |
| `Secrets/EnvFileParser.swift` | 101 | MANTER | `Core/Secrets`, importação de `.env` como dados |

### 2.2 `Sources/AgentBoxMCP` e `Sources/AgentBox` (UI)

| Arquivo atual | Veredito | Lógica a extrair antes do descarte |
|---|---|---|
| `AgentBoxMCP/main.swift` | REFATORAR | Vira `agentbox mcp`, com reconexão (AR-110) |
| `Terminal/TerminalRuntimeManager.swift` | DESCARTAR | `decodeWaitStatus` e sinal por process group vão para `agentboxd` |
| `Terminal/NativeAgentMonitor.swift` | DESCARTAR | Reconciliação de execuções anteriores vai para `Core/AgentRuns` |
| `Terminal/ConversationResumeView.swift` | DESCARTAR | — |
| `Computers/AgentComputerAccess.swift` | DESCARTAR | Roteamento MCP, criação de box por subagente, pedidos humanos → `ComputerAccessService` (Core) |
| `Computers/RemoteDesktopView.swift` | DESCARTAR | Substituído por noVNC (`00 T8`); política de atalhos capturados vai para o capítulo de UI |
| `Computers/HumanRequestCenter.swift`, `HumanRequestsView.swift`, `BrokerDesktopActions.swift` | DESCARTAR | Notificações → `Core/Attention` + `NotificationService` |
| `Docker/BrowserComputerStore.swift`, `BrowserComputerPanel.swift`, `DockerViews.swift` | DESCARTAR | Orquestração → `ComputerService` |
| `Capture/*` | DESCARTAR | — |
| `Workspace/WorkspaceView.swift` | DESCARTAR | `launchSavedAgent`, `startTerminalValidated`, `refreshGit`, `createWorktree` → `LaunchService`, `WorkspaceService`, `GitService` |
| `Workspace/AgentLaunchBindingStore.swift` | DESCARTAR | — |
| `Workspace/WorkspaceDirectoryAccess.swift` | DESCARTAR | Bookmarks desnecessários sem sandbox (`audit/09 §5 item 9`) |
| `Library/*` | DESCARTAR | `createScrapingAgent` some; importação genérica vai para o catálogo |
| `Settings/SecretSettingsView.swift`, `App/*` | DESCARTAR | Probes de CLI → `CLIHealthService` |
| `Resources/Brands/*` | MANTER | Ícones de provider vão para `DesignSystem` (revisar com o design) |

### 2.3 `runtime/`, `scripts/` e `Tests/`

| Item | Veredito | Destino |
|---|---|---|
| `runtime/boxes/server.py`, `engine.py`, `desktop_browser.py` | REFATORAR | `runtime/box/`. Sem lock global nas leituras (`audit/02 #20`); escuta só na rede interna; VNC + websockify; ações ampliadas (capítulo de computadores); token lido de `/run/agentbox/token` |
| `runtime/boxes/public_http.py` | REFATORAR | A lógica de bloqueio de IP privado e pinning de DNS vai para o `egress` (vale para tudo, não só para a ferramenta HTTP; `audit/09 N8`) |
| `runtime/boxes/capture.py` | DESCARTAR | Substituído pelo listener do egress |
| `runtime/boxes/Dockerfile` | REFATORAR | Sem pins de pacote apt; base fixada por digest; tag por hash de contexto; publicada no GHCR (`audit/09 N11`, `00 T7`) |
| `runtime/boxes/test_*.py`, `smoke_docker.py` | REFATORAR | Testes do runtime no CI Linux; smoke sem contexto fixo (`AGENTBOX_DOCKER_CONTEXT`) |
| `runtime/hooks/claude_event.py` (+ teste) | DESCARTAR | Substituído por `agentbox hook` (`audit/09 N15`) |
| — | NOVO | `runtime/egress/` (proxy configurável, listener, uso do proxy, SSRF, relay) e, na v1.1, `runtime/agent/` (imagem `agentbox-agent`) |
| `scripts/build_app.sh` | REESCREVER | `scripts/build.sh` + `install.sh` (§9) |
| `scripts/build_spec.py` | DESCARTAR | Gerava a spec antiga |
| `Tests/AgentBoxCoreTests/GitWorkspaceTests`, `ProcessesResolverTests`, `ProcessesProbeTests`, `CLIConversationCatalogTests`, `ComputerMCPProtocolTests`, `ComputerMCPToolArgumentsTests`, `BrowserRuntimeTests`, `WorkspaceStoreTests` (parte do layout), `LibraryTests` (parte das mutações), `SecretsTests` (parser) | REFATORAR | Portar para Swift Testing junto com o código que testam |
| `Tests/AgentBoxRuntimeTests/ProcessesPTYTests` | REFATORAR | Vira teste do daemon (sinais, grupos, exit codes) |
| `LocalMCPChannelTests` | REFATORAR | Vira teste do `UDSServer` e do helper real |
| Demais testes (`ControlBroker`, `ComputerCallProvenance`, `BrowserImageUpdate*`, `ScrapingBox*`, `Capture*`, `LegacyKeychain*`, `DockerComputerTests`, `NativeAgentMonitor`, `AgentComputerAccessRouting`, `DesktopStream`, `CapturePanelStore`, `ConversationResumeRuntime`, `NativeChildFlowDockerTests`, `BrowserChildControlDockerTests`, `ComputerPolicyTests`, `HumanRequestsTests`, `AgentLaunchTests`, `AgentRegistryTests`, `ScrapingLaunchTargetTests`, `BrowserComputerServiceTests`) | DESCARTAR | Testam código descartado ou reescrito. O cenário de `NativeChildFlowDockerTests` (Claude real + box) reaparece como contrato de CLI gated (§8.2) |

---

## 3. Dados

### 3.1 Layout em disco

**AR-301 [P0 · v1]** Tudo em `~/Library/Application Support/AgentBox/`, diretórios `0700`, arquivos `0600` (`audit/09 §2.3`; hoje `workspace.json` é `0644`, `audit/09 N3`):

```
db/agentbox.sqlite (+ -wal, -shm)
backups/        daily-YYYYMMDD.sqlite (7), pre-migration-<id>-<ts>.sqlite (5)
run/            app.sock, app.alive, spool/hooks/<runID>.jsonl, launch/<runID>/, paste/,
                ptyd-v1.sock (só modo degradado/testes; no LaunchAgent o caminho é do launchd, §0.1)
sessions/<ptySessionID>/   output.log (rotativo 2 × 8 MiB), meta.json   ← escrito pelo daemon
boxes/<computerID>/        token (0400), credencial do proxy configurado (0400, só para o egress)
logs/           app.log, agentboxd.log, cli.log (5 × 2 MiB cada)
legacy-import-<ts>/        cópia dos JSON importados
diagnostics/    pacotes exportados
```

Fora de `AB`: sessões limpas em `~/AgentBox/sessions/`, worktrees novas na raiz de §0.1 e dados de execução dos computadores em `~/AgentBox/runs/<session>/<computer>/` (`work/`, `logs/`, `transcript/`, `box.json`; escritos pelo egress e pelo app, nunca montados no container; 07 §2.8; R1 K-98).

Scrollback, logs e transcripts dos CLIs ficam **fora** do banco. Transcripts nunca são copiados, só referenciados (`audit/09 §2.3`).

### 3.2 Schema SQLite por migração

**AR-310 [P0 · v1] Convenções.** Tabelas `STRICT`. IDs `TEXT` com UUIDv7 (ordenáveis). Datas `INTEGER` em ms desde a época, UTC. Colunas JSON `TEXT` com `CHECK (json_valid(col))`. Dinheiro em `INTEGER` micro-dólares. `PRAGMA journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`, `busy_timeout=5000`.

**AR-311 [P0 · v1] Tabelas, por migração.** O `v1_initial` tem **só** as tabelas da Fatia 1, para que o agente da T-05 não congele decisões das fatias 2 e 3 (AR-320: migração publicada nunca é editada; R3 §11.6). Cada fatia seguinte entra como migração própria. Estados e enums seguem §0.4.

**`v1_initial` (Fatia 1: shell, terminais, sessões limpas, composer)**

| Tabela | Colunas |
|---|---|
| `project` | `id` PK, `name`, `kind` (`git`/`folder`), `root_path` UNIQUE, `git_remote_url`, `default_branch`, `worktree_root`, `branch_prefix`, `default_profile_id` FK NULL, `color`, `source` (`manual`/`orca_import`), `import_source_id` (id do repo no Orca, AC-111), `sort_index`, `created_at`, `archived_at` |
| `worktree` | `id` PK, `project_id` FK→project, `path` UNIQUE, `branch`, `base_ref`, `is_main` (0/1), `created_by_app` (0/1), `source`, `created_at`, `last_seen_at`, `archived_at` |
| `session` | `id` PK, `kind` (`worktree`/`checkout`/`folder`/`clean`), `project_id` FK NULL, `worktree_id` FK NULL, `folder_path`, `managed_folder` (0/1, pasta criada pelo app em `~/AgentBox/sessions`), `title`, `status_note`, `status_note_author`, `status_note_at`, `unread` (0/1), `last_viewed_at`, `lifecycle` (`active`/`archived`), `sort_index`, `pinned` (v1.1), `created_at`, `last_active_at`, `archived_at`. `CHECK ((kind IN ('worktree','checkout')) = (worktree_id IS NOT NULL) AND (kind = 'clean') = (project_id IS NULL))` (R1 K-81) |
| `tab` | `id` PK, `session_id` FK, `title`, `title_locked`, `sort_index`, `layout_json` (árvore de splits com `terminal_id` e proporções), `focused_terminal_id`, `created_at`, `closed_at` |
| `terminal` | `id` PK, `tab_id` FK, `provider` (`claude`/`codex`/`opencode`/`shell`/`custom`), `profile_id` FK NULL, `title`, `title_source` (`user`/`osc`/`auto`), `cwd`, `add_dirs_json`, `launch_spec_json` (o pedido), `resolved_argv_json` (segmentos, 06 §2.4.1), `env_keys_json` (só nomes), `cold_log` (0/1, opt-out por terminal), `pty_session_id`, `daemon_major`, `current_run_id` (id da execução atual; tabela `agent_run` chega em `v2_activity`), `native_conversation_id`, `state` (`not_started`/`launching`/`running`/`exited`/`killed`/`failed_to_start`/`interrupted`/`container_stopped`), `exit_code`, `exit_signal`, `last_message` (≤ 500 caracteres), `font_size`, `created_at`, `started_at`, `ended_at`, `deleted_at` |
| `launch_profile` | `id` PK, `name`, `provider`, `model`, `effort`, `permission_mode`, `add_dirs_json`, `extra_args_json`, `env_json` (sem segredo), `scope` (`global`/`project`), `project_id` FK NULL, `is_default`, `source`, `created_at`, `updated_at` |
| `setting` | `key` PK, `value_json`, `updated_at` |
| `ui_state` | `key` PK, `value_json`, `updated_at` (larguras, grupos recolhidos, frame da janela) |

**`v2_activity` (Fatia 2: hooks, atenção, GitHub, importação do Orca, catálogo, segredos)**

| Tabela | Colunas |
|---|---|
| `agent_run` | `id` PK, `terminal_id` FK NULL, `parent_run_id` FK NULL, `root_run_id`, `kind` (`main`/`native_subagent`/`teammate`/`app_worker_light`/`app_worker_isolated`), `harness`, `agent_type`, `provider_session_id`, `provider_agent_id`, `mode` (`light`/`isolated`/NULL), `batch_id` NULL (sem FK até `v4_batches`, R1 D-06), `status` (`starting`/`idle`/`working`/`needs_input`/`waiting_on_subagents`/`done`/`failed`/`blocked`/`interrupted`/`unknown`/`stalled`), `status_kind` (`question`/`permission`/`other`/NULL), `estimated` (0/1), `status_reason`, `subtitle` (última nota DOING), `started_at`, `last_event_at`, `ended_at` |
| `agent_event` | `run_id` FK, `seq`, `event_id` (id gerado pelo helper; UNIQUE por execução: idempotência entre socket e spool), `type`, `payload_json` (sanitizado, ≤ 16 KiB), `at` (ms), `at_ns` (ocorrência em ns, define a ordem do redutor com eventos fora de sequência). PK (`run_id`, `seq`). Retenção: 30 dias **e** 10 mil por execução. O estado de `agent_run` é projeção dos eventos reaplicados em ordem de `at_ns`; `type` também guarda os sintéticos `ProcessExit` e `PtyLost` (T2-01) |
| `attention` | `id` PK, `kind`, `priority` (1–3, 01 §5.12), `source_kind`, `source_id`, `reason`, `payload_json`, `created_at`, `seen_at`, `resolved_at` |
| `inbox_event` | `id` PK, `session_id` FK NULL, `kind`, `payload_json`, `created_at`, `read_at` |
| `catalog_item` | `id` PK, `source` (`claude`/`codex`/`agents`/`opencode`/`plugin`), `kind` (`agent`/`skill`/`plugin`/`mcp`/`instructions`), `path`, `name`, `description`, `content_hash`, `clients_json`, `discovered_at`, `missing_at` |
| `secret` | `id` PK, `name` UNIQUE, `default_env_name`, `ciphertext` BLOB, `nonce` BLOB, `key_version`, `note`, `created_at`, `updated_at`, `last_used_at` |
| `secret_binding` | `secret_id` FK, `target_kind` (`profile`/`session`/`computer`/`proxy`), `target_id`, `env_name`. PK composta |
| `import_run` | `id` PK, `source` (`agentbox_json`/`orca`/`agentbox_cli`), `source_path`, `source_fingerprint`, `dry_run`, `status`, `summary_json`, `started_at`, `finished_at` |
| `metric` | `id` PK, `name`, `value`, `unit`, `tags_json`, `at`. Retenção 30 dias |

**`v3_computers` (Fatia 3: computadores no modo leve)**

| Tabela | Colunas |
|---|---|
| `computer` | `id` PK, `owner_run_id` FK NULL, `session_id` FK NULL, `name`, `mode` (`light`/`isolated`), `display` (`http`/`headless`/`desktop`), `persistent`, `proxy_id` FK NULL, `browser_profile_id` FK NULL, `image_ref`, `image_digest`, `network_name`, `runtime_container_id`, `egress_container_id`, `work_container_id` (`work` na v1, `agent` na v1.1, conforme `mode`), `api_port`, `vnc_port`, `egress_admin_port`, `generation`, `state` (`queued`/`provisioning`/`ready`/`in_use`/`stopped`/`failed`/`removing`/`removed`/`orphan`), `created_at`, `last_used_at`, `expires_at`, `removed_at` |
| `computer_queue` | `id` PK, `computer_id` FK, `position`, `requested_at`, `reason` (fila persistente de 07 CS-131) |
| `browser_profile` | `id` PK, `name`, `volume`, `sites_json`, `locked_by_computer_id` FK NULL, `created_at`, `last_used_at` |
| `help_request` | campos de 01 §5.10: `id` PK, `computer_id` FK, `run_id` FK NULL, `kind` (`captcha`/`login`/`mfa`/`download`/`choice`/`permission`/`other`), `reason`, `state` (`open`/`taken_over`/`resolved`/`declined`/`cancelled`/`expired`), `created_at`, `resolved_at` |
| `proxy` | Proxy genérico configurado pelo usuário (P13): `id` PK, `name`, `preset` (`custom`/`zyte`), `scheme` (`http`/`https`/`socks5`), `host`, `port`, `username`, `secret_id` FK NULL (senha ou chave no Vault), `geo` NULL, `api_mode` (0/1; modo API/render quando o provedor suporta), `is_default`, `created_at`, `updated_at`. **Sem colunas de limite ou orçamento** |
| `proxy_usage` | `proxy_id` FK, `computer_id` FK NULL, `period_start`, `requests`, `bytes`, `cost_micros` NULL (só quando o provedor informa), `updated_at`. PK (`proxy_id`, `computer_id`, `period_start`). Só exibição; nada corta por valor |

Diário, comandos e requests dos computadores **não** vão para o banco: ficam nos arquivos append-only de `logs/` do run folder (07 CS-149), indexados sob demanda.

**Migrações posteriores**: `v4_batches` (v1.1, lote como entidade, R1 D-06: tabela `batch` e FK de `agent_run.batch_id`), `v5_legacy_runs` (v1.1, P15: `legacy_run` com `id`, `path`, `name`, `created_at`, `result_path`, `journal_path`, `imported_at`).

Índices mínimos (cada um na migração da sua tabela): `worktree(project_id)`, `session(project_id, archived_at)`, `tab(session_id)`, `terminal(tab_id)`, `terminal(pty_session_id)`, `agent_run(parent_run_id)`, `agent_run(terminal_id)`, `agent_run(status)`, `attention(resolved_at)`, `computer(state)`, `metric(name, at)`.

**AR-312 [P0 · v1] Acesso.** Um `DatabasePool` em `AgentBoxStore`. Escritas só por métodos do Store (`async`, fora do main). A UI observa com `ValueObservation` entregue no MainActor; nenhuma `View` grava. Estado transitório de layout (arrastar divisor, redimensionar sidebar) fica em memória e é gravado no fim do gesto ou com debounce de 300 ms (`audit/07 item 55`; `audit/09 N3`).

### 3.3 Migrações

**AR-320 [P0 · v1]** `DatabaseMigrator` com migrações nomeadas (`v1_initial`, `v2_<assunto>` …). Migração publicada nunca é editada. `eraseDatabaseOnSchemaChange` só em testes.

**AR-321 [P0 · v1]** Antes de aplicar qualquer migração pendente, backup com `VACUUM INTO backups/pre-migration-<id>-<ts>.sqlite` (mantém os 5 mais novos). Migração falhou: rollback da transação, banco intocado, banner com "Open Diagnostics".

**AR-322 [P0 · v1]** Banco de versão mais nova (identificador de migração desconhecido, por exemplo após rollback do app): o app abre **somente leitura**, mostra banner "Database was created by a newer Agent Box" e oferece abrir o backup pré-migração correspondente. Nunca apaga.

**AR-323 [P0 · v1]** Todo teste de migração parte de um banco fixture da versão anterior com dados e confere o resultado (`StoreTests/Migrations`).

### 3.4 Backup e recuperação de corrupção

**AR-330 [P0 · v1] Backup diário.** No primeiro boot do dia e a cada 24 h com o app aberto: `VACUUM INTO backups/daily-YYYYMMDD.sqlite`, fora do main, mantendo 7.

**AR-331 [P0 · v1] Corrupção nunca desabilita a UI (`00 T2`).** No boot, `PRAGMA quick_check` (antes da primeira consulta da UI). Falhou:
1. move `agentbox.sqlite*` para `db/corrupt-<ts>/`;
2. restaura o backup mais novo que passa em `integrity_check`;
3. se não houver backup válido, cria banco vazio e oferece reimportar (JSON atual, Orca);
4. mostra banner não bloqueante com o que foi perdido (data do backup) e "Reveal Corrupt File".

Erro `SQLITE_CORRUPT`/`SQLITE_NOTADB` em tempo de execução: o app entra em modo somente leitura com o estado em memória, mostra banner e repete o fluxo acima no próximo boot. Terminais e o daemon não são afetados.
- Aceite: teste que corrompe bytes do arquivo e confere que o app abre com banner e o backup restaurado; XCUITest equivalente com `AGENTBOX_TEST_CORRUPT_DB=1`.

**AR-332 [P1 · v1]** "Export database" e "Restore from backup…" em Settings › Advanced, com confirmação.

### 3.5 Importadores

**AR-340 [P0 · v1] Regras comuns.** Todo importador tem dry-run (mostra contagens e conflitos antes de gravar), é idempotente (`source_fingerprint`), lê **cópias** dos arquivos de origem (copiados para `legacy-import-<ts>/` antes do parse), nunca escreve na origem e registra `import_run`. Parse tolerante: campo desconhecido é ignorado e contado no resumo.

**AR-341 [P0 · v1] JSON do Agent Box atual.**

| Arquivo | Destino |
|---|---|
| `workspace.json` | `session` (`kind=clean` se o cwd não for repo git; senão `project` + `worktree` + `session`), `tab`, `terminal` (estado `interrupted`, com [Resume] quando houver ID nativo), `layout_json` |
| `library.json` | Agentes salvos → `launch_profile` quando mapeáveis; skills → `catalog_item` por referência ao caminho de origem se ainda existir. Memórias **não** entram no banco (`00 T14`): são exportadas para `legacy-import-<ts>/memories.md` e o resumo aponta o arquivo |
| `AgentRuns.json` | `agent_run` encerradas (histórico; roda depois de `v2_activity`), status final `unknown` para as que estavam `running` |
| `computer-policy.json`, `docker-connection.json` | `setting` |
| `browser-computers.json` | `computer` com `state=orphan` para o GC oferecer limpeza (containers, volumes e itens antigos do Keychain `com.agentbox.browser-token.v1`) |
| `secrets.json`, `secret-references.json` | `secret`, com leitura do Keychain antigo **por segredo e sob confirmação** (cada leitura pode pedir senha) |
| `ControlBroker.json`, `human-requests.json`, `agent-launch-bindings.json`, `scraping-box-assignments.json`, `directory-bookmarks.json`, `image-update.json`, dados de Capture | Ignorados (copiados para `legacy-import-<ts>/`, não importados) |

**AR-342 [P0 · v1] Orca (P3).** Fonte: cópia só leitura de `~/Library/Application Support/orca/profiles/<perfil>/profile-state.db` (+ `-wal`, `-shm`), com `orca-data.json` como fallback (06 §6.1; R1 K-96; verificado com Orca 1.4.219). Entra na Fatia 2 e os worktrees em `~/orca/workspaces/<repo>/<nome>`. Mapeia repositórios → `project`, worktrees ativos → `worktree` + `session`, `agentDefaultArgs` → `launch_profile` padrão por provider, e as preferências de terminal e aparência que o capítulo de UI adotar (fonte, tema, scrollback). O parser é versionado pela versão do Orca e testado com fixture anonimizada. Worktree cujo caminho não existe mais é ignorado e listado.
- Aceite: com o Orca do dono (contagens do dia do teste; em 2026-10-16, 7 repositórios e 111 worktrees, 06 §6.1), o dry-run mostra as contagens certas e a importação não altera nenhum arquivo do Orca (conferido por hash antes/depois).

**AR-343 [P1 · v1.1] CLI `agentbox` antigo (P15: runs importados na v1.1).** `~/orca/projects/agentbox/runs/*` → `legacy_run` (migração `v5_legacy_runs`) só por referência (`result.json`, diário). A chave Zyte do `.env` vira um `proxy` com preset `zyte` e `secret` no Vault, só com confirmação (P13; `audit/10` R1.4).

---

## 4. Concorrência (Swift 6 estrito)

**AR-401 [P0 · v1]** Modo de linguagem Swift 6 em todos os alvos desde o primeiro commit; warnings como erro no CI (`00 T3`; hoje `swiftLanguageModes: [.v5]`, `audit/02 §1`).

**AR-402 [P0 · v1] Isolamento padrão.** `AgentBoxUI`, `AgentBoxDesignSystem` e o app: `defaultIsolation(MainActor.self)` (SE-0466). Demais alvos: isolamento padrão `nonisolated`, com a feature `NonisolatedNonsendingByDefault` ligada, para que funções `async` não isoladas rodem no executor de quem chama.

**AR-403 [P0 · v1] Serviços são actors; dados são valores.** Cada serviço do Core é `actor` (ou `final class` `Sendable` imutável). DTOs e snapshots são `struct` `Sendable`. A UI recebe snapshots imutáveis; nenhum objeto mutável do Core atravessa para a UI.

**AR-404 [P0 · v1] Nada bloqueante no pool cooperativo.** O pool tem cerca de uma thread por núcleo; bloqueá-lo para o app inteiro (`audit/09 N4`). Regras:
- Espera de processo, leitura de pipe, socket bloqueante, `SecItem*` (pode esperar um prompt do Keychain), leitura de arquivo grande (> 1 MiB) e varredura de diretórios grandes (catálogo, transcripts) rodam no `BlockingIOExecutor` (`TaskExecutor` sobre uma fila/threads dedicadas, usado com `withTaskExecutorPreference`) ou numa API async real (`DispatchIO`, Network.framework).
- Proibidos em contexto async: semáforos, `sleep`, locks segurados durante I/O (AR-131). Espera usa `Task.sleep(for:)`, `AsyncStream`, `withTaskCancellationHandler`.
- Aceite: teste de stress que dispara 20 `boxes_reserve`/`box_claim` em paralelo contra um `FakeDockerClient` lento (2 s cada) e mede que um `await` trivial no MainActor responde em < 50 ms durante todo o teste.

**AR-405 [P0 · v1] Regras do MainActor.**
- Trabalho permitido no main: aplicar snapshots, layout, desenho, alimentar terminais visíveis dentro do orçamento (AR-406).
- Proibido no main: I/O de disco ou rede, `Process`, JSON acima de 64 KiB, ordenação ou filtro de listas com mais de 500 itens (fica no Core).
- Modelos `@Observable` por linha da sidebar e por pane, para que um badge não invalide o terminal (`audit/06 §3.4 regra 4`).
- Watchdog em builds de desenvolvimento: um ping do main a cada 250 ms; atraso > 500 ms registra `hang` com signpost (AR-604).

**AR-406 [P0 · v1] Alimentação dos terminais.** O `PTYClient` (actor) demultiplexa os frames do daemon e entrega a cada pane visível por fila própria. A view recebe os bytes no main, coalescidos por quadro (`CADisplayLink` da view): no máximo 256 KiB por pane por quadro e 4 ms de `feed` somados por quadro para todos os panes. O excedente fica na fila; backlog acima de 4 MiB descarta a fila e pede snapshot (`resyncRequired`). Panes ocultos não recebem bytes (AR-102). Esse backlog de 4 MiB é do app e não se confunde com a fila de 2 MiB por cliente no daemon (§0.3). Parse fora do main fica para o spike S-02: a 1.20.0 alimenta no main com este orçamento; a 1.99/2.x promete parse e Metal fora do main, mas só entra com medição e decisão escrita na AR-122.

**AR-407 [P0 · v1] Fila de computadores.** `actor ComputerScheduler` com fila FIFO e limite de concorrência derivado da memória da VM Docker. A fórmula de custo e admissão é a de 07 (CS-130/CS-132), dono do assunto; este requisito fixa só a mecânica. Chamadas paralelas **esperam** na fila e recebem status de progresso; nunca falham com `transitionInProgress` (`audit/02 #8`; `audit/09 §2.4`).

**AR-408 [P0 · v1] Cancelamento.** Toda chamada MCP, `ctl` e operação Docker carrega uma `Task` cancelável com prazo. O timeout do agente cancela a operação; o que já foi criado no Docker é reconciliado pelos eventos (`audit/09 N19`).

**AR-409 [P0 · v1] Daemon.** `agentboxd` usa GCD por sessão (fila serial + `DispatchSource` de leitura do master), sem pool cooperativo no caminho de dados. O registro de sessões é um actor. O daemon segue o modo Swift 6 estrito como os outros alvos.

---

## 5. Segurança

### 5.1 Modelo de ameaça

**AR-501 [P0 · v1] O modelo abaixo é publicado no README e em Settings › Advanced › "Security model" (linha com link para o texto; R1 K-55), e substitui as promessas de "caller autenticado" e "lease exclusivo" do código atual (`audit/09 N2`; `audit/08 §1.6`).**

Ativos: arquivos do usuário; credenciais (login do Claude/Codex no Mac, token do `gh`, credenciais de proxy, segredos do usuário, token `setup-token` na v1.1); clipboard do Mac; a capacidade de **digitar em qualquer terminal** (inclusive Claude com `--dangerously-skip-permissions`); tokens das boxes; integridade do uso do proxy e dos logs de evidência; o Docker do usuário.

| Ator | Confiável? | Fronteira real | O que o app promete |
|---|---|---|---|
| Usuário | Sim | — | — |
| Agente no Mac (modo leve) | **Tanto quanto o usuário**: tem shell, arquivos e o socket Docker | Só o modo de permissão do próprio CLI | Nenhum isolamento do agente. O container isola **o navegador**, não o agente |
| Agente no container (modo isolado, v1.1) | Não | Container sem socket Docker, sem `$HOME`, uid distinto, rede `internal`, egress filtrado | Escopo e destino limitados. Sem gateway, o agente consegue usar e ler a credencial de modelo da box (declarado na UI) |
| Página web no navegador da box | Não | Container + egress | Sem acesso à LAN, ao host nem a metadados |
| Saída de programas no terminal (logs, páginas raspadas, `cat`) | Não | Emulador | Não lê clipboard, não executa nada, não dispara ação sem clique |
| Outro processo do mesmo uid | Igual ao usuário | Nenhuma | Defesa em profundidade só onde é barata (assinatura no socket do daemon) |
| Supply chain (dependências, imagem, CLIs) | Parcial | Versões exatas e digests | Builds reproduzíveis e auditáveis |

**AR-502 [P0 · v1] Ameaças e mitigações obrigatórias.**

| # | Ameaça | Mitigação |
|---|---|---|
| A1 | Programa lê o clipboard por OSC 52 (`audit/07 item 1`) | Nunca responder à consulta, nem na UI nem no daemon (AR-520) |
| A2 | Escrita no clipboard por OSC 52 sem o usuário perceber | Toggle em Settings › Terminal (padrão ligado, como na config do dono) + toast `"<title>" copied to the clipboard.` (02 §3, 03 §9.4) |
| A3 | Escape de bracketed paste (texto colado com `ESC[201~`) injeta comando | Remover `ESC` e caracteres de controle C0/C1 (exceto `\t`, `\n`) do conteúdo colado ou arrastado antes de enviar |
| A4 | Caminho arrastado com metacaracteres vira comando | Escape de shell no caminho; imagem colada vira arquivo `0600` em `run/paste/` com limpeza em 24 h (`audit/07 item 5`) |
| A5 | Link no terminal abre esquema perigoso | Só ⌘-clique abre; `http`/`https` direto; `file:` e outros esquemas pedem confirmação; nunca executar arquivo |
| A6 | Notificação forjada por OSC 9/777 ou BEL | Notificações vindas da saída do terminal são rotuladas com o pane de origem e nunca aprovam nada |
| A7 | Título forjado (OSC 0/2) imita outro pane | Título de OSC aparece como secundário quando o usuário fixou um título; sem caracteres de controle nem bidi |
| A8 | Processo local injeta teclas pelo socket do daemon | `0600` + `getpeereid` + requisito de assinatura do peer (AR-503) |
| A9 | Token da box em `docker inspect` (`audit/09 N1`) | Token por arquivo montado só leitura; nunca em env (AR-512) |
| A10 | SSRF a partir da box (`audit/09 N8`) | Rede `internal` + egress que bloqueia RFC1918, link-local, `host.docker.internal`, metadados e portas de outras boxes, para navegador e HTTP |
| A11 | Agente apaga ou forja uso de proxy e logs (`audit/08` N9) | Contagem de uso, listener e credencial do proxy só no egress; logs append-only no run folder do host, sem montagem no container (07 CS-149) |
| A12 | Container isolado escapa ou alcança o Mac | Sem `/var/run/docker.sock`, sem `$HOME`, `--cap-drop ALL`, `no-new-privileges`, `--read-only` com tmpfs, `--pids-limit`, usuário não-root, seccomp padrão |
| A13 | Segredo vaza em log, diagnóstico, argv ou `meta.json` | Redação na escrita do log (AR-602), env só com nomes no disco, segredo nunca em argv |
| A14 | Credencial do Mac copiada para N containers (corrida de refresh, `audit/08 §1.2`) | Proibido copiar Keychain do Claude, `~/.codex/auth.json` ou token do `gh` (`00 P7`) |
| A15 | Dependência ou imagem adulterada | Versões exatas, `Package.resolved` versionado, base e imagem por digest, noVNC com hash, CLIs fixados na imagem |
| A16 | Teclas do Mac capturadas pelo viewer (⌘Q, ⌘W indo para a box; `audit/07 item 40`) | Atalhos do app têm prioridade; indicador de "keyboard captured" com tecla de escape (detalhe no capítulo de UI) |

**AR-503 [P0 · v1] Autenticação dos sockets locais.**
- `ptyd-v1.sock`: `0600` (launchd), `getpeereid` == uid do usuário e requisito de assinatura via `LOCAL_PEERTOKEN` + `SecCodeCopyGuestWithAttributes` aceitando **só o app** (`identifier "app.agentbox.mac"` + certificado folha da identidade local). O helper `agentbox` não fala com o daemon.
- `app.sock`: `0600`, `getpeereid`. Os serviços `mcp` e `hook` aceitam qualquer processo do usuário (são chamados por CLIs de agentes) e só oferecem as operações desses serviços. O serviço `ctl` exige a opção ligada (AR-806).
- Registro honesto: um agente no Mac pode chamar o helper assinado. A assinatura no socket do daemon impede processos arbitrários de injetar teclas; não é fronteira contra o agente no Mac, que já é tratado como o usuário (AR-501).

### 5.2 Keychain e segredos

**AR-510 [P0 · v1] Item único no Keychain.** Uma chave mestra de 256 bits aleatória, num único item `kSecClassGenericPassword` (serviço `app.agentbox.vault`, conta `master-v1`), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, não sincronizável. A ACL é a padrão do criador, ou seja, o designated requirement do app. Com assinatura estável (AR-530), "Always Allow" vale para sempre.
- Nada de item por box, por segredo ou por token (`audit/09 §2.5`). Nada de API `SecKeychain*` deprecada (`LegacyKeychainInteraction` é descartado).
- O Data Protection Keychain exigiria `keychain-access-groups` com Team ID, que o certificado local não tem; por isso o item fica no keychain de login com ACL.
- O daemon e o helper **não** acessam o Keychain.

**AR-511 [P0 · v1] Segredos do usuário cifrados no banco.** Valores em `secret.ciphertext` com AES-GCM (CryptoKit) usando uma chave derivada da mestra (HKDF, `info="secret-v1"`). Rotação: `key_version`. Leitura do Keychain uma vez por boot, no `BlockingIOExecutor` (AR-404), e a chave fica só em memória.

**AR-512 [P0 · v1] Tokens das boxes fora de env.** Token da box = `HMAC-SHA256(chaveMestra, "box|" + computerID + "|" + generation)`. Entregue por arquivo `boxes/<id>/token` (`0400`) bind-montado só leitura em `/run/agentbox/token` com o uid do runtime. `docker inspect` mostra o caminho, não o valor. A credencial do proxy configurado pelo usuário (P13) vai do mesmo jeito, só para o egress. Decisão de entrega por arquivo (não por stdin em tmpfs) fechada por R1 K-77 + P16; 07 segue. Variáveis `AB_*` não existem mais no ambiente de Xvfb, Openbox ou xdotool (`audit/09 N18`).
- Aceite: `docker inspect` de todos os containers da box e `env` dentro do `box-runtime` não contêm nenhum token (teste Docker gated).

**AR-513 [P0 · v1] Segredos injetados nos terminais.**
- Só por opt-in explícito: `secret_binding` num perfil de lançamento ou numa sessão.
- O app resolve os valores no momento do `create` e os envia ao daemon na requisição; o daemon mantém o env em memória e grava só os **nomes** em `meta.json`. O banco guarda só os nomes (`terminal.env_keys_json`).
- O pane mostra "env: N secrets" com a lista de nomes.
- Segredo nunca vai em argv (visível em `ps`) nem em arquivo de `--settings`.
- Na v1.1, o token `setup-token` do Claude para o modo isolado segue `00 P7`: guardado no Vault, entregue por arquivo só leitura na box, nunca copiado do Keychain do Claude no Mac.

### 5.3 Terminal

**AR-520 [P0 · v1] OSC 52 de leitura: nunca (`00 T6`).** A UI usa só `TerminalView` com delegate próprio que devolve `nil` em `clipboardRead`; `LocalProcessTerminalView` é proibido (devolve o pasteboard, `MacLocalTerminalView.swift:122`; lint AR-131). O terminal headless do daemon idem. Teste de unidade: alimentar `ESC ] 52 ; c ; ? BEL` e conferir que nada é escrito no PTY (espelha o teste "never answers a clipboard query" do Orca).

**AR-521 [P0 · v1]** As mitigações A2–A7 da AR-502 são requisitos do `TerminalSurface`, com teste de unidade cada uma em `TerminalCoreTests`.

**AR-522 [P1 · v1]** BEL não toca som (`bellStyle = .none`) e vira estado "não lido"; OSC 777/9;4 alimentam estado do pane (detalhe no capítulo de terminal; `audit/07 item 11`).

### 5.4 Assinatura, TCC e entitlements

**AR-530 [P0 · v1] Identidade de assinatura estável (`00 T4`).** Certificado de assinatura de código autoassinado "Agent Box Local Signing", criado uma vez por `scripts/make-signing-cert.sh` no keychain de login e marcado como confiável para assinatura de código. Designated requirement fixo: `identifier "<id>" and certificate leaf = H"<sha1 do certificado>"`. Mesma identidade para app, `agentboxd` e `agentbox`. Corrige a perda de ACL do Keychain, os prompts repetidos de TCC e a instabilidade das notificações a cada build (`audit/09 N6`).
- Se um dia houver Developer ID, a troca é só de identidade (e reconcessão única das permissões).

**AR-531 [P0 · v1] Hardened runtime ligado; sem App Sandbox.** O sandbox é incompatível com PTY, CLIs arbitrários e socket Docker (`audit/09 §2.7`). Assinar de dentro para fora (`agentbox`, `agentboxd`, depois o app), **sem `--deep`**, com `--options runtime`.

**AR-532 [P0 · v1] Entitlements.** Nenhum entitlement especial no app, no daemon nem no helper. Todo código é linkado estaticamente (SPM), então a validação de biblioteca do hardened runtime não exige `disable-library-validation`. Se uma dependência futura exigir framework dinâmico, a exceção é registrada aqui com o motivo.

**AR-533 [P0 · v1] TCC.** `AssociatedBundleIdentifiers` no plist do daemon faz o System Settings atribuir o `agentboxd` ao Agent Box. Processos lançados pelo daemon têm o daemon como processo responsável, então os prompts de pastas protegidas (Documentos, Mesa, Downloads) aparecem para ele: o `agentboxd` leva um `Info.plist` embutido (`-sectcreate __TEXT __info_plist`) com as `NS*UsageDescription` em inglês. Security-scoped bookmarks não são usados (`audit/09 §5 item 9`).
- Aceite: depois de conceder Documentos uma vez, reinstalar o app com `install.sh` não pede de novo.

**AR-534 [P1 · v1]** Gravação de tela: necessária só para `ctl screenshot` de janelas com camadas Metal (AR-806). O app pede na primeira vez que o `ctl` precisar, nunca no onboarding comum.

### 5.5 Hooks sem python3

**AR-540 [P0 · v1]** Os hooks são o binário Swift `agentbox hook`, dentro do bundle. Nenhum hook, script de lançamento ou helper depende de `python3`, `node` ou `jq` do host (`audit/09 N15`). Num Mac sem Command Line Tools, lançar um Claude no app não abre o instalador do Xcode.
- Aceite: teste que roda o lançamento com `PATH=/usr/bin:/bin` e um `python3` falso que falha, e confere que os eventos chegam.

---

## 6. Observabilidade

**AR-601 [P0 · v1] Logger por categoria.** `Logger(subsystem:category:)` em todo módulo. Categorias:

| Subsystem | Categorias |
|---|---|
| `app.agentbox` | `lifecycle`, `ui`, `store`, `migration`, `import`, `pty-client`, `launch`, `hooks`, `mcp`, `ctl`, `computers`, `docker`, `egress`, `git`, `catalog`, `secrets`, `notifications`, `perf` |
| `app.agentbox.ptyd` | `lifecycle`, `protocol`, `session`, `restore`, `perf` |
| `app.agentbox.cli` | `mcp`, `hook`, `ctl` |

Caminhos, argv, URLs e IDs de conversa usam `privacy: .private`; segredos nunca são registrados, nem como privados.

**AR-602 [P0 · v1] Log em disco.** Além do `os_log`, cada processo grava JSONL rotativo em `logs/` (5 × 2 MiB), porque `OSLogStore` no app só lê o próprio processo. A redação acontece **antes** de gravar: padrões de token (`sk-ant-`, `sk-`, `ghp_`, `github_pat_`, `gho_`, `Bearer …`, credenciais de proxy (incl. chave Zyte), `user:pass@` em URLs de proxy) viram `‹redacted›`, e `/Users/<nome>` vira `~`. Teste de unidade com cada padrão.

**AR-603 [P0 · v1] Pacote de diagnóstico.** Settings › Diagnostics › "Export Diagnostics…" gera um `.zip` em `diagnostics/` com: logs dos três processos; versões (app, build, protocolo do daemon, schema, imagem da box, `claude`/`codex`/`opencode`/`gh`/`git`/`docker`); `docker info` resumido (runtime, memória, CPUs, arquitetura); contagens por tabela (sem conteúdo); configurações sem segredos; tabela `metric` dos últimos 7 dias; relatórios de crash recentes (AR-604); estado das sessões do daemon (IDs, tamanhos, idade). Antes de salvar, mostra a lista de arquivos. Nada sai da máquina.

**AR-604 [P0 · v1] Detecção de crash e hang.**
- Sentinela `run/app.alive` (pid, build, início) criada no boot e apagada na saída limpa. No boot seguinte, sentinela presente com pid morto = encerramento inesperado. O app procura `~/Library/Logs/DiagnosticReports/{AgentBox,agentboxd,agentbox}-*.ips` mais novos que a sentinela e mostra banner "Agent Box quit unexpectedly" com "View report" e "Add to diagnostics".
- Crash do daemon: detectado pela queda da conexão e pela mudança de `pid`/`startedAt` no `helloAck`; os terminais afetados viram `interrupted` com cold restore (AR-104).
- `MXMetricManager` (MetricKit) para diagnósticos de hang e crash entregues pelo sistema, gravados em `logs/`.
- Watchdog do main (AR-405) em builds de desenvolvimento.

**AR-605 [P1 · v1] Signposts e métricas locais.** `OSSignposter` em: boot até a primeira janela, attach de sessão, primeiro byte do terminal, lançamento de agente (pedido → processo → primeiro output), `boxes_reserve` → `ready` (fila → container → saudável), primeiro quadro do viewer, migração, importação, backup. Os mesmos pontos gravam duração na tabela `metric`. A tela Diagnostics mostra p50/p95 dos últimos 7 dias.

---

## 7. Performance

Máquina de referência: a do dono (Apple Silicon, 48 GiB, 14 CPUs, macOS 27; `audit/08 §0`). Os orçamentos valem em build Release, com Metal ligado, e são medidos pelos benchmarks da AR-720.

**AR-701 [P0 · v1] Abertura.**

| Cenário | Meta p50 | Meta p95 |
|---|---|---|
| Frio (daemon parado, 20 terminais salvos) até janela interativa com sidebar | 400 ms | 800 ms |
| Reabrir após ⌘Q (daemon vivo) até panes visíveis com scrollback restaurado | 300 ms | 600 ms |
| Primeiro conteúdo de um pane após mostrá-lo (snapshot + attach) | 80 ms | 150 ms |
| Abrir o app em modo `.accessory` → janela (AR-108) | 150 ms | 300 ms |

O boot não espera Docker, git, catálogo nem CLIs: tudo isso chega depois, em segundo plano.

**AR-702 [P0 · v1] Latência de input.** Tecla → glifo na tela, com o hop do daemon: p95 ≤ 16 ms em repouso; p95 ≤ 33 ms com 4 panes visíveis despejando saída (`yes`, `cat` de 50 MB). Overhead do daemon (receber input → escrever no PTY; ler PTY → frame no socket): p99 ≤ 2 ms.

**AR-703 [P0 · v1] Vazão sem travar.** `cat` de 50 MB num pane não causa hitch > 100 ms no main e não atrasa o input dos outros panes além da AR-702. O daemon agrupa saída em ≤ 16 ms ou 64 KiB por frame (`audit/09 §2.8`).

**AR-704 [P0 · v1] Memória.**

| Item | Meta |
|---|---|
| Sessão no daemon com 5 mil linhas de scrollback (padrão do dono; máx. 50 mil configurável) | ≤ 25 MB |
| Sessão no daemon com 50 mil linhas | ≤ 80 MB |
| View de terminal viva no app (Metal) | ≤ 30 MB |
| App com 20 terminais (4 visíveis + K=4 views em cache) e 15 boxes na sidebar | ≤ 600 MB RSS |
| App em modo `.accessory` | ≤ 120 MB RSS |
| Daemon com 20 sessões | ≤ 600 MB RSS |

Só existem views para panes visíveis e os últimos K=4 usados; os demais vivem só no daemon (`audit/09 §2.8`).

**AR-705 [P0 · v1] CPU em repouso.** 20 terminais ociosos, nenhuma animação visível: app ≤ 1 % e daemon ≤ 0,5 % de um núcleo (média de 60 s). Indicadores animados usam Core Animation limitado a 24–30 fps (`audit/06 §3.4 regra 2`).

**AR-706 [P0 · v1] Carga real: 20 terminais + 15 boxes.** Cenário de aceite (`audit/08 N2`, `audit/10 R6.3`): 20 terminais (6 com TUI ativa de agente), 15 boxes headless e 2 desktop rodando, 6 miniaturas visíveis. Metas: sidebar rola a 120 Hz sem hitch; input dentro da AR-702; app ≤ 800 MB; nenhuma operação de UI espera Docker. `boxes_reserve` → `ready` com imagem local: p95 ≤ 5 s (headless) e ≤ 10 s (desktop); primeiro quadro do viewer ≤ 1,5 s. Miniaturas fora da tela param de atualizar.

**AR-707 [P0 · v1] Helper e hooks.** `agentbox hook` do exec à saída: p95 ≤ 30 ms (é chamado em todo `PreToolUse`). `agentbox mcp` primeira resposta a `initialize`: ≤ 100 ms com o app aberto.

**AR-708 [P0 · v1] Renderer Metal.** `setUseMetal(true)` em toda view de terminal, com fallback para CoreGraphics registrado em log se falhar (`00 T6`; `audit/09 §2.8`). O renderer fica atrás de `protocol TerminalRenderer` para permitir troca futura sem refazer a UI; libghostty não é avaliada na v1.

**AR-709 [P0 · v1] PTY fora do main thread.** O app nunca lê PTY: o daemon lê, e o app recebe frames num actor fora do main (AR-406). Nenhum `LocalProcess` com `DispatchQueue.main` (`audit/09 N14`).

**AR-710 [P0 · v1] Resize.** Um `TIOCSWINSZ` por transição animada, no início (04 R2; ao fechar painel, no fim), e no arrasto no máximo 1 por quadro mais o final ao soltar (04 M-202) (R1 K-93). Durante transições de layout, o terminal não é redimensionado quadro a quadro (`audit/06 §3.4 regra 1`). Teste: uma transição gera exatamente um `resize` no protocolo.

**AR-711 [P0 · v1] Persistência fora do main, com debounce.** Escritas no banco são `async` no Store; layout grava no fim do gesto ou com debounce de 300 ms; eventos de hooks são gravados em lote (até 50 ms ou 100 eventos por transação). Meta: transação de escrita p99 ≤ 10 ms; nenhuma escrita no main.

**AR-720 [P0 · v1] Benchmarks reproduzíveis.** `scripts/bench.sh` roda os cenários AR-701 a AR-707 com `xctrace` (templates Time Profiler, Animation Hitches, Allocations) e com os signposts da AR-605, e grava JSON em `docs/evidence/bench/<data>-<sha>.json`. Roda no Mac do dono antes de cada release e em toda PR que toque terminal, daemon, sidebar ou motion.

---

## 8. Qualidade e testes

### 8.1 Pirâmide

**AR-801 [P0 · v1]** Swift Testing (`@Test`) para tudo, exceto XCUITest (XCTest).

| Camada | O que prova | Ferramenta | Onde roda | Meta |
|---|---|---|---|---|
| Unidade | Layout puro, adapters de CLI (argv por perfil e provider), parsers (sessões Claude/Codex/OpenCode com fixtures reais anonimizadas, `orca-data.json`, JSON atual), redação de logs, política OSC/paste, Vault com chave em memória, mutações | Swift Testing | CI macOS | Core, Store, Protocol e TerminalCore com ≥ 80 % de linhas |
| Store | Migrações v(n-1) → v(n) com dados, corrupção → restauração, backup, `ValueObservation` | Swift Testing + arquivos reais | CI macOS | Toda migração tem teste |
| Protocolo do daemon | `agentboxd` real com socket temporário: create → output → **matar o cliente** → attach → snapshot igual; seq sem buracos; `resyncRequired`; cliente N-1; fuzz do framing; respostas a consultas só por um emulador (AR-105); OSC 52 nunca respondido | Swift Testing + processo real | CI macOS | — |
| PTY real | Sinais, grupos, exit codes, env do `create`, `$SHELL` | Swift Testing + scripts fixture | CI macOS | — |
| Runtime e egress | API do runtime, lease, VNC, bloqueio de SSRF, proxy configurável e contagem de uso, listener | `unittest` + Docker | CI Linux | — |
| Integração Docker real | Criar, saúde, VNC, parar, remover, GC, eventos, rede `internal` bloqueando RFC1918, token fora de `inspect` | Swift Testing gated por `AGENTBOX_DOCKER_CONTEXT` (sem contexto fixo; imagem construída no setup; recursos rotulados por execução e removidos no teardown) | Mac do dono | — |
| Contrato dos CLIs | `claude` com `--settings` gera hooks que chegam; `codex -c mcp_servers…` enxerga as ferramentas; `--resume` repassa flags; `mcpServers` inline por subagente | Gated por `AGENTBOX_REAL_CLI=1`, modelo barato, teto de US$ 0,50 por execução | Mac do dono, antes de release e quando a versão do CLI muda | — |
| UI (XCUITest) | Fluxos P0 (AR-803) | XCUITest no projeto gerado | CI macOS (com `AGENTBOX_FAKE_RUNTIME=1`) e Mac do dono (Docker real) | Todos os fluxos P0 |
| Snapshot | Componentes do design system e estados (linha da sidebar em cada estado do agente, tab, badge, banners, erros, vazios), tema escuro (único na v1, DS13), Reduce Motion | swift-snapshot-testing em `NSHostingView`, tamanho e fonte fixos | Mac do dono (referências no SO dele); CI só se houver referências para o SO do runner | Todo componente do DesignSystem, com referência **aprovada pelo dono** ao lado do crop do Orca (snapshot sem aprovação não fecha tarefa; R3 §5.3) |
| Motion | Durações e curvas vêm do enum `Motion`; com Reduce Motion nenhuma `Animation` não nula é aplicada; uma transição = um resize de PTY | Swift Testing + signposts; `xctrace` manual | CI (tokens e Reduce Motion), Mac do dono (hitches) | — |

**AR-802 [P0 · v1] Testes não dependem do ambiente do autor.** Nada de contexto Docker, imagem ou caminho fixo (`audit/02 §5`). Fixtures de CLI são anonimizadas e versionadas com a versão do CLI de origem. Testes gated pulam com mensagem clara quando a variável não está definida.

**AR-803 [P0 · v1] Fluxos P0 em XCUITest.**
1. Primeira abertura → importar do Orca (fixture) → projetos na sidebar.
2. Criar sessão de worktree → terminal já rodando o agente (P9) → split → nova tab.
3. "New Clean Session" (P10/P11) em um clique.
4. ⌘Q com sessão viva → menu bar → reabrir → mesmo processo, scrollback restaurado.
5. Subagente leve pede computador (`box_claim`) → computador aparece → viewer → Take Over → Hand Back (com runtime falso no CI, real no Mac do dono).
6. Banco corrompido → app abre com banner e backup restaurado.
7. Teste de varredura: percorre a árvore de acessibilidade de cada tela principal e falha se um controle interativo não tiver `accessibilityIdentifier`.
8. Para cada `ActionID` do registro, **um** XCUITest com clique real (`click()`) ou atalho real, que declara o efeito esperado (estado, navegação ou erro **específico**; "algum erro visível" não conta). `ctl ui action` fica para jornadas longas (R3 §7.2–7.3).

Ordem: os fluxos 1 (importação do Orca) e 5 (computadores) são das fatias 2 e 3; na Fatia 1 valem 2, 3, 4 (sem LaunchAgent até a T-24), 6, 7 e 8.

### 8.2 Automação do app por agentes

**AR-805 [P0 · v1] `accessibilityIdentifier` em todo controle e contêiner (`00 T13`).** Esquema hierárquico estável, com IDs de domínio e nunca índices de posição. A convenção é a de 02 §17 e a **lista única é 03 §22** (04, 05 e este capítulo citam, não inventam; R1 §4). Exemplos: `sidebar.project.<id>`, `sidebar.session.<id>`, `sidebar.session.<id>.status`, `tabs.tab.<terminalId>`, `tabs.tab.<terminalId>.close`, `pane.<terminalId>`, `pane.<terminalId>.status`, `overlay.<nome>`, `overlay.<nome>.submit`, `viewer.<computerId>`, `viewer.<computerId>.takeOver` / `.handBack` (verbos Take Over / Hand Back, R1 D-02 + P16), `settings.<seção>.<controle>`. O enum `A11yID` vive em `AgentBoxProtocol/Automation/` (§0.5), é gerado da lista de 03 §22 e gera `docs/automation-ids.md`. O teste de varredura da AR-803 item 7 garante a cobertura.
- **Todo controle passa pelo registro.** `scripts/lint-ui.sh` falha em `Button(`, `.onTapGesture`, `NSButton`/`NSMenuItem` cuja ação não seja `ActionRegistry.perform(.<id>)` (R3 §7.1). Assim toda interação tem um `ActionID`, o registro é a fonte do índice de ações e o teste de cobertura confere registro × XCUITest (AR-803 item 8).
- **Controle de fatia futura não é renderizado** (feature flag por fatia), em vez de aparecer desabilitado (R3 §5.6). Desabilitado só por pré-condição real, sempre com tooltip do motivo (AC-T02).

**AR-806 [P0 · v1] `agentbox ctl`.** Serviço `ctl` do `app.sock` (AR-106). **Desligado por padrão**; liga em Settings › Advanced › "Automation channel (agentbox ctl)" (03 §14.2; R1 K-55) ou ao lançar com `AGENTBOX_AUTOMATION=1` (testes). Enquanto ligado, a faixa da titlebar mostra "Automation on". Sobe na **T-02** (Fatia 1, logo depois do esqueleto) com o mínimo `state`, `ui tree`, `ui action`, `ui wait`, `screenshot`, `record`; os comandos de terminal entram com o daemon (T-06). Toda chamada vai para o log `ctl`. Saída sempre em JSON.

| Comando | Efeito |
|---|---|
| `ctl state` | JSON do modelo: projetos, sessões, tabs, terminais (estado, pid, provider), execuções, computadores, atenção |
| `ctl session open --project <id>|--clean [--name]` | Cria sessão; devolve IDs |
| `ctl terminal new --session <id> --provider shell|claude|codex [--profile] [--cwd]` | Abre terminal |
| `ctl terminal send <id> <texto>` | Envia bytes (`\n` explícito) |
| `ctl terminal screen <id> [--scrollback N]` | Texto da tela vindo do emulador headless do daemon (via app) |
| `ctl terminal wait <id> --text <regex> [--timeout]` | Espera texto na tela |
| `ctl ui tree [--root <a11yID>]` | Árvore de identificadores, rótulos, valores e estados |
| `ctl ui action <a11yID> [press|focus|select|set <valor>]` | Executa a ação **pelo view model** (registro de ações por identificador, via `ActionDispatching`, AR-134), não por evento sintético. Foco é `ui action <id> focus` (não existe `ctl ui focus`) |
| `ctl ui wait <a11yID> [--state]` | Espera um elemento aparecer ou mudar de estado |
| `ctl screenshot --window|--element <a11yID> --out <arquivo.png>` | Captura via ScreenCaptureKit da janela do próprio app (exige Gravação de Tela, AR-534; fidelidade com camadas Metal: spike S-07); `--element` recorta pelo frame do identificador |
| `ctl app quit [--completely]` / `ctl app launch` | Ciclo de vida: `quit` = Keep Running (app vai a `.accessory`, PTYs vivos); `--completely` = Quit Agent Box Completely. Não existe `--keep`. O `launch` usa `open -b app.agentbox.mac` |
| `ctl daemon status` / `ctl daemon kill` | Diagnóstico (inclui `inputBytesByOrigin` por sessão, usado pelos ACs de "zero bytes escritos pelo app"); `kill` só com `AGENTBOX_AUTOMATION=1` (testes de cold restore) |
| `ctl record start|stop --out <arquivo.mov>` (P1) | Gravação da janela para comparação de motion com o Orca |

**AR-808 [P0 · v1] Referência visual do Orca e comparação mecânica (P14).** O gate visual por tela usa o pacote versionado `docs/rebuild/reference/orca-1.4.219/` (F0-3): PNGs @2x, janela 1440×900, tema escuro, com os fixtures de 05 §0.3, e um `manifest.json` ligando cada PNG ao ID de tela do 03 e ao `A11yID` equivalente. Os arquivos do renderer do Orca são extraídos do `app.asar` instalado por `scripts/extract-orca-reference.sh`, nunca de scratchpad. `scripts/compare-ui.sh <tela>` tira `ctl screenshot` do Agent Box no mesmo tamanho e fixtures e grava lado a lado + diff de sobreposição (50% e diferença absoluta) em `docs/evidence/ui/<tarefa>/`. Toda tarefa visual só fecha com esse lado a lado e **OK explícito do dono** (P14).

**AR-809 [P1 · v1] `LayoutConformanceTests`.** Medidas de geometria lidas de `ctl ui tree` (frames por `A11yID`) contra as tabelas de 02/03 e o checklist de `audit/04 §8`: tab row 32, sidebar 280, semáforos em x 16/36/56 e y 18, linha de agente 24, raio do card 10 etc. Falha no CI. Cada tarefa de UI cobre as medidas que tocou (R3 §5.2).

**AR-807 [P0 · v1] Runtime falso.** `AGENTBOX_FAKE_RUNTIME=1` troca o `DockerClient` por um fake determinístico que simula criação, saúde, eventos e um viewer com imagem estática. Usado no CI e em XCUITest sem Docker.

### 8.3 E2E

**AR-810 [P0 · v1] `scripts/e2e.sh`.** Usa `ctl` + Docker real + CLIs reais (modelo barato), num repositório temporário:
1. `scripts/build.sh` e instala num diretório temporário (não em `/Applications`) com dados em `AGENTBOX_HOME` temporário.
2. Cria projeto; abre shell e Claude.
3. `ctl app quit` (Keep Running), `ctl app launch`; confere o mesmo PID e o buffer restaurado.
4. Pede ao Claude um subagente leve que chama `box_claim`; confere container, rede `internal`, VNC e um quadro.
5. Take Over e Hand Back.
6. `SubagentStop` remove a box e o volume (efêmera).
7. `ctl daemon kill`; confere o banner "Background agents stopped unexpectedly", o estado `interrupted` e [Resume].
8. Confere que nenhum token aparece em `docker inspect` nem nos logs.

Cada passo grava evidência (JSON, telas, trechos de log) em `docs/evidence/e2e/<data>-<sha>/`. Custo de modelo ≤ US$ 0,50 por execução. `AGENTBOX_HOME` existe só para testes e isola banco, sockets (com caminho curto, por causa do limite de 104 bytes de `sun_path`) e o label do daemon (`app.agentbox.ptyd.test-<n>`).

### 8.4 CI

**AR-815 [P0 · v1] O que roda onde.**

| Onde | O quê | Gatilho |
|---|---|---|
| GitHub Actions, runner `macos-15` (mínimo declarado, T3) | Build Release + testes de unidade, Store e protocolo (lane de compatibilidade; R3 §11.11) | Toda PR |
| GitHub Actions, runner macOS (o mais novo disponível) | `bootstrap` + `gen` + `xcodebuild` Release com Swift 6 e warnings como erro; `lint.sh`; testes de unidade, Store, protocolo do daemon e PTY; XCUITest com runtime falso; snapshot só se houver referências para o SO do runner | Toda PR e push em `main` |
| GitHub Actions, `ubuntu-24.04-arm` | Testes do runtime e do egress; build das imagens arm64; testes Docker do runtime; em `main`, publica `ghcr.io/gabrielgreco1/agentbox-box` e `-egress` por digest e grava o digest num manifesto versionado | Toda PR que toque `runtime/`; push em `main` |
| Mac do dono | `scripts/e2e.sh`, integração Swift ↔ Docker real, contrato dos CLIs, snapshots canônicos, `scripts/bench.sh`, assinatura e `install.sh` | Gate antes de merge de PR que toque daemon, terminal, computadores ou launch; sempre antes de release |

Runners macOS do GitHub não rodam Docker (sem virtualização aninhada; `audit/09 §3`). Um runner self-hosted no Mac do dono é P2.

**Peer auth no CI** (S-03): o runner não tem a identidade "Agent Box Local Signing". Plano: cada job cria um certificado efêmero num keychain temporário (`security create-keychain` + `make-signing-cert.sh --ephemeral`), assina app, daemon e testes com ele, e o daemon de teste é compilado com o DR desse certificado. Plano B, se o S-03 reprovar: em builds `DEBUG` com flag de **compilação** (nunca variável de ambiente), o daemon aceita peers por `getpeereid` + Team ID ad-hoc; Release nunca tem esse caminho.

### 8.5 Definition of Done por tarefa

**AR-820 [P0 · v1]** Uma tarefa só fecha quando (vale a partir da T-02; a T-01, esqueleto, está isenta dos itens 3, 4 e 5, porque o `ctl` ainda não existe; R3 §4.2):
1. Compila em Swift 6 estrito sem warnings; `lint.sh` e `lint-ui.sh` passam.
2. Tem testes na camada certa da pirâmide (lógica nova sem teste de unidade não entra; mudança de schema vem com teste de migração).
3. Todo controle novo tem `accessibilityIdentifier`, `ActionID` no registro (AR-134) e **um XCUITest com clique ou atalho real** com efeito declarado (AR-803 item 8); o teste de varredura passa.
4. **Evidência visual comparada com o Orca (P14):** para mudança de UI, `scripts/compare-ui.sh` (AR-808) com screenshots no tema escuro (via `ctl screenshot`) lado a lado com o PNG de referência do Orca, diff de sobreposição e `LayoutConformanceTests` das medidas tocadas (AR-809); para motion, gravação (`ctl record`) lado a lado, conforme 04. Anexados na PR e em `docs/evidence/ui/<tarefa>/`. Divergência intencional é explicada. **A tarefa só fecha com OK explícito do dono** sobre essa evidência.
5. Snapshot de componente novo com referência aprovada pelo dono; Reduce Motion e tamanho mínimo de janela conferidos.
6. Logs nas categorias certas, sem segredo (conferido pelo teste de redação).
7. Sem regressão de orçamento de desempenho (AR-720) quando toca terminal, daemon, sidebar ou motion.
8. Fluxos P0 afetados passam no XCUITest; `e2e.sh` passa no Mac do dono quando a tarefa toca daemon, launch ou computadores.
9. Lista do que a tarefa **não** fez; capítulo da spec atualizado se o comportamento mudou.

### 8.6 QA com permissão de Acessibilidade

**AR-825 [P0 · v1] Checklist da máquina de QA** (`scripts/qa-preflight.sh` confere e explica o que falta):
- Acessibilidade concedida ao runner de teste (Xcode/`xcodebuild`, para XCUITest) e ao terminal ou agente que fizer QA exploratório via Acessibilidade (o bloqueio de `audit/03 §0` era `AXIsProcessTrusted() == false`).
- Gravação de Tela concedida ao Agent Box (para `ctl screenshot`).
- Docker rodando no contexto de teste; imagem presente ou baixável.
- CLIs `claude` e `codex` logados.
- Itens de QA manual que só humano ou Acessibilidade fecham: Esc em overlays, foco do terminal após fechar overlay, ⌘W/⌘Q com viewer focado, Shift+Enter no Claude e no Codex (`audit/07 itens 9 e 14`; `audit/07 correção 13`).

---

## 9. Build, assinatura, instalação e versões

**AR-901 [P0 · v1] Scripts.**

| Script | Faz |
|---|---|
| `scripts/bootstrap.sh` | Confere Xcode 26.x e `rg`; baixa e confere XcodeGen 2.46.0 por SHA-256 (AR-120) e as demais versões de `scripts/tool-versions.txt` (Geist); falha com versão errada; cria o certificado local se faltar (`make-signing-cert.sh`) |
| `scripts/make-signing-cert.sh` | Cria a identidade "Agent Box Local Signing" no keychain de login, marca confiança para assinatura de código e imprime o SHA-1 usado no designated requirement |
| `scripts/gen.sh` | `xcodegen generate` |
| `scripts/build.sh` | `gen` + `xcodebuild` Release; embute `agentboxd` e `agentbox` em `Contents/MacOS`, o plist em `Contents/Library/LaunchAgents`; assina de dentro para fora com `--options runtime`; `codesign --verify --strict` e confere o designated requirement esperado |
| `scripts/install.sh` | Ver AR-902 |
| `scripts/lint.sh`, `scripts/lint-ui.sh`, `scripts/bench.sh`, `scripts/e2e.sh`, `scripts/qa-preflight.sh`, `scripts/compare-ui.sh`, `scripts/extract-orca-reference.sh`, `scripts/gen-tokens.py` | Seções 1.5, 7 e 8; tokens em §0.5 |
| `scripts/build-images.sh` | Build local das imagens `box`/`egress` (fallback do GHCR) com tag pelo hash do contexto |

**AR-902 [P0 · v1] `install.sh`.**
1. Roda `build.sh`.
2. Se o app estiver aberto, pede `ctl app quit --completely` (ou `osascript quit`) e espera; **nunca** mata o daemon.
3. Guarda a versão instalada em `~/Library/Application Support/AgentBox/previous/Agent Box.app`.
4. Copia o novo bundle para um temporário em `/Applications` e troca por `rename` atômico.
5. Abre o app; no primeiro boot, o app registra o LaunchAgent com `SMAppService` se não estiver registrado.
6. `install.sh --rollback` restaura a versão anterior.

Sem Sparkle e sem notarização enquanto não houver distribuição (`00 T4`).

**AR-903 [P0 · v1] Versões independentes e visíveis.**

| Versão | Formato | Onde aparece |
|---|---|---|
| App | SemVer `0.x.y` até a v1, depois `1.x.y`; `CFBundleVersion` = número de commits em `main` | About, Diagnostics |
| Protocolo do daemon | `major.minor` | `helloAck`, Diagnostics |
| Schema do banco | Último identificador de migração | Diagnostics |
| Imagens | `ctx-<sha12>` do contexto + digest | Diagnostics, tela de computadores |
| Ferramentas MCP e payload de hook | Inteiro em `AgentBoxProtocol` | Handshake do `app.sock` |

**AR-904 [P0 · v1] Upgrade do daemon.**
- O binário do daemon vive no bundle. Trocar o bundle não afeta o daemon em execução (o processo continua com o binário já carregado); a próxima subida usa o binário novo.
- **Mesmo major:** o app novo conecta no daemon antigo e negocia `minor`/capabilities. Se o daemon for mais velho que o mínimo suportado, o app mostra "Restart background service to update" (R1 K-46) e só reinicia por ação do usuário ou quando não houver sessões vivas (`drain`).
- **Major novo:** label, plist e variável de socket novos (`app.agentbox.ptyd.v2`, `AGENTBOX_PTYD_SOCK_V2`). Sessões novas vão para o v2; as antigas continuam no v1 até terminarem. O app fala N e N-1 e mostra "<n> terminals on previous background service". O bundle carrega o binário e o plist do major anterior por um ciclo de major, e o app só chama `unregister` do v1 quando ele não tem sessões.
- Aceite: teste de protocolo com cliente N contra daemon N-1 e o inverso.

**AR-905 [P1 · v1] Imagens.** O app conhece o digest esperado de cada imagem (manifesto gerado no CI e embutido no bundle). Na falta, oferece "Download (GHCR)" ou "Build locally (≈ 2 min)" com progresso (`docker build --progress=rawjson`). Nunca instala Docker sozinho (`audit/09 §2.5`).

---

## 10. Ordem de implementação técnica

A ordem segue as fatias de 01 §4 e a decomposição de R3 §10; a granularidade de tarefa (T-01…T-25) é a de R3 §10, que este capítulo adota. Três regras corrigem a versão anterior (R3 §4.2, §11.9):

- **Registro de ações, `A11yID` e `ctl` mínimo sobem para o começo** (T-02), antes de qualquer tarefa visual. Sem isso nenhuma tarefa cumpre a DoD (AR-820).
- **Design system e motion entram na ordem** (T-03 tokens e fontes, T-11/T-12 componentes, motion mínimo da Fatia 1 dentro de cada tarefa).
- **A Fatia 1 roda com o daemon filho do app** (modo degradado, mesmo protocolo); LaunchAgent e sobrevivência ao ⌘Q são a última tarefa da fatia, depois do S-01.

| # | Etapa | Entrega (tarefas de R3 §10) | Critério de saída |
|---|---|---|---|
| F0 | Fatia 0: fechamento | Errata e esta tabela §0 aplicadas nos capítulos; pacote de referência do Orca (AR-808); tabela de ações da Fatia 1; spikes S-01…S-08 (§11); `legacy/` (AR-202); versões fixadas (XcodeGen, SwiftTerm, GRDB, Geist) | Nenhum nome de §0 divergente nos capítulos; relatórios dos spikes em `docs/evidence/spikes/`; `bootstrap.sh` falha com versão errada |
| 0 | Esqueleto (T-01) | `project.yml`, `Packages/AgentBoxKit` com os alvos da AR-121 vazios, Swift 6, `defaultIsolation`, `lint.sh`, `bootstrap`/`gen`/`build`/`install`, certificado local, `LogFacade`, CI macOS (incl. `macos-15`) e Linux | App vazio assinado instala e abre; `codesign` confere o DR; CI verde com lint. DoD itens 3–5 isentos |
| 1 | Automação mínima e base visual (T-02, T-03) | `ActionRegistry` + `ActionDispatching` (AR-134), `A11yID`, `app.sock` só com `ctl`, `ctl state/ui tree/ui action/ui wait/screenshot/record`, varredura, `lint-ui.sh`; tokens gerados, Geist com `OFL.txt` | `ctl ui tree` lista a janela vazia; `ctl screenshot` gera PNG fiel (S-07); o lint falha num `Button` solto de teste; teste de paridade de tokens |
| 2 | Protocolo, domínio e Store da Fatia 1 (T-04, T-05, T-08) | `AgentBoxProtocol` com fixtures; tipos de domínio; `v1_initial` só com as tabelas da Fatia 1 (AR-311), backup, corrupção; env de login | Fixtures encode/decode; migração de banco vazio; corrupção abre com banner; AC-312 com o shell do dono |
| 3 | Daemon e terminal (T-06, T-07, T-09) | `agentboxd` como filho do app (ring, corte, preâmbulo, origem do input, AR-105), peer auth (S-03), `TerminalSurface` com `TerminalView` + delegate próprio, Metal, orçamento AR-406 | Matar o cliente e reanexar devolve a mesma tela (S-04); OSC 52 de leitura nunca respondido; AR-702/703 com 4 panes |
| 4 | Shell da janela e componentes (T-10…T-14) | Janela e chrome, overlays e componentes base, sidebar, tabs e panes | `LayoutConformanceTests`; lado a lado aprovado pelo dono (P14); um resize por transição |
| 5 | Lançamento e sessões (T-15…T-23) | Adapters sem injeções, fluxo de lançamento e estados do pane, sessões limpas, Git mínimo, projetos, composer, Quick Launch, menus e atalhos, reabertura sem LaunchAgent | AC-307 por segmentos (06 §2.4.1) com zero bytes do app no PTY; XCUI de cada `ActionID`; AR-803 fluxos 2, 3, 6, 7, 8 |
| 6 | LaunchAgent e ⌘Q (T-24, T-25) | `SMAppService` com o socket do S-01, ⌘Q Keep Running, `MenuBarExtra`, reattach, cold restore | `e2e.sh` passos 1–3 e 7: mesmo PID após quit/launch; AR-803 fluxo 4; relatório da Fatia 1 |
| 7 | Fatia 2: atividade e integrações | `v2_activity`, `agentbox hook` + spool, injeções por lançamento, estratégia do Codex (06 §3.3.1, S-05), atenção, notificações, Inbox, GitHub, catálogo, Vault e segredos, importador do Orca e do JSON atual, onboarding completo, Conversations | Contrato dos CLIs verde; hooks chegam com o app fechado; `PATH` sem python3; nenhuma escrita em `~/.claude` ou `~/.codex`; AR-803 fluxo 1 |
| 8 | Fatia 3: computadores (modo leve) | `v3_computers`, `AgentBoxDocker` (Engine API, exec hijacked), imagens por digest, rede `internal` + `egress`, proxy genérico (P13), token por arquivo, `ComputerScheduler`, noVNC, `agentbox mcp`, ferramentas de 07, motion "computador em uso" | `e2e.sh` completo; AR-706 medido; nenhum token em `inspect`; AR-803 fluxo 5 |
| 9 | Observabilidade e endurecimento | Signposts, `metric`, Diagnostics, pacote exportável, crash; benchmarks completos, snapshots aprovados, revisão do modelo de ameaça | Todos os AR P0 · v1 verificados; release `1.0.0` |
| 10 | v1.1 (modo isolado) | Imagem `agentbox-agent`, container `agent` com `dtach`, sessões `docker exec` no daemon, hooks HTTP e MCP via egress (AR-113), credenciais conforme `00 P7`, `v4_batches`, `v5_legacy_runs`, worktree montado no mesmo caminho absoluto (`audit/09 N16`) | Aceite de `audit/08 §1.7` |

As fatias 2 e 3 podem andar em paralelo depois da etapa 6, desde que o `app.sock` esteja estável. Dependências entre tarefas: grafo de R3 §10 (sem ciclos depois que o `ctl` sobe para a T-02).

---

## 11. Spikes e verificações

Lista consolidada de todo item "(verificar)", spike e pergunta aberta da spec (R3 §6). Cada linha tem dono (quem executa / quem decide), fatia em que bloqueia e critério de saída. Evidência em `docs/evidence/spikes/<id>/` (spikes) ou `docs/evidence/` (contratos de CLI, com `AGENTBOX_REAL_CLI=1`). O resultado de cada um é escrito de volta no capítulo dono.

### 11.1 Spikes (antes ou no início da Fatia 1, salvo indicação)

| # | Spike | Bloqueia | Dono | Critério de saída | Plano B |
|---|---|---|---|---|---|
| S-01 | `SMAppService.agent` com `Sockets/SecureSocketWithKey` (`AGENTBOX_PTYD_SOCK_V1`), `launch_activate_socket`, `launchctl getenv` após `register()`, aprovação de login item, label de teste com `AGENTBOX_HOME` | T1, P4, T-24 | Agente executa; dono aprova o login item | App assinado registra; o launchd cria o socket; `getenv` devolve o caminho; `nc -U` acorda o daemon. Evidência: log e `launchctl print` | Daemon com `RunAtLoad=false` + `launchctl kickstart`, `bind` próprio em `AB/run/ptyd-v1.sock` (exceção a T1 vai ao 00); a Fatia 1 já roda no modo degradado |
| S-02 | SwiftTerm 1.20.0 × 1.99.0: Metal, `feed` fora do main, `send` de outra thread, busca, OSC 133/7, latência com 4 panes e `yes \| head -c 200M` | T6, AR-406, AR-702, T-09 | Agente | Medição nos dois; decisão de versão escrita na AR-122 | Ficar na 1.20.0 com feed no main e orçamento AR-406 |
| S-03 | Peer auth (`LOCAL_PEERTOKEN` + `SecCodeCheckValidity`) com o certificado local em dev, runner do XCUITest e CI | T-07, testes de protocolo no CI | Agente | Peer aceito e recusado; receita de CI com certificado efêmero (§8.4) | `getpeereid` + Team ID ad-hoc só em `DEBUG` por flag de compilação |
| S-04 | Reattach: replay do ring desde o ponto de corte, preâmbulo de modos e redraw `cols-1`, com Claude, Codex (alt-screen) e `vim` | P4, TA-105, T-06 | Agente | `textSnapshot` antes e depois iguais em 20 repetições; vídeo | Serializador de células (later) |
| S-05 | Hooks por lançamento: (a) Claude `--settings` soma com os hooks do Orca (V1); (b) Codex `-c hooks…`: trust exigido? hash estável? (V6); (c) Codex app-server daemon × `--no-daemon` (V12) | T10, Fatia 2 (define o adapter já na Fatia 1) | Agente executa; **dono decide D-Codex-1** (aceitar trust gravado pelo próprio Codex) | Payloads gravados como fixtures; decisão escrita em 06 §3.3.1 e §2.2 | Codex por tail do rollout, `estimated` (baseline) |
| S-06 | Captura do env de login (`-l -i -c` com marcador em PTY oculto) com o zsh do dono (p10k/oh-my-zsh) | TA-110, AC-312, T-08 | Agente no Mac do dono | Captura < 1 s, sem lixo; `which claude node gh` resolve | `-l -c` com timeout |
| S-07 | `ctl screenshot` via ScreenCaptureKit da própria janela com camadas Metal (com e sem Gravação de Tela) | Toda evidência visual (P14), T-02 | Agente; dono concede a permissão | PNG fiel do terminal Metal | `CGWindowListCreateImage` (deprecado) ou snapshot do `CAMetalLayer` pelo app |
| S-08 | 07 S1 antecipado para a Fatia 0: `mcpServers` inline por subagente e `agent_id` nos hooks na 2.1.302 | Modelo de identidade do modo leve (AR-111) | Agente | Fixture com dois filhos distinguíveis | Revisão do modelo de identidade em 07 antes da Fatia 3 |

Os demais spikes de 07 (S2 porta e DNS em rede `internal` no Docker Desktop, OrbStack e Colima; S3 noVNC em WKWebView ≥ 20 fps; S4 `deny` de `Skill(agentbox)`; S5; S6 API de uso do provedor de proxy) ficam na Fatia 3, com dono e critério em 07 §9.

### 11.2 Verificações de contrato dos CLIs (06 §7)

| Item | Onde | Fatia | Se falhar |
|---|---|---|---|
| V1 hooks de `--settings` somam com os do usuário e trazem `session_id`, `source`, `last_assistant_message`, `notification_type` | 06 §2.2, §3.3 | 2 | Última mensagem pelo transcript |
| V2 nome da ferramenta de pergunta (`AskUserQuestion`?) | 06 §3.3 | 2 | Só `PermissionRequest`/`Notification` |
| V3 `permissions.deny: ["Skill(agentbox)"]` vale com `--dangerously-skip-permissions` | 06 §2.9 | 2 | "Disable Globally…" recomendado |
| V4 `--plugin-dir` segue symlink; `-c` para caminhos de skills do Codex | 06 §4.2 | 2 | Cópia por lançamento |
| V5 `--resume` com flags regeneradas restaura skills e MCP (bloqueia TA-209) | 06 §2.6 | 2 | — |
| V6 Codex hooks e `mcp_servers` por `-c`, trust, campos de `SessionStart`/`Stop` | 06 §3.3.1 | 2 | Rollout `estimated` |
| V7 `opencode session list --format json` (diretório, data) | 06 §2.5 | 2 | ID manual |
| V8 `claude --resume` depois de mover a pasta | 06 §2.7 | v1.1 | Bloquear "Move Folder" |
| V9 bracketed paste sem Enter no Claude e no Codex | 06 §5.7 | 2 | Só clipboard |
| V10 `gh run view --log-failed --job <databaseId>` | 06 §5.7 | v1.1 | Log do run filtrado |
| V11 env do zsh (= S-06) | 06 §1.7 | 1 | `-l -c` |
| V12 Codex app-server daemon (= S-05(c)) | 06 §2.2 | 2 | `--no-daemon` padrão |
| V13 `claude agents --json`; `statusLine` com `rate_limits.five_hour/seven_day` (AC-1001); `notification_type` = `permission_prompt`/`idle_prompt`; timeout de hook 5 s; `-n/--name` como título; `--session-id` + `/clear` | 06 §2.6, §2.8, §3.3 | 2 | Recurso desabilitado com motivo |
| Codex `SessionStart.session_id`; `last_assistant_message` no `Stop` do Codex; payloads exatos | 06 §2.5, §3.3, §3.4 | 2 | Rollout |
| `~/.agents/skills` lido pelo Claude; pasta de agentes do OpenCode; `OPENCODE_CONFIG`; agentes do Codex por `-c`; precedência no Codex | 06 §4.1, §4.2, §4.4, TA-220 | 2 / later | Mensagem honesta na UI |

### 11.3 Marcadores de 07 (dono: 07; Fatia 3)

Publicação de porta só pelo `egress`; memória "a medir com o lote de 15"; custo por unidade do proxy configurado e se há API de uso (S6; P13: só exibição); `mcpServers` inline e `agent_id` (= S-08); filhos do Codex por hooks; modo de permissão padrão na box; uid 10004 e virtiofs no Colima e OrbStack; `codex login --device-auth` em container auxiliar; gateway de credenciais; hooks `type:"http"`; mensagens pai ↔ filho isolado (P12 já decide o "com Enter"); `deny` de `Skill(agentbox)` (= V3).

### 11.4 Perguntas abertas de outros capítulos (para o dono do capítulo fechar)

| Capítulo | Pergunta | Dono |
|---|---|---|
| 08 | Imagem do runtime no GHCR pública ou privada (recomendação: pública, não contém segredo) | Dono |
| 08 | ScreenCaptureKit sem Gravação de Tela (= S-07) | Agente |
| 06 | D-Codex-1: aceitar o trust de hooks gravado pelo próprio Codex após clique do usuário (§3.3.1) | **Dono** |
| 01 | `stalled` "há N minutos" (10 min proposto); `stale` "além da janela" (fundido em `unknown`); detecção de "o CLI não deixa desligar item global" | 01 |
| 04 | Blur do scrim (desligado na v1); dono do `ui-kit.css`; entrada `LAYOUT` do render; aprovação de tokens `"draft": true`; aprovação do dono por momento | 04 |
| 03 | `Stop` de subagente "se o harness suportar"; grupos de split por arrasto (v1.1); zoom da UI fora do terminal (later, desabilitado com motivo); detectar "shell ocioso" ao fechar | 03 |
| 00 | P7 (credenciais do modo isolado) fecha na abertura da v1.1 | Dono |
| 05 | Metas de desempenho iniciais (08 AR-7xx prevalece); microcopy final vem do 03 | 05 |

Itens de 01 §8 que esta revisão considera fechados por P15/P16: raiz de worktree, "Computer" na UI, sessões importadas sem processo, helper da barra de menus (não existe; §0.1), diálogo do primeiro ⌘Q, nome `quiet-harbor`. A importação da chave Zyte agora é "proxy com preset Zyte, com confirmação" (P13).
