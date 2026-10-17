# E-02-03 · Changelog da edição de 02-design-system e 03-screens

Data: 2026-10-16. Escopo: aplicar em `spec/02-design-system.md` e `spec/03-screens.md` os patches que R1, R2 e R3 atribuem a esses arquivos, com as decisões P11–P16 de `00-decisions.md` e os recados dos editores de 04, 07 e 01+05. Os dois arquivos estão marcados no topo com "Revisado após R1–R3 em 2026-10-16". Nenhum outro capítulo foi tocado.

## 1. O que mudou

### Decisões do 00 aplicadas
- **P11**: "Scratch" saiu de tudo. Agora são clean sessions, seção **Sessions**, ação **New Clean Session** (⇧⌘N) e **New Clean Session in Folder…** (⌥⇧⌘N, que AC-1105 pedia e não existia). O composer usa `No Project (Clean Session)`. IDs: `sidebar.cleanSessions[.new]` e `landing.newCleanSession`. O nome automático é `quiet-harbor` (P15) e renomear a sessão não renomeia a pasta.
- **P13**:
  - Saiu todo teto de orçamento: os campos de orçamento do Settings, os eventos de 80% e de 100% com `[Add $1]` na Inbox, o switch `Budget alerts` e o alerta de 80% na status bar.
  - Entrou **Settings › Computers › Proxies**: lista de `ProxyProfile`, `Default proxy for computers`, formulário com `Name` / `Preset` (`Custom` · `Zyte (proxy)` · `Zyte API (render)`) / `Type` (`HTTP` · `HTTPS` · `SOCKS5`) / `Host` / `Port` / `Username` / `Password` / `Country` / `Extra CA certificate` / `Render endpoint` / `API key` / preços informativos, botão `[Test Proxy]` e `Import from agentbox CLI…`.
  - Entraram também `Computer proxy` no composer, `Proxy ▸` no viewer, a coluna `Proxy` (nome + uso) na página Computers e o segmento **Proxy usage** (`statusBar.proxyUsage`, que antes era `proxySpend`), sem limites.
- **P14**: nova **03 §23 Checklist de fidelidade visual com o Orca**. A comparação é lado a lado em 760×480 e 1440×900, com `compare-ui.sh`, `LayoutConformanceTests` e OK explícito do dono. DS §15 e 03 §20 passam a citá-la.
- **P15**:
  - "Computer" na UI e "box" fora dela. Os textos do modo isolado usam "Container" (`Container stopped`, `Test in a Container`, `Isolated agents`).
  - O ⌘Q virou overlay (§16.10), **nunca NSAlert**, com `Keep Running` como padrão e `Don't ask again` ligado ao novo `Ask before quitting with running agents`.
  - Sessões importadas aparecem como `Not started`, com `Start Claude Code`, e cada projeto mostra só as 5 mais recentes mais `Show <n> more`.
  - Raiz de worktree em `~/orca/workspaces`.
- **P4 / D-03**: saiu a opção `Never` do ícone da menu bar. O helper de login também saiu: o app fica em `.accessory` e ganhou `Quit Agent Box Completely`.
- **P16**: os conflitos foram resolvidos pela recomendação dos revisores, incluindo D-02 (`Take Over` / `Hand Back`, IDs `.takeOver` / `.handBack`, ⇧⌘R), D-09, D-11 e D-12.

### R1 (consistência)
- **Números**:
  - blur do scrim desligado na v1 (K-05) e tooltip M-106 com 150/100 ms (K-04);
  - anel de foco de 3 pt e token `stroke.focusRing` (K-06);
  - spinner pelo M-811 (K-07) e hover da tab em 120 ms (K-08);
  - miniatura a ≤ 1 fps (K-09) e Undo de 8 s com o toast `Session deleted.` (K-20);
  - composer com 560 de largura.
- **Nomes e microcopy**:
  - K-26 `Requesting control…`, K-29 `Next Needing Attention` e K-30 `Skip permissions (<flag>)` / `Skip Permissions`;
  - K-31 perfis `Claude · Skip permissions` e K-32 opções de "Where";
  - K-34: `Move to Project…`, `Convert to Project…` e `Move Folder into Project…` (v1.1), sem git init;
  - K-35 nome derivado do prompt e K-36 duplo clique na nota;
  - K-39 `Log In` no lugar de `Sign In` e K-40 `Block in Agent Box` · `Disable Globally…` · `Keep` + `Restore Skill`;
  - K-42: os textos de orçamento foram removidos (P13);
  - K-46 "background service" e K-47/K-48 variantes de saída e de interrupção;
  - K-49 `Try Again`, que substituiu todo `Retry`;
  - K-50: variantes do banner de banco, `Reveal Corrupt File` e `window.databaseBanner`;
  - K-51 título das notificações, K-52 `Terminal bell` desligado por padrão, K-53 ícone da menu bar e K-54 badge do Dock com prioridade 1–2;
  - K-55: `Credentials`, `Export Diagnostics…`, `Automation on`, `Security model`, `Export Database…` / `Restore from Backup…`, `Import Again…` e `Reload Shell Environment`;
  - K-56 estados de computador (`Waiting for memory · 3 of 15 queued`, `Ready` / pill `Idle`) e K-57 `Decline…` com motivo;
  - K-58: hover amplia a miniatura (M-612). K-59: abas Activity, Network, Journal, Commands, Files, Timeline e Result;
  - K-60 `On This Mac` / `In Container` e K-62 `You're in control`;
  - R1 §10: pill `Claude has control`.
- **Estados canônicos (K-78, K-79)**:
  - DS §2.6 segue 01 §6.3 mais `blocked`. `Needs input` é o rótulo do estado; `Needs you` fica só para atenção agregada.
  - `stale` virou `unknown` / `Status unavailable`, e `estimated` passou a ser uma flag.
  - DS §2.7 ficou com `launching`, `killed`, `interrupted`, `containerPhases` e `Container stopped`, e perdeu `reattached`.
- **Motion**: todos os códigos `M:Xn`, `A1…F6` e `E0…E4` foram trocados pelos `M-xxx` de 04 conforme R1 §4. O grep por `M:[A-Z§]` e por códigos antigos entre crases volta vazio nos dois arquivos.
- **Atalhos (03 §21 canônica)**:
  - ⌘T é shell, ⌥⌘T é o agente padrão e ⌥⌘N é o Quick Launch.
  - Foco de pane só com ⌘] / ⌘[, e ⌥⌘←/→ é histórico.
  - ⇧⌘T é só reabrir tab. ⌘⇧E não existe. O Motion Lab usa ⌃⌥⌘M (o ⌥⌘M do sistema fica livre).
  - O roteamento de ⌘F por escopo está explícito, e ⇧⌘⌫ não age com o terminal focado.
  - Há um teste anti-conflito no `KeyBindingRegistry`, e toda a notação está na ordem da Apple (⌃⌥⇧⌘).
- **Referências quebradas**: X-01 a X-11 corrigidas. A regra do prefixo `audit/NN` foi aplicada em todas as citações da auditoria (X-13, X-21), e a citação "checklist 04 §8" passou a apontar para 03 §23.
- **"P2" como prioridade**: virou `v1.1, TA-119` / `later`. O zoom da UI fora do terminal é later e fica desabilitado com motivo.
- **Regra 15 do DS**: deixou de proibir 720 e 760, que são constantes de §5.2.
- **Versões (K-89)**: Pin (v1.1), ações da menu bar (v1.1), lembrete de 3 min (v1.1), eventos de PR (v1.1), `Open at login` removido, Clone from URL (v1.1) e `.env` (v1.1).
- **Bookmarks (AR-533)**: saíram "Pasta escolhida vira bookmark" e "Reauthorize Folder…".

### R2 (cobertura)
- Paleta **Insert Skill or Agent** (SEM #1): modo `/` no ⌘J, comando no menu Session e `[Insert in Prompt]` na Library e na aba Context. Cola por bracketed paste sem Enter (T11).
- **Regra de salvamento do Settings** (03-B22): salva ao mudar ou no blur, sem botão Save, com indicador de mudança pendente, erro inline e `Applies to new terminals.`.
- **Nada sai da caixa**: nova §1.5, com regras por superfície em 760×480, fixtures de nomes longos e critério de teste.
- Outras lacunas fechadas:
  - notificação de lote concluído (SEM #2) e ícone do app (SEM #19, DS §9.2);
  - split arrastando a tab marcado como v1.1;
  - variante em container do Stop computer e popover `Container` (07 #45, v1.1);
  - lista de itens later em §0 (SEM #6–8, #11, #20);
  - Filter da sidebar como later (R2.6).

### R3 (implementabilidade)
- **Nova 03 §24 Tabela de ações**: `ActionID`, efeito, motivo de desabilitado e versão para cada controle e item de menu, incluindo os mais de 25 itens que estavam sem comportamento (Check for Problems, Hide App Name, Locate Folder…, Show Launch Details, Show Hook Log, Refresh Git, Collapse All Sessions, Mute Notifications, Rename Branch…, Restart with ▸, Reset Title, Send Interrupt, Close Other Panes, Equalize Pane Sizes, Open Computer…, Agent Settings…, Manage Agents…, Open Diagnostics, Stop All Agents…, Pause Notifications, Agent Box Help, Hide from Sidebar, Open in Editor/terminal com a configuração em Settings › General). Novos overlays: §16.13 Rename Branch e §16.14 About.
- **03 §22 é a lista única e canônica** de IDs (DS §17 só dá a convenção). Inclui:
  - os 35 IDs que 04 marcou com †;
  - os de 07: `batch.*`, `overlay.newBatch.*` e `settings.computers.proxies.*`;
  - `<host>.status`;
  - `.takeOver` / `.handBack`.
- **Proibição explícita** de `LocalProcessTerminalView`, de resposta a OSC 52 de leitura e de `TerminalFindBarView`, em DS §3, DS §16, 03 §4.1 e no lint.
- **Lint de UI** especificado (padrões e testes do próprio lint), mais a regra "todo Button passa pelo ActionRegistry".
- **Feature flag por fatia**: controle de fatia futura não renderiza (DS §15 regras 20 e 21; 03 §0 e §20).
- Também:
  - caminho dos tokens no alvo `AgentBoxDesignSystem` (08) e `design/` declarado legado;
  - Geist com o nome upstream, SHA e `OFL.txt`;
  - pacote de referência `docs/rebuild/reference/orca-1.4.219/` no lugar de `scratchpad/orca-src`;
  - estado `Not started` (AC-109);
  - critério de "shell ocioso" definido;
  - `Stop Subagent` só renderiza com a capacidade.

### Pedidos dos outros editores
- **04**: IDs † adicionados e `landing.newCleanSession`; textos de checklist `Running setup script` (v1.1), `Checking Docker`, `Building image`, `Starting network proxy` e `Starting desktop` em §4.6 e §11.4; M-901 sem desenho de traço (DS §12.21 alinhado).
- **07**: lote na **v1** (decisão do dono passada pelo 07). Entraram o painel §12.4 Batch, o overlay §16.15 New Batch…, `File › New Batch…` e o evento de lote concluído na Inbox. Proxies ficaram como subseção de Settings › Computers, como em 07 CS-160.
- **01+05**: rótulos finais de Proxies listados acima, para alinhar AC-118, AC-418 e AC-1004. ⌘T = shell, ⌥⌘N = Quick Launch, `Take Over` / `Hand Back`, e §23 nos dois tamanhos para AC-T26 e AC-T27.

## 2. O que NÃO foi aplicado, e por quê

- **D-01 "Scratch"** (recomendação de R1): contrariado por P11.
- **K-90 "NSAlert quando não há janela"**: não foi aplicado. O dono pediu ⌘Q sempre em overlay. Sem janela, o app abre a janela principal e mostra o overlay nela. `NSAlert` fica só para erro fatal de inicialização (antes de existir janela).
- **K-42 (`Add $1.00`) e D-04 (níveis de orçamento)**: removidos por P13, que não tem orçamento.
- **D-06 (lote na v1.1)**: contrariado pela decisão do dono repassada pelo editor de 07 (lote na v1). **01 §4.2 ainda lista o lote na v1.1** e precisa de ajuste.
- **Tamanhos do `AgentStateIndicator` (R3 §2.2: 02 com 10/12/16 × 04 com 8/10/12/16)**: ficou o 02, que é dono dos tokens visuais. 04 foi avisado no texto ("04 M-4xx usa estas caixas").
- **Tabela tecla → bytes (R3 §7.7) e protocolo do `ctl`**: são de 06 e 08; 03 só referencia.
- **Clean Up…**: marcado v1.1 por 01 §4.2 (R10.4). R1 não apontou isso, e 01 prevalece no escopo.
- **Insert Skill or Agent na v1 (Fatia 4)**: decidido aqui porque R2 pedia uma decisão. 01 §4 e 06 §4.2 precisam registrar a ação e o texto de invocação por CLI.
- **Microcopy de terceiros**: os textos de onboarding em 05 (`Signed in` etc.) e os nomes de ferramenta MCP são correções de 05 e 07; aqui só ficou o texto canônico de 03.
- **Contagens do Orca nos exemplos (6 repos, 103 worktrees)**: mantidas como exemplo de fixture (K-23 só pede mudança no aceite de 08).
- **Fatia 1 redefinida (R3 §10)**: é decisão do 01. As telas marcam a fatia nos controles que dependem dela (Fatias 2, 3 e 4), sem redefinir as fatias.
