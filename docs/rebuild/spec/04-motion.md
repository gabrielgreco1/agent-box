# 04 · Motion

Spec de rebuild do Agent Box · capítulo de animação · 2026-10-16
**Revisado após R1–R3 em 2026-10-16** (patches de `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`; registro em `review/E-04-changelog.md`).
Decisão de origem: **P8** (`00-decisions.md`). Também valem: P1 (UI no estilo Orca), P2 (texto de UI em inglês), P4 (reattach), P5/P6 (computadores), P9 (sessão abre agente), P10/P11 (sessões limpas, seção "Sessions"), P14 (aprovação visual pelo dono), P15 ("Computer" na UI; ⌘Q com overlay), P16 (conflitos resolvidos pelos revisores), T3 (macOS 15, Swift 6), T5 (overlays na janela, nunca `.sheet`), T6 (SwiftTerm com Metal), T8 (noVNC), T10 (estados por hooks), T13 (`agentbox ctl` + `accessibilityIdentifier`).
Base: `audit/06-motion.md` (proposta original), `audit/04-orca-reference.md`, `audit/07-review-ui.md` (correções), código do Orca 1.4.219 (renderer, só leitura; os caminhos citados são relativos a `src/renderer/src` e passam a vir do pacote de referência versionado `docs/rebuild/reference/orca-1.4.219/` proposto em R3 F0-3, nunca de um scratchpad) e a skill `motion-designer` do dono (`~/.claude/skills/motion-designer`).

Toda string entre aspas que aparece na tela está em inglês. O resto do texto está em português. Microcopy, atalhos e `accessibilityIdentifier` **não são definidos aqui**: este capítulo cita os de `03-screens.md` (§21 atalhos, §22 IDs, telas) e a convenção de `02-design-system.md` §17. Se um texto citado aqui divergir de 03, vale 03. Toda referência à auditoria leva o prefixo `audit/NN` (R1 X-21).

### Correspondência de IDs: auditoria 06 → este capítulo

Os capítulos 02 e 03 citavam os IDs da auditoria (`A1…F6`, `E0…E4`, e em 03 uma forma com prefixo `M` e dois-pontos. Eles foram substituídos pelos IDs `M-xxx` abaixo (R1 §4). A tabela fica só para referência histórica; nenhum capítulo deve citar o ID antigo. Atenção: a auditoria usa `D1…D13` no inventário (§1.2) e `D1…D9` no catálogo (§4.D); a coluna abaixo usa o catálogo.

| audit/06 | Momento | 04 |
|---|---|---|
| A1 | Abrir o app | M-001 (+ M-002 processo morto) |
| A2 | Primeira execução / onboarding | M-004 |
| A3 | Estado vazio sem sessões | M-901 |
| B1 | Criar sessão (linha nasce) | M-204 (+ M-501 no lançamento pelo composer) |
| B2 | Trocar de sessão | M-203 |
| B3 | Expandir/recolher sessão ou subagentes | M-206 (em formulário: M-111) |
| B4 | Filtrar (busca) | M-207 |
| B5 | Renomear | M-208 |
| B6 | Fechar/remover sessão | M-209 |
| B7 | Hover em linha + peek | M-210 (peek: M-107) |
| B8 | Recolher sidebar | M-201 |
| B9 | Arrastar divisor | M-202 |
| C1 | Abrir tab | M-301 (troca de tab ativa: M-304) |
| C2 | Fechar tab | M-302 |
| C3 | Reordenar tab | M-303 |
| C4 | Split | M-306 |
| C5 | Fechar pane | M-307 |
| C6 | Focar/localizar pane (rim flash) | M-309 (revelar card: M-211) |
| C7 | Janela estreita | sem equivalente (o estado "Pane estreito" de 03 §4.6 não anima) |
| C8 | Toast | M-110 |
| C9 | Overlays/painéis | M-101 / M-102 / M-103 (palette: M-104) |
| C10 | Painéis laterais | M-108 |
| C11 | Alertas destrutivos | M-103 |
| C12 | Popovers (Git, tooltips) | M-105 (menus/popovers), M-106 (tooltip), M-107 (hover card) |
| D1 | Press | M-801 |
| D2 | Hover de botão/ícone | M-802 |
| D3 | Hover de card da Biblioteca | sem equivalente (02 §15 proíbe grade de cards) |
| D4 | Erro inline | M-808 |
| D5 | Terminal falhou ao iniciar | M-313 |
| D6 | Processo encerrou | M-312 |
| D7 | Estados vazios | M-901 / M-905 |
| D8 | Contadores | M-810 (badge de atenção: M-701) |
| D9 | Loading de listas (skeleton) | M-812 (viewer conectando: M-603) |
| E0 | Pré-requisito de dados | §7.2.2 (`LaunchProgress`) e M-408 |
| E1 | Indicador de estado do agente | M-401…M-408, M-404b (`working` M-401, `waiting` M-402, `done` M-403, `failed`/`blocked` M-404, `interrupted` M-404b) |
| E2 | Ignição | M-501…M-506 (placeholder: M-503; pular: M-506) |
| E3 | Subagente com Docker | M-213 (linha filha), M-507, M-601 (glifo), M-602 (fila), M-613 (parou) |
| E4 | Computador usado × takeover | M-604…M-611 |
| F1 | Abrir Biblioteca | M-109 |
| F2 | Card → detalhe | M-112 |
| F3 | Tabs internas | M-113 (segmented de 02 §12.12 também) |
| F4 | Salvar | M-809 |
| F5 | Configurações | M-109 |
| F6 | Inbox | M-705 |

---

## 0. Resumo

- O motion do Agent Box serve para **mostrar estado real**: o que está sendo lançado, quem está trabalhando, quem precisa de você e quem está pilotando um computador. Decoração e atividade fingida estão proibidas.
- A base é o Orca: 150–200 ms para quase tudo, deslocamentos de 2–8 pt, um spinner único a 12 passos/s sincronizado entre instâncias, e Reduce Motion com fallback desenhado. Os números divergentes da auditoria foram conferidos no código do Orca (§2).
- Os tokens ficam em um arquivo só, `design/motion/tokens.json`. Ele gera `MotionTokens.generated.swift` para o app e `tokens.js` para os protótipos HTML. O vídeo do protótipo e o app usam as mesmas curvas e springs.
- O terminal **nunca anima geometria**. Cada transição faz no máximo um resize do PTY, sempre no início. Loops infinitos rodam em Core Animation a ≤ 30 fps (spinner a 12) e param quando não estão visíveis.
- O catálogo (§6) tem um ID estável `M-xxx` por momento animado. Os três momentos obrigatórios de P8 estão descritos quadro a quadro em §7: **abrir telas** (M-101, M-108, M-109), **agente sendo lançado** (M-501…M-506) e **computador em uso** (M-604…M-609).
- **Os três momentos não cabem todos na Fatia 1** (R3 §4.1). Abrir telas e lançamento são da Fatia 1; "computador em uso" depende de Docker, viewer e `ControlBroker` e só fica `verified` na Fatia 3 (modo leve) e na v1.1 (isolado). O storyboard e o port no Motion Lab com dados simulados podem andar antes. A tabela de fatias por momento está em §12.2.
- Workflow (§9): beat sheet → HTML com `tokens.js` → render Playwright quadro a quadro (60 fps, sem motion blur) → o dono revisa o **vídeo** → port para SwiftUI/Core Animation → comparação lado a lado no **Motion Lab** (§10). O aceite (§11) combina gravações, Instruments, contagem de resizes do PTY e testes automatizados de ordem e duração dos eventos de motion.

---

## 1. Princípios

1. **Motion é estado.** Um elemento se move porque algo real mudou ou está acontecendo: um processo iniciando, um agente trabalhando, uma troca de controle. Não existe loop "para dar vida". Se o estado é desconhecido, o indicador fica parado e diz isso (M-407).
2. **Só "working" gira.** Entre os estados de agente, apenas `working` tem loop. `needs input` chama atenção com dois ripples e para. `done`, `failed`, `idle` e `waiting on subagents` são estáticos.
3. **Um movimento principal por vez** (skill, `craft.md` §3). Numa mesma área, a saída termina antes da entrada. Nunca há duas coreografias competindo pelo olho.
4. **Origem motivada.** O que abre a partir de um botão nasce do botão. O que é lançado viaja até onde vai morar (chip → linha da sidebar/tab). O controle do computador "entra" ou "sai" pela borda do viewer.
5. **Pequeno e rápido.** Deslocamentos de 2–8 pt, nunca a altura da view. Interações diretas duram ≤ 200 ms. Nada de UI direta passa de 500 ms; sequências longas são feitas de passos curtos encadeados a eventos reais. Se o olho precisa perseguir o movimento, está rápido demais.
6. **A saída é mais curta que a entrada** (cerca de 70–75%) e usa ease-in. Quem sai não chama atenção.
7. **O terminal é sagrado.** Nenhuma animação muda o frame do terminal quadro a quadro. Opacidade de container é permitida porque é só composição. O resize acontece uma vez, no início da transição, para que o redesenho do TUI fique escondido sob o movimento (§4).
8. **Input nunca espera animação.** Toda transição pode ser interrompida e redirecionada (springs do SwiftUI retargetam; CA parte do `presentation()`). Navegação por teclado repetível (↑↓ em listas, ⌃Tab, ⌘1…9, ⌃1…9) é instantânea ou ≤ 80 ms. O foco volta ao terminal no **início** da saída de um overlay, não no fim.
9. **Sem progresso falso.** Spinners aparecem só depois de 150 ms. Cada passo de checklist corresponde a um evento real do core e fica visível por pelo menos 120 ms (fila visual, sem atrasar o processo). Percentuais só existem quando o core reporta bytes ou etapas.
10. **Reduce Motion tem desenho próprio.** Ele não desliga tudo: movimento vira crossfade de 150 ms, loop vira estado estático legível, ripple vira troca de cor. Cor, ícone e texto de estado nunca dependem de movimento (§5).
11. **Mesmos números no protótipo e no app.** Nenhuma duração, curva ou spring é escrita à mão no Swift ou no HTML. Tudo sai de `tokens.json` (§3).

---

## 2. Divergências resolvidas (audit/06 × audit/04 × código do Orca)

O `audit/07` (correção 5) apontou números inconsistentes. Conferi cada um no código do Orca (renderer da 1.4.219). A coluna "Decisão" vale para este capítulo e substitui `audit/06` onde houver conflito.

| Tema | audit/06 dizia | audit/04 dizia | Código do Orca (verificado) | Decisão |
|---|---|---|---|---|
| Scrim de dialog | 0,45 | `black/55` + blur 2 px | `bg-black/55 backdrop-blur-[2px]`, fade sem duração própria → padrão do tw-animate, 150 ms `ease` (`components/ui/dialog.tsx:41`) | `opacity.scrim = 0.55`, fade 150 ms. Blur de 2 pt **desligado na v1** (custo sobre o terminal Metal); ligar só se o Instruments mostrar < 1 ms de GPU por quadro (§4 R8) |
| Escala de entrada do dialog | 0,96 | 0,95 | `zoom-in-95` / `zoom-out-95`, `duration-200` para abrir e fechar (`dialog.tsx:115`) | Entrada 0,95 → 1 em 200 ms. Saída 1 → 0,98 em 150 ms (regra 6; o Orca fecha em 200) |
| Duração do dialog | 150 ms ("diálogos/menus") | 200 ms | Dialog 200 ms; menus 150 ms | Dialog 200; menus 150 |
| Menus e context menu | zoom 95, 150 ms | fade + zoom 98 + 8 px | Abre `duration-150 zoom-in-[0.98]` + `slide-in-from-*-2` (8 px); fecha `zoom-out-95` (`dropdown-menu.tsx:36`, `context-menu.tsx:62`) | Menus custom: abre 150 ms, escala 0,98, 8 pt do lado da âncora; fecha 120 ms só com fade (a escala 0,95 na saída do Orca chama atenção demais). Menus nativos (`NSMenu`) não são animados por nós |
| Popover | — | — | `zoom-in-95`, padrão 150 ms (`popover.tsx:174`) | 150 ms, escala 0,95, 8 pt |
| Tooltip (atraso) | — | "~700 ms Radix" | Provider global 400 ms (`App.tsx:92`); tabs 500 (`TabStripTooltipProvider.tsx:13`); ✕ da tab 1000 (audit/07); bolinha de estado 200 (`StateIndicatorTooltip.tsx:4`) | `delay.tooltip` 0,40 / `tooltipTab` 0,50 / `tooltipTabClose` 1,00 / `tooltipStateDot` 0,20. Animação: fade + escala 0,95 + 8 pt, 150 ms |
| Hover card (peek) | 350 ms | — | Abre em 250, fecha em 120 (`sidebar/WorktreeCardMeta.tsx:74-75`); card de tab abre instantâneo se outro já está aberto (audit/07 item 36) | 250 / 120; troca entre cards já abertos sem atraso nem animação de entrada |
| Spinner working | 0,9 s contínuo, 24–30 fps | 1 volta/s, 12 passos | `rotate(86400turn)` em `86400s steps(1036800)` = **1 volta/s em 12 passos (30° cada)**; fase zerada no `animationstart` de toda instância (`AgentWorkingSpinner.tsx`, `main.css:1792-1806`); Reduce Motion = anel completo | 1,0 s por volta, 12 passos discretos, fase global sincronizada. Anel 2 pt `yellow-500` com topo transparente. Reduce Motion: anel completo parado |
| Rim flash do pane | 1,5 s, 1 → 0,42 → 0 | — | `pane-focus-rim-flash` 1,5 s `ease-out`: opacidade 1 → 0,42 (24%) → 0 (46%) → 0; borda 1,5 px a 68%, anel 2 px a 34%, glow 18 px a 36% em `--terminal-pane-locate` = `blue-400` no escuro (`terminal.css:165-206`, `main.css:345`) | Igual ao Orca |
| Glow ao revelar workspace | escala 0,992 → 1 → 1,006 + fade | — | 1,5 s `ease-out`: (0%: 1, 0,992) (24%: 0,72, 1) (60%: 0,28, 1,006) (100%: 0, 1,006); borda 1,5 px, anel 1 px, glow 14 px (`main.css:1940-1987`) | Igual ao Orca |
| Sidebar recolher | 0,30 s `sheet`, resize no fim | 200 ms `ease` | `.sidebar { transition: width 200ms ease }` (`main.css:1451`) | 220 ms com curva `drawer`, sidebar desliza como camada, **um** resize do terminal no início (§4 R2). O Orca anima a largura porque no DOM isso é barato; para nós, cada quadro seria um SIGWINCH |
| Opacidade de pane inativo | — | 0,9, 140 ms | Padrão 0,9 (`shared/constants.ts:42`), transição 140 ms `ease` (`default-global-settings.ts:90`, `pane-divider.ts:81`). A config do dono usa **0,8** (audit/07, correção 3) | 0,8, 140 ms `ease` |
| Painel lateral (kanban) | 300 ms `expoOut` / 200 ms `(.7,0,.84,0)` | — | Confirmado (`main.css:2083-2091`) | Igual, para painéis acoplados (M-108) |
| Expansão de agentes no card | 180 ms `expoOut` | 180 ms | `compact-agent-expansion-reveal` 180 ms `(.16,1,.3,1)`, `translateY(-2px)` (`main.css:1809-1822`) | Igual |
| Collapsible | 200 / 180 ms | 200 / 180 ms | `collapsible-down` 200 ms / `up` 180 ms `ease-out` (`main.css:2035-2039`) | Igual |
| Settings | 180 ms, 8 px | 180 ms | `settings-shell-enter` 180 ms `ease-out`, 8 px (`main.css:1990-2003`) | Igual |
| Toast | 12 pt de subida | saída 150 ms | O Orca usa sonner (padrão da biblioteca, ~400 ms; não está no repo). `update-card` entra 200 ms `ease-out` de `translateX(100%)` e sai 150 ms `ease-in` só com fade (`main.css:2587-2623`) | Entrada 200 ms, `y +12 → 0` + fade; saída 150 ms só com fade |
| Ripple de clique | 0,46 s, 0,4 → 1,4 | — | `feature-wall-click-ring` 460 ms `ease-out`, escala 0,4 → 1,4, opacidade 0,9 → 0 (`main.css:2788-2802`) | Igual (cursor fantasma, M-605) |
| Anel de atenção | 1,8 s, 0,68 → 2,4 | — | `contextual-tour-target-ring` 1,8 s `ease-out` **infinito**, 0,72 → 0 em 72% (`main.css:2993-3005`) | Mesmo desenho, mas **2 ciclos e para** |
| "Conteúdo entrando" 320–380 ms `(.2,.8,.2,1)` | Tratado como padrão do Orca | — | `browserTabIn`, `browserViewIn`, `md-block-in` e `tasks-workspace-in` existem só em `components/feature-wall/` (storyboards de marketing), não na UI de produto | A curva `standard (.2,.8,.2,1)` fica como token nosso. A duração de UI direta cai para 200 ms; 320+ ms só em revelações (M-503) |
| Cor de "working" | Cor do provider (Claude laranja) | `yellow-500` | `border-yellow-500` (`AgentWorkingSpinner.tsx`) | `yellow-500` para todos os providers; a identidade do provider fica no logo, não no spinner |
| Abrir o app (M-001) | Terminais restaurados em "Pronto para iniciar" | — | — (audit/07, correção 6) | Reanexação com buffer já preenchido; processo morto = estado `Interrupted` de 03 §4.6 (scrollback a 50% + banner com "Resume" / "Start Fresh" / "Close") (M-001, M-002) |

Também revisei duas regras de `audit/06`:
- **Curva de saída.** `(.7,0,.84,0)` tem 2% de progresso aos 60 ms e 47% aos 133 ms (de 150 ms): parece atraso seguido de corte. Ela fica restrita ao fechamento de painel por recorte (`exitClip`). Fades de saída usam `exit = (.42,0,1,1)` (o `ease-in` do CSS, que o Orca usa no `update-card-exit`).
- **Resize no fim versus no início.** `audit/06` fazia o resize no fim ao recolher e no início ao expandir. Aqui é **sempre no início**: o redesenho do TUI (dezenas de ms no Claude Code) acontece sob a camada que se move, não depois que o olho já parou.

---

## 3. Tokens de motion

### 3.1 Fonte única e geração

- Arquivo canônico: `design/motion/tokens.json` (versionado, revisado como código).
- Gerador: `scripts/motion/gen_tokens.py` (Python stdlib) produz:
  - `MotionTokens.generated.swift`, no alvo `AgentBoxDesignSystem` de `Packages/AgentBoxKit` (nome fixado em 08, AR-121; pasta `AgentBoxDesignSystem/Tokens/`, a mesma dos tokens de 02);
  - `design/motion/lib/tokens.js` com `window.MOTION = {...}`. Ele existe porque `fetch()` de `file://` é bloqueado no render da skill (`pipeline.md`, "Gotchas").
- O CI roda o gerador e falha se os arquivos gerados diferirem do commit.
- Nenhum `Animation.easeOut(duration:)`, `timingCurve(...)` ou `spring(...)` literal fora de `Motion.swift`. Uma regra de lint (SwiftLint custom rule ou `grep` no CI) bloqueia literais de animação em views.

### 3.2 Durações (segundos)

| Token | s | Uso |
|---|---|---|
| `press` | 0,08 | escala de botão pressionado; saída de conteúdo na troca de sessão |
| `hover` | 0,12 | fundo/cor no hover, troca de cor de estado, aparecimento de botões do header do pane |
| `fast` | 0,15 | menus, popovers, tooltips, scrim, saídas de dialog, crossfade de Reduce Motion |
| `paneOpacity` | 0,14 | opacidade de pane ativo/inativo |
| `base` | 0,20 | dialogs, tabs, toasts, conteúdo entrando, collapsible |
| `disclosure` | 0,18 | expandir agentes no card, recolher collapsible, troca de seção de settings |
| `drawer` | 0,22 | sidebar esquerda recolher/expandir |
| `medium` | 0,24 | desenho de check, troca de pill, morph de estado |
| `panel` | 0,30 | painel lateral (recorte), passos de onboarding, banner do viewer |
| `handoff` | 0,36 | troca de controle do computador |
| `flight` | 0,42 | voo do chip de lançamento |
| `ripple` | 0,46 | ripple de clique e de pouso |
| `flash` | 1,50 | rim flash, glow de revelação |
| `attention` | 1,80 | um ciclo do anel de atenção |

### 3.3 Curvas (cubic-bezier)

| Token | Pontos | Origem | Uso |
|---|---|---|---|
| `standard` | (0,2, 0,8, 0,2, 1) | Orca (feature-wall) | conteúdo entrando, dialog, tab, chip (eixo x) |
| `expoOut` | (0,16, 1, 0,3, 1) | Orca (kanban, disclosure) | revelações, painel lateral, handoff, checks |
| `drawer` | (0,32, 0,72, 0, 1) | Orca (revelação longa) | sidebar, banner, scroll até item |
| `exit` | (0,42, 0, 1, 1) | CSS `ease-in` (Orca `update-card-exit`) | fades e escalas de saída |
| `exitClip` | (0,7, 0, 0,84, 0) | Orca (kanban fecha) | só fechamento de painel por recorte |
| `ease` | (0,25, 0,1, 0,25, 1) | CSS `ease` (padrão tw-animate) | scrim, opacidade de pane, hover |
| `cssEaseOut` | (0, 0, 0,58, 1) | CSS `ease-out` | rim flash, glow, settings, collapsible |
| `twEaseOut` | (0, 0, 0,2, 1) | Tailwind `ease-out` | barras de progresso, contadores |
| `inOut` | (0,4, 0, 0,2, 1) | Tailwind padrão | respiração (loop ida e volta) |
| `linear` | (0, 0, 1, 1) | — | rotações, marching ants, shimmer |

Progresso a 60 fps, para conferir protótipo e app quadro a quadro:
- `standard` 200 ms: f2 0,61 · f4 0,86 · f6 0,95 · f8 0,98 · f12 1,00
- `expoOut` 300 ms: f2 0,53 · f4 0,79 · f6 0,90 · f8 0,96 · f12 0,99
- `exit` 150 ms: f2 0,08 · f4 0,26 · f6 0,51 · f8 0,82 · f9 1,00
- `drawer` 220 ms: f2 0,47 · f4 0,85 · f6 0,94 · f8 0,98 · f13 1,00

### 3.4 Springs

SwiftUI: `.spring(response:dampingFraction:)`. Core Animation (macOS 14+): `CASpringAnimation(perceptualDuration: response, bounce: 1 − dampingFraction)`, ou explícito com `mass = 1`, `stiffness = (2π/response)²`, `damping = 2·ζ·(2π/response)`. HTML: oscilador amortecido analítico (§9.4).

| Token | response | damping | stiffness / damping (CA) | Overshoot | Assenta (0,1%) | Uso |
|---|---|---|---|---|---|---|
| `snappy` | 0,28 | 0,86 | 503,6 / 38,6 | 0,5% | 0,36 s | seleção, indicador de tab ativa, vizinhas abrindo espaço, press de volta |
| `panel` | 0,36 | 0,90 | 304,6 / 31,4 | 0,15% | 0,44 s | morph herói, mover sessão entre seções |
| `lively` | 0,40 | 0,72 | 246,7 / 22,6 | 3,8% | 0,61 s | **só** pouso do chip, nascimento de linha lançada, bump de badge, "pronto" do computador |
| `cursor` | 0,35 | 0,85 | 322,3 / 30,5 | 0,6% | 0,45 s | cursor fantasma do agente |
| `drag` | 0,22 | 0,90 | 815,7 / 51,4 | 0,15% | 0,27 s | tab solta após arrasto |

Progresso a 60 fps (para comparar quadros): `snappy` f3 0,33 · f6 0,72 · f9 0,92 · f12 0,99 · f15 1,004. `lively` f6 0,55 · f12 0,97 · f18 1,038 (pico) · f30 1,00. `cursor` f6 0,59 · f12 0,94 · f21 1,006.

### 3.5 Distâncias, escalas, opacidades, atrasos

| Grupo | Token | Valor |
|---|---|---|
| distância (pt) | `hairline` / `micro` / `small` / `medium` / `large` | 2 / 4 / 8 / 12 / 16 |
| distância | `arcLift` (altura do arco do chip) | 56 |
| escala | `dialogFrom` / `menuFrom` / `exitTo` / `press` / `dragLift` / `bump` / `tabFromX` | 0,95 / 0,98 / 0,98 / 0,97 / 1,02 / 1,15 / 0,96 |
| opacidade | `scrim` / `inactivePane` / `exitedDim` / `interruptedContent` / `reconnectFrame` / `ghostIdle` / `liveBorder` | 0,55 / 0,80 / 0,35 / 0,50 / 0,40 / 0,40 / 0,70 |
| traço (pt) | `ring` (spinner) / `focusRing` (anel de foco, DS9) / `liveBorder` / `rim` | 2 / 3 / 1,5 / 1,5 |
| stagger (s) | `list` (máx. 6 itens) / `children` / `checklistMinStep` | 0,035 / 0,06 / 0,12 |
| atraso (s) | `tooltip` / `tooltipTab` / `tooltipTabClose` / `tooltipStateDot` | 0,40 / 0,50 / 1,00 / 0,20 |
| atraso (s) | `hoverCardOpen` / `hoverCardClose` / `spinnerShow` / `ignitionSkip` / `ghostIdleAfter` / `typingHold` | 0,25 / 0,12 / 0,15 / 0,30 / 3,0 / 1,2 |

### 3.6 Loops

| Token | Período | fps máx. | Fase | Técnica |
|---|---|---|---|---|
| `spinner` | 1,0 s, 12 passos discretos de 30° | 12 | global sincronizada | `CAKeyframeAnimation` `transform.rotation.z`, `calculationMode = .discrete` |
| `breath` | 1,6 s ida e volta (`inOut`) | 24 | por instância | `CABasicAnimation` opacity, `autoreverses` |
| `liveBorder` | 3,2 s por volta (1,2 s em `revoking`) | 30 | global | rotação de `CAGradientLayer(type: .conic)` mascarado |
| `marching` | 0,8 s | 24 | global | `CAShapeLayer.lineDashPhase` |
| `shimmer` | 1,4 s | 30 | global | `CAGradientLayer` como máscara, translação |
| `halo` | 1,2 s ida e volta | 24 | por instância | escala 1 ↔ 1,04 + opacidade 0,5 ↔ 0,8 |
| `dots` | 0,9 s, 3 pontos com 0,15 de defasagem | 12 | global | opacidade discreta |

Regra de fase global: `beginTime = CACurrentMediaTime() − fmod(CACurrentMediaTime(), period)`, convertido para o tempo da layer com `layer.convertTime(_:from: nil)`. Todas as instâncias do mesmo loop ficam em fase, como no Orca.

### 3.7 `tokens.json` (conteúdo inicial)

```json
{
  "schema": "agentbox.motion.tokens",
  "version": 1,
  "duration": {
    "press": 0.08, "hover": 0.12, "paneOpacity": 0.14, "fast": 0.15,
    "disclosure": 0.18, "base": 0.20, "drawer": 0.22, "medium": 0.24,
    "panel": 0.30, "handoff": 0.36, "flight": 0.42, "ripple": 0.46,
    "flash": 1.50, "attention": 1.80
  },
  "easing": {
    "standard":   [0.2, 0.8, 0.2, 1.0],
    "expoOut":    [0.16, 1.0, 0.3, 1.0],
    "drawer":     [0.32, 0.72, 0.0, 1.0],
    "exit":       [0.42, 0.0, 1.0, 1.0],
    "exitClip":   [0.7, 0.0, 0.84, 0.0],
    "ease":       [0.25, 0.1, 0.25, 1.0],
    "cssEaseOut": [0.0, 0.0, 0.58, 1.0],
    "twEaseOut":  [0.0, 0.0, 0.2, 1.0],
    "inOut":      [0.4, 0.0, 0.2, 1.0],
    "linear":     [0.0, 0.0, 1.0, 1.0]
  },
  "spring": {
    "snappy": { "response": 0.28, "dampingFraction": 0.86 },
    "panel":  { "response": 0.36, "dampingFraction": 0.90 },
    "lively": { "response": 0.40, "dampingFraction": 0.72 },
    "cursor": { "response": 0.35, "dampingFraction": 0.85 },
    "drag":   { "response": 0.22, "dampingFraction": 0.90 }
  },
  "distance": { "hairline": 2, "micro": 4, "small": 8, "medium": 12, "large": 16, "arcLift": 56 },
  "scale": { "dialogFrom": 0.95, "menuFrom": 0.98, "exitTo": 0.98, "press": 0.97, "dragLift": 1.02, "bump": 1.15, "tabFromX": 0.96 },
  "opacity": { "scrim": 0.55, "inactivePane": 0.80, "exitedDim": 0.35, "interruptedContent": 0.50, "reconnectFrame": 0.40, "ghostIdle": 0.40, "liveBorder": 0.70 },
  "stroke": { "ring": 2.0, "focusRing": 3.0, "liveBorder": 1.5, "rim": 1.5 },
  "stagger": { "list": 0.035, "listMax": 6, "children": 0.06, "checklistMinStep": 0.12 },
  "delay": {
    "tooltip": 0.40, "tooltipTab": 0.50, "tooltipTabClose": 1.00, "tooltipStateDot": 0.20,
    "hoverCardOpen": 0.25, "hoverCardClose": 0.12, "spinnerShow": 0.15,
    "ignitionSkip": 0.30, "ghostIdleAfter": 3.0, "typingHold": 1.2
  },
  "loop": {
    "spinner":    { "period": 1.0, "steps": 12, "fps": 12, "phase": "global" },
    "breath":     { "period": 1.6, "fps": 24, "easing": "inOut", "from": 0.55, "to": 1.0, "phase": "instance" },
    "liveBorder": { "period": 3.2, "periodRevoking": 1.2, "fps": 30, "phase": "global" },
    "marching":   { "period": 0.8, "fps": 24, "dash": [3, 2], "phase": "global" },
    "shimmer":    { "period": 1.4, "fps": 30, "phase": "global" },
    "halo":       { "period": 1.2, "fps": 24, "scale": [1.0, 1.04], "opacity": [0.5, 0.8], "phase": "instance" },
    "dots":       { "period": 0.9, "fps": 12, "offset": 0.15, "phase": "global" }
  },
  "keyframes": {
    "rimFlash":     { "duration": 1.5, "easing": "cssEaseOut", "opacity": [[0, 1], [0.24, 0.42], [0.46, 0], [1, 0]] },
    "revealGlow":   { "duration": 1.5, "easing": "cssEaseOut", "opacity": [[0, 1], [0.24, 0.72], [0.6, 0.28], [1, 0]], "scale": [[0, 0.992], [0.24, 1], [0.6, 1.006], [1, 1.006]] },
    "clickRing":    { "duration": 0.46, "easing": "cssEaseOut", "scale": [0.4, 1.4], "opacity": [0.9, 0] },
    "attentionRing":{ "duration": 1.8, "easing": "cssEaseOut", "scale": [[0, 0.68], [0.72, 2.4]], "opacity": [[0, 0.72], [0.72, 0]], "repeat": 2 },
    "shake":        { "duration": 0.30, "amplitude": 6, "cycles": 3 },
    "bump":         { "spring": "lively", "scale": [1, 1.15, 1] }
  },
  "policy": {
    "loopMaxFps": 30, "loopMaxFpsLowPower": 15,
    "reducedCrossfade": 0.15,
    "maxUiDirect": 0.50
  }
}
```

### 3.8 API no Swift (gerada + escrita à mão)

```swift
// MotionTokens.generated.swift (gerado; não editar)
enum MotionTokens {
  enum Duration { static let base: Double = 0.20 /* … */ }
  enum Easing { static let standard = Bezier(0.2, 0.8, 0.2, 1.0) /* … */ }
  enum Springs { static let snappy = SpringSpec(response: 0.28, dampingFraction: 0.86) /* … */ }
  // distance, scale, opacity, stagger, delay, loop, keyframes
}

// Motion.swift (à mão, consome os tokens e a política)
enum Motion {
  static func curve(_ e: Bezier, _ d: Double) -> Animation      // .timingCurve(e.x1, e.y1, e.x2, e.y2, duration: d)
  static func spring(_ s: SpringSpec) -> Animation               // .spring(response:dampingFraction:)
  static func caTiming(_ e: Bezier) -> CAMediaTimingFunction     // controlPoints idênticos
  static func caSpring(_ s: SpringSpec) -> CASpringAnimation     // perceptualDuration/bounce
  // Atalhos semânticos usados pelas views:
  static var dialogIn: Animation   { curve(.standard, MotionTokens.Duration.base) }
  static var dialogOut: Animation  { curve(.exit, MotionTokens.Duration.fast) }
  // …um por papel, nunca por tela
}
```

`MotionPolicy` (`@Observable`, MainActor) decide em tempo de execução: `reduceMotion`, `reduceTransparency`, `windowOccluded`, `appActive`, `lowPower`, `layoutTransitionInFlight`, `mode` (`.normal | .instant | .slow(factor)` para testes e Motion Lab). Toda animação passa por `MotionPolicy.animation(for: .dialogIn)`, que já devolve o fallback quando necessário.

---

## 4. Regras de performance

| # | Regra | Como cumprir |
|---|---|---|
| R1 | **O terminal nunca anima geometria.** Nenhum `.animation`, `withAnimation` ou `matchedGeometryEffect` em ancestral do `TerminalSurface` muda o frame dele. Opacidade do container de pane é permitida (composição pura). | `TerminalSurface` hospedado num container com tamanho próprio; animações de layout acontecem em camadas irmãs. Lint: proibir `.animation(_:value:)` em views que contêm `TerminalSurface`. |
| R2 | **Um resize por transição, no início.** Mudanças de layout que alteram cols/rows aplicam o tamanho final no primeiro quadro. A camada que se move (sidebar, painel, divisor) passa por cima. Durante a transição o PTY ignora `layout()` intermediários. | `MotionPolicy.layoutTransitionInFlight = true` durante a transição; `TerminalSurface.layout()` só repassa tamanhos quando `false` ou quando o tamanho é o final declarado. O `completion` do `withAnimation` limpa a flag. |
| R3 | **Fechar algo sobre o terminal: cobrir e depois cortar.** Para remover um pane, cobre-se o pane com uma view da cor do canvas (fade 0 → 1, 120 ms). Depois o layout muda em um passo, sem snapshot do Metal (`cacheDisplay` não captura camadas Metal). | Componente `PaneCover`. |
| R4 | **Terminal entra com cobertura, não com opacidade.** No primeiro byte, uma cobertura da cor do canvas faz fade 1 → 0 em 160 ms sobre o terminal. A camada Metal nunca fica em grupo de opacidade enquanto faz streaming. | `PaneCover` reaproveitado. |
| R5 | **Loops infinitos só em Core Animation.** Nada de `TimelineView`, `repeatForever` ou `PhaseAnimator` infinito em SwiftUI: eles reavaliam o corpo no main thread. `KeyframeAnimator` e `PhaseAnimator` só em one-shots de ≤ 0,6 s. | `NSViewRepresentable` com layers; um componente por tipo de loop (§8). |
| R6 | **Loops ≤ 30 fps e spinner a 12.** Cada animação de loop define `preferredFrameRateRange` (`CAFrameRateRange(minimum: 8, maximum: fps, preferred: fps)`). O spinner usa keyframes discretos (12 commits/s), não rotação contínua. Em Low Power Mode, o teto cai para 15 fps. | Tokens `loop.*.fps` e `policy.loopMaxFpsLowPower`. |
| R7 | **Pausar fora de vista.** Loops param (`layer.speed = 0`, guardando `timeOffset`) quando a janela está ocluída (`NSWindow.occlusionState`), a view sai da janela ou fica oculta (`viewDidMoveToWindow`, `isHiddenOrHasHiddenAncestor`), a linha sai da área visível da sidebar (`onDisappear` da `LazyVStack`) ou a sessão não está selecionada. Com o app inativo, loops decorativos (halo, shimmer, liveBorder) param; spinners visíveis continuam. Ao retomar, a fase é recalculada pela regra global, sem "pulo" de catch-up. | `LoopHost` central que observa `MotionPolicy` e registra cada layer em loop. |
| R8 | **Sem blur nem sombra animada sobre texto em streaming.** Glow do rim flash e borda viva são layers sem `shadowPath` dinâmico. O blur do scrim fica desligado na v1 (§2). | Revisão de código + Instruments (GPU). |
| R9 | **Folhas animadas isoladas.** Estado de animação vive em modelos `@Observable` por linha, tab e pane. Um badge pulsando não invalida o pane do terminal nem a lista inteira. | Arquitetura de views (02 §16 e 08); verificar com o instrumento SwiftUI (contagem de body updates). |
| R10 | **Nenhuma transição bloqueia input.** Teclas digitadas durante qualquer animação chegam ao destino. O foco volta ao terminal no primeiro quadro da saída do overlay. | Teste XCUITest de digitação durante M-102 (§11). |
| R11 | **Frames do stream do computador nunca são interpolados.** Troca imediata, a menos que o fps caia abaixo de 4: aí há crossfade de 80 ms entre frames. | `DesktopCanvasView`. |
| R12 | **Orçamento.** 0 hitches a 120 Hz durante qualquer momento de prioridade A com 4 terminais em stress (`yes \| pv -qL 2000000`). Hitch ratio < 5 ms/s como limite de reprovação. 10 spinners `working` visíveis: ≤ 2% de um núcleo no app e ≤ 3% no WindowServer. Janela ocluída: 0 commits de loop. | §11. |

---

## 5. Reduce Motion, transparência, energia e VoiceOver

Esta é a seção de Reduce Motion citada pelos outros capítulos (a referência antiga "04 §3.3" em 02 aponta para curvas; o certo é **04 §5**).

| Situação | Comportamento |
|---|---|
| `accessibilityReduceMotion` (SwiftUI) / `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (AppKit/CA, observado via `accessibilityDisplayOptionsDidChangeNotification`) | Translação, escala, voo e recorte viram **crossfade de 0,15 s** (`ease`). Loops viram estado estático: spinner = anel completo parado; respiração = cor sólida; marching ants = traço sólido; shimmer = bloco estático a 6%; borda viva = borda sólida na cor de quem controla. Ripple e anel de atenção viram troca de cor (0,15 s). Rim flash vira borda estática por 0,6 s. Contadores trocam o número sem bump. |
| Preferência do app | Settings › Appearance › `Reduce motion`: `Follow System` (padrão) · `On` (03 §14.2). O valor entra em `MotionPolicy.reduceMotion` com OR do sistema. |
| `accessibilityDisplayShouldReduceTransparency` | Sem glow nem blur; scrim sólido a 0,55; bordas sólidas. |
| Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`) | Teto de loops em 15 fps; halo e shimmer desligados (estáticos); spinner continua a 12. |
| Janela ocluída / app inativo | R7. |
| VoiceOver | Só os anúncios de 02 §14.2 (cooldown de 5 s por terminal), em inglês, ex.: "Claude Code in fix-arcgis-pagination needs input", "You're in control of phoenix-az", "Control returned to Claude Code". Motion não cria anúncio próprio. Indicadores expõem `accessibilityValue` com o label de 02 §2.6 ("Working", "Needs input", "Waiting on subagents", "Done", "Failed", "Blocked", "Interrupted", "Idle", "Status unavailable"). |
| Teclado | Nenhuma informação depende só de animação; foco visível (anel de 3 pt, DS9, token `stroke.focusRing`) aparece em 0,12 s e não anima posição. |

---

## 6. Catálogo de momentos

### 6.1 Convenções

- **ID** estável `M-xxx`, agrupado por centena: 0xx app/janela · 1xx overlays e telas · 2xx sidebar e sessões · 3xx tabs e panes · 4xx estados do agente · 5xx lançamento · 6xx computador · 7xx notificações · 8xx micro-interações · 9xx vazios e erros. IDs nunca são reaproveitados; um momento removido fica marcado "retirado".
- **Duração · curva** usa nomes de token (§3). "→" separa fases encadeadas.
- **Técnica**: SUI = SwiftUI (`transition`, `withAnimation`, `matchedGeometryEffect`, `contentTransition`) · KA = `KeyframeAnimator` · PA = `PhaseAnimator` · CA = Core Animation num `NSViewRepresentable` · AK = AppKit (`NSAnimationContext`, `NSScrollView`) · Sys = sistema.
- **RM** = fallback com Reduce Motion.
- **Test ID** = `accessibilityIdentifier` do elemento animado, **tirado da lista canônica de 03 §22** e da convenção de 02 §17 (R1 §4). Este capítulo não cria identificadores. Os poucos que 03 §22 ainda não lista estão marcados com † e devem entrar lá (pedido registrado em `review/E-04-changelog.md`). `<id>` é o identificador do domínio (sessão, terminal, computador); `<terminalId>`, `<computerId>` e `<childId>` quando a distinção importa. Todo momento também emite o evento de motion `M-xxx` com fases (`begin`, marcos nomeados, `end`) em signpost e no canal `agentbox ctl` (§11.3).
- **Prioridade e fatia** seguem §12 (§12.2 diz em que fatia cada momento fica `verified`).

### 6.2 App e janela (M-0xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-001 | Abrir o app (reattach) | Lançamento; daemon `agentboxd` responde ao handshake | sidebar: 0,20 `standard`, stagger `list` (máx. 6; o resto aparece junto com o 6º) | Linhas da sidebar: opacidade 0 → 1, y +4 → 0. Panes reanexados: buffer pintado **antes** do primeiro frame visível; `PaneCover` 1 → 0 em 0,16 só se o primeiro frame do ring buffer atrasar > 1 quadro. Indicadores começam na fase global. Janela: animação do sistema. | SUI + `PaneCover` | fade 0,15 no container da sidebar | `sidebar`, `pane.<terminalId>.cover`† |
| M-002 | Processo morreu desde a última abertura (estado `Interrupted`, 03 §4.6) | Reattach encontra o processo encerrado (reboot, crash) | 0,16 `ease` → banner 0,24 `drawer` → ações 0,20 `standard` | Opacidade do container do terminal 1 → `interruptedContent` (0,50; opacidade de container, R1 permite). Depois o banner do topo revela por recorte: "This terminal stopped while Agent Box was closed." (ou "This terminal stopped when your Mac restarted."), com os botões de 03 §4.6 ("Resume" / "Start Fresh" / "Close"; shell: "Restart" / "Close") subindo 4 pt com fade, stagger 0,035. | SUI (banner irmão) | fade | `pane.<terminalId>.interrupted`, `pane.<terminalId>.interrupted.resume` |
| M-003 | Serviço de segundo plano desconectado / reconectando | Socket do `agentboxd` cai | entrada 0,24 `drawer`; spinner M-811 | Banner `warning` no topo de cada pane revela por recorte vertical (03 §4.6 "Daemon unavailable"): "Lost connection to the background service. Reconnecting…" com spinner; o terminal fica congelado, sem esmaecer. Depois de 10 s, os botões "Restart Background Service" / "Open Diagnostics" entram com fade (0,20). Ao reconectar: banner recolhe (0,18 `exit`). O banner de janela "Background agents stopped unexpectedly" (AC-810) usa a mesma entrada. Nenhum texto de UI cita "daemon" nem "agentboxd" (R1 K-46). | SUI | banner estático, spinner parado | `pane.<terminalId>.daemonBanner`; janela: `window.daemonBanner`† |
| M-004 | Onboarding (passos) | Primeira abertura (P3) | passo novo: 0,30 `expoOut` (x +16 → 0, fade); passo antigo: 0,18 `exit` (x 0 → −8, fade) | Itens importados (projetos, worktrees, args) entram conforme são lidos: fade + 4 pt, stagger `list`; check desenhado 0,24 `expoOut`. Barra de progresso: largura em 0,30 `twEaseOut`. | SUI | crossfade entre passos | `onboarding`, `onboarding.item.<key>`, `onboarding.import.<group>` |
| M-005 | Janela fica ativa/inativa | `NSWindow` key/occlusion | — | Não anima nada. Pausa e retoma loops (R7). | — | — | — |

### 6.3 Overlays, telas e painéis (M-1xx), obrigatório nº 1

Detalhe quadro a quadro de M-101, M-108 e M-109 em §7.1.

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-101 | Overlay nasce do botão (composer "New Session", "Add a Project", "Resume interrupted agents?", confirmações; T5) | Clique no botão de origem ou atalho (⌘N etc.) | scrim 0,15 `ease`; cartão 0,20 `standard`; conteúdo 0,20 `standard` com stagger 0,035 (máx. 3 grupos) | Scrim 0 → 0,55. Cartão: opacidade 0 → 1, escala 0,95 → 1 com âncora no ponto do botão projetado na borda do cartão, translação de 12 pt na direção do botão → 0. Botão de origem mantém fundo "ativo" enquanto o dialog existe. | SUI: `OverlayPanelHost` + `anchorPreference` do botão | fade 0,15 sem escala/offset | `overlay.scrim`†, `overlay.<name>` (ex.: `overlay.composer`) |
| M-102 | Dialog fecha (Esc, Cancel, clique no scrim) | Ação de fechar | 0,15 `exit` | Cartão: opacidade 1 → 0, escala 1 → 0,98 (âncora no botão de origem). Scrim 0,55 → 0 em 0,15. Foco volta ao terminal no quadro 0. Fundo "ativo" do botão some em 0,12. | SUI | fade 0,15 | idem |
| M-103 | Overlay de confirmação (fechar terminal, apagar sessão, ⌘Q com agentes vivos) | Ação destrutiva; ⌘Q com agentes vivos (03 §16.10, P15) | igual a M-101/M-102, cartão 448 pt (DS §12.18) | Botão destrutivo entra já focado; sem stagger. O ⌘Q com agentes vivos também é overlay ("Keep Running" padrão). `NSAlert` (animação do sistema) só quando nenhuma janela está aberta e para erros fatais de inicialização (R1 K-90). | SUI | fade | `overlay.confirmClose`, `overlay.confirmDelete`, `overlay.confirm.primary` |
| M-104 | Command palette ⌘J | ⌘J | entrada 0,15 `standard`; saída 0,12 `exit` | Ancorada no topo: opacidade 0 → 1, escala 0,98 → 1, y −8 → 0. Resultados mudam **sem** animação. A seleção por ↑↓ é instantânea. | SUI | fade 0,15 | `overlay.palette` |
| M-105 | Menu custom / context menu | Clique, clique direito | entrada 0,15 `standard`; saída 0,12 `exit` | Opacidade, escala 0,98 → 1, 8 pt a partir do lado da âncora, origem na âncora. Itens sem stagger. Menus `NSMenu` nativos: sistema. | SUI | fade | `menuPanel.<name>`† (`menu.<group>.<action>` é dos menus do app, 03 §18) |
| M-106 | Tooltip | Hover após `delay.tooltip*` | 0,15 `standard`; saída 0,10 | Opacidade, escala 0,95 → 1, 8 pt do lado. Tooltip seguinte enquanto um está aberto: sem atraso e sem animação. | SUI (overlay próprio, não `.help`) | fade | `tooltip`† |
| M-107 | Hover card (peek de sessão/tab) | Hover 0,25 s | entrada `snappy`; saída 0,12 `exit` | Opacidade, escala 0,97 → 1, âncora no canto da linha/tab. Troca entre cards abertos: imediata. | SUI | fade | `<host>.hoverCard` (ex.: `sidebar.session.<id>.hoverCard`) |
| M-108 | Painel direito (Source Control, Checks, Computers, Conversations, Context; 03 §10) abre/fecha | Botão da activity bar ou atalho (⌘L, ⇧⌘G, ⇧⌘C, ⇧⌘H; 03 §21) | abre 0,30 `expoOut`; fecha 0,20 `exitClip` | Recorte `inset(0 0 0 100%) → inset(0)` a partir da borda que encosta no conteúdo. O conteúdo do painel **não** desliza. Hairline interna aparece no fim (0,12). Terminal: resize único no quadro 0 da abertura e no último quadro do fechamento (R2). | SUI (`.mask` animando largura) | fade 0,15 | `rightPanel`, `rightPanel.tab.<name>` |
| M-109 | Página do centro (Settings, Library, Computers; 03 §12–§14) entra/sai | Navegação (⌘,, ⇧⌘L, nav da sidebar). A Inbox é feed na sidebar (03 §9.1) e usa M-705 | entrada 0,18 `cssEaseOut` (y +8 → 0, fade); saída 0,08 `exit` (fade) | Sidebar e tab bar ficam paradas; só a área de conteúdo troca. Trocar de seção dentro de Settings repete a entrada. | SUI | fade 0,15 | `settings.page`, `library.page`, `computers.page` |
| M-110 | Toast | Undo, erro não bloqueante, confirmação | entrada 0,20 `standard`; saída 0,15 `exit` | Canto inferior direito, 360 pt. Entrada: y +12 → 0 + fade. Empilhamento: `snappy`. Saída: só fade. Desfazer tem barra de tempo linear (largura 1 → 0 na duração do toast). | SUI | fade | `toast.<kind>` |
| M-111 | Expansão inline em formulário ("Advanced", "Reuse existing branch") | Toggle | abre 0,20 `cssEaseOut`; fecha 0,18 `cssEaseOut` | Altura por recorte; conteúdo com y −2 → 0 e fade. Chevron 0 → 90° em 0,15 `standard`. | SUI | instantâneo | `overlay.<name>.advanced` (ex.: `overlay.composer.advanced`) |
| M-112 | Lista → detalhe (Library, 03 §13.1: lista de 320 + detalhe) | Seleção de linha (clique, ↑↓) | seleção `snappy` (clique) / instantânea (teclado); detalhe 0,20 `standard` | O fundo de seleção desliza na lista; o detalhe troca com crossfade + 4 pt, sem stagger. Sem morph herói e sem avatar: a Library é lista, não grade de cards (DS §15). | SUI | crossfade | `library.row.<kind>.<id>`, `library.detail.*` |
| M-113 | Abas internas: activity bar do painel direito, detalhe do computador (Activity, Network, Journal, Commands, Files, Timeline, Result; 07 CS-320) e segmented de 02 §12.12 | Clique | sublinhado/seleção `snappy`; conteúdo 0,20 `standard` | Sublinhado de 2 pt (ou fundo do segmento) desliza (`matchedGeometryEffect`); conteúdo: crossfade + 8 pt na direção da aba escolhida. | SUI | sublinhado salta; crossfade | `rightPanel.tabs.indicator`†, `rightPanel.computer.<id>.tab.<name>` |

### 6.4 Sidebar e sessões (M-2xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-201 | Recolher/expandir sidebar (⌘B) | Atalho ou botão | 0,22 `drawer` (as duas direções) | Sidebar como camada: x 0 ↔ −largura; rótulos fazem fade nos primeiros 40%. Terminal: resize único no quadro 0 (R2). Ao expandir, o espaço vazio à esquerda aparece no quadro 0 e a sidebar cobre esse espaço. Ao recolher, o terminal cresce no quadro 0 e a sidebar sai por cima dele. | SUI + `MotionPolicy.layoutTransitionInFlight` | instantâneo | `sidebar`, `window.sidebarToggle` |
| M-202 | Arrastar divisor (sidebar, splits) | Drag | imediato | Largura segue o mouse sem animação; o resize do PTY é limitado a 1 por quadro de display e aplicado com debounce de 50 ms ao soltar. Duplo clique reseta: linha-guia de 1 pt anima até a posição nova (0,20 `standard`), layout aplicado uma vez no fim. | AK/SUI | linha-guia ausente | `pane.divider.<id>`† |
| M-203 | Seleção de sessão desliza | Clique na linha, ⌘1…9 | clique: `snappy`; teclado: instantâneo | Fundo de seleção (`matchedGeometryEffect id: "selection"`) desliza até a linha. Workspace: saída 0,08 (fade) → entrada 0,16 (fade). Sem slide de terminais. | SUI | troca seca + fade 0,15 | `sidebar.selection`† |
| M-204 | Linha pendente → card pronto (03 §2.9) | Composer submetido; eventos do core (fetching → creating → ready) | fases: texto 0,16 `standard`; pronto: 0,18 `expoOut` | Pendente: spinner neutro 16 pt (atraso `spinnerShow`) + nome 13 pt + fase na linha 2 em 11 pt muted, com os textos de 03 §2.9 ("Preparing…", "Fetching origin…", "Creating worktree…", "Copying .env files…" só na v1.1, "Starting Claude Code…"). Troca de fase: texto antigo sobe 4 pt e some, o novo sobe de +4 pt (`contentTransition(.push(from: .bottom))`). Pronto: spinner → indicador do agente (crossfade 0,18); a linha da fase colapsa (fade 0,12 → altura 0,18); a lista de agentes do card expande (M-206). | SUI | crossfade de texto, sem push | `sidebar.pending.<id>` → `sidebar.session.<id>` |
| M-205 | Pendente falhou | Erro do core (branch existe, fetch sem rede) | 0,18 `expoOut` | Spinner → `AlertCircle` `destructive` (escala 0,6 → 1); linha 2 troca para "Couldn't create worktree" (push vertical). No centro, a mensagem e as ações de 03 §6.4 ("Try Again" · "Use Existing Branch" · "Create Without Fetching" · "Discard", conforme o caso) entram com y −2 → 0 e fade (padrão M-505). | SUI | crossfade | `sidebar.pending.<id>` |
| M-206 | Expandir/recolher agentes no card | Chevron, clique na pill-resumo | 0,18 `expoOut` | Altura por recorte (grid 0fr → 1fr do Orca), conteúdo y −2 → 0 + fade. Chevron 90° em 0,15. | SUI | instantâneo | `sidebar.session.<id>.summaryPill`, `sidebar.session.<id>.agent.<terminalId>.children.toggle` |
| M-207 | Filtrar sidebar | Digitação na busca | saída 0,15 `exit`; destaque 0,12 | Linhas que saem: fade + altura → 0. Trecho que casa recebe fundo realçado. Sem stagger. Esc limpa e devolve o foco ao terminal. | SUI | instantâneo | `sidebar.search`, `sidebar.search.empty` |
| M-208 | Renomear inline | Duplo clique / Enter | 0,12 `ease` → 0,24 | Fundo do campo surge no lugar do rótulo; ao confirmar, `contentTransition(.interpolate)` do texto. | SUI | sem interpolação | `sidebar.session.<id>.name` |
| M-209 | Apagar ou arquivar sessão | Confirmação (M-103) | 0,12 `exit` → 0,18 `exit` | Linha: fade → altura 0. Vizinhas sobem com `snappy`. Ao apagar: toast "Session deleted." · "Undo" (8 s, M-110; R1 K-20). | SUI | fade | `sidebar.session.<id>` |
| M-210 | Hover em linha | Hover | 0,12 `ease` | Fundo 0 → hover; botões de ação trailing aparecem com opacidade (0,12). Sem escala. | SUI | igual | — |
| M-211 | Revelar sessão atual / item navegado | Botão "Reveal Current Session" do rodapé (03 §2.12), clique em notificação ou item da Inbox. Sem atalho (o ⇧⌘E antigo não existe em 03 §21) | scroll 0,30 `drawer` → `revealGlow` 1,5 s | Scroll até a linha; quando assenta, glow 1,5 pt + anel 1 pt + glow 14 pt na cor `blue-400`, keyframes do Orca. | AK (scroll) + CA (glow) | scroll instantâneo + borda estática 0,6 s | `sidebar.footer.reveal`, `sidebar.session.<id>.revealGlow`† |
| M-212 | Sessão limpa movida para projeto (P10) | "Move to Project…" (R1 K-34) | `panel` | A linha sobe (escala `dragLift` + sombra, 0,12), viaja da seção "Sessions" (P11) até a posição no grupo do projeto (`matchedGeometryEffect`) e assenta. A seção de origem fecha o espaço com `snappy`. | SUI | crossfade nas duas posições | `sidebar.session.<id>` |
| M-213 | Linha filha (subagente) brota do pai | Hook `SubagentStart` ou `boxes_reserve` | conector 0,24 `expoOut` → linha 0,20 `standard`; vários filhos: stagger `children` | Conector em L se desenha do pai até a posição do filho (`trim` 0 → 1); a linha sobe 4 pt com fade. Com computador (Fatia 3): o glifo M-601 aparece no lugar do ícone. | SUI (`Path.trim`) | fade | `sidebar.session.<sessionId>.child.<childId>`, `.connector`† |
| M-214 | Arrastar sessão para reordenar/agrupar | Drag | lift 0,12; vizinhas `snappy`; soltar `drag` | Linha levantada: escala 1,02 + sombra; vizinhas abrem espaço; ao soltar, assenta com `drag`. | SUI | sem escala | `sidebar.session.<id>` |

### 6.5 Tabs e panes (M-3xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-301 | Abrir tab | ⌘T (shell), ⌥⌘T (agente padrão), Quick Launch ("+" ou ⌥⌘N), lançamento (03 §21) | largura `snappy`; conteúdo 0,20 `standard`; indicador `snappy` | Tab inserida à direita da ativa: largura 0 → 180/220 (mínimo 72). Conteúdo: fade, y −2 → 0, escala x 0,96 → 1 (âncora leading). Vizinhas abrem espaço. Indicador de tab ativa desliza. Overflow: a faixa rola até a tab (0,24 `drawer`). O conteúdo do pane segue M-503/M-504. | SUI (`matchedGeometryEffect id: "activeTab"`) | fade, indicador salta | `tabs.tab.<terminalId>`, `tabs.activeIndicator`† |
| M-302 | Fechar tab | ⌘W, ✕, clique do meio | conteúdo 0,12 `exit` → largura 0,18 `exit` | Conteúdo some, depois a largura colapsa. Vizinhas fecham o espaço com `snappy`; indicador desliza para a próxima ativa. Fechar = encerrar processo: agente rodando pede confirmação (M-103, 03 §16.1). ⇧⌘T (Reopen Closed Tab) reabre com M-301. | SUI | instantâneo | `tabs.tab.<terminalId>` |
| M-303 | Reordenar tab (drag) | Drag | lift 0,12; vizinhas `snappy`; soltar `drag` | Escala 1,02 + sombra; vizinhas abrem espaço; ao soltar, a tab assenta na vaga. | SUI | sem escala | `tabs.tab.<terminalId>` |
| M-304 | Trocar tab ativa | Clique, ⌃⇥, ⌃1…9, ⇧⌘] / ⇧⌘[ | clique: indicador `snappy`; teclado: instantâneo | Indicador desliza; conteúdo do pane troca **sem** animação (terminais pesados). | SUI | instantâneo | `tabs.activeIndicator`† |
| M-305 | Overflow da faixa de tabs | Tabs excedem a largura | 0,15 `ease` | Fades de 24 pt nas bordas e chevrons 20×24 aparecem e somem com opacidade. | SUI | igual | `tabs.overflow.leading`† / `tabs.overflow.trailing`† |
| M-306 | Split (⌘D direita, ⇧⌘D abaixo; tab ou cabeçalho de pane arrastado para uma zona de drop) | Atalho/drop | divisor 0,20 `expoOut`; placeholder 0,12; terminal `PaneCover` 0,16 | Quadro 0: o pane existente vai para o tamanho final (um resize). O divisor "se desenha" do centro para as pontas (`scaleY/scaleX` 0 → 1). O pane novo começa como placeholder (canvas + marca do provider a 30%) com fade e depois segue M-503/M-504. Durante o drag de tab ou de pane (v1, F11), a moldura do pane sob o cursor e a prévia da zona (metade do pane, `blue-400` a 14%) aparecem com fade de 0,15 e a prévia desliza entre zonas em 0,20 `standard` (só a camada de overlay, nunca o terminal); soltar aplica o layout num único resize por pane; Esc ou soltar fora cancela. Reduce Motion: crossfade de 0,15, sem deslizar. | SUI + R2 | fade | `pane.divider.<id>`†, `pane.<terminalId>` |
| M-307 | Fechar pane | ⌘W no pane, processo encerrado com "Close" | cobertura 0,12 `exit` → layout em 1 passo → divisor some 0,12 | `PaneCover` 0 → 1 sobre o pane que sai (R3); depois o irmão ocupa o espaço num único resize; o divisor faz fade. | SUI + R3 | instantâneo | `pane.<terminalId>.cover`† |
| M-308 | Foco de pane | Clique, ⌘] / ⌘[ (⌥⌘←/→ é Back/Forward, 03 §21) | 0,14 `ease` | Opacidade do container: inativo 0,8 ↔ ativo 1. Cabeçalho do pane: cor 0,12. Botões do header aparecem no hover (0,12). | SUI (opacidade de container; R1 permite) | troca seca | `pane.<terminalId>` |
| M-309 | Localizar pane (rim flash) | Navegação por teclado entre panes, "Open terminal" vindo de notificação/pedido, M-702 | 1,5 s `rimFlash` | Layer sobreposta: borda 1,5 pt a 68%, anel 2 pt a 34%, glow 18 pt a 36% em `blue-400`; opacidade 1 → 0,42 (24%) → 0 (46%). Clique comum **não** dispara. | CA (`CAKeyframeAnimation`, `keyTimes [0, .24, .46, 1]`) | borda estática 0,6 s | `pane.<terminalId>.rimFlash`† |
| M-310 | Atenção persistente no pane | Agente do pane em `needs input` e pane fora de foco | 0,15 `ease` | Borda interna 1,5 pt a 64% + 3 pt a 18% na cor `orange-500` (padrão `data-terminal-attention` do Orca), estática até o foco. | SUI/CA | igual | `pane.<terminalId>.attention`† |
| M-311 | Zoom de fonte do terminal (⌘= ⌘- ⌘0) | Atalho | entrada 0,12; hold 0,8 s; saída 0,20 `exit` | Pill central "110%" com fade. A mudança de fonte em si é imediata (resize único). | SUI | igual | `pane.<terminalId>.zoomPill`† |
| M-312 | Processo encerrou | Exit do PTY | 0,24 `standard` | Com código ≠ 0 ou sinal: overlay irmão 0 → `exitedDim` (0,35) e o cartão de 03 §4.6 (título "Terminal exited", texto "The process ended with exit code <n>. Its output is preserved.", botões "Close" / "Restart" / "Resume Conversation") sobe 4 pt com fade, stagger 0,035. Com código 0: sem escurecer; o banner neutro "Claude Code exited." (shell: "Process exited.") revela por recorte (0,24 `drawer`). | SUI | fade | `pane.<terminalId>.exitOverlay` (≠ 0), `pane.<terminalId>.exitBanner` (0) |
| M-313 | Terminal falhou ao iniciar (`failedToStart`, "Couldn't start") | Erro de spawn | rim flash vermelho 1,2 s → erro 0,24 `standard` | `rimFlash` em `red-500`, uma vez; "Couldn't start Claude Code" e o erro sobem 4 pt com fade; ações de 03 §4.6: "Try Again" / "Open Agent Settings" / "Copy Details". | CA + SUI | borda estática vermelha 0,6 s | `pane.<terminalId>.startError` |

### 6.6 Estados do agente (M-4xx)

Fonte de dados: `AgentActivityState` vindo de hooks por lançamento (T10), que chegam na **Fatia 2**. Na Fatia 1 não há hooks: o indicador mostra só o estado do processo (02 §2.7) e o agente aparece como `unknown` (M-407), conforme R3 §4.1.

Estados canônicos (01 §6.3, com os acréscimos de R1 K-78): `starting`, `idle`, `working`, `needsInput` (subtipos `question`, `permission`, `other`), `waitingOnSubagents` (`audit/10` R6.1), `done`, `failed`, `blocked` (só subagente, journal `BLOCKED`), `interrupted`, `unknown` (absorve o antigo `stale` de 02) e `stalled` (v1.1). `estimated` é flag, não estado (OpenCode e shell, 06). `exited(code)` é estado de processo (01 §6.2), não de agente. Labels de UI, glifos e cores: 02 §2.6.

Tamanhos: os de 02 §2.6 (`AgentStateDot` do Orca): `sm` 10 (linha de agente, linha filha, Inbox), `md` 12 (tab, header de pane e coluna de status do card, onde `done` e `failed` são bolinha de 8), `lg` 16 (linha pendente, viewer, menu bar extra). Um único componente, `AgentStateIndicator` (CA), atende todos.

| ID | Estado / transição | Gatilho | Duração · curva | Visual e movimento | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-401 | `working` | `UserPromptSubmit`/`PreToolUse` (Claude), notify (Codex) | `loop.spinner` (1 s, 12 passos, 12 fps) | Anel 2 pt `yellow-500`, topo transparente, girando em fase global. Entrada: crossfade 0,18 a partir do estado anterior. | CA | anel completo parado | `<host>.status`† (valor "Working") |
| M-402 | `needsInput` | Pergunta do agente ou `Notification` com `permission_prompt`; `PermissionRequest` (Codex); `idle_prompt` só com turno ativo (um agente recém-lançado sem prompt fica `idle`, R1 K-78) | entrada: escala 0,6 → 1 com `lively` + `attentionRing` × 2 (3,6 s); depois estático | Balão `?` (`MessageCircleQuestion`) `orange-500`. Dois anéis de atenção saem do glifo e o movimento para. Na sidebar, a linha sobe para a seção/ordem de atenção (`snappy`). Se o pane dono não está focado: M-310. Badge de contagem: M-701. Anúncio de VoiceOver (02 §14.2). | CA (anel) + SUI | troca de cor 0,15, sem anel | idem ("Needs input") |
| M-403 | `working → done` | `Stop` sem filhos ativos | arco fecha 0,24 `expoOut` → check 0,24 `expoOut` | Onde `done` é check em círculo (tabs, linhas, Inbox; 02 §2.6): o arco completa o círculo (`strokeEnd` → 1, cor `yellow-500 → emerald-500`) e um check é desenhado (`trim`). Na coluna de status do card (bolinha de 8): crossfade para bolinha `emerald-500` com escala 0,6 → 1. Fica `done` não lido até o usuário ver o terminal; depois de 30 min visto e sem atividade, passa a `idle` com crossfade 0,30 (M-406). | KA (SwiftUI, one-shot) | crossfade 0,15 | idem ("Done") |
| M-404 | `failed` / `blocked` | `failed`: `StopFailure`, exit ≠ 0, erro de hook. `blocked`: subagente com `BLOCKED` no diário (CS-260) | 0,18 `expoOut` | Bolinha `red-500`, escala 0,6 → 1. Sem loop. | SUI | crossfade | idem ("Failed" / "Blocked") |
| M-404b | `interrupted` | Processo morreu fora do app (reboot, crash; M-002) | crossfade 0,18 | Bolinha `#a1a1a1` (02 §2.6), sem animação. | SUI | igual | idem ("Interrupted") |
| M-405 | `waitingOnSubagents` | `Stop` do pai com filhos em background ou computador com pedido aberto | crossfade 0,18 | Glifo `activity` `yellow-500` estático (o "monitoring" do Orca) + contador "2" em 9 pt. O movimento fica nos filhos (cada um com o seu M-401). Ao terminar o último filho: o pai transita conforme o hook seguinte. | SUI | igual | idem ("Waiting on subagents"; o contador fica no glifo) |
| M-406 | `idle` | `done` visto há 30 min, ou agente recém-iniciado sem prompt (após `SessionStart`) | crossfade 0,30 | Bolinha `neutral-500` a 40%. | SUI | igual | idem ("Idle") |
| M-407 | `unknown` | Hooks não confirmados (sem `SessionStart` em 10 s), provider sem hooks, hooks calados além da janela (o antigo `stale`), ou Fatia 1 (ainda sem hooks) | crossfade 0,18 | Círculo tracejado `amber-500` (`CircleDashed`), estático. Tooltip: "Status unavailable — hooks not connected" (o motivo varia). | SUI | igual | idem ("Status unavailable") |
| M-408 | Matriz de transições | Qualquer troca | ≤ 0,24 | Toda troca é crossfade 0,18 do glifo, exceto: working → done (M-403); qualquer → needsInput (M-402); qualquer → working (o anel aparece já na fase global, sem rampa). Trocas mais rápidas que 120 ms são coalescidas (vale o último estado). | CA/SUI | crossfade 0,15 | — |
| M-409 | Última mensagem do agente (linha de texto na sidebar) | Hook `Stop` / notify | 0,16 `standard` | Texto antigo sobe 4 pt e some; o novo entra (`contentTransition(.push(from: .bottom))`). Tempo relativo ("now", "12m") troca sem animação. | SUI | crossfade | `sidebar.session.<sessionId>.agent.<terminalId>.lastMessage`† |
| M-410 | Reordenar por atenção | Estado muda e a ordenação da sidebar depende dele | `snappy` | Linhas trocam de posição com spring; nunca durante hover ou drag do usuário (adiado até o mouse sair). | SUI | instantâneo | — |

`<host>` = `sidebar.session.<sessionId>.agent.<terminalId>`, `tabs.tab.<terminalId>`, `pane.<terminalId>.header` ou `rightPanel.computers.thumb.<computerId>`†. O sufixo `.status` segue AR-805 (R1 §4) e deve entrar em 03 §22.

### 6.7 Lançamento do agente (M-5xx), obrigatório nº 2

Detalhe quadro a quadro em §7.2.

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-501 | Composer submetido → chip voa até a sessão | ⌘↵ / "Create Session" no composer (P9, 03 §6.3) | saída do composer 0,15 `exit`; voo 0,42 (x `standard`, y `expoOut`); pouso `lively` + `clickRing` | Chip (cápsula 24 pt: logo do provider + nome) nasce sobre o botão "Create Session", viaja em arco (`arcLift` 56 pt) até a vaga da nova linha na sidebar (ou até a tab, se for terminal novo numa sessão existente), escala 1 → 0,85 e vira a linha (matched geometry). | SUI KA + `matchedGeometryEffect` (overlay na mesma janela) | sem chip: composer some em fade, linha aparece em fade | `overlay.composer.launchChip`†, `sidebar.pending.<id>` |
| M-502 | Nova tab de agente numa sessão existente | Quick Launch ("+" ou ⌥⌘N) → "New Claude Code Tab"; ⌥⌘T | M-301 | A tab nasce do botão "+" (âncora trailing do "+"); sem chip, porque a origem já é vizinha do destino. Pane segue M-503. | SUI | fade | `tabs.tab.<terminalId>` |
| M-503 | Ignição: placeholder + checklist das etapas reais (estado `Ignition` de 03 §4.6, a PhaseList) | Pane criado e primeiro byte ainda não chegou após `ignitionSkip` (0,30 s) | logo 0,20 `standard`; `halo` em loop; linhas 0,20 `standard`; check 0,24 `expoOut` | Logo do agente de **32 pt** (03 §4.6) centralizado com halo (escala 1 ↔ 1,04, opacidade 0,5 ↔ 0,8). Abaixo, checklist (até 6 linhas) com uma linha por etapa real (§7.2.2): linha ativa = spinner de 12 fps; concluída = check desenhado e texto muted. Cada linha visível ≥ 0,12 s. | CA (halo, spinners) + SUI (lista) | logo estático; linhas com fade; check aparece sem desenho | `pane.<terminalId>.ignition`, `pane.<terminalId>.ignition.cancel`, `pane.<terminalId>.ignition.step.<stepKey>`† |
| M-504 | Primeiro byte → terminal | Primeiro output do PTY | 0,12 `exit` → `PaneCover` 0,16 `standard` | Checklist e logo: fade + y −4 (0,12). Cobertura do terminal: 1 → 0 (0,16). Indicador → `working` (M-401). | SUI + R4 | crossfade 0,15 | `pane.<terminalId>.cover` |
| M-505 | Lançamento falhou | Etapa retorna erro (worktree, config, spawn, exit precoce) | 0,24 | Spinner da etapa → X vermelho desenhado (0,18); mensagem e ações de 03 §4.6/§6.4 ("Try Again" / "Open Agent Settings" / "Copy Details"; "Use Existing Branch" ou "Create Without Fetching" quando couber) sobem 4 pt; rim flash vermelho (M-313); indicador da sidebar → `failed` (M-404). | KA + CA | crossfade + borda estática | `pane.<terminalId>.ignition.step.<stepKey>`† (erro de etapa), `pane.<terminalId>.startError` (spawn) |
| M-506 | Lançamento rápido (pula a ignição) | Primeiro byte < `ignitionSkip` | 0,16 | Sem placeholder: o pane mostra o canvas e M-504 roda direto. Evita o placeholder piscar. | SUI | igual | — |
| M-507 | Subagente nativo nasce (hook) | `SubagentStart` | M-213 | Sem chip voando (o usuário não pediu pelo app). A linha filha brota do pai. Com computador (Fatia 3): M-601 no lugar do ícone. | SUI | fade | `sidebar.session.<sessionId>.child.<childId>` |
| M-508 | (v1.1) Subagente em modo isolado vira tab | CLI no container (P5/P6) | M-601 → M-301 → M-503 | A tab nasce com o glifo do container no lugar do logo. A checklist da ignição inclui as etapas do container (§7.2.2, bloco C; estado `Isolated: preparing` de 03 §4.6). | SUI + CA | fade | `tabs.tab.<terminalId>` |

### 6.8 Computador (M-6xx), obrigatório nº 3

Detalhe quadro a quadro em §7.3. **Fatia 3** (modo leve); variantes do modo isolado na v1.1 (§12.2). Na UI o termo é "Computer" (P15); "box" só aparece em nomes de ferramentas MCP, logs e pastas. Verbos de controle: "Take Over" / "Hand Back" (R1 D-02, adotado por P16), estado `revoking` = "Requesting control…" (R1 K-26). Cores: agente pilotando = `violet-400` (`--ai-action-accent` do Orca no escuro); humano no controle = `zinc-100` a 90%; precisa de você = `orange-500`; reconectando = neutro.

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-601 | Computador provisionando (glifo `BoxProvisioningGlyph`, 02 §2.8) | `boxes_reserve`, computador anexado a um terminal | `marching` em loop; face 0,20 `standard`; pronto `lively` | Caixa isométrica (16 pt na linha filha, 32 pt no placeholder do viewer, 03 §11.4). Contorno tracejado com marching ants enquanto alguma etapa roda. Cada grupo concluído preenche uma face: topo = imagem pronta; esquerda = container + proxy de egress no ar; direita = computador saudável (browser ou desktop). Pronto: tracejado → sólido (crossfade 0,18), pop de escala 1 → 1,06 → 1 (`lively`), tick verde desenhado (0,24). | CA (`lineDashPhase`, faces) + KA (pop) | contorno sólido, faces preenchem com fade, sem pop | `sidebar.session.<sessionId>.child.<childId>.glyph`† |
| M-602 | Computador na fila (capacidade) | Core responde "queued" (`audit/10` R4.7) | crossfade 0,18 | Contorno pontilhado estático a 50%, **sem** marching (nada está trabalhando). Rótulo "Waiting for memory · 3 of 15 queued" (curto: "Queued"; R1 K-56). | SUI | igual | `sidebar.session.<sessionId>.child.<childId>.glyph`† (valor "Queued") |
| M-603 | Viewer conectando | Viewer aberto antes do primeiro frame | `shimmer` | Área do frame com skeleton e brilho varrendo (gradiente em máscara, 1,4 s). Com o computador ainda provisionando, mostra o glifo de 32 pt e a PhaseList do computador no lugar (03 §11.4). | CA | bloco estático | `viewer.<computerId>.connecting`† |
| M-604 | Agente pilotando: borda viva + pill | `ControlGrant.agent` ativo e input do agente nos últimos 10 s | borda: `liveBorder` 3,2 s, 30 fps; pill 0,20 `standard` | Traço 1,5 pt com gradiente cônico `violet-400` (100% → 0% → 100%), opacidade 0,7, girando. Pill no topo à esquerda: logo + spinner + "Claude is using this computer" (ou o nome do filho, "phoenix-az"). Sem input há > 10 s: a rotação para (borda estática a 0,5) e a pill troca para "Claude has control" (subestado de `agentControl`, a acrescentar em 02 §2.8; R1 §10). | CA (`CAGradientLayer .conic` + máscara de borda) + SUI | borda sólida `violet-400` | `viewer.<computerId>.controlFrame`†, `viewer.<computerId>.controlPill` |
| M-605 | Cursor fantasma, ripple de clique, digitação | Eventos de input do MCP do computador (move/click/type/scroll), com coordenadas | cursor `cursor` spring; ripple 0,46 `clickRing`; tecla 0,12 | Seta 14 pt `violet-400` com contorno branco 1 pt e etiqueta "Claude" 9 pt. Move por spring da posição anterior até o alvo. O ripple (anel de 24 pt, escala 0,4 → 1,4, opacidade 0,9 → 0) dispara quando o core confirma que o clique foi **executado**, não quando foi pedido. `type`: glifo de teclado ao lado do cursor pulsa (opacidade 0,6 → 1, 0,12) e a pill mostra "Claude is typing" por `typingHold`. `scroll`: chevron na direção, fade 0,30. Ocioso por 3 s: cursor → 40%. | SUI (cursor, overlay) + CA (ripple) | cursor salta sem spring; ripple vira ponto que some em 0,15 | `viewer.<computerId>.ghostCursor`†, `viewer.<computerId>.clickRipple`† |
| M-606 | Humano pede o controle (`revoking`) | "Take Over" (⇧⌘R; ⇧⌘T é Reopen Closed Tab) | rampa 0,24 `standard` | Botão vira "Requesting control…" com spinner (`contentTransition`), desabilitado. Borda acelera de 3,2 s para 1,2 s por volta (`layer.speed`) e dessatura para 50%. Cursor fantasma congela. Após 1,5 s sem ACK: pill "Waiting for Claude to pause…". Após 10 s sem ACK: "Force Take Over" (`destructive xs`) entra com fade 0,15 (03 §11.4). | CA (`speed`) + SUI | borda sólida dessaturada | `viewer.<computerId>.takeOver` |
| M-607 | Handoff agente → humano | Broker concede o controle ao humano | 0,36 `expoOut` | Gradiente faz fade (0,18 `exit`) e a borda sólida `zinc-100` entra (0,30 `standard`). Um anel de 2 pt contrai da borda para dentro (inset 0 → 6 pt, opacidade 1 → 0), uma vez. Pill: texto antigo sobe 6 pt e some; "You're in control" entra de baixo; logo → glifo de cursor (`contentTransition(.symbolEffect(.replace))`). Cursor fantasma some (0,16). Na linha filha da sidebar, o estado do computador ao lado troca para "You're in control" (crossfade 0,18; R1 K-62); o estado de atividade do agente não muda. VoiceOver anuncia. | KA + CA | crossfade de cor 0,15, sem anel | `viewer.<computerId>.controlFrame`† (valor "Human") |
| M-608 | Handoff humano → agente | "Hand Back" (⇧⌘R), com nota opcional (popover de 03 §11.5) | 0,36 `expoOut` | Inverso: o anel expande (inset 6 → −2, recortado) e some; borda humana faz fade; o gradiente volta e a rotação retoma **na fase global**; pill "Claude is using this computer". O cursor fantasma reaparece (0,16) no primeiro input do agente. | KA + CA | crossfade | idem (valor "Agent") |
| M-609 | Agente pede ajuda (captcha, login) | `help_request` (07 §3.2) | banner 0,30 `drawer`; borda `breath`; botão `attentionRing` × 2 | Borda vira `orange-500` sólida respirando (0,55 ↔ 1, 1,6 s, 24 fps). Banner de 40 pt (03 §11.4) revela por recorte de dentro do topo do viewer: "phoenix-az needs you · CAPTCHA on aca-prod.accela.com" + "Take Over" em destaque, com 2 anéis de atenção, e "Decline…". Sidebar: M-402. Fora de foco: M-702/M-703. Ao assumir: M-607 parte do laranja. | SUI + CA | borda laranja estática; banner com fade | `viewer.<computerId>.helpBanner`†, `viewer.<computerId>.controlFrame`† (valor "Needs you") |
| M-610 | Reconectando / conexão lenta | Estado do stream `reconnecting` / `delayed` | 0,30 `ease`; `dots` | Último frame dessatura para 40%; pill "Reconnecting…" com 3 pontos. `delayed`: pill âmbar "Slow connection" sem loop (R1 K-56). | SUI + CA | sem pontos | `viewer.<computerId>.status`† |
| M-611 | Desconectado | `disconnected` | 0,30 → 0,24 `standard` | Frame escurece; cartão "Disconnected from <computer>." com "Reconnect" / "Open Diagnostics" (03 §11.4) sobe 4 pt. | SUI | fade | `viewer.<computerId>.disconnected`† |
| M-612 | Miniatura na aba "Computers" do painel direito (03 §10.4) e na thumbnail strip do viewer (03 §11.3) | Computador ativo na sessão | hover: ampliação `snappy`; estado: crossfade 0,18 | Miniatura com borda 1 pt na cor de quem controla (sem rotação: a borda viva só existe no viewer aberto) e um spinner M-401 se o agente estiver ativo. Hover amplia 1 → 1,6 (âncora na miniatura) após 0,25 s, com a URL e a última nota. Clique abre o viewer como tab da sessão (M-301; 03 §11). Atualização do frame: ≤ 1 fps (CS-403). | SUI | sem ampliação animada | `rightPanel.computers.thumb.<computerId>`†, `viewer.<computerId>.strip.thumb.<otherId>` |
| M-613 | Computador parou | Filho terminou, "Stop Computer…", sessão arquivada (lote é v1.1, R1 D-06) | 0,24 | Glifo M-601 perde o preenchimento (faces → 20%) e o traço fica neutro; miniatura faz fade para 0 e a lista da aba Computers fecha o espaço com `snappy`. | SUI | fade | `sidebar.session.<sessionId>.child.<childId>.glyph`† |

### 6.9 Notificações e atenção (M-7xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-701 | Badge de atenção no item `Inbox` da sidebar (03 §2.3 e §9.1) | Contagem de AttentionItems de prioridade 1–2 (agentes em `needsInput`, pedidos de computador, falhas; 01 §5.12) muda | bump `lively`; número `contentTransition(.numericText())` 0,24 | Badge `orange-500`; ao aumentar: escala 1 → 1,15 → 1 + um `attentionRing` (um só ciclo). Ao diminuir: só o número troca. | SUI + CA | troca de número | `sidebar.nav.inbox.badge`† |
| M-702 | Clique em notificação do sistema | `UNUserNotificationCenterDelegate.didReceive` | ativa a janela → M-203 → M-211 → M-309 (para computador: M-301 na tab do viewer, ou M-108 na aba Computers) | Sequência encadeada por eventos: seleciona a sessão, revela a linha com glow, foca o pane certo com rim flash; para pedidos de computador, abre o viewer com o banner M-609. Cada passo começa quando o anterior assenta (sem sobreposição). | encadeado | passos com fade, sem glow/flash | `motion.chain.notificationOpen` (evento) |
| M-703 | Dock e atenção do sistema | `needsInput` ou pedido de computador com app inativo | sistema | `NSApp.dockTile.badgeLabel` = nº de AttentionItems de prioridade 1–2 não resolvidos (R1 K-54); `NSApp.requestUserAttention(.informationalRequest)` uma vez por pedido novo. Não animamos o ícone. | Sys | igual | — |
| M-704 | Ícone da barra de menus (P4) | Processos ativos ou pendências mudam | nenhum | Conforme 03 §17: número ao lado quando há pendências, ponto âmbar só com não lidos, glifo normal enquanto há trabalho. Sem animação (custo e distração permanentes na barra). Depois do ⌘Q o app fica em modo accessory e o ícone continua (R1 D-03). | Sys | igual | `menuBar.icon` |
| M-705 | Inbox (feed na sidebar, ⇧⌘I; 03 §9.1) | Evento novo / resolvido / marcado como lido | entrada `lively`; resolvido 0,18 `exit` | Item novo entra no topo (fade + y −8 → 0); vizinhos descem com `snappy`. Resolvido: texto riscado (0,12) → fade → altura 0. | SUI | fade | `inbox`, `inbox.item.<eventId>` |
| M-706 | Banner in-app com o app em primeiro plano | Notificação suprimida pela regra "janela focada e sessão ativa" do Orca, mas o evento é de outra sessão | 0,20 `standard` / saída 0,15 `exit` | Usa o toast (M-110) com ação "Open". | SUI | fade | `toast.<kind>`, `toast.<kind>.action` |

### 6.10 Micro-interações (M-8xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-801 | Press de botão | mouseDown | 0,08 `ease` → volta `snappy` | Escala 0,97; primário escurece 6%. Ícones de toolbar não escalam (só fundo). | `ButtonStyle` | só cor | — |
| M-802 | Hover de botão/ícone | Hover | 0,12 `ease` | Fundo 0 → 8% branco; ícone 70% → 100%. Sem escala em superfícies grandes. | SUI | igual | — |
| M-803 | Anel de foco | Foco por teclado | 0,12 `ease` | Anel 3 pt (DS9, token `stroke.focusRing`) aparece com fade; ao mover o foco, o anel **não** desliza. | SUI | igual | — |
| M-804 | Toggle (switch) | Clique/espaço | `snappy` | Knob desliza; trilho troca de cor em 0,12. | SUI | troca seca | — |
| M-805 | Checkbox | Clique | 0,16 `expoOut` | Check desenhado (`trim`). | SUI | aparece | — |
| M-806 | Chevron de disclosure | Toggle | 0,15 `standard` | Rotação 0 ↔ 90°. | SUI | salta | — |
| M-807 | Campo de texto em foco | Foco | 0,12 `ease` | Borda e anel. | SUI | igual | — |
| M-808 | Erro inline de formulário | Validação | mensagem 0,20 `standard`; shake 0,30 | Mensagem: fade + y −4 → 0. Borda vermelha 0,12. **Shake** (3 ciclos, 6 pt) só ao submeter inválido. | KA (offset x) | sem shake | `overlay.<name>.<field>.error`† |
| M-809 | Sucesso no botão (Save, Copy) | Ação concluída | 0,24 `expoOut`; volta após 1,2 s | Rótulo → check desenhado + "Saved"/"Copied" (`contentTransition`); volta com crossfade 0,18. | KA | crossfade | `<host>.<button>` (o ID do próprio botão) |
| M-810 | Contadores (custo, capturas, badges) | Valor muda | 0,24 `twEaseOut` | `contentTransition(.numericText())`; números tabulares, alinhados à direita. Bump só em badges de atenção (M-701). | SUI | troca seca | — |
| M-811 | Spinner genérico atrasado | Operação async | aparece após `spinnerShow` 0,15; fade 0,12 | Mesmo anel do M-401, em `neutral-400` quando não é agente. Some com fade 0,12 se a operação terminar antes. | CA | anel parado | `<host>.spinner` |
| M-812 | Skeleton de lista (retomar conversa, Docker, Library) | Carregamento > 0,15 s | `shimmer`; resultados 0,20 `standard`, stagger `list` | Linhas cinza com brilho; resultados entram com fade + 4 pt. | CA + SUI | blocos estáticos; resultados com fade | `<list>.skeleton` |
| M-813 | Barra de progresso | Bytes/etapas reportados | 0,30 `twEaseOut` | Largura interpola (Orca `duration-300 ease-out`); indeterminada só com shimmer. | SUI | troca seca | `<host>.progress` |
| M-814 | Copiar/colar no terminal (feedback) | ⌘C com seleção, clique "Paste into prompt" (T11) | 0,12 → hold 0,6 → 0,20 | Pill "Copied" / "Pasted" no canto do pane. Nunca anima o texto do terminal. | SUI | igual | `pane.<terminalId>.feedbackPill`† |

### 6.11 Estados vazios e erros (M-9xx)

| ID | Momento | Gatilho | Duração · curva | Propriedades | Técnica | RM | Test ID |
|---|---|---|---|---|---|---|---|
| M-901 | Landing vazia (sem projetos nem sessões; 03 §19) | Lista vazia | tile 0,20 `standard` → texto 0,20 `standard` | O tile de 64 com o logo entra com fade + escala 0,98 → 1, **sem desenho de traço** (03 §19 e DS §12.21: sem ilustração). Título, texto e ações ("Add Project…", "New Clean Session" (P11), "Import from Orca…" quando couber) sobem 4 pt, stagger 0,035. Sem loop. | SUI | fade | `landing`, `landing.addProject`, `landing.newScratch` (renomear para `landing.newCleanSession` em 03, P11)†, `landing.importOrca` |
| M-902 | Busca sem resultado | Filtro zera a lista | 0,15 `ease` | `No sessions match "<query>".` + "Clear Search" com fade (03 §2.2). | SUI | igual | `sidebar.search.empty`, `sidebar.search.clear` |
| M-903 | Docker indisponível / imagem ausente | Detector de runtime (T7) | banner 0,24 `drawer`; ações 0,20 | Banner no topo da página Computers (e da aba Computers) revela por recorte: "Docker isn't running." + "Start Docker" (03 §12.3). A ação em andamento usa M-813. | SUI | fade | `computers.dockerBanner`† |
| M-904 | Persistência degradada (T2: corrupção nunca desabilita a UI) | Falha de migração/leitura | banner 0,24 `drawer` | Banner no topo do centro com o texto de 03 §1.4: "Agent Box couldn't read its database. Your terminals are still running." + "Open Diagnostics" (variantes de 08: "Database was created by a newer Agent Box", "Restored from the backup of <date>." + "Reveal Corrupt File"). UI continua interativa. | SUI | fade | `window.databaseBanner`† |
| M-905 | Lista ou painel vazio (sem computadores, Inbox vazia, sem histórico) | Lista vazia | 0,20 `standard` | Texto + ação opcional (DS §12.21: sem ilustração, sem ícone grande), ex.: "No computers yet. Agents create them when they need a browser.", "Nothing needs you."; fade + 4 pt. | SUI | fade | `<panel>.empty`† |
| M-906 | Erro genérico de ação longa (`audit/10` RT.3) | Falha | 0,24 | Erro aparece **no lugar onde a ação foi pedida** (linha, card, pane, painel) com o padrão M-205/M-505: indicador → vermelho, mensagem e ação sobem 4 pt. Nunca alerta modal genérico. | SUI | fade | `<host>.error` |

---

## 7. Os três momentos obrigatórios, quadro a quadro

Quadros a 60 fps (f0 = gatilho). Os valores de progresso vêm das tabelas de §3.3/§3.4; o protótipo HTML e o app devem bater nesses quadros com tolerância de ±1 quadro e ±2% (§11).

### 7.1 Abrir telas

#### 7.1.1 M-101 + M-102 · Composer "New Session" nascendo do "+" da sidebar (Fatia 1)

Contexto: a janela com 2 terminais em streaming. O usuário clica no "+" do header "Projects" (`sidebar.projects.newSession`, 03 §2.4) ou aperta ⌘N; com atalho, a origem continua sendo o "+" se ele estiver visível. Se a sidebar estiver recolhida, a origem é o botão de toggle da sidebar (`window.sidebarToggle`); sem botão visível, o composer abre centrado e sem offset.

Geometria: cartão de **560 pt** centrado na janela (largura do composer em 03 §6). Vetor de origem `v` = do centro do cartão até o centro do botão. Âncora da escala = interseção de `v` com a borda do cartão (expressa como `UnitPoint`). Offset inicial = `normalize(v) × 12 pt`.

| Quadro | t (ms) | Scrim | Cartão (opacidade · escala · offset) | Conteúdo | Outros |
|---|---|---|---|---|---|
| f0 | 0 | 0 | 0 · 0,950 · 12 pt | — | Botão "+": press 0,97 (M-801) e fundo "ativo". O terminal perde o foco (cursor oco). Evento `M-101 begin`. |
| f2 | 33 | 0,19 | 0,61 · 0,981 · 4,7 pt | grupo 1 (Project + Where) começa: 0 → 1, y +4 → 0 | — |
| f4 | 67 | 0,41 | 0,86 · 0,993 · 1,7 pt | grupo 2 (Create from / Worktree / Folder) começa | Botão volta da escala (spring). |
| f6 | 100 | 0,51 | 0,95 · 0,998 · 0,6 pt | grupo 3 (Agent, Profile, Prompt, Advanced) começa | — |
| f9 | 150 | 0,55 | 0,99 · 1,000 · 0,1 pt | — | Scrim assentou. |
| f12 | 200 | 0,55 | 1 · 1 · 0 | grupo 3 em 0,95 | Campo "Prompt" recebe foco (AC-301; R1 K-88); o foco já está lá desde f0 para as teclas não se perderem, e o anel aparece em 0,12 (M-803). Evento `M-101 settled`. |
| f16 | 267 | — | — | todos assentados | Evento `M-101 end`. |

Saída (M-102), Esc no f0':

| Quadro | t (ms) | Scrim | Cartão (opacidade · escala) | Outros |
|---|---|---|---|---|
| f0' | 0 | 0,55 | 1 · 1 | Foco devolvido ao terminal **agora** (teclas já vão para o PTY). |
| f3' | 50 | 0,46 | 0,84 · 0,997 | — |
| f6' | 100 | 0,27 | 0,49 · 0,990 | Fundo "ativo" do "+" em fade (0,12). |
| f9' | 150 | 0 | 0 · 0,980 | Overlay removido da árvore. Evento `M-102 end`. |

Variação: submit com ⌘↵ não usa M-102; usa M-501 (§7.2).

#### 7.1.2 M-108 · Painel direito, aba "Computers" (mesma coreografia para qualquer aba; entra na fatia em que o painel direito aparece)

| Quadro | t (ms) | Terminal | Painel (recorte visível) | Outros |
|---|---|---|---|---|
| f0 | 0 | **resize único** para a largura final (um SIGWINCH). O TUI redesenha sob o painel. | 0% | Botão do painel fica ativo. Evento `M-108 begin`. |
| f2 | 33 | parado | 53% | Conteúdo do painel já está no lugar final; só a máscara cresce a partir da borda que encosta no terminal. |
| f4 | 67 | — | 79% | — |
| f8 | 133 | — | 96% | — |
| f18 | 300 | — | 100% | Hairline interna faz fade 0 → 1 (0,12). Evento `M-108 end`. |

Fechar: máscara 100% → 0% em 0,20 `exitClip` (f0–f12); o resize do terminal acontece no último quadro (f12), quando o painel já não cobre nada. É a única exceção à regra "resize no início": ao fechar, o espaço só é devolvido quando o conteúdo saiu.

#### 7.1.3 M-109 · Settings (página do centro; Fatia 1)

| Quadro | t (ms) | Conteúdo antigo | Settings |
|---|---|---|---|
| f0 | 0 | opacidade 1 → 0 em 0,08 | — |
| f5 | 83 | removido | começa: opacidade 0, y +8 |
| f8 | 133 | — | `cssEaseOut`: 0,42 · y 4,6 |
| f13 | 217 | — | 0,90 · y 0,8 |
| f16 | 267 | — | 1 · 0. Evento `M-109 end`. |

Trocar de seção dentro de Settings repete só a parte do Settings (sem fade de saída: a seção antiga é substituída no f0).

### 7.2 Agente sendo lançado

#### 7.2.1 M-501 → M-503 → M-504 · "New Session" com Claude Code e worktree nova (Fatia 1)

Contexto: composer aberto (M-101), projeto `otter`, agente Claude, prompt preenchido. ⌘↵ em f0.

| Quadro | t (ms) | Composer | Chip | Sidebar | Workspace | Evento |
|---|---|---|---|---|---|---|
| f0 | 0 | começa a sair (M-102 sem devolver foco): opacidade 1 → 0, escala → 0,98, 0,15 `exit` | nasce sobre "Create Session": cápsula 24 pt, logo Claude + "fix-arcgis-pagination", opacidade 1 | — | — | `M-501 begin` |
| f3 | 50 | 0,84 | x 0,46 · y 0,56 do trajeto, sobe pelo arco (até 56 pt acima da reta) | vaga da nova linha começa a abrir: altura 0 → 28 (`snappy`) | — | — |
| f6 | 100 | 0,49 | x 0,75 · y 0,81 | vaga em 72%; linhas abaixo descem | — | — |
| f9 | 150 | 0 (removido) | x 0,88 · y 0,92; escala → 0,92 | vaga em 92% | — | — |
| f15 | 250 | — | x 0,97 · y 0,99; escala 0,87 | assentada | — | — |
| f25 | 420 | — | **pouso**: x/y 1; escala 0,85 → morph em linha (matched geometry 0,08) | linha nasce: fundo pisca seleção 0 → 12% → 0 (0,30); `clickRing` de 16 pt sai do logo (0,46) | — | `M-501 landed` |
| f30 | 500 | — | removido | seleção desliza para a nova linha (`snappy`); spinner pendente ainda invisível (atraso 0,15 desde o início do pending) | workspace antigo: fade 0,08 | — |
| f35 | 583 | — | — | spinner pendente aparece (fade 0,12); fase "Fetching origin…" | entra o pendente da sessão: logo Claude 32 pt + halo; checklist linha 1 entra (fade + 4 pt) | `M-503 begin` |
| … | eventos reais | — | — | fase troca com push vertical (M-204) | cada etapa: spinner → check desenhado (0,24); linha seguinte entra; mínimo 0,12 s por linha | `M-503 step:<key>` |
| T_ready | — | — | — | spinner pendente → indicador do agente (crossfade 0,18); linha da fase colapsa | tab "Claude" nasce (M-301); a checklist **continua** no pane (mesmo componente, sem salto, porque o pane ocupa o workspace) | `M-301 begin` |
| T_byte | — | — | — | indicador → `working` (anel na fase global) | M-504: checklist e logo saem (fade, y −4, 0,12); `PaneCover` 1 → 0 (0,16) revela o Claude Code desenhando | `M-504 begin` |
| T_byte + f10 | +167 | — | — | — | terminal 100% visível | `M-501 end` |

Se a sessão nova não precisa de worktree (pasta existente, sessão limpa P10/P11 criada por "New Clean Session" ⇧⌘N), as etapas de Git não existem e o pendente quase sempre dura menos que `ignitionSkip`. Nesse caso vale M-506: a tab nasce e o terminal aparece direto, sem placeholder.

#### 7.2.2 Checklist das etapas reais

Cada linha corresponde a um evento `LaunchProgress` emitido pelo core (requisito para 08: o core expõe esses eventos com `stepKey`, `status` (`running | done | failed | skipped`) e, quando houver, `detail` e `progress`). Linhas `skipped` não aparecem. Os `stepKey` são deste capítulo; o texto de cada linha é o de 03 (§2.9, §4.6 e §11.4). Onde 03 ainda não tem o texto, o daqui é proposta e está marcado com † para entrar em 03:

| Bloco | `stepKey` | Linha na UI | Quando existe | Evento que conclui |
|---|---|---|---|---|
| A · Sessão (Fatia 1) | `git.fetch` | "Fetching origin…" | worktree nova | `git fetch` retorna |
| A | `git.worktree` | "Creating worktree…" | worktree nova | `git worktree add` retorna |
| A | `files.copy` (v1.1, `.worktreeinclude`, R1 K-89a) | "Copying .env files…" | configurado no projeto | cópia concluída |
| A | `setup.script` | "Running setup script"† (abre em tab própria) | `setup` do projeto | script iniciado (não espera terminar) |
| B · Terminal (Fatia 1) | `launch.config` | "Preparing launch" (hooks, MCP, skills, por lançamento) | sempre | arquivos `--settings`, `--mcp-config`, `--plugin-dir` gravados |
| B | `pty.spawn` | — (não aparece; a linha seguinte cobre) | sempre | `agentboxd` confirma o PTY |
| B | `cli.exec` | "Starting Claude Code…" (nome de exibição do agente) | sempre | primeiro byte no PTY (encerra a ignição, M-504) |
| B | `hooks.handshake` (Fatia 2) | — (não aparece na lista) | Claude/Codex | `SessionStart` recebido; se não chegar em 10 s, o indicador vai para `unknown` (M-407) |
| C · Computador (Fatia 3, modo leve; v1.1 isolado) | `box.runtime` | "Checking Docker"† | sempre que há computador | Engine API responde |
| C | `box.image` | "Pulling image" com bytes na barra (M-813) ou "Building image"† | imagem ausente | digest presente |
| C | `box.container` | "Creating computer" (isolado, v1.1: "Creating container") | sempre | container `running` |
| C | `box.egress` | "Starting network proxy"† | sempre (T9) | sidecar `egress` saudável |
| C | `box.computer` | "Starting browser" / "Starting desktop"† | sempre | healthcheck do browser/VNC ok |
| C | `box.cli` (v1.1) | "Starting Claude Code" (precedido por "Mounting workspace" e "Signing in to Claude Code", 03 §4.6) | modo isolado | primeiro byte |

Faces do glifo M-601: topo = `box.image`; esquerda = `box.container` + `box.egress`; direita = `box.computer`.

Regras da checklist:
- No máximo 6 linhas visíveis; as concluídas mais antigas colapsam numa linha "3 steps done" (fade 0,15).
- Linha ativa: spinner 12 fps à esquerda; texto primário. Concluída: check `emerald-500` desenhado (0,24 `expoOut`) e texto muted (0,12).
- O tempo mínimo de 0,12 s por linha é só visual: se três eventos chegarem no mesmo quadro, as linhas entram com 0,12 s entre elas, mas o processo não espera.
- Etapas com `progress` mostram a barra (M-813). Sem `progress`, não há barra.
- Falha (M-505): a linha fica com X vermelho desenhado (0,18); a mensagem do erro aparece logo abaixo (fade + 4 pt) com as ações; as linhas seguintes não aparecem.

#### 7.2.3 M-507 · Subagente nativo com computador (sem chip; linha filha na Fatia 2, glifo na Fatia 3)

| Quadro | t (ms) | Sidebar | Evento |
|---|---|---|---|
| f0 | 0 | `SubagentStart` (ou `boxes_reserve`): vaga abaixo do pai abre (`snappy`) | `M-213 begin` |
| f0–f14 | 0–240 | conector em L desenha do pai até a vaga (`trim` 0 → 1, `expoOut`) | — |
| f8–f20 | 133–333 | linha filha: fade + y +4 → 0 (`standard`); glifo M-601 no lugar do ícone, com marching ants | — |
| +60 ms por filho | — | segundo filho repete com stagger `children` | — |
| eventos `box.*` | — | faces do glifo preenchem; pronto = pop `lively` + tick | `M-601 face:<n>`, `M-601 ready` |
| primeiro input do agente no computador | — | indicador do filho → `working` | `M-401` |

### 7.3 Computador em uso

Cena de referência (Fatia 3): viewer do `phoenix-az` aberto como tab da sessão (03 §11), em split ao lado do terminal pai. Agente filho clicando no formulário do Accela.

#### 7.3.1 M-604 + M-605 · Agente pilotando, cursor e clique

| Quadro | t (ms) | Borda | Cursor fantasma | Pill | Evento |
|---|---|---|---|---|---|
| — | contínuo | gradiente cônico `violet-400` gira 360° em 3,2 s (30 fps → 96 quadros por volta); fase global | parado em (412, 318), 100% | "Claude is using this computer" + spinner | — |
| f0 | 0 | — | evento `computer.click(640, 402)` **pedido**: cursor começa a mover (spring `cursor`) | — | `M-605 move` |
| f6 | 100 | — | 59% do trajeto | — | — |
| f12 | 200 | — | 94% | — | — |
| f18 | 300 | — | 100,5% (micro-overshoot) | — | — |
| f21 | 350 | — | assentado | — | — |
| f_exec | quando o core confirma a execução (normalmente 30–150 ms após o pedido) | — | ripple de 24 pt no alvo: escala 0,4 → 1,4, opacidade 0,9 → 0, 0,46 s | — | `M-605 click` |
| f_exec + f28 | +460 | — | ripple some | — | — |
| frames do stream | — | — | — | — | o resultado do clique aparece no frame seguinte do stream (sem interpolação, R11) |
| `type("permit 2024")` | 0 | — | glifo de teclado pulsa a cada chamada (0,12) | troca para "Claude is typing" (push vertical 0,16); volta após 1,2 s sem `type` | `M-605 type` |
| 3 s sem input | — | — | opacidade 1 → 0,4 (0,30) | — | `M-605 idle` |
| 10 s sem input | — | rotação para (borda estática 0,5) | — | "Claude has control" | `M-604 idle` |

Se o primeiro clique acontece antes de qualquer `move` conhecido, o cursor nasce no alvo com fade 0,12 (sem viagem desde o canto).

#### 7.3.2 M-606 → M-607 · Humano assume o controle

| Quadro | t (ms) | Borda | Anel de handoff | Pill / botão | Cursor fantasma | Sidebar | Evento |
|---|---|---|---|---|---|---|---|
| f0 | 0 | período 3,2 s → 1,2 s em rampa de 0,24 (`speed` 1 → 2,67); saturação 100% → 50% | — | "Take Over" → "Requesting control…" + spinner (0,16) | congela | — | `M-606 begin` |
| f14 | 240 | rápida e dessaturada | — | — | — | — | — |
| f90 | 1500 | (sem ACK ainda) | — | pill: "Waiting for Claude to pause…" | — | — | `M-606 waiting` |
| g0 | 0 (grant) | gradiente: opacidade 0,7 → 0 (0,18 `exit`); borda `zinc-100` 0 → 0,9 (0,30 `standard`) | inset 0 pt, opacidade 1 | texto antigo começa a subir 6 pt e sumir (0,12) | opacidade 1 → 0 (0,16) | linha do filho: estado do computador → "You're in control" (crossfade 0,18) | `M-607 begin` |
| g4 | 67 | gradiente 0,57 · humana 0,65 | inset 4,3 pt · 0,28 (`expoOut` 0,36: 0,72) | "You're in control" entra de +6 pt | 0,77 | — | — |
| g8 | 133 | gradiente 0,27 · humana 0,84 | inset 5,5 · 0,08 | logo → glifo de cursor (`symbolEffect.replace`) | 0,26 | — | — |
| g12 | 200 | gradiente 0 · humana 0,88 | inset 5,9 · 0,02 | assentada | 0 | — | — |
| g22 | 367 | — | removido | — | — | — | `M-607 end`; VoiceOver: "You're in control of phoenix-az" |

O viewer vira first responder em g0: o cursor do sistema já controla o computador durante a animação.

#### 7.3.3 M-608 · Devolver ao agente ("Hand Back", ⇧⌘R)

| Quadro | t (ms) | Borda | Anel | Pill | Evento |
|---|---|---|---|---|---|
| h0 | 0 | humana 0,9 → 0 (0,18 `exit`); gradiente 0 → 0,7 (0,30 `standard`), **já girando na fase global** | inset 6 → −2 pt (recortado na borda), opacidade 1 → 0, 0,36 `expoOut` | "Hand Back" → nota opcional enviada; texto "You're in control" sai para cima; "Claude is using this computer" entra | `M-608 begin` |
| h12 | 200 | gradiente 0,68 | inset −1,8 · 0,02 | assentada | — |
| h22 | 367 | — | removido | — | `M-608 end`; VoiceOver: "Control returned to Claude" |
| primeiro input do agente | — | — | — | — | cursor fantasma reaparece (fade 0,16) e o filho volta a `working` |

#### 7.3.4 M-609 · Agente pede ajuda (captcha)

| Quadro | t (ms) | Viewer | Sidebar | Fora do app | Evento |
|---|---|---|---|---|---|
| f0 | 0 | borda: gradiente violeta → `orange-500` sólida (crossfade 0,18); começa `breath` (0,55 ↔ 1, 1,6 s) | linha do filho: M-402 (glifo "?" com `lively` + 2 anéis); badge M-701 | se a janela não está focada ou a sessão não está ativa: notificação (M-702) + dock (M-703) | `M-609 begin` |
| f0–f18 | 0–300 | banner revela por recorte de dentro do topo (0,30 `drawer`): "phoenix-az needs you · CAPTCHA on aca-prod.accela.com" | — | — | — |
| f18 | 300 | "Take Over" em destaque; começa o 1º `attentionRing` (1,8 s) | — | — | — |
| f126 | 2100 | 2º anel | — | — | — |
| f234 | 3900 | anéis param; a borda continua respirando até o pedido ser atendido | — | — | `M-609 settled` |
| clique em "Take Over" | — | M-606/M-607 partindo do laranja; o banner recolhe (0,18 `exitClip`) quando o grant chega | estado do computador → "You're in control" | — | `M-607 begin` |

---

## 8. Componentes

| Componente | Momentos | Notas |
|---|---|---|
| `Motion` + `MotionTokens` (gerado) + `MotionPolicy` | todos | §3.8; `MotionPolicy.mode` aceita `.instant` e `.slow(x)` |
| `MotionEvents` | todos | `os_signpost` (subsystem `app.agentbox`, category `Motion`, nome = ID) + stream para `agentbox ctl motion events` em modo de automação |
| `LoopHost` | todos os loops | registra layers em loop, aplica fase global, teto de fps, pausa/retoma (R5–R7) |
| `OverlayHost` (dialog, palette, menu, tooltip, hover card) | M-101…M-107 | `anchorPreference` do botão de origem; foco e Esc; uma pilha por janela |
| `SidePanelHost` | M-108 | máscara de recorte + coordenação com R2 |
| `PaneCover` | M-001, M-307, M-504, M-506 | view da cor do canvas sobre o terminal (R3/R4) |
| `RimFlash` | M-309, M-313, M-211 | CA, keyframes do Orca, cor parametrizável |
| `AgentStateIndicator` | M-401…M-408, M-404b, M-811 | CA; tamanhos `sm` 10 / `md` 12 / `lg` 16 (02 §2.6; bolinha de 8 dentro do `md`); `accessibilityValue` |
| `LaunchChip` + `LaunchIgnitionView` | M-501…M-506, M-508 | KA para o voo; checklist ligada a `LaunchProgress` |
| `BoxProvisioningGlyph` (nome de 02 §2.8) | M-601, M-602, M-613 | CA; 16 e 32 pt |
| `ComputerControlFrame` (borda viva, anel de handoff, pill, banner) | M-604, M-606…M-609 | CA para borda/anel; SUI para pill/banner |
| `GhostCursorLayer` | M-605 | coordenadas do MCP mapeadas para o espaço do viewer (pixels do VNC ou CSS px do headless × escala) |
| `ToastCenter` | M-110, M-706 | pilha com `snappy` |
| `MotionLab` | §10 | só em builds Debug e no canal de automação |

Lottie e Rive ficam fora (`audit/06` §4.H). `MotionAssetView`/AVPlayer não é usado para ícones.

---

## 9. Workflow de prototipagem com a skill do dono

### 9.1 O que usar da skill

A skill `motion-designer` (`~/.claude/skills/motion-designer`) foi feita para vídeos sociais. Para a UI do Agent Box:

- **Usar:** o método de timeline determinística (`window.seek(t)` função pura de t, `window.MARK`, `window.DUR`, `window.ready`; sem `Date.now`, transições CSS ou `Math.random`), o template `templates/timeline.html` como base, `scripts/render.py` (frames, `--test` com contact sheet, `--scale`, `--range`), `scripts/export_marks.py`, `scripts/sheet.py`, `scripts/encode.sh` e as regras de `references/craft.md` que valem para UI: um movimento por vez; se o olho persegue, está rápido; saídas antes de entradas; revisão em vídeo e não em stills; versões paralelas por agentes independentes.
- **Pular:** o intake (Q0–Q16), safe zones e faixas HEAD/VIS/CAP de redes sociais, narração, legendas, trilha e CTA. O render usa `--ar` customizado (`1440x900` para a janela inteira, `640x400` para um componente), com uma entrada `LAYOUT` própria.
- **Mudar:** o `pipeline.md` captura a 240 fps e aplica `tmix=frames=4` (motion blur). Para UI isso engana, porque o app não tem blur de movimento. Aqui o render é **60 fps sem `tmix`** (`render.py --fps 60` + `encode.sh frames out.mp4 60`, que com FPS < 120 não mistura quadros) e 120 fps quando o ponto for avaliar ProMotion. O áudio é silêncio (`silent.wav` gerado uma vez).

### 9.2 Estrutura no repo

```
design/motion/
  tokens.json                      # fonte única (§3.7)
  lib/tokens.js                    # gerado
  lib/motion.js                    # bezier (UnitBezier do WebKit) + spring analítico + loops + helpers
  lib/ui-kit.css                   # cores, tipos e componentes do rebuild (de 02), sem screenshots
  storyboards/
    M-101-dialog/  beats.md  timeline.html  marks.json  renders/
    M-501-launch/  beats.md  options/A-…/ B-…/ C-…/  renders/
    M-604-computer/ …
  recordings/                      # gravações do app (Motion Lab) e comparações lado a lado
  README.md                        # log: ID · versão · status (draft/approved/ported/verified) · decisão do dono · links
scripts/motion/
  gen_tokens.py  render_ui.sh  compare.sh
```

### 9.3 Passo a passo

1. **Beat sheet (`beats.md`).** Para cada momento: uma frase que conta a história ("o chip sai do Create e vira a linha da sessão"), a lista de `MARK`s com o evento real que dispara cada um (`PRESS`, `COMPOSER_GONE`, `CHIP_LAND`, `STEP_FETCH_DONE`, `FIRST_BYTE`), e a tabela quadro a quadro de §7 como alvo. É um documento interno: o dono não aprova storyboard escrito (`craft.md` §9).
2. **HTML com tokens.** Copiar `templates/timeline.html`, trocar o bloco de marca pelo `ui-kit.css`, carregar `lib/tokens.js` e `lib/motion.js`. A UI é recriada em HTML/SVG com as cores, tipos e medidas reais do rebuild (o oposto do slideshow de screenshots do D10). Nenhum número literal de tempo ou curva no HTML: tudo vem de `MOTION.*`. Terminais aparecem como blocos de texto estático (o terminal não anima, então não há o que prototipar nele).
3. **Variações.** Para os três obrigatórios, gerar **A/B/C por agentes independentes** (regra da skill), cada uma com uma leitura diferente (ex.: handoff com anel contraindo, com varredura de cor pela borda, com a pill "atravessando" o viewer). Só tokens existentes. Se uma variação precisa de um token novo, ele entra no `tokens.json` como proposta, marcado `"draft": true`.
4. **Render quadro a quadro (Playwright).**
   - Stills de checagem: `python3 $SKILL/scripts/render.py storyboards/M-501-launch/timeline.html --ar 1440x900 --test 0,0.05,0.1,0.15,0.25,0.42,0.5,0.6` → `sheet.png`. O agente lê o contact sheet e confere com a tabela de §7 antes de mostrar qualquer coisa.
   - Draft para direção: `--fps 30 --scale .5`.
   - Final: `--fps 60` (e `--fps 120` sob demanda), `encode.sh … 60`, sem `tmix`.
   - Slow-mo 4× para revisão de detalhe: `ffmpeg -i in.mp4 -filter:v "setpts=4*PTS" slow.mp4`.
   - Contact sheet a 30 fps do trecho principal para revisão quadro a quadro (`sheet.py`).
   - `scripts/motion/render_ui.sh <storyboard>` empacota tudo isso.
5. **Revisão do dono.** O dono assiste aos MP4 (normal + slow-mo), lado a lado com as variações, e escolhe. A decisão e o motivo das rejeições vão para `design/motion/README.md`. Os arquivos são revelados no Finder (`open -R`), como a skill faz.
6. **Port.**
   - Cada `MARK` vira um passo nomeado: `KeyframeAnimator` (keyframes com as mesmas curvas), `PhaseAnimator` (fases discretas) ou `withAnimation(_:completionCriteria:_:completion:)` encadeado a eventos reais do core. Loops viram componentes CA (§8).
   - Cada passo emite o mesmo nome em `MotionEvents` (`M-501 landed`), o que liga protótipo, app e testes pelo mesmo vocabulário.
7. **Verificação no app.** O Motion Lab reproduz a cena com dados simulados, com scrub e slow-mo. `scripts/motion/compare.sh` grava o app (§10) e monta um vídeo lado a lado com o storyboard aprovado (`ffmpeg hstack`, sincronizado pelo `begin`). O dono assiste à comparação. Depois vêm Instruments e Reduce Motion (§11).

### 9.4 Paridade matemática HTML ↔ Swift

- **Bezier.** `lib/motion.js` implementa o mesmo solver do `UnitBezier` do WebKit (Newton-Raphson com fallback de bissecção, ε = 1e-6), que é a mesma família usada por `CAMediaTimingFunction` e `timingCurve`.
- **Spring.** Oscilador amortecido com os parâmetros do SwiftUI: `ω0 = 2π/response`, `ζ = dampingFraction`, `ωd = ω0·√(1−ζ²)`, `x(t) = 1 − e^(−ζ·ω0·t)·(cos(ωd·t) + (ζ·ω0/ωd)·sin(ωd·t))`. Velocidade inicial 0.
- **Teste de paridade.** Um teste Swift carrega `lib/motion.js` no `JavaScriptCore` e compara 101 amostras de cada curva e spring com a implementação Swift (`Bezier.value(at:)`, `SpringSpec.value(at:)`), tolerância 1e-4. O mesmo teste garante que `tokens.js` e `MotionTokens.generated.swift` têm os mesmos valores.

### 9.5 O que o storyboard decide e o que só o app decide

| Decidido no storyboard HTML | Só no app |
|---|---|
| Coreografia (ordem, stagger, sobreposição), escolha de curvas e springs, desenho dos indicadores (arco, ripple, borda viva, halo, glifo do computador), cores de handoff, comparação de variações | Custo real (CPU/GPU, hitches), 120 Hz, comportamento do SwiftTerm (resize/SIGWINCH/redesenho do TUI), foco e teclado, materiais do sistema, SF Symbols effects, latência real de eventos (ACK do broker, primeiro byte) |

O vídeo do storyboard nunca é usado dentro do app.

---

## 10. Motion Lab (debug no app)

Janela `Motion Lab`, disponível em builds Debug (⌃⌥⌘M; o ⌥⌘M antigo colide com "Minimize All" do sistema, R3 §2.2, e o novo não aparece em 03 §21) e por `agentbox ctl motion lab` quando o canal de automação está ligado.

| Recurso | Comportamento |
|---|---|
| Catálogo | Lista todos os `M-xxx` deste capítulo, com status (`draft / ported / verified`), prioridade e link para o storyboard aprovado. Busca por ID e nome. |
| Disparar | Botão "Trigger" roda o momento num palco com dados simulados (fontes falsas de `LaunchProgress`, `ControlBroker`, hooks e eventos de computador, com atrasos configuráveis, ex.: "first byte after 1.2 s", "ACK after 2 s"). |
| Scrub | Slider de t. SwiftUI: componentes aceitam um `MotionClock` injetável e renderizam `KeyframeTimeline.value(time:)` no t escolhido. CA: `layer.speed = 0` + `timeOffset = t`. |
| Slow-mo | 1× · 0,5× · 0,2× (`MotionPolicy.mode = .slow`, multiplicando durações e `layer.speed` global da janela). |
| Simulações | Toggles: Reduce Motion, Reduce Transparency, Low Power, janela ocluída, app inativo, 120 Hz vs 60 Hz (limitar `preferredFrameRateRange`). |
| Stress | "Stress terminals": abre 4 panes rodando `yes \| pv -qL 2000000` (ou `cat` de um arquivo grande) enquanto o momento roda. |
| HUD | FPS real (via `CADisplayLink` da janela), hitches contados, número de resizes de PTY desde o trigger, loops ativos no `LoopHost` e a fps de cada um. |
| Comparar | Abre o MP4 aprovado do storyboard lado a lado, sincronizado no `begin` do evento, com o mesmo slider de t. |
| Gravar | "Record" grava a região do palco com ScreenCaptureKit a 60 fps em `design/motion/recordings/M-xxx-app-<data>.mp4` e chama `compare.sh`. |
| Log de eventos | Linha do tempo dos `MotionEvents` (nome, fase, t), exportável em JSON para anexar a PRs. |

---

## 11. Critérios de aceite de motion

### 11.1 Por momento (prioridades A e B)

Um momento só passa de `ported` para `verified` quando cumpre tudo abaixo, os dados reais da sua fatia existem (§12.2) e o dono marcou "approved" no `design/motion/README.md` depois de ver o lado a lado (P14).

| # | Critério | Como verificar |
|---|---|---|
| MA1 | Durações e curvas vêm de tokens | CI: lint sem literais de animação; teste de paridade (§9.4) verde |
| MA2 | Coreografia igual ao storyboard aprovado | `compare.sh`: vídeo lado a lado app × storyboard; o dono aprova assistindo. Nos quadros-chave de §7, diferença ≤ 1 quadro e ≤ 2% nas propriedades medidas (scrub no Motion Lab + leitura do `presentation()`) |
| MA3 | Ordem e duração dos eventos | XCUITest/integração lê `agentbox ctl motion events` e confere a sequência de fases (ex.: `M-501 begin → landed → M-503 begin → M-504 begin → M-501 end`) e cada duração com tolerância de ±16 ms (`mode = .normal`) |
| MA4 | Funcional em `instant` | Suíte XCUITest completa com `-AgentBoxMotionMode instant`: mesmos eventos, duração 0, nenhum teste depende de `sleep` |
| MA5 | Reduce Motion | Suíte com `-AgentBoxReduceMotion YES`: cada momento emite o fallback esperado (ex.: `M-501 chipFlight=skipped`); screenshots por momento mostram estado legível sem movimento; nenhum loop ativo além de zero no `LoopHost` |
| MA6 | Terminal intocado | Contador de resizes de PTY (exposto em `agentbox ctl debug pty-resizes`) = **exatamente 1** por transição de layout (M-201, M-108, M-306, M-307) e 0 para os demais momentos. Teste automatizado |
| MA7 | Sem hitches | Instruments, template *Animation Hitches*, a 120 Hz, com os 4 terminais em stress do Motion Lab, disparando cada momento de prioridade A. Meta: 0 hitches; reprova acima de 5 ms/s de hitch time. Automatizado no lane de performance com `xcrun xctrace record --template 'Animation Hitches' --launch …` e um parser que extrai o hitch ratio |
| MA8 | Custo dos loops | 10 indicadores `working` visíveis por 60 s: CPU do app ≤ 2% de um núcleo e do WindowServer ≤ 3% acima da linha de base (`top -l` amostrado pelo script de performance); instrumento *Core Animation* mostra 12 commits/s para o spinner |
| MA9 | Pausa fora de vista | Janela ocluída por 10 s: 0 commits de loop (instrumento Core Animation / contador do `LoopHost`); ao voltar, as fases batem com a fase global (teste unitário do cálculo de `beginTime`) |
| MA10 | Input não espera | XCUITest: abrir dialog e apertar Esc seguido de digitação imediata; todos os caracteres chegam ao PTY (eco verificado). Arrastar divisor durante M-201 não trava |
| MA11 | Sem quadro quebrado | Gravação do Motion Lab revisada quadro a quadro (contact sheet a 30 fps com `sheet.py`): nenhum quadro com flash do canvas, conteúdo fora do container, salto de layout ou texto sobreposto |
| MA12 | Acessibilidade | Todo elemento animado listado tem o `accessibilityIdentifier` do catálogo; indicadores expõem `accessibilityValue`; anúncios de VoiceOver de 02 §14.2 ligados aos momentos M-402, M-403, M-404, M-607, M-608 e M-609 conferidos com Accessibility Inspector |
| MA13 | Interrompível | Teste: disparar M-201 duas vezes em 100 ms; disparar M-101 e Esc no f3; trocar de tab durante M-301. O estado final é correto, sem salto e com um único resize |

### 11.2 Por entrega

- **v1:** todos os momentos de prioridade A e B de §12.1 em `verified`, cada um na fatia de §12.2. Os de prioridade C podem estar em `ported`.
- **v1.1:** M-508 e as variantes de M-6xx para o modo isolado (CLI no container) em `verified`.

### 11.3 Instrumentação para os testes

- `-AgentBoxMotionMode normal|instant|slow:<fator>` e `-AgentBoxReduceMotion YES|NO` como launch arguments (só respeitados em builds de teste ou com o canal de automação ligado).
- `agentbox ctl motion events --follow` emite JSON por linha: `{"id":"M-501","phase":"landed","t":0.421,"target":"sidebar.pending.8F2…","reduced":false}`.
- `agentbox ctl motion trigger M-xxx [--fixture …]` dispara um momento com dados simulados (o mesmo motor do Motion Lab). É o que os testes de MA2/MA3 usam.
- Signposts `Motion` com begin/end por ID aparecem no Instruments ao lado do *Animation Hitches*, o que permite atribuir um hitch a um momento.

---

## 12. Prioridade e fatias

### 12.1 Prioridade

Os rótulos de prioridade deste capítulo são **A / B / C**. Eles substituem os antigos "P0 / P1 / P2", que colidiam com as decisões P0…P16 de `00-decisions.md` (R1 K-74, R3 §2.3).

| Prioridade | Momentos |
|---|---|
| **A** (v1, bloqueia a entrega da fatia em que o momento entra) | Tokens + `MotionPolicy` + `LoopHost` + `MotionEvents`; M-101, M-102, M-103, M-108, M-109 (abrir telas); M-201 (corrige o resize do app antigo, `audit/06` S1); M-301, M-302, M-304, M-306, M-307, M-309; M-401…M-408, M-404b; M-501…M-507 (lançamento); M-601, M-602, M-604…M-609 (computador); M-001, M-002; M-702 |
| **B** (v1) | M-003, M-104…M-107, M-110, M-111, M-113, M-202…M-214, M-303, M-305, M-308, M-310…M-313, M-409, M-410, M-603, M-610…M-613, M-701, M-703…M-706, M-801…M-814, M-903, M-904, M-906 |
| **C** (v1 se couber) | M-004, M-112, M-901, M-902, M-905 |
| **v1.1** | M-508 e variantes de M-6xx do modo isolado |

### 12.2 Em que fatia cada momento fica `verified`

As fatias são as de 01 §4.1. Um momento só pode ficar `verified` (§11.1, critérios MA1…MA13) quando os dados reais que o disparam existem; antes disso ele pode estar `ported` no Motion Lab com fontes simuladas. Isso resolve a dependência apontada em R3 §4.1: a Fatia 1 não precisa (nem pode) entregar "computador em uso".

| Fatia | Momentos | Dado que destrava |
|---|---|---|
| **1 · Casca e terminais** | Infra (tokens, `MotionPolicy`, `LoopHost`, `MotionEvents`, Reduce Motion primeiro); **obrigatório nº 1**: M-101, M-102, M-103, M-104, M-105, M-106, M-107, M-109 (Settings), M-110, M-111; **obrigatório nº 2**: M-501, M-502, M-503, M-504, M-505, M-506; M-001, M-002, M-003 (assim que o daemon existir); M-201, M-202, M-203, M-204, M-205, M-206 (só se houver mais de um terminal), M-207, M-208, M-209, M-210, M-211, M-212, M-214; M-301…M-309, M-311…M-313; M-407 (todo agente aparece como `unknown`, R3 §4.1); M-704 (quando o LaunchAgent e o ⌘Q com agentes vivos entrarem, última tarefa da fatia); M-801…M-814; M-901, M-902, M-904, M-905, M-906 | PTY, daemon, composer, `LaunchProgress` (blocos A e B de §7.2.2) |
| **2 · Atenção e GitHub** | M-108 (primeira aba do painel direito; se Conversations ficar na Fatia 1, M-108 sobe junto), M-113 (activity bar), M-213 e M-507 (linha filha de subagente nativo), M-310, M-401…M-406, M-404b, M-408, M-409, M-410, M-701, M-702, M-703, M-705, M-706; M-004 se o onboarding completo ficar nesta fatia (R3 §10) | Hooks por lançamento (T10), Inbox, notificações |
| **3 · Computadores, modo leve** | **obrigatório nº 3**: M-601…M-613; bloco C de §7.2.2; M-903; glifo de computador em M-213/M-507 | Docker, runtime, viewer noVNC, `ControlBroker` |
| **4 · Uso e biblioteca mínima** | M-109 (Library), M-112 | Library |
| **v1.1** | M-508, variantes isoladas de M-6xx, `files.copy` | Modo isolado, `.worktreeinclude` |

Leitura de P8 e de 01 §4.1 ("os três momentos de motion obrigatórios" na Fatia 1): na Fatia 1 os momentos 1 e 2 ficam `verified`; o momento 3 tem storyboard aprovado e port no Motion Lab com dados simulados, e fica `verified` na Fatia 3. A aprovação do dono segue P14 (lado a lado com a referência, OK explícito).

Dependências de dados (para outros capítulos): `AgentActivityState` por hooks (T10), `LaunchProgress` com `stepKey` (§7.2.2), eventos de etapa de computador, `ControlBroker` com `revoking` e ACK, eventos de input do MCP do computador com coordenadas e confirmação de execução, contador de resizes de PTY e canal `agentbox ctl motion` (T13).

---

## 13. Fontes

- `docs/rebuild/spec/00-decisions.md` (P1, P2, P4, P5, P6, P8, P9, P10, P11, P14, P15, P16, T1, T3, T5, T6, T8, T10, T13).
- `docs/rebuild/review/R1-consistency.md` (§0, §4, K-04…K-06, K-20, K-25…K-27, K-34, K-46…K-50, K-53…K-59, K-62, K-63, K-74, K-78, K-84…K-90, X-20), `R2-coverage.md` (§5), `R3-implementability.md` (§2.2, §2.3, §4.1, §10).
- `docs/rebuild/audit/06-motion.md` (inventário, proposta e catálogo originais), `04-orca-reference.md` §1.5 e §5, `07-review-ui.md` (correções 3, 5 e 6; itens 34, 36 e 38), `10-review-journeys.md` (J3, J4, R4.7, R6.1, RT.3).
- Código do Orca (só leitura): `components/ui/dialog.tsx:41,115`; `components/ui/dropdown-menu.tsx:36`; `components/ui/context-menu.tsx:62`; `components/ui/popover.tsx:174`; `components/ui/tooltip.tsx:36`; `App.tsx:92`; `components/tab-bar/TabStripTooltipProvider.tsx:13`; `components/StateIndicatorTooltip.tsx:4`; `components/sidebar/WorktreeCardMeta.tsx:74-75`; `components/AgentWorkingSpinner.tsx`; `components/AgentStateDot.tsx`; `assets/main.css` (linhas 228-235, 345-346, 1451, 1792-1822, 1940-2003, 2035-2091, 2587-2623, 2788-2802, 2993-3005); `assets/terminal.css:120-206`; `lib/pane-manager/pane-divider.ts:79-86`; `shared/constants.ts:42`; `shared/default-global-settings.ts:90`; `components/feature-wall/*` (origem de `browserTabIn` e afins).
- Skill do dono: `~/.claude/skills/motion-designer/SKILL.md`, `references/craft.md` (§2, §3, §5c, §9), `references/pipeline.md`, `templates/timeline.html`, `scripts/render.py`, `scripts/encode.sh`, `scripts/export_marks.py`, `scripts/sheet.py`. Variante com brand kits: `~/Desktop/Labrynth/labrynth-motion-design/skills/labrynth-motion-design/` (mesmo pipeline; não usada para tokens do Agent Box).
