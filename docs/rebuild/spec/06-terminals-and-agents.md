# 06 · Terminais, agentes, biblioteca, Git/GitHub e importação do Orca

> **Revisado após R1–R3 em 2026-10-16.** Patches de `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md` aplicados; o que mudou e o que não foi aplicado está em `review/E-06-08-changelog.md`. Todo nome que vira código (bundle id, label, socket, env, spool, comando de hook, diretório de lançamento, ops do protocolo, limites, estados) segue a tabela única **`08 §0 Identificadores canônicos`**; se este capítulo e a tabela divergirem, vale a tabela. Spikes e itens "(verificar)" estão consolidados em **`08 §11`**.

Capítulo da spec do rebuild do Agent Box. Data: 2026-10-16. Escrito em português; todo texto de interface aparece em inglês (P2).

**Prevalece** `00-decisions.md`. Decisões aplicadas aqui: P3 (importar do Orca, só leitura), P4 (⌘Q não mata agentes; daemon de PTY; ícone na barra de menus), P9 (criar sessão abre o agente rodando), P10 e P11 (sessões limpas; seção "Sessions", ação "New Clean Session" ⇧⌘N), P12 (pai envia mensagem com Enter só a filhos que ele criou), P13 (proxy genérico, sem teto de orçamento), P15 (padrões de 01 §8: raiz de worktrees, nome `quiet-harbor`, aviso no primeiro ⌘Q, sessões importadas sem processo), P16 (conflitos pela recomendação dos revisores), T1 (`agentboxd`), T2 (SQLite/GRDB), T3 (Swift 6, macOS 15), T4 (assinatura estável), T5 (overlays, nunca `.sheet`), T6 (SwiftTerm + Metal, sem leitura de clipboard por OSC 52), T10 (estado por hooks configurados por lançamento), T11 (colar só por clique; prompt inicial como argumento), T12 (skill global `agentbox` concorrente), T13 (`agentbox ctl` e `accessibilityIdentifier`), T14 (sem cerimônia de hash/revisão, sem memória própria, sem Chat UI, sem SSH).

**Base**: auditoria `docs/rebuild/audit/02`, `05`, `08`, `09`, `10` e trechos da `01` e da `04`. Conferido nesta data, na máquina do dono:

- `claude --help` 2.1.302, `codex --help` / `codex resume --help` / `codex queue --help` / `codex features list` 0.160.0, `opencode --help` / `opencode session list --help` 1.18.34, `gh` 2.93.0 (`gh pr`, `gh run view --log-failed`, `gh auth token`, `gh auth git-credential`).
- `Sources/AgentBox/Terminal/TerminalRuntimeManager.swift:353-368` (allowlist de env que este capítulo substitui).
- Estado do Orca em `~/Library/Application Support/orca/profiles/local-default/` (só estrutura e contagens, nenhum valor sensível; cópia temporária apagada depois).
- `~/.claude/settings.json` e `~/.codex/hooks.json` (nomes de eventos dos hooks do Orca), `~/.codex/config.toml` (`notify` ocupado), `~/.codex/sessions/**/rollout-*.jsonl` (formato `session_meta`), `~/.codex/session_index.jsonl`.
- Código do Orca (só leitura): `src/main/git/worktree-include-file.ts`, `src/shared/orca-yaml.ts`, `src/shared/orca-yaml-hook-types.ts`, `src/main/*/hook-service.ts`.

**Convenções**

- Requisitos: `TA-nnn`. Faixas: 1xx terminais e daemon, 2xx lançamento, 3xx estado de atividade, 4xx biblioteca, 5xx Git/GitHub, 6xx importação do Orca.
- Prioridade: **P0** (sem isso a jornada não fecha), **P1** (fecha, mas mal), **P2** (melhoria).
- Versão: **v1**, **v1.1** ou **later**.
- **(verificar)**: comportamento vindo de doc ou inferência, ainda não testado nesta máquina. Todo item assim tem um teste de contrato na §7 que precisa passar antes da implementação depender dele. A lista consolidada, com dono e critério, está em `08 §11`.
- Caminhos do app: `AB = ~/Library/Application Support/AgentBox` (diretório `0700`, arquivos `0600`).
- Referências à auditoria levam o prefixo `audit/` (ex.: `audit/09 §2.2`, `audit/04 §5.4`). Sem prefixo, `NN §x` é um capítulo da spec.

---

## 0. Visão geral

```
Agent Box.app (assinada, hardened runtime, sem sandbox)
 ├─ AgentBoxUI (MainActor)  ── view models ──►  AgentBoxCore (actors)
 │                                               ├─ PTYClient ──────────── UDS ──► agentboxd (LaunchAgent, socket do launchd)
 │                                               ├─ LaunchService (adapters)        └─ sessões: PTY + emulador headless + ring + cold log
 │                                               ├─ AgentActivityService ◄── UDS `run/app.sock` ◄── `agentbox hook` (helper)
 │                                               ├─ CatalogService (FSEvents)                        └─ spool `run/spool/hooks/` se o app estiver fechado
 │                                               ├─ GitService / GitHubService (git CLI, gh token, GraphQL)
 │                                               ├─ MCPHost + ComputerService (Docker Engine API; capítulo 07)
 │                                               └─ OrcaImporter (cópia read-only do SQLite do Orca)
 ├─ Contents/MacOS/agentboxd
 └─ Contents/MacOS/agentbox   (subcomandos: hook | mcp | ctl)
```

Quatro regras atravessam o capítulo:

1. **O daemon só hospeda PTYs.** Banco, Git, hooks, Docker, MCP, serviço de computadores e biblioteca ficam **no processo do app** (`AgentBoxCore`), que continua vivo em modo `.accessory` depois do ⌘Q (`08 AR-108`). No daemon ficam só os PTYs, inclusive, na v1.1, os de `docker exec -it agent dtach …` do modo isolado. O sidecar de cada computador se chama **`egress`** (T9). Decisão fechada para todos os capítulos (`08 §0`; R1 K-75).
2. **O lançamento é declarativo.** O app guarda o que foi pedido (`LaunchRequest`) e gera o argv e os arquivos de apoio a cada start. Nada depende de um diretório temporário sobreviver.
3. **Nada global é escrito.** Hooks, MCP, skills e agentes do Agent Box entram por lançamento (`--settings`, `--mcp-config`, `--plugin-dir`, `--agents`, `-c`). Configuração global do usuário, do Orca e do Codex Computer Use fica intocada. O caso dos hooks do Codex, que exigem *trust* gravado em `~/.codex/config.toml`, está em §3.3.1.
4. **Ninguém digita no PTY de um agente sem clique do usuário** (T11), com uma única exceção: o agente pai pode enviar mensagem completa, com Enter, a subagentes que **ele mesmo** criou (P12; ferramenta de 07). Toda escrita no PTY leva uma origem no protocolo (§1.3) e a de P12 fica registrada na timeline.

---

## 1. Terminais e o daemon `agentboxd`

### 1.1 Responsabilidades

| Peça | Faz | Não faz |
|---|---|---|
| `agentboxd` | Cria e mantém PTYs; roda um emulador headless (SwiftTerm `Terminal`) por sessão para eventos e modos; guarda ring de bytes e cold log; repassa input, resize e sinais; emite eventos de processo e de OSC | Banco, Git, hooks, notificações, Docker, MCP, captura de env |
| App (`PTYClient`, actor) | Captura o env do shell de login e o envia em cada `create`; anexa só os panes visíveis; renderiza com SwiftTerm + Metal; é o **único** cliente do daemon | Ser dono de processo de agente |
| `agentbox` (helper) | `hook`: recebe eventos dos CLIs. `mcp`: ponte stdio para o app (07). `ctl`: automação opt-in (T13). Os três falam só com `AB/run/app.sock` | Falar com o daemon (nem o `ctl`: ele passa pelo app, `08 AR-503`) |

### 1.2 Hospedagem no launchd

- Registro com `SMAppService.agent(plistName: "app.agentbox.ptyd.v1.plist")`. O plist fica em `Contents/Library/LaunchAgents/` com `Label = app.agentbox.ptyd.v1`, `BundleProgram = Contents/MacOS/agentboxd`, `AssociatedBundleIdentifiers = [app.agentbox.mac]`, `ProcessType = Interactive`, `AbandonProcessGroup = true`, `KeepAlive = false`.
- **Ativação por socket (T1)**. O plist é estático dentro do bundle e não conhece o home do usuário; `SockPathName` é um caminho literal, sem expansão de `~` nem de variáveis (R3 §1). Por isso o socket **não** usa `SockPathName`:
  - **Canônico**: chave `Sockets` com `SecureSocketWithKey = AGENTBOX_PTYD_SOCK_V1`. O launchd cria o socket num diretório privado dele (`/private/tmp/com.apple.launchd.*/…`, caminho curto, bem abaixo dos 104 bytes de `sun_path`) e publica o caminho na variável `AGENTBOX_PTYD_SOCK_V1` do domínio do usuário (o mesmo mecanismo do `SSH_AUTH_SOCK` do macOS). O app lê o caminho com `launchctl getenv AGENTBOX_PTYD_SOCK_V1` depois do `register()` e o guarda só em memória. O daemon recebe o fd com `launch_activate_socket`; nunca faz `unlink`/`bind`. A variável é removida do env dos terminais pela denylist `AGENTBOX_*` (§1.7).
  - **Plano B** (se o spike S-01 reprovar o canônico): o daemon roda com `RunAtLoad = false`, o app o acorda com `launchctl kickstart gui/<uid>/app.agentbox.ptyd.v1` e o próprio daemon faz `bind` em `AB/run/ptyd-v1.sock` (`0600`, conferindo dono e modo do diretório). Isso deixa de ser "socket ativado pelo launchd" e exige registrar a exceção a T1 no 00.
  - **Modo degradado e testes**: daemon filho do app, mesmo binário e protocolo, `bind` em `AB/run/ptyd-v1.sock` (ou `$AGENTBOX_HOME/run/ptyd-v1.sock` nos testes, label `app.agentbox.ptyd.test-<n>`).
- **Resultado do S-01 (2026-10-17, `docs/evidence/spikes/S-01/`): o plano canônico funciona; o plano B não foi necessário.** Com `SMAppService.agent` e `Sockets/SecureSocketWithKey`: o launchd cria o socket em `/var/run/com.apple.launchd.<id>/Listeners` (diretório `0700`), `launchctl getenv AGENTBOX_PTYD_SOCK_V1` devolve o caminho logo depois do `register()`, `launch_activate_socket("Listeners")` (o nome é o da entrada em `Sockets`, não o da variável; o símbolo vem por `dlsym`) entrega o fd 3 e `nc -U` acorda o daemon; ocioso, ele sai e a conexão seguinte o relança no mesmo caminho. Achados que o plist e o app precisam respeitar: (1) sem `SockPathMode` o socket sai `0666` (o plist de produção fixa `384`); (2) o launchd **prende o job ao `cdhash` do `BundleProgram` no registro**: trocar esse binário (toda atualização do app, ad-hoc ou certificado autoassinado) deixa o job em `spawn failed` (`EX_CONFIG`/`OS_REASON_CODESIGNING`) e a conexão fica pendurada; `unregister()`+`register()` mata o daemon e, logo depois da troca, ainda grava o cdhash velho (o BTM só atualiza minutos depois). **Solução adotada (desvio de 08 §0.1, a ratificar pelo dono): o `BundleProgram` é um launcher estável `agentboxd-launch` (C, 33 KB, só faz `exec` do `agentboxd` ao lado com os mesmos argumentos; o fd do socket é herdado).** O cdhash do launcher não muda, então atualizar o `agentboxd` não exige novo registro: o daemon antigo sai quando a última sessão termina (`drainWhenIdle`) e o novo sobe na conexão seguinte (e2e `scripts/e2e-launchd.sh`, passo 4). Se o launcher mudar, o app guarda o fingerprint dele, nunca desregistra com o job rodando e re-registra com o daemon parado (`BackgroundAgentHost`); (3) com app ad-hoc e Mac sem restrição de Itens de Início o `register()` devolveu `enabled` na hora (sem `requiresApproval`); em outro Mac ou depois de "Itens de Início" restrito o estado pode vir `requiresApproval`, e aí vale o modo degradado abaixo.
- Sai sozinho após 60 s sem sessões vivas e sem clientes conectados. O launchd o relança na próxima conexão.
- Label, plist e variável do socket carregam a versão **major** do protocolo (`…ptyd.v1`, `AGENTBOX_PTYD_SOCK_V1`). Ver §1.10.
- O primeiro registro pede aprovação do item de login. O app pede isso no onboarding, com uma frase do porquê ("Keeps your agents running when you quit Agent Box"). Sem aprovação, o app funciona em modo degradado (acima) e o quit avisa que vai encerrar tudo. A Fatia 1 roda inteira nesse modo; o LaunchAgent entra na última tarefa da fatia, se o S-01 passar (`08 §10`).

### 1.3 Protocolo

Esta seção e `08 AR-102` descrevem o **mesmo** protocolo, com os mesmos nomes. A fonte normativa é o módulo `AgentBoxProtocol` mais as fixtures JSON versionadas em `Tests/ProtocolTests/Fixtures/`, escritas **antes** do daemon (tarefa T-04 de `08 §10`). Mudança aqui exige mudança da fixture, e vice-versa.

**Transporte**: socket Unix (§1.2), stream. **Frame**: `u32 len (big-endian) | u8 kind | payload`, `len` limitado a 1 MiB; frame maior fecha a conexão com `error{code:"frameTooLarge"}`.

| `kind` | Direção | Payload |
|---|---|---|
| `0x01` control | ambos | JSON UTF-8 (`Codable`, módulo `AgentBoxProtocol`) |
| `0x02` output | daemon → cliente | `sessionID (16 B) | seq (u64 BE) | bytes` |
| `0x03` input | cliente → daemon | `sessionID (16 B) | origin (u8) | bytes` |

- **`seq`** é o offset em bytes, desde o início da sessão, do primeiro byte do frame. É contínuo: o próximo frame começa em `seq + len(bytes)`. Buraco = bug (teste de protocolo).
- **`origin`** identifica quem escreveu no PTY: `0x00` tecla do usuário · `0x01` colagem do usuário (⌘V, arrastar) · `0x02` colagem do app por clique (T11, ex. "Send Failures") · `0x03` `ctl` · `0x04` mensagem do agente pai a filho que ele criou (P12) · `0x05` resposta a consulta do terminal (DA/DSR, AR-105). O daemon conta bytes por origem e expõe os contadores em `list` (`inputBytesByOrigin`); é assim que os critérios de aceite provam "o app não escreveu nada no PTY" (§2.4.1).

**Handshake** (primeiro frame obrigatório, timeout 2 s):

```json
→ {"op":"hello","id":1,"protocol":{"major":1,"minor":0},"client":{"kind":"app","build":"1.0 (42)"},"capabilities":["coldLog","osc133","textSnapshot","inputOrigin"]}
← {"op":"helloAck","id":1,"protocol":{"major":1,"minor":2},"daemon":{"build":"1.0 (41)","pid":812,"startedAt":"…","binary":"…/agentboxd"},"capabilities":["coldLog","osc133","textSnapshot","inputOrigin","drainWhenIdle"],"sessions":7}
```

`client.kind` só aceita `app` (o `ctl` nunca conecta no daemon, `08 AR-503`).

- Major diferente: o daemon responde `error{code:"protocolMajorMismatch"}` e fecha. O cliente procura o daemon da major certa.
- Minor: os dois lados usam a interseção de `capabilities`. Recurso novo entra como capability, sem bump de major.

**Autenticação do peer** (antes de ler o `hello`):

1. `getpeereid`: uid do peer igual ao do daemon.
2. `getsockopt(LOCAL_PEERTOKEN)` → audit token → `SecCodeCopyGuestWithAttributes` → `SecCodeCheckValidity` contra um requisito compilado no daemon: mesma folha de certificado da identidade de assinatura (T4) **e** identificador `app.agentbox.mac` (só o app; `08 AR-503`).
3. Falhou: responde `error{code:"peerRejected"}` (sem `id`), fecha e registra (`Logger`, subsystem `app.agentbox.ptyd`, categoria `auth`). O erro vem antes de qualquer `hello` e não revela o motivo além da categoria.

Motivo: o socket permite digitar em qualquer terminal, inclusive num Claude com `--dangerously-skip-permissions`. Um processo do mesmo usuário (um agente com Bash) não pode usar o daemon. Builds de desenvolvimento usam a mesma identidade local (T4); não existe bypass por variável de ambiente. Única exceção (T1-07, S-03): enquanto o daemon estiver assinado **ad-hoc** (dono ainda sem `make-dev-cert.sh`) e o build tiver a flag de compilação `AGENTBOX_ALLOW_ADHOC_PEERS`, vale só o uid (modo `adhoc-development`, registrado no log). `scripts/build.sh` passa a flag só quando assina ad-hoc; daemon assinado com certificado ignora a flag; daemon ad-hoc sem a flag recusa todos. Como isso funciona com XCUITest, `ctl` e o runner de CI é o spike S-03 (`08 §11`).

**Requisições** (todas com `id`; resposta `{"op":"ok","id":…, …}` ou `{"op":"error","id":…,"code":…,"message":…}`):

| `op` | Campos | Efeito |
|---|---|---|
| `create` | `sessionID` (UUID gerado pelo app), `argv`, `cwd`, `env` (completo), `cols`, `rows`, `term`, `ringBytes`, `coldLog: bool`, `label`, `owner{terminalID, runID}` | Abre o PTY e faz spawn (forkpty + execve, código próprio do daemon sobre as rotinas de PTY do SwiftTerm; nunca `LocalProcess` com fila do main). **Idempotente**: `sessionID` já existente devolve a sessão atual sem novo spawn |
| `list` | — | Sessões com `sessionID`, `pid`, `pgid`, `argv[0]`, `cwd` atual, `state` (`running`/`exited`), `startedAt`, `exit`, `lastOutputAt`, `title`, `endSeq`, `inputBytesByOrigin` |
| `attach` | `sessionID`, `cols`, `rows`, `mode: snapshot|sinceSeq`, `sinceSeq?` | `snapshot`: responde `attachSnapshot{sessionID, startSeq, endSeq, modesPreamble}` (preâmbulo em base64) e em seguida manda os bytes do replay como frames `output` de `startSeq` a `endSeq`, depois o stream ao vivo. `sinceSeq`: reenvia do `sinceSeq` pedido se ele ainda estiver no ring; senão cai para `snapshot` (§1.5) |
| `detach` | `sessionID` | Para o stream para este cliente; a sessão continua |
| `resize` | `sessionID`, `cols`, `rows` | `TIOCSWINSZ`. Só o app redimensiona; regra de quando em §1.8 |
| `signal` | `sessionID`, `signal`, `target: group|foreground` | `killpg` no grupo da sessão ou no grupo de foreground (`tcgetpgrp`) |
| `kill` | `sessionID`, `mode: graceful|force` | `graceful`: SIGHUP + SIGTERM ao grupo, evento `stillAlive` após 5 s. `force`: SIGKILL, só por ação explícita do usuário |
| `subscribe` | `sessionIDs` ou `all`, `events[]` (`exit`, `title`, `cwd`, `bell`, `prompt`, `altScreen`, `modes`, `idle`) | Eventos sem bytes (para sessões não visíveis) |
| `textSnapshot` | `sessionID`, `lines` | Texto da tela e do fim do scrollback do emulador headless (para `ctl terminal screen` via app e diagnóstico) |
| `forget` | `sessionID` | Apaga ring e cold log de uma sessão encerrada |
| `drainWhenIdle` | — | Marca o daemon para sair quando a última sessão acabar (upgrade) |
| `ping` | — | Latência e saúde |

O input não é uma requisição JSON: vai em frames `0x03` (com `origin`), sem resposta.

**Eventos** (`op:"event"`, com `sessionID`): `exit{code, signal, at}`, `title{text}` (OSC 0/2), `cwd{path}` (OSC 7), `bell`, `prompt{phase: A|B|C|D, exitStatus?}` (OSC 133), `altScreen{on}`, `modes{bracketedPaste, appCursor, mouse}`, `idle{since}`, `stillAlive`, `resyncRequired`, `sessionGone`.

**Códigos de erro**: `protocolMajorMismatch`, `badRequest`, `unknownSession`, `sessionExited`, `spawnFailed` (com `errno` e `path`), `frameTooLarge`, `notCapable` (capability não negociada), `peerRejected` (peer não autenticado, enviado antes de fechar), `internal`. Lista fechada; código novo entra como capability.

**Backpressure**: fila por cliente limitada a **2 MiB** (`08 AR-102`). Estourou: o daemon descarta a fila daquele cliente e envia `resyncRequired`; o cliente refaz `attach` em modo `snapshot`. A sessão nunca é bloqueada por um cliente lento. (O app tem outro limite, do lado dele: backlog de 4 MiB por pane antes de pedir snapshot, `08 AR-406`.)

**Coalescência**: o daemon agrupa a saída em frames de até 16 ms ou 64 KiB.

**Capabilities iniciais (minor 0)**: `coldLog`, `osc133`, `textSnapshot`, `inputOrigin`, `drainWhenIdle`.

**Precisões da implementação (T1-04, `AgentBoxProtocol`)**: (1) `len` conta os bytes de `kind` + payload (o prefixo de 4 bytes não entra); `len == 0` é `badRequest`; `len` > 1 MiB responde `frameTooLarge` assim que o prefixo chega, sem esperar o corpo. (2) `ok` leva o campo `result` (`created` com `session`+`spawned`, `list` com `sessions`, `pong`, `textSnapshot`); ausente = resposta vazia. (3) `attachSnapshot` também responde `attach` por `sinceSeq` atendido pelo ring, com `resumed:true` e `modesPreamble` vazio. (4) `error` sem `id` é erro de conexão. (5) Campos e capabilities desconhecidos são ignorados na leitura; `op`, evento, código de erro ou `client.kind` desconhecidos falham a decodificação (`badRequest`). (6) Negociação: versão = major do par e `min(minor)`; capabilities = interseção; N-1 só por cliente de compatibilidade que anuncia a major anterior no socket antigo. As fixtures normativas estão em `Tests/ProtocolTests/Fixtures/` (`v1/`, `n-1/`, `invalid/`, `frames/`).

### 1.4 Ciclo de vida da sessão

```
create ─► running ──exit──► exited(code|signal) ──forget──► (apagada)
             │  ▲
   detach/attach (qualquer número de vezes; zero ou mais clientes)
```

- O app guarda `pty_session_id` em `terminal`. Ao abrir, chama `list`, cruza com o SQLite e marca: **vivo** (reanexar), **encerrado com log** (mostrar buffer esmaecido) ou **ausente** (reboot ou crash do daemon; usar cold log; estado de processo `interrupted`, §3.1).
- Só panes visíveis ficam anexados (recebem bytes); os 4 últimos usados mantêm a **view** em cache e reanexam com snapshot ao aparecer; o resto só recebe eventos (`subscribe`; `08 AR-406`). Isso limita memória e trabalho do main thread (R6.3).
- Fechar um pane com processo vivo (⌘W) pede confirmação no overlay de 03 §16.1 ("Close this terminal?" [Cancel] [Close Terminal]). Fechar = `kill graceful`; se sobrar processo após 5 s, o pane mostra "Process didn't exit" com [Force Quit].
- Apagar terminal ou sessão: mesma confirmação, depois `forget`. Undo por 8 s (DS §12.19) apenas para o registro (o processo já terminou).

### 1.5 Ring buffer, modos e reattach

- **Ring** por sessão: 4 MiB padrão (configurável de 1 a 32 MiB em Settings › Terminal).
- **Ponto de corte**: o emulador headless marca o offset do último `ESC c`, `CSI 2J`/`CSI 3J` ou entrada em alt-screen. O replay começa no ponto de corte mais recente que ainda está no ring; se nenhum estiver, começa no início do ring precedido de `ESC c`.
- **`attachSnapshot`** = `{sessionID, startSeq, endSeq, modesPreamble}` seguido dos bytes do replay em frames `output` (nunca num JSON só: o ring passa do limite de 1 MiB por frame). `modesPreamble` reestabelece o que o replay pode ter cortado: alt-screen, bracketed paste, application cursor/keypad, modos de mouse, cursor visível, título; é uma sequência de escapes VT, serializada em base64 no JSON. O cliente cria um emulador novo, aplica o preâmbulo e os bytes, e passa a consumir `output` com `seq ≥ endSeq`.
- **Redraw forçado**: depois do attach, o daemon aplica o tamanho do cliente; se for igual ao atual, faz `cols-1` e volta para `cols` em 50 ms, o que gera `SIGWINCH` e faz TUIs (Claude, Codex) redesenharem. Validação com Claude, Codex e `vim`: spike S-04.
- **Cold log**: o daemon grava a saída bruta em `AB/sessions/<ptySessionID>/output.log` (rotação **2 × 8 MiB**) e `meta.json` com `terminalID`, `runID`, `argv`, `cwd`, `envKeys` (só nomes, **nunca valores**), `pid`, `startedAt`, `exit`. Escrita assíncrona em lote. Liga por padrão; desliga por terminal ("Don't keep output on disk") ou globalmente. Retenção: apagado com o terminal (`forget`) ou 7 dias depois do `exit`.
- Escopo: restauração por replay de bytes (`audit/09` D3). Serializador de células fica para later, só se aparecer artefato visual medido.

### 1.6 Sobrevivência: o que volta e como

| Evento | Processos | O que o usuário vê ao reabrir |
|---|---|---|
| Fechar a janela | Vivos | Nada muda; a sessão continua no app (accessory) |
| ⌘Q, escolhendo **Keep Running** | Vivos | Panes com processo vivo e scrollback, inclusive o que saiu com o app fechado (ring) |
| Crash do app | Vivos | Igual ao anterior; eventos de hook do intervalo vêm do spool (§3.2) |
| Atualização do app (`install.sh`) | Vivos | Igual; o daemon antigo continua até ficar ocioso (§1.10) |
| Crash do daemon | Mortos (SIGHUP) | Banner "Background agents stopped unexpectedly" (AC-810) e, em cada pane, último buffer do cold log esmaecido com "This terminal stopped unexpectedly.", [Resume] para agentes, [Restart Shell] para shells |
| Logout, reboot, desligar | Mortos | Layout, tabs e panes; último buffer esmaecido; [Resume] por pane e "Resume Agents…" por sessão (overlay "Resume interrupted agents?" com lista de CLI, modelo e última mensagem e o botão "Resume <n>"; nada retoma sozinho; 03 §16) |
| Sleep | Suspensos pelo sistema | Nada a fazer; "manter acordado" é de 07 (v1.1) |

- [Resume] relança com o ID nativo capturado **e regenera** flags, MCP, hooks, skills e agentes do lançamento original (§2.6).
- Shell sem agente: [Restart Shell] abre `$SHELL -l` no mesmo cwd (último OSC 7 ou o cwd original). Opção "Restart shells automatically after reboot" (desligada por padrão).
- Subagentes e computadores depois de reboot: 07 (R8.2).

### 1.7 Ambiente do shell de login

O daemon nasce com o env mínimo do launchd. O **app** captura o env do usuário e o envia em cada `create`.

**Captura** (no startup do app, fora do main thread, e em Settings › Terminal › "Reload Shell Environment"). Esta ordem é a canônica (`08 §0`, `08 AR-103`); o spike S-06 (2026-10-17, `docs/evidence/spikes/S-06/README.md`) a mediu com o zsh 5.9 do dono (sem p10k nem oh-my-zsh; o `~/.zshrc` só exporta PATH, define funções e faz `source` de arquivos de chaves). Não há premissa de tema de prompt: o que protege o app de rc lento ou barulhento é o marcador, o timeout e o `SIGKILL`:

1. Shell = `$SHELL` do usuário (`getpwuid`), nunca `zsh` fixo.
2. Primeira tentativa: shell **interativo de login** dentro de um PTY oculto (`pty.fork`), `stdin` vazio, `TERM=dumb`, comando `-l -i -c 'printf "\n__AB_ENV__\n"; /usr/bin/env -0 > "$AB_ENV_OUT"; printf "\n__AB_ENV_END__\n"'`. **O env sai por arquivo** (`AB_ENV_OUT`, criado pelo app em `AB/run/`, modo 0600, apagado em seguida), não pelo PTY: o PTY troca `\n` por `\r\n` e corrompe valores multilinha (certificados); com `env -0 > arquivo` o valor sai byte a byte (S-06, teste 3). O marcador `__AB_ENV_END__` só sinaliza o fim; tudo antes dele (banners, avisos, sequências ANSI de rc barulhento) é ignorado. **Timeout 5 s e `SIGKILL` no grupo do PTY**; sem processo órfão (S-06, caso 2c: rc que dorme 60 s foi cortado sem sobras). Medido: mediana 32 ms; 0,76 s com um rc sintético barulhento.
3. Falhou ou estourou: `-l -c` **sem PTY e sem `-i`**, mesmo marcador, timeout 3 s (20 ms medidos). **Não é caminho normal:** sem `-i` o `.zshrc` não roda e o PATH perde entradas (no Mac do dono, `~/.opencode/bin`). Quando este fallback é o usado, o Diagnostics mostra o banner `Using non-interactive shell environment` (nunca silencioso) e marca a fonte como `non-interactive`.
4. Falhou: env do launchd + diretórios conhecidos no PATH (`~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, nvm atual). Banner no Diagnostics: "Using fallback environment".
5. Fica só em memória (pode ter tokens). Diagnostics mostra a fonte, a duração e a lista de chaves (sem valores).

**Composição do env de cada terminal** (nesta ordem; a última vence):

1. Env capturado.
2. Remoção (denylist mantida em código, com teste): `PWD`, `OLDPWD`, `SHLVL`, `_`, `TERM_SESSION_ID`, `TERM_PROGRAM*`, `ITERM_*`, `WEZTERM_*`, `KITTY_*`, `GHOSTTY_*`, `VSCODE_*`, `ORCA_*`, `AGENTBOX_*`, `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SSE_PORT` e marcadores de sessão de outros agentes (lista revisada a cada versão de CLI). Motivo: `ORCA_PANE_KEY` herdado ativaria os hooks globais do Orca dentro do Agent Box; `CLAUDECODE` faz o Claude achar que é aninhado.
3. Do app: `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=AgentBox`, `TERM_PROGRAM_VERSION`, `LANG` (se ausente, `en_US.UTF-8`), `AGENTBOX_PANE_ID` (= `terminal.id`), `AGENTBOX_RUN_ID` (= id da execução; novo a cada start ou resume), `AGENTBOX_APP_SOCK` (caminho absoluto de `AB/run/app.sock`). Servem para correlação, não autenticação (`08 AR-111`). Nenhuma outra variável `AGENTBOX_*` chega ao terminal.
4. Do perfil de lançamento (`env{}`), e segredos marcados por opt-in no perfil (o pane mostra "env: 2 secrets").

Consequências verificáveis:

- `SSH_AUTH_SOCK` chega ao terminal (vem do launchd ou do rc do usuário; nada o remove).
- `PATH` é o do shell do usuário, inclusive nvm/asdf/bun configurados no `.zshrc`.
- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `ALL_PROXY` (e minúsculas) passam como estão. Proxy do sistema (`scutil --proxy`) não é convertido em env (later).
- `GH_TOKEN`, `ANTHROPIC_*`, `OPENAI_*` passam se o usuário os exporta. É o comportamento de qualquer terminal; o modelo de ameaça já trata o agente no Mac como tão confiável quanto o usuário (`audit/09 §2.7`).

### 1.8 Multi-terminal: tabs, splits, foco e layout

Modelo (por sessão): **Session → Tab[] → árvore de splits → Pane → Terminal**. Uma tab é um grupo de panes, como no Orca; não é "um terminal por tab".

- **Splits ilimitados**: ⌘D (à direita), ⇧⌘D (abaixo). Limite só físico: um pane não fica menor que 240 × 120 pt (03 §4.3); abaixo disso o split é recusado com o toast "Not enough room to split. Close a pane or widen the window." O limite atual de 5 panes (`WorkspaceStore.swift:112`) some.
- **Foco**: clique, ⌘] / ⌘[ (próximo/anterior). ⌥⌘←/→ é histórico (voltar/avançar), como no Orca (03 §21); não há foco direcional por setas. O pane focado é first responder do terminal. Pane inativo com opacidade 0,8 (DS4 de 02).
- **Zoom**: ⇧⌘↵ expande o pane focado dentro da tab; repete para voltar.
- **Tabs**: ⌘T abre um shell numa tab nova; ⌥⌘T abre o agente padrão; ⌥⌘N abre o lançador (Quick Launch, 03 §7) para escolher agente, perfil e prompt (tabela de atalhos: 03 §21). ⌘W fecha o pane focado (a tab some com o último pane); reordenar por arraste; título dinâmico (OSC 0/2, ou `-n/--name` do Claude), com renomear manual que prevalece.
- **Novo pane** em split herda o cwd atual do pane de origem (último OSC 7) e o provider escolhido no lançador.
- **Divisores**: 3 pt visíveis, 9 pt de clique. Resize do PTY: em transição animada, um só, no início (04 R2; ao fechar painel, no fim); em arrasto, no máximo 1 por quadro e o final ao soltar (04 M-202). Teste: uma transição gera exatamente um `resize` no protocolo (`08 AR-710`).
- **Persistência**: `tab.layout_json` (árvore com frações e `terminalID`s), ordem das tabs, tab ativa e pane focado, em SQLite, gravados com debounce de **300 ms** e no fim do gesto (`08 AR-711`). Nada é gravado por frame.
- Grupos de tabs lado a lado (arrastar tab até a borda) ficam para v1.1. Arrastar um pane para reorganizar: later (R2 SEM #11).
- Atalhos globais, ⌘1…9 e paleta: 03 §21.

### 1.9 Quit e item na barra de menus

**⌘Q** com processos vivos abre o overlay de confirmação dentro da janela (T5; texto de 03 §16.10). `NSAlert` escuro só quando nenhuma janela está aberta (quit pelo Dock ou pela barra de menus com a janela fechada).

> **3 agents and 2 shells are still running.**
> They keep running in the background and you can come back anytime.
> [Keep Running] (padrão, ↵) · [Stop All and Quit…] · [Cancel] · ☑ Don't ask again

- **Primeira vez** (P15): o overlay aparece no primeiro ⌘Q com agentes vivos, com "Don't ask again" **marcado** por padrão. Mantido marcado, os ⌘Q seguintes aplicam Keep Running direto. Settings › General › "Ask before quitting with agents running" religa o aviso. Isso troca o sentido de ⌘Q no macOS (o app não sai); decisão registrada em R1 D-12 e fechada por P15/P16.
- **Keep Running**: o app fecha as janelas, libera as views de terminal, troca para `NSApplication.ActivationPolicy.accessory` (sem ícone no Dock) e mantém o item na barra de menus, o receptor de hooks, o MCP, o serviço de computadores e as notificações. Reabrir pelo item, pelo Dock ou pelo Spotlight volta à janela já anexada.
- **Stop All and Quit…**: `kill graceful` em todos, espera até 5 s mostrando quem falta, oferece [Force Quit] para o resto, e só então encerra. Computadores são tratados pelo capítulo 07 **antes** de matar terminais, e nunca depois (corrige `audit/09` N10).
- Sem processos vivos: ⌘Q encerra direto.

**Item na barra de menus** (`MenuBarExtra`, servido pelo próprio processo do app; **não existe helper de login separado**, R1 D-03 fechado por P16):

- Ícone conforme 03 §17: número ao lado quando há pendências; ponto âmbar só com não lidos; sem animação. Setting "Show menu bar icon": `Always` · `When agents are running` (padrão). Não existe `Never` (P4 exige o ícone enquanto houver agentes; R1 K-91).
- Menu: seção "Needs You" (cada item vai ao pane), seção "Working" (agente, sessão, tempo), "Open Agent Box", "Stop All Agents…", "Quit Agent Box Completely" (encerra o processo do app e **tira o ícone até reabrir**; os agentes seguem no daemon; notificações, MCP e computadores param até reabrir; o spool cobre os hooks do intervalo e `agentbox mcp` reabre o app em segundo plano quando um agente chama uma ferramenta, `08 AR-110`).
- v1.1: ações no próprio menu (assumir computador, responder) (R6.5).

### 1.10 Upgrade do daemon

- `install.sh` troca o bundle com `rename` atômico. O daemon em execução continua com o binário antigo mapeado.
- **Mesma major**: no `helloAck` o app compara builds. Se o daemon for mais antigo, envia `drainWhenIdle`: ele continua aceitando sessões e sai quando a última terminar; o launchd sobe o binário novo na conexão seguinte. Diagnostics (que pode usar termos técnicos, 01) mostra "Daemon update pending (7 terminals running)" e oferece [Restart Daemon Now…], que lista o que vai morrer e oferece [Resume] depois. Fora do Diagnostics, o texto é o de `08 AR-904` ("Restart background service to update").
- **Major nova**: novo label, plist e variável de socket (`app.agentbox.ptyd.v2`, `AGENTBOX_PTYD_SOCK_V2`). O app registra o agente v2 para sessões novas e mantém um cliente de compatibilidade N-1 (`list`, `attach`, input, `resize`, `signal`, `kill`) para as sessões do daemon antigo, que sai sozinho quando fica ocioso. O app nunca suporta mais de N-1.
- Teste obrigatório: app N com daemon N-1 vivo e 3 sessões; attach, input e kill funcionam; sessão nova vai para o daemon N.

### 1.11 Requisitos — terminais e daemon

| ID | P | Versão | Requisito | Aceite |
|---|---|---|---|---|
| TA-101 | P0 | v1 | `agentboxd` como LaunchAgent via `SMAppService`, ativado por socket do launchd, saída após 60 s ocioso | `launchctl print gui/$UID/app.agentbox.ptyd.v1` mostra o job e `launchctl getenv AGENTBOX_PTYD_SOCK_V1` devolve o caminho do socket (S-01); matar o cliente e reconectar relança o daemon; sem sessões, o processo some em ≤ 70 s |
| TA-102 | P0 | v1 | Protocolo com framing binário, handshake `hello/helloAck`, major/minor e capabilities | Teste de protocolo: cliente com major errada recebe `protocolMajorMismatch`; capability ausente no daemon desabilita o recurso no cliente sem erro |
| TA-103 | P0 | v1 | Autenticação do peer por uid **e** requisito de assinatura (só `app.agentbox.mac`) | Um binário não assinado (ou assinado com outra identidade, inclusive o helper `agentbox`) do mesmo usuário é desconectado antes do `hello`; o app conecta |
| TA-104 | P0 | v1 | `create` idempotente por `sessionID`; `attach`/`detach`/`resize`/`signal`/`kill` conforme §1.3; input com `origin` e contadores por origem | Teste: `create` repetido não faz segundo spawn; Ctrl-C chega ao grupo de foreground; `kill graceful` encerra `sleep 100` e um `bash` com filho; `list` devolve `inputBytesByOrigin` coerente com o que foi enviado |
| TA-105 | P0 | v1 | Ring de 4 MiB, ponto de corte, preâmbulo de modos e redraw forçado no attach | Teste: rodar `vim` e o Claude, matar o cliente, reanexar; a tela renderizada é igual (comparação de `textSnapshot`), bracketed paste continua ativo, seq sem buracos |
| TA-106 | P0 | v1 | Backpressure de 2 MiB por cliente com `resyncRequired`; sessões ocultas não recebem bytes | `yes | head -c 200M` num pane oculto não aumenta a memória do app além de 50 MB; o pane visível ao lado continua respondendo (hitch < 50 ms) |
| TA-107 | P0 | v1 | Sobrevivência a ⌘Q (Keep Running), crash do app e atualização do app | E2E `ctl`: anotar PID do Claude, `ctl app quit`, `ctl app launch`: mesmo PID e o buffer inclui saída gerada com o app fechado; repetir com `kill -9` no app |
| TA-108 | P0 | v1 | Cold log em disco (2 × 8 MiB) e restauração depois de reboot/crash do daemon, com [Resume] e [Restart Shell] | `kill -9` no daemon: banner "Background agents stopped unexpectedly"; cada pane mostra o último buffer esmaecido e "This terminal stopped unexpectedly."; [Resume] relança o agente com o mesmo ID nativo |
| TA-109 | P1 | v1 | Cold log desligável por terminal e global; retenção de 7 dias após o `exit` | Com a opção desligada, nenhum arquivo em `AB/sessions/<id>/`; arquivos de sessões antigas são apagados na limpeza diária |
| TA-110 | P0 | v1 | Env do shell de login conforme §1.7 (captura com marcador, fallback, denylist, variáveis do app) | Num terminal aberto por app lançado pelo Finder: `which claude node gh` resolvem como no Terminal.app; `echo $SSH_AUTH_SOCK` não é vazio; `env | grep ORCA_` é vazio mesmo se o app foi aberto de dentro do Orca; um `export FOO_PROXY` no `.zshrc` aparece |
| TA-111 | P1 | v1 | "Reload Shell Environment" e Diagnostics com fonte, duração e chaves | Editar o `.zshrc`, recarregar, abrir terminal novo: a variável nova existe; terminais já abertos não mudam |
| TA-112 | P0 | v1 | Tabs como grupos de panes; splits ilimitados com mínimo físico; foco por teclado; zoom | 12 panes numa tab de 1440 pt; ⌘]/⌘[ percorrem todos; ⇧⌘↵ expande e volta sem relançar processo |
| TA-113 | P0 | v1 | Layout, tab ativa e foco persistidos em SQLite com debounce, restaurados ao abrir | Arrastar divisor por 5 s gera ≤ 2 escritas; reabrir mostra as mesmas frações (±1 pt) e o mesmo pane focado |
| TA-114 | P0 | v1 | ⌘W e apagar terminal/sessão com confirmação quando há processo; Force Quit só por ação explícita | Fechar pane com Claude vivo pede confirmação; Cancel não envia sinal; nenhum SIGKILL sem clique em Force Quit |
| TA-115 | P0 | v1 | Overlay de quit com Keep Running / Stop All and Quit… no primeiro ⌘Q (P15); modo accessory; sem helper de login | Com 2 agentes, ⌘Q + Keep Running: sem ícone no Dock, item na barra de menus presente, hooks continuam chegando (notificação de fim de turno aparece) |
| TA-116 | P0 | v1 | Item na barra de menus (03 §17) com contagem, "Needs You", "Working", Open, Stop All, Quit Completely | Com 1 agente em needs input, o ícone mostra "1"; clicar no item abre a janela no pane certo; "Quit Agent Box Completely" tira o ícone e não mata nenhum PTY |
| TA-117 | P1 | v1 | Upgrade com `drainWhenIdle` (mesma major) e compatibilidade N-1 (major nova) | Teste de §1.10 passa; Diagnostics mostra o daemon pendente |
| TA-118 | P1 | v1 | Modo degradado sem aprovação do item de login, com aviso no quit | Negar a aprovação: terminais funcionam; o overlay de quit diz "Agents will stop when you quit" |
| TA-119 | P1 | v1.1 | Grupos de tabs lado a lado por arraste | Arrastar uma tab até a borda direita cria grupo; layout persiste |
| TA-120 | P2 | later | Serializador de células no lugar do replay de bytes | Só se um teste de artefato visual falhar com o ring |

---

## 2. Lançamento de agentes

### 2.1 Modelo: o que foi pedido e como foi lançado

```swift
struct LaunchRequest: Codable, Sendable {      // persistido em terminal.launch_spec_json
  var provider: Provider                        // .claude | .codex | .opencode | .shell | .custom(argv)
  var profileID: LaunchProfile.ID?              // + snapshot dos campos no momento do lançamento
  var cwd: String
  var initialPrompt: String?                    // só no primeiro start
  var mainAgent: CatalogRef?                    // --agent (Claude) / --agent (OpenCode)
  var sessionActivations: [CatalogRef]          // skills, agentes e plugins ativados para esta sessão
  var injections: Set<Injection>                // .activityHooks, .agentBoxMCP, .orchestrationSkill, .usageStatusLine
  var nativeConversation: NativeConversation?   // provider, id, capturedBy, capturedAt
}
```

- `LaunchPlan` (não persistido como contrato) = `argv`, `env` e arquivos de apoio, gerado por `ProviderAdapter.plan(request, capabilities)` a cada start.
- `terminal.resolved_argv_json` guarda o último argv só para diagnóstico. **Nunca** é comparado com o recomputado (fim do bug de `restore`, `audit/02 §2.7`).
- Sem plano revisável, sem hash, sem binding (T14).

### 2.2 Adapters por CLI

Cada adapter declara capabilities verificadas por versão. A detecção roda no onboarding, quando o binário muda (mtime ou `--version`) e em Settings › Agents › "Check Again": resolve o executável (`CLIExecutableResolver` atual, com override por CLI), lê `--version` e faz parse do `--help` (com timeout de 5 s, fora do main). O resultado fica em cache por `(caminho, versão)`. Flag ausente = opção desabilitada na UI com o motivo ("Requires Claude Code ≥ x").

**Claude Code 2.1.302** (conferido no `--help`)

| Uso no app | Flag | Observação |
|---|---|---|
| Prompt inicial | `[prompt]` posicional | Depois de todas as flags |
| ID escolhido pelo app | `--session-id <uuid>` | Sempre em lançamento novo |
| Retomar | `-r/--resume <id>` | Com todas as injeções regeneradas |
| Continuar último do cwd | `-c/--continue` | "Continue Last" no lançador |
| Fork | `--fork-session` (com `--resume`) | v1.1 |
| Nome | `-n/--name <nome>` | Nome da sessão do app; aparece no título |
| Modelo / esforço | `--model`, `--effort low|medium|high|xhigh|max` | |
| Permissões | `--permission-mode acceptEdits|auto|bypassPermissions|manual|dontAsk|plan`, `--dangerously-skip-permissions` | |
| Diretórios extras | `--add-dir` | |
| Hooks, statusLine, deny rules | `--settings <arquivo>` | Mescla com as settings do usuário (verificar: hooks de várias fontes rodam todos) |
| MCP do Agent Box | `--mcp-config <arquivo>` | **Sem** `--strict-mcp-config`: os MCPs do usuário continuam |
| Skills/plugins da sessão | `--plugin-dir <dir|zip>` (repetível) | |
| Agentes da sessão / agente principal | `--agents <json|arquivo>`, `--agent <nome>` | Formato verificado em 2.1.302 (S-08): `mcpServers` de cada subagente é um **array** de `{ "<nome>": {command,args} }` (um objeto `{nome:{…}}` é recusado com `expected array, received object`); `tools` do filho limitado a `mcp__<nome>__*`; nome de servidor único por filho (`agentbox-<runId>-<n>`) |
| Modelo de fallback | `--fallback-model` | Opcional no perfil |
| Não usados | `--bg`, `-w/--worktree`, `--tmux`, `--bare`, `--safe-mode`, `--remote-control` | O daemon e o GitService cobrem; `--remote-control` é later. `--bare` e `--safe-mode` **desligam hooks**: se um perfil (inclusive importado do Orca) trouxer uma delas em `extraArgs`, o perfil mostra o aviso "Activity status is unavailable with --bare" e o terminal fica `unknown` (R3 §1) |

**Codex CLI 0.160.0**

| Uso | Flag | Observação |
|---|---|---|
| Prompt inicial | `[PROMPT]` posicional | |
| Retomar | `codex resume <id> [PROMPT]` | Aceita as mesmas `-c` |
| Continuar último | `codex resume --last` | Filtra por cwd |
| Fork | `codex fork <id>` | v1.1 |
| Modelo / perfil | `-m`, `-p/--profile` | |
| Sandbox / aprovação | `-s read-only|workspace-write|danger-full-access`, `-a on-request|never`, `--dangerously-bypass-approvals-and-sandbox` | |
| Diretórios extras | `--add-dir` | |
| MCP, hooks, overrides | `-c chave=valor` (TOML) | `-c mcp_servers.agentbox.command=…` etc. Hooks por `-c` entram como `untrusted` e só rodam com o trust inline de §3.3.1 (`-c 'hooks.state={…}'`, P18) |
| Scrollback nativo | `--no-alt-screen` | Opção do perfil (padrão desligado) |
| Mensagem para sessão existente | `codex queue --thread <id> --message` | Later (steering) |
| App-server compartilhado | `--no-daemon` | **Padrão do adapter Codex (S-05(c), `docs/evidence/spikes/S-05/README.md`; P18).** O daemon (`codex app-server daemon`) roda com ppid 1 e pgid próprio, socket em `~/.codex/app-server-control/`, fora do grupo do PTY. O adapter passa `--no-daemon` para que a sessão e os `-c` por lançamento fiquem no processo do pane, `kill` do pane encerre o agente e o ID seja capturável. Capability `noDaemon` registrada por versão do Codex (se a versão não aceita a flag, o lançamento segue sem ela e o Diagnostics avisa). A TUI do Codex atualiza `[tui]` em `~/.codex/config.toml` por conta própria a cada lançamento, independente do Agent Box: a regra "o app não escreve em `~/.codex`" vale para o app, não para o Codex |
| Nunca usar | `--dangerously-bypass-hook-trust`, `--worktree`, `--remote` | |

O Codex 0.160 **não** tem `--session-id`. Captura do ID na §2.5.

**OpenCode 1.18.34**

| Uso | Flag |
|---|---|
| Prompt inicial | `--prompt <texto>` |
| Retomar / continuar / fork | `-s/--session <id>`, `-c/--continue`, `--fork` |
| Modelo / agente | `-m provider/model`, `--agent <nome>` |
| Permissões | `--auto` |
| Pasta | `[project]` posicional (o app usa cwd e não passa o posicional) |

OpenCode é cidadão de segunda classe na v1: abre, retoma e recebe prompt; estado de atividade é estimado (§3.3); injeção de MCP/skills é later.

**Shell e comando livre**: `$SHELL -l` (interativo de login, no PTY). "Custom Command" aceita argv sem interpolação (tokenização tipo shell-words, mostrada antes de lançar).

### 2.3 Perfis de lançamento

```
LaunchProfile { id, name, provider, model?, effort?, permission (enum por provider),
                addDirs[], extraArgs[] (tokenizados), env{}, secrets[] (refs), scope: global|project }
```

- Resolução: perfil global padrão do provider → perfil padrão do projeto → escolha no lançador → override por terminal ("Relaunch With…").
- **Padrões herdados do Orca** (importação, §6): Claude `--dangerously-skip-permissions`; Codex `--dangerously-bypass-approvals-and-sandbox` (valores conferidos em `settings.agentDefaultArgs`). Sem Orca, os mesmos padrões são propostos no onboarding com o texto "Agents run without permission prompts (same as Orca). You can change this per profile." e escolha explícita.
- Indicador permanente: ícone `ShieldOff` no header do pane e na tab (03 §4.2), sem cor (02 §1 regra 5), com tooltip `Skip permissions (<flag exata>)`, sempre que o lançamento efetivo pula permissões.
- `extraArgs` que repetem um campo estruturado (ex.: `--model`) geram aviso; o campo estruturado vence.
- Perfis prontos: "Claude · Default", "Claude · Plan", "Codex · Default", "OpenCode · Default", "Shell". Perfis importados do Orca: "Claude · Skip permissions" e "Codex · Bypass approvals", com o detalhe "Imported from Orca" (§6.2; R1 K-31).

### 2.4 Prompt inicial como argumento

- O prompt digitado no composer ou no lançador vai no argv (Claude e Codex posicional, OpenCode `--prompt`). **Nunca** é digitado no PTY (T11).
- Prompt com mais de **16 KiB** (bytes UTF-8), ou que começa com `-`: o app grava `AB/run/launch/<runID>/prompt.md` (`0600`) e passa o argumento `Read and follow the task in <caminho>`. O arquivo some com o diretório do lançamento (§2.8). 16 KiB deixa folga para o `ARG_MAX` somado ao env; um prompt de 40 KB vai para arquivo (AC-308; R1 K-12).
- Anexos (later): o app salva o arquivo e coloca o caminho no prompt.
- O prompt só vai no primeiro start. Resume nunca repete o prompt.

#### 2.4.1 argv: segmentos e como os critérios de aceite verificam

O `LaunchPlan` monta o argv em segmentos, nesta ordem, e grava cada segmento separado em `terminal.resolved_argv_json` (`{"executable":…, "identity":[…], "profile":[…], "injected":[…], "prompt":[…]}`):

| Segmento | Claude | Codex | OpenCode |
|---|---|---|---|
| `executable` | `claude` (caminho resolvido) | `codex` | `opencode` |
| `identity` | `--session-id <uuid>` (novo) ou `--resume <id>` | `resume <id>` (subcomando, no resume) | `-s <id>` (no resume) |
| `profile` | flags do perfil, na ordem do perfil (modelo, esforço, permissão, `--add-dir`, `extraArgs`) | idem | idem |
| `injected` | `--settings`, `--mcp-config`, `--plugin-dir`, `--agents`, cada um apontando para dentro de `AB/run/launch/<runID>/` | `-c …` gerados (§2.8) | — |
| `prompt` | posicional | posicional | `--prompt <texto>` |

Regra dos critérios de aceite (vale para AC-307, AC-309 e os testes de argv de `08 §10` T-15):

1. "argv **exatamente** X" compara `executable + identity + profile + prompt`, **sem** o segmento `injected`. Ex.: AC-307 espera `claude --session-id <uuid> --dangerously-skip-permissions hello` e isso é o que sobra tirando `injected`.
2. O segmento `injected` é verificado à parte: só flags da lista acima, cada caminho dentro do diretório do lançamento, e nenhuma flag fora da allowlist.
3. **Na Fatia 1 não há injeções** (hooks e MCP entram na Fatia 2): o segmento `injected` é vazio e o argv real é literalmente igual ao esperado.
4. "Zero bytes escritos pelo app no PTY" é verificado pelo contador `inputBytesByOrigin` do daemon (§1.3): as origens `0x02`, `0x03` e `0x04` ficam em zero até o primeiro input humano.

### 2.5 ID nativo da conversa

| Provider | Como o app obtém o ID | Quando muda |
|---|---|---|
| Claude | Gera UUID v4 e lança com `--session-id`. Grava em `terminal.native_conversation_id` antes do spawn | `/clear`, `/compact` ou resume que troca o ID: o hook `SessionStart` traz `session_id` e `source`; o app atualiza (`audit/01` E9) |
| Codex | 1º hook `SessionStart` por lançamento (campo `session_id`, verificar); 2º fallback: primeiro `~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl` criado após o spawn cuja linha `session_meta` tem `cwd` igual e `timestamp ≥ spawn − 2 s`; nome em `~/.codex/session_index.jsonl` (`id`, `thread_name`) | Novo `SessionStart` |
| OpenCode | `opencode session list --format json` antes e 5 s depois do spawn; a sessão nova com o mesmo diretório (campos verificar) | Novo poll após `exit` |
| Shell | — | — |

Sem ID capturado, [Resume] vira "Continue Last" (`-c`, `resume --last`, `-c`) com aviso.

### 2.6 Resume, inclusive depois de reboot

- [Resume] (pane encerrado) e "Resume Agents…" (sessão) montam um `LaunchPlan` a partir do `LaunchRequest` persistido, com `nativeConversation` preenchido e **sem** `initialPrompt`.
- Todas as injeções são **regeneradas** no diretório da execução (§2.8): settings de hooks, config MCP, plugin da sessão, JSON de agentes. O Claude não restaura `--settings`, `--mcp-config`, `--plugin-dir` nem `--agents` sozinho (`audit/05` a), então eles sempre voltam no argv.
- O perfil usado é o snapshot do lançamento original, salvo se o usuário escolher "Resume With…" (outro modelo ou permissão, mesmo ID).
- Antes de retomar, o app checa se a conversa já está aberta em outro lugar: Claude via `claude agents --json` (sessões ativas) e via outro terminal do próprio app; Codex/OpenCode só dentro do app. Aberta: oferece "Fork Instead" (v1.1) ou cancelar.
- Painel "Conversations" (03 §10.5; Fatia 2): lista unificada das conversas do projeto atual nos três CLIs, lida só de metadados: `~/.claude/projects/<slug-do-cwd>/*.jsonl` (nome, mtime, primeira mensagem do usuário truncada em 120 caracteres), `~/.codex/session_index.jsonl` + `session_meta.cwd` dos rollouts, `opencode session list --format json`. Nenhum transcript é copiado para o banco.

### 2.7 Sessões limpas (P10)

- "New Clean Session" (⇧⌘N, um clique; P11): cria `~/AgentBox/sessions/<nome>` ou usa uma pasta escolhida ("New Clean Session in Folder…"). Raiz configurável. "Scratch" não é usado em lugar nenhum (P11).
- **Nome automático** (P15): par adjetivo-substantivo em kebab-case, como `quiet-harbor`; o gerador nunca reaproveita uma pasta existente (AC-1102). Com prompt, o título da sessão são as primeiras palavras do prompt como digitadas e a pasta usa o slug (AC-303). Renomear a sessão não renomeia a pasta. O mesmo gerador serve worktrees sem nome.
- Lança exatamente como uma sessão de projeto: mesmo lançador, perfis, injeções, estados e notificações. Recursos de Git (branch, PR, worktree) ficam ocultos. No domínio, `session.kind = clean` (`08 §0`).
- Aparece na seção **"Sessions"** da sidebar (P11; 03).
- **Promover**: "Move to Project…" liga a sessão a um projeto existente **sem mover a pasta** (v1), ou cria um projeto a partir da pasta ("New Project from This Folder", o antigo "Convert to Project"). "Move Folder into Project…" (v1.1) exige todos os terminais parados, move a pasta e avisa: "Conversations started here may not resume after the move" (o Claude indexa transcripts pelo cwd; verificar se `--resume <id>` funciona após mover, V8).
- "Initialize Git Here" transforma em projeto Git (v1.1).

### 2.8 Injeção por lançamento, sem tocar config global

Diretório por execução: `AB/run/launch/<runID>/` (`0700`), criado no start, **apagado no `exit`** do processo (limpeza que continua após erro) e varrido no boot (tudo que não pertence a sessão viva). Cada start ou resume cria um `runID` novo, então ele faz o papel de "tentativa". Sem cópia de conteúdo de skill, sem hash.

**Fatia 1**: nenhuma injeção (o estado do agente aparece como `unknown`, §3.1). A tabela abaixo entra a partir da Fatia 2.

| Injeção | Claude | Codex | OpenCode |
|---|---|---|---|
| Hooks de atividade (§3) | `--settings settings.json` com `hooks` apontando para `"<bundle>/Contents/MacOS/agentbox" hook --provider claude --event <Evento>` | Estratégia da §3.3.1 (P18: hooks por `-c` com *trust* inline `-c 'hooks.state={…}'`, sem gravar em `~/.codex`; fallback: tail do rollout `estimated`). Nunca `--dangerously-bypass-hook-trust` | — (estimado) |
| MCP do Agent Box | `--mcp-config mcp.json` (`agentbox mcp --run <runID>`) | `-c mcp_servers.agentbox.command="…"`, `-c mcp_servers.agentbox.args=[…]` (v1.1, R7.4) | later |
| Skill de orquestração do app | plugin `agentbox` em `--plugin-dir` | later | later |
| Skills/agentes da sessão | `--plugin-dir` (plugin gerado) e `--agents agents.json` | §4.3 | `--agent` |
| Medidor de uso | `statusLine` em `--settings` que chama o comando do usuário, repassa o mesmo JSON e devolve a mesma saída (status bar, 03 §5) | lido dos rollouts | — |
| Bloqueio da skill `agentbox` antiga | `permissions.deny` em `--settings` (§2.9) | — | — |

Regras:

- Nunca escrever em `~/.claude/settings.json`, `~/.claude.json`, `~/.codex/config.toml`, `~/.codex/hooks.json`, `~/.config/opencode/*`, nem no repositório do usuário.
- `notify` do Codex fica intocado no `config.toml` (ocupado pelo Codex Computer Use). Override por lançamento (`-c notify=…`) só como alternativa da §3.3.1, e encadeando o comando original.
- Os hooks globais do Orca continuam instalados e saem cedo porque o env do Agent Box não tem `ORCA_*` (§1.7).
- Uma injeção que falha ao gerar (ex.: binário `agentbox` ausente) não impede o lançamento: o terminal abre sem ela e o pane mostra "Activity tracking unavailable" com o motivo.

### 2.9 Coexistência com o Orca e com a skill global `agentbox`

- **Orca**: os dois apps rodam juntos. O Agent Box não escreve nada do Orca, remove `ORCA_*` do env e avisa antes de remover um worktree que o Orca também lista (§5.2, §6.4). Os dois podem ter terminais no mesmo worktree; o app avisa, não bloqueia.
- **Skill `agentbox` antiga** (`~/.claude/skills/agentbox/SKILL.md`, e qualquer skill cuja descrição case com "spawn … subagents … Docker"): detectada no onboarding e no catálogo. Banner: "A global *agentbox* skill competes with Agent Box computers." Opções:
  Texto do aviso (03): `A global "agentbox" skill is installed and may compete with Agent Box tools.` Opções canônicas (R1 K-40):
  1. **Block in Agent Box** (padrão): `--settings` com `permissions.deny: ["Skill(agentbox)", "Bash(agentbox *)"]` (verificar a sintaxe `Skill(...)` e que deny vale com `--dangerously-skip-permissions`, V3; se não valer, cair para a opção 2 com explicação). Antes da Fatia 2, quando ainda não há injeções, a opção fica indisponível com o motivo.
  2. **Disable Globally…**: move a pasta para `~/.claude/skills/.disabled/agentbox` com backup e confirmação; afeta Orca e terminais externos (dito no diálogo).
  3. **Keep**: nada muda; o banner some.
  - `Redirect` (skill-shim global, 07) fica fora da v1: escreve fora do app (R1 D-11).
- **Claude `--bg` / `claude agents`**: o app não usa, mas lê `claude agents --json` só para detectar conversa aberta fora (§2.6).

### 2.10 Requisitos — lançamento

| ID | P | Versão | Requisito | Aceite |
|---|---|---|---|---|
| TA-201 | P0 | v1 | `LaunchRequest` persistido e `LaunchPlan` gerado a cada start por adapter; sem hash nem comparação de argv | Mudar a versão do Claude entre dois starts não invalida terminais salvos; teste unitário de argv por perfil para os 4 providers |
| TA-202 | P0 | v1 | Detecção de CLI (executável, versão, `--help`) com cache e capabilities por versão; flag ausente desabilita a opção com motivo | Com um `claude` falso sem `--effort`, a opção some do perfil com "Not supported by this version"; probe não roda no main |
| TA-203 | P0 | v1 | Adapters Claude, Codex, OpenCode e shell conforme §2.2; nenhum provider fica "export only" | Criar sessão com cada provider abre o pane já rodando (P9) em ≤ 1 s até o primeiro byte |
| TA-204 | P0 | v1 | Perfis com modelo, esforço, permissão, add-dirs, extraArgs, env e segredos; resolução global → projeto → lançador → terminal | Teste unitário da resolução; "Relaunch With…" troca o modelo e mantém o ID |
| TA-205 | P0 | v1 | Padrões sem permissão herdados do Orca, com indicador `ShieldOff` permanente | Após importar, um Claude novo tem `--dangerously-skip-permissions` no argv e o `ShieldOff` visível no header do pane e na tab |
| TA-206 | P0 | v1 | Prompt inicial como argumento; fallback por arquivo para > 16 KiB ou início com `-`; argv verificado por segmentos (§2.4.1) | Prompt com aspas, quebras de linha, emoji e `$(rm -rf ~)` chega literal; nenhum byte do prompt passa pelo input do PTY |
| TA-207 | P0 | v1 | Claude sempre com `--session-id` gerado pelo app; troca de ID por `/clear` atualizada via `SessionStart` | Após `/clear`, o terminal guarda o ID novo e [Resume] abre a conversa nova |
| TA-208 | P1 | v1 | Captura de ID do Codex (hook, depois rollout) e do OpenCode (`session list`) | Teste de contrato com os CLIs reais (§7) preenche o ID em ≤ 10 s |
| TA-209 | P0 | v1 | Resume regenera hooks, MCP, plugin e agentes; funciona depois de reboot | E2E: lançar Claude com skill de sessão, matar o daemon, [Resume]: o hook de atividade volta a chegar e a skill aparece em `/skills` |
| TA-210 | P1 | v1 | "Resume Agents…" (overlay "Resume interrupted agents?") com lista e checkboxes, nunca automático | Depois de reboot simulado, nenhum agente sobe sozinho; o diálogo lista CLI, modelo e última mensagem |
| TA-211 | P1 | v1 | Painel "Conversations" (03 §10.5) com histórico dos três CLIs por projeto, só metadados | Lista mostra conversas Claude e Codex do cwd com título e data; o banco não contém texto de transcript além da primeira linha truncada |
| TA-212 | P1 | v1 | Guarda contra conversa aberta em dois lugares | Retomar um ID Claude que está ativo em outro terminal mostra o aviso e não lança |
| TA-213 | P0 | v1 | Sessões limpas em um clique, mesma experiência de lançamento, "Move to Project…" sem mover | "New Clean Session" cria a pasta com nome `quiet-harbor`-style, abre o agente e não mostra UI de Git; anexar a um projeto mantém terminais vivos |
| TA-214 | P1 | v1.1 | "Move Folder into Project…" com terminais parados e aviso de resume | Mover com terminal vivo é recusado |
| TA-215 | P0 | v1 | Injeções por lançamento em `AB/run/launch/<runID>/` (a partir da Fatia 2), apagadas no exit e no boot | Depois de 20 lançamentos encerrados, o diretório está vazio; nenhum arquivo global dos CLIs mudou (checksum antes/depois em teste) |
| TA-216 | P0 | v1 | Falha de injeção não bloqueia o lançamento e é visível no pane | Remover o helper `agentbox`: o Claude abre e o pane mostra "Activity tracking unavailable" |
| TA-217 | P0 | v1 | Coexistência com Orca: env sem `ORCA_*`, nenhuma escrita em arquivos do Orca | Com o Orca aberto, terminal do Agent Box no mesmo worktree não muda o estado de nenhum pane do Orca |
| TA-218 | P0 | v1 | Detecção da skill `agentbox` e opções Block in Agent Box / Disable Globally… / Keep | Com "Block in Agent Box", pedir "spawn 2 subagents for Phoenix and Austin" num Claude do app não executa o CLI antigo |
| TA-219 | P1 | v1.1 | Fork de conversa (`--fork-session`, `codex fork`, `--fork`) | Fork cria terminal novo com ID novo e a origem intacta |
| TA-220 | P2 | later | MCP e skills por lançamento no OpenCode (`OPENCODE_CONFIG` ou equivalente, verificar) | — |

---

## 3. Estado de atividade, notificações e inbox

### 3.1 Estados

Estados canônicos de **atividade do agente** (01 §6.3 mais `blocked`; R1 K-78; nomes Swift e de banco em `08 §0`). O estado do **processo** (`launching`, `running`, `exited`, `killed`, `failedToStart`, `interrupted`, `notStarted`…) é outra máquina, de 01 §6.2, e aparece ao lado.

| Estado | Significado | Indicador (DS §2.6; motion 04 M-4xx) |
|---|---|---|
| `starting` | Spawn feito, sem primeiro evento | Ignição só se passar de 300 ms |
| `idle` | Pronto, sem turno em andamento: `done` visto há 30 min, ou agente recém-iniciado sem prompt (após `SessionStart`) | — |
| `working` | Turno em andamento | Spinner |
| `needsInput(kind)` | `question`, `permission` ou `other` | Balão `?` laranja + "Needs input" |
| `waitingOnSubagents(n)` | Turno do pai acabou, mas há filhos vivos | Glifo `Activity` estático + "Waiting on 2 subagents" |
| `done` | Turno acabou; **unread** até o usuário ver o pane | Check; negrito enquanto não lido |
| `failed(reason)` | `StopFailure` (ex.: limite de uso) ou exit ≠ 0 com agente | Bolinha vermelha + motivo |
| `blocked` | Só subagente: nota `BLOCKED` no diário (07) | Vermelho, como em 02 |
| `interrupted` | O processo morreu fora do controle do usuário (reboot, crash do daemon) | Bolinha `#a1a1a1`, sem animação |
| `unknown` | Sem hooks (Fatia 1, `--bare`, Codex sem estratégia, helper ausente) ou hooks calados além da janela | "Status unavailable" (tooltip com o motivo) |
| `stalled` (v1.1) | Subagente sem chamada de ferramenta nem nota há 10 min | 07 |

`estimated` não é estado: é uma **flag** sobre o estado, para OpenCode, shell (OSC 133) e Codex por rollout. Mesmo glifo, com "estimated" no tooltip.

**Fatia 1**: sem hooks, todo agente aparece como `unknown` / "Status unavailable" e o card mostra o estado do processo (R3 §4.1).

Agregação (card de sessão, menu bar, Dock): a de 01 §6.3.

### 3.2 Transporte dos eventos

- Hooks **command** chamando o helper assinado: `"<bundle>/Contents/MacOS/agentbox" hook --provider <claude|codex> --event <Evento>` (comando canônico, `08 §0`). Sem `python3` (resolve `audit/09` N15).
- O helper lê o JSON do stdin, sai em silêncio se `AGENTBOX_RUN_ID` não existir, envia um frame ao serviço `hook` de `AGENTBOX_APP_SOCK` (`AB/run/app.sock`) com timeout de **200 ms** e, se o app não responder, faz append em `AB/run/spool/hooks/<runID>.jsonl` (`0600`; limite 4 MiB por arquivo; acima disso descarta os mais antigos e grava um marcador `truncated`). Escreve `{}` no stdout e sai com 0, p95 ≤ 30 ms (`08 AR-707`). Nunca bloqueia nem muda o comportamento do agente. `timeout` do hook nas settings: 5 s.
- O app drena o spool no boot, ao reconectar e enquanto roda (kqueue no diretório, nunca polling; `08 AR-109`), avançando o cursor **mesmo** em linha inválida (linha registrada como erro; corrige `audit/02` #11). O "cursor" é a existência do arquivo: o leitor toma `flock`, renomeia `<runID>.jsonl` para `<runID>.jsonl.<id>.draining`, lê, e apaga o renomeado quando todas as linhas foram processadas (o escritor confere o inode depois do lock e reabre se o arquivo foi renomeado, então nada se perde nem se lê duas vezes). Um `.draining` que sobrou por crash é relido no boot: a ingestão é idempotente pelo `event_id` do envelope. Erro transitório do banco mantém o arquivo; linha inválida ou com run id que não é UUID é pulada. `--provider` assume `claude` e `--event` assume `hook_event_name` do payload; o helper reduz o payload antes de enviar ou gravar (nunca leva o prompt nem `tool_response`).
- `AGENTBOX_PANE_ID` e `AGENTBOX_RUN_ID` só correlacionam evento ↔ terminal e execução. Não são autenticação (`audit/09 §2.7`). Não existe `AGENTBOX_HOOK_TOKEN`.
- Hooks `type: "http"` ficam para o modo isolado (v1.1, 07; `http://egress:8790/hooks/<provider>`), porque no host o app pode estar fechado e eventos HTTP se perderiam.
- Eventos são gravados em `agent_event(run_id, seq, type, payload_json, at)` com retenção de **30 dias e 10 mil eventos por execução** (`08 AR-311`). O payload guardado é reduzido aos campos da §3.3.

### 3.3 Mapeamento por CLI

**Claude** (eventos registrados por lançamento): `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `SessionEnd`.

| Evento | Transição | Campos usados |
|---|---|---|
| `SessionStart` | → `idle`; atualiza ID nativo | `session_id`, `source`, `transcript_path`, `cwd` (V1 confirmado em 2.1.302, S-05(a): hooks de `--settings` **somam** com os globais do Orca e de projeto, não os substituem; payloads em `docs/evidence/spikes/S-05/`. `Notification` não foi verificado: em `-p` não dispara, e a TUI grava confiança de pasta em `~/.claude.json`; V13 segue aberto) |
| `UserPromptSubmit` | → `working` | — |
| `PreToolUse` | → `working`; subtítulo "Running Bash", "Editing x.swift"; se `tool_name` for a ferramenta de pergunta ao usuário (`AskUserQuestion`, verificar nome) → `needsInput(question)` | `tool_name`, alvo curto |
| `PostToolUse` / `PostToolUseFailure` | → `working` (sai de `needsInput(question)`) | `tool_name` |
| `PermissionRequest` | → `needsInput(permission)` | `tool_name`, resumo |
| `Notification` | `permission_prompt` → `needsInput(permission)`; `idle_prompt` sem turno ativo → mantém `done`; outros → `needsInput(other)` | `notification_type`, `message` |
| `Stop` | Filhos vivos > 0 → `waitingOnSubagents(n)`; senão → `done` | `last_assistant_message` (verificar; fallback §3.4) |
| `StopFailure` | → `failed(reason)` | erro/motivo (ex.: limite de uso) |
| `SubagentStart` / `SubagentStop` | contador de filhos vivos por `agent_id`; último `SubagentStop` com pai em `waitingOnSubagents` → `done` | Confirmados em 2.1.302 (S-08): `agent_id`, `agent_type`; no `SubagentStop`, `last_assistant_message`, `agent_transcript_path`. Hooks de `PreToolUse`/`PostToolUse` **dentro do filho** trazem `agent_id`, `agent_type` e, para ferramenta MCP, `mcp_server{name, source:"agent"}`; os do pai (ferramenta `Agent`) não trazem `agent_id` e têm `tool_use_id`. O filho é identificado por `agent_id`/`agent_type`; o `agent_id` é gerado pelo Claude a cada execução e só serve de correlação, nunca de autenticação (07) |
| `SessionEnd` | Aguarda `exit` do daemon | `reason` |
| `exit` do daemon | `code == 0` → `exited`; ≠ 0 → `failed("exited with 1")` | — |

**Codex 0.160** (hooks estáveis; eventos conferidos no `hooks.json` existente: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SubagentStart`, `SubagentStop`): mesmo mapeamento, sem `Notification`/`StopFailure`. Falha de turno vem do rollout (`rate_limits.primary.used_percent = 100`, erros) lido por tail do arquivo do terminal. Campos exatos dos payloads: verificar (§7).

#### 3.3.1 Codex: hooks exigem *trust* por hash; decisão P18 (opção B) e estratégia

**O problema** (R3 §1, conferido na máquina): os hooks do Codex 0.160 só rodam depois de "confiados". O Codex grava a confiança por hash em `~/.codex/config.toml` (`[hooks.state."<arquivo>:<evento>:i:j"] trusted_hash = "sha256:…"`).

**O que o spike S-05 mediu** (2026-10-17, Codex 0.160.0, `docs/evidence/spikes/S-05/README.md`): hooks de `-c` entram como `source=sessionFlags`, chave `/<session-flags>/config.toml:<evento>:i:j`, `untrusted`, e **não executam**. O `currentHash` é estável para o mesmo comando e `timeout` (não depende de cwd nem de repetição) e muda se qualquer um dos dois mudar. O trust pode ser fornecido **no próprio lançamento**, sem escrever em `~/.codex/config.toml`: `-c 'hooks.state={"<chave>"={trusted_hash="<hash>"}}'` (a forma de tabela inline funciona; a forma pontilhada `hooks.state."<chave>".trusted_hash=…` é ignorada). Com isso `SessionStart` (traz `transcript_path`, o rollout, já no primeiro evento) e `UserPromptSubmit` (traz `turn_id`, `prompt`) dispararam na TUI e no `codex exec`. O `permission_mode` do payload não é confiável para o estado (veio `bypassPermissions` com `-s read-only`). **Pendente (cota do Codex esgotada até 22/10/2026):** payloads de `PreToolUse`, `PostToolUse`, `Stop`/`last_assistant_message` e `SubagentStart/Stop`; reexecutar `codex_trusted_run.py` do spike depois disso.

**Decisão (P18, D-Codex-1 = opção B).** O app passa o trust dos **próprios** hooks por `-c 'hooks.state={…}'` inline, a cada lançamento. Isto não usa `--dangerously-bypass-hook-trust` (vale só para os hooks listados, por hash), não grava nada em `~/.codex` e dispensa clique, mas é auto-confiança declarada: o hash é o do hook que o app mesmo gera. O dono aceitou isso em P18 (delegado). Fica proibido: gravar `trusted_hash` no `config.toml`, `--dangerously-bypass-hook-trust` e `CODEX_HOME` temporário.

**Procedimento por lançamento do adapter Codex** (com `--no-daemon`, §2.2):

1. Os hooks do helper são sempre os mesmos: `"<bundle>/Contents/MacOS/agentbox" hook --provider codex --event <Evento>`, `timeout=5`, **sem run id nem pane no comando** (correlação só por env, §1.7). Assim o hash não muda entre execuções nem entre versões do app apenas por caminho.
2. O app sobe um app-server de sonda (`codex app-server --listen stdio://`, ~0,3 s) com os mesmos `-c hooks.<Evento>=[…]` e chama `hooks/list` para ler o `currentHash` de cada hook; guarda em cache por (versão do Codex, hash da definição) e só refaz a sonda quando a definição ou a versão mudam.
3. Lança o Codex com os `-c hooks.<Evento>=[…]` e com `-c 'hooks.state={…}'` contendo o `trusted_hash` de cada chave `/<session-flags>/config.toml:<evento>:i:j`.
4. **Fallback:** se a sonda falhar, o trust não entrar (o `hooks/list` pós-lançamento mostra `untrusted`) ou a versão do Codex mudar o formato, o terminal usa **tail do rollout** (`~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl`, como em §2.5), só leitura, estado marcado `estimated`, e o Diagnostics mostra o motivo. O rollout continua sendo o baseline sempre disponível.
5. O `Stop` do Codex só fecha o turno se o payload real for confirmado pela reexecução pendente; até lá, `done` do Codex vem do rollout (`estimated`).

Alternativas avaliadas no spike, sem compromisso: `-c notify=[…]` por lançamento (só fim de turno; o `notify` global do Computer Use é substituído, não encadeado, a menos que o helper o chame); app-server JSON-RPC (`hooks/list`, `thread/*`; viável para sonda, contra P9 como transporte do agente).

**Fatias.** Fatia 1: nenhum hook; Codex aparece `unknown` como todos os agentes. Fatia 2: rollout `estimated` sempre ativo + hooks `-c` com trust inline (P18).

Nenhum caminho usa `--dangerously-bypass-hook-trust` nem grava em `~/.codex/*` pelo app.

**OpenCode**: `estimated`. `working` quando há saída nos últimos 2 s; `done (estimated)` após 5 s sem saída depois de um Enter do usuário; bell → `needsInput(other, estimated)`. Eventos do `opencode serve` ficam para later.

**Shell**: OSC 133 (`C` → `working`, `D;status` → `done`/`failed`); sem OSC 133, só `exited`. Bell em pane não focado → unread.

### 3.4 Última mensagem

- Fonte: `last_assistant_message` do `Stop` (Claude) e do `Stop` do Codex (verificar); fallback: ler só o final do `transcript_path` (Claude) ou do rollout (Codex), no máximo 256 KiB, e pegar a última mensagem do assistente.
- Sanitização: tira ANSI e caracteres de controle, junta espaços, corta em 500 caracteres para o banco. A sidebar mostra uma linha; o hover mostra o texto guardado.
- Pedidos de permissão mostram "Wants to run: `git push origin …`" no lugar da última mensagem.

### 3.5 Notificações do sistema e badge

- `UNUserNotificationCenter`; permissão pedida no onboarding com uma frase do porquê. Depende de assinatura estável (T4).
- **Quando**: entrada em `needsInput`, `done` e `failed` (deduplicado por terminal e turno). Settings › Notifications: um toggle por tipo (Needs input: on, com som; Finished: on, sem som; Failed: on; `Terminal bell`: off) e "Suppress when the session is visible" (ligado) (03 §14; R1 K-52).
- **Supressão**: não notifica se a janela é key e o pane do evento está visível.
- **Formato** (`audit/04 §5.4`): título `"{project} / {session} — {Agent} {status}"`, com `status` em `needs input`, `finished`, `failed` (ex.: "rti-platform / stacktax-pr-bronze — Claude finished"); computador: `"{session} — {computer} needs you"`, corpo `<Kind> on <host>` (07 CS-433), corpo = última mensagem ou pedido de permissão. `userInfo = {terminalID, sessionID}`. `threadIdentifier` = sessão (agrupa no Notification Center).
- **Clique**: ativa o app (sai do modo accessory, se for o caso), seleciona projeto, sessão e tab, foca o pane e dispara o rim flash. Marca o item como lido.
- **Badge do Dock**: `NSApp.dockTile.badgeLabel` = número de AttentionItems de prioridade 1–2 não resolvidos (01 §5.12): terminais em `needsInput`, `failed` não lidos e pedidos de ajuda de computadores (07). Some quando zera. Em modo accessory o número vai para o item da barra de menus.
- v1.1: responder pela notificação ("continue") via colagem explícita (R6.7).

### 3.6 Inbox e unread

- **Unread**: `done`, `failed` e bell viram não lidos até o pane ficar visível com a janela key por 1 s. A tab ganha ponto âmbar; a linha da sidebar fica em negrito. Ações "Mark as Read" / "Mark as Unread" na linha.
- **Inbox** (v1): item de nav da sidebar com contagem (⇧⌘I; 03 §2.3 e §9.1); feed agrupado em `Needs You · Working · Done · Earlier`, cada item com tempo relativo e última mensagem; clique vai ao pane. "Mark All as Read". "Next Needing Attention" (atalho em 03 §21) percorre `needsInput` por ordem de espera.
- **"Since you were away"** (v1.1, R2.3): ao voltar depois de > 30 min sem a janela key (ou ao reabrir o app), a Inbox abre um resumo do intervalo: turnos concluídos, perguntas, falhas, mudanças de PR/checks (§5) e eventos de computadores e uso de proxy quando o provedor informar (07; P13), agrupados por sessão.

### 3.7 Requisitos — estado de atividade

| ID | P | Versão | Requisito | Aceite |
|---|---|---|---|---|
| TA-301 | P0 | v1 | Máquina de estados da §3.1 e agregação por precedência | Teste unitário com sequências reais de eventos (fixtures gravadas dos CLIs) cobre todas as transições |
| TA-302 | P0 | v1 | Helper `agentbox hook` assinado, sem Python, com spool quando o app está fechado | Com o app em "Quit Completely", um turno do Claude termina; ao reabrir, a sessão mostra `done` com a última mensagem e o horário certo |
| TA-303 | P0 | v1 | Hooks do Claude por `--settings`, nunca globais; helper inerte sem `AGENTBOX_RUN_ID` | Checksum de `~/.claude/settings.json` igual antes e depois; um `claude` aberto no Terminal.app não gera eventos no app |
| TA-304 | P0 | v1 | Estado `waitingOnSubagents` quando o pai para com filhos vivos | Pedir ao Claude dois subagentes em background: o pai fica "Waiting on 2 subagents" até o último `SubagentStop`, depois `done` |
| TA-305 | P0 | v1 | `needsInput` por permissão e por pergunta | Claude em `manual` pedindo para rodar `ls` vira `needsInput(permission)` em ≤ 1 s; aprovar volta a `working` |
| TA-306 | P0 | v1 | Última mensagem por terminal na sidebar (uma linha, hover com o texto) | Depois de um turno, a linha mostra o começo da resposta, sem ANSI |
| TA-307 | P1 | v1 | Estado do Codex conforme §3.3.1: rollout (`estimated`) como baseline; hooks por lançamento com trust inline `-c 'hooks.state={…}'` e `--no-daemon` (P18, S-05); nenhuma escrita do app em `~/.codex` | Num `codex` lançado pelo app, um turno mostra `working` e depois `done`; checksum de `~/.codex/config.toml` e `hooks.json` igual antes e depois |
| TA-308 | P1 | v1 | Estado estimado para OpenCode e shell (OSC 133), marcado como estimado | Shell com OSC 133: `sleep 2` mostra working e depois done; tooltip diz "estimated" no OpenCode |
| TA-309 | P0 | v1 | Notificações com formato, supressão, toggles e clique levando ao pane | Com o app em segundo plano, fim de turno gera notificação; clicar foca o pane certo com rim flash; com o pane visível e a janela key, não há notificação |
| TA-310 | P0 | v1 | Badge do Dock e contagem no item da barra de menus | 2 agentes em needs input → badge "2"; ver os dois panes zera |
| TA-311 | P0 | v1 | Unread por pane/tab/linha, Inbox com feed e "Mark All as Read" | Bell num pane oculto marca a tab; abrir o pane limpa |
| TA-312 | P1 | v1.1 | Inbox "Since you were away" com eventos de agentes, PR/checks e computadores | Depois de 1 h fora, a Inbox lista o que mudou, agrupado por sessão |
| TA-313 | P1 | v1 | Retenção de `agent_event` (30 dias e 10 mil eventos por execução) e drenagem do spool tolerante a linha inválida | Teste: linha corrompida no spool não trava a leitura das seguintes |
| TA-314 | P2 | v1.1 | Responder pela notificação via colagem explícita | — |

---

## 4. Biblioteca (agentes, skills, plugins)

Escopo v1: **catálogo só leitura** das fontes nativas, ativação por sessão (aditiva) e "Open in Editor". Criar/editar com backup: v1.1. Memória própria do app: fora (T14).

### 4.1 Fontes indexadas por referência

| Fonte | Caminho | Formato | Clientes que leem nativamente | Na máquina hoje |
|---|---|---|---|---|
| Agentes Claude (usuário) | `~/.claude/agents/**/*.md` | Markdown + frontmatter (`name`, `description`, opcionais `tools`, `model`, `skills`, `mcpServers`…) | Claude | 13 |
| Agentes Claude (projeto) | `<repo>/.claude/agents/**/*.md` | idem | Claude | por projeto |
| Skills Claude (usuário) | `~/.claude/skills/<nome>/SKILL.md` (e `.zip`) | pasta com `SKILL.md` | Claude | 133 entradas |
| Skills Claude (projeto) | `<repo>/.claude/skills/` | idem | Claude | por projeto |
| Plugins Claude | `~/.claude/plugins/installed_plugins.json` → `agents/`, `skills/`, `commands/` de cada plugin | plugin | Claude (namespaced `/plugin:skill`) | 2 (`swift-lsp`, `vercel`) |
| Skills compartilhadas | `~/.agents/skills/`, `<repo>/.agents/skills/` | pasta com `SKILL.md` | Codex (Claude: verificar) | ~30 |
| Agentes Codex | `~/.codex/agents/*.toml` (`name`, `description`, `developer_instructions`) | TOML | Codex | 12 |
| Skills Codex (legado) | `~/.codex/skills/` | pasta | Codex antigo | 3 |
| OpenCode | `~/.config/opencode/opencode.jsonc` (chave `agent`), pastas de agentes do OpenCode (verificar caminho) | JSON/MD | OpenCode | — |
| Instruções | `~/.claude/CLAUDE.md`, `<repo>/CLAUDE.md`, `<repo>/AGENTS.md`, `~/.codex/AGENTS.md` | Markdown | respectivos | só exibição na v1 |
| Só no app (v1.1) | `AB/library/agents/*.md`, `AB/library/skills/<nome>/` | formato Claude | via injeção | — |

- Índice em SQLite `catalog_item(source, kind, name, description, path, mtime, sha256 do arquivo principal, clients[], scope, frontmatter_json reduzido)`. Conteúdo lido sob demanda. Nada é copiado.
- FSEvents por fonte com debounce de 1 s. Fontes de projeto entram quando o projeto é aberto.
- Frontmatter inválido não derruba a fonte: o item aparece com "Invalid frontmatter" e a linha do erro.
- `.zip` de skill aparece como "Packaged skill (.zip)", sem ativação na v1.
- O item mostra em quais clientes está disponível (ícones) e, no terminal focado, se está ativo e por quê ("Always on (global)", "Added to this session", "Not available in Codex").

### 4.2 Ativação

| Item | Claude | Codex | OpenCode |
|---|---|---|---|
| Global (usuário/projeto/plugin instalado) | Sempre ativo pelo próprio CLI; o app só mostra | Sempre ativo (agentes `.toml`, `~/.agents/skills`) | Sempre ativo (config) |
| Skill ativada na sessão | Plugin gerado por lançamento `AB/run/launch/<runID>/plugin-session/` com `.claude-plugin/plugin.json` (`name: "agentbox-session"`) e `skills/<nome>` como symlink para a pasta de origem (verificar que o Claude segue symlink; senão, cópia por lançamento sem hash) → `--plugin-dir`. Invocação `/agentbox-session:<nome>` | Não suportado na 0.160 sem escrever em pasta lida pelo Codex (verificar `-c` para caminhos de skills). A UI diz "Not available in Codex" | later |
| Agente ativado na sessão (subagente) | `--agents agents.json` gerado do frontmatter + corpo (`description`, `prompt`, `tools`, `model`, `skills`, `mcpServers` como **array**, S-08) | Agentes só via `~/.codex/agents` (verificar override por `-c`) | config por lançamento (later) |
| Agente principal | `--agent <nome>` | — | `--agent <nome>` |
| Plugin ativado na sessão | `--plugin-dir <pasta|zip>` | — | — |
| Desligar um item global só numa sessão | Não suportado de forma seletiva (o `--disable-slash-commands` desliga todas as skills). A UI diz isso em vez de prometer (R9.1). Exceção: bloqueio por `permissions.deny` (§2.9) | — | — |

Regras de produto:

- Ativação de sessão vale para o **próximo lançamento** do terminal. O painel mostra "Applies on next launch" e oferece [Relaunch With Resume].
- Agent teams do Claude: os lançamentos do app não ligam `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` (o Orca do dono está com `claudeAgentTeamsMode: off`); se o env do usuário ligar, a UI avisa que subagentes nomeados podem virar teammates e ignorar `mcpServers` (`audit/08` C7).
- A skill de orquestração e o MCP do computador entram pelos mecanismos da §2.8; o preset "Web scraping" fixo no código sai (`audit/02` #5). Um agente da biblioteca pode declarar o MCP do Agent Box em `mcpServers` (v1.1, R9.3).

### 4.3 Criar e editar (v1.1)

- **New Agent**: nome, descrição, modelo, ferramentas, skills, MCP, instruções. Escopo: User (`~/.claude/agents/<nome>.md`), Project (`<repo>/.claude/agents/<nome>.md`) ou Agent Box only (`AB/library/agents/`, injetado por `--agents`). Checkbox "Also create Codex agent" gera `~/.codex/agents/<nome>.toml` (`name`, `description`, `developer_instructions` = corpo; campos sem equivalente listados no diálogo como "not converted").
- **Edit Skill / Edit Agent**: editor de texto simples no painel direito ou "Open in Editor" (Cursor/VS Code/Zed configurável). Antes de salvar: diff, backup em `AB/backups/library/<timestamp>/<caminho relativo>`, aviso "Used by 3 running terminals · applies on next launch". "Revert" usa o backup.
- Escrita em `~/.claude` e `~/.codex` só por ação explícita, com diff e backup (R9.4). Nunca durante lançamento.

### 4.4 Conflitos

- Mesmo nome em mais de uma fonte: o catálogo agrupa e marca a vencedora pela precedência do cliente (Claude: managed > `--agents` > projeto > usuário > plugin; Codex: projeto > usuário, verificar). As perdedoras aparecem como "Shadowed by …".
- Skill de plugin é namespaced; não conflita com skill de mesmo nome.
- Espelhos `.md` ↔ `.toml` divergentes (nome igual, descrição ou instruções diferentes): lint P2 "Out of sync with Codex agent".
- Descrição que concorre com ferramentas do app (caso `agentbox`): §2.9.

### 4.5 Requisitos — biblioteca

| ID | P | Versão | Requisito | Aceite |
|---|---|---|---|---|
| TA-401 | P1 | v1 | Catálogo das fontes da §4.1 por referência, com índice SQLite e FSEvents | Abre com 13 agentes Claude, 12 Codex, 133 skills Claude e ~30 compartilhadas; criar um `.md` em `~/.claude/agents` aparece em ≤ 2 s; o banco não contém corpo de skill |
| TA-402 | P1 | v1 | Disponibilidade por cliente e estado no terminal focado ("Always on", "Added to this session", "Not available in Codex") | Selecionar um terminal Codex marca skills Claude-only como indisponíveis |
| TA-403 | P1 | v1 | Ativar skill/agente/plugin só nesta sessão (Claude) via plugin gerado, `--agents` e `--plugin-dir` | Ativar `webscraping-expert` numa sessão: o Claude dessa sessão a lista em `/skills`; outra sessão não |
| TA-404 | P1 | v1 | Agente principal por terminal (`--agent` no Claude e no OpenCode) | Lançar com agente "qa-engineer" faz o Claude responder com o papel desse agente |
| TA-405 | P1 | v1 | Mensagens honestas sobre o que não é suportado (desligar global por sessão; skills no Codex) | Nenhum toggle aparece para ação que o CLI não suporta |
| TA-406 | P1 | v1 | Conflitos de nome com precedência e "Shadowed by" | Agente de projeto com o nome de um de usuário aparece como vencedor |
| TA-407 | P1 | v1 | Exibir `CLAUDE.md`/`AGENTS.md` global e do projeto (só leitura) com "Open in Editor" | — |
| TA-408 | P1 | v1.1 | Criar agente nos formatos nativos, com espelho Codex opcional | Criar "permit-portal-scout" gera o `.md` e o `.toml` válidos; `claude agents`/Codex o listam |
| TA-409 | P1 | v1.1 | Editar skill/agente com diff, backup, aviso de uso e Revert | Editar e reverter restaura o arquivo byte a byte |
| TA-410 | P2 | later | Lint da biblioteca (frontmatter, referências quebradas, espelhos divergentes) e conversor Claude ↔ Codex ↔ OpenCode | — |
| TA-411 | P2 | v1 (Fatia 4) | "Insert Skill/Agent…" na palette (03 §8): insere `/agentbox-session:<nome>` ou a menção do agente no prompt do pane focado, por colagem com clique e **sem Enter** (T11, origem `0x02`) (R2 SEM #1; proposta, 03 desenha) | Escolher uma skill na palette deixa o texto no prompt do Claude sem enviar |
| TA-412 | P2 | later | Visualizar a memória automática do Claude, renomear a conversa nativa e promover uma execução a agente salvo (R2 SEM #9, #16, #17) | — |

---

## 5. Git e GitHub

### 5.1 Projetos

- **Project** = repositório Git (raiz por `git rev-parse --show-toplevel`) ou pasta comum. "Add Project…" escolhe uma pasta; "Clone…" (`gh repo clone owner/repo` na raiz de projetos) fica para v1.1.
- Uma sessão pertence a um projeto e aponta para um diretório: worktree nova, checkout existente (inclusive o principal) ou pasta. Sessões limpas (§2.7) não têm projeto.
- Projetos vêm também da importação do Orca (§6).

### 5.2 Worktrees

**Criar** (no composer, 03 §6; operação em segundo plano com linha pendente na sidebar):

| Origem | Passos |
|---|---|
| Base padrão | `git fetch origin <default>` (timeout 30 s; offline: usa a ref local e avisa) → `git worktree add -b <branch> <path> origin/<default>` |
| Branch existente | Se não estiver em uso por outro worktree: `git worktree add <path> <branch>`; remota: `git worktree add --track -b <branch> <path> origin/<branch>` |
| PR (`#123` ou URL) | `gh pr view 123 --json number,title,url,headRefName,baseRefName,isCrossRepository,headRepositoryOwner`. Mesmo repo: `git fetch origin <headRef>` e worktree rastreando `origin/<headRef>`. Fork: `git fetch origin pull/123/head:pr-123-<slug>` sem upstream (push para fork é later). Sessão ligada ao PR |
| Issue (`#45` ou URL) | `gh issue view 45 --json number,title,body,url` → branch `<prefix>/45-<slug do título>`; nome da sessão = título; prompt inicial pré-preenchido com título, URL e corpo (editável) |

**Nomes**:

- Raiz: `settings.worktreeRoot`, padrão `~/orca/workspaces` quando importado do Orca (`workspaceDir`), senão `~/AgentBox/worktrees`. Caminho: `<raiz>/<repo>/<slug>`.
- Slug: do nome digitado ou das primeiras palavras do prompt; minúsculas ASCII, hífens, até 40 caracteres.
- Branch: `<prefix>/<slug>`. Prefixo: modo `git-username` (login do `gh`, senão `git config user.name` normalizado), `custom` ou `none`; importado do Orca (`branchPrefix: git-username` → `gabrielgreco1/…`).
- Colisão de caminho ou branch: sufixo `-2`, `-3`. Branch digitada que já existe: oferece [Use Existing Branch].
- Falha (rede, branch em uso, disco): erro no card pendente com [Try Again] e a ação alternativa (R3/RT.3). Rollback de criação incompleta como no `GitWorktreeManager` atual.

**Arquivos ignorados e setup**:

- `.worktreeinclude` (v1.1, R3.4; R1 K-89a): na raiz do repo; lista de caminhos literais, `#` comentário, sem glob nem `!` (ignorados com aviso), sem `..`, sem `.git`; só copia o que existe no checkout principal **e** é gitignored; limites de 256 KiB e 1000 entradas; nunca bloqueia a criação. Mesmo contrato do Orca (`worktree-include-file.ts`), para não configurar duas vezes.
- Sem `.worktreeinclude`: oferta por projeto "Copy `.env*` files into new worktrees" (desligada por padrão).
- `orca.yaml` (v1.1): `scripts.setup` (roda depois do `worktree add`, numa tab "Setup"), `scripts.archive` (antes de remover), `setupAgentStartupPolicy: start-immediately | wait-for-setup`, `worktree.sharedDirectories` (symlink, ex.: `node_modules`). Política de execução do setup: Ask / Run by default / Skip (importada de `setupScriptLaunchMode`). Campos não suportados (`environmentRecipes`, `defaultTabs`, `issueCommand`) são ignorados com nota no Diagnostics.

**Remover / arquivar**:

- "Delete Session…" numa sessão de worktree mostra, antes de qualquer ação: terminais vivos (precisam parar), arquivos alterados e não rastreados, commits não publicados (`git rev-list --count @{u}..HEAD`; sem upstream: commits à frente da base), se o Orca também lista o worktree (§6.4), se o PR está aberto.
- Opções: [Archive] (esconde da sidebar e mantém o worktree em disco) e [Delete Worktree] (`git worktree remove <path>`, depois `git worktree prune`), com checkbox "Also delete branch `<b>`" (`git branch -d`; `-D` só com segunda confirmação quando não mesclada).
- `--force` só com confirmação explícita que lista o que será perdido. Nunca `stash`, `reset` ou `clean` automáticos (`audit/01` F4).

### 5.3 Status local na sidebar

- `GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch -z` por worktree: branch, upstream, ahead/behind, contagem de alterações, conflitos (entradas `u`), HEAD destacado. `GIT_OPTIONAL_LOCKS=0` evita disputar o `index.lock` com os agentes.
- Gatilhos: FSEvents no diretório git do worktree (`git rev-parse --git-dir`: `HEAD`, `index`, `refs`) e na árvore de trabalho, com debounce de 1 s e no máximo um `status` a cada 2 s por worktree. Sessões fora da tela: a cada 60 s e ao focar.
- Card (03 §2.6): branch, `↑2 ↓0`, ponto de alterações, badge de conflito, chip do PR com estado e ícone de checks.
- Runner de processo async único (sem semáforo no pool cooperativo, `audit/09` N4), com timeout e saída limitada.

### 5.4 Autenticação GitHub

- Ordem: `GH_TOKEN`/`GITHUB_TOKEN` do env capturado (§1.7) → `gh auth token --hostname <host>`. Token só em memória, renovado ao receber 401. O app não guarda token, não faz OAuth próprio na v1 e **nunca** entrega esse token a containers (P7).
- Sem `gh` ou sem login: estado "GitHub not connected" no Diagnostics e no card, com [Open Terminal With `gh auth login`]. Device flow próprio: later.
- Erro de SSO/permissão por repo: mensagem com o repo e o link de autorização devolvido pela API.

### 5.5 PRs e checks (GraphQL `statusCheckRollup`)

Uma consulta por repositório, com aliases para até 20 branches das sessões ativas:

```graphql
query($owner:String!, $name:String!) {
  rateLimit { cost remaining resetAt }
  repository(owner:$owner, name:$name) {
    b0: pullRequests(headRefName:"gabrielgreco1/fix-arcgis", first:3,
                     orderBy:{field:UPDATED_AT, direction:DESC}) {
      nodes {
        number title url state isDraft reviewDecision mergeable mergeStateStatus headRefOid
        commits(last:1) { nodes { commit { statusCheckRollup {
          state
          contexts(first:100) { nodes {
            __typename
            ... on CheckRun { name status conclusion detailsUrl databaseId
                              checkSuite { workflowRun { databaseId } } }
            ... on StatusContext { context state targetUrl }
          } }
        } } } }
      }
    }
    # b1: …
  }
}
```

- PR da sessão: o mais recente com `headRefName` igual à branch e `headRefOid` igual ao HEAD local ou ancestral; sessão criada de PR usa o número direto.
- Polling: 60 s com a janela ativa, 5 min em segundo plano, imediato 5 s depois de mudar `refs/remotes` (push detectado por FSEvents), e "Refresh" manual. Com `rateLimit.remaining < 200`, polling vai a 5 min. Em 403 de limite secundário: backoff exponencial até 15 min, mantendo o último estado marcado "stale".
- Chip: none / draft / open / merged / closed; checks: pendente, sucesso, falha (com contagem); review: approved / changes requested.
- Mudanças (checks falharam, PR aprovado, mergeado) viram eventos do inbox e notificações (v1.1, R5.4).

### 5.6 Abrir PR

"Create Pull Request" no card da sessão (overlay):

1. Pré-preenche base (`baseRefName` da origem ou branch padrão), título (nome da sessão ou último commit), corpo (vazio ou template do repo), "Draft".
2. Mostra o que vai rodar: `git push -u origin <branch>` (se não houver upstream ou houver commits à frente) e `gh pr create --base … --head … --title … --body-file … [--draft]`.
3. Executa com saída visível no próprio overlay; erro mantém o overlay aberto com o texto e [Try Again]. Sucesso: chip aparece e link "Open on GitHub".

Alternativa sempre disponível: "Open Compare on GitHub" (`gh pr create --web`). Merge pelo app: later.

### 5.7 Mandar falhas de check ao agente

- Botão "Send Failures to {Agent}" no popover de checks (v1.1, R5.5) e no item do inbox.
- Coleta: `CheckRun` com `conclusion` em `FAILURE`, `TIMED_OUT`, `ACTION_REQUIRED` ou `CANCELLED`; para GitHub Actions, `gh run view <runId> --log-failed` (por job, usando o `databaseId` do CheckRun quando `--job` aceitar), últimas 120 linhas por job, total ≤ 12 KiB, sem ANSI nem timestamps. `StatusContext` externo: só nome e link.
- Texto (template editável em Settings › GitHub, padrão em inglês):

  ```
  CI checks failed on PR #412 (https://github.com/…/pull/412):
  - build (GitHub Actions): https://…
    <trecho do log>
  Please investigate and fix.
  ```

- Entrega: escolher o terminal-agente da sessão (se houver mais de um, picker). **Colagem por clique** (T11): frame de input ao daemon com origem `0x02` e `ESC[200~ … ESC[201~`, **sem Enter**, e foco no pane. (A exceção com Enter de P12 vale só para o agente pai falando com filhos que ele criou, §0 regra 4.) Só se o emulador headless indicar bracketed paste ativo; senão copia para o clipboard e mostra "Copied — paste it into the agent".
- Agente em `working`: aviso "Claude is working; the text will wait in its prompt" e colagem permitida.

### 5.8 Credenciais git nos terminais

- No host, terminais herdam o env do usuário (§1.7), então os helpers de credencial do `~/.gitconfig` funcionam como no Terminal.app. Na máquina do dono: HTTPS com `credential.helper = !gh auth git-credential` (`audit/08` C2) e `ssh-agent` vazio.
- O app não define `GIT_ASKPASS`, `GIT_TERMINAL_PROMPT` nem `GIT_SSH_COMMAND`.
- Operações de Git do próprio app (fetch, status, push do "Create Pull Request") rodam com o mesmo env capturado.
- Containers: fora deste capítulo (broker de credencial, P7, 07).

### 5.9 Requisitos — Git e GitHub

| ID | P | Versão | Requisito | Aceite |
|---|---|---|---|---|
| TA-501 | P0 | v1 | Projeto Git ou pasta como entidade; "Add Project…" | Adicionar um repo mostra branch e worktrees existentes (`git worktree list --porcelain`) |
| TA-502 | P0 | v1 | Criar worktree a partir da base padrão e de branch existente, com nomes, prefixo e colisões da §5.2, em segundo plano | Composer com prompt "fix arcgis pagination" cria `~/orca/workspaces/rti-platform/fix-arcgis-pagination` na branch `gabrielgreco1/fix-arcgis-pagination` e abre o Claude rodando; a UI não trava durante o fetch |
| TA-503 | P1 | v1 | Criar a partir de PR (mesmo repo) e de issue, com sessão ligada | `#123` cria worktree na `headRefName` rastreando o remoto; issue preenche nome e prompt |
| TA-504 | P2 | later | PR de fork com push de volta | — |
| TA-505 | P1 | v1.1 | `.worktreeinclude` com o contrato do Orca; oferta de copiar `.env*` | Repo com `.env` ignorado e listado: o worktree novo tem o arquivo; um caminho rastreado listado não é copiado |
| TA-506 | P1 | v1.1 | `orca.yaml`: setup (tab "Setup"), archive, política de início do agente, `sharedDirectories` | Repo com `scripts.setup: pnpm install` e `wait-for-setup`: o agente começa depois do setup terminar |
| TA-507 | P0 | v1 | Remover/arquivar com checagens (terminais, dirty, não publicados, Orca, PR) e branch opcional | Worktree com commit não publicado mostra o aviso e exige a segunda confirmação para `-D` |
| TA-508 | P0 | v1 | Status local por FSEvents com `GIT_OPTIONAL_LOCKS=0`, ahead/behind, dirty, conflitos | Um commit feito pelo agente atualiza o card em ≤ 3 s; nenhum `index.lock` é criado pelo app (teste com `fs_usage`) |
| TA-509 | P0 | v1 | Auth GitHub herdando `gh` (ou `GH_TOKEN`), token só em memória; estado "not connected" com ação | Sem `gh` no PATH, o card mostra o estado e o botão; com `gh` logado, nenhum prompt aparece |
| TA-510 | P1 | v1 | PR e checks via GraphQL com `statusCheckRollup`, uma consulta por repo, polling e rate limit da §5.5 | Com 10 sessões em 3 repos, ≤ 3 requisições por ciclo; checks mudam de pendente para falha em ≤ 70 s com a janela ativa |
| TA-511 | P1 | v1 | "Create Pull Request" com push e `gh pr create` visíveis e confirmados | PR criado aparece no chip; erro de push mantém o overlay com o texto |
| TA-512 | P1 | v1.1 | "Send Failures to {Agent}" com coleta de logs e colagem por clique, sem Enter | Check falho gera o texto com o trecho do log no prompt do Claude, sem enviar; com bracketed paste desligado, vai para o clipboard |
| TA-513 | P0 | v1 | Credenciais git do usuário funcionam nos terminais | Num Claude aberto pelo app: `git push` num repo HTTPS conclui sem prompt |
| TA-514 | P1 | v1.1 | Eventos de PR/checks no inbox e notificações | Check falho com o app em segundo plano gera notificação "2 checks failing on #412" |
| TA-515 | P1 | v1.1 | Diff só leitura na aba Source Control (01; R1 K-64) e "Clone…" (R1 K-89g) | — |
| TA-516 | P2 | later | Merge pelo app, device flow próprio, comentar em PR (R2 SEM #10) | — |

---

## 6. Importação do Orca (removida por P21)

O Agent Box não importa nem lê dados do Orca (P21). Fica só o importador dos JSONs antigos do próprio Agent Box (T2-10). Requisitos TA-601…TA-607 removidos. A pasta padrão de worktrees é `~/AgentBox/worktrees/<repo>/<nome>`.

---

## 7. Testes de contrato e verificações pendentes

Rodam com `AGENTBOX_REAL_CLI=1`, contra as versões instaladas, antes de qualquer código depender do item. Resultado vira evidência JSON em `docs/evidence/`. Modelo barato e prompts curtos. Dono, fatia e critério de cada linha, junto com os spikes S-01…S-08, estão na lista consolidada de `08 §11`.

| # | Verificar | Como | Se falhar |
|---|---|---|---|
| V1 | Hooks de `--settings` rodam junto com os hooks do usuário (Orca) e recebem `session_id`, `source`, `last_assistant_message`, `notification_type` (**confirmado em 2.1.302, S-05(a)**, exceto `notification_type`) | Claude real com `--settings` de teste gravando payloads | Ler a última mensagem do transcript (§3.4) |
| V2 | Nome da ferramenta de pergunta ao usuário (`AskUserQuestion`?) e evento de permissão em `manual` | Prompt que força pergunta e comando que pede permissão | Ficar só com `PermissionRequest`/`Notification` |
| V3 | `permissions.deny: ["Skill(agentbox)"]` bloqueia a skill mesmo com `--dangerously-skip-permissions` | Claude real pedindo para usar a skill | Opção "Disable globally…" como recomendação |
| V4 | `--plugin-dir` segue symlinks de `skills/<nome>` | Plugin gerado com symlink | Cópia por lançamento |
| V5 | `--resume <id>` com `--settings`/`--mcp-config`/`--plugin-dir`/`--agents` regenerados restaura tudo | Lançar, encerrar, retomar, conferir `/skills` e `/mcp` | — (bloqueante para TA-209) |
| V6 | Codex aceita hooks e `mcp_servers` por `-c`; exige *trust*? Hash estável entre lançamentos? Campos de `SessionStart`/`Stop` | **Respondido em S-05 (2026-10-17):** exige trust (`untrusted` não executa); hash estável com comando e `timeout` constantes; trust inline por `-c 'hooks.state={…}'`; `SessionStart`/`UserPromptSubmit` capturados. **Aberto:** `PreToolUse`/`PostToolUse`/`Stop` e `mcp_servers` por `-c` (reexecutar depois de 22/10/2026) | Estado do Codex por tail do rollout, marcado "estimated" (baseline de §3.3.1) |
| V7 | `opencode session list --format json` traz diretório e data | CLI real | ID manual no Resume do OpenCode |
| V8 | `claude --resume <id>` depois de mover a pasta da sessão | Mover pasta de teste | Bloquear "Move Folder" com conversa a retomar |
| V9 | Bracketed paste chega ao prompt do Claude e do Codex sem enviar | Colagem via daemon | Só clipboard |
| V10 | `gh run view --log-failed --job <id>` aceita o `databaseId` do CheckRun | Repo de teste com check falho | Log do run inteiro filtrado por nome do job |
| V11 | Captura do env (`-l -i -c` com marcador, env por arquivo) não trava nem polui | **Respondido em S-06 (2026-10-17)** com o zsh do dono (sem p10k nem oh-my-zsh): 32 ms, 0 lixo fora dos marcadores, `claude node gh codex` resolvem. Rc sintético barulhento 0,76 s; rc que trava cortado em 5 s | Fallback `-l -c` marcado `non-interactive` |
| V12 | Codex app-server daemon compartilhado: a TUI lançada pelo app delega a sessão a um processo fora do grupo do PTY? Efeito de `--no-daemon` em captura de ID, `kill` e convivência com o Orca | **Respondido em S-05(c):** o daemon vive fora do PTY (ppid 1, pgid próprio); `--no-daemon` é seguro e barato e vira padrão. Não provado em qual processo a thread vive (turnos falharam por cota) | `--no-daemon` por padrão no adapter (P18) |
| V13 | `claude agents --json`, encadeamento de `statusLine` com `rate_limits.five_hour/seven_day`, `notification_type` = `permission_prompt`/`idle_prompt`, timeout de hook de 5 s, `-n/--name` como título, `--session-id` + `/clear` | Claude real | Recurso correspondente desabilitado com motivo |

Testes automáticos sem CLI real (CI macOS): protocolo do daemon (handshake, idempotência, reattach com seq, backpressure, N-1), autenticação do peer com binário assinado por outra identidade, argv por adapter e perfil, máquina de estados com fixtures de payloads gravados, drenagem do spool, parser de `.worktreeinclude` (casos do Orca), mapeamento da importação com um SQLite de fixture anonimizado, `git status --porcelain=v2` com repos temporários.

E2E (`scripts/e2e.sh` com `agentbox ctl`): composer → worktree → Claude rodando com prompt → split com shell → `ctl app quit` (Keep Running) → reabrir com mesmo PID → `kill -9` no daemon → cold restore → [Resume] com hooks de volta → fim de turno gera `done` e notificação.
