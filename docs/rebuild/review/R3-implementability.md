# R3 · Revisão de implementabilidade da spec de rebuild

Data: 2026-10-16. Escopo: `docs/rebuild/spec/00..08`, lidos inteiros (em quatro leituras paralelas, cruzadas depois). Ponto de vista: o engenheiro que vai construir, e o agente de código que vai receber cada tarefa. A spec não foi editada; tudo aqui é recomendação.

Convenção de referência: `01:225` = arquivo `01-product.md`, linha 225. "Auditoria" = `docs/rebuild/audit/`.

---

## 0. Veredito em uma página

A spec é muito mais concreta que a média: tokens com hex e pt, microcopy exata, protocolo do daemon com framing, schema SQLite, Definition of Done (`08:647`), `accessibilityIdentifier` por controle e um teste de varredura (AC-T01/T02). O risco de "cara de AI" e de "clique que não faz nada" caiu bastante.

Ela **ainda não está pronta para ir a agentes em fatias**, por cinco motivos:

1. **Os capítulos se contradizem em nomes que viram código e teste.** Labels de launchd, bundle id, nomes de socket, env vars, IDs de acessibilidade, nome da seção de sessões limpas, limiar do prompt em arquivo, IDs de motion (§2). O 00 não decide nenhum desses pontos, e um agente vai escolher um lado ao acaso. Pior: o teste escrito a partir de um capítulo vai falhar contra o código escrito a partir de outro.
2. **A referência visual que deveria ser o gate não existe no repositório.** Não há nenhum screenshot do Orca: `audit/screens/` tem 2 PNGs, e são do app *antigo*. O código-fonte do Orca citado como fonte da verdade (`scratchpad/orca-src`) está num diretório temporário de sessão (`/private/tmp/.../scratchpad/orca-src`) e vai sumir. O "checklist 04 §8" citado em `02:879` aponta para a seção errada. Sem isso, "parecer com o Orca" volta a ser opinião (§5).
3. **A Fatia 1 do `01:86` é grande demais e depende de coisas das fatias 2 e 3.** Ela inclui os três momentos de motion, e um deles é "agente usando computador", que só existe na Fatia 3. Inclui também daemon com launchd, retomada, Conversations, importação do Orca e onboarding. A ordem técnica do `08:713` não casa com as fatias do `01`. A DoD exige `ctl screenshot` e ação registrada no `ctl` desde a primeira tarefa, mas o `ctl` é a etapa 5 (§4).
4. **Há riscos técnicos que podem derrubar a arquitetura e não têm spike agendado antes da Fatia 1.** Dois exemplos: socket activation do launchd com caminho dentro do home num plist empacotado, e peer auth por assinatura em builds de desenvolvimento e CI. O 07 agenda spikes, mas só para a Fatia 3 (§6).
5. **"Tudo que clica funciona" tem gate, mas com furos.** O teste dispara ações pelo view model (`ctl ui action`), não por clique real. Aceita "erro visível" como efeito, e não há lint que force todo `Button` a passar pelo registro. Há ainda dezenas de itens de menu sem comportamento definido e controles de fatias futuras desenhados na UI (§7).

O que fazer antes da primeira linha de código: uma **fatia 0 de fechamento**, com cerca de 3 a 4 dias de trabalho de agente mais horas do dono, descrita no §9. Ela consiste em uma errata decidida pelo dono, um pacote de referência visual do Orca versionado, seis spikes e o esqueleto com o gate de automação. A decomposição da Fatia 1 está no §10.

---

## 1. Verificações locais (rodadas nesta máquina, sem login nem mudança de config)

| Item | Resultado | Consequência para a spec |
|---|---|---|
| `claude --version` | `2.1.302` | Bate com 06/07. |
| Flags do Claude usadas pela spec | Existem: `--settings <file-or-json>`, `--mcp-config`, `--strict-mcp-config`, `--plugin-dir` (repetível, aceita .zip), `--agents <json-or-file>`, `--agent`, `--session-id <uuid>`, `-r/--resume`, `-c`, `--fork-session`, `-n/--name`, `--permission-mode` (`acceptEdits, auto, bypassPermissions, manual, dontAsk, plan`; `manual` existe), `--dangerously-skip-permissions`, `--add-dir`, `--effort`, `--fallback-model`, `--disable-slash-commands`, `setup-token`, `agents` | Nenhuma flag inventada. Observação: `--bare` e `--safe-mode` desligam hooks. O app nunca deve herdar perfil do Orca com essas flags sem avisar que o estado de atividade some. |
| Hooks globais do Claude | `~/.claude/settings.json` tem 13 eventos, todos do Orca, que saem cedo sem `ORCA_AGENT_HOOK*` | Confirma `06:388` (remover `ORCA_*` do env). V1 (`--settings` soma com os hooks do usuário) continua precisando de teste real. |
| `codex --version` | `codex-cli 0.160.0` | Bate. |
| Flags do Codex | Existem: `-c key=value` (TOML), `--enable/--disable`, `-p/--profile`, `-s`, `-a`, `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `-C/--cd`, `--add-dir`, `--no-alt-screen`, `--no-daemon`, `resume [SESSION_ID] [PROMPT]`, `resume --last`, `fork`, `queue`, `features` | Atenção para dois pontos: **não existe `--session-id`** no Codex (o 06 já assume isso), e o Codex agora tem um **app-server daemon compartilhado** (`daemon_auto_start` stable = true, `--no-daemon`). O 06 não discute se o Codex lançado pelo Racky deve usar `--no-daemon`. Isso afeta captura de ID, sobrevivência e o comportamento com dois apps. Entra como spike. |
| Hooks do Codex | `~/.codex/hooks.json` (escrito pelo Orca) + `[hooks.state."<arquivo>:<evento>:i:j"] trusted_hash = "sha256:…"` em `config.toml` | Os hooks do Codex exigem **trust persistido por hash**, gravado no `config.toml` do usuário. Hooks por `-c` (`06:377`, AR-112) provavelmente caem nessa regra e não rodam, ou pedem trust na TUI a cada hash novo. Gravar trust é escrita em config global (contra T10), e `--dangerously-bypass-hook-trust` é proibido (`06:306`). **A Fatia 2 depende disso, e é o risco nº 1 do T10 para o Codex.** A saída do `08:737` (`CODEX_HOME` temporário por lançamento) mexe em login e histórico do Codex. É spike, não detalhe. |
| `notify` do Codex | Ocupado pelo Codex Computer Use (`config.toml:1`) | Confirma `06:387`. |
| Swift/Xcode | Swift 6.2.4, Xcode 26.3, macOS 27.0.1 (arm64) | `swift-tools-version: 6.2` + `defaultIsolation` (SE-0466) estão disponíveis. |
| XcodeGen | **Não instalado** (`which xcodegen` vazio). Homebrew oferece `2.46.0` | O `08:110` diz "instalação por Homebrew com versão conferida", mas o Homebrew não fixa versão de fórmula. Recomendo baixar o release zip do GitHub com SHA-256 fixo no `bootstrap.sh`, ou usar `mint`. Sem isso, o primeiro agente vai rodar `brew install xcodegen` e cada máquina fica com uma versão. |
| SwiftTerm em `Package.resolved` | `1.20.0` (rev `5d14406`, 2026-08-18). O resolved também fixa `swift-argument-parser 1.8.2`, que não está no `Package.swift` atual (pin órfão) | — |
| SwiftTerm, Metal | Existe API pública: `setUseMetal(_:) throws`, `isUsingMetalRenderer`, `metalRendererStatus` (com recuperação de frames travados), `metalBufferingMode`, `drawMetalFrameNow()` | T6 é viável na 1.20.0. |
| SwiftTerm, busca | `findNext/findPrevious(_:options:scrollToResult:)`, `searchMatchSummary(_:options:limit:)`, `clearSearch()`, `SearchOptions(caseSensitive:regex:wholeWord:)`. A find bar embutida (`TerminalFindBarView`) é **privada** e abre via `performFindPanelAction` | O `02 §16` ("Find bar SwiftUI própria usando `SearchService`") é viável com a API pública. O agente precisa saber que não deve usar a find bar embutida (visual de sistema, quebra a regra 17 do `02`). |
| SwiftTerm, OSC 52 | `TerminalViewDelegate.clipboardRead(source:) -> Data?`. **`LocalProcessTerminalView` devolve o conteúdo do pasteboard** (`MacLocalTerminalView.swift:122`) | Um agente que usar `LocalProcessTerminalView` "para começar" viola T6 em silêncio. A spec deve proibir `LocalProcessTerminalView` na UI (o PTY é do daemon) e exigir delegate próprio com `clipboardRead → nil`. AR-520 já tem o teste; falta a proibição explícita. |
| SwiftTerm, novas versões | Tag **`v1.99.0` de 2026-10-08** (8 dias), 250 commits depois da 1.20.0, preparando a v2: "Move macOS Metal layer rendering off the main thread", "Allow terminal input from transport threads", "Parse thread optimizations", "Surface additional APIs in v2" | O `08:136` manda "subir para o último 1.x estável", e um agente vai ler `1.99.0`. Isso responde em parte à questão aberta 1 do `08:733` (parse fora do main), mas é pré-release de API nova, com menos de duas semanas. **Decisão necessária**: fixar 1.20.0 na Fatia 1 e fazer spike 1.99 em paralelo (§6, S-02). |
| Geist | Licença **SIL OFL 1.1** (vercel/geist-font). Homebrew cask `font-geist` 1.8.1 (não instalado). Fonte: releases de `github.com/vercel/geist-font`, ou pacote npm `geist` | Pode ser embutida no bundle, com `OFL.txt` junto (exigência da OFL). A spec (`02:277`) cita `Geist-Variable.ttf`, mas o nome upstream é diferente (`Geist[wght].ttf` / `GeistVF`). Falta fixar versão, URL e SHA-256, conferir o nome de família registrado para `Font.custom("Geist")` e dizer onde fica a licença no bundle e no About. |
| Orca instalado | `/Applications/Orca.app` versão **1.4.219**, com `app.asar` | É daqui que deve sair o pacote de referência versionado (§5). |
| `launchd.plist(5)` | `SockPathName` é um caminho literal. A man page não documenta expansão de `~` nem de variáveis | `06:61` usa `SockPathName = AB/run/daemon-v1.sock`, com AB em `~/Library/Application Support/…`, num plist **estático** dentro do bundle (`SMAppService`). O plist não sabe o home do usuário. É risco de arquitetura (S-01). |

---

## 2. Contradições entre capítulos (precisam de decisão antes de qualquer tarefa)

O 00 prevalece, mas não cobre nada disto. Proponho que o dono feche cada linha numa errata (`00-decisions.md` § "Errata R3") e que os capítulos passem a citá-la.

### 2.1 Nomes que viram código

| Tema | Versões | Onde |
|---|---|---|
| Bundle id | `app.racky` / `app.racky.mac` | `06:60,89` vs `08:69,96` |
| Label e socket do daemon | `app.racky.daemon.v1` + `daemon-v1.sock` / `app.racky.ptyd.v1` + `ptyd-v1.sock` (teste: `ptyd.test-<n>`) | `06:60-61` vs `08:53,70,631,706` |
| Env da execução | `RACKY_TERMINAL_ID`, `_HOOK_SOCKET`, `_HOOK_TOKEN` / `RACKY_PANE_ID`, `_RUN_ID`, `_APP_SOCK` | `06:171` vs `08:98` |
| Spool de hooks | `run/hook-spool/<terminalID>.jsonl`, 300 ms / `run/spool/hooks/<runID>.jsonl`, 200 ms | `06:448` vs `08:94` |
| Comando de hook | `racky hook --provider claude --event X` / `racky hook --event <nome>` | `06:448` vs `08:100` |
| Dir de lançamento | `run/launch/<terminalID>/<attempt>/` / `run/launch/<runID>/` | `06:373` vs `08:100` |
| Ops do protocolo | `attach{sessionID,cols,rows}`, `drainWhenIdle`, `forget`, `textSnapshot`, `ping` / `attach{sessionID, mode: snapshot\|sinceSeq}`, `drain`, sem os três últimos | `06:96-109` vs `08:72-74` |
| Backpressure | 4 MiB / 2 MiB | `06:113` vs `08:73` |
| Cold log | 2 × 8 MiB, meta {terminalID,cwd,startedAt,exit} / 8 MiB, meta {argv, env names, pid} | `06:136` vs `08` |
| Retenção `agent_event` | 50 mil por terminal / 10 mil por run, 30 dias | `06:452` vs `08:311` |
| Debounce de layout | 500 ms / 300 ms | `06:191` vs `08:312` |
| Captura do env | `-l -i -c` em PTY oculto (5 s) → `-l -c` / `-l -c` (3 s) → `-lic` | `06:162` vs `08:77` vs AC-312 |
| Pasta dos tokens de UI | `Sources/RackyUI/Design/Colors.swift` / alvo `RackyDesignSystem` em `Packages/RackyKit` / "`RackyDesign`" | `02:53` vs `08:121` vs `04:15` |
| `session.kind` | `worktree/checkout/folder/clean` / `worktree/clean` | `01:204-213` vs `08:311` |
| Estado de atividade | `needsInput, waitingOnSubagents, idle, unknown…` / `working/waiting/permission/blocked/…/unverifiable` / DS adiciona `stale`, `blocked` | `06 §3.1`, `04:373` vs `08` vs `02:130-151` |
| Estados de processo/pane | `launching` / `starting`; "Not started" (AC-109) não existe em nenhuma máquina de estados; `failedToStart`, `daemonUnavailable`, `restoredDead` só no DS | `01:487-516` vs `02:159-170` vs `03:476-494` |

### 2.2 Nomes e comportamentos que o usuário vê

| Tema | Versões | Onde |
|---|---|---|
| Sessão sem projeto | "Clean session", seção **"Sessions"**, "File › New Clean Session" / "Scratch session", seção **"Scratch"**, ⌘⇧N "New Scratch Session", e o DS proíbe "Clean session" | `01:225,608`, `05 J11`, `04:349,459` vs `02:954`, `03:309-314` |
| Promover sessão limpa | "Attach to Project…" (v1) + "Move Folder Into Project…" (v1.1) / "Move to Project…", "Convert to Project", "Move folder into project…" (todos v1) / "Promote to Project…" (§16.8) | `06:368` vs AC-1106/1107 vs `03:174,251` |
| Nome automático | `untitled-<n>` ou derivado do prompt / par de palavras `quiet-harbor` / "criatura marinha" | `06:365` vs `01:674`, AC-1102 vs `03:545` |
| Prompt em arquivo | > 16 KB / > 64 KiB ou começa com `-` / 40 KB já vai para arquivo (AC-308) / sem limiar | `01:279` vs `06:340` vs `05:248` vs `03:538` |
| argv exato | AC-307 exige argv **exatamente** `claude --session-id <uuid> --dangerously-skip-permissions hello`; o 06 sempre injeta `--settings`/`--mcp-config`/`--plugin-dir` | `05:245` vs `06:44,377-382` |
| Opções "Where" do composer | 4 opções / 3 (`New Worktree · Existing Branch · Folder`) / por contexto (`New Worktree · Existing Worktree · Main Checkout`; Scratch: `New Folder · Choose Folder…`) | `01:614` vs `02:677` vs `03:532` |
| Largura do composer | 560 / 512 | `03:525` vs `04:478` |
| ⌘Q | Pergunta só na primeira vez / sempre, salvo "Don't ask again"; os botões diferem | `05:597` vs `06:197-205` vs `03:1118` |
| ⌘⇧T | Reabrir tab fechada (com `--resume`) / Take Control no viewer | `03`, AC-T09 vs `04:416` |
| Foco de pane | ⌘] / ⌘[ / ⌘⌥ setas (colide com Back/Forward ⌥⌘←/→) | `03:1287` vs `04:364` |
| Outros atalhos de 04 que não existem ou colidem | ⌘⇧E (Reveal), ⌥⌘M (Motion Lab colide com "Minimize All" do sistema) | `04:348,736` |
| Take over | "Take over / Hand back" / "Take Control / Give Back", e o DS proíbe "Takeover" | `01:586`, `00 T8` vs `02:964` |
| Needs input | "Needs input" / "Needs you" | `01:526` vs `02:133` |
| Daemon perdido | Três textos diferentes | `03:488`, `04:310`, `02:752` |
| Pane interrompido | Opacidade 50% + banner + Resume/Start Fresh/Close / overlay 0,35 + pill "Exited while Racky was closed" | `03:487` vs `04:309` |
| Erro de lançamento | Retry/Open Agent Settings/Copy Details / Retry/"Open launch log" | `03:485` vs `04:369,400` |
| Estado vazio | "Sem ilustração" / M-901 desenha o logo com trim | `03:1251`, `02:758` vs `04:459` |
| Foco (anel) | 3 pt / 2 pt | `02:790` vs `04:289` |
| Blur do scrim | blur 2 / desligado na v1 | `02:713` vs `04:44` |
| Logo da ignição | 32 / 48 | `03:481` vs `04:540` |
| Tamanhos do `AgentStateIndicator` | 10/12/16 / 8/10/12/16 | `02:145` vs `04:663` |
| Fonte da importação do Orca | `orca-data.json` com 6 repos e 103 worktrees / `profile-state.db` primário, JSON legado, 7 repos e 111 worktrees | `05:41,68,85` vs `06:740-747` |
| Regra 15 do DS ("nada de 680/720/760") | O próprio DS usa 720 (palette, Settings) e 760×480 (janela mínima) | `02:872` vs `02:26,343,347,351` |

### 2.3 Referências quebradas

- **Códigos de motion.** O 03 usa `M:C9`, `M:B8`, `M:E2`… (IDs da auditoria 06) em pelo menos 20 lugares, e o DS usa `A1…F6`/`E0…E4`. O 04 renumerou tudo para `M-xxx` e não há tabela de correspondência. Um agente que siga o 03 implementa os valores **antigos**, que o 04 §2 revogou.
- **IDs de acessibilidade do 04 diferentes dos do 03/DS.** São mais de 20 pares, por exemplo `sidebar.sessionRow.<id>` vs `sidebar.session.<id>`, `pane.<id>.launchError` vs `.startError`, `computer.viewer.*` vs `viewer.*`, e `menu.<name>` colide com `menu.<group>.<action>`. Como os testes de motion localizam elementos por esses IDs, **a suíte quebra no primeiro dia**.
- **Seções do 03 citadas pelo DS.** "03 §7" (composer) é Quick Launch; "§4.4" (rename) é Find; "§3.7", "§2" e "§12" apontam para o lugar errado. "04 §3.3" (Reduce Motion) é Curvas. "Checklist 04 §8" (`02:879`) não existe no spec 04; está na **auditoria** 04 §8.
- **"P2" com dois sentidos.** No 00, P2 é "UI em inglês". Em `02:110,266,469,848` e `03:347`, P2 é prioridade 2. Um agente lê "pin tab (P2)" como ligado ao idioma, ou como v1.
- **"07 #14", "09 N7", "R2.4".** São IDs da **auditoria**, mas convivem com os capítulos 06/07 da spec; `03:804` usa "07" nos dois sentidos. Um "capítulo de status bar" (`06:381`) e um "capítulo de UI" (`04:272,690`) não existem.

---

## 3. Interfaces: o que está definido, o que falta

| Interface | Estado | Falta para um agente implementar sem inventar |
|---|---|---|
| Protocolo do daemon | Bom: framing, kinds, handshake (exemplo), ops, eventos (`06 §1.3`) | Um **único** documento normativo, porque 06 e 08 divergem (§2.1). Faltam: schema JSON por op (tipos, opcionais, `id`), lista de códigos de erro, valores de `list.state`, codificação do `attachSnapshot` (JSON com base64 ou frames binários), formato do `modesPreamble`, semântica de `seq` (offset de bytes ou contador de frames), quem vence o `resize` com dois clientes (app + `ctl`) e **campo de origem da escrita**, exigido por AC-307/AC-505 e ausente do protocolo. Proposta: `RackyProtocol` vira a fonte, com fixtures JSON versionadas em `Tests/ProtocolTests/Fixtures/` escritas **antes** do daemon. |
| `app.sock` (mcp, hook, ctl) | Comandos do `ctl` em `08:603-615` | Schema de request e response do `ctl` e do frame de hook. AC-T03 cita `ctl ui focus` e `ctl screenshot window`, e o 06 cita `ctl app quit --keep`; nenhum dos três existe na tabela do 08. |
| Schema SQLite | Bom: `08 AR-311` | Colunas pedidas por ACs e ausentes: status note com autor e hora (AC-208), última mensagem do terminal, unread/seen, ID de origem do Orca (AC-111), cor do projeto, opt-out de cold log por terminal, `addDirs` e segredos do perfil, estado "not started". O `session.kind` diverge do 01. |
| Modelos Swift | `LaunchRequest` (`06:251`), `LaunchProfile` em pseudocódigo, entidades em `01 §5` (sem tipos) | `Provider`, `CatalogRef`, `Injection`, `NativeConversation` só nomeados. Não há um arquivo de "tipos de domínio v1" que o agente de UI e o de Core compartilhem. Proposta: a tarefa T-05 (§10) cria esses tipos e os demais passam a depender dela. |
| Eventos entre módulos | Só o diagrama `06:27-38` | Não há contrato `PTYClient → TerminalService → AgentActivity`, nem eventos `LaunchProgress` além de `04:550`, nem a forma como a UI observa (ValueObservation para o que é persistido; e o transitório?). É o lugar mais provável de cada agente inventar um bus diferente. |
| MCP tools | 07 tem assinaturas (`browser_screenshot(...)`, `desktop_action(...)`) | Fora da Fatia 1. Ver o resumo do 07/08 no §11. |
| Hooks | Lista de eventos e mapeamento (`06:456-470`) | Forma JSON do `--settings` gerado (matcher, array), forma TOML do `-c` do Codex (talvez inviável, §1), frame do hook no `app.sock`, cursor do spool. |
| `KeyBindingRegistry` / registro de ações | Citado (`02:849,918`, `03:1160`), com tabela de atalhos em `03 §21` | Não há tipo nem regra de escopo. O ⌘F tem três escopos atrás de um só key equivalent de `NSMenu`, e o menu dispara antes da view. É a base de "tudo que clica funciona" e não tem dono no 08. |
| Tokens | Valores completos no 02/04 | `design/tokens/*.json` não existe, o gerador não está especificado e o `design/` atual tem lixo do app antigo (`design/motion/timeline.html`, `screens/01-16` em PT-BR com Manrope). **Um agente vai abrir `design/screens/` achando que é referência.** O 02 deve declarar `design/` legado e o rebuild deve começar com `design/` limpo, ou movê-lo para `legacy/`. |
| Layout do repositório | `08` define `Packages/RackyKit` + `project.yml` | Não diz o que acontece com `Package.swift`, `Sources/` e `Tests/` atuais na raiz. Ficam lado a lado? São apagados na etapa 0? O `08 §2` tem uma tabela DESCARTAR/REESCREVER por arquivo, mas não diz **onde** o código antigo vive enquanto isso. Um agente vai tentar compilar os dois. |

---

## 4. Fatias, ordem e dependências circulares

### 4.1 A Fatia 1 do `01:86` não fecha

- Pede "os três momentos de motion obrigatórios", e o terceiro (agente usando computador, M-601…M-609) depende de Docker, viewer e ControlBroker, que são da Fatia 3.
- Pede onboarding com detecção de Docker e conflitos de skill, retomada em lote, Conversations (que vive no painel direito, cujas outras abas são Fatia 2) e importação do Orca. Isso é umas três fatias de trabalho.
- O card de sessão mostra estado de agente, mas o estado vem de hooks, que são Fatia 2. Nada diz o que a Fatia 1 mostra. A resposta coerente com `04 M-407` é `unknown`/"Status unavailable", ou só o estado do processo.

### 4.2 A ordem do `08 §10` e a DoD se mordem

- **DoD → ctl → DoD.** A DoD (`08:647-651`) exige, em toda tarefa, ação registrada no `ctl`, varredura de IDs e screenshot via `ctl screenshot`. O `ctl` é a etapa 5. As etapas 0–4 (esqueleto, daemon, terminal, persistência, sessões) não podem cumprir a DoD. **Correção:** o registro de ações, os `A11yID` e o `ctl` mínimo (`state`, `ui tree`, `ui action`, `screenshot`) sobem para a etapa 0/1.
- **AC-301 → ctl.** O critério de "teclas não chegam ao PTY" usa `ctl terminal screen`, e o XCUITest não lê bytes do PTY. O mesmo vale para o resto dos critérios de terminal.
- **Peer auth → assinatura → CI.** O daemon recusa peers sem a assinatura local, sem bypass por env (`06:92`). O runner macOS do GitHub não tem a identidade "Racky Local Signing". Ou o CI cria um certificado efêmero por job, ou não há teste de protocolo no CI. A spec não decide.
- **Hooks → trust do Codex → config global.** Ver §1.

### 4.3 Ordem proposta

Fatia 0 (fechamento, §9) → Fatia 1 redefinida (§10) → Fatia 2 (hooks/atenção/GitHub + importação do Orca + Conversations + onboarding completo) → Fatia 3 (computadores + motion "computador em uso") → Fatia 4.

---

## 5. O que impede o resultado de ficar "AI generated" de novo

**O que já está bom:**
- Os tokens são numéricos e completos: hex, pt, peso, entrelinha, durações e curvas. A matemática das curvas e springs do 04 foi conferida e bate.
- A lista "nunca" do `02:858-877` é concreta (emojis, Sparkles, cards com raio 14+, subtítulos de marketing, cor como enfeite, mais de um primário…).
- A microcopy é declarada exata (`03:6`).

**O que falta, e é o que decide:**

1. **Referência visual versionada.** Proposta de gate: `docs/rebuild/reference/orca-1.4.219/`.
   - Screenshots PNG @2x, janela 1440×900, escuro, de cada superfície da Fatia 1: janela vazia, sidebar com 3 projetos (card ativo, hover, unread, pendente), tab row (ativa, hover, overflow), dois panes em split com header, find bar, composer (cada variante do "Where"), quick launch, palette, confirmação de fechar, toast, menus de contexto, estado vazio. Mais crops 1:1 dos componentes.
   - Um `manifest.json` liga cada PNG ao ID de tela do 03 e ao `accessibilityIdentifier` equivalente no Racky.
   - Os arquivos do renderer do Orca citados pelo 02/04, extraídos do `app.asar` da versão instalada por script (`scripts/extract-orca-reference.sh`). Nunca de um scratchpad.
   - A captura do Orca é feita uma vez (dono ou agente com Gravação de Tela), com dados fictícios iguais aos fixtures do `05 §0.3`.
2. **Comparação mecânica, não opinião.** Duas propostas:
   - `scripts/compare-ui.sh <tela>`: `ctl screenshot` do Racky no mesmo tamanho e com os mesmos fixtures, montagem lado a lado mais **diff de sobreposição** (50% e diferença absoluta) em `docs/evidence/ui/<tarefa>/`. Não precisa ser pixel-perfect (fontes e AppKit divergem), mas o diff torna visíveis desvios de 4 pt, cor errada ou peso errado, que a revisão "a olho" de um agente deixa passar.
   - **Medições automáticas** a partir da árvore do `ctl ui tree` (frames por ID): altura da tab row = 32, sidebar = 280, semáforos em x 16/36/56 e y 18, linha de agente = 24, card com raio 10… O checklist da auditoria 04 §8 e as tabelas do 02 viram um `LayoutConformanceTests` que falha no CI. Grande parte da "cara do Orca" é geometria, e geometria dá para testar.
3. **Snapshot tests com referência aprovada.** O `08` lista `swift-snapshot-testing` e `UISnapshotTests`, mas "snapshot só se houver referências" (`08:615`) deixa a porta aberta para nunca haver referência. Regra proposta: cada componente do DS entra com snapshot de referência **aprovado pelo dono** junto do crop do Orca. Snapshot sem aprovação não fecha a tarefa.
4. **Lint de UI de verdade.** `scripts/lint-ui.sh` (`02:855`) só tem nome. Conteúdo mínimo proposto, todo greppable:
   - Proibir `.sheet(`, `List(`, `Form(`, `Picker(…).pickerStyle(.segmented)`, `TextEditor`, `.animation(` sem `value:` em view raiz, `Color(red:`, `Color(hex:` fora de `DS.Color`, literais numéricos em `.padding(`/`.frame(` fora de `DS.Space`, `Font.system(size:` fora de `DS.Font`, `LocalProcessTerminalView`, emojis em literais e `Sparkles`.
   - Exigir que toda string de UI esteja no String Catalog (AC-T04).
5. **Revisão do dono como gate explícito por tarefa de UI**, com prazo e formato (o PNG lado a lado). O 04 já faz isso para motion (`04:757`). Para telas, o 05 deixa a fidelidade como `MANUAL` em AC-T26, só no fim da v1. Tem de ser por tarefa, senão o desvio se acumula como no app anterior.
6. **Controles de fatias futuras não aparecem.** O DS e o 03 desenham Star/pin (v1.1), Moon/Sleep (v1.1), Pin tab (P2), activity bar de Source Control, Context, Mute, chip de PR (Fatia 2) e faixa Computers (Fatia 3). Se aparecerem desabilitados na Fatia 1, a UI fica cheia de coisa morta; se aparecerem habilitados, nada funciona. Regra proposta: **feature flag por fatia; controle de fatia futura não é renderizado**. Não basta desabilitar.

---

## 6. Riscos técnicos: spikes e todas as verificações pendentes consolidadas

### 6.1 Spikes que precisam acontecer antes ou no início da Fatia 1

| # | Spike | Por que bloqueia | Critério de saída | Plano B |
|---|---|---|---|---|
| S-01 | `SMAppService.agent` + `Sockets/SockPathName` com caminho no home do usuário, num plist estático no bundle; `launch_activate_socket`; aprovação de login item; teste com `RACKY_HOME` e label de teste | T1 e P4. Se o launchd não aceitar o caminho, a arquitetura de ativação muda | App assinado registra, o launchd cria o socket, e `nc -U` acorda o daemon. Evidência: log e `launchctl print` | Socket em caminho fixo fora do home (por exemplo `/tmp/racky-<uid>/`, com validação de dono e modo), ou daemon com `KeepAlive` que faz `bind` ele mesmo. O modo degradado (`06:64`, daemon filho do app) já serve para a Fatia 1. |
| S-02 | SwiftTerm 1.20.0 vs 1.99.0: Metal, `feed` fora do main, `send` de outra thread, busca, OSC 133/7, latência com 4 panes e `yes \| head -c 200M` | T6, AR-406, AC-T07 (p95 ≤ 50 ms) | Medição nos dois; decisão de versão escrita no 08 | Ficar na 1.20.0 com feed no main e orçamento (`08:733`). |
| S-03 | Peer auth (`LOCAL_PEERTOKEN` + `SecCodeCheckValidity`) com o certificado local em dev, XCUITest runner, `racky ctl` e CI | Sem isso nenhum cliente fala com o daemon fora do Mac do dono | Teste aceito e recusado; receita de CI (certificado efêmero no keychain do job) | Requisito por Team ID ad-hoc mais `getpeereid` em builds `DEBUG` com flag de compilação (não por env). |
| S-04 | Reattach: replay do ring a partir do ponto de corte, preâmbulo de modos e redraw `cols-1`, com Claude e Codex (TUI com alt-screen) e `vim` | P4, TA-105 | `textSnapshot` antes e depois iguais em 20 repetições; vídeo | Serializador de células (fora do escopo hoje). |
| S-05 | Hooks por lançamento: (a) Claude `--settings` soma com os hooks do Orca (V1); (b) Codex `-c hooks…` sem trust, ou `CODEX_HOME` temporário; (c) Codex app-server daemon versus `--no-daemon` | T10, Fatia 2 (mas define o adapter da Fatia 1) | Payloads gravados como fixtures em `docs/evidence/` | Estado do Codex por tail do rollout, marcado "estimated" (V6). |
| S-06 | Captura do env de login (`-l -i -c` com marcador em PTY oculto) com o zsh do dono (p10k/oh-my-zsh) | TA-110, AC-312. Se travar, nenhum agente acha `claude` | Captura em menos de 1 s, sem lixo, `which claude node gh` resolve | `-l -c` com timeout. |
| S-07 | `ctl screenshot` via ScreenCaptureKit da própria janela com camadas Metal | Toda a evidência visual depende disso | PNG fiel do terminal Metal | `CGWindowListCreateImage` (deprecado) ou snapshot do `CAMetalLayer` pelo próprio app. |

### 6.2 Todos os "(verificar)" e as perguntas abertas, consolidados

**06 (contrato de CLI, tabela V1–V11 em `06:801-813`)**
- `06:285` / V1: hooks de `--settings` somam com os do usuário e recebem `session_id`, `source`, `last_assistant_message`, `notification_type`.
- `06:349`: Codex `SessionStart.session_id`. `06:350` / V7: campos de `opencode session list --format json`.
- `06:368` / V8: `claude --resume` depois de mover a pasta.
- `06:377` / V6: hooks e `mcp_servers` do Codex por `-c`; trust (provável problema, §1).
- `06:395` / V3: `permissions.deny: ["Skill(racky)"]` vale com `--dangerously-skip-permissions`.
- `06:423`: `OPENCODE_CONFIG`.
- `06:462` / V2: nome da ferramenta de pergunta (`AskUserQuestion`?).
- `06:466`, `06:480`: `last_assistant_message` no `Stop` do Claude e do Codex.
- `06:472`: payloads exatos do Codex.
- `06:534`: `~/.agents/skills` no Claude. `06:537`: pasta de agentes do OpenCode.
- `06:552` / V4: `--plugin-dir` segue symlink; `-c` para caminhos de skills do Codex.
- `06:553`: agentes do Codex por `-c`. `06:572`: precedência no Codex.
- V5 (bloqueia TA-209): `--resume` com flags regeneradas restaura skills e MCP.
- V9: bracketed paste chega sem Enter. V10: `gh run view --log-failed --job`. V11: env do zsh.
- **Sem linha V, mas dependentes de CLI:** `claude agents --json` (`06:360,398`); encadeamento de `statusLine` e `rate_limits.five_hour/seven_day` (`06:381`, AC-1001); `notification_type` = `permission_prompt`/`idle_prompt` (`06:465`); timeout de hook 5 s; `-n/--name` como título (`06:188`); `--session-id` mais `/clear` (`06:348`); **Codex app-server daemon** (novo, §1).

**07 (`07:8` define a convenção; spikes S1–S6 em `07:759-764`, todos agendados para a Fatia 3)**
- `07:113`: publicação de porta só pelo gate.
- `07:148`: estimativas de memória "a medir com o lote de 15".
- `07:182`: custo Zyte por unidade (S6: existe API de uso?).
- `07:248` / S1: `mcpServers` inline por subagente e `agent_id` nos hooks na 2.1.302.
- `07:486`: filhos do Codex por hooks.
- `07:602`: modo de permissão padrão na box.
- `07:614`: uid 10004 e virtiofs no Colima e OrbStack.
- `07:626`: `codex login --device-auth` num container auxiliar.
- `07:628`: gateway de credenciais.
- `07:647`: hooks `type:"http"`.
- `07:649`: mensagens pai ↔ filho isolado.
- `07:738` / S4: `deny` de `Skill(racky)`.
- S2: porta e DNS em rede `internal` no Docker Desktop, OrbStack e Colima. S3: noVNC em WKWebView ≥ 20 fps.

**08 (questões em aberto, `08:731-737`)**
1. Parse de VT fora do main (agora com o dado novo do SwiftTerm 1.99, S-02).
2. Hooks do Codex por `-c` sem tocar `~/.codex` (S-05).
3. ScreenCaptureKit sem Gravação de Tela (S-07).
4. Imagem GHCR pública ou privada.

**01 (pontos que o dono ainda precisa confirmar, `01:665-675`)**
- Raiz de worktree `~/orca/workspaces/<repo>/<nome>`.
- "Computer" na UI e "box" só nas ferramentas.
- Sessões importadas sem processo, 5 mais recentes + "Show N more".
- Forma do helper da barra de menus.
- Diálogo do primeiro ⌘Q.
- Nome automático `quiet-harbor`.
- Importar a chave Zyte na v1.

Também: `stalled` "há N minutos" (N indefinido, `01:533`); `stale` "além da janela" (`02:140`); detecção de "o CLI não deixa desligar item global" (`01:385`).

**04**
- Nome do pacote do DS (`04:15,79`).
- Blur do scrim "se o Instruments mostrar < 1 ms" (`04:44,271`).
- Dono do `ui-kit.css` (`04:690`).
- Entrada `LAYOUT` do render (`04:679`).
- Processo de aprovação de tokens `"draft": true` (`04:704`).
- Aprovação do dono como gate de cada momento (`04:712,757`).
- P2 "v1 se couber" (`04:795`).

**03**
- `Stop` de subagente "se o harness suportar" (`03:298`).
- Grupos de split por arrasto (`03:347`).
- O que é "zoom da UI" fora do terminal (`03:1196`).
- Como detectar "shell ocioso" na confirmação de fechar (`03:1050`).

**00**
- P7 (credenciais do modo isolado) decidido só na abertura da v1.1.

**05**
- Metas de desempenho "iniciais, o 08 pode recalibrar" (AC-608).
- Microcopy "o 03 pode refinar" (`05:22`).

---

## 7. "Tudo que clica funciona": o que garante e o que falta

**Já existe:**
- AC-T01: todo controle interativo tem `accessibilityIdentifier`, com varredura.
- AC-T02: toda ação do registro central tem teste que dispara e confere efeito; todo desabilitado tem tooltip com o motivo.
- `ctl ui action` pelo view model, e o índice de IDs no `03:1339-1365`.

**Furos e correções propostas:**

1. **Nada obriga o controle a estar no registro.** Um `Button { … }` solto passa na varredura de IDs se tiver ID, e ninguém testa a ação dele. Correção: lint que falha em `Button(`/`.onTapGesture`/`NSButton` cujo `action` não seja `ActionRegistry.perform(.id)`. Assim, toda interação de UI tem um `ActionID`, o registro é a fonte do índice e o teste de cobertura confere registro × testes.
2. **Disparar pelo view model não prova que o clique funciona.** Overlay por cima, view de tamanho zero, foco roubado e responder chain errado passam. Correção: para cada `ActionID`, **um** XCUITest com `click()` ou atalho real. O `ctl ui action` fica para as jornadas longas.
3. **"Erro visível" conta como efeito.** Um botão que sempre dá erro passa. Correção: o teste declara o efeito esperado (estado, navegação ou erro **específico**).
4. **Itens sem comportamento definido no 03.** São 25 ou mais; exemplos: `Check for Problems`, `Hide App Name`, `Locate…`, `Show Launch Details`, `Show Hook Log`, `Refresh Git`, `Reauthorize Folder…`, `Collapse All Sessions`, `Mute Notifications`, `Rename Branch…`, `Restart with ▸`, `Reset Title`, `Send SIGINT`, `Close Other Panes`, `Equalize Pane Sizes`, `Open Computer…`, `Agent Settings…`, `Manage Agents…`, `[Open Diagnostics]`, `Stop All Agents…`, `Pause Notifications for 1 Hour`, `Racky Help`, `Hide from Sidebar` e "Open in…" (quais editores e terminais, configurados onde). Correção: cada um ganha linha numa **tabela de ações** (ID, rótulo, atalho, fatia, pré-condição, efeito, estado desabilitado com motivo, teste), ou sai da v1.
5. **Estados desabilitados quase não estão especificados.** Só cinco aparecem (`03:82,462,536,555,784`). A tabela de ações do item 4 resolve.
6. **Conflitos de atalho.** ⌘⇧T, ⌘⌥setas, ⌘⇧E e ⌥⌘M (§2.2). ⌘F com três escopos num só key equivalent. ⌃⇥ e ⌃1…9 globais tirados do PTY (consistente com `03:1335`, mas convém registrar). ⇧⌘⌫ com o terminal focado. Correção: `KeyBindingRegistry` com escopo explícito e teste que falha em atalho duplicado no mesmo escopo, ou que conflite com a lista reservada do terminal.
7. **Teclas no terminal só em teste MANUAL** (AC-T08: Shift+Enter, ⌘←…). Correção: uma tabela tecla → bytes esperados (por exemplo Shift+Enter → `ESC [13;2u` ou `\n` conforme o Orca), com teste de unidade no `TerminalSurface`.

---

## 8. Itens grandes demais para uma tarefa (consolidado)

Cada linha abaixo precisa virar várias tarefas:
- Daemon (protocolo, auth, launchd, ring/cut, cold log, backpressure, N-1).
- `TerminalSurface`.
- Adapters de lançamento (4 CLIs, probe, perfis, injeções, prompt em arquivo).
- Atividade (hook helper, spool, máquina de estados, notificações).
- Ciclo de quit e menu bar.
- Git worktree (4 origens + FSEvents).
- GitHub.
- Biblioteca.
- Importação do Orca.
- Onboarding.
- `ctl` + registro + varredura.
- Store (migrações, backup, corrupção).
- Card de sessão (`03:188-255`, 9 estados + hover card + menu).
- Composer (`03 §6`).
- Máquina de estados do pane.
- Atalhos e menus (`03 §18/§21`).
- Settings.
- Painel direito.
- Viewer.
- Infra de motion e cada cadeia obrigatória.
- `TooltipController` e `DSCombobox` (cada um é um componente AppKit não trivial).
- Pipeline de tokens.

---

## 9. Fatia 0: fechamento antes de codar (proposta)

| # | Item | Responsável | Pronto quando |
|---|---|---|---|
| F0-1 | **Errata R3** no `00-decisions.md` decidindo cada linha de §2.1/§2.2/§2.3, mais a tabela de correspondência `M:Xn → M-xxx` e a unificação dos IDs de acessibilidade (o 03 §22 vira a única lista; o 04 passa a citá-la) | Dono decide; agente redige | Nenhuma linha de §2 sem decisão; `grep` por `M:[A-F][0-9]` nos capítulos retorna 0 |
| F0-2 | Redefinir a Fatia 1 no `01:86` conforme o §10 (sem Conversations, importação do Orca, onboarding completo e momento 3 de motion) | Dono | `01 §4.1` atualizado |
| F0-3 | **Pacote de referência do Orca 1.4.219** (§5.1) + script de extração do `app.asar` + remoção das citações a `scratchpad/orca-src` | Agente com Gravação de Tela + dono valida | `docs/rebuild/reference/orca-1.4.219/manifest.json` cobre todas as superfícies da Fatia 1 |
| F0-4 | **Tabela de ações da Fatia 1** (ID, rótulo, atalho, efeito, desabilitado/motivo, teste) derivada do 03 | Agente; dono revisa | Todo controle visível na Fatia 1 tem linha; o que não tem sai da UI |
| F0-5 | Spikes S-01 a S-07 (§6.1) | Agentes, em paralelo | Relatório e evidência em `docs/evidence/spikes/`; decisões refletidas no 06/08 |
| F0-6 | Declarar `design/` legado (mover para `legacy/design/`) e definir o destino de `Package.swift`/`Sources/`/`Tests/` antigos | Dono | O agente da tarefa T-01 não encontra código antigo no caminho do build |
| F0-7 | Fixar versões: XcodeGen (zip + SHA), SwiftTerm (após S-02), GRDB, Geist (versão + SHA + `OFL.txt`) | Agente | `bootstrap.sh` falha com versão errada |

---

## 10. Decomposição da Fatia 1 (shell + terminais + sessões limpas + composer + auto-launch)

**Escopo proposto da Fatia 1.**
- Janela e chrome, sidebar (Projects + seção de sessões limpas), tab row, splits.
- Terminal SwiftTerm Metal ligado ao daemon. A Fatia 1 roda com o daemon como **filho do app** (modo degradado do `06:64`, mesmo protocolo); o LaunchAgent e a sobrevivência ao ⌘Q entram na última tarefa da fatia, se o S-01 passar.
- Sessões limpas, composer (todas as origens, inclusive worktree nova) e Quick Launch.
- Auto-launch de Claude, Codex e shell com perfil, prompt como argumento e `--session-id`.
- Motion mínimo: overlays M-101/102/103, pendente M-204/205, tabs M-301/302/304, split M-306/307, ignição M-503/504/506, toast M-110, com fallbacks de Reduce Motion primeiro.
- Fica de fora: estado por hooks (o card mostra só o estado do processo, e o agente aparece como `unknown`), PR/GitHub, importação do Orca, Conversations, onboarding além de "CLI detectado / não logado", computadores, Library e status bar.

**Regras para toda tarefa** (DoD do `08:647`, ajustada):
- O agente recebe: os IDs de requisito e de AC citados, a linha da tabela de ações, os PNGs de referência do Orca e a errata.
- O agente entrega:
  - (a) build Swift 6 sem warnings, `lint.sh` e `lint-ui.sh` passando;
  - (b) testes na camada certa;
  - (c) para UI, `compare-ui.sh` com lado a lado e diff em `docs/evidence/ui/<tarefa>/`, e `LayoutConformanceTests` das medidas tocadas;
  - (d) XCUITest com clique real para cada `ActionID` novo;
  - (e) um vídeo curto (`ctl record`) quando há interação;
  - (f) lista do que **não** fez.
- O dono aprova a evidência visual antes do merge.

| ID | Tarefa | Escopo | Arquivos principais | Depende de | Pronto quando | Evidência exigida |
|---|---|---|---|---|---|---|
| T-01 | Esqueleto e build | `project.yml` (XcodeGen fixado), `Packages/RackyKit` com os alvos da AR-121 vazios, Swift 6, `defaultIsolation`, `bootstrap/gen/build/install.sh`, certificado local, CI macOS (build + lint + testes vazios) | `project.yml`, `Packages/RackyKit/Package.swift`, `scripts/*.sh`, `.github/workflows/` | F0-6, F0-7 | App vazio assinado instala, abre e passa `codesign --verify --strict` com o DR esperado; CI verde | Log do `build.sh`, saída do `codesign -dr -`, link do CI |
| T-02 | Registro de ações, A11yID e `ctl` mínimo | `ActionRegistry` (ActionID → handler, enabled, motivo), `A11yID` tipado, `app.sock` (só serviço `ctl`, opt-in), `racky ctl state/ui tree/ui action/ui wait/screenshot/record`, teste de varredura, lint de `Button` sem registro | `RackyCore/Control/`, `RackyUI/Actions/`, `racky/ctl`, `scripts/lint-ui.sh` | T-01, S-07 | `ctl ui tree` lista a janela vazia; `ctl screenshot` gera PNG; o lint falha num `Button` solto de teste | PNG + JSON da árvore |
| T-03 | Tokens e fontes | `design/tokens/*.json` (cor, tipo, espaço, raio, sombra) a partir do 02; gerador → `DS.Color/Font/Space/Radius`; `design/motion/tokens.json` → `MotionTokens.generated.swift` + `tokens.js`; Geist embutida com `OFL.txt`; teste de paridade JS↔Swift (04 A1) | `design/tokens/`, `design/motion/tokens.json`, `scripts/gen-tokens.py`, `RackyDesignSystem/Tokens/` | T-01 | Teste de que todo token do 02 §4–8 existe com o valor certo; `Font.custom("Geist")` resolve (teste) | Página de amostras renderizada (`ctl screenshot`) ao lado das cores e tipos do Orca |
| T-04 | Protocolo do daemon | `RackyProtocol`: framing, DTOs de todas as ops e eventos com o schema unificado (F0-1), códigos de erro, capabilities, fixtures JSON | `RackyProtocol/`, `Tests/ProtocolTests/Fixtures/` | T-01, F0-1 | Encode/decode de todas as fixtures; frame > 1 MiB rejeitado; teste N vs N-1 com fixtures | Relatório de testes |
| T-05 | Tipos de domínio e Store da Fatia 1 | Modelos `Project, Worktree, Session, Tab, PaneLayout, Terminal, LaunchProfile, LaunchSpec` (Sendable); GRDB `v1_initial` só com as tabelas da Fatia 1, mais `setting` e `ui_state`; backup pré-migração; `ValueObservation` no MainActor | `RackyCore/Domain/`, `RackyStore/` | T-01, F0-1 | Testes de CRUD, migração a partir de banco vazio, corrupção abre em modo leitura com banner (AR-322) | Relatório de testes |
| T-06 | `rackyd` núcleo (modo filho do app) | PTY spawn (forkpty, pgid), `create/list/attach/detach/resize/signal/kill/subscribe/textSnapshot/forget/ping`, ring 4 MiB com ponto de corte e preâmbulo, coalescência, backpressure, emulador headless que nunca responde OSC 52 de leitura, dono das respostas de consulta (AR-105). Escuta num socket privado passado pelo app | `rackyd/`, `RackyTerminalCore/` | T-04, S-04 | `DaemonTests`: matar o cliente e reanexar devolve a mesma tela (`textSnapshot`) com `vim` e um TUI de teste; ninguém responde a `OSC 52;c;?` | `textSnapshot` antes e depois |
| T-07 | Peer auth | `LOCAL_PEERTOKEN` + requisito de código; caminho de CI decidido no S-03 | `RackyPlatform/PeerAuth/` | T-06, S-03 | Peer assinado aceito e não assinado recusado, no Mac e no CI | Logs `daemon.auth` |
| T-08 | Env de login | Captura com marcador, fallback, denylist (incluindo `ORCA_*`), cache e invalidação | `RackyPlatform/LoginShellEnv/` | T-01, S-06 | Testes de unidade + AC-312 com o shell do dono | Saída `which claude codex gh` dentro de um pane |
| T-09 | `TerminalSurface` | `TerminalHostView` com `TerminalView` (nunca `LocalProcessTerminalView`), Metal, delegate próprio (`clipboardRead → nil`, OSC 52 de escrita conforme o setting), tema do 02, `PTYClient` actor com alimentação por orçamento, política de paste e links, find bar própria com a busca pública do SwiftTerm, zoom ⌘=/⌘-/⌘0, tabela tecla→bytes | `RackyUI/Terminal/`, `RackyCore/PTYClient/` | T-03, T-06, S-02 | AC-T05, AC-T07 (p95 ≤ 50 ms com 4 panes), testes tecla→bytes, comparação visual do terminal com o Orca (fonte, cor, inset 4) | `bench.sh`, PNG lado a lado |
| T-10 | Janela e chrome | `MainWindowController` (fullSizeContentView, sem NSToolbar), semáforos em 16/36/56 × 18 reaplicados em resize e tela cheia, faixa de titlebar 36, `MainSplitViewController` com sidebar 280 (220–500, ⌘B), centro e painel direito **oculto na Fatia 1**, janela mínima 760×480 e inicial 1440×900, error boundaries | `RackyUI/Window/` | T-02, T-03 | `LayoutConformanceTests` (semáforos, faixas, larguras); XCUI de ⌘B, resize e tela cheia | Lado a lado com `orca/main-empty.png` + diff |
| T-11 | Overlay host e componentes base | `OverlayPanelHost/OverlayRouter` com o contrato de foco (`02:718-727`; nenhuma tecla vai ao PTY, AC-T06), `DSButton`, `DSIconButton`, `DSTextField`, `Keycap`, `DSSegmented`, `DSSwitch`, `ConfirmationOverlay`, `ToastCenter`, motion M-101/102/103/110 com fallback RM | `RackyDesignSystem/Components/`, `RackyUI/Overlay/` | T-03, T-10 | AC-T06; snapshot aprovado de cada componente ao lado do crop do Orca | PNGs, vídeo do overlay abrindo e fechando |
| T-12 | `DSCombobox`, `DSMenuPanel`, `TooltipController`, `PromptEditor` | Componentes AppKit com type-ahead, delays de tooltip (400/500/1000/200 ms), IME, ⌘↵ | `RackyDesignSystem/Components/` | T-11 | Testes de teclado; snapshots aprovados | PNGs + vídeo |
| T-13 | Sidebar: estrutura | `ScrollView` + `LazyVStack` (sem `List`), seções Projects e de sessões limpas (nome da errata), linha de projeto, card de sessão **na versão da Fatia 1** (título, pasta ou branch, linhas de agente com estado do processo e `unknown`), linha pendente com fases, rename inline, estados vazios, teclado (⌘1…9 fica para a Fatia 2), menus de contexto só com as ações da tabela da Fatia 1 | `RackyUI/Sidebar/` | T-05, T-11, F0-4 | `LayoutConformanceTests` (alturas 32/28/24, card raio 10, padding 6); XCUI com clique real de cada ação do menu | Lado a lado com `orca/sidebar-*.png` (ativo, hover, pendente, vazio) |
| T-14 | Tabs e panes | Tab row 32 + 4, tab 180/220 (mín. 72), overflow, rename, reordenar, fechar com confirmação (`kill graceful`, "Force Quit" após 5 s), ⌘⇧T; árvore de splits ⌘D/⌘⇧D, divisor 3 pt / hit 9, tamanho mínimo, header de pane com 2+ panes, foco ⌘]/⌘[, opacidade 0,8 inativo; persistência do layout; motion M-301/302/304/306/307 com um resize por transição | `RackyUI/Tabs/`, `RackyUI/Panes/` | T-09, T-11, T-05 | Contador de resize do PTY = 1 por gesto (04 A6); resize, colapso ou troca de tab nunca recriam PTY (teste); XCUI de cada ação | Vídeo de split/fechar + PNG lado a lado |
| T-15 | Adapters de lançamento | `LaunchPlanner`: perfis (Claude, Codex, shell; OpenCode opcional), resolução terminal → projeto → global, probe de CLI (instalado, logado), argv dourado por adapter e perfil, `--session-id` no Claude, prompt como argumento com o limiar da errata, sem injeções na Fatia 1 (ou com, se a errata decidir; AC-307 ajustado), env da execução | `RackyCore/Launch/` | T-05, T-08, F0-1 | Testes de argv com golden files para cada combinação; zero bytes escritos no PTY pelo app (teste com o daemon) | Golden files |
| T-16 | Fluxo de lançamento e estados do pane | Criar terminal → `create` no daemon → ignição se o primeiro byte demorar > 300 ms (M-503/504/506) → Running / Exited / Couldn't start (Retry, Open Agent Settings, Copy Details) / DaemonUnavailable; `LaunchProgress` | `RackyCore/Launch/`, `RackyUI/Panes/States/` | T-14, T-15 | XCUI de cada estado com CLI falso (sucesso, demora, falha no spawn, saída precoce); AC-310 | Vídeo dos quatro casos |
| T-17 | Sessões limpas | Gerador de nome (errata; nunca reaproveita pasta existente, AC-1102), criação em `~/Racky/sessions/`, um clique no "+" → tab com o agente padrão e foco no terminal em menos de 1 s (AC-1101), "in Folder…", rename sem mexer na pasta (AC-1103), apagar com "Move folder to Trash" só se a pasta for gerenciada (AC-1105/1108), promoção na forma da errata | `RackyCore/Sessions/`, `RackyUI/Sidebar/` | T-13, T-16 | AC-1101…1108 da Fatia 1 em XCUI e E2E | Vídeo do clique ao agente rodando |
| T-18 | Git mínimo | `GitService` async: detectar repo, listar worktrees, `worktree add` com branch e prefixo, base `origin/main`, fetch com timeout, erros mapeados para "Use Existing Branch" e "Create Without Fetching" | `RackyCore/Git/` | T-05 | Testes com repositório temporário (branch existente, fetch falho, pasta ocupada) | Relatório de testes |
| T-19 | Projetos | "Add Project…" (pasta, bookmark), linha de projeto, remover projeto (sem apagar arquivos) | `RackyCore/Projects/`, `RackyUI/Sidebar/` | T-13, T-18 | XCUI | PNG lado a lado |
| T-20 | Composer ⌘N | Overlay (largura da errata), campos `03 §6.1` (Project, Where por contexto, Create from só com nome de branch na Fatia 1; `#123`/URL ficam para a Fatia 2), Agent, Profile, Prompt, Advanced (Session name, Branch, Worktree location; **sem** "Subagent computers" e "Watch Claude subagents"), linha de resumo do comando, validação, "Create More", Esc com descarte; ao criar: fecha na hora, linha pendente, tab rodando (P9) | `RackyUI/Composer/` | T-12, T-15, T-16, T-18, T-19 | AC-301, 302, 305, 306, 307–309, 313, 314, 316; XCUI com clique real em todo campo; tempo do submit até o pane com output | Vídeo + PNGs lado a lado de cada variante do "Where" |
| T-21 | Quick Launch (⌘⌥N / "+") e ⌘T | Popover `DSMenuPanel` com agentes e perfis, "Start <agente> with …", ⇧↵ em split; ⌘T shell; ⌘⌥T agente padrão | `RackyUI/QuickLaunch/` | T-12, T-16 | XCUI de cada item; AC-313 | PNG lado a lado |
| T-22 | Menus do app e atalhos | `KeyBindingRegistry` com escopo, menus `File/Edit/View/Window/Help` só com as ações da Fatia 1 (o resto não aparece), teste anti-conflito, teclas reservadas ao terminal | `RackyUI/Commands/` | T-02, T-14, T-20 | Teste de conflito; XCUI disparando cada atalho | Tabela gerada dos atalhos |
| T-23 | Persistência e reabertura (sem LaunchAgent) | Ao reabrir o app: sessões, tabs e layout voltam; terminais mortos aparecem como "Interrupted" com [Resume] (`claude --resume <id>`) e [Start Fresh] | `RackyCore/Sessions/Restore` | T-14, T-15 | XCUI: fecha, abre e confere a mesma árvore; Resume executa o argv correto | Vídeo |
| T-24 | Daemon como LaunchAgent e ⌘Q mantém agentes | `SMAppService`, socket do S-01, ⌘Q com "Keep Running", ícone na barra de menus, reattach com scrollback, cold restore depois de `kill -9` | `rackyd/Launchd`, `RackyUI/MenuBar/`, `RackyCore/AppLifecycle/` | T-06, T-07, T-23, S-01 | `e2e.sh` passos 1–3 e 7 (`08:625`): mesmo PID depois de quit/launch; cold restore | Log do e2e + vídeo |
| T-25 | Fechamento da fatia | Varredura AC-T01/T02 com clique real, `compare-ui.sh` de todas as telas da fatia, Reduce Motion, janela mínima, um dia de uso real do dono | — | Todas | Relatório da fatia com a lista do que diverge do Orca e por quê | `docs/evidence/slice1/` |

**Grafo de dependências.** As tarefas podem andar em paralelo assim: T-01 → {T-02, T-03, T-04, T-05, T-08} → {T-06 → T-07, T-09, T-10 → T-11 → T-12, T-18} → {T-13, T-14, T-15} → {T-16, T-19} → {T-17, T-20, T-21, T-22} → T-23 → T-24 → T-25. Não há ciclos depois que o `ctl` (T-02) sobe para o começo.

**Tamanho.** Cada tarefa cabe em uma sessão de agente de um a dois dias de trabalho. Duas exceções: T-06 e T-09, que podem ser divididas em "núcleo" e "endurecimento" se o spike mostrar complexidade.

---

## 11. Resumo dos achados específicos do 07 e do 08

Estes pontos não afetam a Fatia 1 diretamente, mas precisam entrar na errata antes da Fatia 3:

1. **Papel do `rackyd`.** O 07 (`07:246`, CS-230/231/240) põe o MCP, o serviço de boxes, o `exec` pela Engine API e o reqlog **no daemon**. O 08 (`08:33`) diz que o daemon "não abre banco, não fala com Docker, git nem hooks". O 00 T1 diz "daemon de PTY". É a contradição de arquitetura mais cara do conjunto: a escolha errada gera ou um daemon inchado ou ferramentas que morrem no "Quit Completely".
2. **Sidecar: `gate` ou `egress`.**
   - O 07 usa `gate:3128` e `gate:8790`; o 08 usa `egress:8080`.
   - O container `work` é o shell da v1 no 07 e o CLI da v1.1 no 08.
   - A ferramenta de entrada é `computer_acquire` no 08 e `boxes_reserve`/`box_claim` no 07.
   - Labels divergem (`racky.owner=<installId>` contra `app.racky.mac`; `racky.box` contra `racky.computer`), e o nome da rede também.
   - A publicação de portas diverge: só o gate publica, ou API, VNC e admin publicam.
3. **Segredos da box.**
   - O 07 entrega por `docker exec -i` em tmpfs e nada fica em disco. O 08 AR-512 usa arquivo no host, `0400`, montado read-only, com a chave Zyte "do mesmo jeito".
   - A fórmula do token também diverge (`HMAC(master, boxId)` contra `HMAC(master,"box|"+id+"|"+generation)`).
   - É ponto de segurança; precisa de decisão explícita.
4. **Dados de execução.** O 07 usa `~/Racky/runs/...` e `~/Racky/worktrees/...`. O 08 AR-301 diz que tudo vive em `~/Library/Application Support/Racky/`.
5. **Admissão de computadores.** O 07 CS-130 usa a soma das médias móveis; o 08 AR-407 usa `floor((MemTotal−2GiB)/custo)`.
6. **Schema.**
   - O 07 CS-001 exige no SQLite tabelas que o 08 não tem: `BrowserProfile`, `HelpRequest`, `BudgetLedger`, `JournalEntry`, `CommandRecord`, `RequestRecord` e a fila persistente.
   - O `v1_initial` do 08 já inclui `computer`, `batch` e `budget`, e "migração publicada nunca é editada" (AR-320).
   - **Recomendação:** o `v1_initial` da Fatia 1 tem só as tabelas da Fatia 1; computadores entram como `v2_computers` na Fatia 3. Isso precisa estar escrito, senão o agente da T-05 cria as 19 tabelas e congela decisões da Fatia 3.
7. **Ciclo latente de módulos.**
   - O registro de ações vive na UI, o enum `A11yID` no DesignSystem (`08:597`) e o servidor `ctl` no Core (`08:122`).
   - O Core não pode importar SwiftUI nem DesignSystem (AR-130).
   - Sem um protocolo invertido (`ActionDispatching` no Core, implementado na UI e injetado no boot), o agente vai criar o import Core → UI. A T-02 do §10 precisa dessa definição.
8. **Lint com falso positivo.** O padrão `sleep(` (AR-131) pega o `Task.sleep(for:)` que o AR-404 prescreve; `Process` pega `ProcessInfo`; `print(` pega `fingerprint(`. Os padrões precisam ser regex com limite de palavra, e cada um precisa de um teste de lint.
9. **Critério de saída incoerente no 08.**
   - A etapa 4 sai com "fluxos 1–4 da AR-803 com shell", mas o fluxo 2 exige agente rodando (P9), e isso é da etapa 6.
   - A DoD (itens 3 e 4) depende da etapa 5.
   - Design system e motion (P8) não aparecem na ordem do `08 §10`.
10. **Exec com stdin pela Engine API** exige conexão hijacked/upgrade, que nenhum capítulo especifica. O 07 (CS-101, CS-440, CS-501) ainda usa o CLI `docker context ls` / `docker exec -it`, contra "CLI só para build/pull" (AR-114).
11. **Sem lane de teste no macOS 15**, que é o mínimo declarado (T3). O CI usa o runner mais novo e o dono está no 27. APIs como `defaultIsolation`, ScreenCaptureKit e `SMAppService` podem divergir entre versões.
12. **Marcadores e perguntas do 07.**
    - Os marcadores estão consolidados no §6.2. Q1 (container separado contra P5 "mesmo container") e Q2 (colar com Enter a pedido do pai, contra T11) **contradizem o 00** e estão marcadas "antes da v1".
    - Os spikes S1–S6 estão agendados só para a Fatia 3. S1 (identidade por filho via `mcpServers` inline) define o modelo de identidade inteiro do modo leve e deveria rodar já na Fatia 0, porque é barato.

---

## 12. Lista curta para o dono decidir (ordem de impacto)

1. Nomes canônicos: bundle id, label, socket, env, spool, launch dir e ops do protocolo, escolhendo 06 ou 08 em bloco (§2.1).
2. Nome da sessão sem projeto ("Scratch" ou "Clean"/"Sessions") e o conjunto de ações de promoção na v1.
3. Fatia 1 redefinida conforme o §10, e Fatia 0 aprovada.
4. Pacote de referência do Orca como gate visual por tarefa; o dono aprova o lado a lado antes do merge.
5. Controles de fatias futuras não são renderizados (feature flag por fatia).
6. SwiftTerm: 1.20.0 fixo agora, com a 1.99/2.0 avaliada em spike.
7. Papel do `rackyd` (só PTY, ou também MCP e boxes).
8. Entrega de segredos à box (stdin/tmpfs ou arquivo read-only).
9. Codex: hooks por `-c` com trust, `CODEX_HOME` temporário ou estado "estimated"; e `--no-daemon`.
10. Limiar do prompt em arquivo, regra do argv exato (AC-307) e nome automático das sessões.
