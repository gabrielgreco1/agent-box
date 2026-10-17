# 04 — Referência de design: Orca → Agent Box

Status: auditoria (somente leitura). Data: 2026-10-16.
Alvo: refazer a UI do Agent Box (SwiftUI/AppKit nativo) com a aparência e o comportamento do Orca.

## 0. Fontes e método

| Fonte | O que é |
|---|---|
| `/Applications/Orca.app` | Orca **1.4.219**, bundle id `com.stablyai.orca`, Electron. `app.asar` foi extraído para o scratchpad (`.../scratchpad/orca-asar`) e não para o repositório. |
| Código aberto | `https://github.com/stablyai/orca` (MIT). Clone raso em `/private/tmp/claude-501/-Users-gabriel-orca-workspaces-agent-box-otter/5dda428d-ecea-4852-b667-584fd17012cc/scratchpad/orca-src`. Todos os valores abaixo vêm do código-fonte (Tailwind v4 + shadcn/Radix + lucide-react 0.577 + cmdk + sonner + xterm 6). |
| Docs do Orca | `orca-src/docs/site/content/docs/*.mdx` (first-session, worktrees, tabs-panes-splits, notifications, agents-sessions, quick-open, settings) e `orca-src/docs/STYLEGUIDE.md`. |
| Config do dono | `~/Library/Application Support/orca/profiles/…` (lidas só as chaves de aparência): `theme: dark`, `appFontFamily: Geist`, `sidebarWidth: 280`, `rightSidebarWidth: 310`, `terminalFontFamily: SF Mono`, `terminalFontSize: 14`, `terminalLineHeight: 1`, `terminalCursorStyle: block`, `terminalThemeDark: "Ghostty Default Style Dark"`, `uiZoomLevel: 0`. **É exatamente isso que ele vê no dia a dia, então é o alvo.** |
| Design anterior | `design/` deste repositório (ver §9). |

Conversões: 1 unidade Tailwind = 4 px; `text-xs` = 12 px; `text-sm` = 14 px; raios derivam de `--radius` = 10 px (ver §1.4). Os caminhos citados são relativos a `orca-src/src/renderer/src/`, salvo indicação.

---

## 1. Tokens

### 1.1 Cores — tema escuro (o que o dono usa)

Fonte: `assets/main.css:294-403` (`.dark`) e `:436-462` (status).

| Token | Hex / valor | Uso |
|---|---|---|
| `background` | `#0a0a0a` | canvas da janela (também `backgroundColor` da BrowserWindow) |
| `foreground` | `#fafafa` | texto principal |
| `card` | `#171717` | titlebar, faixa de tabs, status bar |
| `popover` | `#171717` | popovers |
| `primary` / `primary-foreground` | `#e5e5e5` / `#171717` | botão primário (claro sobre escuro) |
| `secondary` / `muted` | `#262626` | superfícies secundárias |
| `muted-foreground` | `#a1a1a1` | texto secundário, ícones inativos |
| `accent` | `#404040` | hover de botões ghost |
| `border` | `rgba(255,255,255,0.07)` | todas as linhas divisórias |
| `input` | `rgba(255,255,255,0.15)` | borda de inputs |
| `ring` | `#737373` | foco |
| `worktree-sidebar` | `#2a2a2a` | **fundo da sidebar esquerda** (e do strip de 36 px acima dela) |
| `worktree-sidebar-accent` | `#353535` | item selecionado na sidebar |
| `worktree-sidebar-border` | `rgba(255,255,255,0.07)` | |
| `sidebar` | `#171717` | sidebar direita, settings |
| `sidebar-accent` | `#262626` | |
| `sidebar-primary` | `#1447e6` | (raro) |
| `editor-surface` | `#1e1e1e` | editor/diff |
| `destructive` | `#ff6568` | erro, "rename failed" |
| `status-success` | `#86efac` | |
| `status-warning` | `#eab308` | |
| `agent-question` | `orange-500` = `#f97316` | agente esperando o usuário (needs input) |
| `agent-question-text` | `orange-300` = `#fdba74` | |
| `workspace-status-review` / `progress` / `done` | `#16a34a` / `#d4a300` / `#c7a594` | estados de PR do workspace |
| `tab-group-split-divider` / `-strong` | `#71717a` / `#a1a1aa` | divisor entre grupos de tabs |
| divisor de pane de terminal | `#3f3f46` (claro: `#d4d4d8`), 3 px | splits dentro de uma tab |
| `ai-action-accent` | `violet-400` = `#a78bfa` | |
| git: added / modified / deleted / untracked | `#81b88b` / `#e2c08d` / `#c74e39` / `#73c991` | decorações de arquivos |
| Logo Claude | `#D97757` | glifo do Claude (`status-bar/icons.tsx:318`) |

Cores de estado (paleta Tailwind usada diretamente):

| Estado | Cor |
|---|---|
| working (spinner) | `yellow-500` `#eab308` |
| done / active (bolinha) | `emerald-500` `#10b981` |
| failed / blocked | `red-500` `#ef4444` |
| idle / inactive | `neutral-500` a 40% (`#737373` @ 0.4) |
| unread (bolinha / sino) | `amber-500` `#f59e0b` |
| needs input | `orange-500` `#f97316` (ícone `MessageCircleQuestion`) |
| PR open / merged / closed / draft | `emerald-500`@80% / `purple-400`@70% / muted@60% / muted@50% |
| checks failing / pending / passing | `rose-500`@85% (`#f43f5e`) / `amber-500`@85% / `emerald-500`@80% |

Tema claro (para referência, `:root` em `main.css:171-290`): background `#fff`, card `#fff`, worktree-sidebar `#f5f5f5`, accent sidebar `#eaeaea`, border `#e5e5e5`, muted-fg `#737373`, destructive `#e40014`.

### 1.2 Terminal (tema do dono: "Ghostty Default Style Dark")

Fonte: `src/shared/terminal-themes/defaults.ts:6-29`, `src/shared/terminal-fonts.ts`, `default-global-settings.ts`.

- Fundo `#282c34`, texto `#ffffff`, cursor `#ffffff` (bloco, piscando), seleção `#5a7898`.
- ANSI 0-7: `#1d1f21 #cc6666 #b5bd68 #f0c674 #81a2be #b294bb #8abeb7 #c5c8c6`.
- ANSI 8-15: `#666666 #d54e53 #b9ca4a #e7c547 #7aa6da #c397d8 #70c0b1 #eaeaea`.
- Fonte SF Mono 14 px, line-height 1.0, peso 500 (bold 700). Padding interno do xterm de 4 px.
- Pane inativo com opacidade 0.9; transição de 140 ms.

### 1.3 Tipografia

- **UI:** `Geist` (variável, OFL, embutida em `assets/fonts/Geist-Variable.woff2`), com fallback `-apple-system`. `letter-spacing: 0.01em` global e antialiased. Itens de navegação usam `tracking-tight` (−0.025em).
- **Mono:** `SF Mono, SFMono-Regular, ui-monospace…`. Usada em terminal, títulos de pane, nomes de modelo e pastas.
- **Escala real em uso** (fica quase toda entre 10 e 14 px):

| px | Peso | Onde |
|---|---|---|
| 9 | — | keycaps no hover do Search |
| 10 | 500–600 | badges (`primary`, `rename failed`, `sparse`), tempo relativo ("5d"), nome do modelo |
| 11 | 400 | branch embaixo do nome, linhas de atividade do agente, labels uppercase do settings, rodapé da palette |
| 12 | 600 | nome "Orca" na titlebar, label da seção "Projects", tabs (`text-xs`), itens de menu (12 px / lh 17 / peso 450) |
| 13 | 500 / 600 | itens da nav e Search (500), nome do worktree (400 lido, 600 não-lido), nome do projeto (600), itens do Settings |
| 14 | 400–500 | corpo de dialogs, botões, inputs |
| 16–18 | 600 | títulos de dialog (composer 16, dialog padrão 18) |
| 36 | 700 | "ORCA" na landing vazia |

### 1.4 Raios, espaçamento, sombras

- `--radius` = 10 px. sm = 6, md = 8, lg = 10, xl = 14, 2xl = 18. Na prática os controles pequenos usam `rounded-md` = **8 px**, mas os botões da titlebar usam **4 px** e os badges **4 px** (`rounded`/`rounded-[4px]`).
- Cards do worktree: `rounded-lg` = 10 px.
- Menus dropdown/contexto: **11 px**, padding 4 px. Item de menu com 8 px × 4 px de padding e raio 8.
- Dialog: 10 px de raio, 24 px de padding, 16 px de gap.
- Grade base de 4 px. Valores recorrentes: 2, 4, 6, 8, 10, 12, 16, 24.
- Sombras:
  - Dialog (escuro): `0 24px 72px rgba(0,0,0,.55)` + `inset 0 1px 0 rgba(255,255,255,.06)`.
  - Menu: `0 16px 34px rgba(0,0,0,.40)`.
  - Flutuante: `0 10px 24px rgba(0,0,0,.18)`.
  - Não há glow nem gradiente em lugar nenhum.
- Materiais:
  - Menus: `rgba(0,0,0,0.72)` + `backdrop-blur-2xl` + borda `white/14`.
  - Dialog: `rgba(23,23,23,0.96)` + blur.
  - Overlay de modal: `black/55` + blur de 2 px.

### 1.5 Movimento

Fonte: `main.css` e as classes `tw-animate-css` dos primitivos.

| Elemento | Duração | Easing |
|---|---|---|
| Hover de botão/linha (bg/cor) | 100–150 ms | ease |
| Largura da sidebar (colapsar) | 200 ms | ease |
| Card do worktree (hover/ativo) | 200 ms | — |
| Expandir lista de agentes no card | 180 ms (grid-rows 0fr→1fr) + reveal opacity/translateY(−2px) | `cubic-bezier(0.16,1,0.3,1)` (ease-out-expo) |
| Collapsible down / up | 200 / 180 ms | ease-out |
| Dialog abrir/fechar | 200 ms, fade + zoom 95%→100% | default |
| Dropdown abrir | 150 ms, fade + zoom 98% + slide de 8 px do lado | default |
| Tooltip | fade + zoom 95% (delay padrão Radix ~700 ms) | |
| Chevron rotacionar | 150 ms | |
| Settings entrar | 180 ms | ease-out |
| Opacidade de pane inativo | 140 ms | |
| Botões do header do pane (hover reveal) | 120 ms opacidade | |
| Spinner "working" | 1 volta/s em **12 passos discretos** (não é contínuo); todos em fase; parado sob Reduce Motion | steps |
| Toast de update in/out | 200 / 150 ms | ease-out / ease-in |
| "Revelar workspace atual" (glow) | 1.5 s | ease-out |

Regra geral: ≤ 200 ms, sem bounce, `prefers-reduced-motion` respeitado em todos os loops.

### 1.6 Ícones

- **lucide-react**, stroke padrão (2). Na nav da sidebar usam stroke 1.75 (ativo 2.25) e no header de seção 2.25.
- Tamanhos: 16 px (nav, toggles da titlebar), 14 px (ações de header, menus), 12–13 px (status, quick actions, logos de agente no card), 10 px (dentro de badges).
- Logos de agente: SVG inline para Claude, Codex (OpenAI), OpenCode, Copilot, Aider, Droid, Pi, Kilo. Para os demais, PNG em `src/shared/agent-icons/*.png` (amp, cline, cursor, gemini, goose, …) com `borderRadius 2`. O fallback é um tile com letra.

---

## 2. Anatomia da janela

```
┌──────────────── 280 ───────────────┬────────────────────────────────────────────┬──── 310–350 ────┐
│ ●●●  Orca  [▯]            [←][→]   │ [tab][tab][tab] [+]     [▷ Command] [⋯][▯] │ activity bar 36 │ 36 px (sidebar) / 32 px (tab row)
├────────────────────────────────────┼────────────────────────────────────────────┼─────────────────┤
│ [🔍 Search                   ⌘K]   │                               [□][⫿][×]   │                 │
│  ≡ Tasks                           │                                            │  Explorer /     │
│  ⏲ Automations                     │          terminal (xterm, full-bleed)      │  Source Control │
│  ▢ Orca Mobile                     │                                            │  / Checks …     │
│ Projects            🔔 ⚙ 📁 +      │                                            │                 │
│  ▸ repo                            │                                            │                 │
│   ● worktree-name   [primary]      │                                            │                 │
│     branch/name                    │                                            │                 │
│     ◌ ✳ texto do agente …     5d   │                                            │                 │
│ ─────────────────────────────────  │                                            │                 │
│ [kanban] [crosshair]               │                                            │                 │
├────────────────────────────────────┴────────────────────────────────────────────┴─────────────────┤
│ status bar 24 px: uso Claude/Codex … portas, recursos, ssh                                        │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Janela / titlebar

Fontes: `src/main/window/createMainWindow.ts:102-135` e `main-window-visual-lifecycle.ts:110-123`.

- `titleBarStyle: 'hiddenInset'`; não há barra de título visível e o conteúdo começa em y = 0.
- **Semáforos:** `trafficLightPosition {x: 16, y: 12}`. A constante `TITLEBAR_CSS_CENTER = 18` dá o centro vertical dos semáforos em **y = 18**, ou seja, o meio de uma faixa de 36 px. Com zoom, o y é recalculado.
- Sem vibrancy no macOS (foi removida de propósito). Fundo `#0a0a0a`. Tamanho mínimo 600×400. `acceptFirstMouse: true`.
- **Faixa esquerda** (`.titlebar-left`, acima da sidebar):
  - 36 px de altura, fundo `worktree-sidebar` (#2a2a2a).
  - Divisor feito com `box-shadow: inset 0 -1px 0 border`, para não roubar 1 px e manter o centro em 18.
  - Região de arrastar.
  - Conteúdo da esquerda para a direita:
    1. Pad de **80 px** reservado aos semáforos.
    2. **"Orca"**: 12 px, peso 600, altura 24, padding 0 6, margin-left 2, margin-right 4, raio 4, cor muted. Clicável; o clique direito oferece "Hide App Name".
    3. **Toggle da sidebar:** lucide `PanelLeft` 16 px, padding 4×8, raio 4, hover `accent` com cor `foreground`. Atalho ⌘B.
    4. **Voltar/avançar** (`ArrowLeft`/`ArrowRight` 12 px, padding 4×5), empurrados para a direita da faixa (`ml-auto mr-3`). Atalhos ⌘⌥← / ⌘⌥→. Ficam desabilitados com opacidade 0.45.
- **Sidebar colapsada:** a faixa vira flutuante (`absolute`, fundo `card`, borda direita) sobre a linha de tabs.

### 2.2 Linha de tabs (topo do painel principal)

Fontes: `components/tab-group/TabGroupPanel.tsx`, `components/tab-bar/*`.

- **Altura 32 px**, fundo `card` (#171717), `border-bottom` 1 px `border`. Fica abaixo de uma faixa de arrastar de 4 px, completando os 36 px da faixa da sidebar. Cada grupo de split tem a sua própria linha de tabs.
- **Strip:** rolagem horizontal sem scrollbar, com fade de 24 px nas bordas quando há overflow e chevrons de 20×24.
- **Largura da tab:** 180 px (220 px quando a janela tem ≥ 1280 px), mínimo 72 px.
- **Tab:**
  - `px-1.5` (6 px), texto de 12 px, separador `border-r` 1 px entre tabs.
  - Ativa: fundo `foreground` 6% sobre `card` (≈ `#1f1f1f`), texto `foreground` e **barra inferior de 2 px `foreground`**.
  - Inativa: fundo `card`, texto `muted-foreground`, que fica `foreground` no hover.
  - Não lida com atividade: overlay `amber-500/10`.
- **Conteúdo da tab**, em ordem:
  1. `AgentStateDot` (12 px): spinner amarelo, check verde, `?` laranja, bolinha vermelha ou cinza.
  2. Logo do agente de 12 px (70% de opacidade se inativa), ou `ShellIcon` de 12 px se for um shell puro.
  3. Ícone `Pin` (opcional).
  4. Título truncado.
  5. Bolinha de cor opcional (8 px).
  6. **Fechar:** `X` de 12 px num botão de 16×16, raio 4. Sempre visível na ativa; nas inativas só aparece no hover. Clique do meio também fecha. Duplo clique renomeia.
- **"+":** botão de 28×28, raio 8, `Plus` 14 px, hover `accent/50`. Abre um menu de 288 px de largura (raio 11) com:
  - campo de busca/omnibox ("Search open tabs, files, URLs, agents…")
  - New Terminal ⌘T
  - New Browser Tab ⌘⇧B
  - New Markdown ⌘⇧M
  - Open Markdown ⌘⇧O
  - lista de agentes ("New Claude tab", …)
  - "Agent settings…"
- **À direita** (só no grupo focado, gap 2 px):
  - **"▷ Command":** botão de 28 px de altura, padding 6, `Play` 14 px e texto "Command" 12 px/500 em cor muted. Quando já existem comandos salvos vira split button (▶ preenchido + nome + `ChevronDown` → lista de 320 px).
  - `⋯` (Pane actions): só aparece quando há splits.
  - **Toggle do painel direito:** `PanelRight` 16 px, ⌘L.

### 2.3 Área de terminal e splits

- O terminal ocupa todo o espaço restante, sem moldura nem cartão, com 4 px de padding interno.
- **Header do pane:**
  - 24 px de altura, sobreposto no topo do pane, padding 0 8, fonte mono 13 px.
  - Cor `white/52` e separador `white/6`.
  - Ações no canto superior direito, ghost de 24×24 com ícone de 12 px: `MessageSquarePlus`, `SquareTerminal`, `SquareSplitVertical` (split à direita) e `X`.
  - O split aparece no pane ativo ou no hover; o fechar só no hover, com fade de 120 ms.
  - Variante "chromeless": fundo transparente.
- **Split dentro da tab:** ⌘D à direita, ⌘⇧D para baixo, ⌘] / ⌘[ para trocar o foco, ⌘⇧↵ para expandir, ⌘W para fechar. O divisor tem 3 px visíveis (`#3f3f46`) e 3 px extras de área de clique de cada lado. O pane inativo fica com opacidade 0.9.
- **Split de grupos de tabs:** arraste a tab até a borda direita ou inferior de um pane. A alça tem 6 px de área de clique e linha de 3 px `#71717a` (`#a1a1aa` no hover/drag, transição de 100 ms). O grupo sem foco fica com opacidade 0.95.

### 2.4 Painel direito

- Largura padrão de 350 px (o dono usa 310), mínimo 220. Sempre preserva 320 px para o centro.
- Fundo `sidebar` (#171717) com `border-left` 1 px. Alça de resize de 4 px (hover `ring/20`).
- **Activity bar** no topo:
  - 36 px de altura, botões de 36×36 com ícone de 16 px.
  - Ativo: `foreground` com sublinhado de 2 px (de 25% a 75% da largura). Inativo: `muted/60`.
  - Bolinhas de status de 7 px.
- Abas:
  - Explorer (`Files`, ⌘⇧E)
  - Agents (histórico de sessões)
  - Attached worktrees (`Workflow`)
  - Source Control (`GitBranch`, ⌘⇧G); aqui ficam ahead/behind, dirty e commit/push
  - Checks / PR Checks (`ListChecks`)
  - Ports (`Plug`)
  - Search (⌘⇧F)
- Overflow vai para um menu `⋯`.

### 2.5 Status bar

- **24 px** de altura, padding 0 12, gap 16, `border-top`, fundo `card`, texto de 12 px.
- À esquerda: medidores de uso Claude/Codex (abre um roster de 360 px) e refresh.
- À direita: Caffeinate, updates, recursos, portas, SSH.
- O clique direito escolhe quais segmentos aparecem. Dá para esconder tudo.

---

## 3. Sidebar esquerda (anatomia detalhada)

Fonte: `components/sidebar/**`.

- **Largura:** 280 px por padrão, mínimo 220, máximo 500. Fundo `#2a2a2a`.
- **Resize:** área de clique de 12 px centrada na borda direita. A linha de 1 px fica transparente e vira `ring/50` no hover e `ring` no drag.
- **Scrollbar:** 8 px, invisível até o hover da sidebar; depois `muted-fg` a 28% (48% no hover do thumb).

### 3.1 Topo (nav)

- Wrapper com padding 8 px nas laterais, 8 px em cima e 4 px embaixo; gap de 2 px.
- **Search:**
  - Altura ≈ 32 px, padding 8×6, raio 8.
  - Fundo `foreground/5` (hover `/8`). Texto de 13 px/500 em `foreground/60`.
  - Ícone `Search` de 16 px a `fg/30`.
  - Os keycaps do atalho só aparecem no hover/foco, com 9 px.
- **Itens (Tasks `List`, Automations `CalendarClock`, Orca Mobile `Smartphone`):**
  - Mesma caixa do Search: gap de 8 px, 13 px/500, `tracking-tight`, texto `fg/60`, ícone 16 px a `fg/30` com stroke 1.75.
  - Hover `fg/8`.
  - Ativo: fundo `worktree-sidebar-accent` (#353535), texto cheio, ícone com stroke 2.25.
- Extras:
  - No hover de Tasks aparecem ícones de 14 px dos provedores (GitHub, GitLab, Linear, Jira).
  - "Orca Mobile" tem a pílula "New": 10 px/600, `bg-primary`, `rounded-full`.
  - Clique direito → "Hide from sidebar".

### 3.2 Header "Projects"

- 8 px de margem superior, **32 px** de altura, padding 0 8 px.
- Label "Projects": 12 px/600, `muted-foreground/80`.
- Ações à direita: botões ghost de 24×24, raio 8, ícone de 14 px com stroke 2.25, cor muted e hover `accent`.
  1. `Bell`: alterna o corpo da sidebar para o feed de atividade/agentes. Ativo: `primary/15`.
  2. `SlidersHorizontal`: menu de Sort by / Group by / Show / Filters (esconder dormentes, branch default, criados por automação/CLI, detached).
  3. `FolderPlus`: "Add project".
  4. `Plus`: "New workspace" (⌘N).

### 3.3 Linha de projeto (grupo)

- **28 px** de altura e 6 px de gap entre linhas virtuais. Padding esquerdo de 10 px + 10 px por nível.
- Ícone do repo de 16 px (caixa com raio 4, glifo de 14), nome em 13 px/600.
- Fica sticky no topo ao rolar.
- No hover aparecem, à direita, botões de 20 px: `ChevronDown` (colapsar; gira −90° quando fechado), `Ellipsis` (menu do projeto) e `Plus` (novo workspace no projeto).

### 3.4 Card de worktree

- **Superfície:** `rounded-lg` (10 px), borda transparente, `ml-1` (4 px) e `pr-1.5` (6 px). Padding vertical de 5/6 px, ou 8 px quando o card só tem título. Transição de 200 ms.
- **Estados:**

| Estado | Visual |
|---|---|
| hover | `sidebar-accent` a 40% |
| ativo | fundo `fg` 10%, borda `fg` 18% misturada à borda |
| multi-seleção | anel `ring` 30–35% |
| deletando | 50% de opacidade, grayscale e pílula "Deleting…" com spinner |
| SSH desconectado | 60% de opacidade |

- **Layout:** coluna de status de 20 px à esquerda (+4 px de margem) e conteúdo em coluna com gap de 6 px.
  - **Linha 1:**
    - Status: bolinha de 8 px `emerald-500` (ativo/done) ou `neutral-500/40` (inativo), spinner amarelo de 8 px (working) ou `?` laranja (needs input).
    - Nome: 13 px, lh 20. Não lido: 600 `foreground`; lido: 400 `foreground/80`. Duplo clique renomeia inline.
    - Badges, todos com 16 px de altura, 10 px, padding 0 6, raio 4:
      - **`primary`:** texto `fg/70`, borda `fg/20`, fundo `fg/6%`. Tooltip "Primary worktree (original clone directory)".
      - **`rename failed`:** `destructive` com borda `/40`, fundo `/10` e `AlertCircle` de 10 px. O clique abre um dialog.
      - `sparse` em âmbar, detached HEAD (cor git-modified).
    - No hover: `Star` (pin, amber-400) e `Trash2` 14 px (hover destrutivo).
  - **Linha 2:** branch em 11 px `muted-foreground`, lh 1. Opcionalmente o chip do repo (10 px/600 minúsculo, fundo `accent`, raio 4), badge de conflito (âmbar, `GitMerge`) e ícone de PR de 13 px na cor do estado (open/merged/checks). Hover no card abre detalhes (portas, PR, checks).
  - **Linhas de agente:**
    - **24 px** de altura, padding 0 4, gap 4, raio 4, texto de 11 px `muted-foreground`.
    - Conteúdo:
      1. `AgentStateDot` sm (10 px; spinner amarelo quando working)
      2. logo do agente de 13 px (Claude `#D97757`)
      3. texto "lead – trail", com lead `muted/90` (600 `foreground` se não visto) e trail `muted/65`, truncado
      4. modelo em mono 10 px (máx. 96 px), opcional
      5. contador `+N`
      6. **tempo** 10 px `tabular-nums` `muted/60` ("now", "12m", "3h", "5d")
    - Hover: `accent` 18%. Pane focado: fundo `worktree-sidebar-accent`.
    - Com muitos agentes vira uma pílula-resumo de 24 px (até 3 grupos de estado com logos sobrepostos de 16 px e chevron de 12 px) que expande em 180 ms.
- **Linha pendente** (criação em background): spinner de 16 px + nome de 13 px.
- **Rodapé da sidebar:** `border-top`, padding 8×6, ícones `Kanban` (board) e `Crosshair` (rolar até o atual).
- **Lista vazia:** "No workspaces found" em 11 px muted, centralizado, mais o botão "Clear Filters".
- **Menu de contexto do worktree** (cabeçalho "Workspace" em 11 px), itens com ícone de 14 px:
  - Rename/Update
  - Open In ▸
  - Copy Path
  - Copy Name
  - Pin/Unpin
  - Mark Read/Unread
  - Move to group
  - Delete Worktree (destrutivo)

---

## 4. Inventário de componentes

| Componente | Especificação resumida |
|---|---|
| Button | Alturas: default 36, sm 32, xs 24 (12 px), lg 40. Ícones: 36/32/24. Raio 8, texto 14/500. Variantes default (claro), secondary, outline (`input/30`), ghost (hover `accent/50`), destructive (`destructive/60`), link. Foco: anel de 3 px `ring/50`. |
| Botão de titlebar | Padding 4×8, raio 4, ícone de 16 px muted, hover `accent`. |
| Input | Raio 8, padding 12×6, 14 px, borda `input`, foco com anel de 3 px. |
| Badge | `rounded-full`, padding 8×2, 12/500. Variante de sidebar: 16 px de altura, 10 px, raio 4. |
| Tooltip | Fundo `foreground` (claro) e texto `background` (escuro): **tooltip invertido**. 12 px, padding 12×6, raio 8, seta de 10 px. |
| Dropdown / context menu | Mínimo 176 px, raio 11, padding 4. Fundo `black/72` com blur e borda `white/14`. Itens de 12 px/450, lh 17, padding 8×4, raio 8, foco `white/14`. Separador `border/60` com 3 px de margem. Ícones de 14 px muted. |
| Dialog | 512 px (confirmação: 448), raio 10, padding 24, gap 16. Overlay `black/55` com blur de 2 px. Título 18/600, descrição 14 muted, footer alinhado à direita com gap 8. X a 16/16 do canto. Animação de 200 ms (fade + zoom 95%). |
| Confirmation | Promise-based. Tile de ícone opcional de 40 px (raio 10, ícone de 20). Checkbox "Don't ask again". Botões Cancel (outline) e Confirm (default/destructive). |
| Command palette (⌘J) | 900 px (máx. 96vw), a `min(10%,64px)` do topo, raio 14, sombra `0 26px 84px rgba(0,0,0,.32)`. Input de 48 px, lista com altura máxima de `min(600, 100vh−224)`. Rodapé de 11 px com dicas (⌘↵ Create workspace · ↵ Open · Esc · ↑↓). |
| Quick Open (⌘P) | 660 px, a 20% do topo, input de 36 px. Linhas com ícone de arquivo de 14 px + nome + diretório muted. |
| Toast | sonner, canto inferior direito, ícones de 16 px (check, info, triangle, octagon, loader). |
| Card de notificação in-app | 360 px, fixo 40 px acima do rodapé e 16 px da direita, empilhado com gap de 8. |
| AgentStateDot | sm: caixa de 10 / bolinha de 6. md: caixa de 12 / bolinha de 8. Ver estados em §1.1. |
| Spinner working | Círculo com borda de 2 px `yellow-500` e topo transparente, 12 passos/s. |
| Combobox de agente | Trigger de 36 px, largura cheia, ícone de 14 + label + `ChevronsUpDown`. Popover com "Search agents...", "Blank Terminal" primeiro, depois a lista e "Manage agents →". |
| Settings | Sidebar de 280 px (com "Back to app", busca de 13 px e itens de 13/500 com padding 10×8 e raio 10) e conteúdo centralizado de **896 px** com padding 40/32/96 e 40 px entre seções. |
| Landing vazia | Coluna de 512 px. Logo em tile de 80 px (raio 18). "ORCA" 36/700, subtítulo 14 muted. Botões "Add project" e "Create Worktree". Lista de atalhos (320 px). |

---

## 5. Fluxos

### 5.1 Adicionar projeto

1. A ação vem do `FolderPlus` no header "Projects", da landing ou do "+" no campo Project do composer (abre aninhado e preserva o que já foi digitado).
2. Dialog "Add a project" (512 px):
   - Uma ação primária grande: **Browse folder** (picker nativo).
   - Uma lista "OTHER WAYS TO ADD": Clone from URL e Create new project. Navegação por ↑↓, com chip ⏎ na linha selecionada.
3. **Clone:** campos "Git URL" e "Parent folder"; ↵ clona ("Cloning...").
4. Se a pasta contiver vários repos, há um scan com opção "Stop scan" e um passo de importação múltipla.
5. Depois de adicionar: o Orca detecta o **base ref** (`origin/main`) e abre o checkout default como worktree **primary**.

### 5.2 Criar worktree/sessão (composer)

1. Abre com ⌘N, pelo "+" do header, pelo "+" no hover do projeto ou por ⌘J → "Create worktree" (quando a busca não casa com nada, a palette oferece criar com o texto digitado).
2. Modal de 512 px, título 16/600 "Create worktree". Seções com 16 px de espaçamento e labels de 12/500 muted:
   1. **Project:** combobox com type-ahead; "Add a new project" fica fixo no fim da lista.
   2. **Create From [Optional]:** um campo inteligente que aceita nome, `#1234`, branch ou URL de GitHub/GitLab/Linear/Jira. O seletor de **base ref** fica alinhado à direita do label. Se o branch já existe, aparece o checkbox "Reuse branch" (animação de 200 ms). **↵ nesse campo leva o foco ao seletor de agente.**
   3. **Agent [Optional]:** combobox pré-selecionado com o agente default; também tem "Blank Terminal". O clique direito define o default. O ícone de engrenagem abre as configurações de agentes. **↵ no trigger submete.**
   4. **Advanced ⌄** (fechado por padrão):
      - Workspace name
      - Branch name (`feature/my-branch`)
      - **Note**: vira o prompt ou rascunho do agente
      - script de setup (`orca.yaml`)
      - parent workspace
      - sparse checkout
   5. **Footer:** toggle "Create more", botão primário `sm` "Create" com dica ⌘↵ e caixa de erro destrutiva quando falha.
3. ⌘↵ submete de qualquer campo. Nome vazio gera um nome de criatura marinha. O branch fica `prefixo/nome` (prefixo = usuário git, custom ou nenhum).
4. **O modal fecha na hora.** `git fetch` + `git worktree add` rodam em background. Enquanto isso:
   - a sidebar mostra uma linha pendente (spinner);
   - o painel principal mostra as fases `preparing → fetching → creating`.
5. Quando termina, o worktree fica ativo e **uma tab de terminal já abre rodando o CLI do agente** no cwd do worktree (Claude com `--dangerously-skip-permissions` por padrão, configurável), com o Note como prompt. "Blank Terminal" abre só o shell.
6. Dentro de um worktree existente:
   - "+" na tab bar → "New Claude tab" etc.
   - ⌘⌥T abre o agente default.
   - ⌘T abre um terminal.

### 5.3 Sessão na sidebar e git

- Cada sessão de agente é uma **linha de 24 px** dentro do card do worktree, com estado, logo, último texto e tempo.
- O estado vem do título OSC do terminal e de hooks dos agentes.
- **Agent states:**

| Estado | Glifo | Quando |
|---|---|---|
| working | spinner amarelo | agente rodando |
| permission / needs input | `?` laranja | esperando o usuário |
| done | check/bolinha verde | terminou o turno |
| failed / blocked | bolinha vermelha | erro, bloqueio |
| interrupted | bolinha muted | interrompido |
| idle | bolinha cinza 40% | sem atividade há ~30 min |
| (nenhum) | — | shell puro, não reconhecido |

- **Git no card:** branch (linha 2) e ícone de PR colorido por estado/checks. Também badges: `primary`, conflito de merge, detached HEAD, `rename failed` (o branch auto-gerado pode ser renomeado sozinho quando o agente começa a trabalhar).
- **Ahead/behind e dirty não aparecem no card**; ficam em Source Control no painel direito.
- Failed checks viram chip vermelho. O hover do card mostra State/Review/Checks.
- **Ciclo do worktree:** Create → Work → Review (diff contra o start-from) → Ship (commit, push, PR, checks inline) → Archive/Delete (remove diretório e branch, com confirmação).

### 5.4 Notificações

- **Quando o agente passa de working para idle/needs-input**, o Orca dispara:
  - notificação do sistema, com título `"{repo} / {worktree} - {Agent} {status}"` (status: needs input, finished, failed, …) e corpo com a última mensagem;
  - som (System, Two Tone, Bong, …, ou arquivo próprio);
  - chip/estado não lido no worktree.
- Suprimido se a janela está focada no próprio workspace (`suppressWhenFocused: true`). Há cooldown por workspace.
- Clicar na notificação leva ao worktree e ao pane certos.
- **Não lido:** nome em negrito, bolinha âmbar de 6 px na coluna de status, overlay `amber/10` na tab e bolinha âmbar no ícone da menu bar.
  - A doc fala em badge no Dock, mas o código atual usa o tray.
- **Sino (`Bell`)** no header "Projects": alterna para o feed de agentes, agrupado por status (running no topo, needs-you, done).

### 5.5 Tabs e splits

- Cada worktree tem a sua própria árvore de panes; trocar de worktree troca o layout inteiro (persistido).
- Uma tab contém terminal, editor, browser, diff ou PR.
- Arrastar a tab até a borda faz split. ⌘D/⌘⇧D fazem split dentro da tab de terminal.
- Atalhos de tab:
  - ⌘⇧] / ⌘⇧[: próxima/anterior
  - Ctrl+Tab: recente
  - ⌘W: fechar
  - ⌘⇧T: reabrir
  - ⌘R: renomear
- Quando o agente sai, aparece o chip **Restart** na tab.

### 5.6 Palette e navegação

- **⌘J**, "Jump to...", busca em chats, terminais, workspaces, tasks, settings e ações:
  - Vazia: Recent Chats & Terminals (needs-you primeiro) e Recent Worktrees.
  - Tab abre os filtros por host e projeto.
  - ⇧↵ abre em split.
  - Se nada casar, oferece "Create worktree".
- ⌘P: arquivos. ⌘⇧↑/↓: worktree anterior/próximo. ⌘1–9: selecionar workspace. ⌘⌥←/→: histórico.

### 5.7 Settings

Página inteira (não é modal). Fica em "Back to app" + busca (⌘F). Grupos:

| Grupo | Seções |
|---|---|
| AI Capabilities | Agents, Accounts, … |
| Set Up | General, Integrations, Mobile |
| Workflows | Git, Terminal, Quick Commands, Browser, … |
| Interface | Appearance (tema, fonte UI, terminal, janela), Notifications, Shortcuts |
| Remote Hosts | — |
| Privacy | — |
| Advanced | — |
| Experimental | — |

Também há uma seção por projeto.

### 5.8 Onboarding

Overlay de cartão (até 1100 px, raio 14, título 34/600). Passos:
1. Pick your default agent
2. Theme
3. GitHub tasks
4. Notifications
5. Termina com "Add your first project"

---

## 6. Atalhos globais (padrão macOS)

| Ação | Atalho |
|---|---|
| Toggle sidebar / painel direito | ⌘B / ⌘L |
| Novo worktree | ⌘N (ou ⌘⇧N) |
| Jump palette / arquivos | ⌘J / ⌘P |
| Nova tab terminal / agente default | ⌘T / ⌘⌥T |
| Fechar tab ou pane / reabrir | ⌘W / ⌘⇧T |
| Próxima/anterior tab | ⌘⇧] / ⌘⇧[ |
| Split direita / baixo | ⌘D / ⌘⇧D |
| Foco pane próximo/anterior | ⌘] / ⌘[ |
| Expandir pane | ⌘⇧↵ |
| Worktree anterior/próximo | ⌘⇧↑ / ⌘⇧↓ |
| Selecionar workspace N | ⌘1…9 |
| Voltar/avançar | ⌘⌥← / ⌘⌥→ |
| Explorer / Source Control / Search | ⌘⇧E / ⌘⇧G / ⌘⇧F |
| Renomear worktree | ⌘⌥R |
| Deletar workspace | ⌘⇧⌫ |
| Submeter composer | ⌘↵ |
| Zoom | ⌘= / ⌘- / ⌘0 |

Settings não tem atalho padrão: ⌘, fica com o terminal. Para o Agent Box, recomendo manter ⌘, para Settings, que é o padrão do macOS.

---

## 7. Orca → Agent Box nativo (SwiftUI/AppKit)

| Orca | Implementação nativa recomendada |
|---|---|
| `titleBarStyle: hiddenInset`, conteúdo começando em y = 0 | `NSWindow.styleMask.insert(.fullSizeContentView)`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, **sem NSToolbar** (o toolbar força alturas de 38/52 pt e muda o espaçamento). Em SwiftUI: `.windowStyle(.hiddenTitleBar)` mais um `NSViewRepresentable`/`WindowAccessor` para os ajustes finos. `isMovableByWindowBackground = false`. |
| `trafficLightPosition {x:16, y:12}` (centro em y = 18) | Reposicionar `standardWindowButton(.closeButton/.miniaturizeButton/.zoomButton)` mudando `frame.origin` (x = 16, 36, 56; y centralizado em 18 pt a partir do topo, em coordenadas do superview `NSTitlebarView`). Reaplicar em `windowDidResize`, `windowDidEnterFullScreen`/`Exit` e `viewDidLayout` (o AppKit reseta). Alternativa robusta: subclasse de `NSWindow` com override de `layoutIfNeeded`. Validar com screenshot ao lado do Orca. |
| Faixa de arrastar (`-webkit-app-region: drag`) | A faixa de 36 px é uma `NSView` com `mouseDownCanMoveWindow = true` (ou `window.performDrag(with:)` no `mouseDown`). Botões dentro dela são views normais (não arrastam). Duplo clique na faixa → `performZoom` (respeitar `AppleActionOnDoubleClick`). |
| Pad de 80 px + "Orca" + `PanelLeft` + ←/→ | `HStack(spacing:0)` de 36 pt: `Spacer().frame(width:80)`, `Text("Agent Box").font(12, .semibold)` com padding 6 e raio 4, botões de 16 pt com padding 4×8, raio 4 e hover `accent`. ←/→ usam SF Symbol `arrow.left`/`arrow.right` de 12 pt ou lucide exportado. |
| Sidebar 280 (220–500) redimensionável | **`NSSplitViewController`** com `NSSplitViewItem(sidebarWithViewController:)` hospedando SwiftUI (`NSHostingController`), `minimumThickness 220`, `maximumThickness 500`, `canCollapse = true`, divisor fino (`dividerStyle = .thin`, com cor própria via subclasse que desenha `border`). **Não usar** `NavigationSplitView` (aparência de sidebar de sistema com vibrancy e inset). Desligar o material: `NSSplitViewItem.allowsFullHeightLayout = true` e fundo sólido `#2a2a2a`. Colapsar com animação de 200 ms (`NSAnimationContext`). ⌘B → `toggleSidebar`. |
| Painel direito 310–350 (mín. 220) | Terceiro `NSSplitViewItem(inspectorWithViewController:)` (macOS 14+) ou item comum com `canCollapse`. ⌘L. |
| Lista de worktrees virtualizada | SwiftUI `ScrollView` + `LazyVStack(spacing: 6)` com `ForEach` hierárquico (projeto → worktree → agentes). Linhas próprias, **não** `List(.sidebar)` (traz seleção azul e insets do sistema). Hover com `.onHover`, seleção desenhada à mão (fundo `fg` 10%, borda `fg` 18%, raio 10). Header de projeto sticky com `LazyVStack(pinnedViews: .sectionHeaders)`. |
| Scrollbar invisível até o hover | `NSScrollView.scrollerStyle = .overlay` (o padrão com trackpad já é parecido). |
| Bolinhas de status, spinner em 12 passos | `Circle().fill(...)` de 6/8 pt. Spinner: arco com `trim(0, 0.75)` e `stroke(lineWidth: 2)` amarelo, rotação via `TimelineView(.periodic(by: 1/12))` em incrementos de 30°; checar `accessibilityReduceMotion`. |
| Tab bar de 32 px com tabs de 180/220 (mín. 72) | View própria em SwiftUI (`ScrollView(.horizontal)` + `HStack(spacing:0)`); **não** usar `NSTabView` nem window tabbing. Tab ativa com fundo `fg` 6% e barra inferior de 2 pt. Fechar só no hover nas inativas. Reordenar com `.draggable`/`.dropDestination` (ou `NSDraggingSource` se precisar de split por borda). Clique do meio via `NSEvent` monitor. |
| "+" com menu omnibox | `Button` + `.popover` customizado (não `Menu`, porque precisa de campo de busca). Itens de 12 px, raio 8. |
| "▷ Command" | `Button` com `Image(systemName:"play")` de 14 pt e texto de 12/500 muted, altura 28. Vira split button com `Menu` quando houver comandos. |
| Terminal xterm full-bleed | Engine nativa já existente no Agent Box (SwiftTerm/Ghostty-lib), sem moldura, padding 4, SF Mono 14 peso medium, line-height 1.0, tema Ghostty Default Style Dark (§1.2). Pane inativo com `alphaValue 0.9`. |
| Splits de terminal (divisor 3 px `#3f3f46`, hit 9 px) | `NSSplitView` aninhado com subclasse que sobrescreve `dividerThickness = 3` e `drawDivider(in:)`, e aumenta a área de clique via `splitView(_:effectiveRect:…)`. Ou árvore própria em SwiftUI com `DragGesture`. |
| Header do pane (24 px, ícones no canto) | Overlay `.overlay(alignment: .topTrailing)` com botões de 24 pt e ícones de 12 pt; aparecem com `.onHover` e opacidade animada em 120 ms. |
| Status bar de 24 px | `HStack` de 24 pt na base da janela, fundo `card`, `Divider` no topo, texto de 12 px. Opcional e escondível. |
| Dialog (512, raio 10, overlay `black/55`) | **Overlay SwiftUI dentro da janela** (`ZStack` com scrim `Color.black.opacity(0.55)`, cartão `#171717` a 96%, borda `white/14`, sombra 0/24/72 a 55%), com transição `.opacity.combined(with: .scale(0.95))` de 200 ms. Evitar `.sheet` nativo (desce do topo e tem outro visual). Esc fecha; ⌘↵ submete via `.keyboardShortcut(.return, modifiers: .command)`. |
| Dropdown / context menu (raio 11, blur) | `NSMenu` nativo para menus de contexto (o comportamento nativo vale mais que o pixel e já é escuro e translúcido). Para popovers ricos (agent picker, filtros): `.popover` ou `NSPanel` com `NSVisualEffectView(.menu)` e raio 11. |
| Tooltip invertido | `.help()` nativo é suficiente. Fidelidade total exigiria um `NSPanel` próprio (opcional). |
| Command palette ⌘J (900 px, topo 64) | `NSPanel` não-ativável (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`) ou overlay SwiftUI ancorado a 64 pt do topo. Input de 48 pt, lista navegável por ↑↓ e `ScrollViewReader`. |
| Toasts (sonner) | Overlay SwiftUI no canto inferior direito, cartão de 360 px, empilhado, saída em 150 ms. |
| Notificações do sistema | `UNUserNotificationCenter` com título `"{repo} / {worktree} - {Agent} {status}"`, suprimidas quando a janela é key e o worktree está ativo. Clique → `userInfo` com IDs de worktree e pane. Som via `UNNotificationSound` ou `NSSound`. Badge: `NSApp.dockTile.badgeLabel` (melhor que o tray do Orca, que é o que a doc promete). |
| Fonte Geist | Embutir `Geist-Variable` (OFL) no bundle (`ATSApplicationFontsPath`) e usar `Font.custom("Geist", size:)` com tracking +0.01em (−0.025em na nav). Alternativa aceitável: SF Pro (`.system`), que muda pouco a densidade. |
| Ícones lucide | Opção A: exportar os ~40 SVGs usados (PanelLeft, PanelRight, ArrowLeft/Right, Search, List, CalendarClock, Smartphone, Bell, SlidersHorizontal, FolderPlus, Plus, ChevronDown, Ellipsis, Star, Trash2, GitBranch, GitMerge, AlertCircle, X, Play, SquareSplitVertical, SquareTerminal, MessageSquarePlus, Files, ListChecks, Plug, Kanban, Crosshair, MessageCircleQuestion, CircleCheck, Activity, Moon, Pin, Globe, TerminalSquare, Settings2, ChevronsUpDown) como template images em Assets com stroke ajustado. Opção B: SF Symbols equivalentes (sidebar.left, sidebar.right, magnifyingglass, bell, slider.horizontal.3, folder.badge.plus, plus, …). **Recomendo A** para a sidebar e a tab bar, onde a semelhança com o Orca é mais visível. |
| Logos de agentes | Claude (`#D97757`), Codex e OpenCode em `design/assets/brands/` (PNG). Converter para PDF/SVG vetorial em Assets. |
| Tokens | `enum Theme` com `Color(hex:)` para cada token de §1.1. Opacidades `fg/x` como `Color.white.opacity(x)` sobre a superfície. Modo claro opcional (os tokens claros já estão em §1.1). |
| Movimento | `Animation.easeOut(duration: 0.18)` para disclosure (aproximação de `cubic-bezier(0.16,1,0.3,1)`: `.timingCurve(0.16,1,0.3,1,duration:0.18)`), `.easeInOut(0.2)` para sidebar, `.linear(0.1–0.15)` para hovers. Tudo condicionado a `accessibilityReduceMotion`. |
| Criar sessão → terminal abre sozinho | Fluxo do composer (§5.2): ao confirmar, fechar o modal, inserir a linha pendente na sidebar, criar o worktree em background (`Task`) e, ao concluir, abrir uma tab cujo processo já é `claude …` no cwd do worktree. Sem tela intermediária. |

Pontos de atenção:
1. Medir semáforos e faixas lado a lado com o Orca em screenshots com o mesmo zoom.
2. O Orca tem **dois níveis de cinza** no escuro (sidebar `#2a2a2a` mais clara que o canvas `#0a0a0a` e a tab bar `#171717`). Isso é essencial para o visual "Orca".
3. As bordas são **sempre 7% de branco**, nunca cinza sólido.

---

## 8. Checklist de fidelidade (para QA visual)

- [ ] Semáforos centrados em y = 18, com o primeiro em x = 16. Faixa de 36 px.
- [ ] Sidebar de 280 px com fundo `#2a2a2a` e divisor `white/7`.
- [ ] Search e nav com 13 px/500, ícones de 16 px a 30% e altura ≈ 32 px.
- [ ] "Projects" em 12/600 muted, com 4 ícones ghost de 24 px.
- [ ] Card do worktree: nome 13 px, branch 11 px, badges de 16 px/10 px, linhas de agente de 24 px com tempo de 10 px.
- [ ] Tab row de 32 px em `#171717`, tabs de 180 px, ativa com barra de 2 px.
- [ ] Terminal SF Mono 14 sobre `#282c34`, sem moldura.
- [ ] Nenhum gradiente, glow, sombra em cards de lista ou label uppercase decorativo na área de trabalho.
- [ ] Hovers em ≤ 150 ms e disclosure em 180 ms.

---

## 9. Design anterior (`design/`): o que reaproveitar

Inventário:
- `index.html`: protótipo web v0.4 (Manrope, PT-BR).
- `docs/spec.html`: spec em 19 capítulos; o cap. 14 tem tokens e motion.
- `docs/review.html`.
- `screens/01–16`: Agora, Terminal+desktop, Human control, Trocar CLI, Boxes/Profiles, Memória, Resultados, Clientes locais, Nova sessão, Atividade, Evidência, Novo perfil, Biblioteca de agentes, Memória IA, Hover preview, Histórico.
- `motion/`: walkthrough de 24 s, loop do símbolo, `timeline.html`.
- `source/`: `AgentBox.swift`, `Agents.swift`, `TerminalViews.swift`, `MotionAssetView.swift`.
- `assets/brands/`: logos oficiais em PNG com proveniência em `sources.json`.

**Reaproveitar:**
1. **Logos de marca** de `design/assets/brands/` (claude, claude-code-wordmark, codex, opencode, docker) e a regra "só logo oficial, sem sombra/glow".
2. **Abordagem da janela** (título oculto, titlebar transparente) em `source/AgentBox.swift` (por volta das linhas 146 e 322). Só ajustar a posição dos semáforos para os valores de §7 e parar de desenhá-los à mão (o design antigo desenha círculos de 10 px no conteúdo; usar os botões nativos).
3. **Tabela de movimento** do spec (cap. 14): fades de 160–200 ms, sheet com escala 0.98, spring de hover peek, "sem progresso falso", fallback de Reduce Motion. Ela é compatível com §1.5.
4. **Conceitos de fluxo e copy:**
   - `SessionLauncher` (cliente/Shell → Folder/Worktree/Detached → Docker opcional, tela 09). Mapeia bem no composer do Orca: Project / Create From / Agent / Advanced.
   - Handoff de CLI (tela 04).
   - Clientes locais com status de login (tela 08).
   - Fila "needs action" (tela 10). Equivale ao feed do sino.
   - Hover preview de sessão (tela 15). Equivale ao hover card do worktree.
5. **Semântica de cor:** âmbar = precisa de humano, vermelho suave = erro. Reaproveitável, mas **trocar os valores** pelos do Orca (§1.1), porque o Orca separa amarelo working, laranja needs-input, âmbar unread e verde done.
6. `MotionAssetView.swift` só se ainda houver algum asset em loop.

**Descartar:**
- Dashboard "Agora" e thumbnails grandes (telas 01/15 como página principal). O Orca abre direto no terminal.
- Cards grandes, padding de 15–28 px, raios de 14–18 em cards e modais com sombra de raio 50, grade de biblioteca de agentes (tela 13). A densidade do Orca é de linhas com 24–32 px e raios de 4–10.
- Desktop/browser falsos em tema claro (`DesktopView`, `LiveSurface`) e ilustrações de demo.
- Telas de pesquisa/scraping (Profiles, Results, Evidence, Memory) como telas de primeiro nível. Se ficarem, que virem abas do painel direito.
- O símbolo "BoxMark" e os avatares de letra em quadrados coloridos: usar os logos reais com status dot.
- Labels uppercase espaçados e headers com título + subtítulo em todo modal.
- Fonte Manrope: usar Geist (como o Orca) ou SF.
- Tokens antigos (`#151517`/`#19191B`/`#1E1E21`, accent `#CDD5EA`): substituir pela tabela §1.1. São próximos, mas a hierarquia de superfícies do Orca é outra: canvas mais escuro e sidebar mais clara.

---

## 10. Arquivos-chave no código do Orca (para consulta durante a implementação)

Caminhos relativos a `orca-src/` no scratchpad:

- **Tokens e CSS:** `src/renderer/src/assets/main.css` (tokens em 169-462; titlebar em 1004-1277; sidebar/cards em 1451-1870; animações em 1783-2160), `assets/terminal.css`.
- **Janela:** `src/main/window/createMainWindow.ts`, `src/main/window/main-window-visual-lifecycle.ts`.
- **Chrome:** `src/renderer/src/app-shell/TitlebarLeftControls.tsx`, `TitlebarMainStrip.tsx`, `AppWorkspaceShell.tsx`.
- **Sidebar:** `components/sidebar/index.tsx`, `SidebarNav.tsx`, `SidebarHeader.tsx`, `worktree-card-*.tsx`, `worktree-list/rows/SectionHeader.tsx`, `StatusIndicator.tsx`, `AgentStateDot.tsx`, `AgentWorkingSpinner.tsx`.
- **Tabs:** `components/tab-group/TabGroupPanel.tsx`, `components/tab-bar/SortableTab.tsx`, `tab-width-rules.ts`, `TabBarQuickCommandsButton.tsx`.
- **Composer:** `components/NewWorkspaceComposerModal.tsx`, `NewWorkspaceComposerCard.tsx`, `components/new-workspace/*`, `components/agent/AgentCombobox.tsx`.
- **Palette:** `components/WorktreeJumpPalette.tsx`, `components/cmd-j/*`, `components/QuickOpen.tsx`.
- **Primitivos:** `components/ui/{button,dialog,dropdown-menu,tooltip,badge,command}.tsx`.
- **Agentes e ícones:** `lib/agent-catalog*.ts(x)`, `lib/agent-icon-glyphs.tsx`, `src/shared/agent-icons/*.png`.
- **Notificações:** `src/main/notifications/notification-delivery-service.ts`, `src/main/ipc/notification-options.ts`.
- **Atalhos:** `src/shared/keybindings/definitions-core-*.ts`.
