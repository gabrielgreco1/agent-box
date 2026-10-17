# 06 · Motion — auditoria e proposta para o rebuild da UI

Data: 2026-10-16 · Escopo: `Sources/`, `design/` (protótipo Codex), Orca.app (referência), skill `motion-designer` / `labrynth-motion-design`.
Nada foi alterado no código. Nenhum vídeo foi gerado. A extração do Orca foi feita fora do repo (scratchpad `orca-motion/`), só leitura de CSS/JS.

---

## 0. Resumo

- **O app real quase não tem motion.** Há **uma** animação em todo `Sources/`: o recolhimento da sidebar (`WorkspaceView.swift:179`), e ela provavelmente redimensiona o terminal a cada quadro. O resto troca de estado sem transição: status, tabs, splits, badges, a posse do controle do computador. Todos os painéis grandes são `.sheet` do sistema.
- **O protótipo do Codex (`design/`) erra no método.** Usa `.animation(value:)` implícito na raiz, `easeInOut` de 0,2 s para tudo e loops decorativos de 30 fps com atividade falsa. O "walkthrough" em vídeo é um slideshow de screenshots. Não há tokens, não há hierarquia de tempo, e as três cenas que importam não foram desenhadas.
- **O Orca é contido e consistente.** Usa 150–200 ms para diálogos (fade + zoom 95%), 320–380 ms `cubic-bezier(.2,.8,.2,1)` para conteúdo entrando, um "rim flash" de 1,5 s para localizar um pane, e um spinner de agente sincronizado entre todas as instâncias e limitado a ~12 fps. Reduce Motion é respeitado em todo lugar. Essa é a base certa.
- **Proposta:** um sistema de tokens (`Motion.swift`), componentes dedicados para os três momentos-chave (**painéis**, **agente usando o computador**, **agente sendo lançado**), loops infinitos só em Core Animation, terminal nunca animado e um "Motion Lab" no app. O storyboard é feito na skill (HTML `seek(t)` + Playwright) com as **mesmas curvas e springs** que o Swift vai usar.

---

## 1. Inventário do que existe

### 1.1 `Sources/` (app real, SwiftUI + SwiftTerm)

Busca: `withAnimation|.animation(|.transition(|matchedGeometryEffect|PhaseAnimator|KeyframeAnimator|TimelineView|NSAnimationContext|CABasicAnimation|CAKeyframe|Lottie|spring|symbolEffect|contentTransition|repeatForever|.animator()|reduceMotion`.

| # | Local | O que faz | Avaliação |
|---|---|---|---|
| S1 | `Sources/AgentBox/Workspace/WorkspaceView.swift:179` | `.animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: snapshot.sidebarCollapsed)` no `HStack` raiz (sidebar + workspace) | **Ruim.** (a) A animação fica no ancestral do `TerminalSurface`, então a largura do workspace é interpolada. O provável resultado é o `LocalProcessTerminalView` receber vários `setFrame` em 140 ms. Cada um recalcula cols/rows e manda SIGWINCH, e o TUI do Claude Code/Codex redesenha várias vezes. *Confirmar no Instruments.* (b) A sidebar sai com `if` e transição padrão (opacity). Ela some por fade enquanto o canvas "pula", sem deslizar. (c) 0,14 s com `easeOut` genérico para ~288 pt dá ~2000 pt/s: rápido demais para ler e curto demais para parecer intencional. (d) Ponto positivo: respeita Reduce Motion (`:102`). |
| S2 | `WorkspaceView.swift:630-643` `statusIcon` | `ProgressView().controlSize(.mini)` → `Circle` verde → ícones | **Sem transição.** O spinner do sistema troca seco para um ponto verde. Não há diferença entre "processo vivo" e "agente trabalhando". |
| S3 | `WorkspaceView.swift:706-730` `sessionTabs` | Tabs são `Button` com troca de cor de fundo | **Sem motion.** Nem inserção, nem remoção, nem indicador de tab ativa animado. |
| S4 | `WorkspaceView.swift:925-965` splits / `:1451` `split()` | Novo pane aparece instantâneo; divisor arrastado é imediato | O arrasto imediato está **correto** (AB-006). O split e o fechamento de pane não têm nenhuma transição nem indicação de foco. |
| S5 | `WorkspaceView.swift:203` + 14 rotas `WorkspaceSheet` (`:65-98`); `LibraryView.swift:90-95`; `BrowserComputerPanel.swift:191,197`; `DockerViews.swift:62`; `AgentBoxApp.swift:70` (11 `.sheet(` no total) | Tudo é `.sheet` do sistema: Biblioteca, Pedidos, Lançar agente, Computador, Configurações iniciais… | **Problema estrutural.** A sheet do macOS desce da barra de título com curva fixa e não aceita customização. Ela não suporta matched geometry a partir do botão de origem e fica estranha para painéis grandes (a Biblioteca inteira dentro de uma sheet). Também não dá para encadear "fechar sheet → agente nasce na tab". |
| S6 | `HumanRequestsView.swift:4-26` `HumanRequestBadge` | Cápsula laranja com contagem aparece e some com `if` | **Sem atenção.** Um pedido humano é o evento mais importante do app e chega sem nenhum sinal visual além do número. |
| S7 | `RemoteDesktopView.swift:499-546` | Botões "Assumir"/"Devolver" e texto `"Ao vivo · somente leitura"` / `"Ao vivo · controle humano"` | **Lacuna principal.** Quem está pilotando o computador só aparece em texto 11 pt cinza. Não há borda, cor, cursor fantasma nem transição de handoff. Os estados `connecting/reconnecting/delayed/disconnected` (`:22-29`) também são só texto. |
| S8 | `ProgressView` genérico em `CapturePanel.swift:63,244`, `BrowserComputerPanel.swift:183`, `DockerViews.swift:156`, `AppSettingsView.swift:58`, `ConversationResumeView.swift:98`, `WorkspaceView.swift:635,1640` | Spinner do sistema | Aceitável como fallback, mas aparece imediatamente (sem atraso de ~150 ms) e não informa a etapa. |
| S9 | `WorkspaceView.swift:850` popover do Git | `.popover` do sistema | OK, a animação nativa é adequada. |
| S10 | `HumanRequestCenter.swift:69-90` | `UNUserNotification` com som | OK como canal. Falta o par visual in-app (badge com ripple, banner no viewer) e o *dock badge*. |

**Conclusão §1.1:** o app tem 1 animação, e ela provavelmente prejudica o terminal. Todos os momentos de estado (lançar, trabalhar, esperar, assumir controle) estão sem motion.

### 1.2 `design/` (protótipo e assets do Codex)

| # | Local | O que faz | O que está ruim |
|---|---|---|---|
| D1 | `design/source/AgentBox.swift:122-124` | `.animation(.easeInOut(0.22), value: model.human)`, `.animation(.easeInOut(0.2), value: model.screen)`, `.animation(.easeOut(0.18), value: model.modal)` na raiz | **Animação implícita global.** Qualquer mudança de layout na mesma transação também anima, o que dá o aspecto "mole". `easeInOut` em entradas parece lento no início. Trocar de tela vira crossfade da página inteira. |
| D2 | `design/source/AgentBox.swift:125` | Modal `ModalLayer().transition(.opacity)` | Só opacity: sem escala, sem deslocamento, sem coreografia de backdrop e sem origem. Parece "piscar". |
| D3 | `design/source/AgentBox.swift:126-127` | `AgentPeek` com `.opacity + .scale(0.97, anchor: .topLeading)` e `.spring(response: 0.28, dampingFraction: 0.86)` | **A melhor peça do protótipo.** A âncora vem da origem e o spring é sóbrio. Manter (vira o token `snappy`). |
| D4 | `design/source/AgentBox.swift:128` | Toast `.move(edge: .bottom) + .opacity` | A direção está ok, mas `move(edge:)` desloca a altura inteira da view: o toast "voa" demais. O correto é um offset de 12 pt. |
| D5 | `design/source/Agents.swift:62` | Hover de card `easeInOut(0.18)` | `easeInOut` no hover dá sensação de atraso. Hover pede ease-out curto (0,12 s). |
| D6 | `design/source/Agents.swift:105` | `withAnimation(.easeInOut(0.2)) { agentTab = tab }`; sublinhado da tab em `overlay { if … Rectangle() }` | Sem `matchedGeometryEffect`, o sublinhado **some e reaparece** em vez de deslizar até a tab nova. |
| D7 | `design/source/Agents.swift:18-26` `LiveSurface` | `TimelineView(.animation(minimumInterval: 1/30))` permanente, que redesenha um "navegador fake" com checkmarks progredindo em loop de 8 s | **Custo e mentira.** Reavalia a árvore inteira 30×/s por card, sem pausar quando está invisível, e mostra progresso que não existe. Motion que finge estado destrói a confiança no indicador real. |
| D8 | `design/source/MotionAssetView.swift` + `design/motion/box-loop.mp4` | Mascote em loop de 4 s via `AVQueuePlayer`/`AVPlayerLooper` | Vídeo para animar um ícone: não muda de cor, não reage a estado, decodifica H.264 continuamente e é bitmap. Deve ser vetor nativo (CA/SwiftUI). |
| D9 | `design/motion/box-loop.html:133` | `seek(t)`: `translateY(-4·sin)`, `rotate(1.2°·sin)`, piscada gaussiana fixa em t=2,12 s | A senoide simétrica fica com cara de protetor de tela: sem antecipação, sem pausa. A piscada cai sempre no mesmo instante e fica mecânica. Não está ligada a nenhum estado do produto. |
| D10 | `design/motion/timeline.html:141` (`agentbox-walkthrough.mp4`, 24 s) | 6 screenshots estáticos (`../screens/*.png`) com fade 0,3 s `E.o3`, subida de 8 px e cursor interpolado | **É um slideshow.** Nenhum elemento de UI se move de verdade (tabs, painéis, indicadores), então o vídeo não informa a implementação. A folha `motion-contact-sheet.jpg` confirma: seis telas paradas. |
| D11 | `design/motion/render.sh:5` | `RENDERER=/Users/gabrielgreco/.codex/skills/motion-designer/scripts/render.py` + `tmix=frames=4` | Caminho errado (usuário e pasta `.codex` desta máquina não existem; o certo é `~/.claude/skills/motion-designer/scripts/render.py`). O **motion blur do `tmix` é inadequado para preview de UI**: o app real não tem blur de movimento, então o vídeo parece mais suave do que o app vai ficar. |
| D12 | `design/index.html:3` (CSS) | `.peek` 0,16/0,18 s, `@keyframes dialogIn` 0,2 s `ease-out` 7 px, `.ping` 1,8 s opacidade infinita, `.agent-card:hover translateY(-3px)`, `@media (prefers-reduced-motion)` zera tudo | As durações estão no lugar, mas o `ease-out` do CSS (0,0,.58,1) é fraco. `.ping` pulsa sem significado. O Reduce Motion "mata tudo", inclusive o feedback de estado (o certo é trocar movimento por fade). |
| D13 | `design/index.html:35` `animateStreams` | `requestAnimationFrame` contínuo movendo um cursor em senoide | Mesmo problema de D7: atividade falsa e loop permanente. |

**Diagnóstico de por que "o Codex não fez nenhuma animação que preste":**
1. Animou **por contágio** (`.animation` na raiz) em vez de coreografar elemento por elemento.
2. Usou **uma curva só** (`easeInOut` ~0,2 s) para hover, modal, tela e tab. Sem hierarquia, nada se destaca.
3. Gastou motion em **decoração** (loops fake, mascote em vídeo) e não nos **estados reais** (lançando, trabalhando, esperando, quem controla).
4. O storyboard em vídeo **não continha a UI animada**, só screenshots, então não havia o que portar.
5. Não definiu **tokens**: cada lugar inventou o próprio número.

### 1.3 Requisitos já escritos

`docs/tasks/AB-006-visual.md:13`: "Recolher a sidebar usa transição de 140 ms. Reduzir movimento elimina a animação. Arrastar divisórias continua imediato." Mantemos o espírito (Reduce Motion, arrasto imediato) e revisamos a técnica (§4.D).

---

## 2. Como o Orca anima (referência extraída)

Orca é Electron + React + Tailwind/Radix (shadcn). Analisei o CSS compilado (`out/renderer/assets/I18nProvider-*.css`) e componentes JS. Tokens e padrões encontrados:

| Padrão | Valores exatos no Orca | Lição para o Agent Box |
|---|---|---|
| Transição padrão | `--default-transition-duration: .15s`, `cubic-bezier(.4,0,.2,1)`; utilitários mais usados: `duration-150` (30×), `duration-200` (29×), `duration-300` (21×), `ease-out` (96×) | A base é **150–200 ms ease-out**. Animações longas são exceção. |
| Diálogos/menus (Radix) | `data-[state=open]:animate-in fade-in-0 zoom-in-95` / `closed: fade-out-0 zoom-out-95`, `slide-in-from-{top,bottom,left,right}-2` (8 px), 150 ms | Escala 0,95→1 + fade + 8 px de origem. A saída é mais curta que a entrada. |
| Conteúdo entrando | `browserTabIn` 320 ms `cubic-bezier(.2,.8,.2,1)` (`translateY(-2px)`→0); `browserViewIn` 360 ms; `tasks-workspace-in` 320 ms (4 px); `md-block-in` 380 ms (−2 px) | Deslocamentos **minúsculos** (2–4 px) com curva desacelerada longa. Fica elegante sem chamar atenção. |
| Painel lateral (kanban sheet) | Abre: `clip-path inset(0 100% 0 0)→inset(0)` 300 ms `cubic-bezier(.16,1,.3,1)`; fecha: 200 ms `cubic-bezier(.7,0,.84,0)` | **Revelar por recorte** em vez de deslizar o painel: o conteúdo não se move, a janela "abre". A saída usa ease-in rápido. |
| Expansão de grupo | `grid-template-rows 0fr→1fr` 180 ms `(.16,1,.3,1)`; colapsável 200/180 ms; revelação longa 700 ms `cubic-bezier(.32,.72,0,1)` | Altura animada por clip, com a curva iOS-like para revelações grandes. |
| Configurações | `settings-shell-enter` 180 ms ease-out, `translateY(8px)`→0 | Trocar de seção = fade + 8 px. |
| **Agente trabalhando** | `AgentStateDot`: `working` = anel `border-2 border-yellow-500 border-t-transparent` girando; `animation: 86400s steps(1036800) infinite` (≈12 passos/s, ou seja, **~12 fps de propósito**); no `onAnimationStart` faz `startTime = 0` em todas as instâncias, então **todos os spinners giram em fase**; com Reduce Motion fica parado e completo | Indicador barato e **sincronizado**: dez agentes trabalhando não viram um "formigueiro". |
| Outros estados de agente | `monitoring` (ícone activity amarelo), `done` (circle-check esmeralda), `waiting`/`permission` (ícone de pergunta), `blocked/interrupted/failed` (ponto vermelho), `idle` (ponto neutro 40%), `unverifiable` (círculo tracejado âmbar) | Taxonomia de estados a copiar (§4.E). **Só "working" se move.** |
| Localizar pane | `pane-focus-rim-flash`: borda 1,5 px + `box-shadow 0 0 0 2px, 0 0 18px` na cor `--terminal-pane-locate`; opacidade 1 → .42 (24%) → 0 (46%), 1,5 s ease-out, uma vez | O "onde está?" vira um flash de borda, sem mexer o terminal. |
| Localizar workspace | `scroll-to-current-workspace-reveal-glow` 1,5 s: escala .992→1→1.006 + fade | Destaque pontual de item revelado na sidebar. |
| Anel de atenção (tour) | `contextual-tour-target-ring` 1,8 s: escala .68→2.4, opacidade .72→0 | Ripple para "olhe aqui", reaproveitado para pedido humano. |
| Clique demonstrativo | `feature-wall-click-ring` 460 ms: escala .4→1.4, opacidade .9→0 | Ripple de clique do **cursor do agente** no desktop. |
| Toast/atualização | `update-card-enter` 200 ms ease-out a partir de `translateX(100%)`; exit 150 ms ease-in | Saída curta e sem movimento. |
| Barras | `transition-all duration-300` na largura | Contadores e barras interpolam em 300 ms. |
| Reduce Motion | `motion-reduce:animate-none`, `@media (prefers-reduced-motion)` em cada keyframe; JS checa `matchMedia` | Cada animação tem um **fallback desenhado** (spinner vira anel estático completo), não um "desligar tudo". |

Leitura geral: o Orca **não anima o terminal nem o layout dos panes**. Toda a vida visual está em indicadores pequenos, overlays e painéis. Esse é o recorte certo para nós também.

---

## 3. Sistema de motion proposto (tokens)

Implementar como `Sources/AgentBox/Design/Motion.swift` e espelhar em `design/motion/tokens.json` (consumido pelos storyboards HTML; ver §6).

### 3.1 Durações

| Token | s | Uso |
|---|---|---|
| `press` | 0,08 | escala ao pressionar |
| `hover` | 0,12 | fundo/cor no hover, troca de cor de status |
| `fast` | 0,16 | popovers, saídas, tooltips |
| `base` | 0,24 | tabs, linhas da sidebar, toasts, conteúdo entrando |
| `panel` | 0,32 | painéis/overlays abrindo |
| `reveal` | 0,48 | sequências (lançamento, handoff) |
| `flash` | 1,5 | rim flash / glow de localização (one-shot) |
| `ambient` | 1,2–3,2 | loops (spinner 0,9; respiração 1,6; borda viva 3,2) |

Regra: **saída = 60–70% da entrada**. Nada de UI direta passa de 0,5 s. Sequências longas são feitas de passos curtos.

### 3.2 Curvas e springs (valores para SwiftUI, macOS 14)

```swift
enum Motion {
  // Curvas
  static let standard = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)   // Orca: conteúdo entrando
  static let expoOut  = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)    // painéis, reveals
  static let sheet    = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.36)   // painéis grandes / sidebar
  static let exit     = Animation.timingCurve(0.7, 0, 0.84, 0, duration: 0.18)    // saídas
  static let hover    = Animation.easeOut(duration: 0.12)
  // Springs (sem bounce perceptível em UI de trabalho)
  static let snappy   = Animation.spring(response: 0.28, dampingFraction: 0.86)   // seleção, tabs, peek (D3)
  static let panel    = Animation.spring(response: 0.36, dampingFraction: 0.90)   // overlays, hero morph
  static let lively   = Animation.spring(response: 0.40, dampingFraction: 0.72)   // SÓ chegada de agente e badge
  // Distâncias
  static let micro: CGFloat = 4, small: CGFloat = 8, large: CGFloat = 16
  static let stagger = 0.035   // listas nativas (cap 6 itens = 210 ms)
}
```

Princípios (vêm de `craft.md` da skill e do Orca):
- **Um movimento principal por vez.** Saídas terminam antes de entradas na mesma área.
- **Motion = estado.** Loop só onde há trabalho real acontecendo. Nada de atividade fingida (D7, D13).
- **Se o olho precisa perseguir o movimento, está rápido demais** (craft §3). Deslocamentos de 2–8 pt, nunca a altura da view.
- **Origem motivada:** o que abre a partir de um botão nasce do botão (âncora/matched geometry).
- **Atrasar spinners em 150 ms** e exibir cada micro-etapa por pelo menos 120 ms, para não piscar.

### 3.3 Reduce Motion, transparência e energia

| Situação | Comportamento |
|---|---|
| `accessibilityReduceMotion` (SwiftUI) / `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (AppKit/CA) | Translações e escalas viram **crossfade 0,15 s**. Loops viram **estado estático** (spinner = anel completo + texto; respiração = cor sólida). Ripples viram mudança de cor. Cor e ícone de estado continuam iguais. |
| `accessibilityDisplayShouldReduceTransparency` | Sem glow/blur. Bordas sólidas. |
| Janela ocluída (`NSWindow.occlusionState`) ou app inativo | Pausar todos os loops decorativos (`layer.speed = 0`). Os de estado podem seguir só na sidebar visível. |
| Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`) | `preferredFrameRateRange` máximo 30 fps nos loops. |
| VoiceOver | Mudanças de estado relevantes (agente esperando você, controle transferido) disparam `AccessibilityNotification.Announcement`. |

### 3.4 Regras de performance (o terminal não pode perder fps)

1. **Nunca animar o frame do `TerminalSurface`** nem colocar `.animation` em ancestrais dele. Mudanças de layout que afetam o terminal fazem **um único resize no fim** (ou no início) da animação. Durante a animação, o terminal fica com o tamanho antigo, recortado (`clipped`), e o resize do PTY é adiado (`TerminalSurface` ignora `layout()` enquanto `MotionPolicy.layoutTransitionInFlight`; aplica no `completion` de `withAnimation(_:completionCriteria:_:completion:)`).
2. **Loops infinitos em Core Animation** (render server), não em `TimelineView`/`withAnimation(.repeatForever)` que reavaliam SwiftUI no main thread. `CABasicAnimation` com `preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)` para não puxar 120 Hz no ProMotion.
3. **Fase sincronizada** (truque do Orca): `anim.beginTime = CACurrentMediaTime() - fmod(CACurrentMediaTime(), period)` em todo indicador do mesmo tipo.
4. **Isolar folhas animadas.** `WorkspaceView` tem 1.682 linhas e um `@State snapshot` gigante: qualquer toggle reavalia tudo. O rebuild deve ter modelos `@Observable` por linha/pane, para que um badge pulsando não invalide o pane do terminal.
5. Overlays sobre o terminal (rim flash, borda de foco) são `CALayer`/views irmãs com `allowsHitTesting(false)`, sem `shadow`/`blur` permanentes sobre área de texto que está fazendo streaming.
6. **Medição obrigatória:** Instruments → *Animation Hitches* + *SwiftUI*, com 4 terminais rodando `yes | pv -qL 2000000` (ou `cat` de arquivo grande) enquanto se dispara cada animação. Meta: 0 hitches a 120 Hz e nenhum resize extra de PTY (logar `sizeChanged` em `TerminalRuntimeManager.swift:36`).

---

## 4. Catálogo de momentos e animação proposta

Legenda de técnica: **SUI** = SwiftUI (transition/spring/matchedGeometry), **KA** = `KeyframeAnimator`, **PA** = `PhaseAnimator`, **CA** = Core Animation em `NSViewRepresentable`, **TV** = `Canvas`+`TimelineView` (só curta duração).

### A. App e janela

| Momento | Animação | Duração / curva | Técnica | Reduce Motion |
|---|---|---|---|---|
| A1 Abrir o app | Conteúdo da janela: fade 0→1. Linhas da sidebar sobem 4 pt com stagger 35 ms (máx. 6). Terminais restaurados aparecem já no estado "Pronto para iniciar", **sem** animação. | 0,24 `standard`; stagger 0,035 | SUI (`.transition` + `onAppear` com delay por índice) | fade 0,15 só no container |
| A2 Primeira execução (setup) | Substituir a sheet `AgentBoxApp.swift:70` por um onboarding em overlay de passos: passo novo entra +16 pt/fade, antigo sai −8 pt/fade. Barra de progresso interpola. | 0,32 `expoOut` / saída 0,18 `exit` | SUI | crossfade |
| A3 Estado vazio (sem sessões) | A marca Agent Box se desenha uma vez (traço `trim` 0→1, depois preenchimento). O texto sobe 4 pt. **Sem loop.** | 0,6 `expoOut` + 0,24 | SUI (`Shape.trim`) ou CA | estático |

### B. Sessões e sidebar

| Momento | Animação | Duração / curva | Técnica | Reduce Motion |
|---|---|---|---|---|
| B1 Criar sessão | A linha nasce: altura 0→28 por clip, fade e 4 pt de subida. O destaque de seleção **desliza** da linha anterior para a nova. O workspace faz crossfade. | `lively` (só aqui) + `snappy` na seleção | SUI: `matchedGeometryEffect(id:"selection")` | fade |
| B2 Trocar de sessão | Seleção desliza (`snappy`). Conteúdo do workspace: saída 80 ms, entrada 160 ms (fade). **Sem slide** (terminais pesados). | 0,08 + 0,16 | SUI; terminal sem animação própria | fade |
| B3 Expandir/recolher sessão ou subagentes | Chevron gira 90°. Filhos revelados por clip de altura (padrão grid-rows do Orca), com 2 pt de subida. | 0,18 `expoOut`; chevron 0,18 `standard` | SUI (container `.clipped()` + `.transition(.move(edge:.top).combined(.opacity))`) | instantâneo |
| B4 Filtrar (busca) | Linhas que saem: fade + colapso. Trecho que casa com a busca ganha fundo realçado 0,12. | 0,16 `exit` | SUI | instantâneo |
| B5 Renomear | O rótulo vira campo no lugar (fundo surge 0,12). Ao confirmar, o texto novo faz `contentTransition(.interpolate)`. | 0,12 / 0,24 | SUI | — |
| B6 Fechar/remover sessão | Linha: fade + altura→0. Toast "Desfazer" entra (C5). | 0,18 `exit` | SUI | fade |
| B7 Hover em linha | Fundo 0→`selection` 50%. Prévia (peek) após 350 ms: escala .97→1 + fade, âncora no canto da linha (padrão D3). Saída 0,1. | 0,12 `hover`; peek `snappy` | SUI | sem escala |
| **B8 Recolher sidebar (substitui S1)** | A sidebar **desliza** para fora (`offset x = −largura`) como camada sobre o canvas, com fade dos rótulos nos primeiros 40%. O workspace muda de largura **uma vez**: ao recolher, no fim; ao expandir, no início, com a sidebar entrando por cima da área já reservada. O terminal nunca é redimensionado quadro a quadro. Alternativa equivalente: congelar o resize do PTY durante a animação (§3.4-1). | 0,30 `sheet` / volta 0,26 | SUI + `completion` | instantâneo (como AB-006) |
| B9 Arrastar divisor da sidebar/split | **Imediato** (manter). Duplo clique para resetar: uma linha-guia anima até a posição nova (0,2 `standard`) e o layout é aplicado uma vez no fim. | 0,2 | SUI | aplica direto |

### C. Tabs, panes, toasts, painéis

| Momento | Animação | Duração / curva | Técnica | Reduce Motion |
|---|---|---|---|---|
| C1 Abrir tab | A tab entra com fade + `y −2 pt` + `scaleX .96→1` (âncora leading). As vizinhas abrem espaço com spring. O indicador de tab ativa (fundo/linha 2 pt) **desliza** até ela. | 0,32 `standard` (Orca `browserTabIn`); indicador `snappy` | SUI: `matchedGeometryEffect(id:"activeTab")` | fade |
| C2 Fechar tab | Fade 0,12, depois largura→0 0,18 `exit`. O indicador desliza para a próxima. | 0,12 + 0,18 | SUI | instantâneo |
| C3 Reordenar tab (drag) | A tab levantada sobe para escala 1,02 + sombra. As outras abrem espaço com `snappy`. | `snappy` | SUI | sem escala |
| C4 Split | (1) O divisor "se desenha" do centro para as pontas (`scaleY 0→1`). (2) O pane novo aparece como placeholder (cor do canvas + marca do provider), com fade. (3) O terminal real entra no tamanho final, fade 0,12. O pane existente redimensiona **uma vez**. | 0,22 `expoOut` + 0,12 | SUI (placeholder) + regra §3.4 | fade |
| C5 Fechar pane | O pane faz fade 0,14, o divisor recolhe e o irmão ocupa o espaço em um resize único. | 0,14 `exit` | SUI | instantâneo |
| C6 Focar/localizar pane | **Rim flash** do Orca: borda 1,5 pt + halo 18 pt na cor de destaque; opacidade 1 → .42 (24%) → 0 (46%), uma vez. Só em navegação por teclado, "Abrir terminal" vindo de um pedido ou notificação. Clique comum só troca a cor do cabeçalho (0,12). | 1,5 s ease-out | CA (`CAKeyframeAnimation` opacity, `keyTimes [0,.24,.46,1]`) em layer sobreposta | borda estática 0,6 s |
| C7 Janela estreita (1 pane só, `WorkspaceView.swift:686-687`) | Crossfade entre layout em grade e pane único. | 0,16 | SUI | — |
| C8 Toast in-app | Sobe 12 pt + fade (não `move(edge:)`). Empilha com `snappy`. Sai com fade + 4 pt. Desfazer e erros não bloqueantes passam por aqui. | 0,24 `expoOut` / 0,16 `exit` | SUI | fade |
| **C9 Painéis/overlays (substitui sheets S5)** | Para fluxos principais (Nova sessão, Novo terminal, Lançar agente, Pedidos, Computador, Retomar conversa): **overlay dentro da janela**. Backdrop 0→0,45 (linear 0,2). Painel: opacidade 0→1, escala .96→1, `y +8→0`, **transform-origin no botão que abriu** (ou matched geometry botão→painel). Conteúdo interno com stagger 35 ms. Fecha: opacidade + escala .98 em 0,16 `exit`, backdrop 0,2. | `panel` (0,36 / 0,90) | SUI: host `OverlayPanelHost` com `@Namespace` | fade 0,15 |
| C10 Painéis laterais (Biblioteca, Pedidos, Computador acoplado) | Revelação por **recorte** da borda (padrão kanban do Orca: `clip inset 100%→0`). O conteúdo não desliza. Sombra/borda interna aparece no fim. Fecha com recorte reverso. | abre 0,30 `expoOut`; fecha 0,20 `exit` | SUI (`.mask` com `Rectangle` animando largura) ou CA (`mask` layer) | fade |
| C11 Alertas destrutivos (forçar encerramento, sair) | Manter `NSAlert`/`.confirmationDialog` nativos. | sistema | — | — |
| C12 Popovers (Git, tooltips) | Manter os nativos. | sistema | — | — |

### D. Hover, press, foco, erros, vazios

| Momento | Animação | Duração / curva | Técnica |
|---|---|---|---|
| D1 Press de botão | Escala .97 ao pressionar e volta com `snappy`. Primários: fundo escurece 6%. | 0,08 easeOut | `ButtonStyle` com `configuration.isPressed` |
| D2 Hover de botão/ícone | Fundo 0→8% branco, ícone 70%→100%. **Sem escala** em superfícies grandes. | 0,12 `hover` | SUI |
| D3 Hover de card (Biblioteca) | `y −2 pt`, borda clareia, sombra +2. | 0,18 `standard` | SUI |
| D4 Erro inline (formulário) | Mensagem: fade + 4 pt. Campo: borda vermelha. **Shake** horizontal (3 ciclos, amplitude 6 pt) só em submit inválido. | 0,2 / shake 0,3 | KA (offset x keyframes) |
| D5 Terminal falhou ao iniciar | Rim flash (C6) em **vermelho**, uma vez. O conteúdo de erro sobe 4 pt com fade. | 1,2 s + 0,24 | CA + SUI |
| D6 Processo encerrou | O terminal escurece com overlay 0→35% preto e o rótulo "Encerrado · código X" faz fade. Botão "Reiniciar" entra com stagger. | 0,24 | SUI (overlay irmão) |
| D7 Estados vazios | One-shot de desenho (traço + texto subindo), sem loop. | 0,6 `expoOut` | SUI `trim` |
| D8 Contadores (badges, capturas, custo) | `contentTransition(.numericText())` + "bump" de escala 1→1,15→1. | `lively` | SUI |
| D9 Loading de listas (retomar conversa, Docker) | Skeleton com brilho varrendo (gradiente em máscara, 1,4 s linear), mostrado após 150 ms. Resultados entram com stagger 35 ms. | 1,4 linear / 0,24 | CA (gradient layer) |

### E. Agentes: os três momentos principais

#### E0. Pré-requisito de dados (sem isto o motion vai mentir)
Hoje o app só conhece `TerminalProcessState` (`idle/starting/running/exited/failed`, `TerminalRuntimeManager.swift:7-12`) e hooks `sessionStart/subagentStart/subagentStop` (`AgentRunRegistry.swift:21`). Para animar **trabalhando / ocioso / esperando input** é preciso um `AgentActivityState`, alimentado pelos hooks do Claude Code (`UserPromptSubmit`/`PreToolUse` → `working`; `Stop` → `done`/`idle`; `Notification` com `permission_prompt` → `permission`; `idle_prompt` → `waiting`) e pelo `notify` do Codex. Os estados copiam a taxonomia do Orca: `working, waiting, permission, blocked, failed, done, idle, unverifiable`.

#### E1. Indicador de estado do agente (sidebar, tab, cabeçalho de pane, thumbnail)

| Estado | Visual | Movimento | Técnica |
|---|---|---|---|
| `working` | Arco de 270° (2 pt) na cor do provider (Claude laranja / Codex neutro) em volta da marca | Rotação 0,9 s linear infinita, **fase sincronizada** entre todas as instâncias, 24–30 fps | CA: `CAShapeLayer` + `transform.rotation.z`, `preferredFrameRateRange` |
| `waiting` / `permission` | Ponto âmbar + glifo "?" | **Entrada:** ripple (anel escala .6→2,4, opacidade .72→0, 1,2 s ease-out) **duas vezes e para**. Depois respiração lenta (opacidade .6↔1, 1,6 s ease-in-out) só enquanto a janela não estiver em foco no terminal dono. Badge com bump (D8). | CA (ripple + respiração) |
| `done` | Check esmeralda | O arco de `working` **fecha o círculo** (trim → 1, 0,24) e vira check (desenho do traço 0,24). Após 2 s esmaece para o ponto neutro. | SUI `KeyframeAnimator` (trim, opacity) |
| `failed` / `blocked` | Ponto vermelho | Troca com crossfade + escala .6→1 (0,18). **Sem loop.** | SUI |
| `idle` | Ponto neutro 40% | Nenhum | — |
| `unverifiable` | Círculo tracejado âmbar | Nenhum | — |

Transição entre estados: `contentTransition(.symbolEffect(.replace))` (macOS 14) para glifos SF, crossfade 0,18 para os demais. Reduce Motion: arco completo estático (como o Orca), ripple vira mudança de cor.

#### E2. Agente solicitado → sendo lançado ("Ignição")
Fases reais: pedido (botão Lançar no `AgentLaunchView`, ou hook `subagentStart`) → preparação (memórias, skills, worktree, binding; `AgentLaunchPlanner`) → `starting` → primeiro byte no PTY → `running` + `working`.

| t (s) | O que acontece | Curva | Técnica |
|---|---|---|---|
| 0,00 | O botão "Lançar" morfa: o rótulo sai (fade 0,08) e um mini-arco entra no botão. | `snappy` | SUI `contentTransition` |
| 0,08 | O painel de lançamento (overlay C9, não sheet) fecha **em direção à tab de destino**: escala .98 e a origem passa a ser a tab. Ao mesmo tempo, um **chip** (marca do provider em cápsula) se destaca do botão e viaja em arco até a posição da tab/linha nova. | chip: `KeyframeAnimator`, x com `standard` 0,42 s, y com `expoOut`, escala 1→.8→1 | SUI KA + `matchedGeometryEffect` (só funciona porque é overlay na mesma janela) |
| 0,42 | O chip "pousa": a tab nasce (C1) com `lively` e a linha da sidebar nasce (B1). Um ripple curto de 0,46 s sai do ponto de pouso. | `lively` | SUI + CA |
| 0,42→N | **Placeholder de ignição** no pane: marca do provider centralizada com halo radial suave respirando (escala 1↔1,04, opacidade .5↔.8, 1,2 s) e um brilho varrendo a grade vazia do terminal (gradiente 1,4 s linear). Abaixo, um checklist real das etapas (`Memórias ✓ · Skills ✓ · Worktree ✓ · Iniciando claude…`): cada linha entra com 4 pt + fade, e o check se desenha (trim 0,18). Mínimo de 120 ms por linha, sem atraso artificial. | linhas 0,24 `standard` | CA (halo/brilho) + SUI (lista) |
| primeiro byte | O halo **colapsa para a posição do cursor** (escala 1→0, 0,22 ease-in) e o terminal faz fade 0→1 em 0,16. O indicador passa a `working`. | `exit` + 0,16 | SUI/CA |
| falha | O arco fica vermelho, um X se desenha, rim flash vermelho (D5) e o erro sobe 4 pt. | 0,24 | KA |

Regras: se `starting→running` levar menos de 300 ms, **pular o placeholder** (vai direto para o fade do terminal). Se o lançamento vier de um hook (subagente nativo), não há chip voando: a linha filha "brota" da linha pai (E3). Reduce Motion: sem chip, sem halo; o checklist aparece com fade e o terminal entra com fade.

#### E3. Subagente spawnando container Docker
| Fase | Visual | Duração / curva | Técnica |
|---|---|---|---|
| `subagentStart` | Na sidebar, o conector em L (hoje `arrow.turn.down.right`, `WorkspaceView.swift:574`) **se desenha** do pai até a posição do filho (trim 0→1), depois a linha filha sobe 4 pt com fade. Vários filhos: stagger 60 ms. | conector 0,24 `expoOut`; linha 0,24 | SUI `Path.trim` |
| Provisionando computador (imagem → container → browser pronto) | Ícone de **caixa isométrica**: contorno tracejado com "formigas marchando" (`lineDashPhase`, 0,8 s linear) enquanto espera. Cada etapa concluída preenche uma face (fade 0,2): 3 faces = 3 etapas reais do `BrowserComputerService`. | marching 0,8 s; faces 0,2 `standard` | CA (`CAShapeLayer.lineDashPhase`) |
| Pronto | A caixa "fecha": tracejado vira sólido, pop 1→1,06→1 e tick verde se desenha. | `lively` / 0,24 | SUI KA |
| Falha | Face vermelha + rótulo do erro. Sem pop. | 0,2 | SUI |

É preciso expor eventos de etapa do serviço Docker para a UI (hoje são erros/retornos assíncronos).

#### E4. Computador usado pelo agente × humano assumindo o controle
Estados reais: `DesktopConnectionState` (`RemoteDesktopView.swift:22-29`) + `ControlGrant.Kind {human, agent, nativeChild}` (`ControlBroker.swift:10`) + fase `revoking`.

| Momento | Animação | Duração / curva | Técnica |
|---|---|---|---|
| **Agente pilotando** | (1) **Borda viva** no viewer: traço 1,5 pt com gradiente cônico na cor do agente girando devagar, opacidade 0,7. (2) Pill no cabeçalho com a marca do agente + arco `working` + "Claude está usando". (3) **Cursor fantasma** do agente (se o broker expuser a última coordenada de input): move com spring e mostra ripple de clique (escala .4→1,4, opacidade .9→0, 0,46 s). Digitação acende um glifo de teclado (0,12). (4) Na sidebar/thumbnail, um ícone de "tela em uso" com o arco sincronizado. | borda 3,2 s linear; cursor `spring(response: 0.35, dampingFraction: 0.85)`; ripple 0,46 ease-out | CA (`CAGradientLayer type .conic` + máscara de borda, rotação); SUI p/ pill e cursor |
| Frames do stream | Troca **imediata** (fidelidade). Só se o fps cair abaixo de 4: crossfade de 80 ms entre frames. | — | `DesktopCanvasView` |
| Humano clica "Assumir" → `revoking` (esperando ACK do agente) | O botão vira "Pedindo controle…" com mini-arco. A borda viva **acelera** (1,2 s) e dessatura, sinalizando que o agente está largando. | 0,24 | CA (`speed`) |
| Controle concedido ao humano | **Handoff:** a borda morfa da cor do agente para a cor "humano" (branco/âmbar quente) em 0,3 s. Um anel contrai das bordas para dentro (inset 0→6 pt, opacidade 1→0) **uma vez**. A pill troca o texto com slide vertical ("Você está no controle") e o glifo vira cursor. O cursor fantasma do agente some (fade 0,16). A pill do agente na sidebar mostra "pausado". | 0,36 `expoOut` | SUI KA + CA |
| Humano clica "Devolver" | Sequência reversa: o anel expande para fora, volta a cor do agente e a borda viva retoma a rotação. | 0,36 | idem |
| Agente pede ajuda (HumanRequest pendente, ex.: captcha) | Borda âmbar com respiração (1,6 s). Banner desce de dentro do topo do viewer ("O agente precisa de você · Assumir") por revelação de clip, não com o banner inteiro voando. Badge da sidebar faz ripple (E1). Fora de foco: `UNNotification` (já existe), *dock badge* e `NSApp.requestUserAttention(.informationalRequest)`. | banner 0,30 `sheet` | SUI + CA |
| `connecting` | Skeleton com brilho varrendo no lugar do frame. | 1,4 linear | CA |
| `reconnecting` / `delayed` | O último frame dessatura para 40% (0,3), com pill "Reconectando" e 3 pontos em sequência (stagger 0,15, loop). `delayed`: pill âmbar sem loop. | 0,3 | SUI + CA |
| `disconnected` | Frame escurece 0,3 e overlay com ação entra com fade + 4 pt. | 0,3 / 0,24 | SUI |

Reduce Motion: borda estática na cor de quem controla (é a informação essencial), sem rotação nem anel. A troca de cor continua, em crossfade de 0,15.

### F. Biblioteca, configurações, pedidos

| Momento | Animação | Duração / curva | Técnica |
|---|---|---|---|
| F1 Abrir Biblioteca | Painel lateral (C10) ou tela própria. Grid de cards com stagger 35 ms. | 0,30 `expoOut` | SUI |
| F2 Card → detalhe do agente | **Hero morph:** avatar e título viajam do card para o cabeçalho do detalhe, e o resto entra com fade + 8 pt. | `panel` | SUI `matchedGeometryEffect` |
| F3 Tabs internas (Memória/Histórico/Boxes/Skills) | Sublinhado desliza (corrige D6). O conteúdo faz crossfade + 8 pt na direção da tab. | `snappy` / 0,24 | SUI |
| F4 Salvar memória/agente | O botão vira check desenhado (0,24) e volta ao normal depois de 1,2 s. | 0,24 | SUI KA |
| F5 Configurações (cena `Settings`) | Troca de seção = fade + 8 pt (Orca `settings-shell-enter`, 0,18 ease-out). A altura da janela é animada pelo AppKit (`setFrame(_:display:animate:)`). | 0,18 | SUI + AppKit |
| F6 Inbox de pedidos | Item novo entra no topo com `lively`. Item resolvido risca + fade e colapsa. | `lively` / 0,18 `exit` | SUI |

### G. Prioridade

- **P0:** tokens + `MotionPolicy` (§3), B8 (corrige S1), C9/C10 (painéis no lugar das sheets), E1 (indicadores), E2 (ignição), E4 (controle do computador). Depende de E0 (estados de atividade).
- **P1:** C1–C6 (tabs, split, rim flash), C8 (toasts), D1–D6, E3 (Docker), F6.
- **P2:** F1–F5, A1–A3, D7–D9.

### H. Lottie / Rive?
- **Não usar Lottie no P0/P1.** Tudo acima é vetor simples (arcos, traços, gradientes) que SwiftUI/CA fazem com custo menor, cores dinâmicas por estado e Reduce Motion nativo. Lottie é uma dependência a mais, com controle de estado pobre e a mesma limitação de fps.
- **Rive** só valeria para um **mascote/marca com estados** (state machine: idle → working → waiting → done), caso se queira personagem. O `box-loop` (D8/D9) atual não justifica. Se for adotado, só no estado vazio e no onboarding, nunca perto do terminal.
- **Remover** `MotionAssetView`/AVPlayer como técnica para ícones.

---

## 5. Componentes a construir no rebuild

| Componente | Responsabilidade |
|---|---|
| `Motion` (tokens) + `MotionPolicy` (`@Observable`: reduceMotion, reduceTransparency, occluded, lowPower, `layoutTransitionInFlight`) | Fonte única de curvas, springs e políticas |
| `AgentStateIndicator` (CA) | E1, fase sincronizada, `preferredFrameRateRange` |
| `OverlayPanelHost` + `SidePanelHost` | C9/C10, origem no botão, foco e Esc |
| `LaunchIgnitionView` + `LaunchChip` | E2 |
| `ComputerControlFrame` (borda viva, handoff, banner, cursor fantasma) | E4 |
| `BoxProvisioningGlyph` | E3 |
| `RimFlash` (CA) | C6/D5 |
| `ToastCenter` | C8 |
| `MotionLab` (cena só em DEBUG) | Lista de todos os momentos, botão "disparar", **scrub de t**, slow-mo 5× (`CATransaction`/`layer.speed = 0.2`), toggle Reduce Motion simulado, botão "estressar terminais" |

---

## 6. Workflow: skill de motion → storyboard → SwiftUI

### 6.1 O que a skill é
`~/.claude/skills/motion-designer` (genérica) e `labrynth-motion-design` (com brand kits, em `~/Desktop/Labrynth/labrynth-motion-design/`). Método: timeline HTML/SVG **determinística** (`window.seek(t)` função pura de t, `MARK` com eventos nomeados, sem `Date.now`/CSS transitions/`Math.random`) → Playwright captura frame a frame (`scripts/render.py`, `--test` gera contact sheet, `--sweep` checa layout) → ffmpeg (`encode.sh`). Helpers em `templates/timeline.html`: `seg/clamp/lerp`, easings `E.o3/o5/i3/io3`, `fade()`, `hlA()`. Regras de `references/craft.md` que valem para UI: "um movimento por vez", "se o olho precisa perseguir, está rápido demais", "saídas terminam antes de entradas", "pessoas julgam animação, não stills", "versões paralelas por agentes independentes". Tokens Labrynth (`brands/labrynth.md §5/§10`): `expo-out cubic-bezier(.16,1,.3,1)` como física única, 300/500/700 ms, stagger 70–110 ms, sem bounce.

A skill é voltada para **vídeos sociais** (intake de idioma, plataforma, narração, safe zones). Para UI: **pular o intake** e usar só `templates/timeline.html` + `render.py` + `encode.sh`, com `--ar` customizado (ex.: `1440x900` para a janela, `480x320` para um componente).

### 6.2 Pipeline proposto
1. **Tokens compartilhados.** Criar `design/motion/tokens.json` (durações, béziers, springs). O HTML lê o JSON e um script gera `Motion.swift`. O que se vê no vídeo usa os mesmos números do app.
2. **Spring idêntico ao SwiftUI no HTML.** Implementar no template a resposta do oscilador amortecido com os parâmetros do SwiftUI: `ω0 = 2π/response`, `ζ = dampingFraction`, `ωd = ω0·√(1−ζ²)`, `x(t) = 1 − e^(−ζω0t)·(cos ωd·t + (ζω0/ωd)·sin ωd·t)`. Béziers: `cubic-bezier` com solver (o mesmo que o CSS usa).
3. **Um storyboard por momento-chave** (E2 ignição, E4 handoff, C9 painel, E1 estados, B8 sidebar), cada um com a **UI real recriada em HTML** (as cores e tipos do rebuild, não screenshots: o oposto de D10), `MARK`s nomeados por fase (ex.: `PRESS, CHIP_LAND, FIRST_BYTE`) e, para estados, uma cena que percorre todos.
4. **Variações A/B/C** com agentes independentes (regra da skill): por exemplo, três propostas de handoff de controle. Renderizar draft 60 fps, meia resolução, e o dono escolhe **assistindo**.
5. **Render para UI:** 60 fps (e 120 fps quando for avaliar ProMotion), **sem `tmix`/motion blur** (corrige D11, que também tem o caminho do renderer errado). Também gerar contact sheet a 30 fps para revisão quadro a quadro e um GIF/MP4 em slow-mo 4×.
6. **Port para SwiftUI:** cada `MARK` vira um passo de `PhaseAnimator`/`KeyframeAnimator` ou um `withAnimation(...){ } completion:`. Durações e curvas vêm dos tokens. Loops viram `CABasicAnimation` (§3.4).
7. **Validação no app:** o **Motion Lab** dispara a mesma cena, com scrub e slow-mo. Gravar com `screencapture -v` e comparar lado a lado com o MP4 do storyboard. Instruments com terminais em stress (§3.4-6). Por fim, Reduce Motion ligado.

### 6.3 O que é viável e o que não é

| Viável no storyboard HTML | Só no app |
|---|---|
| Coreografia (ordem, stagger, sobreposição), escolha de curvas/springs, estilo dos indicadores (arco, ripple, borda viva, halo), handoff de cores, comparar variações em vídeo | Animação de `.sheet`/janelas do sistema, materiais com vibrancy (`NSVisualEffectView`), SF Symbols effects, comportamento real do SwiftTerm (resize/SIGWINCH), custo real de CPU/GPU e hitches, 120 Hz real, foco/teclado |

Ou seja: a skill serve para **decidir o desenho e o tempo** e entregar referência em vídeo. A verdade final é o Motion Lab + Instruments. Não usar o vídeo do storyboard dentro do app (como foi feito com `box-loop.mp4`).

---

## 7. Arquivos citados
- `Sources/AgentBox/Workspace/WorkspaceView.swift` (`:102`, `:179`, `:203`, `:630-643`, `:706-730`, `:925-965`)
- `Sources/AgentBox/Computers/RemoteDesktopView.swift` (`:22-29`, `:499-546`)
- `Sources/AgentBox/Computers/HumanRequestsView.swift` (`:4-26`), `HumanRequestCenter.swift` (`:69-90`)
- `Sources/AgentBox/Terminal/TerminalRuntimeManager.swift` (`:7-12`, `:36`, `:382`)
- `Sources/AgentBoxCore/Control/ControlBroker.swift` (`:10`, `:48-66`), `Sources/AgentBoxCore/AgentRegistry/AgentRunRegistry.swift` (`:18-21`)
- `design/source/AgentBox.swift` (`:122-128`), `design/source/Agents.swift` (`:18-26`, `:62`, `:105`), `design/source/MotionAssetView.swift`
- `design/motion/box-loop.html:133`, `design/motion/timeline.html:141`, `design/motion/render.sh:5`, `design/index.html:3,35`
- `docs/tasks/AB-006-visual.md:13`
- Skill: `~/.claude/skills/motion-designer/{SKILL.md,references/craft.md,references/pipeline.md,templates/timeline.html}`; `~/Desktop/Labrynth/labrynth-motion-design/skills/labrynth-motion-design/brands/labrynth.md` (§5, §10)
- Orca (extraído, só dados): scratchpad `orca-motion/out/renderer/assets/I18nProvider-*.css`, `AgentStateDot-*.js`, `OnboardingInlineCommandTerminal-*.js`
