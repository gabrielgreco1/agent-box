# 02 · Design system

Status: spec do rebuild. Data: 2026-10-16. **Revisado após R1–R3 em 2026-10-16** (mudanças em `review/E-02-03-changelog.md`). Prevalece: `00-decisions.md`. Base: auditoria `audit/03`, `audit/04`, `audit/06`, `audit/07`, `audit/10` e o código-fonte do Orca 1.4.219 (renderer extraído do `app.asar` instalado para `docs/rebuild/reference/orca-1.4.219/`, R3 F0-3; nunca de um scratchpad).

Este capítulo define **tokens, componentes base, foco, acessibilidade e regras visuais**. Telas e microcopy completas ficam em `03-screens.md`. Animações ficam em `04-motion.md` e aqui só são referenciadas pelo ID `M-xxx` de `04-motion` (mapeamento a partir da auditoria 06 em `review/R1-consistency.md` §4). Os `accessibilityIdentifier` seguem a convenção de §17, e a **lista canônica é `03 §22`**.

Convenções:
- Medidas em **pt** (1 px do Orca com zoom 0 = 1 pt no Mac). Tailwind: 1 unidade = 4 pt.
- `fg/x` = `foreground` (`#fafafa`) com opacidade `x`%. Ex.: `fg/8` = `#fafafa` a 8%.
- Toda string de UI está em **inglês** (P2). O texto da spec é português.
- "Orca:" aponta para o arquivo-fonte de onde o valor foi tirado (relativo a `src/renderer/src/` do pacote de referência `docs/rebuild/reference/orca-1.4.219/`, salvo indicação).
- Referência à auditoria sempre com prefixo `audit/NN` (ex.: `audit/07 #3`). "07" sozinho é o capítulo 07 da spec.
- Versões: **v1**, **v1.1** e **later** (01 §4). "P2" é sempre a decisão P2 do `00` (UI em inglês), nunca prioridade.
- A pasta `design/` do repositório é **legado** do app antigo (telas em PT-BR com Manrope, `design/motion/timeline.html`): não é referência. Os tokens desta spec nascem em `design/tokens/*.json` limpos (R3 §3, F0-6).

---

## 0. Decisões de valores onde os relatórios divergiam

Conferidas no código do Orca. Estas linhas valem sobre os relatórios.

| # | Assunto | Divergência | Decisão | Fonte verificada |
|---|---|---|---|---|
| DS1 | Atraso do tooltip | 04 diz ~700 ms (padrão Radix); 07 diz 400 ms | **400 ms** padrão; tabs 500 ms; ✕ da tab 1000 ms; bolinha de estado 200 ms | `App.tsx:92`, `components/ui/tooltip.tsx` (`delayDuration = 0` no primitivo, sobrescrito no app) |
| DS2 | Dialog: scrim e escala | audit/06 C9 propõe scrim 0,45 e escala 0,96 | Scrim **`black/55`** (o blur 2 pt do Orca fica desligado na v1; só liga se o Instruments aprovar, 04 §2 e R8); entrada **fade + zoom 0,95→1 em 200 ms** (M-101) | `components/ui/dialog.tsx:40,115` |
| DS3 | Menu: escala e duração | 06 §2 junta tudo em 150 ms/95% | Menus **150 ms, zoom 0,98→1**, slide 8 pt do lado | `components/ui/dropdown-menu.tsx:36` |
| DS4 | Opacidade de pane inativo | audit/04 diz 0,9 | **0,8** (config real do dono; 0,9 é só o padrão do Orca). Configurável em Settings › Terminal | `audit/07 correção 3` |
| DS5 | Largura da sidebar | spec antiga 288 (224–480) | **280 (220–500)** | `audit/04 §3`, config do dono `sidebarWidth: 280` |
| DS6 | Janela mínima | spec antiga 1000×650; Orca 600×400 | **760×480**. 760 = sidebar 220 + centro 320 + painel direito 220. Abaixo de 1100 de largura o painel direito recolhe sozinho. Nada sai da caixa nessa largura (03 §1.5) | `audit/07 correção 8` |
| DS7 | ⌘K | 01 AA8 e app atual usam ⌘K para busca/palette | **⌘K = Clear Terminal**, **⌘J = palette** (padrão de Terminal.app/iTerm/Ghostty e do Orca) | `shared/keybindings/definitions-core-3.ts:258` |
| DS8 | ⌘, | Orca não tem atalho para Settings | **⌘, = Settings** (padrão macOS). Terminal não recebe ⌘, | HIG |
| DS9 | Anel de foco | Orca usa 3 px `ring/50`; audit/07 sugere 2 pt; 04 usava 2 pt | **3 pt** `ring` a 50% (fidelidade ao Orca), desenhado por fora do controle (outset), raio = raio do controle + 3. Token `stroke.focusRing = 3` (04); o `stroke.ring = 2` de 04 é só o traço do spinner | `components/ui/button.tsx:8`, `input.tsx:15` |
| DS10 | Cor do spinner "working" | audit/06 E1 propõe arco na cor do provider | **Amarelo `#eab308` para todo agente**, como no Orca. Quem é o agente já é dito pelo logo ao lado; o indicador diz só o estado | `AgentStateDot.tsx` (comentário "one for *who*, one for *what state*") |
| DS11 | Fonte da UI | 04 aceita SF Pro como alternativa | **Geist Variable embutida** (OFL). SF Pro só como fallback automático se a fonte não carregar | config do dono `appFontFamily: Geist` |
| DS12 | Tooltip nativo | audit/04 §7 diz que `.help()` basta | **Tooltip próprio** (com keycap) na titlebar, tab bar, header de pane, status bar e ícones de ação; `.help()` só em controles de formulário | `audit/07 #27` |
| DS13 | Tema claro | Orca tem claro/escuro/sistema | **Só escuro na v1**, `NSApp.appearance = .darkAqua`. Tokens claros já documentados (§2.11) para não refazer | `audit/07 #19` |
| DS14 | Tabs: tamanho do texto | app atual 13 pt | **12 pt** (`text-xs`), largura fixa 180/220, mín. 72 | `tab-width-rules.ts:1-3` |
| DS15 | Idioma | audit/07 §I propõe pt-BR e glossário pt | **Inglês** (P2). O glossário de §18 substitui o de audit/07 #53 | `00-decisions P2` |

---

## 1. Princípios visuais

1. **É o Orca.** Antes de inventar um valor, procurar o equivalente no Orca. Quando o Agent Box tem algo que o Orca não tem (computadores, subagentes em box, controle humano), o componente novo é feito **com as peças existentes** (mesmos tamanhos de linha, badges, bolinhas, raios) e nunca com um estilo próprio.
2. **Dois níveis de cinza.** Sidebar `#2a2a2a` mais clara que o canvas `#0a0a0a`; faixa de tabs, status bar e painel direito em `#171717`. O terminal é `#282c34`. Essa hierarquia é a "cara" do Orca.
3. **Bordas sempre `white/7`.** Nunca cinza sólido, nunca 2 pt (exceto a barra da tab ativa e o divisor de pane de 3 pt).
4. **Densidade de linha.** Linhas de 24–32 pt, texto de 11–13 pt, raios de 4–10. Nada de cards grandes, padding acima de 16 no conteúdo de trabalho, nem títulos com subtítulo em toda tela.
5. **Cor = estado.** Cor saturada só aparece para dizer um estado (agente, PR, checks, controle do computador, erro). Ações não têm cor: o botão primário é claro sobre escuro.
6. **Motion = estado.** Só se move o que está de fato acontecendo (agente trabalhando, box provisionando, agente no controle). Ver `04-motion`.
7. **O terminal manda.** Nada desenha por cima do texto do terminal em regime permanente, nada anima o frame do terminal, nada rouba foco dele sem o usuário pedir.

---

## 2. Cores (tema escuro)

Implementação: `enum DS.Color` no alvo `AgentBoxDesignSystem` (`Packages/AgentBoxKit/Sources/AgentBoxDesignSystem/Tokens/Colors.swift`, 08 §1.2), gerado de `design/tokens/colors.json`. Cada token é um `Color` e um `NSColor` (para AppKit/SwiftTerm). Valores com alfa são `Color(white: 1, opacity: x)` **compostos sobre a superfície**; nunca pré-misturar em hex, porque a mesma opacidade cai sobre fundos diferentes.

### 2.1 Superfícies

| Token (Swift) | Orca | Hex / valor | Uso |
|---|---|---|---|
| `canvas` | `background` | `#0a0a0a` | Fundo da janela e da área central atrás do terminal; fundo das páginas Library/Computers; landing vazia. `NSWindow.backgroundColor` |
| `chrome` | `card` | `#171717` | Faixa de tabs, status bar, header de página (36), cards de onboarding, superfícies de popover sólidas |
| `sidebar` | `worktree-sidebar` | `#2a2a2a` | Sidebar esquerda inteira e a faixa de titlebar de 36 pt acima dela |
| `sidebarSelected` | `worktree-sidebar-accent` | `#353535` | Item de nav ativo; linha de agente cujo pane está focado |
| `panel` | `sidebar` | `#171717` | Painel direito; sidebar de Settings |
| `panelSelected` | `sidebar-accent` | `#262626` | Item ativo dentro do painel direito |
| `secondary` | `secondary`/`muted` | `#262626` | Botão secondary; trilho de toggle; fundo de keycap; skeleton base |
| `accent` | `accent` | `#404040` | Hover de botão ghost (a 50%); hover dos botões da titlebar (100%); toggle "on" |
| `editor` | `editor-surface` | `#1e1e1e` | Diff e visualizador de arquivo (SKILL.md, agente) |
| `overlayCard` | dialog dark | `rgba(23,23,23,0.96)` + blur do material | Fundo de dialog/overlay/palette |
| `menuMaterial` | menu dark | `rgba(0,0,0,0.72)` + blur 2xl | Fundo de menus e popovers ricos |
| `scrim` | overlay | `black/55` (sem blur na v1, 04 R8) | Atrás de dialog/overlay |
| `terminalBackground` | tema do dono | `#282c34` | Fundo do terminal e dos placeholders de pane |

### 2.2 Texto e ícones

| Token | Valor | Uso |
|---|---|---|
| `textPrimary` | `#fafafa` | Texto principal, ícone ativo |
| `textSecondary` | `#a1a1a1` (`muted-foreground`) | Texto secundário, ícone inativo, labels de campo |
| `textTertiary` | `#a1a1a1` @ 60% | Tempo relativo, contador, hint de rodapé |
| `textQuaternary` | `#a1a1a1` @ 45% | Placeholder (`muted-foreground/60` no input ≈ este) |
| `textOnPrimary` | `#171717` | Texto do botão primário |
| `navText` | `fg/60` | Texto dos itens de nav e do Search na sidebar |
| `navIcon` | `fg/30` | Ícone dos itens de nav e do Search |
| `paneTitle` | `white/52` | Título do header de pane |
| `paneTitleInput` | `white/70` sobre `white/4` | Campo de renomear no header do pane |
| `disabled` | elemento inteiro a 50% | Controles desabilitados (Orca `disabled:opacity-50`) |

### 2.3 Opacidades de `fg` (sobre qualquer superfície)

| Token | Valor | Uso |
|---|---|---|
| `fg5` | `fg/5` | Fundo do campo Search da sidebar |
| `fg6` | `fg/6` | Fundo da tab ativa (sobre `chrome` ≈ `#1f1f1f`); fundo do badge `primary`/neutro |
| `fg8` | `fg/8` | Hover de nav item e do Search |
| `fg10` | `fg/10` | Fundo do card de sessão ativo |
| `fg18` | `fg/18` | Borda do card de sessão ativo |
| `fg20` | `fg/20` | Borda do badge neutro |
| `hoverRow` | `sidebarAccent(#262626)/40` | Hover do card de sessão |
| `hoverAgentRow` | `accent/18` | Hover da linha de agente |

### 2.4 Linhas, inputs, foco

| Token | Valor | Uso |
|---|---|---|
| `border` | `white/7` | Todo divisor e borda de painel; separador entre tabs |
| `borderStrong` | `white/14` | Borda de menus, dialogs, popovers, toasts |
| `input` | `white/15` | Borda de inputs; fundo de outline button a 30% (`input/30`) |
| `ring` | `#737373` | Anel de foco (usado a 50%); linha de resize da sidebar em drag |
| `paneDivider` | `#3f3f46` | Divisor de split dentro de uma tab (3 pt) |
| `groupDivider` / `groupDividerStrong` | `#71717a` / `#a1a1aa` | Divisor entre grupos de tab (split por arrasto, v1.1, TA-119) e hover/drag dele |
| `paneTitleSeparator` | `white/6` | Linha sob o header de pane |

### 2.5 Semânticas

| Token | Hex | Uso |
|---|---|---|
| `destructive` | `#ff6568` | Texto/ícone de erro e de ação destrutiva; borda de input inválido |
| `destructiveFill` | `#ff6568` @ 60% | Fundo do botão destructive (Orca `dark:bg-destructive/60`) |
| `success` | `#86efac` | Texto de sucesso ("Connected", "Logged in") |
| `warning` | `#eab308` | Aviso não bloqueante ("Token expires in 12 days") |
| `locate` | `#60a5fa` (blue-400) | Rim flash de localizar pane (M-309) |
| `aiAccent` | `#a78bfa` (violet-400) | Cor de "agente no controle" do computador (§2.8) |

Fundos de aviso: `warning/10` com borda `warning/25`; erro: `destructive/10` com borda `destructive/40` (badge `rename failed` do Orca).

### 2.6 Estados de agente

Fonte: `T10` (hooks por lançamento), `AgentStateDot.tsx`, estados de domínio de 01 §6.3 (mais `blocked`, só de subagente). **Um glifo diz o estado; o logo ao lado diz quem.** Nunca fundir os dois. O rótulo `Needs input` é o do estado do agente; "Needs you" fica só para atenção agregada (Inbox, contadores, pedidos de computador).

| Estado (modelo) | Label (UI, tooltip e VoiceOver) | Glifo | Cor | Lucide | Movimento (`04-motion`) |
|---|---|---|---|---|---|
| `starting` (processo lançado, sem evento de sessão) | `Starting` | Spinner genérico `md` cinza | `#a1a1a1` | — | M-811 |
| `working` | `Working` | Arco 270°, traço 2 pt, topo transparente | `#eab308` | — (desenhado) | M-401 (12 passos/s, fase sincronizada) |
| `needsInput` (subtipos `question`, `permission`, `other`) | `Needs input` | Balão com `?` | `#f97316` (orange-500); texto relacionado `#fdba74` | `MessageCircleQuestion` | M-402 (ripple 2× na entrada) |
| `waitingOnSubagents` (turno acabou, filhos rodando; R6.1) | `Waiting on subagents` | Ícone de atividade (estático) | `#eab308` | `Activity` | M-405 |
| `done` (turno concluído) | `Done` | Check em círculo (tabs, linhas, inbox) / bolinha (coluna do card) | `#10b981` (emerald-500) | `CircleCheck` | M-403 |
| `failed` | `Failed` | Bolinha | `#ef4444` (red-500) | — | M-404 |
| `blocked` (subagente com `BLOCKED` no diário, CS-260) | `Blocked` | Bolinha | `#ef4444` | — | M-404 |
| `interrupted` (reboot, processo morto) | `Interrupted` | Bolinha | `#a1a1a1` | — | nenhum (M-404b) |
| `idle` (`done` visto e sem atividade há 30 min, ou agente recém-iniciado sem prompt) | `Idle` | Bolinha | `#737373` @ 40% | — | M-406 |
| `unknown` (sem hooks, ou hooks calados além da janela) | `Status unavailable` (tooltip com o motivo, ex. `Status unavailable — hooks not connected`) | Círculo tracejado | `#f59e0b` (amber-500) | `CircleDashed` | M-407 |
| `stalled` (v1.1, subagente sem atividade há 10 min) | `Stalled?` | Círculo tracejado | `#f59e0b` | `CircleDashed` | nenhum |
| *(shell puro, sem agente)* | — | nenhum glifo | — | — | — |

`estimated` não é estado: é uma marca (OpenCode, shell) que acrescenta `(estimated)` ao tooltip. `exited` é estado de processo (§2.7), não de agente.

Tamanhos do indicador (`AgentStateDot` do Orca; 04 M-4xx usa estas caixas):

| Variante | Caixa | Bolinha | Spinner | Ícone (`?`, check, activity) | Onde |
|---|---|---|---|---|---|
| `sm` | 10 | 6 | 10 (traço 1,5) | 10 | Linha de agente, linha filha, inbox |
| `md` | 12 | 8 | 12 (traço 2) | 12 | Tab, header de pane, coluna de status do card (bolinha 8) |
| `lg` | 16 | 10 | 16 (traço 2) | 16 | Linha pendente, viewer, menu bar extra (template) |

**Estado agregado do card de sessão** (coluna de status): a agregação de 01 §6.3, o pior estado entre os agentes: `needsInput` > `failed`/`blocked` > `working` > `waitingOnSubagents` > `done` não lido > `interrupted` > `done` lido > `idle` > `unknown`. Pedido de ajuda de computador conta como `needsInput`. `done` lido vira bolinha emerald; `idle` vira bolinha cinza 40%.

**Não lido** (`unread`): bolinha `#f59e0b` de 6 pt no canto superior direito da coluna de status do card, nome em 600, tab com overlay `amber-500/10`, item com ponto na inbox, badge no Dock, ponto no ícone da menu bar.

### 2.7 Processo / terminal

O estado do processo é separado do estado do agente (um shell não tem agente; um Claude pode estar vivo e `idle`).

| Estado | Label | Indicador | Onde aparece |
|---|---|---|---|
| `launching` | `Starting…` | Spinner `md` cinza `#a1a1a1` (ignição só depois de 300 ms, M-503/M-506) | Header de pane, tab, linha de agente (até o primeiro byte) |
| `running` | — (o estado do agente assume) | — | — |
| `exited(0)` | `Exited` | Bolinha `#737373` | Tab, linha |
| `exited(≠0)` / sinal externo | `Exited with code <n>` / `Killed (<SIGNAME>)` | Bolinha `#ef4444` | Tab, linha, overlay no pane (M-312) |
| `killed` (parado pelo usuário) | `Stopped` | Bolinha `#737373` | Tab, linha |
| `failedToStart` | `Couldn't start` | Bolinha `#ef4444` | Tab, linha, estado do pane (M-313) |
| `interrupted` (reboot ou PTY perdido) | `Interrupted` | Bolinha `#a1a1a1` | Tab, linha, pane esmaecido |
| `containerPhases` (isolado, v1.1) | `Preparing container…` | `BoxProvisioningGlyph` (M-601) | Tab, linha, pane |
| `containerStopped` (isolado, v1.1) | `Container stopped` | Bolinha `#ef4444` | Tab, linha, pane |
| `daemonUnavailable` (estado de UI, não de domínio) | `Reconnecting…` | Spinner `md` cinza | Banner no pane (M-003) |
| *(sessão importada, nunca iniciada)* | `Not started` | nenhum glifo | Card e centro (03 §4.7) |

Reanexar ao daemon (`reattached`) não é estado: o pane volta como `running`.

### 2.8 Computadores e controle

| Estado | Label | Visual | Cor |
|---|---|---|---|
| `provisioning` | `Starting computer…` | `BoxProvisioningGlyph` (caixa tracejada, M-601) | `#a1a1a1` |
| `queued` | `Waiting for memory · 3 of 15 queued` (curto: `Queued`) | Ícone `Hourglass` 12 (M-602) | `#a1a1a1` |
| `ready`, ninguém usando | `Ready` (pill de controle sem dono: `Idle`) | Ícone `Monitor` 12 | `#a1a1a1` |
| `agentControl` | `Claude is using this computer` (pill `Claude is using`) | Borda viva no viewer + pill; ícone `Monitor` com arco `working` (M-604/M-605) | `aiAccent #a78bfa` |
| `agentControl`, agente sem ação há > 10 s | `Claude has control` (pill sem spinner) | Borda viva parada | `aiAccent` |
| `revoking` | `Requesting control…` | Pill com spinner (M-606) | `#a78bfa` → dessatura |
| `humanControl` | `You're in control` | Borda 2 pt sólida + pill (M-607) | `#fafafa` |
| `helpRequested` | `Needs you · CAPTCHA` | Borda que respira + banner (M-609) | `#f97316` |
| `reconnecting` / `delayed` | `Reconnecting…` / `Slow connection` | Frame a 40% de saturação + pill (M-610) | `#a1a1a1` / `#eab308` |
| `stopped` | `Stopped` | Ícone `Monitor` a 50% | `#737373` |
| `failed` / `oom` | `Computer failed` / `Out of memory` | Bolinha | `#ef4444` |

Selo de **modo** (P5), sempre ao lado do logo do agente. Na escolha (composer, Settings) os modos se chamam `On This Mac` e `In Container`:
- **In Container** (CLI no container, v1.1): ícone `Box` 10 pt `#a1a1a1`, tooltip `Runs in a container`. Clicável no header do pane: popover com CPU, memória e imagem (03 §4.2).
- **On This Mac** (CLI no Mac, computador no Docker): o selo fica no **computador** (`Monitor` 10 pt), nunca no terminal; tooltip `Runs on your Mac · computer in Docker`.

### 2.9 Git, PR e checks

| Token | Valor | Uso |
|---|---|---|
| `gitAdded` / `gitModified` / `gitDeleted` / `gitUntracked` / `gitRenamed` | `#81b88b` / `#e2c08d` / `#c74e39` / `#73c991` / `#73c991` | Letras de status de arquivo (A/M/D/U/R) no Source Control; ponto de "dirty" no card (`gitModified`, 6 pt) |
| `diffAddedBg` / `diffAddedGutter` | `#81b88b` @ 16% / @ 30% | Diff só leitura |
| `diffRemovedBg` / `diffRemovedGutter` | `#c74e39` @ 18% / @ 32% | Diff só leitura |
| `prOpen` | `#10b981` @ 80% | Ícone `GitPullRequest` |
| `prDraft` | `#a1a1a1` @ 50% | Ícone `GitPullRequestDraft` |
| `prMerged` | `#c084fc` (purple-400) @ 70% | Ícone `GitMerge` |
| `prClosed` | `#a1a1a1` @ 60% | Ícone `GitPullRequestClosed` |
| `checksFailing` | `#f43f5e` (rose-500) @ 85% | Ícone `CircleX` 12 / chip |
| `checksPending` | `#f59e0b` @ 85% | Ícone `CircleDot` 12 (estático) |
| `checksPassing` | `#10b981` @ 80% | Ícone `CircleCheck` 12 |
| `conflict` | `#f59e0b` | Badge `GitMerge` "Conflicts" |

### 2.10 Logos de agentes

| Agente | Arquivo | Cor | Uso |
|---|---|---|---|
| Claude Code | `Assets/AgentLogos/claude.pdf` (de `design/assets/brands/`) | `#D97757` | glifo oficial, nunca recolorido |
| Codex | `codex.pdf` | template (`textPrimary`) | |
| OpenCode | `opencode.pdf` | template | |
| Shell | lucide `SquareTerminal` | `textSecondary` | Terminal sem agente |
| Fallback | tile 12×12 r2 `secondary` com inicial 8/600 | — | CLI desconhecido |

Tamanhos: 12 (tab, a 70% se inativa), 13 (linha de agente), 14 (menus, palette, composer), 16 (Library, Settings › Agents), 20 (onboarding). Regra: logo oficial, sem sombra, sem glow, sem fundo colorido.

### 2.11 Tema claro (fora da v1, tokens registrados)

`canvas #ffffff`, `chrome #ffffff`, `sidebar #f5f5f5`, `sidebarSelected #eaeaea`, `border #e5e5e5`, `textSecondary #737373`, `destructive #e40014`, `success #15803d`, `warning #ca8a04`, `paneDivider #d4d4d8`, terminal "Builtin Tango Light". Cada token de §2 tem par claro em `colors.json`, mesmo sem uso na v1.

---

## 3. Tema do terminal

Fonte: config real do dono no Orca (`terminalThemeDark: "Ghostty Default Style Dark"`) e `src/shared/terminal-themes/defaults.ts:6-29`. Aplicado com `installColors(_:)` do SwiftTerm, mais `nativeBackgroundColor`, `nativeForegroundColor`, `caretColor` e `selectedTextBackgroundColor` (o app atual só aplica fundo e texto, `audit/07 #7`).

| Papel | Hex |
|---|---|
| Background | `#282c34` |
| Foreground | `#ffffff` |
| Cursor | `#ffffff`, bloco, piscando |
| Cursor text | `#282c34` |
| Selection background | `#5a7898` |
| Selection foreground | (mantém a cor da célula) |

| Índice | Normal | Hex | Índice | Bright | Hex |
|---|---|---|---|---|---|
| 0 | black | `#1d1f21` | 8 | bright black | `#666666` |
| 1 | red | `#cc6666` | 9 | bright red | `#d54e53` |
| 2 | green | `#b5bd68` | 10 | bright green | `#b9ca4a` |
| 3 | yellow | `#f0c674` | 11 | bright yellow | `#e7c547` |
| 4 | blue | `#81a2be` | 12 | bright blue | `#7aa6da` |
| 5 | magenta | `#b294bb` | 13 | bright magenta | `#c397d8` |
| 6 | cyan | `#8abeb7` | 14 | bright cyan | `#70c0b1` |
| 7 | white | `#c5c8c6` | 15 | bright white | `#eaeaea` |

Tipografia e comportamento padrão (Settings › Terminal permite mudar):

| Item | Padrão | Limites |
|---|---|---|
| Fonte | SF Mono | qualquer monoespaçada instalada |
| Tamanho | 14 | 8–32, ⌘= / ⌘- / ⌘0 por pane |
| Peso | 500 (Medium); bold 700 | |
| Line height | 1.0 | 1.0–1.6 |
| Padding interno | 4 pt nos quatro lados (inset nas constraints do host, não padding SwiftUI; `audit/07 correção 11`) | 0–16 |
| Opacidade de pane inativo | 0.8 (`DS4`) | 0.5–1.0 |
| Scrollback | 5 000 linhas | 1 000–50 000 |
| Option as Meta | `Auto` (decide pelo layout de teclado) | Auto / Left / Right / Always / Never |
| Copy on select | Off | |
| Trim trailing whitespace on copy | On | |
| OSC 52 write (apps escrevem no clipboard) | On, com toast `"<title>" copied to the clipboard` | Off |
| OSC 52 read | **Nunca responde** (T6, `audit/07 #1`). Não existe toggle. A view usa `TerminalView` com delegate próprio cujo `clipboardRead(source:)` devolve `nil`. **Proibido usar `LocalProcessTerminalView`** em qualquer lugar do app (ele devolve o pasteboard, `MacLocalTerminalView.swift:122`, e o PTY é do daemon); o lint de UI falha nesse símbolo (§15) | — |
| Bell | Sem som; marca a tab/sessão como não lida; notificação só se `Terminal bell` estiver ligado (padrão desligado, 03 §14.2) | |
| Link click | Hover sublinhado; ⌘-clique abre. Clique simples com popover de ações: later (na v1 só ⌘-clique) | |
| Renderer | Metal (`setUseMetal(true)`, T6) | Fallback CoreText em Diagnostics |

---

## 4. Tipografia

### 4.1 Famílias

| Família | Uso | Implementação |
|---|---|---|
| **Geist Variable** (SIL OFL 1.1) | Toda a UI | Arquivo upstream `Geist[wght].ttf` (releases de `github.com/vercel/geist-font`), com versão, URL e SHA-256 fixados no `bootstrap.sh` (F0-7); `OFL.txt` vai no bundle (`Resources/Fonts/`) e o About cita a licença. `ATSApplicationFontsPath = Fonts`. Um teste confere que `Font.custom("Geist", size:)` resolve para a família registrada; pesos intermediários (450) via `NSFontDescriptor` com `kCTFontVariationAttribute` eixo `wght`. Fallback do sistema: SF Pro |
| **SF Mono** | Terminal, título do header de pane, caminhos, branches no Source Control, nome de modelo, IDs, diffs, comandos em dialogs | `NSFont.monospacedSystemFont(ofSize:weight:)` |

Regras globais: tracking **+0,01 em** em toda a UI (13 pt → +0,13 pt); itens de nav e Search da sidebar **−0,025 em**; antialias padrão; números que mudam (tempo, contador, %, US$) usam `monospacedDigit()`.

### 4.2 Escala

| Token | Tamanho / peso / line height | Uso (exemplos reais) |
|---|---|---|
| `keycap` | 9 / 500 / 12 | Keycaps dentro do Search da sidebar; keycaps em tooltips usam `micro` |
| `micro` | 10 / 500 / 12 | Badges da sidebar (`Main`, `Detached`, `Container`), pílula `New`, contador `+3` |
| `microNumeric` | 10 / 400 / 12, tabular | Tempo relativo (`now`, `12m`, `3h`, `5d`), custo `$0.12` na linha filha |
| `monoMicro` | SF Mono 10 / 400 | Nome do modelo (`opus-4.5`), máx. 96 pt |
| `small` | 11 / 400 / 14 | Branch sob o nome, linhas de agente/filhas, ajuda de campo, rodapé da palette, labels uppercase do Settings (11/500, tracking 0,18 em, só na sidebar de Settings) |
| `label` | 12 / 500 / 16 | Labels de campo do composer e de dialogs, botões `xs`, status bar, tooltips |
| `sectionLabel` | 12 / 600 / 16 | "Projects", "Sessions", cabeçalhos de grupo da inbox e da palette |
| `tab` | 12 / 400 (ativa 500) / 16 | Título da tab |
| `menuItem` | 12 / 450 / 17 | Itens de menu, context menu, popover de lista |
| `body` | 13 / 400 / 20 | Nome da sessão lida (400 `fg/80`), itens do Settings, linhas de lista, texto de páginas |
| `bodyStrong` | 13 / 600 / 20 | Nome da sessão não lida, nome de projeto, títulos de linha na Library |
| `nav` | 13 / 500 / 18, tracking −0,025 em | Search e itens de nav da sidebar |
| `monoPane` | SF Mono 13 / 400 / 24 | Título do header de pane |
| `control` | 14 / 500 / 20 | Texto de botões `sm`/`default`/`lg` |
| `input` | 14 / 400 / 20 (13 dentro da sidebar e da palette compacta) | Inputs, textareas, selects |
| `dialogBody` | 14 / 400 / 20 | Descrição de dialog, texto de onboarding |
| `composerTitle` | 16 / 600 / 22 | Título do composer e de overlays médios |
| `dialogTitle` | 18 / 600 / 24 | Título de dialog padrão e de confirmação |
| `pageTitle` | 24 / 600 / 30 | Título de seção no Settings, título das páginas Library/Computers (Orca `text-2xl font-semibold`) |
| `display` | 28 / 600 / 34 | "Agent Box" na landing vazia (Orca usa 36/700 em caixa alta para a marca; aqui fica menor e sem caixa alta para não virar "hero") |
| `paletteInput` | 16 / 400 / 22 | Campo da palette ⌘J (input de 48 pt) |

Regras: nada abaixo de 9 pt; nada acima de 28; no máximo **dois pesos** por componente; texto longo trunca com `…` no fim (nomes) ou no meio (caminhos: `~/orca/…/arizona/sandperch`); a versão completa vai para o tooltip.

---

## 5. Espaçamento e medidas de layout

### 5.1 Escala (grade de 4 com meios-passos do Orca)

| Token | pt | Uso típico |
|---|---|---|
| `s0_5` | 2 | gap entre itens de nav, gap entre botões da titlebar, gap entre botões à direita da tab bar |
| `s1` | 4 | padding interno do terminal, gap ícone/texto em linhas de agente, margem esquerda do card |
| `s1_5` | 6 | padding horizontal da tab, gap entre linhas do card, padding vertical do card |
| `s2` | 8 | padding lateral da sidebar, padding de item de menu, gap de ícone + texto em nav |
| `s2_5` | 10 | padding esquerdo de linha de projeto, indentação por nível |
| `s3` | 12 | padding horizontal da status bar e de inputs, recuo de linha filha |
| `s4` | 16 | gap entre seções do composer/dialog, margem de toast, distância do ✕ ao canto do dialog |
| `s6` | 24 | padding de dialog |
| `s8` | 32 | padding lateral das páginas |
| `s10` | 40 | gap entre seções do Settings, padding superior das páginas |

### 5.2 Constantes de layout

| Constante | Valor | Origem |
|---|---|---|
| Altura da faixa de titlebar | 36 | Orca `TITLEBAR_CSS_CENTER = 18` |
| Centro dos semáforos | x = 16 (primeiro botão), y = 18 a partir do topo; espaçamento 20 (x = 16, 36, 56) | `createMainWindow.ts:102-135` |
| Pad reservado aos semáforos | 80 (0 em tela cheia) | `TitlebarLeftControls.tsx:45` |
| Tab row | 32 + faixa de arrasto de 4 acima = 36 | `TabGroupPanel.tsx` |
| Tab | 180 (220 com janela ≥ 1280), mín. 72 | `tab-width-rules.ts` |
| Header de pane | 24, sobreposto | |
| Status bar | 24 | |
| Sidebar esquerda | 280 (220–500) | DS5 |
| Painel direito | 310 padrão (220–480); preserva 320 no centro | config do dono |
| Activity bar do painel direito | 36, botões 36×36 | |
| Janela mínima | 760×480 | DS6 |
| Janela padrão (primeira abertura) | 1440×900, centralizada | — |
| Dialog padrão / confirmação | 512 / 448 de largura (máx. janela − 32) | `dialog.tsx` (`sm:max-w-lg` / `md`) |
| Composer | 560 (máx. janela − 32) | Orca 512 + campo de pasta; ver `03 §6`. 04 usa 560 |
| Palette ⌘J | 720 (máx. 96% da janela), a `min(10%, 64)` do topo | Orca 900 numa janela de 1440+; reduzido porque o Agent Box não lista arquivos |
| Toast | 360, a 16 da direita e 40 acima da status bar | |
| Menu | mín. 176 | |
| Tooltip | máx. 280 | |
| Settings | sidebar 240; conteúdo centralizado até 720 (encolhe com a janela; regras de largura mínima em `03 §1.5`), padding 40/32/96 | Orca 280/896; reduzido porque Settings é página dentro da janela e não janela própria (ver `03 §14`) |

---

## 6. Raios

| Token | pt | Uso |
|---|---|---|
| `rXS` | 2 | Logos PNG, keycap interno |
| `rSM` | 4 | Botões da titlebar, badges, linhas de agente/filhas, botão ✕ da tab, keycaps |
| `rMD` | 6 | Checkbox, thumbnails de computador, chips de filtro |
| `rControl` | 8 | Botões, inputs, selects, nav items, Search, itens de menu, botão "+" da tab bar, segmented |
| `rCard` | 10 | Card de sessão, dialog, itens da sidebar do Settings, card de inbox |
| `rMenu` | 11 | Menus, context menus, popovers, hover cards |
| `rLarge` | 14 | Palette ⌘J, onboarding |
| `rTile` | 18 | Tile do logo na landing |
| `rFull` | ∞ | Pílula `New`, switch, contador do nav, bolinhas |

Raio de foco = raio do controle + 3 (`DS9`).

---

## 7. Bordas e divisores

| Elemento | Especificação |
|---|---|
| Divisor sidebar ↔ centro | 1 pt `border`; sobre ele, área de resize de 12 pt centrada; a linha vira `ring/50` no hover e `ring` no drag |
| Divisor sob a faixa de titlebar da sidebar | `inset 0 -1 0 border` (desenhado dentro, não rouba altura) |
| Divisor sob a tab row | 1 pt `border` |
| Separador entre tabs | 1 pt `border` à direita de cada tab |
| Divisor de pane (split) | 3 pt `paneDivider #3f3f46` visível + 3 pt de hit de cada lado (9 pt) |
| Painel direito | `border-left` 1 pt; resize de 4 pt (hover `ring/20`) |
| Status bar | `border-top` 1 pt |
| Inputs | 1 pt `input` (`white/15`); inválido `destructive` |
| Dialog, menu, popover, toast | 1 pt `borderStrong` (`white/14`) |
| Card de sessão ativo | 1 pt `fg/18` |
| Tab ativa | barra inferior 2 pt `textPrimary` |
| Activity bar ativa | sublinhado 2 pt `textPrimary` de 25% a 75% da largura |
| Viewer: agente no controle | traço 1,5 pt `aiAccent` (borda viva, M-604) |
| Viewer: humano no controle | 2 pt `#fafafa` sólido |
| Viewer: pedido de ajuda | 2 pt `#f97316` respirando |

---

## 8. Sombras e materiais

| Token | Valor | Uso |
|---|---|---|
| `shadowDialog` | `0 24 72 rgba(0,0,0,.55)` + `inset 0 1 0 rgba(255,255,255,.06)` | Dialog, composer, onboarding |
| `shadowPalette` | `0 26 84 rgba(0,0,0,.32)` + inset igual | Palette ⌘J |
| `shadowMenu` | `0 16 34 rgba(0,0,0,.40)` + `inset 0 1 0 rgba(255,255,255,.04)` | Menus, popovers, hover cards |
| `shadowFloating` | `0 10 24 rgba(0,0,0,.18)` | Toasts, tooltip, find bar, tab arrastada |
| — | **nenhuma sombra** | Cards de sessão, linhas, tabs paradas, botões, painéis, terminal |

Materiais: menus `rgba(0,0,0,.72)` + `NSVisualEffectView(.menu, .behindWindow)`; dialogs `rgba(23,23,23,.96)` + blur do material; scrim `black/55`, sem blur na v1 (04 R8). Com **Reduce Transparency**: menus `#171717` sólido, dialogs `#171717` sólido, scrim `black/70`.

---

## 9. Ícones

Biblioteca: **lucide** (mesmo set do Orca, `lucide-react 0.577`). Os SVGs usados são exportados para `Assets.xcassets/Lucide/` como **PDF template** (`preserves-vector-representation`), um arquivo por traço: `stroke 2` (padrão), `stroke 1.75` (nav inativo), `stroke 2.25` (nav ativo e header de seção). Não misturar SF Symbols na UI de trabalho; SF Symbols só em `NSAlert`/`NSOpenPanel` do sistema.

Tamanhos: **16** (nav da sidebar, toggles da titlebar, activity bar, Search), **14** (ações de header, itens de menu, ações de hover, botão "+"), **12** (status, tab ✕, header de pane, badges com ícone, logos de agente na tab), **10** (dentro de badges, selos de modo), **20** (ícone de dialog de confirmação no tile de 40).

### 9.1 Lista de ícones usados

| Lucide | Onde | Tamanho |
|---|---|---|
| `PanelLeft` | Toggle da sidebar (titlebar) | 16 |
| `PanelRight` | Toggle do painel direito (tab bar) | 16 |
| `ArrowLeft` / `ArrowRight` | Voltar/avançar na faixa da titlebar | 12 |
| `Search` | Search da sidebar, palette, busca de páginas | 16 / 14 |
| `Inbox` | Nav "Inbox" | 16 |
| `Monitor` | Nav "Computers", tab de computador, linha filha de computador, selo Light | 16 / 12 / 10 |
| `Library` | Nav "Library" | 16 |
| `Settings` | Rodapé da sidebar (Settings) | 14 |
| `SlidersHorizontal` | Filtro/ordenação no header "Projects" | 14 |
| `FolderPlus` | Add Project | 14 |
| `Plus` | Nova sessão (header), "+" da tab bar, `New Clean Session` (header "Sessions") | 14 |
| `ChevronDown` / `ChevronRight` | Colapsar projeto/seção/grupo; Advanced do composer | 12 |
| `ChevronsUpDown` | Trigger de select/combobox | 14 |
| `Ellipsis` | Menu de projeto, menu de linha, overflow | 14 |
| `Star` | Fixar sessão (hover; v1.1) | 14 |
| `Archive` | Arquivar sessão (hover e menu) | 14 |
| `Trash2` | Delete (menus; ação destrutiva) | 14 |
| `Pencil` | Rename (menus) | 14 |
| `GitBranch` | Activity bar Source Control; branch em menus | 16 / 14 |
| `GitPullRequest` / `GitPullRequestDraft` / `GitPullRequestClosed` / `GitMerge` | Chip de PR; conflito | 12–13 |
| `ListChecks` | Activity bar Checks | 16 |
| `CircleCheck` / `CircleX` / `CircleDot` | Checks passando / falhando / pendentes; estado `done` | 12 |
| `Check` | Mark as Read / Mark All as Read (Inbox); item marcado em menus | 14 |
| `Crosshair` | Reveal Current Session (rodapé da sidebar) | 14 |
| `CircleDashed` | Estado `unknown` (e `stalled`, v1.1) | 10–12 |
| `Activity` | Estado `waitingOnSubagents` | 10–12 |
| `MessageCircleQuestion` | Estado `needsInput` | 10–12 |
| `AlertCircle` | Badge de erro, banner de erro | 10–14 |
| `TriangleAlert` | Aviso (toast, banner) | 14–16 |
| `Info` | Toast informativo | 16 |
| `Loader` | Toast de progresso (gira) | 16 |
| `X` | Fechar tab, pane, toast, overlay, find bar | 12 / 14 / 16 |
| `SquareSplitHorizontal` | Split Right (header de pane, menu) | 12 / 14 |
| `SquareSplitVertical` | Split Down | 12 / 14 |
| `Maximize2` / `Minimize2` | Expandir/recolher pane | 12 |
| `SquareTerminal` | Shell (tab, quick launch, composer "Blank terminal") | 12–14 |
| `RotateCw` | Restart / Try Again / Refresh | 14 |
| `Play` | Resume / Start | 14 |
| `Square` | Stop (com preenchimento, 12; nunca o quadrado branco sólido de 13 do app atual) | 12 |
| `History` | Activity bar Conversations; "Resume conversation" | 16 / 14 |
| `Layers` | Activity bar Context (o que está carregado na sessão) | 16 |
| `Box` | Selo `In Container` (v1.1), `BoxProvisioningGlyph` base | 10 / 16 |
| `Hourglass` | Computador na fila | 12 |
| `MousePointer2` | Take Over | 14 |
| `Hand` | Hand Back | 14 |
| `Keyboard` | Selo "Keyboard captured" | 12 |
| `ExternalLink` | Open in GitHub / navegador | 12 |
| `FolderOpen` | Reveal in Finder | 14 |
| `Code` | Open in Editor | 14 |
| `Copy` | Copy path / ID / command | 14 |
| `Pin` | Tab fixada (later; não renderiza na v1) | 12 |
| `CaseSensitive` / `Regex` / `ArrowUp` / `ArrowDown` | Find bar | 14 |
| `Bell` / `BellOff` | Settings › Notifications; "Mute" no menu da sessão | 14 |
| `Moon` | Sleep Session (v1.1) | 14 |
| `ShieldOff` | Indicador "permissions skipped" no header de pane | 12 |
| `Download` | Importar do Orca, baixar imagem | 14 |
| `KeyRound` | Accounts / Credentials | 14 |
| `Stethoscope` | Diagnostics | 14 |
| `Wrench` | Settings › Advanced | 14 |
| `Palette` | Settings › Appearance | 14 |
| `Command` | Settings › Shortcuts | 14 |
| `Github` | Settings › GitHub, ações de PR | 14 |
| `Container` | Settings › Computers | 14 |
| `Network` | Settings › Computers › Proxies (P13) | 14 |
| `TextCursorInput` | `Insert Skill or Agent…` (palette, Library, Context) | 14 |
| `Bot` | Settings › Agents, aba Agents da Library | 14 |
| `Sparkles` | **proibido** (§15) | — |

Ícones novos só entram nesta lista por revisão; o lint de assets falha se um PDF não listado for usado.

### 9.2 Ícone do app e marca

Fecha a lacuna R2 SEM #19 (`audit/01 AA10`).
- **App icon** (`AppIcon.appiconset`, mestre 1024×1024 em vetor): forma e grade padrão de ícone do macOS, fundo `#171717` sólido, glifo da marca (o mesmo do tile da landing, 03 §19) em `#fafafa`, sem gradiente, sem brilho, sem sombra própria além da do sistema. Todos os tamanhos exigidos pelo Xcode gerados do mestre.
- **Template da barra de menus**: o mesmo glifo simplificado, monocromático, 18×18 (03 §17).
- **Tile da landing**: 64×64, raio 18, fundo `secondary`, glifo 32 `textPrimary`.
- O glifo é desenhado uma vez, em `design/brand/agentbox-glyph.svg`, e todos os usos derivam dele. Entra com aprovação do dono, lado a lado com o ícone do Orca no Dock (P14).

---

## 10. Hit targets

| Regra | Valor |
|---|---|
| Alvo mínimo de clique | 24×24 (visual pode ser menor; a área de toque é expandida com `contentShape`) |
| Botões de ação no hover do card (pin, archive) | visual 20×20, hit 24×24 |
| Botão ✕ da tab | visual 16×16, hit 20×20 (não pode invadir o título) |
| Botões do header de pane | 24×24 |
| Botões da titlebar | ícone 16 + padding 4×8 = 32×24 |
| Itens de nav e linhas de lista | altura cheia da linha (32 / 28 / 24), largura total |
| Divisor de pane | 9 pt (3 visível + 3 + 3) |
| Resize da sidebar | 12 pt |
| Resize do painel direito | 4 pt visível, 8 pt de hit |
| Bolinha de estado com tooltip | hit 16×16 |
| Keycaps e badges | não clicáveis, exceto badges explicitamente marcados (`rename failed`, chip de PR) com hit ≥ 20 de altura |

---

## 11. Motion (somente referências)

Tokens de duração e curva vivem em `04-motion` (`Motion.swift` + `design/motion/tokens.json`). Este capítulo só associa componentes a momentos:

| Componente | Momento em `04-motion` |
|---|---|
| Hover de botão, linha, tab | M-802 / M-210 |
| Press | M-801 |
| Anel de foco | M-803 (3 pt, DS9) |
| Seleção do card de sessão | M-203 |
| Disclosure (projeto, Advanced, filhos) | M-206 (sidebar) / M-111 (formulário) |
| Overlay / dialog / composer / palette | M-101 / M-102 / M-103 / M-104 |
| Menus e popovers | M-105 (+ DS3) |
| Tooltip | M-106 (fade + 0,95, 150 ms; saída 100 ms), atraso DS1 |
| Hover card | M-107 |
| Toast | M-110 |
| Tab abrir / fechar / reordenar / trocar | M-301 / M-302 / M-303 / M-304 |
| Split / fechar pane / foco / localizar pane | M-306 / M-307 / M-308 / M-309 |
| Sidebar recolher | M-201 |
| Indicador de estado do agente | M-401…M-408 |
| Agente sendo lançado | M-501…M-506 |
| Computador provisionando / na fila | M-601 / M-602 |
| Agente usando o computador / handoff | M-604…M-611 |
| Processo encerrou | M-312; falhou ao iniciar M-313 |
| Spinner genérico | M-811 |
| Skeleton | M-812 |
| Settings trocar seção / páginas | M-109 |
| Inbox item novo / resolvido | M-705 |

Regra herdada: tudo respeita **Reduce Motion** (troca translação/escala por crossfade 150 ms; loops viram estado estático) e **nada anima o frame do terminal**.

---

## 12. Componentes base

Cada componente vive no alvo `AgentBoxDesignSystem` (`Sources/AgentBoxDesignSystem/Components/`, 08 §1.2). Todos recebem `accessibilityIdentifier` (T13) seguindo §17 e nenhum contém lógica de domínio (T3): recebem valores prontos e closures. Todo controle interativo dispara uma ação do registro (`ActionID`, 03 §24); nenhum `Button` tem closure solta (lint, §15).

### 12.1 Button

Orca: `components/ui/button.tsx`. Texto em Title Case (§18).

| Variante | Fundo | Texto | Hover | Pressed | Uso |
|---|---|---|---|---|---|
| `primary` | `#e5e5e5` | `#171717` | `#e5e5e5` @ 90% | @ 84% | Uma por superfície: "Create", "Start", "Resume" |
| `secondary` | `#262626` | `#fafafa` | `#262626` @ 80% | @ 70% | Ações alternativas: "Add Project" na landing |
| `outline` | `input/30` + borda `input` | `#fafafa` | `input/50` | `input/60` | "Cancel", "Open in Editor" |
| `ghost` | transparente | `textSecondary` (ícone) / `textPrimary` (texto) | `accent/50` | `accent/70` | Ações em linhas, headers, toolbar |
| `destructive` | `destructiveFill` | `#ffffff` | `destructive` @ 70% | @ 80% | "Delete Session", "Stop All Agents" |
| `link` | — | `#e5e5e5`, sublinhado no hover | — | — | "Learn more", "Open System Settings" |

| Tamanho | Altura | Padding H (com ícone) | Texto | Ícone | Raio |
|---|---|---|---|---|---|
| `xs` | 24 | 8 (6) | 12/500 | 12 | 8 |
| `sm` | 32 | 12 (10) | 14/500 | 14 | 8 |
| `default` | 36 | 16 (12) | 14/500 | 16 | 8 |
| `lg` | 40 | 24 (16) | 14/500 | 16 | 8 |

Estados: `disabled` = 50% e sem hit; `loading` = rótulo substituído por spinner 14 + rótulo de progresso ("Creating…"), largura mantida; foco = anel `DS9`. Botão com atalho mostra keycap à direita só em overlays ("Create ⌘↵").

SwiftUI: `struct DSButtonStyle: ButtonStyle` (variante, tamanho) + `.buttonStyle(.ds(.primary, .sm))`. `.keyboardShortcut(.defaultAction)` no primário de overlays, `.cancelAction` no Cancel (Esc). Pressed via `configuration.isPressed`; hover via `.onHover` + `@State`; foco via `@FocusState`/`isFocused` do `.focusable()`.

### 12.2 Icon button

| Variante | Caixa | Ícone | Raio | Hover | Uso |
|---|---|---|---|---|---|
| `titlebar` | 32×24 (padding 4×8) | 16 `textSecondary` | 4 | `accent` 100%, ícone `textPrimary` | Toggle sidebar, painel direito |
| `titlebarSmall` | 22×20 (padding 4×5) | 12 | 4 | idem; desabilitado 45% | ←/→ |
| `header` | 24×24 | 14 stroke 2,25 | 8 | `accent` | Ações do header "Projects", header de página |
| `row` | 20×20 (hit 24) | 14 | 4 | `accent`; destrutivo: ícone `destructive` | Archive no hover do card (Pin: v1.1); ações de projeto |
| `pane` | 24×24 | 12 | 4 | `white/10` | Header de pane |
| `tabClose` | 16×16 (hit 20) | 12 | 4 | `fg/10` | ✕ da tab |
| `toolbar` | 28×28 | 14 | 8 | `accent/50` | "+" da tab bar, ⋯, find bar |
| `activity` | 36×36 | 16 | 0 | ícone `textPrimary` | Activity bar do painel direito |

Todo icon button tem **tooltip** (§12.14) com nome + atalho e `accessibilityLabel` igual ao nome do tooltip.

### 12.3 Keycap

Caixa com altura 16 (14 em `keycap`), padding 0×4, raio 4, fundo `secondary`, texto `micro` `textSecondary`, glifos `⌘ ⇧ ⌥ ⌃ ↵ ⎋ ⌫ ↑ ↓`. Cada tecla é um keycap separado com gap 2 ("⌘" "⇧" "D"). Em tooltip e menus o atalho aparece só como texto `textTertiary` (sem caixa), como no Orca.

### 12.4 Badge

| Variante | Altura | Texto | Padding | Raio | Cores | Uso |
|---|---|---|---|---|---|---|
| `neutral` (sidebar) | 16 | 10/500 | 0×6 | 4 | texto `fg/70`, borda `fg/20`, fundo `fg/6` | `Main` (checkout principal), `Detached`, `Container` (v1.1) |
| `error` | 16 | 10/500 + `AlertCircle` 10 | 0×6 | 4 | texto `destructive`, borda `destructive/40`, fundo `destructive/10` | `Rename failed`, `Setup failed` |
| `warning` | 16 | 10/500 | 0×6 | 4 | texto `warning`, borda `warning/25`, fundo `warning/10` | `Conflicts`, `Token expiring` |
| `count` | 16 (mín. 16 de largura) | 10/600 tabular | 0×5 | full | fundo `#f97316`, texto `#171717` quando há AttentionItems de prioridade 1–2 (01 §5.12); senão fundo `secondary`, texto `textSecondary` | Contador no nav Inbox, na menu bar (M-701, M-810) |
| `pill` | 16 | 10/600 | 0×6 | full | fundo `primary`, texto `#171717` | `New` (recurso novo; raro) |
| `chip` (PR) | 18 | 11/500 tabular | 0×6 | 4 | fundo transparente, hover `accent/50`; ícone de PR 13 colorido + `#412` `textSecondary` + glifo de checks 12 | Chip de PR no card e no painel |
| `mono` | 16 | SF Mono 10 | 0×4 | 4 | fundo `accent`, texto `textSecondary` | Nome de modelo destacado, flag (`--dangerously-skip-permissions` em revisão) |

Badge nunca usa gradiente, sombra nem emoji. Máximo de **dois badges** por linha do card; o resto vai para o hover card.

### 12.5 AgentStateIndicator

Ver §2.6. `struct AgentStateIndicator: View { state, size }`. O spinner `working` é uma `CAShapeLayer` em `NSViewRepresentable` (04 M-401): `trim 0…0.75`, rotação em 12 passos/s, `beginTime` alinhado ao relógio global para todos girarem em fase, `preferredFrameRateRange` 12–24. Com Reduce Motion: círculo completo estático. Tooltip com atraso de **200 ms** contendo label + há quanto tempo ("Needs input · 4m"). `accessibilityLabel` = label; não é focável sozinho (o label entra no rótulo da linha que o contém).

### 12.6 AgentLogo

`struct AgentLogo: View { kind, size, dimmed }`. PDF vetorial; Claude mantém `#D97757`; demais em template. `dimmed` = 70% (tab inativa). O selo de modo (§2.8) vem **ao lado** do logo, com gap 2, e nunca sobreposto a ele.

### 12.7 Tab

Orca: `components/tab-bar/SortableTab.tsx`.

- Altura 32; largura 180/220 (mín. 72); padding 0×6; separador `border` à direita.
- Ativa: fundo `fg6` sobre `chrome`, texto `textPrimary` 12/500, **barra inferior 2 pt `textPrimary`**.
- Inativa: fundo `chrome`, texto `textSecondary` 12/400, hover texto `textPrimary` (token `hover`, 120 ms, M-802).
- Não lida: overlay `amber-500/10`.
- Conteúdo, gap 4: `AgentStateIndicator md` → `AgentLogo 12` (70% se inativa) ou `SquareTerminal` 12 / `Monitor` 12 (tab de computador) → selo de modo (opcional) → título truncado → ✕ (`tabClose`; sempre visível na ativa, só no hover nas inativas).
- Clique do meio fecha; duplo clique renomeia inline (regras em `03 §2.11`); arrastar reordena (ativação a 12 pt, M-303).
- Hover card após 500 ms: título completo, cwd, agente + modelo, estado, há quanto tempo, ID da conversa.

SwiftUI: `ScrollView(.horizontal, showsIndicators: false)` + `HStack(spacing: 0)`; indicador ativo com `matchedGeometryEffect` (M-301 / M-304); fade de 24 pt nas bordas com overflow e chevrons 20×24. Não usar `NSTabView` nem window tabbing.

### 12.8 List rows

| Tipo | Altura | Padding | Texto | Hover | Selecionado |
|---|---|---|---|---|---|
| Nav item (sidebar) | 32 | 8×6, gap 8 | `nav` `fg/60`, ícone 16 `fg/30` stroke 1,75 | `fg8` | fundo `sidebarSelected`, texto `textPrimary`, ícone stroke 2,25 `textPrimary` |
| Section header (Projects/Sessions) | 32 | 0×8 | `sectionLabel` `textSecondary/80` | — | — |
| Project row | 28 | esquerda 10 | ícone 16 (caixa r4, glifo 14) + `bodyStrong` | `fg5`; ações aparecem | — |
| Session card | variável (§12.9) | | | | |
| Agent row | 24 | 0×4, gap 4, r4 | `small` `textSecondary` | `hoverAgentRow` | pane focado: `sidebarSelected` |
| Child row | 24 | esquerda +12, conector em L | `small` | idem | idem |
| Menu item | 25 (lh 17 + 4×2) | 8×4, r8 | `menuItem` | `white/14` | check à esquerda (pl 28) |
| Settings nav item | 30 | 12×6, r10 | 13/500 | `fg5` | `panelSelected` |
| Generic list row (Library, Computers, inbox) | 32 (uma linha) / 48 (duas linhas) | 8×12 | `body` + `small` | `fg5` | `fg10` + borda `fg18` (como o card) |
| Table row (Computers, Network) | 28 | 0×12 | `body` / mono 12 | `fg5` | `fg10` |

Linhas **nunca mudam de altura** quando um dado assíncrono chega (`audit/03` problema da linha que "pula" 30→42): reservar a altura da linha 2 desde o início, com placeholder `fg/5` de 60×8 até o Git responder.

### 12.9 Session card

Orca: `worktree-card-*.tsx`. Detalhe de conteúdo em `03 §2.6`.

- Superfície: raio 10, borda transparente (ativo `fg18`), margem esquerda 4, margem direita 6, padding vertical 6 (8 quando só há título), transição 200 ms.
- Layout: coluna de status de 20 (+4) à esquerda; conteúdo em coluna com gap 6.
- Estados: hover `hoverRow`; ativo `fg10` + borda `fg18`; multi-seleção anel `ring/35`; arquivando/excluindo 50% + grayscale + pílula `Archiving…`/`Deleting…` com spinner; dormindo (v1.1) 60%.
- Sem sombra, sem gradiente, sem ícone grande, sem avatar.

SwiftUI: `SessionCardView(model: SessionCardModel)` onde `SessionCardModel` é `@Observable` **por card** (isolamento de invalidação, `audit/06 §3.4-4`).

### 12.10 Input / textarea / search

| Tipo | Altura | Padding | Fundo | Borda | Texto |
|---|---|---|---|---|---|
| `input` | 36 (32 em `sm`) | 12×4 | `input/30` | 1 `input` | `input` 14/400; placeholder `textQuaternary` |
| `textarea` (prompt do composer) | 88 mín., cresce até 240, depois rola | 12×8 | `input/30` | 1 `input` | 14/400, SF Mono **não** (prompt é prosa) |
| `sidebarSearch` | 32 | 8×6 | `fg5` (hover `fg8`) | nenhuma | `nav`; ícone `Search` 16 `fg/30`; keycaps `⌘` `J` (9 pt) só no hover/foco |
| `inlineRename` | altura da linha | 4×0 | `white/4` | 1 `ring/50` | mesma fonte do texto que substitui |
| `paletteInput` | 48 | 16×0 | transparente | borda inferior `border` | `paletteInput` 16/400 |
| `findField` | 26 | 8×0 | `input/30` | 1 `input` | 13/400 |

Search da sidebar: digitar no campo **filtra a sidebar** (como o Orca); o keycap exibido no hover é o da palette (**`⌘J`**) e clicar nele abre a palette. Atalho para focar o campo: `⌘F` quando o foco está na sidebar (fora dela, `⌘F` é a busca do terminal).

Estados: foco = borda `ring` + anel `DS9`; inválido = borda `destructive` + anel `destructive/40` + mensagem `small` `destructive` abaixo (uma linha, ícone `AlertCircle` 12); desabilitado 50%; leitura (`readOnly`) sem borda, fundo `fg5`.

Esc num campo de busca com texto limpa; sem texto, devolve foco ao terminal. Enter durante composição IME é ignorado.

SwiftUI: `TextField`/`TextEditor` com `.textFieldStyle(.plain)` dentro de `DSFieldChrome`. O `TextEditor` precisa de `NSTextView` com `textContainerInset` 12×8 (via `NSViewRepresentable` `PromptEditor`) para controlar padding, ⌘↵ e IME.

### 12.11 Select / combobox

Trigger igual ao `input` (36, raio 8), conteúdo: ícone 14 (opcional) + label 14 + `ChevronsUpDown` 14 `textSecondary` à direita. Abre um **popover** (`rMenu`, `menuMaterial`, `shadowMenu`) com:
- campo de busca no topo ("Search agents…", 32 de altura) quando a lista tem mais de 7 itens;
- lista de itens `menuItem` com ícone 14, label, detalhe `textTertiary` à direita, check no selecionado;
- itens fixos no fim separados por divisor ("Add a New Project…", "Manage Agents…"); cada um é uma ação do registro (03 §24).
Teclado: ↑↓ navega, ↵ escolhe, Esc fecha, digitar filtra (type-ahead). Mesmo com poucos itens usa-se este componente, e não `NSPopUpButton`, para não haver dois visuais de select. Implementação: `DSCombobox` = `Button` + `.popover(arrowEdge: .bottom)` com conteúdo SwiftUI e `NSPopover.appearance = darkAqua`; o popover sem seta (`NSPopover` com `.behavior = .transient` e seta escondida via subclasse) ou `NSPanel` ancorado.

### 12.12 Segmented control

Orca: `toggle-group` com variante `segmented`. Altura 28 (24 em `xs`), fundo `secondary`, raio 8, padding 2; segmento: 12/500, padding 0×10, raio 6; ativo fundo `accent` + texto `textPrimary`; inativo texto `textSecondary`, hover `fg/6`. Indicador do ativo desliza (`snappy`). Indicador do ativo: M-113. Uso: "Where" no composer (`New Worktree · Existing Worktree · Main Checkout`; sem projeto: `New Folder · Choose Folder…`), filtros da Network tab, abas internas da Library. Teclado: ←/→ movem a seleção quando focado. SwiftUI: componente próprio (`DSSegmented`), não `Picker(.segmented)` (visual do sistema).

### 12.13 Toggle (switch) e checkbox

- **Switch** (Orca `switch.tsx`): trilho 36×20, raio full, padding 2; off `textSecondary/30`, on `textPrimary`; botão 14×14 `canvas` com `shadow-sm`, desloca 16 (M-804). Compacto: trilho 24×14, botão 10. Rótulo à esquerda em `body`, descrição `small` `textSecondary` abaixo (máx. 1 linha, `audit/07 #54`). Clique no rótulo também alterna.
- **Checkbox**: 14×14, raio 4, borda `input`, marcado fundo `textPrimary` com check `#171717` 10. Uso: listas de seleção (Resume agents, Import from Orca), "Don't ask again".
SwiftUI: `Toggle` com `ToggleStyle` próprio (`DSSwitchStyle`, `DSCheckboxStyle`).

### 12.14 Tooltip

- Fundo **`textPrimary` (#fafafa)**, texto **`canvas` (#0a0a0a)**: tooltip invertido do Orca. 12/400, padding 6×12 (ou 4×8 em uma palavra), raio 8, máx. 280, seta 10 (rotacionada 45°, raio 2), `shadowFloating`.
- Conteúdo: nome da ação + atalho em `textQuaternary` invertido (`#0a0a0a` @ 55%) separado por 8 pt. Ex.: `Split Right   ⌘D`.
- **Atrasos (DS1):** 400 ms padrão; 500 ms em tabs; 1000 ms no ✕ da tab; 200 ms em bolinhas de estado. Se outro tooltip esteve visível nos últimos 300 ms, o próximo abre sem atraso. Some ao clicar, ao rolar e ao digitar.
- Animação: M-106 (fade + zoom 0,95 + slide 8 pt do lado, 150 ms; saída 100 ms).
- Implementação: `TooltipController` (singleton por janela) com um `NSPanel` não-ativável (`.nonactivatingPanel`, `ignoresMouseEvents = true`, `level = .floating`) hospedando SwiftUI; modificador `.dsTooltip("Split Right", shortcut: .splitRight)` que registra a área via `NSTrackingArea`. `.help()` só em controles de formulário (Settings).

### 12.15 Menu e context menu

- Visual (Orca `dropdown-menu.tsx`): mín. 176, raio 11, padding 4, `menuMaterial` + borda `white/14` + `shadowMenu`; item 12/450 lh 17, padding 8×4, raio 8, foco/hover `white/14`; ícone 14 `textSecondary` à esquerda; atalho à direita em `textTertiary`; separador 1 pt `border/60` com margem 3; cabeçalho de grupo 11/500 `textSecondary` (ex.: "Session"); destrutivo em `destructive` com hover `destructive/20`; desabilitado 50% com tooltip do motivo.
- **Context menus** (clique direito em card, linha, tab, terminal, viewer): **`NSMenu` nativo** (`audit/07 #3`, `audit/04 §7`): o comportamento nativo (teclado, VoiceOver, submenus, tipo-ahead) vale mais que o pixel e já é escuro e translúcido com `darkAqua`. Ícones via `NSMenuItem.image` com os PDFs lucide (template, 14). SwiftUI `.contextMenu` gera `NSMenu` e é aceito para cards e linhas; o terminal usa `menu(for:)` no `NSView` hospedeiro.
- **Dropdowns ricos** (filtro do header "Projects", "+" da tab bar, menus com busca, combobox): popover SwiftUI com o visual acima (`DSMenuPanel`), aberto por clique, fechado por Esc/clique fora; navegação ↑↓ ↵.
- Itens técnicos (Copy Terminal ID, Refresh Git, Show Hook Log, Show Launch Details) só aparecem com **⌥ pressionado** (`NSMenuItem.isAlternate` / `allowsKeyEquivalentWhenHidden`) ou com `Show technical details in menus` ligado, padrão do Orca (`audit/07 #30`). Não existe "Reauthorize Folder…": o app não usa security-scoped bookmarks (AR-533).
- Context menu e dropdown só listam itens com ação definida na tabela de ações (03 §24); item de versão futura não é renderizado.

### 12.16 Popover e hover card

- Popover: raio 11, `menuMaterial` (ou `chrome` sólido quando contém formulário), borda `white/14`, `shadowMenu`, padding 12, sem seta (seta só em tooltip). Abre em 150 ms (DS3, M-105).
- Hover card (card de sessão, tab, chip de PR, thumbnail de computador): largura 280–320, abre após **250 ms** de hover (tab: 500 ms; instantâneo se outro hover card estava aberto), fecha **120 ms** depois de sair (`audit/07 #36`, M-107). Não rouba foco. Conteúdo em linhas `small`/`body` com rótulo `textSecondary` à esquerda (`State`, `Branch`, `PR`, `Checks`, `Computers`).
- Implementação: `NSPopover` com `behavior = .semitransient` para popovers clicáveis; `NSPanel` não-ativável para hover cards.

### 12.17 Overlay / dialog (`OverlayPanelHost`)

Todos os modais (composer, palette, dialogs, onboarding, confirmações, "Add Project", "Resume Agents", **o aviso do ⌘Q**) são **overlays dentro da janela** (T5), nunca `.sheet`, `NSAlert` (exceto erro fatal de inicialização, §12.18) ou janela própria.

Visual:
- Scrim `black/55`, sem blur na v1 (04 R8; Reduce Transparency: `black/70`), cobrindo a janela inteira, inclusive sidebar e titlebar (os semáforos continuam clicáveis).
- Cartão `overlayCard`, borda `white/14`, raio 10 (palette/onboarding 14), `shadowDialog`, padding 24, gap 16.
- Título `dialogTitle` 18/600 (composer 16/600); descrição `dialogBody` `textSecondary`, uma ou duas frases.
- Botão ✕ 16×16 a 16 do canto superior direito (opcional; Esc sempre funciona).
- Footer alinhado à direita, gap 8: `outline` "Cancel" + `primary`/`destructive`. Rodapé esquerdo opcional (checkbox "Don't ask again", toggle "Create more").
- Largura máxima: janela − 32; altura máxima: janela − 96; conteúdo rola por dentro com header e footer fixos. Nunca rolagem horizontal.
- Animação M-101 (200 ms, fade + zoom 0,95) e M-102 (saída 150 ms); confirmação M-103.

Contrato de foco (`audit/07 #23`, P0):
1. Ao abrir: guarda o first responder atual (normalmente o terminal), chama `window.makeFirstResponder` no campo inicial da tela (no composer, o Prompt, AC-301; nos demais, o primeiro campo).
2. Tab/⇧Tab circulam só dentro do overlay.
3. Esc fecha (ou volta um passo em fluxos com passos). ⌘↵ submete. ↵ submete quando o foco não está num `textarea`.
4. Ao fechar: devolve o first responder guardado (o terminal volta a receber teclas).
5. `.accessibilityAddTraits(.isModal)` no cartão; conteúdo de trás `accessibilityHidden(true)`.
6. Overlays não empilham, salvo um nível: um overlay pode abrir **um** sub-overlay (ex.: composer → "Add a project"), que volta ao anterior preservando o que foi digitado.
7. Clique no scrim fecha **só** overlays sem dados digitados; com dados, ignora o clique (evita perder prompt).

SwiftUI: `OverlayPanelHost` na raiz da janela (`ZStack` acima do `NSSplitViewController` hospedado), estado em `OverlayRouter` (`@Observable`, um `enum Overlay`). Teclado via `.onKeyPress(.escape)` e `.keyboardShortcut`. O terminal precisa de um bloqueio explícito: enquanto `OverlayRouter.current != nil`, o `TerminalHostView.acceptsFirstResponder` retorna `false`.

### 12.18 Confirmation dialog

Overlay 448 de largura (Orca `confirmation-dialog.tsx`):
- Tile opcional 40×40, raio 10, fundo `destructive/10` (destrutivo) ou `secondary`, ícone 20.
- Título 18/600 em forma de pergunta ("Close this terminal?"), descrição curta com a consequência concreta ("Claude is still working. Closing ends the process.").
- Checkbox opcional "Don't ask again" (quando marcado e confirmado, toast `You can change this in Settings › General.` com ação `Open Settings`; `Reset "Don't ask again" choices` em Settings › General desfaz).
- Botões: `outline` "Cancel" (Esc) + `destructive`/`primary` com verbo ("Close Terminal", "Delete Session"). Nunca "OK"/"Yes".
- Exceção nativa: só erros fatais de inicialização (antes de existir janela) usam `NSAlert`, com `NSApp.appearance = darkAqua`. **O ⌘Q com agentes vivos é overlay (03 §16.10), nunca `NSAlert`**: se nenhuma janela estiver aberta (quit pelo Dock ou pela barra de menus), o app abre a janela principal e mostra o overlay nela.

### 12.19 Toast

Orca: sonner. Canto inferior direito, 360 de largura, 16 da direita e 40 acima da status bar, empilhados com gap 8 (máx. 3 visíveis; o resto colapsa em "+2 more").
- Cartão `chrome`, borda `white/14`, raio 10, `shadowFloating`, padding 12, gap 8.
- Linha: ícone 16 (`CircleCheck` success, `Info`, `TriangleAlert` warning, `AlertCircle` error em `destructive`, `Loader` progresso) + título 13/500 + descrição `small` `textSecondary` (opcional) + ação `ghost xs` à direita ("Undo", "Copy Details", "Open") + ✕ 14 no hover.
- Duração: 4 s informativo; **8 s com ação Undo**; **60 s erro** (`audit/07 #51`); progresso fica até terminar. Hover pausa o tempo.
- Animação M-110. VoiceOver: anuncia título (polite); erros como assertive.
SwiftUI: `ToastCenter` (`@Observable`) + `ToastStack` em overlay na raiz, `allowsHitTesting` só nos cartões.

### 12.20 Banner (inline)

Faixa dentro de um pane, painel ou página, para estado persistente que pede ação (nunca para sucesso):
- Altura 32 (uma linha), padding 0×12, fundo `warning/10` ou `destructive/10` ou `fg5` (neutro), borda inferior com a cor a 25%, ícone 14, texto 12/500, ação `ghost xs` à direita, ✕ quando dispensável.
- Exemplos: `Claude hit its 5-hour limit. Resets at 2:20 PM.` [Continue in Codex] (v1.1); `Docker isn't running.` [Start Docker]; `Reconnecting to the background service…`.

### 12.21 Empty state

Orca: `EmptyState.tsx`. Sem ilustração, sem ícone grande, sem emoji.
- Coluna centralizada, largura máx. 320; texto `small` 11 `textSecondary` (em listas) ou `body` 13 (em páginas); uma ação `outline sm` ou `ghost xs` opcional.
- Exemplos: `No sessions match "phx".` [Clear Search]; `No computers yet. Agents create them when they need a browser.`
- A única tela vazia com marca é a landing (`03 §19`): tile 64 do logo, raio 18. Sem desenho de traço nem loop (M-901 só faz fade); nenhum outro estado vazio tem marca.

### 12.22 Progresso

| Componente | Visual | Uso |
|---|---|---|
| `AgentWorkingSpinner` | §12.5 | Somente estado `working` de agente |
| `Spinner` | Arco 270°, traço 1,5 (sm 10–12) ou 2 (16), cor `textSecondary`, mesmo loop do spinner de agente (1 volta/s em 12 passos, fase global; 04 M-811), **aparece só após 150 ms** | Operações do app (criando worktree, conectando) |
| `ProgressBar` | Trilho 4 de altura `secondary`, raio full; preenchimento `textPrimary`; determinado anima largura 300 ms; indeterminado = segmento de 30% deslizando 1,2 s (M-813) | Download de imagem, build da imagem do computador, importação do Orca |
| `PhaseList` | Lista vertical de etapas reais: ícone 12 (spinner / `CircleCheck` emerald / `AlertCircle` destructive / círculo vazio `textQuaternary`) + label `small`, tempo à direita `microNumeric` | Ignição do agente (M-503), linha pendente da sessão, onboarding, preparação de computador ou container |
| `Skeleton` | Retângulos `fg5` raio 4 com brilho varrendo (M-812), após 150 ms | Listas que carregam (Conversations, Checks, Library) |
| `BoxProvisioningGlyph` | M-601 | Computador ou container provisionando |

Regra: **nunca progresso falso**. Barra determinada só com dado real (bytes da imagem, etapas concluídas). Sem dado, `Spinner` + texto da etapa.

### 12.23 Divisores e alças de resize

`SplitDivider` (pane): 3 pt `paneDivider`, hit 9, cursor `resizeLeftRight`/`resizeUpDown` via `addCursorRect` (nunca `NSCursor.push/pop`, `audit/03 bug 16`); duplo clique iguala os dois lados (M-202). `SidebarResizeHandle`: hit 12, linha 1 pt `border` → `ring/50` hover → `ring` drag; duplo clique volta a 280. Arrasto é **imediato** e não salva estado a cada quadro (`audit/07 #55`: debounce 300 ms + `onEnded`); resize do PTY no máximo 1 por quadro e o final ao soltar (04 M-202).

### 12.24 Scrollbar

`NSScrollView.scrollerStyle = .overlay`, knob 8 pt, invisível até hover da área; `textSecondary` @ 28% (48% no hover do knob). Na sidebar e nas listas. O terminal usa o scroller do SwiftTerm com o mesmo estilo.

### 12.25 ComputerThumbnail

Miniatura do frame do computador: proporção 16:10, raio 6, borda `border`; rodapé de 20 com `Monitor` 10 + nome (`small`) + estado (§2.8) + uso do proxy `microNumeric` (só quando o provedor informa, P13). Borda viva/humano/ajuda reduzidas a 1,5 pt. Atualiza no máx. 1 fps quando visível (CS-403); congela fora da tela (R6.3). Hover amplia a miniatura (M-612) e mostra URL atual e última nota do diário.

---

## 13. Focus ring e navegação por teclado

- **Anel:** 3 pt `ring` (`#737373`) a 50% (`DS9`), por fora do controle, raio do controle + 3, aparece só com navegação por teclado (`focus-visible`: SwiftUI `.focusEffectDisabled()` no padrão do sistema + anel próprio quando `@FocusState` e o último evento foi teclado). Inputs: borda `ring` + anel.
- **Linhas e cards** não ganham anel quando selecionados por clique; com teclado, a linha focada ganha anel interno 2 pt `ring/50` (inset, para não sair da sidebar).
- **Terminal focado:** sem anel; o pane ativo é marcado pela opacidade (inativos 0,8) e pelo header (`paneTitle` sobe para `white/70`).
- **Full Keyboard Access** (`NSApp.isFullKeyboardAccessEnabled`): todos os controles entram no ciclo de Tab.

Regiões e teclas:

| Região | Entrar | Dentro |
|---|---|---|
| Lista de sessões | `⇧⌘0` | ↑/↓ move entre cards e linhas de agente; →/← expande/recolhe projeto, card ou filhos; ↵ foca o terminal do item; Space abre o hover card; ⌥⌘R renomeia; ⇧⌘⌫ exclui (confirma); Esc volta ao terminal |
| Tab bar | `⌃⇥`, `⇧⌘]`/`⇧⌘[`, `⌃1…9` | ←/→ quando a tab bar tem foco (via Full Keyboard Access); ⌘R renomeia |
| Panes | `⌘]`/`⌘[` (⌥⌘←/→ é Back/Forward, 03 §21) | — |
| Painel direito | `⌘L` (abre e foca), `⇧⌘G`, `⇧⌘C`, `⇧⌘H` | Tab percorre; Esc devolve ao terminal |
| Overlays | automático | §12.17 |
| Menus | nativo | ↑↓ ↵ Esc, type-ahead |

---

## 14. Acessibilidade

### 14.1 VoiceOver: rótulos

Padrão do rótulo composto: **`<nome>, <tipo>, <estado>, <detalhe>`**. O estado vem do mesmo `agentStateLabel` da UI.

| Elemento | `accessibilityLabel` | `accessibilityValue` / traits |
|---|---|---|
| Card de sessão | `"sandperch, session, needs input, branch gabrielgreco1/sandperch, pull request 412 checks failing"` | `.isSelected` quando ativo; `.isButton`; hint `"Opens the session"` |
| Linha de agente | `"Codex, needs input, 'Which table should I use?', 4 minutes ago"` | `.isSelected` se pane focado |
| Linha filha (subagente) | `"phoenix-az, subagent of Claude, working, on this Mac"` | |
| Linha filha (computador) | `"Computer phoenix-az, Claude is using it"` | |
| Linha pendente | `"Creating session fix-arcgis-pagination, fetching"` | `.updatesFrequently` |
| Tab | `"Claude Code, working, tab 2 of 4"` | `.isSelected` |
| Header de pane | `"Pane: Claude Code in sandperch"` | |
| Terminal | `"Terminal, Claude Code"` (SwiftTerm expõe o buffer como `.textArea`) | |
| Indicador de estado isolado | não é elemento próprio (entra no rótulo do pai) | |
| Icon buttons | nome do tooltip (`"Split Right"`) | o atalho vai em `accessibilityCustomContent("Shortcut", "Command D")`, não no hint |
| Chip de PR | `"Pull request 412, open, 2 checks failing"` | `.isLink` |
| Computer viewer | `"Computer phoenix-az, you're in control"` | |
| Status bar segmentos | `"Claude usage, 62 percent of 5-hour limit, resets 2:20 PM"` | |
| Badge de contagem | `"3 need you"` (atenção agregada) | |
| Toast | título + descrição | anúncio automático |

### 14.2 Anúncios (`AccessibilityNotification.Announcement`)

Só estes eventos, com cooldown de **5 s por terminal** (`audit/07 #26`), nunca a saída do terminal:
- agente passou para `needsInput`: `"<Agent> in <session> needs input"`;
- agente terminou (`done`) quando a sessão não está visível: `"<Agent> in <session> finished"`;
- agente falhou / processo saiu com erro: `"<Agent> in <session> failed"`;
- controle do computador mudou: `"You're in control of <computer>"` / `"Control returned to <agent>"`;
- pedido de ajuda de computador: `"<computer> needs you: CAPTCHA"`.

### 14.3 Outros ajustes

- **Reduce Motion:** ver §11 e `04-motion` §5.
- **Reduce Transparency:** materiais sólidos (§8).
- **Increase Contrast** (`accessibilityDisplayShouldIncreaseContrast`): `border` sobe para `white/16`, `textSecondary` para `#c4c4c4`, `navText` para `fg/80`, `paneDivider` para `#71717a`, bolinha `idle` para 70%.
- **Contraste mínimo:** texto primário e secundário ≥ 4,5:1 sobre a superfície (verificado: `#a1a1a1` sobre `#2a2a2a` ≈ 4,7:1; sobre `#171717` ≈ 6,9:1). `fg/60` sobre `#2a2a2a` (nav) ≈ 4,6:1. Texto `textTertiary` (≈ 3,1:1) só para informação redundante (tempo relativo, contadores com equivalente no hover/VoiceOver).
- **Cor nunca é o único sinal:** todo estado tem glifo diferente (spinner, `?`, check, ponto, tracejado) e label no tooltip/VoiceOver; PR e checks têm ícone próprio por estado.
- **Tamanho de texto:** zoom da UI (`uiZoomLevel`, −3 a +5 em passos de 0,5) é **later**: na v1, ⌘= / ⌘- / ⌘0 fora do terminal ficam desabilitados com o motivo `Interface zoom isn't available yet.` (PP-1). O terminal tem zoom próprio desde a v1.
- **Teclado:** todo recurso alcançável sem mouse (§13); o registro de atalhos (`KeyBindingRegistry`, com escopo explícito, 03 §21) e o registro de ações (03 §24) alimentam menus, tooltips e palette, então nenhuma ação existe só como gesto.

---

## 15. Regras "anti-AI-generated"

A UI anterior foi julgada "ridícula, cara de AI generated". Estas regras são verificadas em revisão visual e, onde der, por lint (`scripts/lint-ui.sh` procura padrões proibidos no código).

**Nunca:**
1. Gradientes em superfícies, botões, textos ou bordas. (Única exceção: a borda viva cônica do viewer, M-604, que é estado e não decoração, e o brilho do skeleton, M-812.)
2. Glow, neon, `shadow` colorida, halo permanente. Sombra só em elementos flutuantes (§8).
3. Emojis na UI (inclusive ✨🚀🤖✅⚡). Status é glifo lucide ou bolinha.
4. Ícone `Sparkles`/"magic" para indicar IA. Agente é identificado pelo logo oficial.
5. Cards grandes com padding de 20+ pt, raio de 14+ pt ou sombra em listas de trabalho; grades de cards na Library; dashboards de "métricas" na tela inicial.
6. Títulos com subtítulo explicativo em toda tela e todo overlay ("Create a new session — Start working with your favorite agent in seconds"). Um título curto basta; descrição só quando muda a decisão.
7. Labels em CAIXA ALTA espaçada como decoração na área de trabalho. (Permitido só na sidebar de Settings, 11/500, como no Orca.)
8. Texto de marketing ou de "boas-vindas" dentro do app ("Supercharge your workflow", "Let's get started!", "Unleash"). Microcopy é instrução.
9. Cor como enfeite: avatares de letra coloridos, chips de cor aleatória, ícones dentro de quadrados coloridos, acento azul/roxo em botões.
10. Mais de um botão primário por superfície; botões primários em cor saturada.
11. Ilustrações, mascotes, blobs, ícones gigantes em estados vazios; loops decorativos; "atividade" falsa (cursor animado, checkmarks em loop, `audit/06 §1.2 D7/D13`, inventário).
12. Barras de progresso falsas e spinners infinitos sem texto de etapa.
13. Mostrar dados de depuração como informação principal: PID, UUID, SHA-256, caminhos de hook. Ficam em "Copy ID" (menu com ⌥) ou em Diagnostics.
14. Parágrafos de aviso em `caption` (`audit/07 #54`). Uma linha de ajuda por controle; o resto em "Learn more".
15. Tamanhos ad-hoc e valores fora das escalas de §4–§8 e da tabela de constantes de §5.2. Todo número vem de token: 720 (palette, Settings) e 760×480 (janela mínima) são constantes de §5.2 e valem; um 680 ou 690 solto no código, não.
16. Bounce/overshoot perceptível, animação implícita na raiz (`.animation(value:)` em ancestral), `easeInOut` genérico em tudo (`audit/06 §1.2`).
17. Controles do sistema com visual cru dentro do app: `Form(.grouped)`, `Picker(.segmented)` do sistema, `TextEditor` com `.border`, `List(.sidebar)` com seleção azul.
18. Nome do app repetido (título da janela + header da sidebar). O nome aparece **uma vez**, na faixa da titlebar, como no Orca.
19. Pontuação exclamativa, reticências decorativas ou "…" em botões que não abrem algo.
20. Controles de fatia ou versão futura desenhados na tela (desabilitados ou "coming soon"). Controle de fatia futura **não é renderizado** (feature flag por fatia, R3 §5.6); controle da fatia atual que não pode agir agora fica desabilitado com tooltip do motivo.
21. Controle sem ação: todo `Button`, `.onTapGesture`, `NSButton` e item de menu chama `ActionRegistry.perform(<ActionID>)` (03 §24).

**Sempre:**
- Testar cada tela lado a lado com o Orca em screenshot do mesmo tamanho, com a **checklist de fidelidade visual de `03 §23`** (derivada de `audit/04 §8`), e só fechar a tarefa com o OK explícito do dono sobre o lado a lado (P14).
- Perguntar "o Orca faria isso?". Se a resposta é não e não há motivo de produto escrito, não fazer.

**Lint de UI** (`scripts/lint-ui.sh`, roda no CI e falha o build). Padrões proibidos fora dos arquivos de token e de componente indicados:
- `.sheet(`, `List(`, `Form(`, `.pickerStyle(.segmented)`, `TextEditor` (fora de `PromptEditor`), `NSAlert` (fora do erro fatal de inicialização), `NSPopUpButton`;
- `.animation(` sem `value:`; `Color(red:`, `Color(hex:`, `NSColor(red:` fora de `DS.Color`; `Font.system(size:` fora de `DS.Font`; literal numérico em `.padding(` e `.frame(` fora de `DS.Space`/constantes de §5.2;
- `LocalProcessTerminalView`, `TerminalFindBarView`, `performFindPanelAction`;
- emojis em literais de string, `Sparkles`, PDFs de ícone fora da lista de §9.1;
- `Button(` / `.onTapGesture` / `NSButton` cuja ação não seja `ActionRegistry.perform(`.
Cada padrão é regex com limite de palavra e tem um caso de teste do próprio lint (sem falso positivo em `ProcessInfo`, `Task.sleep`, etc.). Toda string de UI está no String Catalog (AC-T04).

---

## 16. Mapeamento de implementação

| Componente | Tipo Swift | Base | Observação |
|---|---|---|---|
| Janela | `MainWindowController` (`NSWindowController`) | AppKit | `fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`, sem `NSToolbar`, reposiciona semáforos (`03 §1`) |
| Layout de 3 colunas | `MainSplitViewController` | `NSSplitViewController` | Sidebar `sidebarWithViewController` (sem material), centro, painel direito (`inspectorWithViewController`) |
| Faixa de titlebar | `TitlebarStripView` | `NSView` + `NSHostingView` | `mouseDownCanMoveWindow`; duplo clique → `performZoom` respeitando `AppleActionOnDoubleClick` |
| Sidebar | `SidebarView` | SwiftUI `ScrollView` + `LazyVStack(pinnedViews: .sectionHeaders)` | Não usar `List` |
| Session card | `SessionCardView` | SwiftUI | `@Observable` por card |
| Tab bar | `TabBarView` | SwiftUI | `matchedGeometryEffect`, `.draggable`/`.dropDestination` |
| Pane tree | `PaneTreeView` | AppKit (`PaneSplitView: NSSplitView` aninhado) | Divisor 3 pt desenhado; um resize do PTY por transição animada, no início (04 R2; ao fechar painel, no fim); no arrasto, no máximo 1 por quadro mais o final (M-202) |
| Terminal | `TerminalHostView` | `NSView` + SwiftTerm `TerminalView` (Metal), **nunca `LocalProcessTerminalView`** | Inset 4; `menu(for:)`; drag de arquivos; delegate próprio com `clipboardRead → nil` (nunca responde OSC 52 de leitura); bytes vêm do daemon pelo `PTYClient`; `acceptsFirstResponder` bloqueado sob overlay |
| Header de pane | `PaneHeaderView` | SwiftUI em `NSHostingView` sobreposto | Botões revelados no hover (120 ms) |
| Find bar | `TerminalFindBar` | SwiftUI flutuante | Usa a busca pública do SwiftTerm (`findNext`/`findPrevious`, `searchMatchSummary`, `clearSearch`, `SearchOptions`). Nunca a find bar embutida (`TerminalFindBarView`, privada e com visual de sistema) |
| Status bar | `StatusBarView` | SwiftUI | 24 pt |
| Painel direito | `RightPanelView` | SwiftUI | Activity bar própria |
| Overlay host | `OverlayPanelHost` + `OverlayRouter` | SwiftUI `ZStack` | Contrato de foco §12.17 |
| Palette | `CommandPaletteView` | SwiftUI no `OverlayPanelHost` | Ancorada a 64 do topo |
| Button / IconButton | `DSButtonStyle`, `DSIconButton` | SwiftUI `ButtonStyle` | |
| Badge / Keycap | `DSBadge`, `Keycap` | SwiftUI | |
| Input / textarea | `DSTextField`, `PromptEditor` | SwiftUI / `NSTextView` | |
| Combobox | `DSCombobox` | SwiftUI + `NSPopover` | |
| Segmented | `DSSegmented` | SwiftUI | |
| Switch / checkbox | `DSSwitchStyle`, `DSCheckboxStyle` | SwiftUI `ToggleStyle` | |
| Tooltip | `TooltipController` | `NSPanel` não-ativável | Atrasos DS1 |
| Context menu | `NSMenu` (via `.contextMenu` ou `menu(for:)`) | AppKit | Itens ⌥ alternativos |
| Dropdown rico | `DSMenuPanel` | SwiftUI em `NSPopover` | |
| Hover card | `HoverCardController` | `NSPanel` não-ativável | 250/120 ms |
| Toast | `ToastCenter` + `ToastStack` | SwiftUI overlay | |
| Confirmação | `ConfirmationOverlay` | SwiftUI overlay | Inclui o aviso do ⌘Q (03 §16.10); `NSAlert` só para erro fatal de inicialização |
| Agent state | `AgentStateIndicator` | SwiftUI + `CAShapeLayer` | Fase sincronizada |
| Rim flash | `RimFlashLayer` | `CALayer` | M-309 |
| Viewer | `ComputerViewerView` | `WKWebView` (noVNC, T8) + overlays SwiftUI | Captura de teclado com saída (`03 §11.6`) |
| Menu bar extra | `MenuBarController` | `NSStatusItem` + `NSMenu` | Ícone template com contagem (`03 §17`); vive no app, que fica em modo `.accessory` depois do ⌘Q (AR-108); sem helper de login |
| Menus do app | `AppCommands` | SwiftUI `.commands` | Gerado do `KeyBindingRegistry` e do registro de ações (03 §24) |
| Registro de ações | `ActionRegistry` (`ActionID` → handler, `isEnabled`, motivo) | Protocolo `ActionDispatching` no Core, implementado na UI e injetado no boot (o Core não importa UI, AR-130) | Fonte de 03 §24 e do `ctl ui action` |
| Notificações | `NotificationRouter` | `UNUserNotificationCenterDelegate` | `willPresent` + `didReceive` |
| Dock badge | `NSApp.dockTile.badgeLabel` | AppKit | |
| Tokens | `DS.Color`, `DS.Font`, `DS.Space`, `DS.Radius`, `DS.Shadow` | Swift (`AgentBoxDesignSystem`) | Gerados de `design/tokens/*.json` por `scripts/gen-tokens.py` |

---

## 17. Convenção de `accessibilityIdentifier`

Todo elemento interativo e todo container de região tem identificador (T13). Formato: **`<região>.<elemento>[.<qualificador>]`**, lowerCamelCase, qualificador = ID estável do modelo (UUID do app, curto em 8 caracteres) ou nome fixo. Nunca usar o texto visível (muda com a tradução e com o título dinâmico). Esta seção dá só a convenção; **a lista canônica e única de identificadores é `03 §22`**, que 04, 05 e 08 citam. O enum `A11yID` é gerado de `03 §22`.

| Região | Prefixo | Exemplos |
|---|---|---|
| Janela/chrome | `window.` | `window.titlebar`, `window.sidebarToggle`, `window.historyBack` |
| Sidebar | `sidebar.` | `sidebar.search`, `sidebar.nav.inbox`, `sidebar.project.<id>`, `sidebar.session.<id>`, `sidebar.session.<id>.agent.<terminalId>`, `sidebar.session.<id>.child.<childId>`, `sidebar.pending.<id>` |
| Tab bar | `tabs.` | `tabs.tab.<terminalId>`, `tabs.tab.<terminalId>.close`, `tabs.new` |
| Panes | `pane.` | `pane.<terminalId>`, `pane.<terminalId>.header`, `pane.<terminalId>.status`, `pane.<terminalId>.splitRight`, `pane.<terminalId>.exitOverlay.restart` |
| Find | `find.` | `find.field`, `find.next`, `find.previous`, `find.caseSensitive` |
| Status bar | `statusBar.` | `statusBar.usage.claude`, `statusBar.computers` |
| Overlays | `overlay.<nome>.` | `overlay.composer.project`, `overlay.composer.submit`, `overlay.palette.input`, `overlay.confirmClose.confirm`. Botão primário de formulário = `.submit`; de confirmação = `.confirm`; Cancel = `.cancel` |
| Painel direito | `rightPanel.` | `rightPanel.tab.sourceControl`, `rightPanel.checks.row.<name>` |
| Viewer | `viewer.` | `viewer.<computerId>.takeOver`, `viewer.<computerId>.handBack` |
| Páginas | `library.`, `computers.`, `settings.`, `onboarding.`, `inbox.` | `settings.nav.terminal`, `settings.terminal.fontSize` |
| Menu bar extra | `menuBar.` | `menuBar.icon`, `menuBar.item.<sessionId>` |
| Menus do app | `menu.` | `menu.<group>.<action>` (ex.: `menu.terminal.splitRight`) |
| Dropdowns ricos | `menuPanel.` | `menuPanel.<name>` |
| Toasts | `toast.<kind>` | `toast.error.action` |

Os identificadores de cada tela estão listados em `03 §22` (lista canônica). Testes XCUITest e `agentbox ctl` só usam identificadores.

---

## 18. Glossário de UI (inglês) e regras de microcopy

| Conceito | Termo na UI | Não usar |
|---|---|---|
| Repositório/pasta raiz | **Project** | Repo, Workspace |
| Unidade de trabalho ligada a um diretório | **Session** | Workspace, Task |
| Sessão sem projeto e sem Git (P10, P11) | **Clean session**; seção **Sessions** na sidebar; ação **New Clean Session** (⇧⌘N) | Scratch, Loose |
| Cópia de trabalho Git | **Worktree** | Workspace |
| Processo num PTY | **Terminal** | Shell (exceto quando é shell puro), Process |
| Divisão de tela | **Pane** | Split view, Panel |
| Aba | **Tab** | |
| CLI de IA rodando | **Agent** (nome próprio: Claude Code, Codex, OpenCode) | Bot, AI, Assistant |
| Filho nativo do Claude/Codex | **Subagent** | Child agent |
| Ambiente Docker com browser/desktop (P15) | **Computer** | Box, Container, Sandbox ("box" só em ferramentas MCP, logs e pastas) |
| Container do modo isolado (v1.1) | **Container** ("In Container") | Box, Sandbox |
| Modo leve / isolado (P5) | **On This Mac** / **In Container** nas escolhas; adjetivo `isolated` permitido em texto corrido ("Isolated agents") | Light, Mode B / Mode A |
| Humano assume o computador | **Take Over** / **Hand Back** | Take Control, Give Back, Takeover, Revoke |
| Agente espera resposta (estado) | **Needs input** | Needs you (como estado), Waiting |
| Atenção agregada; computador pede ajuda | **Needs you** | Human request, HITL |
| Próximo item que pede atenção | **Next Needing Attention** | Next Needs You |
| Processo de fundo que mantém os terminais | **background service**; o que ele mantém: **background agents** | daemon, agentboxd, terminal daemon (fora de Diagnostics) |
| Proxy configurado pelo usuário (P13) | **Proxy** (nome dado pelo usuário; Zyte é um preset) | Zyte (como nome genérico), budget |
| Configuração de lançamento | **Profile** | Launch preset |
| Notificações in-app | **Inbox** | Requests, Activity |
| Retomar conversa nativa | **Resume** | Restore, Continue (exceto "Continue in Codex") |
| Diário PLAN/DOING/FOUND/BLOCKED | **Journal** | Diary, Notes |
| Log de requisições | **Network** | Listener, reqlog |
| Tentar de novo | **Try Again** | Retry |

Regras:
- **Title Case** em itens de menu, botões, títulos de overlay, nomes de aba e de seção (HIG). **Sentence case** em labels de campo, descrições, tooltips, toasts, banners e estados vazios.
- Botões começam com verbo e dizem o efeito ("Close Terminal", não "OK"; "Delete Session", não "Yes"; "Try Again", não "Retry").
- `…` só em comandos que abrem algo antes de agir ("Rename…", "Add Project…").
- Estados em linguagem de produto: "Running", não "PID 42634"; "Started 2m ago", não "Last event: started".
- Tempo relativo curto (`now`, `12m`, `3h`, `5d`) via `RelativeDateTimeFormatter` em `.abbreviated` com sufixo removido; data absoluta no tooltip.
- Dinheiro `$0.12` (duas casas, ou `<$0.01`); memória `6.1 GB`; porcentagem sem espaço `62%`.
- Strings em String Catalog (`Localizable.xcstrings`) com `en` como idioma de desenvolvimento, mesmo sem outra língua na v1.
