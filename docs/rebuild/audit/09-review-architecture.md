# 09 · Revisão da rodada 1: arquitetura, confiabilidade, segurança, performance e engenharia

Data: 2026-10-16 · Worktree `otter`, commit `c4418cc` · Revisor da segunda rodada.
Lidos por inteiro: `02-core-audit.md` e `05-core-features-gaps.md`. Lidos por seção: 01 (1.U, 1.Z, 1.AB, §4), 03 (§3), 04 (índice), 06 (§3.4). As afirmações centrais foram conferidas no código (`Sources/`, `runtime/`, `scripts/`, `.build/checkouts/SwiftTerm`) e no daemon do Orca (`orca-src/src/main/daemon`, só leitura). Referências no formato `arquivo:linha`. Nada foi alterado no código.

Ambiente conferido: Swift 6.2.4, Xcode 26.3, macOS 27.0.1, arm64. Contextos Docker: `default` e `desktop-linux` (ativo). Não há `~/.colima` nem `~/.orbstack`.

---

## 0. Resumo

1. A rodada 1 acertou o diagnóstico funcional, mas deixou de fora o **modelo de ameaça**. Hoje toda a cerimônia de segurança (Keychain, HMAC, capability, lease com epoch) é contornável por qualquer processo do usuário com acesso ao Docker, **inclusive os próprios agentes no Mac**. O token de cada box vai para `Config.Env` do container e aparece em `docker inspect` (N1, N2).
2. Há **três riscos de confiabilidade sérios que ninguém citou**: (a) JSON corrompido trava a UI inteira, sem recuperação (N3); (b) chamadas bloqueantes dentro de `Task.detached` podem esgotar o pool cooperativo do Swift e travar todo o trabalho assíncrono do app (N4); (c) o app não tem **nenhum log**, nem `os_log` nem `print` (N5).
3. **Correção técnica importante**: o SwiftTerm 1.20 já traz renderer **Metal** (`setUseMetal`), `HeadlessTerminal`, OSC 133, teclado Kitty e busca. A rodada 1 tratou o SwiftTerm como "sem GPU" e sugeriu libghostty. A troca de emulador não se justifica. O daemon de PTY pode usar o `HeadlessTerminal` do próprio SwiftTerm.
4. **Arquitetura-alvo**: um daemon `rackyd` (LaunchAgent via `SMAppService`, com **ativação por socket do launchd**) dono dos PTYs, com emulador headless e log bruto em disco. O app vira cliente. Estado em SQLite (GRDB 7) com migrações e backup. Core em actors com Swift 6 estrito. Docker via Engine API (eventos em vez de polling) para leitura e CLI para build/pull. Rede por box `internal` com sidecar de egress (proxy, listener e bloqueio de SSRF ao mesmo tempo). Viewer via noVNC em `WKWebView`.
5. Os **dois modos de subagente** decididos pelo dono cabem numa única abstração: "sessão = PTY cujo argv é local ou `docker exec -it`". O modo isolado tem duas dependências que a rodada 1 não viu: credenciais do CLI dentro do container (conflita com a regra U9) e worktrees git montados (o arquivo `.git` aponta para caminho absoluto do host) (N16, N17).
6. **Testes ponta a ponta exigem mudança de empacotamento**: um pacote SPM puro não hospeda XCUITest, e o app tem **zero** `accessibilityIdentifier`. Runners macOS do GitHub não rodam Docker (sem virtualização aninhada), então a integração com Docker real precisa ser gate local ou self-hosted.

---

## 1. Achados novos

Severidade: **Crítica** bloqueia o produto ou causa perda de dados; **Alta** quebra garantia central; **Média** degrada confiabilidade ou segurança; **Baixa** é higiene.

| # | Sev. | Achado | Evidência |
|---|---|---|---|
| N1 | Alta | **O token da box vaza via `docker inspect`.** O token é passado por `--env-file` e vira `Config.Env` do container, visível para qualquer processo com acesso ao socket Docker. Com ele dá para falar direto com `127.0.0.1:<porta>` e ignorar MCP, provenance, lease e Keychain. As ≈ 250 linhas de Keychain com contorno de API legada (`KeychainReadGate`, `LegacyKeychainInteraction`) protegem um segredo que já está exposto. | `BrowserComputerService.swift:376-377,703`; `server.py:168` |
| N2 | Alta | **Os agentes no Mac têm o socket Docker.** Claude/Codex com Bash podem rodar `docker exec` em qualquer box, `docker run -v ~/...` e `docker inspect`. No modo leve, o container isola **o navegador do Mac**, mas não isola o agente. Os comentários e a SPEC prometem mais que isso (lease "exclusivo", caller "autenticado"). Falta um modelo de ameaça escrito. | `TerminalRuntimeManager.swift:353-368` (PATH inclui `/usr/local/bin`); `ComputerCallProvenance.swift` |
| N3 | Alta | **JSON corrompido trava a UI.** Falha ao decodificar `workspace.json` desabilita a janela inteira (`.disabled(loadError != nil)`), sem botão de restaurar, sem backup e sem "começar do zero". Além disso, cada mudança do snapshot grava o JSON **de forma síncrona no main thread**, inclusive **a cada frame** ao arrastar o divisor da sidebar ou dos splits. O arquivo fica `0644`. | `WorkspaceView.swift:143-150,181,192-196,653-654,956-959`; `ls -la` em `~/Library/Application Support/Racky` |
| N4 | Alta | **O pool cooperativo pode ser esgotado.** Operações Docker síncronas (semáforo de até 120 s, `NSRecursiveLock` global) rodam dentro de `Task.detached`, que usa threads do pool cooperativo (cerca de 1 por núcleo). Com vários subagentes chamando `computer_acquire` em paralelo, as threads ficam presas esperando o lock global e **todo `await` do app para**, incluindo UI assíncrona, MCP e hooks. | `AgentComputerAccess.swift:492-514`; `BrowserComputerStore.swift:83-117,198,239,268,315,354,425`; `DockerComputerService.swift:3`; `DockerProcessRunner.swift:62,72` |
| N5 | Média | **Não há observabilidade.** Zero ocorrências de `Logger`, `os_log`, `OSLog`, `NSLog` ou `print` em `Sources/`. Não há signposts, MetricKit nem detecção de crash anterior. Falhas reais (Keychain, Docker, hooks) não deixam rastro. Isso impede diagnosticar "não funciona" na máquina do dono. | `grep` vazio |
| N6 | Média | **Assinatura ad-hoc a cada build.** O cdhash muda, então o ACL "Sempre permitir" do Keychain se perde a cada build (o que explica o contorno legado), os prompts de TCC (Documentos/Mesa) se repetem e a identidade das notificações fica instável. Não há hardened runtime, `--deep` está obsoleto e o bundle ID é `local.racky.app`. | `build_app.sh:39-63` |
| N7 | Média | **O app não pode ser dirigido por agentes nem por XCUITest.** Há zero `accessibilityIdentifier` (28 linhas usam só `accessibilityLabel`/`Value`). O pacote é só SPM com alvos executáveis, sem projeto Xcode, o que impede um bundle de UI test. Não existe canal de automação (CLI/socket) para "abrir sessão, digitar, ler a tela". | `grep accessibilityIdentifier` = 0; `Package.swift` |
| N8 | Média | **A política de SSRF é inconsistente.** A ferramenta HTTP bloqueia IPs privados (`public_http.py`), mas `navigate` do navegador só valida o esquema e pode abrir `host.docker.internal`, `192.168.x`, `169.254.x` e as portas de outras boxes (todas na rede `bridge` padrão). | `engine.py:378-385`; `BrowserComputerService.swift:701` |
| N9 | Média | **Canal MCP velho bloqueia o relançamento após crash.** O diretório `/private/tmp/ab-<planID>` é determinístico e criado com `mkdir` exclusivo. Depois de um crash ele sobra, e `register` falha com "O canal deste lançamento já existe". O agente salvo restaurado não volta sem preparar um novo plano. | `ComputerMCPConfiguration.swift:19`; `AgentComputerAccess.swift:150-152` |
| N10 | Média | **Fluxo de saída fora de ordem.** O app mata os terminais (`runtime.shutdown()`) **antes** de tentar encerrar as boxes. Se as boxes falham e o usuário escolhe "Voltar ao app", os agentes já morreram. `shutdown()` faz `usleep(500_000)` no main thread. | `RackyApp.swift:30-45`; `TerminalRuntimeManager.swift:263-268` |
| N11 | Média | **A imagem não é reprodutível no tempo.** O `Dockerfile` fixa versões exatas de pacotes apt do Ubuntu (`xvfb=2:21.1.12-1ubuntu1.8` etc.). Quando o arquivo do Ubuntu removê-las, o build quebra. Como a imagem não é publicada em nenhum registry, não há como recuperar um build bom. | `runtime/boxes/Dockerfile:2-4` |
| N12 | Média | **Docker a partir de app GUI.** O runner herda o ambiente do launchd (PATH mínimo). Por isso `docker pull`/`build` com credential helper (`docker-credential-desktop`, `osxkeychain`) falha com "not found in $PATH" fora do Terminal. `findExecutable` não procura em `~/.orbstack/bin`. | `DockerProcessRunner.swift:42-60` |
| N13 | Média | **Viewer pesado no main thread.** Cada frame MJPEG é decodificado com `NSImage(data:)` dentro de `Task { @MainActor }`. No runtime, `frame()` segura `engine.lock`, então um `navigate` longo congela o viewer. | `RemoteDesktopView.swift:172-174`; `engine.py:387-391` |
| N14 | Média | **Um terminal barulhento trava todos.** `LocalProcessTerminalView` cria `LocalProcess(delegate:)` com a fila padrão `DispatchQueue.main`. Leitura do PTY, parse VT e render acontecem no main thread, então um `cat` grande num pane congela a janela inteira. | `SwiftTerm/Mac/MacLocalTerminalView.swift:93`; `SwiftTerm/LocalProcess.swift:124-127` |
| N15 | Média | **Pipeline de hooks depende de `python3`** via `#!/usr/bin/env python3`. Num Mac sem Command Line Tools, isso abre o instalador do Xcode no meio de uma sessão do agente. O inbox é lido por polling de 300 ms por terminal, quando kqueue/`DispatchSource` resolveria. | `runtime/hooks/claude_event.py:1`; `NativeAgentMonitor.swift:159-164` |
| N16 | Alta (modo isolado) | **Worktree montado no container quebra o git.** O `.git` de um worktree é um arquivo `gitdir: /Users/.../repo/.git/worktrees/<n>`. Montado em outro caminho no container, o `git` falha. Exige montar o repositório principal **no mesmo caminho absoluto** ou clonar dentro da box. | Comportamento do git; `GitWorktreeManager.swift:31-55` cria worktrees com caminho absoluto |
| N17 | Alta (modo isolado) | **Credenciais do CLI dentro do container.** No macOS o Claude Code guarda o OAuth no Keychain, não em arquivo, então o container não herda o login. As opções são `CLAUDE_CODE_OAUTH_TOKEN` (via `claude setup-token`) ou API key. O Codex usa `~/.codex/auth.json` com refresh rotativo, e montar uma cópia gera tokens divergentes. Isso **contradiz a regra U9** da SPEC ("o app não copia token para o container") e o modelo pode exfiltrar o token que enxerga. | `01-features-requested.md` U9; conhecimento dos CLIs (a validar nas versões 2.1.302 / 0.160.0) |
| N18 | Baixa | O runtime passa `AB_API_TOKEN` no ambiente de Xvfb, Openbox e xdotool (o filtro `AB_` só se aplica ao Chromium). | `engine.py:208,220,277` vs `:131`, `desktop_browser.py:38` |
| N19 | Baixa | O `docker` CLI morto por timeout (`terminate`) **não cancela** a operação no daemon Docker: um `create` de 120 s pode concluir depois que o app já fez rollback. Isso deixa container órfão sem metadata. | `DockerProcessRunner.swift:76-84`; `BrowserComputerService.swift:389-397` |

### Afirmações da rodada 1 conferidas e confirmadas
- `swiftLanguageModes: [.v5]` (`Package.swift:18`).
- Allowlist de env (`TerminalRuntimeManager.swift:353-368`).
- Não há remoção de computador. O único `delete` é do token (`BrowserComputerService.swift:150`). Os `rm` existentes são só rollback ou update.
- `SecretVault.resolve` não tem chamador.
- `requestChild`/`revokeChild` só aparecem em testes.
- Closes no timeout do runner com drain em andamento (`DockerProcessRunner.swift:83`).
- Testes Docker fixados em `colima-racky-dev`.
- Não verifiquei de novo: a contagem de 121 avisos de concorrência estrita e os 172 testes.

---

## 2. Arquitetura-alvo

### 2.1 Visão geral

```
┌────────────────────────────── Racky.app (assinada, hardened runtime, sem sandbox) ─────────────────────────────┐
│  RackyApp (@main fino)                                                                                         │
│   └─ RackyUI  (@MainActor por padrão · @Observable por linha/pane · design system · TerminalSurface Metal)      │
│        │ view models chamam só serviços                                                                            │
│   RackyCore (Swift 6 estrito, actors, sem AppKit)                                                               │
│   ┌──────────────┬──────────────┬───────────────┬───────────────┬──────────────┬──────────────┬────────────────┐   │
│   │ Persistence  │ Workspace    │ LaunchService │ AgentRuns     │ Computers    │ Git/GitHub   │ Catalog        │   │
│   │ GRDB/SQLite  │ Project/WT/  │ adapters      │ hooks→eventos │ Engine API + │ git CLI + gh │ ~/.claude,     │   │
│   │ migrações    │ Tab/Terminal │ Claude/Codex/ │ árvore filhos │ CLI build/   │ FSEvents     │ ~/.agents...   │   │
│   │ backup       │              │ OpenCode/Shell│ estado agente │ pull; GC     │              │ índice só meta │   │
│   ├──────────────┴──────┬───────┴───────────────┴───────┬───────┴──────┬───────┴──────────────┴────────────────┤   │
│   │ PTYClient (actor)   │ MCPHost (UDS, por execução)   │ Control      │ Platform: ProcessRunner async,       │   │
│   │ fala rackyd      │ identidade via adapter        │ (runtime =   │ Keychain (1 item mestre), Logger,    │   │
│   └─────────┬───────────┴───────────────┬───────────────┘ fonte única) │ SMAppService, Notifications          │   │
│             │                           │                              └──────────────────────────────────────┘   │
│  Contents/MacOS/rackyd  ·  Contents/MacOS/racky (helper: mcp | hook | ctl)  ·  Library/LaunchAgents/*.plist │
└─────────────┼───────────────────────────┼─────────────────────────────────────────────────────────────────────────┘
              │ UDS framed (hello/versão,  │ stdio MCP ← CLI do agente (modo leve)
              │ peer = uid + code signing) │
┌─────────────▼───────────────────────┐   │          ┌────────────── Docker (Desktop | OrbStack | Colima) ───────────────┐
│ rackyd (LaunchAgent, socket-     │   │          │ rede racky-<box> (internal)                                    │
│ activated, sobrevive a quit/crash   │   │          │  ┌──────────────┐   ┌──────────────────┐   ┌─────────────────┐   │
│ da UI)                              │   └─────────►│  │ box-runtime  │   │ work (modo       │   │ egress sidecar  │   │
│  Session × N:                       │  HTTP 127.0. │  │ Chromium,    │◄──│ isolado): CLI    │──►│ proxy + listener│──► internet
│   PTY master + SwiftTerm Headless   │  0.1:porta + │  │ Xvfb, VNC,   │   │ claude/codex,    │   │ (mitm), bloqueio│   │
│   ring de saída + seq               │  token       │  │ lease, CDP   │   │ dtach, worktree  │   │ RFC1918/host,   │   │
│   log bruto em disco (cold restore) │              │  └──────────────┘   │ no mesmo caminho │   │ orçamento proxy │   │
│   argv local OU `docker exec -it`   │─────────────►│                     └──────────────────┘   └─────────────────┘   │
└─────────────────────────────────────┘ PTY remoto   └───────────────────────────────────────────────────────────────────┘
```

Princípios:
1. **O daemon é pequeno e muda pouco.** O daemon do Orca tem 556 arquivos e cerca de 100 mil linhas TypeScript, com 48 versões de protocolo. Isso mostra o custo de um daemon que acumula responsabilidades. Aqui o `rackyd` só hospeda PTYs, guarda tela e scrollback, faz relay de bytes e emite eventos de processo. Banco de dados, Docker, git e hooks ficam fora dele.
2. **Uma fonte de verdade por estado**: PTY → daemon. Controle do computador → runtime da box. Domínio → SQLite do app. Containers → Docker (rótulos) reconciliado com o SQLite.
3. **Nada bloqueante no pool cooperativo.** Processos via runner async (`swift-subprocess` ou `Process` com `terminationHandler` + `AsyncStream`). Docker via Engine API sobre UDS.

### 2.2 Daemon de PTY (`rackyd`)

**Hospedagem e ciclo de vida**
- O LaunchAgent fica registrado com `SMAppService.agent(plistName:)`. O plist em `Contents/Library/LaunchAgents/` usa `BundleProgram=Contents/MacOS/rackyd`, `AssociatedBundleIdentifiers` (prompts de TCC atribuídos ao app), `ProcessType=Interactive` e `AbandonProcessGroup=true`.
- **Ativação por socket** (chave `Sockets` com `SockPathName` em `~/Library/Application Support/Racky/run/ptyd-v1.sock`, `SockPathMode=0600`). O daemon recebe o fd via `launch_activate_socket`. O launchd vira dono do caminho, o que elimina toda a classe de bugs de "quem pode dar unlink no socket", que custou 23 defeitos ao Orca (`orca-src/src/main/daemon/AGENTS.md`).
- `KeepAlive=false`. O daemon sai sozinho depois de 60 s sem sessões e sem clientes, e o launchd o relança na próxima conexão.
- O label e o socket são **por versão major do protocolo** (`com.racky.ptyd.v1`). Um app novo com protocolo v2 sobe um daemon v2 para sessões novas, e as sessões v1 continuam no daemon antigo até terminarem. O app suporta N e N-1 e mostra "3 terminais em daemon antigo".

**Protocolo (UDS, framing binário)**
- Frame: `u32 len | u8 type | payload`. Mensagens de controle em JSON (`Codable`, módulo `RackyProtocol` compartilhado). Dados em binário: `sessionID(16) | seq(u64) | bytes`.
- Handshake `hello{major, minor, appBuild, capabilities}` → `helloAck{daemonVersion, minor, capabilities, pid, startedAt}`. Recurso novo entra como `capability` e não exige nova versão major.
- Requests:
  - `create{spec: argv, cwd, env, cols, rows, term, label, coldLogPolicy}` → `sessionID`. **O env vem do app**, já capturado do shell de login (ver §6.7), porque o daemon herda o env mínimo do launchd.
  - `list`
  - `attach{sessionID, mode: snapshot|sinceSeq}` → `snapshot{ansi, cursor, modes, seq}`, seguido do stream de dados.
  - `input`, `resize` (com debounce no cliente), `signal{group|foreground}`, `detach`, `kill`, `subscribe{exit, title, cwd, bell, osc133, idle}`, `drain` (sair quando ocioso).
- Backpressure: fila limitada por cliente. Se o limite estoura, o daemon descarta e envia `resyncRequired`, e o cliente pede um snapshot novo. Sessões **não visíveis** no app não recebem bytes, só eventos. Isso também resolve N14, porque o main thread só alimenta os panes visíveis.
- Autenticação do peer: `getpeereid` (mesmo uid) **e** requisito de assinatura via `LOCAL_PEERTOKEN` + `SecCodeCopyGuestWithAttributes`, aceitando só o app e o helper `racky`. Motivo: o socket do daemon permite **injetar teclas em qualquer terminal**, inclusive num Claude com `bypassPermissions`. Um agente rodando como o mesmo usuário não pode ter acesso a ele.

**Tela e scrollback**
- Por sessão, um `SwiftTerm.Terminal` headless (a classe `HeadlessTerminal` já existe em `SwiftTerm/HeadlessTerminal.swift`) numa fila serial própria.
- O SwiftTerm não tem um "serialize addon" como o do xterm. Há duas opções:
  - (a) escrever um serializador de buffer para ANSI (células, atributos, modos, cursor), com testes de ida e volta como os do Orca (`terminal-snapshot-serialize-roundtrip.test.ts`);
  - (b) v1 mais simples: um ring de bytes brutos (por exemplo 4 MiB) reaplicado num emulador novo no attach, cortando no último `ESC c`/`CSI 2J`/troca de alt-screen.
- Recomendação: começar por (b) e migrar para (a) se aparecer artefato visual.
- Cold restore: log bruto em `run/sessions/<id>.log`, rotativo (por exemplo 8 MiB), mais `meta.json`. Depois de reboot ou crash do daemon, o app mostra o último buffer esmaecido e "Retomar conversa" com o ID nativo.

**O que não sobrevive (e é preciso dizer ao usuário)**
- Crash do daemon mata todos os PTYs, porque o master fecha e os filhos recebem SIGHUP. A alternativa é um **host por sessão** (processo minúsculo por PTY, como dtach/abduco ou o "terminal host helper" do Orca v45), que isola crash e upgrade, mas multiplica processos e descoberta. Fica como decisão D2.
- Reboot mata tudo. Voltam layout, buffer e `--resume`.

**Sessões no container (modo isolado)**: o argv da sessão é `docker exec -it <work> dtach -A /run/s/<id>.sock -z <cli…>`. Dentro do container, o `dtach` mantém o CLI vivo se o daemon ou o `docker exec` cair. No reattach, um SIGWINCH força o redraw da TUI. O daemon não precisa saber de Docker.

### 2.3 Modelo de dados e persistência

**SQLite com GRDB 7** (compatível com Swift 6, `DatabasePool` é `Sendable`, `DatabaseMigrator` e `ValueObservation` alimentam a UI).
- **SwiftData não**: migrações frágeis, contexto preso ao MainActor e depuração opaca.
- **JSON não**: sem transação, reescrita inteira, corrupção trava o app (N3).

Tabelas iniciais:

| Tabela | Campos principais |
|---|---|
| `project` | id, root_path, name, git_remote, created_at |
| `worktree` | id, project_id, path, branch, base_ref, archived_at |
| `tab` | id, worktree_id, title, order, layout_json (árvore de splits) |
| `terminal` | id, tab_id, provider, profile_id, cwd, launch_spec_json (o que o usuário pediu), resolved_argv_json (como lançou), pty_session_id, native_conversation_id, state, exit_code, deleted_at |
| `launch_profile` | id, provider, model, permission_mode, extra_args_json, env_json, scope (global/projeto) |
| `agent_run` | id, terminal_id, parent_run_id, kind (main/native_child/isolated_child), status, started_at, ended_at, provider_session_id |
| `agent_event` | run_id, seq, type, payload_json, at · retenção por idade e por quantidade |
| `computer` | id, owner_run_id, mode, image_digest, container_id, volume, host_port, state, persistent, created_at, last_used_at |
| `attention` | id, kind, source_id, reason, created_at, resolved_at |
| `catalog_item` | só metadados: source, path, hash, kind, clients |
| `secret_ref` | só referência ao item do Keychain, sem valor |
| `setting` | chave/valor tipado |

Regras:
- WAL, `foreign_keys=ON`. Escritas num actor `Store`. A UI observa via `ValueObservation`, sem `onChange` gravando em disco. Arrastar divisor só grava no fim do gesto.
- Migrações numeradas no `DatabaseMigrator`. **Backup automático antes de cada migração** e um backup diário (`VACUUM INTO backups/racky-YYYYMMDD.sqlite`), mantendo 7.
- Corrupção: `PRAGMA quick_check` no boot. Se falhar, o arquivo é movido para `corrupt-<ts>.sqlite`, o último backup é restaurado e um banner explica. **Nunca desabilitar a UI.**
- Importador único do JSON atual (`workspace.json`, `library.json`, `AgentRuns.json`, `ComputerPolicy.json`) com dry-run e os originais preservados.
- Scrollback e logs **fora** do banco. Transcripts dos CLIs nunca são copiados, só indexados (concorda com o 05).
- Permissões: diretório `0700`, arquivos `0600`, tudo em `~/Library/Application Support/Racky/{db,run,sessions,backups,logs}`.

### 2.4 Concorrência (Swift 6 estrito)

- `swiftLanguageModes: [.v6]` em todos os alvos desde o primeiro commit, com warnings tratados como erro no CI.
- Alvo UI com `defaultIsolation(MainActor.self)` (SE-0466, Swift 6.2). Alvos Core, Protocol e Daemon com isolamento padrão `nonisolated`, e `NonisolatedNonsendingByDefault` ligado para que funções async sigam o chamador.
- Serviços como `actor`. DTOs `Sendable` (structs). Nenhum `@unchecked Sendable` sem comentário que justifique e teste de stress.
- **Proibido**: `DispatchSemaphore.wait`, `Thread.sleep`, `usleep` e locks segurados durante I/O dentro de contexto async. Valem `AsyncStream`, `withTaskCancellationHandler` e `Task.sleep(for:)`. Uma regra de lint (SwiftLint custom rule ou script `grep` no CI) bloqueia esses símbolos fora de `Platform/`.
- Fila de criação de box: um `actor ComputerScheduler` com fila FIFO e limite de concorrência. Chamadas em paralelo **esperam na fila**, sem falhar (substitui `transitionInProgress`).
- Cancelamento: toda chamada MCP carrega uma `Task` cancelável. O timeout do agente cancela a criação, e a criação em andamento é reconciliada pelo `docker events` (resolve N19).
- PTY: o daemon lê cada PTY numa `DispatchSource` de leitura na fila da sessão. No app, o `PTYClient` (actor) demultiplexa e entrega à view por pane com coalescência por frame (`CADisplayLink` do NSView no macOS 14+).

### 2.5 Containers

**Detecção de runtime** (`RuntimeDetector`):
1. `docker context ls --format json` e o contexto ativo.
2. Sockets conhecidos: `~/.docker/run/docker.sock` (Docker Desktop), `~/.orbstack/run/docker.sock`, `~/.colima/<perfil>/docker.sock`, `/var/run/docker.sock`.
3. `GET /_ping` e `/version` via HTTP sobre UDS.
4. `/info` para `MemTotal`, `NCPU`, `Architecture` e `OperatingSystem`, que identifica Desktop, OrbStack ou Colima.

Ações oferecidas: "Abrir Docker Desktop" (`open -a`), `orb start`, `colima start --cpu N --memory M --vm-type vz --mount-type virtiofs`. Nunca instalar nada sozinho.

| Runtime | Diferenças que importam |
|---|---|
| Docker Desktop | Socket `~/.docker/run`. `host.docker.internal` alcança o host. VM com limite global de RAM. Credential helper `desktop` (N12). |
| OrbStack | Mais leve, memória dinâmica, domínios `*.orb.local`. Socket próprio, CLI em `~/.orbstack/bin`. |
| Colima | Portas publicadas passam pelo port-forwarder do Lima, com **atraso de 1 a 3 s** depois do `start`. O health check precisa esperar a porta, não só o container. Mounts virtiofs exigem `vz`. |

**Cliente Docker**: Engine API sobre UDS (cliente HTTP mínimo em `Network.framework`/socket, ou `AsyncHTTPClient` com UDS) para `ps`/`inspect`/`start`/`stop`/`rm`/`stats` e principalmente **`/events?filters=label=racky.owner`**, que substitui polling e o N+1 de inspect. O CLI fica só para `build`/`pull`, com PATH aumentado (`/usr/local/bin`, `/opt/homebrew/bin`, `~/.orbstack/bin`, `/Applications/Docker.app/Contents/Resources/bin`) para os credential helpers.

**Imagem**
- Duas imagens: `racky-box` (runtime do navegador, o atual) e `racky-agent` (FROM box + node + CLIs fixados, para o modo isolado).
- Tag = hash do contexto de build (`racky-box:ctx-<sha12>`). O app sabe qual tag espera, compara e oferece "Construir (≈ 2 min)" com progresso via `docker build --progress=rawjson`.
- Publicar em GHCR por digest (`ghcr.io/<owner>/racky-box@sha256:…`) como caminho rápido, mantendo o build local como fallback. Remover os pins apt (N11). O base pinado por digest já garante reprodutibilidade, e o registry garante a recuperação.
- arm64 é o alvo. amd64 fica não verificado e deve ser declarado assim.

**Rede e portas**
- Uma rede `internal` por box (`racky-<id>`), em vez de `bridge`. Os containers da box (runtime, work) se falam, e a saída para a internet passa **só** pelo sidecar de egress. O sidecar é o proxy (Zyte opcional, com orçamento), o listener (mitmproxy com CA da box) e o filtro (bloqueia RFC1918, link-local, `host.docker.internal`, metadados). Isso resolve N8 e as lacunas de listener e proxy do 05 numa peça só.
- Portas publicadas só em `127.0.0.1::<porta>` (aleatória), lidas via `inspect`. Publicam-se apenas a API do runtime e o VNC.

**Limites e GC**
- Defaults coerentes: browser com 2 GiB e 2 CPUs, `--pids-limit 512`. Limite global de boxes ativas calculado com `MemTotal` da VM (por exemplo `floor((MemTotal − 2 GiB) / 2 GiB)`).
- Box de subagente é **efêmera**: removida (container + volume) no `SubagentStop`, com opção "manter por 24 h para inspeção". Box nomeada/persistente tem volume de perfil e só sai por ação explícita.
- Reconciliação no boot: tudo com label `racky.owner` que não está no SQLite vai para "órfãos", com tamanho em disco e botão de limpar. Nada é apagado sem confirmação, exceto boxes efêmeras marcadas.
- Segredos: **não usar env.** Token da box = `HMAC(chaveMestra, boxID)`, com a chave mestra num **único** item do Keychain. Nenhum item por box, nenhum prompt. O token chega ao container por arquivo bind-montado read-only (`/run/racky/token`, `0400`, uid do runtime). `docker inspect` mostra o caminho, não o conteúdo.
- No modo isolado, o CLI do agente roda com **outro uid** (10002) e não lê o token do runtime.

### 2.6 Streaming de desktop

| Opção | Latência em loopback | Custo | Veredito |
|---|---|---|---|
| MJPEG atual (4 fps) | 250 ms+, frame inteiro | Já existe | Manter só para miniaturas, com decode fora do main (N13) |
| **VNC (x11vnc/TigerVNC) + noVNC em `WKWebView`** | ≈ 20–60 ms, 20–30 fps em 1280×800 | websockify na box. Zero codec no app. Clipboard e teclado resolvidos | **v1** |
| Cliente RFB nativo (Swift) | Igual ao VNC | Escrever um decoder (Tight/ZRLE) | v2, se o WebView incomodar |
| CDP `Page.startScreencast` | Bom, mas só viewport | Ack por frame | **Headless**: preview e takeover sem Xvfb |
| WebRTC (Selkies/neko) | 10–50 ms | Encoder H.264 na box, mais CPU, mais complexo | Não se justifica em loopback |
| ScreenCaptureKit | — | Captura telas **do Mac**, não do container | Não se aplica. Só faria sentido para "computador = o próprio Mac", fora de escopo |

O takeover continua com a semântica atual (o lease vive no runtime), mas o input humano vai pelo próprio VNC. Durante o takeover, o runtime suspende as escritas do agente, e o VNC fica view-only enquanto o agente controla.

### 2.7 Segurança

**Modelo de ameaça (escrever no README)**

| Ator | Confiável? | Fronteira real |
|---|---|---|
| Usuário | Sim | — |
| Agente no Mac (modo leve) | **Tão confiável quanto o usuário.** Tem shell, Docker e arquivos do usuário | Permissões do próprio CLI (permission mode). O app não promete isolamento |
| Agente no container (modo isolado) | Não confiável | Container (sem socket Docker, sem mount de `$HOME`, uid distinto, rede `internal` + egress filtrado) |
| Página web no navegador da box | Não confiável | Container + egress |
| Outro processo do mesmo uid | Igual ao usuário | Nenhuma. Não tentar defender com HMAC |

Consequências:
- Apagar o "HMAC como autenticação" e a "provenance" como segurança. Mantê-los só para **correlação** (qual filho chamou), com esse nome.
- **Nunca** montar `/var/run/docker.sock` nem `$HOME` no container.
- O socket do daemon exige requisito de assinatura do peer (§2.2).
- Secrets do usuário (API keys, token Zyte, GitHub device flow): Keychain com `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Entram no env do PTY só por opt-in por perfil, e o pane mostra "env: 2 segredos".
- Credenciais do CLI no modo isolado: ver D4.
- Assinatura: **identidade estável**. Developer ID (US$ 99/ano) ou um certificado de assinatura local autoassinado com designated requirement fixo, que basta para uso pessoal e estabiliza Keychain, TCC, notificações e `SMAppService`. Hardened runtime **ligado**, sem App Sandbox (incompatível com PTY, CLIs arbitrários e socket Docker). Sem entitlements especiais. Assinar `rackyd` e `racky` com a mesma identidade, sem `--deep`.
- Notarização só se houver distribuição. Para uso pessoal, não é necessária.
- Atualizações: Sparkle 2 (EdDSA) **só** se houver Developer ID e distribuição. Para app pessoal, `scripts/install.sh` (build, assinar, substituir em `/Applications`, `launchctl kickstart` do daemon se a versão major mudou). Em qualquer caso, a atualização **não mata o daemon**: o binário antigo continua mapeado, e sessões novas usam o novo (§2.2).
- `security-scoped bookmarks`: desnecessários sem sandbox. Remover `WorkspaceDirectoryAccess`. O que importa é a atribuição de TCC para processos do daemon (`AssociatedBundleIdentifiers`).

**Logs, crash e telemetria local**
- `Logger(subsystem: "app.racky", category: …)` por módulo, com `privacy: .private` em caminhos, argv e tokens. Signposts (`OSSignposter`) em launch, attach, acquire de box e primeiro frame do viewer.
- O daemon também grava em arquivo rotativo (`logs/rackyd.log`, 5 × 2 MiB), porque `OSLogStore` no app só lê o próprio processo.
- Crash: no boot, procurar `~/Library/Logs/DiagnosticReports/Racky*.ips` e `rackyd*.ips` mais novos que a última execução e oferecer "abrir/anexar ao diagnóstico". `MXMetricManager` (MetricKit no macOS 12+) para hangs e crashes.
- "Telemetria" **só local**: tabela `metric` (latências de launch, acquire, attach e criação de box; contagem de erros por tipo) e uma tela de Diagnóstico com "Exportar pacote sanitizado" (logs, versões dos CLIs, `docker info` resumido, sem segredos). Nada sai da máquina.

### 2.8 Performance do terminal

- **Ficar com SwiftTerm 1.20+.** Ligar `setUseMetal(true)` (opt-in em `MacTerminalView.swift:429`), com fallback para CoreGraphics se falhar. O app hoje não liga.
- libghostty: o Ghostty expõe embedding em C para o próprio app macOS, mas não como biblioteca estável de terceiros. Não verificado na data. Isolar o renderer atrás de `protocol TerminalRenderer` para deixar a troca possível sem apostar nela.
- Muitos terminais: no app, **só existem views para panes visíveis mais os últimos K usados** (K = 4). Os demais vivem só no daemon. Ao mostrar, o app faz snapshot e attach. Isso limita memória e trabalho do main thread.
- Memória: o emulador headless no daemon custa o scrollback inteiro. Limitar a 10 mil linhas por sessão e expor no Diagnóstico o total por sessão. Meta: ≤ 40 MB por sessão ativa com 10 mil linhas (medir).
- Coalescência: o daemon agrupa a saída em ≤ 16 ms ou 64 KiB por frame. O app alimenta o `Terminal` fora do main quando possível (parse em fila da sessão; o SwiftTerm permite `feed` fora do main se a view não for tocada) e invalida no display link.
- Benchmarks no CI local: `yes | head -c 200M`, `cat` de arquivo de 50 MB e 4 TUIs (`htop`, `vim`, Claude) simultâneas, medindo hitches (Instruments `xctrace record --template 'Animation Hitches'`), CPU do main e RSS. Esse é o mesmo protocolo do 06 §3.4, agora com o daemon.

### 2.9 Módulos e alvos

Gerar o projeto Xcode a partir de um manifesto (XcodeGen ou Tuist), com o código em pacotes SPM locais. O projeto Xcode é necessário para app bundle, LaunchAgent, assinatura e XCUITest.

| Alvo | Tipo | Depende de | Conteúdo |
|---|---|---|---|
| `RackyProtocol` | lib | — | DTOs `Sendable`, framing, versões e capabilities do daemon, protocolo do helper |
| `RackyCore` | lib | Protocol, GRDB | Domínio e serviços (§2.1), adapters de CLI, Docker Engine client, MCP host |
| `RackyPlatform` | lib | — | ProcessRunner async, Keychain, Logger, SMAppService, FSEvents, LoginShellEnv |
| `RackyUI` | lib | Core, Platform, SwiftTerm | Design system, views, view models (MainActor) |
| `RackyApp` | app | UI | `@main`, menus/commands, ciclo de vida |
| `rackyd` | exe | Protocol, SwiftTerm (só `Terminal`/`LocalProcess`), Platform | Daemon de PTY |
| `racky` | exe | Protocol, Core (parte) | Subcomandos `mcp` (stdio → UDS), `hook` (substitui `claude_event.py`, N15), `ctl` (automação e testes, §3) |
| `runtime/box`, `runtime/agent`, `runtime/egress` | imagens | — | Python atual ampliado; Dockerfile do agente; sidecar mitmproxy |
| Testes | ver §3 | | |

**Reaproveitamento do Core atual** (concorda com o 02, com ajustes):
- **Copiar e adaptar**:
  - `WorkspaceNode`/layout (vira `layout_json`);
  - `GitWorkspaceInspector` e `GitWorktreeManager`, com runner async;
  - `CLIExecutableResolver`;
  - `CLIConversationCatalog` (ampliar para histórico);
  - `BrowserRuntimeClient` (marcar `Sendable`);
  - `ComputerMCPProtocol` e `ComputerMCPToolArguments`;
  - `EnvFileParser`;
  - modelos e `LibraryMutations`;
  - flags de hardening do `docker create`;
  - `LocalMCPChannel` (o framing e as validações de socket são bons, mas trocar o handler semáforo-bloqueante por async);
  - `decodeWaitStatus` e `signalOwnedGroups` (vão para o daemon).
- **Descartar**: `TerminalRuntimeManager` (o PTY vai para o daemon), `KeychainReadGate` e `LegacyKeychainInteraction`, `ControlBroker` persistido, journal de update de imagem, `DockerComputerService`, `ScrapingBox*`, cerimônia de hash do launch e `WorkspaceDirectoryAccess`.

---

## 3. Testes e prova de "funciona ponta a ponta"

| Camada | Ferramenta | O que prova | Onde roda |
|---|---|---|---|
| Unidade | Swift Testing (`@Test`) | Mutações puras, adapters de CLI (argv por perfil), parsers (sessões Claude/Codex/OpenCode com fixtures reais anonimizadas), migrações GRDB (banco v1 → vN com dados) | CI macOS (GitHub) |
| Protocolo do daemon | Swift Testing + processo real | Spawn de `rackyd` com socket temporário: create → output → **matar o cliente** → attach → snapshot igual; seq sem buracos; backpressure com `resyncRequired`; versão N-1; fuzz do framing | CI macOS |
| PTY real | Já existe (`ProcessesPTYTests`) | Sinais, grupos, exit codes, migrados para o daemon | CI macOS |
| Runtime da box | `unittest` atual + Playwright real | API, lease, VNC sobe, CDP screencast | **CI Linux** (Docker disponível) |
| Docker real | Testes gated por `RACKY_DOCKER_CONTEXT` (sem contexto fixo), imagem construída no setup, recursos rotulados por execução e removidos no teardown | Criar, start, health, VNC, stop, rm, GC, eventos, rede `internal` bloqueando RFC1918 | **Mac do dono ou self-hosted.** Runners macOS do GitHub não têm virtualização aninhada e não rodam Docker |
| Contrato dos CLIs | Gated por `RACKY_REAL_CLI=1`, com orçamento | `claude --session-id` + hooks chegam; `codex -c mcp_servers` enxerga as ferramentas; `--resume` repassa flags | Local, antes de release |
| UI | **XCUITest** no projeto Xcode | Fluxos P0: criar projeto → ⌘T → terminal já rodando → split → sair e reabrir com processo vivo → takeover de box | Local + CI macOS (sem Docker: box falsa via `RACKY_FAKE_RUNTIME`) |
| Snapshot | `swift-snapshot-testing` em `NSHostingView` com fonte e tamanho fixos, claro/escuro, Reduce Motion | Componentes do design system e estados (sidebar, tab, badge "esperando você", estados de erro) | CI macOS (imagens de referência por versão de SO) |
| Motion | Testes de tokens (durações/curvas vêm do enum `Motion`); teste que, com Reduce Motion, nenhuma `Animation` não nula é aplicada; signposts nas transições, medidos com `xctrace` | O 06 §3.4 (0 hitches, um resize de PTY por transição) | Local (Instruments), sem gate de CI |

**Para agentes conseguirem dirigir o app** (requisito explícito do dono):
1. `accessibilityIdentifier` estáveis e hierárquicos em todo controle e contêiner (`sidebar.project.<id>`, `tab.<id>`, `pane.<terminalID>`, `pane.<id>.status`, `computer.<id>.takeover`). Checklist de PR e um teste XCUITest que percorre a árvore e falha se um controle interativo não tiver ID.
2. **`racky ctl`**: canal de automação opt-in (desligado por padrão, liga em Configurações → Desenvolvedor), via UDS do app, com escopo de capability. Comandos:
   - `ctl session open`
   - `ctl terminal new --provider shell --cwd …`
   - `ctl terminal send <id> "echo ok\n"`
   - `ctl terminal screen <id>` (texto do emulador headless do daemon)
   - `ctl ui focus …`
   - `ctl screenshot window`
   - `ctl state` (JSON do modelo)

   Com isso um agente (Claude Code) roda o E2E sem pixel-clicking, e o resultado é verificável por texto. É o equivalente ao `orca snapshot/click` do Orca.
3. Cenário E2E canônico (script em `scripts/e2e.sh`, usa `ctl` + Docker real):
   1. criar projeto num repo temporário;
   2. abrir shell e Claude (modelo barato);
   3. `ctl app quit`, depois `ctl app launch`, e conferir o mesmo PID e o buffer restaurado;
   4. pedir ao Claude um subagente leve que chama `computer_acquire` e conferir container, VNC e frame;
   5. takeover e devolução;
   6. `SubagentStop` remove a box;
   7. matar o daemon e conferir a mensagem de cold restore.

   O resultado vira evidência JSON em `docs/evidence/`.

CI: GitHub Actions `macos-15` (build com Swift 6 estrito, testes unitários, protocolo e snapshot, lint de proibições) e `ubuntu-latest` (runtime da box, build das imagens, testes Docker do runtime). O gate pré-merge do dono roda `scripts/e2e.sh` localmente.

---

## 4. Decisões em aberto para o dono

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| D1 | Sobrevivência de PTY | (a) daemon próprio `rackyd`; (b) tmux com socket próprio (`-L racky`, `-CC`); (c) nada na v1 | (a). Tmux custa dependência, conflito de atalhos e TUIs quebradas, e o dono quer "estilo Orca" |
| D2 | Granularidade do host de PTY | Daemon único **ou** um host por sessão | Daemon único na v1 (mais simples). Reavaliar se crash ou upgrade do daemon virar dor |
| D3 | Restore de tela | Ring de bytes brutos (v1) **ou** serializador de células | Ring na v1 |
| D4 | Credenciais no modo isolado | (a) `CLAUDE_CODE_OAUTH_TOKEN` de `claude setup-token` (assinatura, longa duração, o modelo enxerga); (b) API key dedicada com limite de gasto; (c) proxy de credenciais no egress que injeta o header (o agente nunca vê o token) | (c) se viável para Anthropic/OpenAI; senão (b). Revogar a regra U9 explicitamente |
| D5 | Workspace no modo isolado | Bind mount do repositório **no mesmo caminho absoluto** (rápido, mas o agente escreve no seu disco) **ou** clone/worktree dentro do volume da box com push para branch | Mount no mesmo caminho para a v1 (N16), com opção "cópia isolada" |
| D6 | Runtime Docker suportado oficialmente | Desktop / OrbStack / Colima | Suportar os três pela Engine API. Testar oficialmente Docker Desktop (instalado) e OrbStack |
| D7 | Imagem | Build local sempre **ou** GHCR por digest com build local como fallback | GHCR + fallback |
| D8 | Assinatura e atualização | Developer ID + Sparkle **ou** certificado local + `install.sh` | Certificado local + script, a menos que haja plano de distribuir |
| D9 | Mínimo de macOS | 14 (atual) **ou** 15 | 15. A máquina é 27, ganha APIs de `@Observable`/SwiftUI mais maduras, e o app é pessoal |
| D10 | Viewer | noVNC em WKWebView **ou** RFB nativo | noVNC na v1 |
| D11 | Egress sidecar desde a v1 | Sim (resolve SSRF, listener e proxy) **ou** adiar | Sim. É a peça que faz o modo isolado ser seguro |
| D12 | Quit padrão | Agentes continuam em segundo plano (com item na barra de menus) **ou** perguntar | Continuar, com aviso uma vez e ícone de status |

---

## 5. Correções aos relatórios da rodada 1

1. **05 (c) item 8 e P2 "renderer GPU", e 02 §1 tabela de dependências.** O SwiftTerm 1.20 **já tem renderer Metal** (`MacTerminalView.setUseMetal`, `metalBufferingMode`), além de `HeadlessTerminal`, OSC 133 (`SemanticPrompt.swift`), teclado Kitty e busca. O problema não é falta de GPU. O app não liga o Metal e alimenta o PTY no main thread (N14). Avaliar libghostty não é prioridade.
2. **02 §4.2 e §7.1 (`PTYHost` no Core com `forkpty`).** Um PTY host dentro do processo do app seria descartado quando o daemon chegar (P0 no 05). O PTY deve nascer **no daemon**. O Core tem só o `PTYClient`. O `HeadlessTerminal`/`LocalProcess` do SwiftTerm já cobrem o lado do daemon.
3. **02 §1 e §2.12 ("um arquivo 0600 resolveria" o token da box).** Incompleto: o token está em `docker inspect` por causa do `--env-file` (N1). Mudar o armazenamento no host não basta. É preciso tirar o token do env do container (arquivo montado ou HMAC de chave mestra, §2.5).
4. **02 §2.9 (servir MCP via HTTP/SSE em loopback).** Com containers no modo isolado, serviços em `127.0.0.1` do Mac podem ser alcançáveis via `host.docker.internal` no Docker Desktop (a verificar com o daemon ligado). Preferir UDS no host (o helper stdio continua) e, no modo isolado, MCP servido **dentro** da rede da box, sem hop pelo app.
5. **02 §2.8 e #12, 05 (b).** A rodada 1 diz que a HMAC "não é fronteira" porque o token está no env do Claude. Isso é verdade, mas o problema é maior: **nenhuma** fronteira existe contra o agente no Mac, porque ele tem o socket Docker (N2). Isso deve virar modelo de ameaça explícito (§2.7), não um ajuste de HMAC.
6. **05 (a), "Ambiente: capturar `zsh -lic env -0`".** (i) `-i` em processo sem TTY pode travar com rc interativo (instant prompt do p10k, prompts de update do oh-my-zsh), então usar timeout e preferir `-l -c` com fallback. (ii) Usar o `$SHELL` do usuário, não `zsh` fixo. (iii) No modelo com daemon, quem captura é o **app** (ou o daemon uma vez por boot), e o env vai **na requisição `create`**. O daemon lançado pelo launchd tem env mínimo e não pode herdar nada útil.
7. **05 transversal ("Persistência em JSON… risco de corrupção").** Subestimado. Hoje a corrupção **desabilita a UI inteira** sem caminho de recuperação, e o snapshot é gravado no main thread a cada frame de arrasto (N3). Isso sobe para Alta.
8. **02 §2.3 (runner bloqueia uma thread por chamada, "aceitável fora do main thread").** Não é aceitável dentro de `Task.detached`: são threads do pool cooperativo, e com o `NSRecursiveLock` global, acquires paralelos podem parar o app inteiro (N4).
9. **02 §3 (`WorkspaceDirectoryAccess` deve ir para Core/Platform).** Sem sandbox, os bookmarks são desnecessários. O problema real é a **atribuição de TCC** aos processos lançados pelo daemon, que se resolve com `AssociatedBundleIdentifiers` e assinatura estável, não com bookmarks.
10. **05 (b), "Box = dois containers control/work".** A decisão do dono (modo isolado vs leve) se encaixa, com uma precisão: no modo leve não há container `work`. O `computer_exec` (shell na box) só deve existir com o `work` separado, ou com uid separado no mesmo container, e com egress filtrado. Sem isso, dar shell reabre o problema que o README do runtime já aponta.
11. **01 U9 ("o app não copia token para o container").** Incompatível com o modo isolado tal como decidido. Precisa de revisão explícita (D4).
12. **02 §5 e 05 ("tornar testes Docker portáveis e rodá-los em CI local").** Correto, mas falta dizer que **o CI hospedado do GitHub em macOS não roda Docker**. A divisão viável é runtime da box no CI Linux, integração Swift↔Docker no Mac do dono ou self-hosted, e XCUITest exige projeto Xcode (o SPM puro não basta).
13. **06 §3.4 regra 1 (adiar o resize do PTY durante a animação).** Correto, e no modelo com daemon o resize é uma mensagem de protocolo. O debounce fica no `PTYClient`, e o daemon só repassa `TIOCSWINSZ` ao fim.
14. **02 tabela de vereditos, "Docker: MANTER o runner".** Manter só como fallback para build/pull. Leitura e eventos devem ir pela Engine API (`/events` elimina polling, o N+1 de inspect e a corrida de N19).

---

## 6. Ordem sugerida (engenharia, não produto)

1. Esqueleto: projeto Xcode gerado, alvos da §2.9, Swift 6 estrito, Logger, lint de proibições, assinatura estável.
2. `rackyd` + protocolo + `PTYClient` + testes de protocolo (reattach, versão N-1). Terminal visível com Metal ligado.
3. GRDB, migrações, backup, importador do JSON atual.
4. LaunchService com adapters e perfis; captura de env do shell de login; `racky hook` em Swift; estado do agente via hooks com kqueue.
5. `racky ctl` + accessibility identifiers + XCUITest dos fluxos P0 + `scripts/e2e.sh` (só terminais).
6. Computers: RuntimeDetector, Engine API + eventos, imagem por hash/GHCR, rede `internal` + egress, token por HMAC, GC, VNC/noVNC. Depois, modo leve com MCP. Depois, modo isolado (`racky-agent`, `dtach`, credenciais conforme D4, mount no mesmo caminho).
7. Diagnóstico local (métricas, exportar pacote, detecção de crash).
