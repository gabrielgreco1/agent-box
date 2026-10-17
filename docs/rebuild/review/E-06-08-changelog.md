# E-06-08 · Changelog da edição de 06 e 08 após R1–R3

Data: 2026-10-16. Arquivos editados: `spec/06-terminals-and-agents.md` e `spec/08-architecture-quality.md`. Nenhum outro capítulo foi tocado. Base: `00-decisions.md` (P1–P16, T1–T14), `review/R1-consistency.md`, `R2-coverage.md`, `R3-implementability.md`. Os dois arquivos levam no topo "Revisado após R1–R3 em 2026-10-16".

## 1. Identificadores canônicos (resumo de `08 §0`)

A tabela completa está em `08 §0` (subseções 0.1–0.5) e é a referência que os outros capítulos devem citar. Os valores que mais mudaram:

| Tema | Canônico | Saiu |
|---|---|---|
| Bundle id | `app.agentbox.mac` | `app.agentbox` (06) |
| Assinatura | app `app.agentbox.mac`, daemon `app.agentbox.ptyd`, helper `app.agentbox.cli` | `app.agentbox.helper` |
| Label do daemon | `app.agentbox.ptyd.v1` (testes: `app.agentbox.ptyd.test-<n>`), plist `app.agentbox.ptyd.v1.plist` | `app.agentbox.daemon.v1` |
| Socket do daemon | LaunchAgent: `SecureSocketWithKey = AGENTBOX_PTYD_SOCK_V1` (caminho do launchd, lido por `launchctl getenv`). Modo degradado, testes e plano B: `AB/run/ptyd-v1.sock` com `bind` do próprio daemon | `SockPathName` com caminho no home (`daemon-v1.sock` / `ptyd-v1.sock`): o plist estático não expande `~` (risco de R3 §1) |
| Quem fala com o daemon | Só o app | `ctl` com `client.kind=ctl` (06) |
| Onde vivem MCP e Docker | No app (`AgentBoxCore`), vivo em `.accessory` após ⌘Q | No `agentboxd` (07) |
| Sidecar | `egress` (proxy `egress:3128`, API `egress:8790`) | `gate` (07), `egress:8080` (08) |
| Papéis de container | `runtime`, `work` (v1, `exec`), `egress`, `agent` (v1.1) | `work` = CLI isolado (08) |
| Rótulos Docker | `agentbox.owner=<installId>`, `agentbox.computer=<id>`, `agentbox.computer_name`, `agentbox.role=…` | `owner=app.agentbox.mac`, `agentbox.box` |
| Env da execução | `AGENTBOX_PANE_ID`, `AGENTBOX_RUN_ID`, `AGENTBOX_APP_SOCK` | `AGENTBOX_TERMINAL_ID`, `_HOOK_SOCKET`, `_HOOK_TOKEN`, `_SESSION` |
| Comando de hook | `"<bundle>/Contents/MacOS/agentbox" hook --provider <claude\|codex> --event <Evento>` | variante sem `--provider` (08) |
| Entrega do hook | timeout 200 ms; p95 ≤ 30 ms | 300 ms / < 50 ms (06) |
| Spool de hooks | `AB/run/spool/hooks/<runID>.jsonl`, 4 MiB, marcador `truncated` | `run/hook-spool/<terminalID>.jsonl` |
| Dir de lançamento | `AB/run/launch/<runID>/` | `run/launch/<terminalID>/<attempt>/` |
| Prompt em arquivo | > 16 KiB (bytes UTF-8) ou começa com `-`; `…/<runID>/prompt.md` | 64 KiB (06) |
| Ops do protocolo | `hello`, `create`, `list`, `attach{mode: snapshot\|sinceSeq}`, `detach`, `resize`, `signal`, `kill`, `subscribe`, `textSnapshot`, `forget`, `drainWhenIdle`, `ping`; input em frame `0x03` com `origin` | `drain` (08); `attach` sem `mode` (06); input sem origem |
| Frame de input | `sessionID | origin(u8) | bytes`; `seq` = offset em bytes | sem origem; `seq` indefinido |
| Backpressure | 2 MiB por cliente no daemon (backlog do app por pane: 4 MiB, outro limite) | 4 MiB (06) |
| Cold log | 2 × 8 MiB; `meta.json` = `terminalID`, `runID`, `argv`, `cwd`, `envKeys`, `pid`, `startedAt`, `exit` | 8 MiB (08); metas diferentes |
| Retenção `agent_event` | 30 dias **e** 10 mil por execução | 50 mil por terminal (06) |
| Debounce de layout | 300 ms | 500 ms (06) |
| Captura do env | `-l -i -c` em PTY oculto com marcador (5 s) → `-l -c` (3 s) → fallback | `-l -c` → `-lic` (08) |
| Tokens / DS | alvo `AgentBoxDesignSystem` em `Packages/AgentBoxKit/Sources/AgentBoxDesignSystem/`; fontes `design/tokens/*.json` e `design/motion/tokens.json`; `*.generated.swift` | `Sources/AgentBoxUI/Design/` (02), `AgentBoxDesign` (04) |
| `A11yID` / `ActionID` | `AgentBoxProtocol/Automation/`; registro via protocolo `ActionDispatching` no Core | enum no DesignSystem (ciclo Core → UI) |
| `session.kind` | `worktree` · `checkout` · `folder` · `clean` | `worktree` · `clean` (08) |
| Atividade do agente | `starting`, `idle`, `working`, `needsInput(kind)`, `waitingOnSubagents`, `done`, `failed`, `blocked`, `interrupted`, `unknown`, `stalled` (v1.1); `estimated` é flag | `exited`/`estimated` como estados (06); `waiting`/`permission`/`unverifiable` (08) |
| Processo/terminal | `notStarted`, `launching`, `running`, `exited`, `killed`, `failedToStart`, `interrupted`, `containerStopped` | `starting`/`failed`/`lost` (08) |
| Computador | `queued`, `provisioning`, `ready`, `inUse`, `stopped`, `failed`, `removing`, `removed`, `orphan` | `creating`/`running` (08) |
| Menu bar com app fechado | Sem helper; app em `.accessory`; "Quit Agent Box Completely" tira o ícone | helper de login (01/03) |
| Ferramentas | SwiftTerm 1.20.0 exato; XcodeGen 2.46.0 por zip + SHA-256; Geist com `OFL.txt` no bundle | "último 1.x"; Homebrew sem versão |

## 2. O que mudou em 06

- Topo: marca de revisão, P11–P16 nas decisões aplicadas, ponteiro para `08 §0` e `08 §11`, regra de prefixo `audit/`.
- §0: MCP, Docker e computadores no app; sidecar `egress`; regra 4 nova (T11 + exceção P12, com origem do input); spool novo no diagrama.
- §1.1–1.2: o helper não fala com o daemon; plist e label `ptyd.v1`; socket por `SecureSocketWithKey` com plano B e modo degradado; Fatia 1 roda em modo degradado.
- §1.3: protocolo unificado com 08 (ops, `attach` com `mode`, input com `origin`, `seq` em bytes, snapshot em frames, códigos de erro, capabilities, `inputBytesByOrigin`, backpressure 2 MiB, `client.kind` só `app`, auth só `app.agentbox.mac`).
- §1.4–1.6: só panes visíveis anexados (K-94); confirmação de fechar de 03 (K-45); Undo de 8 s (K-20); cold log 2 × 8 MiB com `meta.json` canônico; textos do crash do daemon (K-46) e "Resume Agents…" (K-37).
- §1.7: env da execução canônico; captura marcada como canônica com S-06.
- §1.8: pane mínimo 240 × 120 pt (K-17); foco só ⌘]/⌘[ (K-84); opacidade 0,8 (K-03); ⌘T shell, ⌥⌘T agente, ⌥⌘N Quick Launch (K-83); regra de resize de 04 (K-93); debounce 300 ms (K-16).
- §1.9: overlay de quit no primeiro ⌘Q com "Don't ask again" marcado por padrão (P15, K-90, D-12); sem helper de login (D-03); ícone conforme 03 §17 (K-53), sem `Never` (K-91).
- §1.10–1.11: `ptyd.v2`/`AGENTBOX_PTYD_SOCK_V2`; texto "Restart background service to update"; TA-101/103/104/106/107/108/112/115/116 ajustados.
- §2.2: aviso de `--bare`/`--safe-mode` (desligam hooks); linha `--no-daemon` do Codex pendente de S-05(c); nota de trust nos `-c`.
- §2.3: indicador `ShieldOff` (K-30); nomes de perfis importados (K-31).
- §2.4: limiar de 16 KiB; nova **§2.4.1** com os segmentos do argv e a regra de verificação dos ACs (argv exato sem o segmento `injected`; Fatia 1 sem injeções; zero bytes do app pelo contador por origem).
- §2.6–2.7: painel Conversations (K-38); "New Clean Session" ⇧⌘N, seção "Sessions", nome `quiet-harbor` (P11, P15); "Move to Project…" (K-34).
- §2.8–2.9: dir por `runID`; Fatia 1 sem injeções; opções da skill antiga Block in Agent Box / Disable Globally… / Keep, `Redirect` fora (K-40, D-11).
- §3.1: estados canônicos (K-78) com `blocked`, `interrupted`, `unknown`, flag `estimated`, Fatia 1 = `unknown`.
- §3.2: transporte de hooks canônico (K-18, K-15, K-71), sem `HOOK_TOKEN`.
- **§3.3.1 nova**: problema do trust por hash do Codex contra T10, tabela das saídas e por que nenhuma serve sem decisão, estratégia (Fatia 1 sem hooks; S-05; rollout `estimated` como baseline; hooks por `-c` só com S-05 ou D-Codex-1; alternativas notify, app-server e daemon compartilhado avaliadas no spike).
- §3.5–3.6: toggles de notificação (K-52); formato com computador (K-51); badge por AttentionItem 1–2 (K-54); Inbox no lugar do sino, "Next Needing Attention", "Since you were away" (K-27, K-29).
- §3.7: TA-303, 307, 311, 312, 313.
- §4: TA-411 (palette "Insert Skill/Agent…", R2 SEM #1) e TA-412 (later: memória do Claude, renomear conversa, promover execução; R2 SEM #9/#16/#17).
- §5: `.worktreeinclude` em v1.1 (K-89a); diff e clone em v1.1, merge/device flow/comentar PR em later (K-64, K-89g, R2 SEM #10); colagem de "Send Failures" com origem `0x02`.
- §6: perfis importados (K-31); "Import Again…" em Settings › Import (K-55); textos de coexistência com o Orca (R1 §10).
- §7: V6 ligado à §3.3.1; V12 (app-server daemon) e V13 (itens de CLI sem linha V) novos; E2E com `ctl app quit`; ponteiro para `08 §11`.
- Referências da auditoria prefixadas com `audit/` (X-16, X-18, X-21).

## 3. O que mudou em 08

- Topo e convenções: marca de revisão; `later` no lugar de `v2` (K-73); regra `audit/` aplicada a todas as 92 referências da auditoria.
- **§0 Identificadores canônicos** (nova, tabela única em cinco blocos).
- §1.1–1.2: processos com MCP/Docker no app, egress sem orçamento (P13), `work` (v1) e `agent` (v1.1) (K-66); diagrama ajustado.
- AR-101 (socket por `SecureSocketWithKey` + plano B), AR-102 (protocolo unificado com 06), AR-103 (captura de 06, K-19), AR-104 (cold log 2 × 8 MiB, `interrupted`), AR-108 (sem helper, primeiro ⌘Q, §8.3), AR-109, AR-111, AR-112 (comando com `--provider`, Codex por 06 §3.3.1, Fatia 1 sem injeções), AR-113 (`egress:8790`, K-67), AR-114 (owner `installId`, exec hijacked da Engine API).
- AR-120 (XcodeGen 2.46.0 por zip + SHA-256), AR-121 (`Automation/` no Protocol, DS no caminho canônico, `ActionRegistry`), AR-122 (SwiftTerm 1.20.0 exato, proibições, Geist com `OFL.txt`, argument-parser explícito), AR-130, AR-131 (regex com limite de palavra e teste de lint; proíbe `LocalProcessTerminalView` e a find bar privada), **AR-134** nova (`ActionDispatching`, sem ciclo Core → UI).
- **AR-202** nova: código antigo e `design/` movidos para `legacy/` na Fatia 0.
- §3.1: layout com sockets, spool, sessões e run folder fora de `AB` (K-98).
- §3.2: schema reorganizado por migração: `v1_initial` só com tabelas da Fatia 1 (com colunas de K-81 e as que R3 §3 apontou: nota com autor, `last_message`, `unread`, `import_source_id`, cor, opt-out de cold log, `add_dirs`, `not_started`); `v2_activity` (estados K-78, `priority`, `inbox_event`); `v3_computers` (estados K-80, `computer_queue`, `browser_profile`, `help_request`, **`proxy` e `proxy_usage` genéricos, sem orçamento**, P13); `v4_batches` e `v5_legacy_runs` na v1.1. A tabela `budget` saiu.
- AR-321/331 (microcopy), AR-341 (`interrupted`, `unknown`), AR-342 (fonte `profile-state.db`, contagens do dia; K-96, K-23), AR-343 (v1.1, chave Zyte vira proxy com preset).
- AR-404/605/706 (`boxes_reserve`/`box_claim`, K-65), AR-406 (dois limites distintos, S-02), AR-407 (fórmula de admissão é de 07), AR-501 (Settings › Advanced › "Security model"), AR-502 (A2, A11 sem orçamento), AR-512 (credencial do proxy), AR-520, AR-602, AR-603, AR-604, AR-710 (resize de 04).
- §8: snapshots só no tema escuro (K-92) e aprovados pelo dono; fluxos P0 com item 8 (XCUITest com clique real por `ActionID`) e ordem por fatia; AR-805 (IDs de 03 §22, `takeOver`/`handBack`, lint de `Button` fora do registro, feature flag por fatia); AR-806 (Settings › Advanced, `ctl` na T-02, `ctl app quit` sem `--keep`, `inputBytesByOrigin`); **AR-808** (pacote de referência do Orca + `compare-ui.sh`, P14) e **AR-809** (`LayoutConformanceTests`) novas; E2E com nomes novos; CI com lane `macos-15` e receita de peer auth (S-03); DoD reescrita (isenção da T-01, OK do dono por tela, tema escuro, clique real, lista do que não fez).
- §9: bootstrap com versões fixadas, scripts novos, textos de AR-904.
- §10 reescrita: Fatia 0 + etapas alinhadas às tarefas T-01…T-25 de R3 §10, com `ctl` e `A11yID` na etapa 1, DS e motion na ordem, LaunchAgent no fim da Fatia 1, critérios de saída coerentes.
- **§11 Spikes e verificações** (nova; substitui "Questões em aberto"): S-01…S-08 com dono, bloqueio, critério e plano B; V1–V13 e demais itens de CLI; marcadores de 07; perguntas abertas por capítulo.

## 4. O que não apliquei, e por quê

| Item | Motivo |
|---|---|
| Patches de R1/R2/R3 em 01, 02, 03, 04, 05 e 07 | Fora do meu escopo; outros editores. A tabela `08 §0` é o que eles devem seguir. Pontos a conferir por eles: AC-307/308/312/313 e AC-T03 (05) contra 06 §2.4.1 e AR-806; 01 §6.2 precisa ganhar `notStarted` e `failedToStart`; 03 §17 e §16.10 precisam do ⌘Q de primeira vez e de "Show menu bar icon" sem `Never`; 07 precisa de `egress`, MCP no app, `box_claim` e entrega de segredo por arquivo |
| D-Codex-1 (aceitar trust de hooks gravado pelo próprio Codex) | É zona cinzenta de T10; só o dono decide. Documentei o problema e a estratégia sem violar T10 (06 §3.3.1) |
| `--no-daemon` do Codex como padrão | Depende do S-05(c); o adapter não passa a flag até o spike fechar |
| Socket por `SecureSocketWithKey` como fato | Não verificado nesta máquina; é o canônico proposto, com plano B escrito. O plano B desvia de T1 e exige registro no 00 |
| SHA-256 do XcodeGen e versão/SHA da Geist e do GRDB | Preenchidos em F0-7 por quem roda o bootstrap; não baixei binários nesta edição |
| Fórmula de admissão de computadores (R3 §11.5) e segredos por stdin × arquivo | Admissão: deixei 07 como dono (R1 não deu patch). Segredos: mantido o arquivo `0400` de 08, como R1 K-77; 07 precisa seguir |
| Verbos Take Over/Hand Back nos IDs (`.takeOver`) | Apliquei a recomendação de R1 D-02 via P16 em AR-805; se o editor de 02/03 escolher outro par, AR-805 precisa acompanhar |
| R2 SEM itens fora de 06/08 (lote concluído, validação de caminhos, perfil do Chromium, regras do worker etc.) | Pertencem a 03/07 |
| Tabela de ações completa da Fatia 1 (R3 F0-4) e pacote de referência do Orca (F0-3) | São entregas da Fatia 0, não texto de spec; 08 exige os dois (AR-805, AR-808, §10 F0) |
| Lint de UI detalhado (R3 §5.4) | O conteúdo de `lint-ui.sh` é do 02; 08 fixa só a mecânica (Button fora do registro, proibições de terminal) |
