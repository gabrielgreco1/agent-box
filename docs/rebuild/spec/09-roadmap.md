# 09 · Roadmap de implementação para agentes de código

Status: spec do rebuild. Data: 2026-10-16. **Prevalece** `00-decisions.md`; em seguida os capítulos 01–08 na ordem de precedência de cada tema. Este capítulo não cria requisito: ele ordena, quebra em tarefas e diz como provar que cada uma está pronta. Se ele divergir de um capítulo, o capítulo vence e este é corrigido na mesma PR.

Fontes: 01 §4 (escopo e fatias), 08 §10 (ordem técnica), 08 §11 (spikes e verificações), 08 AR-820 (DoD), 05 (ACs) e `review/R3-implementability.md` §6–§10 (Fatia 0 e decomposição da Fatia 1), reconciliados com a spec já revisada (`review/E-*.md`).

Quem lê: o agente de código que recebe uma tarefa (leia §5 e a tarefa), o dono (leia §1, §6 e §7).

---

## 1. Visão geral das fatias

Cada fatia de produto termina com **um dia de uso real** do dono e só fecha com os ACs de saída verdes, a evidência visual aprovada (P14) e o relatório da fatia em `docs/evidence/sliceN/`. Controle de fatia futura não é renderizado (AC-T28). A Fatia 0 não produz produto, produz o chão: referência visual, spikes, scripts e versões fixadas.

| Fatia | Objetivo | O dono consegue, ao final | Dia real de saída | ACs de saída |
|---|---|---|---|---|
| **0 · Fechamento** | Nada de código de produto antes de: errata aplicada, referência do Orca versionada, spikes S-01…S-08 respondidos, scripts de gate e versões fixadas | Abrir o repositório e ver que toda tarefa da Fatia 1 tem referência, dono, critério e script para ser provada | Não há dia de uso. Saída: checklist da §2.6 inteiro verde, aprovado pelo dono | Nenhum AC de produto. Gate: `bootstrap.sh` falha com versão errada; relatórios dos spikes em `docs/evidence/spikes/` |
| **1 · Casca, terminais e sessões limpas** | Substituir o Orca em trabalho **sem** computadores: janela, sidebar, tabs, splits, composer, Quick Launch, sessões limpas, daemon que sobrevive ao ⌘Q | Criar sessão com agente já rodando, abrir sessão limpa em um clique, dividir e fechar panes, fechar o app e reabrir com os agentes vivos | J3 (sem PR e sem hooks), J11, J8 passos de ⌘Q e relançamento, com gravação | AC-000, AC-101 (só CLI detectado e logado), AC-120 (landing), AC-301…316, AC-801…805 e 811, AC-1101…1106 e 1108, AC-T01…T09, T12, T14, T16, T25 (momentos 1 e 2), T26, T27, T28 |
| **2 · Atenção, GitHub** | Saber quem precisa de mim sem olhar cada terminal; PR e checks; importar o Orca | Ver estado real dos agentes (hooks), receber notificação e ir ao agente certo, abrir PR, importar projetos do Orca e usar os dois apps | J1, J2, J5 e J6 completos, com gravação | AC-101…120 (exceto AC-119), AC-201…209, AC-501…506, AC-601…612, AC-806…810, AC-T10, T11, T13, T15, T17, T18, T24 |
| **3 · Computadores, modo leve** | Superar o CLI antigo: o pai pede computador, o filho nativo usa, o dono acompanha e assume | Rodar "spawn 2 subagents" e um lote real de 10+ filhos com computador, ver o viewer, assumir e devolver, coletar resultado com evidência no host | J4 com lote real de pelo menos 10 subagentes (RT.2 item 3) | AC-401…425, AC-428, AC-429, AC-105…107, AC-T19…T23, AC-418, AC-117, AC-118 |
| **4 · Uso, biblioteca mínima e endurecimento** | Fechar a v1: status bar de uso, Library só leitura com ativação por sessão, "Insert Skill or Agent…", observabilidade, benchmarks | Ver uso dos limites do Claude e do Codex, computadores e proxy na status bar; ativar skill numa sessão; inserir skill ou agente no prompt pela palette | RT.2: J2, J3, J4, J6, J8 e J11 num dia real com assinatura estável, usando o Agent Box no lugar do Orca | AC-901…905, AC-1001…1004, AC-T26 de todas as telas, todos os ACs v1 de 05 verdes, release `1.0.0` |
| **v1.1** | Modo isolado e o que 01 §4.2 adia | Rodar CLIs dentro de containers como tabs, handoff, diff, limpeza etc. | Definido na abertura da v1.1 | AC-4xx do modo isolado (AC-451…464) e demais ACs v1.1 de 05 |

---

## 2. Fatia 0 · Fechamento (antes da primeira linha de código)

Responsáveis: agentes executam, o dono decide e aprova onde indicado. Nenhuma tarefa da Fatia 1 começa antes de F0-1 a F0-7 fechados, exceto T1-01 (pode andar com F0-6 e F0-7).

### 2.1 Itens

| # | Item | Dono | Pronto quando |
|---|---|---|---|
| F0-1 | Errata aplicada nos capítulos (nomes canônicos de 08 §0, IDs de motion `M-xxx`, `accessibilityIdentifier` de 02 §17 e 03 §22, atalhos de 03 §21) | Agente redige; dono aprova | `grep` por `M:[A-F][0-9]` retorna 0; nenhum nome de 08 §0 divergente. **Concluído em 2026-10-17 nos capítulos 02, 03, 04, 06, 07:** ver [`errata-check.md`](../../evidence/slice0/errata-check.md) e o relatório [`F0-1-F0-4-report.md`](../../evidence/slice0/F0-1-F0-4-report.md). Restam fora desses capítulos: três nomes a acrescentar em 08 §0 (`AGENTBOX_CAPACITY_ESTIMATES`, `boxes/`, `previous/`) e a política sobre as 7 negações de `scratchpad` |
| F0-2 | Fatia 1 redefinida em 01 §4.1 | — | Feito (P16); só confirmar que 09 §3 e 01 §4.1 batem |
| F0-3 | Pacote de referência visual do Orca 1.4.219 (§2.3) | Agente com Gravação de Tela; dono valida | `manifest.json` cobre todas as superfícies da Fatia 1 nos dois tamanhos; script de extração reproduz os tokens |
| F0-4 | Tabela de ações da Fatia 1 | Agente; dono revisa | 03 §24 já existe; conferir que todo controle visível na Fatia 1 tem linha (ID, rótulo, atalho, efeito, desabilitado com motivo, teste). Controle sem linha sai da UI. **Concluído em 2026-10-17:** 03 §24 agora tem as colunas Atalho e Teste e linhas para o composer inteiro, a linha pendente, `Open Agent Settings`, os diálogos de §16, a busca do terminal, o menu ⋯ dos panes e a palette ([relatório](../../evidence/slice0/F0-1-F0-4-report.md), [`errata-check.md`](../../evidence/slice0/errata-check.md)). Settings segue por regra até T1-26 |
| F0-5 | Spikes S-01…S-08 (§2.2) | Agentes em paralelo | Relatório e evidência em `docs/evidence/spikes/<id>/`; decisão escrita no capítulo dono |
| F0-6 | `design/` antigo para `legacy/design/`; `Package.swift`, `Sources/` e `Tests/` antigos fora do caminho do build (08 AR-202) | Dono aprova o destino; agente move | T1-01 não encontra código antigo no caminho do build |
| F0-7 | Versões fixadas (§2.5) | Agente | `scripts/bootstrap.sh` falha com versão errada |

### 2.2 Spikes (08 §11.1)

Cada spike grava a evidência em `docs/evidence/spikes/<id>/` e escreve o resultado de volta no capítulo dono. Se o critério de saída não fecha, o agente usa o plano B **só se o dono aprovar** quando o plano B for exceção a uma decisão do 00.

| # | Spike | Dono (executa / decide) | Critério de saída | Bloqueia |
|---|---|---|---|---|
| S-01 | `SMAppService.agent` com `Sockets/SecureSocketWithKey`, `launch_activate_socket`, `launchctl getenv`, aprovação de login item, label de teste com `AGENTBOX_HOME` | Agente executa; dono aprova o login item | App assinado registra, o launchd cria o socket, `getenv` devolve o caminho, `nc -U` acorda o daemon; log e `launchctl print` | T1-24 (a Fatia 1 já roda no modo degradado) |
| S-02 | SwiftTerm 1.20.0 × 1.99.0: Metal, `feed` fora do main, `send` de outra thread, busca, OSC 133/7, latência com 4 panes e `yes \| head -c 200M` | Agente; dono ratifica a versão | Medição nos dois; decisão de versão escrita na AR-122 | T1-09 |
| S-03 | Peer auth (`LOCAL_PEERTOKEN` + `SecCodeCheckValidity`) com certificado local, runner do XCUITest e CI | Agente | Peer aceito e recusado; receita de CI com certificado efêmero (08 §8.4) | T1-07 |
| S-04 | Reattach: replay do ring desde o ponto de corte, preâmbulo de modos, redraw `cols-1`, com Claude, Codex e `vim` | Agente | `textSnapshot` antes e depois iguais em 20 repetições; vídeo | T1-06 |
| S-05 | Hooks por lançamento: (a) Claude `--settings` soma com os hooks do Orca; (b) Codex `-c hooks…`: trust exigido? hash estável?; (c) Codex app-server daemon × `--no-daemon` | Agente executa; D-Codex-1 decidida em P18 (opção B) | Payloads gravados como fixtures em `docs/evidence/`; decisão escrita em 06 §3.3.1 e §2.2 | Define o adapter da Fatia 1 (T1-15); bloqueia T2-02/T2-03. **Concluído em 2026-10-17** ([evidência](../../evidence/spikes/S-05/README.md)): (a) confirmado; (b) `untrusted` não executa, hash estável, trust inline por `-c 'hooks.state={…}'`; (c) daemon fora do PTY, `--no-daemon` por padrão. Pendente: payloads Codex de `PreToolUse`/`PostToolUse`/`Stop` (cota até 22/10/2026) |
| S-06 | Captura do env de login (`-l -i -c` com marcador em PTY oculto) com o zsh do dono (sem p10k nem oh-my-zsh, confirmado no S-06) | Agente no Mac do dono | Captura em menos de 1 s, sem lixo; `which claude node gh` resolve | T1-08. **Concluído em 2026-10-17** ([evidência](../../evidence/spikes/S-06/README.md)): 32 ms, sem lixo, env por arquivo, fallback `-l -c` marcado `non-interactive` |
| S-07 | `ctl screenshot` via ScreenCaptureKit da própria janela com camadas Metal, com e sem Gravação de Tela | Agente; dono concede a permissão | PNG fiel do terminal Metal | T1-02 e toda evidência visual |
| S-08 | `mcpServers` inline por subagente e `agent_id` nos hooks (07 S1) na versão do Claude instalada | Agente | Fixture com dois filhos distinguíveis | Modelo de identidade do modo leve (Fatia 3). **Concluído em 2026-10-17** ([evidência](../../evidence/spikes/S-08/README.md)): `mcpServers` como array; `agent_id`/`agent_type`/`mcp_server` nos hooks do filho |

Os demais spikes de 07 (S2, S3, S4, S6, S8, S9) ficam na Fatia 3 (§4.5.3); S5 e S7, na abertura da v1.1.

### 2.3 Pacote de referência visual do Orca 1.4.219

Versionado no repositório em `docs/rebuild/reference/orca-1.4.219/`. **Nunca** depende do scratchpad nem de uma instalação do Orca na máquina de quem está implementando. É a fonte do gate P14 (03 §23, 08 AR-808).

Estrutura:

```
docs/rebuild/reference/orca-1.4.219/
  README.md                  versão, data, SHA-256 do app.asar, fixtures usados, como recapturar
  manifest.json              um registro por PNG (schema abaixo)
  screens/<tela>/<estado>@1440x900.png     PNG @2x, tema escuro
  screens/<tela>/<estado>@760x480.png      PNG @2x, tema escuro
  crops/<componente>/<estado>.png          recortes 1:1 de componentes
  tokens/colors.json  typography.json  spacing.json  radii.json  motion.json   extraídos do renderer
  source/                    trechos do renderer citados por 02 e 04 (se a licença permitir; senão só o índice com hash)
```

`manifest.json`, por PNG: `file`, `screenId` (03 §0), `state`, `size` (`1440x900` ou `760x480`), `a11yId` equivalente no Agent Box (03 §22), `fixture` (05 §0.3), `slice` (1 a 4), `capturedAt`, `notes`.

Superfícies e estados da Fatia 1 (mínimo): janela vazia; sidebar com 3 projetos (card ativo, hover, unread, pendente, vazio, `F-LONG`); seção Sessions; tab row (ativa, hover, overflow, rename); dois panes em split com header; find bar; estados do pane (running, exited, couldn't start); composer (cada variante de "Where", Advanced aberto, erro); Quick Launch; palette; confirmações (fechar terminal, ⌘Q, apagar sessão); toast; menus de contexto; landing; onboarding mínimo; Settings (Agents e launch profiles). Fatias 2 a 4 acrescentam suas telas antes de suas tarefas visuais (Inbox, painel direito, viewer, Computers, Batch, Library, Settings, status bar), sempre nos dois tamanhos.

Extração: `scripts/extract-orca-reference.sh` lê o `app.asar` instalado, grava `source/` e `tokens/` e o hash no README. As capturas são feitas uma vez (agente com Gravação de Tela ou o dono), com os fixtures de 05 §0.3. Se o conjunto passar de ~50 MB, o dono decide entre Git LFS e manter só os PNGs necessários (§7).

### 2.4 Scripts de gate (esqueleto na Fatia 0, conteúdo completo nas tarefas indicadas)

Cada script já nasce com contrato de entrada e saída, código de saída diferente de zero em falha e modo `--help`. Quem completa cada um está na coluna da direita.

| Script | Função | Completa em |
|---|---|---|
| `scripts/bootstrap.sh` | Confere Xcode 26.x e `rg`; baixa e confere XcodeGen 2.46.0 por SHA-256 e as versões de `scripts/tool-versions.txt`; falha com versão errada | F0-7, T1-01 |
| `scripts/extract-orca-reference.sh` | Extrai renderer e tokens do `app.asar` | F0-3 |
| `scripts/compare-ui.sh <tela>` | `ctl screenshot` do Agent Box no mesmo tamanho e fixtures; monta lado a lado e diff de sobreposição (50% e diferença absoluta) em `docs/evidence/ui/<tarefa>/`, nos dois tamanhos | T1-02 (usa o `ctl`); contrato fechado na Fatia 0 |
| `scripts/lint.sh` | Swift 6 sem warnings, proibições de concorrência (`DispatchSemaphore.wait`, `Thread.sleep`, locks em I/O fora de `Platform/`) | T1-01 |
| `scripts/lint-ui.sh` | Proíbe `.sheet(`, `List(`, `Form(`, `Color(hex:` fora de `DS.Color`, literais em `.padding(`/`.frame(` fora de `DS.Space`, `LocalProcessTerminalView`, emojis; exige `Button` via `ActionRegistry`; strings no String Catalog | T1-02 |
| `scripts/gen-tokens.py` | Tokens JSON para `DS.*` e `MotionTokens.generated.swift` + `tokens.js` | T1-03 |
| `scripts/e2e.sh` | Passos de 08 AR-810 com `ctl`, Docker real e CLIs reais (modelo barato, custo ≤ US$ 0,50) | Passos 1–3 e 7 em T1-24; completo na Fatia 3 |
| `scripts/bench.sh` | Orçamentos AR-702/703/706 | T1-09 |
| `scripts/qa-preflight.sh` | Confere Acessibilidade, Gravação de Tela, Docker, CLIs logados (AR-825) | T1-02 |

### 2.5 Bootstrap com versões fixadas

`scripts/tool-versions.txt` é a fonte única. Fixa: Xcode 26.x, XcodeGen 2.46.0 (zip e SHA-256), SwiftTerm (1.20.0 até o S-02 decidir), GRDB 7.x, Geist (versão, SHA e `OFL.txt`), `swift-snapshot-testing`. `Package.resolved` é versionado. `bootstrap.sh` roda no CI e no Mac do dono e falha se qualquer versão divergir.

### 2.6 Checklist de saída da Fatia 0

- [ ] F0-1 a F0-7 fechados e aprovados pelo dono onde marcado.
- [ ] Pacote de referência completo para a Fatia 1 nos dois tamanhos, com `manifest.json` validado por script.
- [ ] Spikes S-01…S-08 com relatório; planos B que exigem exceção ao 00 foram decididos pelo dono.
- [ ] `bootstrap.sh` falha com versão errada (teste negativo gravado).
- [ ] Nenhuma citação a `scratchpad` na spec.

---

## 3. Fatia 1 · Casca, terminais e sessões limpas

Escopo (01 §4.1): janela, sidebar (Projects e Sessions), tab row, splits, overlays, design system, Projeto → Sessão → Tabs → Panes → Terminais, sessões limpas, composer, Quick Launch, perfis de lançamento, daemon como filho do app e depois LaunchAgent, reabertura com "Interrupted" e "Resume", onboarding mínimo, `ctl` mínimo. **Sem hooks**: o card mostra o estado do processo e a atividade do agente é `unknown`. Motion dos momentos 1 e 2 de P8.

Reconciliação com R3 §10: as 25 tarefas de R3 (T-01…T-25) viram **T1-01…T1-25** com a mesma numeração. Duas tarefas novas cobrem itens de 01 §4.1 que R3 deixou sem dono: **T1-26** (onboarding mínimo e Settings mínimo, pois 03 §4.6 manda "Open Agent Settings" nos erros de lançamento) e **T1-27** (arquivar e apagar terminal, sessão e worktree, e "Open in…"). A captura do ID nativo do agente entra em T1-15 e a reabertura em T1-23. `files.copy`, estado por hooks, PR, Conversations e importação do Orca ficam fora.

### 3.1 Regras comuns a todas as tarefas da Fatia 1

- Entrada do agente: IDs de requisito e de AC citados, linha(s) da tabela de ações (03 §24), PNGs de referência do pacote da §2.3 e a errata.
- Saída: DoD completa (§5.2). Nas tarefas visuais: `compare-ui.sh` nos dois tamanhos, `LayoutConformanceTests` das medidas tocadas e **OK explícito do dono (P14)** registrado em `docs/evidence/ui/<tarefa>/`. Nas com motion: gravação (`ctl record`) lado a lado com o protótipo ou a referência.
- Legenda de evidência: **[T]** testes na camada certa; **[SxS]** screenshot lado a lado com o Orca nos dois tamanhos + OK do dono; **[V]** gravação; **[L]** log ou saída de comando.

### 3.2 Tarefas

**T1-01 · Esqueleto e build**
- Escopo: `project.yml` (XcodeGen fixado), `Packages/AgentBoxKit` com os alvos de 08 AR-121 vazios, Swift 6 estrito, `defaultIsolation`, `bootstrap/gen/build/install.sh`, certificado local, `LogFacade`, CI macOS (`macos-15` e o mais novo) com build, lint e testes vazios.
- Arquivos: `project.yml`, `Packages/AgentBoxKit/Package.swift`, `scripts/*.sh`, `scripts/tool-versions.txt`, `.github/workflows/`.
- Depende de: F0-6, F0-7.
- Cobre: T3, T4, AC-T16, AC-T18 (manual).
- Pronto quando: app vazio assinado instala, abre e passa `codesign --verify --strict` com o designated requirement esperado; CI verde. Isenta dos itens 3 a 5 da DoD (AR-820).
- Evidência: [L] `build.sh`, `codesign -dr -`, link do CI.

**T1-02 · Registro de ações, A11yID e `ctl` mínimo**
- Escopo: `ActionRegistry` (ActionID → handler, enabled, motivo), `A11yID` tipado, `app.sock` só com `ctl` e opt-in, `agentbox ctl state | ui tree | ui action | ui wait | screenshot | record`, varredura de IDs, `lint-ui.sh`, `compare-ui.sh`, `qa-preflight.sh`, `KeyBindingRegistry` base e feature flag por fatia.
- Arquivos: `AgentBoxCore/Control/`, `AgentBoxUI/Actions/`, `agentbox/ctl`, `scripts/lint-ui.sh`, `scripts/compare-ui.sh`.
- Depende de: T1-01, S-07.
- Cobre: T13, AC-T01, T02, T03, T28.
- Pronto quando: `ctl ui tree` lista a janela vazia; `ctl screenshot` gera PNG fiel; o lint falha num `Button` solto de teste; `compare-ui.sh` roda numa tela de teste contra um PNG do pacote.
- Evidência: [T] varredura e lint; PNG e JSON da árvore.

**T1-03 · Tokens e fontes**
- Escopo: `design/tokens/*.json` a partir de 02 §2–§8; `gen-tokens.py` gera `DS.Color/Font/Space/Radius` e `MotionTokens.generated.swift` + `tokens.js`; Geist embutida com `OFL.txt`; teste de paridade JS↔Swift (04 MA1); página de amostras.
- Arquivos: `design/tokens/`, `design/motion/tokens.json`, `scripts/gen-tokens.py`, `AgentBoxDesignSystem/Tokens/`.
- Depende de: T1-01. Compara com `tokens/` do pacote da §2.3.
- Cobre: 02 §2–§8, §15, 04 §3, AC-T26 (parcial), AC-T27 (parcial).
- Pronto quando: todo token de 02 existe com o valor certo; `Font.custom("Geist")` resolve; tokens extraídos do Orca e tokens do Agent Box divergem só onde 02 §0 justifica.
- Evidência: [T]; [SxS] página de amostras ao lado das cores e tipos do Orca, com OK do dono.

**T1-04 · Protocolo do daemon**
- Escopo: `AgentBoxProtocol`: framing, DTOs de ops e eventos (schema unificado da errata), códigos de erro, capabilities, handshake N e N-1, fixtures JSON.
- Arquivos: `AgentBoxProtocol/`, `Tests/ProtocolTests/Fixtures/`.
- Depende de: T1-01, F0-1.
- Cobre: T1, 08 §0.3, AR-904 (teste N vs N-1).
- Pronto quando: encode/decode de todas as fixtures; frame > 1 MiB rejeitado; teste N × N-1.
- Evidência: [T].

**T1-05 · Domínio e Store da Fatia 1**
- Escopo: modelos `Project, Worktree, Session, Tab, PaneLayout, Terminal, LaunchProfile, LaunchSpec` (Sendable); GRDB `v1_initial` só com as tabelas da Fatia 1 mais `setting` e `ui_state`; backup pré-migração e diário (últimos 7); corrupção abre com banner (AR-322); `ValueObservation` no MainActor.
- Arquivos: `AgentBoxCore/Domain/`, `AgentBoxStore/`.
- Depende de: T1-01, F0-1.
- Cobre: T2, AC-T13, AC-T14.
- Pronto quando: CRUD, migração de banco vazio, corrupção restaura o backup com o banner de AC-T13.
- Evidência: [T].

**T1-06 · `agentboxd` núcleo (filho do app)**
- Escopo: PTY (forkpty, pgid), ops `create/list/attach/detach/resize/signal/kill/subscribe/textSnapshot/forget/ping`, ring de 4 MiB com ponto de corte e preâmbulo, coalescência, backpressure, emulador headless que nunca responde OSC 52 de leitura, dono das respostas de consulta (AR-105). Socket privado passado pelo app.
- Arquivos: `agentboxd/`, `AgentBoxTerminalCore/`.
- Depende de: T1-04, S-04.
- Cobre: T1, T6, AC-T05, AC-801 (base).
- Pronto quando: `DaemonTests`: matar o cliente e reanexar devolve a mesma tela com `vim` e um TUI de teste; ninguém responde a `OSC 52;c;?`.
- Evidência: [T]; `textSnapshot` antes e depois [L].

**T1-07 · Peer auth**
- Escopo: `LOCAL_PEERTOKEN` + requisito de código; caminho de CI do S-03.
- Arquivos: `AgentBoxPlatform/PeerAuth/`.
- Depende de: T1-06, S-03.
- Cobre: 08 §5, AC-T19 (parte).
- Pronto quando: peer assinado aceito e não assinado recusado, no Mac e no CI.
- Evidência: [T], [L] `daemon.auth`.

**T1-08 · Env de login**
- Escopo: captura com marcador, fallback `-l -c` com timeout, denylist (inclui `ORCA_*`), cache e invalidação.
- Arquivos: `AgentBoxPlatform/LoginShellEnv/`.
- Depende de: T1-01, S-06.
- Cobre: TA-110, AC-312.
- Pronto quando: unidade + AC-312 no shell do dono; env do agente sem `ORCA_*`.
- Evidência: [T]; [L] `which claude codex gh` dentro de um pane.

**T1-09 · `TerminalSurface`**
- Escopo: `TerminalHostView` com `TerminalView` (nunca `LocalProcessTerminalView`), Metal, delegate próprio (`clipboardRead → nil`, OSC 52 de escrita conforme o setting), tema de 02 §3, `PTYClient` actor com alimentação por orçamento (AR-406), política de paste e links, find bar com a busca pública do SwiftTerm, zoom ⌘= ⌘- ⌘0, tabela tecla→bytes.
- Arquivos: `AgentBoxUI/Terminal/`, `AgentBoxCore/PTYClient/`.
- Depende de: T1-03, T1-06, S-02.
- Cobre: T6, AC-T05, AC-T07, AC-T08, 03 §4.1 e §4.4.
- Pronto quando: AC-T05, AC-T07 (p95 ≤ 33 ms conforme AR-702), testes tecla→bytes, `bench.sh` verde.
- Evidência: [T]; `bench.sh` [L]; [SxS] terminal (fonte, cor, inset 4) com OK do dono.
- Obs.: pode dividir em "núcleo" e "endurecimento" se o spike S-02 mostrar complexidade.

**T1-10 · Janela e chrome**
- Escopo: `MainWindowController` (`fullSizeContentView`, sem `NSToolbar`), semáforos em x 16/36/56 e y 18 reaplicados em resize e tela cheia, faixa de titlebar 36, `MainSplitViewController` com sidebar 280 (220–500, ⌘B), painel direito **oculto**, janela mínima 760×480 e inicial 1440×900, regiões de erro (03 §1.4).
- Arquivos: `AgentBoxUI/Window/`.
- Depende de: T1-02, T1-03.
- Cobre: T5, 03 §1, AC-T27 (parcial), AC-T26.
- Pronto quando: `LayoutConformanceTests` (semáforos, faixas, larguras); XCUI de ⌘B, resize e tela cheia.
- Evidência: [T]; [SxS] com `main-empty` do Orca nos dois tamanhos.

**T1-11 · Overlay host e componentes base**
- Escopo: `OverlayPanelHost/OverlayRouter` com o contrato de foco (nenhuma tecla vai ao PTY), `DSButton`, `DSIconButton`, `DSTextField`, `Keycap`, `DSSegmented`, `DSSwitch`, `ConfirmationOverlay`, `ToastCenter`; motion M-101/102/103/110 com Reduce Motion primeiro.
- Arquivos: `AgentBoxDesignSystem/Components/`, `AgentBoxUI/Overlay/`.
- Depende de: T1-03, T1-10.
- Cobre: T5, AC-T06, AC-T25 (parcial), 02 §12.
- Pronto quando: AC-T06; snapshot de cada componente aprovado.
- Evidência: [T]; [SxS] por componente; [V] overlay abrindo e fechando (com Reduce Motion).

**T1-12 · `DSCombobox`, `DSMenuPanel`, `TooltipController`, `PromptEditor`**
- Escopo: componentes AppKit com type-ahead, delays de tooltip (400/500/1000/200 ms), IME, ⌘↵.
- Arquivos: `AgentBoxDesignSystem/Components/`.
- Depende de: T1-11.
- Cobre: 02 §12, AC-T02 (tooltip do desabilitado).
- Pronto quando: testes de teclado; snapshots aprovados.
- Evidência: [T]; [SxS]; [V].

**T1-13 · Sidebar: estrutura**
- Escopo: `ScrollView` + `LazyVStack` (sem `List`), seções Projects e Sessions, linha de projeto, card de sessão na versão da Fatia 1 (título, pasta ou branch, linhas de agente com estado do processo e `unknown`), linha pendente com fases (M-204), rename inline, estados vazios, teclado, menus de contexto só com as ações da tabela da Fatia 1.
- Arquivos: `AgentBoxUI/Sidebar/`.
- Depende de: T1-05, T1-11, F0-4.
- Cobre: 03 §2, AC-305, AC-T27, AC-1105 (parte).
- Pronto quando: `LayoutConformanceTests` (alturas 32/28/24, raio do card 10, padding 6); XCUI com clique real de cada ação do menu.
- Evidência: [T]; [SxS] (ativo, hover, pendente, vazio, `F-LONG`).

**T1-14 · Tabs e panes**
- Escopo: tab row 32 + 4, tab 180/220 (mín. 72), overflow, rename, reordenar, fechar com confirmação (`kill graceful`, "Force Quit" após 5 s), ⇧⌘T; árvore de splits ⌘D/⇧⌘D, divisor 3 pt (hit 9), tamanho mínimo, header do pane com 2+ panes, foco ⌘]/⌘[, opacidade 0,8 inativo, persistência do layout; M-301/302/304/306/307 com um resize por transição.
- Arquivos: `AgentBoxUI/Tabs/`, `AgentBoxUI/Panes/`.
- Depende de: T1-09, T1-11, T1-05.
- Cobre: 03 §3–§4, AC-T09, AC-T25 (parcial), AC-314.
- Pronto quando: contador de resize do PTY = 1 por gesto (04 MA6); resize, colapso ou troca de tab nunca recriam o PTY; XCUI de cada ação.
- Evidência: [T]; [V] split e fechar; [SxS].

**T1-15 · Adapters de lançamento e captura do ID nativo**
- Escopo: `LaunchPlanner` com perfis (Claude, Codex, OpenCode, shell, Custom Command), resolução terminal → projeto → global, probe de CLI (instalado, logado), argv dourado por adapter e perfil, `--session-id` no Claude, prompt como argumento com o limiar da errata, **sem injeções** (sem hooks) na Fatia 1, captura do ID nativo, env da execução.
- Arquivos: `AgentBoxCore/Launch/`.
- Depende de: T1-05, T1-08, F0-1, S-05 (define o adapter).
- Cobre: R3.1, R3.3, T11, AC-307, AC-308, AC-309, AC-104 (parte).
- Pronto quando: golden files para cada combinação; zero bytes escritos no PTY pelo app (teste com o daemon).
- Evidência: [T] golden files.

**T1-16 · Fluxo de lançamento e estados do pane**
- Escopo: criar terminal → `create` no daemon → ignição se o primeiro byte demorar > 300 ms (M-503/504/506) → Running / Exited / Couldn't start (Try Again, Open Agent Settings, Copy Details) / daemon indisponível; `LaunchProgress`.
- Arquivos: `AgentBoxCore/Launch/`, `AgentBoxUI/Panes/States/`.
- Depende de: T1-14, T1-15.
- Cobre: P8 momento 2, AC-310, AC-T12, 03 §4.6.
- Pronto quando: XCUI de cada estado com CLI falso (sucesso, demora, falha no spawn, saída precoce).
- Evidência: [T]; [V] dos quatro casos; [SxS].

**T1-17 · Sessões limpas**
- Escopo: gerador de nome `quiet-harbor` (nunca reaproveita pasta), criação em `~/AgentBox/sessions/`, um clique no "+" da seção Sessions ou ⇧⌘N → tab com o agente padrão e foco no terminal em menos de 1 s, "New Clean Session in Folder…" (⌥⇧⌘N), rename sem mexer na pasta, apagar com "Move folder to Trash" só se gerenciada, promoção "Move to Project…".
- Arquivos: `AgentBoxCore/Sessions/`, `AgentBoxUI/Sidebar/`.
- Depende de: T1-13, T1-16.
- Cobre: P10, P11, P15, AC-1101…1106, AC-1108.
- Pronto quando: AC-1101…1106 e 1108 em XCUI e E2E.
- Evidência: [T]; [V] do clique ao agente rodando.

**T1-18 · Git mínimo**
- Escopo: `GitService` async: detectar repo, listar worktrees, `worktree add` com branch e prefixo, base `origin/main`, fetch com timeout, erros mapeados para "Use Existing Branch" e "Create Without Fetching"; raiz de worktrees `~/orca/workspaces/<repo>/` (P15).
- Arquivos: `AgentBoxCore/Git/`.
- Depende de: T1-05.
- Cobre: R3.2, AC-303, AC-304.
- Pronto quando: testes com repositório temporário (branch existente, fetch falho, pasta ocupada).
- Evidência: [T].

**T1-19 · Projetos**
- Escopo: "Add Project…" (pasta, bookmark), linha de projeto, remover projeto sem apagar arquivos, landing (03 §19).
- Arquivos: `AgentBoxCore/Projects/`, `AgentBoxUI/Sidebar/`.
- Depende de: T1-13, T1-18.
- Cobre: AC-120 (landing), 03 §16.6 e §16.9.
- Pronto quando: XCUI.
- Evidência: [T]; [SxS].

**T1-20 · Composer ⌘N**
- Escopo: overlay (largura da errata), campos de 03 §6.1 (Project, Where por contexto, Create from só com nome de branch na Fatia 1, Agent, Profile, Prompt), Advanced (Session name, Branch, Worktree location; **sem** "Subagent computers" nem "Watch Claude subagents"), linha de resumo do comando, validação, Create More, Esc com descarte; ao criar: fecha na hora, linha pendente, tab rodando (P9).
- Arquivos: `AgentBoxUI/Composer/`.
- Depende de: T1-12, T1-15, T1-16, T1-18, T1-19.
- Cobre: AC-301, 302, 305, 306, 307…309, 313, 314, 316.
- Pronto quando: XCUI com clique real em todo campo; tempo do submit até o pane com output medido.
- Evidência: [T]; [V]; [SxS] de cada variante de "Where".

**T1-21 · Quick Launch e ⌘T**
- Escopo: popover `DSMenuPanel` (⌥⌘N e "+"), "Start <agente> with …", ⇧↵ em split; ⌘T shell; ⌥⌘T agente padrão.
- Arquivos: `AgentBoxUI/QuickLaunch/`.
- Depende de: T1-12, T1-16.
- Cobre: AC-313, 03 §7.
- Pronto quando: XCUI de cada item.
- Evidência: [T]; [SxS].

**T1-22 · Menus do app e atalhos**
- Escopo: `KeyBindingRegistry` com escopo, menus `File/Edit/View/Window/Help` só com ações da Fatia 1, teste anti-conflito, teclas reservadas ao terminal.
- Arquivos: `AgentBoxUI/Commands/`.
- Depende de: T1-02, T1-14, T1-20.
- Cobre: 03 §18 e §21, AC-T02, AC-T08.
- Pronto quando: teste de conflito; XCUI disparando cada atalho.
- Evidência: [T]; tabela gerada dos atalhos.

**T1-23 · Persistência e reabertura (sem LaunchAgent)**
- Escopo: ao reabrir o app, sessões, tabs e layout voltam; terminais mortos aparecem como "Interrupted" com Resume (`claude --resume <id>` com flags regeneradas) e Start Fresh.
- Arquivos: `AgentBoxCore/Sessions/Restore`.
- Depende de: T1-14, T1-15.
- Cobre: R8.1, R2.2 (parte), AC-806, AC-802 (parte).
- Pronto quando: XCUI: fecha, abre e confere a mesma árvore; Resume executa o argv correto.
- Evidência: [T]; [V].

**T1-24 · Daemon como LaunchAgent e ⌘Q mantém agentes**
- Escopo: `SMAppService` com o socket do S-01, ⌘Q com overlay "Keep Running" (§16.10 de 03, nunca `NSAlert`), ícone na barra de menus, `Quit Agent Box Completely`, reattach com scrollback, cold restore depois de `kill -9`. Se o S-01 falhar, aplica o plano B aprovado pelo dono.
- Arquivos: `agentboxd/Launchd`, `AgentBoxUI/MenuBar/`, `AgentBoxCore/AppLifecycle/`.
- Depende de: T1-06, T1-07, T1-23, S-01.
- Cobre: P4, T1, AC-801…805, AC-811.
- Pronto quando: `e2e.sh` passos 1–3 e 7 passam: mesmo PID depois de quit e launch; cold restore.
- Evidência: [L] e2e; [V]; [SxS] do overlay de ⌘Q.

**T1-25 · Fechamento da fatia**
- Escopo: varredura AC-T01/T02 com clique real, `compare-ui.sh` de todas as telas da fatia nos dois tamanhos, Reduce Motion, janela mínima, `F-LONG`, relatório da fatia (o que diverge do Orca e por quê), um dia de uso real do dono.
- Depende de: todas.
- Cobre: critério de saída da fatia (§1), AC-T25 (momentos 1 e 2), AC-T26, AC-T27, AC-T28.
- Pronto quando: todos os ACs de saída verdes; OK do dono em cada tela; dia real feito.
- Evidência: `docs/evidence/slice1/` com relatório, gravação do dia e tabela de divergências.

**T1-26 · Onboarding mínimo e Settings mínimo** (adicionada na reconciliação)
- Escopo: onboarding com CLI detectado, logado ou não (03 §15, só o que a Fatia 1 mostra); Settings com Agents e launch profiles (a tela alvo de "Open Agent Settings"), regra de salvamento de 03 §14.1.
- Arquivos: `AgentBoxUI/Onboarding/`, `AgentBoxUI/Settings/`.
- Depende de: T1-12, T1-15.
- Cobre: AC-101 (parte), AC-104, AC-T04, AC-T27.
- Pronto quando: XCUI com stubs de CLI (instalado, deslogado, ausente); nenhuma seção de fatia futura renderizada.
- Evidência: [T]; [SxS].

**T1-27 · Arquivar, apagar e "Open in…"** (adicionada na reconciliação)
- Escopo: arquivar e apagar terminal, sessão e worktree com os diálogos de 03 §16.1, §16.2, §16.5; "Open in…" (R5.2) com os editores e terminais configurados em Settings.
- Arquivos: `AgentBoxCore/Sessions/`, `AgentBoxUI/Dialogs/`.
- Depende de: T1-17, T1-18, T1-26.
- Cobre: AC-T09, AC-1105, AC-502, AC-306.
- Pronto quando: XCUI de cada diálogo, incluindo "Keep the branch".
- Evidência: [T]; [SxS] de cada diálogo.

### 3.3 Grafo de dependências

T1-01 → {T1-02, T1-03, T1-04, T1-05, T1-08} → {T1-06 → T1-07, T1-09, T1-10 → T1-11 → T1-12, T1-18} → {T1-13, T1-14, T1-15} → {T1-16, T1-19, T1-26} → {T1-17, T1-20, T1-21, T1-22, T1-27} → T1-23 → T1-24 → T1-25. Sem ciclos depois que o `ctl` (T1-02) sobe. Cada tarefa cabe em uma sessão de agente de um a dois dias.

---

## 4. Fatias 2 a 4 e v1.1 (nível de épico)

Antes de começar cada fatia, o mesmo ritual da Fatia 0 em miniatura: acrescentar ao pacote de referência as telas da fatia (nos dois tamanhos), fechar a tabela de ações da fatia (03 §24) e rodar os spikes e verificações da fatia. Cada épico vira tarefas `T<fatia>-nn` na mesma forma da §3 (escopo, arquivos, dependências, ACs, pronto, evidência) quando a fatia anterior fechar. A fatia 2 e a 3 podem andar em paralelo depois da Fatia 1, desde que o `app.sock` esteja estável (08 §10).

### 4.1 Fatia 2 · Atenção, GitHub e convivência com o Orca

Pré-requisitos de verificação: S-05 (concluído) e V1…V13 (08 §11.2); D-Codex-1 decidido em P18 (opção B).

| Tarefa principal | Resumo | Depende de | ACs |
|---|---|---|---|
| T2-01 Atividade e spool | `v2_activity`, `agentbox hook` (sem python3) + spool, máquina de estados de 01 §6, última mensagem por terminal | Fatia 1 | AC-201, 202, AC-T24 |
| T2-02 Injeções Claude por lançamento | `--settings`, `--mcp-config`, `--plugin-dir`; nada escrito em `~/.claude` | T2-01, S-05 | AC-112, 401 (parte) |
| T2-03 Estratégia Codex | Hooks por `-c` com trust inline (P18) e `--no-daemon`, ou rollout `estimated` como fallback | T2-01, S-05, D-Codex-1 | AC-202, 601, 607 |
| T2-04 Atenção e notificações | Notificações do sistema, Inbox (⇧⌘I), badge no Dock, "Next Needing Attention" (⇧⌘A), ⌘J, ⌘1…9, estado do pai considera os filhos | T2-01 | AC-204, 601…607, 611, 612 |
| T2-05 GitHub | `gh`: chip de PR, checks, "Create PR", nota de status da sessão; painel direito (activity bar, Source Control só lista, Checks) | T2-01, Fatia 1 | AC-501, 503, 504, 208 |
| T2-06 Colar no prompt por clique | "Paste into <Agent>" com bracketed paste sem Enter, origem `0x02` (T11) | T2-04 | AC-505, 506 |
| T2-07 Retomada e Conversations | "Resume Agents…" em lote com custo à vista, aba Conversations (⇧⌘H) | T2-01 | AC-203, 205, 206, 207, 806…810 |
| T2-08 Importação do Orca e convivência | Removida por P21 (nenhuma dependência do Orca no produto) | - | - |
| T2-09 Onboarding completo | Checklist de diagnóstico: CLIs, `gh`, Docker, conflitos de config global (R1.1, R1.5…R1.8) | T2-08 | AC-101…104, 112…117 |
| T2-10 Vault, catálogo e importador do JSON atual | Segredos no Keychain/Vault, catálogo de agentes, importador dos JSONs antigos com dry-run | Fatia 1 | AC-118 (parte), AC-T15 |
| T2-11 Desempenho e fechamento | 10 sessões em paralelo medidas (AR-702/703), relatório da fatia | todas | AC-608, 609 |

Saída: J1, J2, J5, J6 num dia real; hooks chegam com o app fechado; nenhuma escrita em `~/.claude` nem `~/.codex` (verificada por teste).

### 4.2 Fatia 3 · Computadores, modo leve

Spikes na primeira semana: S2 (porta e DNS em rede `internal` no Docker Desktop, OrbStack e Colima), S8 (bind de arquivo 0400 por uid), S9 (exec com stdin pela Engine API), depois S3 (noVNC ≥ 20 fps), S4 (`deny` de `Skill(agentbox)`), S6 (uso informado pelo provedor do proxy). S-08 já veio da Fatia 0.

| Tarefa principal | Resumo | Depende de | ACs |
|---|---|---|---|
| T3-01 Docker e imagens | `AgentBoxDocker` (Engine API, eventos, exec hijacked), imagens por digest (GHCR ou build local), contexto ativo, `v3_computers` | Fatia 1, S2, S9 | AC-105…107, AC-T20…T22 |
| T3-02 Egress sidecar e proxy genérico | Proxy escolhido por computador, reqlog com corpos, uso do proxy, bloqueio de SSRF, token por arquivo; Settings › Computers › Proxies (P13), `Import from agentbox CLI…` | T3-01 | AC-117, 118, 417, 418, 419, 424 |
| T3-03 Runtime e ferramentas MCP | `exec`, `curl_cffi`, `http_request`, navegador por seletor (Xvfb headed), diário, render quando o proxy suporta (T12); `agentbox mcp` | T3-01, T3-02, S-08 | AC-411, 412, 415, 416, 428 |
| T3-04 Orquestração | Skill de orquestração por lançamento, conflito com a skill global `agentbox` (S4), `boxes_reserve`, `box_claim`, `ComputerScheduler` com capacidade e fila | T3-03, T2-02 | AC-401…406 |
| T3-05 Viewer e controle humano | noVNC em WKWebView ≥ 20 fps, Take Over e Hand Back com nota, aba Computers (⇧⌘C), página Computers, `help_request` e `help_wait` | T3-03, S3 | AC-407…410, 413, 414, AC-T23 |
| T3-06 Resultado e evidência | `box_collect`, validação de afirmações com request citado, run folder no host, parada e arquivamento | T3-03 | AC-420…423, 425 |
| T3-07 Lote | `Batch`, painel, `New Batch…`, consolidado, notificação "lote concluído" | T3-04, T3-06 | AC-429 |
| T3-08 Motion do momento 3 | M-601…M-613, bloco C de 04 §7.2.2, dados reais | T3-05 | AC-T25 |
| T3-09 Fechamento | `e2e.sh` completo, AR-706 medido, lote real de 10+ filhos | todas | RT.2 item 3 |

Saída: J4 com lote real de pelo menos 10 subagentes terminando com resultado e evidência no host, sem intervenção fora do app; nenhum token em `docker inspect`.

### 4.3 Fatia 4 · Uso, biblioteca mínima e endurecimento

| Tarefa principal | Resumo | Depende de | ACs |
|---|---|---|---|
| T4-01 Status bar | Janelas de uso do Claude e do Codex (`rate_limits`), computadores, RAM, segmento `Proxy usage` e popover (03 §5) | Fatias 2 e 3 | AC-1001…1004 |
| T4-02 Library só leitura | Agents, Skills, Profiles das fontes nativas, ativação aditiva por sessão via plugin gerado, "Open in Editor" | Fatia 2 | AC-901…905 |
| T4-03 Insert Skill or Agent | Comando `Insert Skill or Agent…` na palette (03 §8), `[Insert in Prompt]` na Library, ação na aba Context; colagem por clique sem Enter (TA-411, v1, Fatia 4) | T4-02, T2-06 | AC-909 |
| T4-04 Observabilidade | Signposts, `metric`, Diagnostics, pacote exportável, crash | Fatia 3 | AC-T17 |
| T4-05 Endurecimento | Benchmarks completos, snapshots aprovados, modelo de ameaça revisado (AC-T19), TCC e Keychain estáveis (AC-T18), M-109 da Library | todas | AC-T18, T19, T23 |
| T4-06 Fechamento da v1 | Todos os ACs v1 de 05 verdes; AC-T26 com OK do dono em **toda** tela; dia real J2, J3, J4, J6, J8, J11; release `1.0.0` | todas | RT.2 itens 1 a 4 |

### 4.4 v1.1 (abertura com decisões do dono, §7)

| Épico | Conteúdo | Depende de |
|---|---|---|
| V11-A Modo isolado | Imagem `agentbox-agent`, container com `dtach`, sessões `docker exec` no daemon, hooks HTTP e MCP via egress, credenciais (P7), worktree por filho, broker de git, kit de skills somente leitura, `v4_batches` e `v5_legacy_runs` | Fatia 3, Q1, Q3, Q4, S5, S7 |
| V11-B Mensagens e workers | `agent_message` com Enter (P12), worker leve, `agent_stop`, `ask_parent`, detector de filho parado | V11-A |
| V11-C Handoff e Codex pleno | "Continue in…", detecção de limite, transferência de computador, paridade do Codex | Fatia 2 |
| V11-D GitHub e diff | Diff só leitura, "Send failures to agent", eventos de PR e checks | Fatia 2 |
| V11-E Biblioteca editável | Criar e editar com backup e histórico, quando a mudança vale (R9.2…R9.4) | Fatia 4 |
| V11-F Uso e limpeza | Custo e tokens por terminal, assistente de limpeza, runs do CLI antigo como histórico | Fatia 3 |
| V11-G Sessão e menu | Dormir e fixar sessão, prioridade por tipo, inbox "Since you were away", `.worktreeinclude`, manter o Mac acordado | Fatia 2 |

"Later" (01 §4.3) e "Fora" (01 §4.4) não entram em nenhuma fatia sem decisão do dono.

### 4.4b Backlog do dono (2026-10-19) · anotado, NÃO começar sem o dono

Pedidos do dono depois do primeiro uso real. Só tarefas anotadas; a ordem e o início são decisão dele.

**Computador mais capaz para o agente (dentro do container)**

| Épico | Conteúdo | Depende de |
|---|---|---|
| BK-1 Página como texto estruturado | Snapshot da árvore de acessibilidade com refs estáveis por elemento (como o Playwright MCP); ferramentas clicam/preenchem por ref; menos tokens que screenshot, menos clique errado | T3-03 |
| BK-2 Descoberta automática da API | Do reqlog: XHR/fetch candidato → chamada `http_request` pronta para repetir, com paginação detectada (página, offset, cursor) e esquema da resposta; o agente sai do navegador para HTTP direto | T3-02, T3-03 |
| BK-3 Aprender uma vez, rodar muitas | O caminho que funcionou vira script determinístico (requisições, seletores, paginação) gravado na Library; o lote seguinte roda sem modelo e chama o agente só quando quebra (com o diff do que mudou) | BK-1, BK-2, T3-07 |
| BK-4 Navegador mais humano | Chrome real em vez de Chromium; fuso, idioma, geolocalização e fingerprint coerentes com o país do proxy; perfil persistente; meta: passar Cloudflare/anti-bot sem humano na maioria dos casos | T3-02 |
| BK-5 Logins que persistem | Perfil de navegador por site no Vault: o humano faz login/MFA uma vez pelo viewer e os próximos computadores já entram logados; expiração e "Log in again" | T3-05, T2-10 |
| BK-6 Documentos | PDF para texto, OCR (tesseract) e extração de tabelas no container | T3-03 |
| BK-7 Espaço de dados | DuckDB e pandas no `/work` para deduplicar, validar e exportar CSV/Parquet antes do `result_submit` | T3-06 |

**Agentes e skills**

| Épico | Conteúdo | Depende de |
|---|---|---|
| BK-8 Biblioteca amigável | Library de agentes e skills dentro do app, bonita e navegável (busca, categorias, prévia, de onde vem cada item), além da Library só leitura da T4-02 | T4-02 |
| BK-9 Arrastar e usar | Arrastar um agente ou uma skill da Library para uma sessão, um pane ou o composer e usar na hora (ativa por sessão ou insere no prompt) | BK-8, T4-03 |
| BK-10 Gestão interativa | Criar, editar, ativar e desativar agentes e skills pela UI, com backup e histórico (junta com V11-E) | BK-8 |

**Modelos e onde roda**

| Épico | Conteúdo | Depende de |
|---|---|---|
| BK-11 Outro modelo para o subagente | Escolher o modelo/CLI de cada subagente: por exemplo um subagente no Codex, ou com uma API de terceiros (DeepSeek e afins via endpoint compatível). Precisa de desenho: como o pai Claude delega para um worker que não é Claude (worker leve da V11-B? CLI diferente por slot?), credenciais no Vault, custo por modelo | V11-B, V11-C |
| BK-12 Computadores na nuvem | Rodar os computadores fora do Mac: conta AWS, Cloudflare e outros provedores ligados por uma UI simples (login, região, limite como "no máximo 5 na AWS"); o mesmo container/compose sobe lá em vez do Docker local; viewer, egress e ferramentas iguais; custo visível | T3-01, T3-09 |


#### 4.4c Plano de fases do BK-12 (P27; estudo em `study/cloud-computers.md` §9.3)

**Fase 0 · Spike (3 dias): aguardando OK do dono.** Nada é criado na nuvem antes dele (custa dinheiro e usa a conta do dono). Critério: exec sequestrado e iptables por uid passam numa VM real; só então a Fase 1.

| Item | Escopo | Estado |
|---|---|---|
| BK12-S0 | Spike AWS (`c7g.large`): imagem real, `firewall.py` fail-closed, VNC e exec pelo túnel, latência sa-east-1 vs us-east-1, cota | Aguarda OK do dono |

**Fase 1 · MVP AWS (~30 dias).** Fundação local (sem nuvem) já feita na branch `cloud-foundation`: T-01 a T-07.

| Tarefa | Escopo | Estado |
|---|---|---|
| BK12-T01 | `ComputerHost` (`.local`/`.remote`) atrás do provisionador, sem mudar o caminho local | Feito |
| BK12-T02 | `CloudProvider` + provedor falso + tipos de região, cota, estimativa e AUP; `AWSProvider` só com stub e lista de chamadas | Feito |
| BK12-T03 | Transporte Docker por túnel SSH (socket encaminhado, reconexão, forwards por computador, known_hosts/chave) | Feito |
| BK12-T04 | Chave morta na VM (cloud-init), vida máxima, tags, reaper por tag | Feito |
| BK12-T05 | Teto de gasto diário/mensal aplicado antes de criar e durante | Feito |
| BK12-T06 | Volta de `/work` e logs ao Mac pela API de arquivo antes de apagar a VM | Feito |
| BK12-T07 | Segredos e volumes no host remoto (volumes nomeados, sementeira por archive) | Feito |
| BK12-T08 | `AWSProvider` real: cliente EC2 (SigV4 ou SDK), AMI por região (SSM), security group, `RunInstances` com tags e `InstanceInitiatedShutdownBehavior=terminate` | Pendente (depende da Fase 0) |
| BK12-T09 | Conectar a conta: `aws login`/SSO e CloudFormation quick-create (papel mínimo por tag + alarme de orçamento) | Pendente |
| BK12-T10 | Ligar `ComputerScheduler` ao host remoto: aquisição de host, admissão por capacidade do host, desligar host vazio | Feito (provedor falso): `ComputerHostPool` (reuso, capacidade = min(vCPU/2, GiB/4), teto `maxComputers`, host vazio encerra após 15 min) atrás de `CloudComputerProvisioning`; `runOn == .cloud` sem provedor implementado falha com mensagem, nunca vai ao Mac. Falta o conector SSH real (depende de T08/T09) |
| BK12-T11 | Heartbeat em execução (timer no app, parada no quit, retomada ao reabrir) e reaper ao abrir e a cada N minutos | Feito (provedor falso): `CloudHostSupervisor` (heartbeat por `SSHTunnel.runRemote`, reaper ao abrir e a cada 10 min, readoção por tag) e livro-caixa de gasto em JSON (`FileSpendLedgerStore`). Falta ligar ao app quando houver provedor real |
| BK12-T12 | Reqlog e diário lidos do host remoto durante o run (hoje só voltam ao release) | Pendente |
| BK12-T13 | UI Settings › Computers › Cloud: conta, região com latência e preço, tetos, proxy, custo do dia, órfãos | Parcial: página Computers com escolha local/nuvem, provedor, região, tetos e máximo (F40); faltam conta, latência, proxy, custo do dia e órfãos |
| BK12-T14 | Aviso de uso aceitável: confirmação inicial por conta/provedor, linha curta no card de aprovação e no viewer, reconfirmar em mudança de AUP | Pendente |
| BK12-T15 | Testes de caos (matar o app, derrubar a rede), varredura de portas e evidências | Pendente |

**Fase 2 (~12 dias):** SSM/Instance Connect sem porta de entrada, Budgets com ação, Spot, AMI por região, custo real por Cost Explorer. **Fase 3:** um adaptador por provedor (Hetzner, Fly.io...), cada um após o próprio spike. **Fase 4:** modo isolado na nuvem em dois passos (P27.9).

### 4.5 Verificações, evidências e spikes de 07

#### 4.5.1 Verificações de contrato dos CLIs

Rodam com `AGENTBOX_REAL_CLI=1`, modelo barato, no Mac do dono, antes das tarefas que dependem delas (V1…V13, 08 §11.2). Resultado vira fixture em `docs/evidence/` e é escrito no capítulo dono (06).

#### 4.5.2 Evidências e onde moram

| Tipo | Local |
|---|---|
| Spikes | `docs/evidence/spikes/<id>/` |
| Visual por tarefa | `docs/evidence/ui/<tarefa>/` (lado a lado, diff, gravação, OK do dono) |
| E2E | `docs/evidence/e2e/<data>-<sha>/` |
| Relatório de fatia | `docs/evidence/slice<N>/` |

#### 4.5.3 Spikes de 07 na Fatia 3

S2, S3, S4, S6, S8 e S9 têm dono e critério em 07 §9. S5 e S7 abrem a v1.1.

---

## 5. Regras de execução para os agentes

### 5.1 Fluxo

1. **Uma tarefa por branch e por PR.** Branch `slice<N>/<id>-<slug>` (por exemplo `slice1/t1-09-terminal-surface`). PR pequena, que cabe numa sessão. Não misture tarefas.
2. Antes de codar: leia a tarefa, os IDs de requisito e AC, a linha da tabela de ações (03 §24), os PNGs de referência e os capítulos citados. Se algo estiver ambíguo ou em conflito, aplique a precedência (00 sobre os capítulos) e, se continuar, **pare e pergunte** (§5.4).
3. Escreva o teste antes ou junto do código; toda ação nova entra no `ActionRegistry` com `accessibilityIdentifier`.
4. Rode `scripts/lint.sh`, `scripts/lint-ui.sh` e os testes. Em tarefa visual, rode `compare-ui.sh` nos dois tamanhos e anexe o resultado.
5. Abra a PR com o relatório da §5.3. O dono aprova a evidência visual antes do merge.
6. Atualize o capítulo da spec se o comportamento mudou; não deixe a spec e o código divergirem.

### 5.2 Definition of Done (08 AR-820)

Uma tarefa só fecha quando:
1. Compila em Swift 6 estrito sem warnings; `lint.sh` e `lint-ui.sh` passam.
2. Tem testes na camada certa (lógica nova sem teste de unidade não entra; mudança de schema vem com teste de migração).
3. Todo controle novo tem `accessibilityIdentifier`, `ActionID` e **um XCUITest com clique ou atalho real** com efeito declarado; a varredura passa.
4. Evidência visual comparada com o Orca (P14): `compare-ui.sh`, `LayoutConformanceTests` e, para motion, gravação lado a lado; anexada na PR e em `docs/evidence/ui/<tarefa>/`. **Só fecha com OK explícito do dono.**
5. Snapshot de componente novo aprovado; Reduce Motion e janela mínima conferidos.
6. Logs nas categorias certas, sem segredo (teste de redação).
7. Sem regressão de orçamento de desempenho (AR-720) quando toca terminal, daemon, sidebar ou motion.
8. Fluxos P0 afetados passam no XCUITest; `e2e.sh` passa no Mac do dono quando toca daemon, launch ou computadores.
9. Lista do que a tarefa **não** fez.

### 5.3 Como reportar

Cada PR traz, no corpo: tarefa (ID), requisitos e ACs cobertos com o resultado de cada um, comandos rodados e saída resumida, links para `docs/evidence/...`, divergências intencionais do Orca com o motivo, **lista do que não foi feito**, riscos e decisões tomadas. Nunca escreva "feito" sem a evidência anexada. Se algo falhou, diga qual teste e por quê.

### 5.4 Proibições e quando parar

- **Proibido avançar com AC vermelho.** Se um AC da tarefa ou de uma tarefa anterior falha, a tarefa seguinte não começa. Não marque `skip`, não afrouxe o teste, não reescreva o AC para passar. Se o AC está errado, a correção é feita na spec, com aprovação do dono, antes do código.
- Proibido renderizar controle de fatia futura, mesmo desabilitado (AC-T28).
- Proibido escrever em `~/.claude`, `~/.codex` ou na configuração do Orca (PP-6, P3). Proibido o app escrever no PTY sem clique explícito do usuário (T11; exceção P12 só para filhos que o pai criou, v1.1).
- Proibido pôr valores de estilo fora dos tokens (`DS.*`), usar `.sheet`, `List`, `NSAlert` em fluxo normal ou texto de UI fora do String Catalog.
- Proibido depender do scratchpad, de caminho absoluto da máquina ou de instalação do Orca para gerar evidência; use o pacote de referência.
- Proibido commit de segredo, credencial ou token em fixture, log ou evidência.
- **Pare e pergunte ao dono** quando: (a) uma decisão da §7 bloqueia a tarefa; (b) spike reprova e o plano B é exceção a uma decisão do 00; (c) um AC não pode ser satisfeito como escrito; (d) dois capítulos divergem e a precedência não resolve; (e) a tarefa exigiria permissão do macOS, Keychain, login item, ou ação destrutiva fora do repositório; (f) a evidência visual diverge do Orca e a divergência não está justificada em 03 §23; (g) o custo de modelo de um teste passaria de US$ 0,50 por execução.
- Ao parar, entregue: o que tentou, o que viu, as opções com custo e a recomendação. Não espere ocioso; siga com tarefa independente se existir.

---

## 6. Marcos e gates do dono

| Marco | Gate | Quem aprova |
|---|---|---|
| Fim da Fatia 0 | Checklist da §2.6 | Dono |
| Cada tarefa visual | Lado a lado nos dois tamanhos, OK explícito (P14) | Dono |
| Cada momento de motion | Gravação lado a lado com o protótipo aprovado (04 §9, §11) | Dono |
| Fim de cada fatia | ACs de saída verdes, relatório, dia real de uso | Dono |
| Release `1.0.0` | RT.2 itens 1 a 4 (05 §0.4) | Dono |

---

## 7. Decisões ainda abertas do dono

Consolidadas de `review/E-*.md`, 07 §9, 08 §11 e R3 §12. Nenhuma bloqueia a Fatia 0 inteira; a coluna "Bloqueia" diz quando passa a bloquear.

| # | Decisão | Origem | Recomendação registrada | Bloqueia |
|---|---|---|---|---|
| 1 | **D-Codex-1**: aceitar o trust de hooks do Codex gravado pelo próprio Codex após clique do usuário (zona cinzenta de T10) | 06 §3.3.1, 08 S-05 | **Decidida em P18 (opção B):** trust inline por `-c 'hooks.state={…}'`, sem escrever em `~/.codex`; fallback rollout `estimated` | T2-03 |
| 2 | **Plano B do socket do daemon**: se o launchd não aceitar o caminho no home (S-01), usar `RunAtLoad=false` + `launchctl kickstart` e `bind` próprio em `AB/run/ptyd-v1.sock`, exceção a T1 que precisa ir ao 00 | 08 S-01 | **Não necessário (S-01 aprovou o plano canônico, 2026-10-17, `docs/evidence/spikes/S-01/`).** O modo "daemon filho" ficou como fallback quando o item de login exige aprovação | T1-24 |
| 3 | **Plano B do peer auth** se o S-03 reprovar: `getpeereid` + Team ID ad-hoc só em `DEBUG` por flag de compilação | 08 S-03 | Só aprovar se o S-03 falhar | T1-07 |
| 4 | **Versão do SwiftTerm**: 1.20.0 fixo ou 1.99.0 conforme S-02 | R3 §12 item 6 | 1.20.0 agora | T1-09 |
| 5 | Permissões da máquina de QA: Gravação de Tela, Acessibilidade, login item | 08 AR-825, S-01, S-07 | Dono concede uma vez | T1-02, T1-24 |
| 6 | Destino do código e do `design/` antigos (`legacy/`) | R3 F0-6, 08 AR-202 | Mover para `legacy/` | T1-01 |
| 7 | Tamanho do pacote de referência: Git LFS ou só os PNGs necessários | §2.3 | Só os necessários, sem LFS, se couber em ~50 MB | F0-3 |
| 8 | **Q1** (modo isolado): runtime em container separado do `agent` × P5 "mesmo container" | 07 Q1, R1 D-08 | Manter separado, lido como "mesmo computador"; aberta para a v1.1 | V11-A |
| 9 | **Q3 / P7**: credencial do modo isolado (setup-token direto ou gateway) | 07 Q3, 00 P7 | Abrir a v1.1 com `claude setup-token` e gateway na mesma versão se os termos permitirem | V11-A |
| 10 | **Q4**: modo de permissão padrão no container isolado | 07 Q4 | Herdar o perfil do pai | V11-A |
| 11 | Falta AC em 05 para "Insert Skill or Agent…" (TA-411, agora v1 na Fatia 4); proposta de um AC novo com XCUI da palette e do `[Insert in Prompt]` | Esta revisão | Criar AC-909 em 05 antes da T4-03 (**feito**: AC-909 em 05 §J9) | T4-03 |
| 12 | Imagem do runtime no GHCR pública ou privada | 08 §11.4 | Pública (não contém segredo) | T3-01 |
| 13 | Metas de desempenho iniciais (AR-7xx prevalece sobre 05) | 05 / 08 | Manter 08 | T1-09 |
| 14 | 04: blur do scrim (desligado na v1), dono do `ui-kit.css`, aprovação de tokens `"draft": true`, aprovação por momento | 08 §11.4 | Aprovar por momento no gate P14 | T1-03, T1-11 |
| 15 | 01: `stalled` após 10 min; `stale` fundido em `unknown`; detecção de "o CLI não deixa desligar item global" | 08 §11.4 | Adotar as propostas | T2-01 |
| 16 | 03: `Stop` de subagente "se o harness suportar"; split por arrasto (v1.1); zoom da UI fora do terminal (later); detectar shell ocioso ao fechar | 08 §11.4 | Conforme escrito em 03 | T1-14, T2-01 |
| 17 | Spikes de abertura da v1.1: S5 (15 Claude com setup-token + 3 Codex por 8 h) e S7 (`codex exec-server`) | 07 §9 | Rodar na abertura da v1.1 | V11-A |

Já decididas e que os agentes **não** reabrem: lote na v1 (01 §4.1; contraria R1 D-06), "Insert Skill or Agent…" na v1 Fatia 4, nome "Sessions"/"New Clean Session", sem teto de orçamento de proxy (P13), `Take Over` / `Hand Back`, "Computer" na UI, ⌘Q com overlay e `Keep Running` padrão, raiz de worktree em `~/orca/workspaces`.


## 8. Polimento obrigatório por fatia (feedback do dono, 2026-10-17)

Antes de fechar qualquer fatia roda uma tarefa **TN-POLISH**: varredura de todos os controles e superfícies daquela fatia (cada linha da tabela 03 §24) com o app real em primeiro plano e captura fiel (Gravação de Tela concedida), conferindo hover, press, foco, menus de contexto (sempre `DSMenuPanel`, nunca NSMenu nativo), tooltips, popovers, estados vazio/erro/carregando, motion e "nada sai da caixa". Cada item reprovado vira correção na mesma tarefa. Lista viva de feedback do dono: `docs/evidence/slice1/OWNER-FEEDBACK.md`.
