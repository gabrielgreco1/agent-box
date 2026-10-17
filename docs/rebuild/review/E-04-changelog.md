# E-04 · Changelog da edição de `spec/04-motion.md` após R1–R3

Data: 2026-10-16. Editor: só `04-motion.md` foi alterado. Base: `00-decisions.md` (P11–P16 prevalecem), `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`.

## 1. O que mudou

### Topo e referências
- Marca "Revisado após R1–R3 em 2026-10-16" e lista de decisões ampliada (P11, P14, P15, P16).
- Regra explícita: 04 não define microcopy, atalhos nem `accessibilityIdentifier`. Cita 03 (§21 atalhos, §22 IDs, telas) e a convenção de 02 §17. Se divergir, vale 03.
- **Tabela de correspondência audit/06 → M-xxx** (A1…F6, E0…E4, C9 etc.), copiada de R1 §4 com M-404b em E1. Fica para referência histórica.
- Referências à auditoria com prefixo `audit/NN` (R1 X-21): "06 dizia", "07 (correção 5)", "R6.1 do 10", "R4.7 do 10", "RT.3 do 10", "06 §4.H", "S1".
- "Capítulo de UI" e "capítulo de arquitetura", que não existem, passam a citar 02 e 08. O pacote do DS passa a ser `AgentBoxDesignSystem` (08 AR-121), no lugar de `AgentBoxDesign`.
- `orca-src` em scratchpad sai. O código do Orca passa a vir do pacote versionado `docs/rebuild/reference/orca-1.4.219/` (R3 F0-3).
- §5 se declara a seção de Reduce Motion. A referência "04 §3.3" de 02 está quebrada; o certo é 04 §5. A correção do lado de 02 fica com o editor de 02.

### Números
- Anel de foco: 3 pt (DS9), com o novo token `stroke.focusRing = 3`. `stroke.ring = 2` continua só para o spinner (K-06). Mudou em §5, M-803 e tokens.json.
- Logo da ignição: 32 pt (03 §4.6), não 48. Glifo de computador no viewer: 32 pt (03 §11.4), não 48.
- `AgentStateIndicator`: os tamanhos de 02 §2.6 (`sm` 10 / `md` 12 / `lg` 16, com bolinha de 8 dentro do `md`). Sai o 8/10/12/16. M-403 foi reescrito por variante, não por pt.
- Composer: 560 pt (03 §6), não 512.
- Novo token `opacity.interruptedContent = 0,50`, para o estado Interrupted de 03 §4.6 (scrollback a 50%).
- O token `duration.draw` (0,60) foi removido: era usado só pelo desenho de traço do M-901, que saiu.

### Atalhos
- M-606: o atalho de Take Over passa a ser ⇧⌘R. ⇧⌘T é Reopen Closed Tab (K-85).
- M-308: foco de pane passa a ⌘] / ⌘[. ⌥⌘←/→ é Back/Forward (K-84).
- M-211: o ⌘⇧E sai. A revelação vem do botão "Reveal Current Session" do rodapé, de uma notificação ou da Inbox (K-86).
- M-301 e M-502 usam ⌘T (shell), ⌥⌘T (agente padrão) e Quick Launch ⌥⌘N / "+" (K-83). M-304 usa ⇧⌘] / ⇧⌘[ e ⌃⇥.
- **Motion Lab: ⌃⌥⌘M** (só Debug). O ⌥⌘M antigo colide com "Minimize All" do sistema (R3 §2.2). O novo não aparece em 03 §21.
- Notação unificada no formato de 03 (⇧⌘, ⌥⌘).

### accessibilityIdentifier
Todos os pares da tabela de R1 §4 foram aplicados: `sidebar.sessionRow` → `sidebar.session`, `sidebar.childRow` → `sidebar.session.<s>.child.<c>`, `launchError` → `startError`, `exitedOverlay` → `interrupted`, `launch.*` → `pane.<id>.ignition*`, `launch.chip` → `overlay.composer.launchChip`, `overlay.dialog.*` → `overlay.<name>` / `overlay.confirm*`, `menu.<name>` → `menuPanel.<name>`, `hoverCard.*` → `<host>.hoverCard`, `panel.right.*` → `rightPanel.*`, `screen.*` → `<page>.page`, `split.divider` → `pane.divider`, `box.glyph` → `…child.<c>.glyph`, `computer.*` → `viewer.<computerId>.*`, `computers.thumb` → `rightPanel.computers.thumb`, `titlebar.needsYouBadge` → `sidebar.nav.inbox.badge`, `menubar.status` → `menuBar.icon`, `app.daemonBanner` → `pane.<id>.daemonBanner` / `window.daemonBanner`, `onboarding.*` → os de 03 §22, `empty.*` → `landing` / `sidebar.search.empty` / `<panel>.empty`, `banner.*` → `computers.dockerBanner` / `window.databaseBanner`, `form.*` / `button.*` → `overlay.<name>.*` / `<host>.<button>`. O indicador de estado passa a `<host>.status` (AR-805).

**Pedido ao editor de 03 §22.** Estes IDs estão marcados com † em 04 e ainda não constam da lista canônica:
`overlay.scrim`, `overlay.composer.launchChip`, `overlay.<name>.<field>.error`, `menuPanel.<name>`, `tooltip`, `sidebar.selection`, `sidebar.nav.inbox.badge`, `sidebar.session.<id>.revealGlow`, `sidebar.session.<s>.agent.<t>.lastMessage`, `sidebar.session.<s>.child.<c>.glyph`, `….child.<c>.connector`, `<host>.status`, `tabs.activeIndicator`, `tabs.overflow.leading/trailing`, `pane.<t>.cover`, `.rimFlash`, `.attention`, `.zoomPill`, `.feedbackPill`, `.ignition.step.<stepKey>`, `pane.divider.<id>`, `rightPanel.tabs.indicator`, `rightPanel.computers.thumb.<computerId>`, `viewer.<c>.controlFrame`, `.ghostCursor`, `.clickRipple`, `.helpBanner`, `.connecting`, `.status`, `.disconnected`, `window.daemonBanner`, `window.databaseBanner`, `computers.dockerBanner`, `<panel>.empty`. Também é preciso renomear `landing.newScratch` para `landing.newCleanSession` (P11).

### Estados canônicos (K-78, K-79)
- O texto de M-4xx lista os estados de 01 §6.3, mais `blocked` e `interrupted`. `stale` foi absorvido por `unknown`. `estimated` virou flag. `exited` passa a ser estado de processo.
- M-404 cobre `failed` e `blocked`. **Novo M-404b**: `interrupted`, bolinha `#a1a1a1`, sem animação.
- M-402: `needsInput` usa o balão `?`. `idle_prompt` só conta com turno ativo; agente recém-lançado sem prompt fica `idle`. O badge passou de M-810 para M-701 (X-20).
- M-403: depois de visto, `done` vira `idle` só após 30 min. M-406 ganhou o caso "recém-iniciado sem prompt".
- M-407 e os `accessibilityValue` usam "Status unavailable" (antes "State unknown").

### Nomes e microcopy (texto de 03 prevalece)
- Inbox: M-701 passou a ser o badge do item `Inbox` da sidebar. M-705 é o feed da sidebar. M-109 deixou de tratar Inbox como página (K-27, K-63).
- Needs input / Needs you: "Needs input" para estado de agente; "needs you" só para computador e atenção agregada.
- "Requesting control…" mantido (K-26). Verbos **Take Over / Hand Back** e "Force Take Over" (D-02 com P16). "Paused" virou "You're in control" (K-62).
- Daemon perdido (M-003): banner por pane com "Lost connection to the background service. Reconnecting…", depois "Restart Background Service" / "Open Diagnostics". A UI não usa "agentboxd" nem "daemon" (K-46).
- Pane interrompido (M-002): estado Interrupted de 03 §4.6, com "Resume" / "Start Fresh" / "Close" (K-47).
- Saída com erro (M-312): cartão "Terminal exited" com Close / Restart / Resume Conversation. Com código 0, o banner "Claude Code exited." (K-48).
- Erro de lançamento (M-313, M-505, M-205): "Try Again" / "Open Agent Settings" / "Copy Details", mais "Use Existing Branch" e "Create Without Fetching" (K-48, K-49). Pendente falho usa `AlertCircle` e "Couldn't create worktree".
- Estado vazio (M-901): segue a landing de 03 §19, com "Add Project…", "New Clean Session" (P11) e "Import from Orca…". **Sem desenho de traço do logo**, porque 03 §19 e DS §12.21 dizem "sem ilustração" (R3 §2.2). M-902: `No sessions match "<query>".` + "Clear Search". M-903: sai "Build image in background". M-904: texto de 03 §1.4 com as variantes de 08. M-905: sem ícone.
- Seção "Sessions" e "Move to Project…" em M-212 (P11, K-34). "New Clean Session" ⇧⌘N citada em §7.2.1.
- "Session deleted." · "Undo" 8 s (K-20). "Reuse existing branch". Checklist e linha pendente com os textos de 03 §2.9 e §4.6 ("Preparing launch", "Fetching origin…", "Creating worktree…", "Starting Claude Code…"). `files.copy` virou v1.1 (K-89a). O bloco C segue 03 §11.4 ("Creating computer", "Starting browser").
- K-56 (estados de computador): M-610 com "Reconnecting…" e "Slow connection". M-602 com rótulo curto "Queued".
- M-609 usa `help_request` (K-65). O banner no formato de 03 ("phoenix-az needs you · CAPTCHA on …") ganhou "Decline…".
- "box" saiu da prosa e da UI ("Computer", P15). Ficou só em nomes de ferramenta (`boxes_reserve`), `stepKey` (`box.*`) e `BoxProvisioningGlyph`.
- M-108: abas reais do painel direito, sem a lista Computers/Requests/Agents/Library (K-63). M-109: Settings, Library e Computers.
- M-112: deixou de ser morph herói com avatar e virou lista → detalhe (R2 §5; DS §15).
- M-113: abas de 07 CS-320 (K-59).
- M-612: aba Computers e strip do viewer. O clique abre o viewer como tab, com ≤ 1 fps (K-58, K-9).
- M-103: ⌘Q com agentes vivos vira overlay. `NSAlert` só sem janela aberta (K-90, P15).
- M-703 e M-704: badge com AttentionItems de prioridade 1–2 e ícone conforme 03 §17 (K-53, K-54, D-03).
- Composer: foco inicial no Prompt (K-88). Os grupos do stagger seguem os campos de 03 §6.1.
- VoiceOver: só os anúncios de 02 §14.2. "Session ready" saiu e A12 foi ajustado.
- Settings › Appearance › `Reduce motion` com as opções de 03 (`Follow System` / `On`).

### Fatias (R3 §4.1)
- §0 avisa que os três momentos obrigatórios não cabem todos na Fatia 1.
- **Nova §12.2** com a fatia em que cada momento fica `verified`. Abrir telas e lançamento ficam na Fatia 1. Estados por hooks ficam na Fatia 2; na Fatia 1 o agente aparece como `unknown`. "Computador em uso" fica na Fatia 3, e o isolado na v1.1. Antes disso, o storyboard e o port no Motion Lab com dados simulados podem andar.
- Títulos de §7 marcados com a fatia. Blocos A, B e C da checklist marcados com Fatia 1/2/3. Critério de `verified` exige os dados reais da fatia e a aprovação P14.
- Prioridades renomeadas de P0/P1/P2 para **A/B/C**, porque colidiam com as decisões P* (K-74; R3 sobre "P2 v1 se couber").

## 2. O que NÃO foi aplicado, e por quê

- **"Scratch" (recomendação D-01 de R1):** não foi aplicado. P11 decidiu "Sessions" e "New Clean Session".
- **Blur do scrim, durações do tooltip e resize no início (K-04, K-05, K-93):** 04 já estava certo; nada mudou. As correções correspondentes são em 02, 03, 06 e 08.
- **Tabela de ações, `KeyBindingRegistry` com escopo e teste anti-conflito de atalhos (R3 §7):** fora do escopo do capítulo de motion. Aqui só se garantiu que nenhum atalho citado colide com 03 §21.
- **Texto de M-604 "Claude has control":** mantido. R1 §10 pede que ele entre em 02 §2.8, e isso é com o editor de 02.
- **`window.daemonBanner`:** mantido para o banner "Background agents stopped unexpectedly" (AC-810), como R1 §4 recomenda, embora 03 §22 só tenha `pane.<id>.daemonBanner`. Precisa entrar em 03.
- **Textos de checklist que 03 não tem:** "Running setup script", "Checking Docker", "Building image", "Starting network proxy" e "Starting desktop" ficaram como proposta (†) até 03 incluí-los.
- **Evento `computer.click(…)` em §7.3.1:** mantido. É nome interno de evento de input, não ferramenta MCP nem texto de UI.
- **Spikes, pacote de referência do Orca, lint de UI e `compare-ui.sh` (R3 §5/§6):** são de 08 e da Fatia 0. 04 só cita o pacote de referência como origem do código do Orca.
- **Correções em outros capítulos que citam 04:** 02 §11 com os IDs M-xxx, 02 "§3.3" → "§5", 03 `M:` → `M-` e 05 "04 E2/E3". Ficam com os editores desses capítulos; a tabela de correspondência em 04 serve de apoio.
