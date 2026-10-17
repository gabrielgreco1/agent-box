# 07 · Revisão da rodada 1 com foco em UI/UX e paridade com o Orca

Data: 2026-10-16. Somente leitura: nada foi alterado em `Sources/`.

**Escopo.** Revisei 03, 04 e 06 por inteiro e as partes de UI de 01 e 05. Também revisei:
- `Sources/AgentBox/**`;
- o checkout do SwiftTerm 1.20.0 em `.build/checkouts/SwiftTerm`, porque muitos comportamentos do terminal vêm dele e não do nosso código;
- o código-fonte do Orca, que tratei só como dado, sem executar;
- as chaves de aparência, terminal e notificação das configurações reais do Orca do dono (`~/Library/Application Support/orca/profiles/local-default/orca-data.json`). Não li nenhuma chave de segredo.

**Convenções.**
- Caminhos do Orca são relativos a `scratchpad/orca-src/src/`. `R/` é o mesmo que `renderer/src/`.
- Caminhos do Agent Box são relativos a `Sources/AgentBox/`. `ST/` é o mesmo que `.build/checkouts/SwiftTerm/Sources/SwiftTerm/`.
- **P0:** bloqueia o rebuild ou é risco de segurança/confiança. **P1:** necessário para a paridade "parece o Orca". **P2:** polimento.
- Só entram achados **novos**. Quando um achado complementa algo da rodada 1, isso vem indicado como "(complementa 03 #x)".

---

## A. Terminal (onde o dono passa 90% do tempo)

1. **P0: o terminal entrega o clipboard do Mac a qualquer programa que pedir (OSC 52 query).**
   - Evidência: `ST/Mac/MacLocalTerminalView.swift:121-126` implementa `clipboardRead` devolvendo `NSPasteboard.general`. `ST/Terminal.swift:2695-2701` responde a `OSC 52;c;?` com o conteúdo em base64 direto no PTY. O Agent Box usa `LocalProcessTerminalView` sem sobrescrever nada disso (`Terminal/TerminalRuntimeManager.swift:311-316`).
   - Por que importa: um `cat` de página raspada, um log ou o próprio agente pode ler o que o usuário copiou, inclusive senhas e tokens. O Orca **nunca** responde a essa consulta (`R/components/terminal-pane/osc52-clipboard.ts:16-22,176`; teste "never answers a clipboard query" em `osc52-clipboard.test.ts:125`). A escrita via OSC 52 é permitida por padrão, mas fica atrás de uma configuração e mostra um toast (`osc52-clipboard-toast.ts`).
   - Recomendação: subclasse que devolve `nil` em `clipboardRead`. Escrita OSC 52 permitida, mas com o toggle "Permitir que apps do terminal escrevam no clipboard" em Configurações › Terminal.

2. **P1: a busca no terminal (⌘F) já existe no SwiftTerm, só não está ligada.**
   - Evidência: SwiftTerm 1.20 tem `TerminalFindBarView` e `performFindPanelAction` (`ST/Mac/MacTerminalView.swift:2506-2566,2664`). Ele depende de um item de menu com `NSFindPanelAction`, e o app não declara `.commands {}` (`App/AgentBoxApp.swift:57-61`).
   - Orca: barra flutuante de 340 px no canto superior direito, com `Aa` (case), regex, ↑/↓, contador `i/N` e "No results", e Enter/⇧Enter/Esc (`R/components/TerminalSearch.tsx:39-58,126-153`).
   - Recomendação: no MVP, `CommandGroup(after: .textEditing)` com "Buscar…" ⌘F, ⌘G e ⇧⌘G mandando `performFindPanelAction` ao first responder. Na fase Orca, uma barra própria com contador (o `SearchService` do SwiftTerm já devolve as ocorrências).

3. **P1: não existe menu de contexto no terminal.** O SwiftTerm para Mac não implementa `rightMouseDown` nem `menu(for:)` (grep em `ST/Mac/MacTerminalView.swift`). O clique direito não faz nada.
   - Orca (`R/components/terminal-pane/TerminalContextMenu.tsx:195-354`), na ordem: Copiar, Selecionar tudo, Colar (com atalho) · Quick Commands · Fork/Copiar contexto da sessão do agente · Dividir à direita/abaixo · Igualar tamanhos, Expandir pane · Definir título…, Limpar título · Copiar ID da sessão/terminal/pane · Fechar pane · Limpar tela, Reiniciar terminal.
   - Recomendação: `NSMenu` nativo com esse conjunto, em português. Para o Agent Box, adicionar "Copiar ID da conversa" e "Abrir computador".

4. **P1: links no terminal.** O SwiftTerm abre o link direto com `NSWorkspace` (`ST/Mac/MacLocalTerminalView.swift:143-146`). Ele só detecta URLs (`linkReporting = .implicit`) e não tem dica de hover, popover, caminhos `arquivo:linha:coluna` nem ⌘-clique.
   - Orca:
     - clique simples abre um popover de ações; ⌘-clique abre direto (`R/components/terminal-pane/terminal-link-activation.ts:3-46`);
     - tooltip "Click for actions, ⌘+click to open" (`terminal-link-open-hints.ts:12-87`);
     - detecção de caminho com `:line:col`, `~/`, `./` (`R/lib/terminal-links.ts:33-58,281-302`);
     - ações "Abrir arquivo / Abrir com app padrão / Mostrar no Finder / Copiar link" (`terminal-file-link-actions.ts:90-160`, `LinkActionPopover.tsx:79-121`).
   - Recomendação: P1 só com ⌘-clique e hover sublinhado (`linkHighlightMode = .hover` já existe, `ST/Apple/AppleTerminalView.swift:1299`). Detectar caminhos relativos ao cwd (depende do OSC 7, já citado em 05) e levar o popover para o P2. Ver também o item 40: no modo isolado o caminho é do container.

5. **P1: arrastar arquivos para o terminal e colar imagem não funcionam.**
   - Evidência: grep por `registerForDraggedTypes`/`draggingEntered` no SwiftTerm não acha nada. O 01 §4.5 lista isso como sugestão, mas não diz que **é obrigatório para Claude Code/Codex**.
   - Orca:
     - caminhos são inseridos com escape de shell;
     - imagens vão em *bracketed paste*, para o CLI tratar como anexo (`R/components/terminal-pane/terminal-drop-path-writer.ts:46-80`, `terminal-drop-image-path.ts:5-12`);
     - imagem colada sem texto vira arquivo temporário e o caminho é colado (`terminal-clipboard-paste.ts:51-80`).
   - Recomendação: `NSView` hospedeira com `registerForDraggedTypes([.fileURL, .png, .tiff])` e um `paste:` sobrescrito que trata imagem. Mostrar destaque de drop no pane (overlay de 2 pt).

6. **P1: zoom de fonte do terminal (⌘= ⌘- ⌘0) e a fonte em si.** 03 só diz "fonte 12pt fixa". O que falta:
   - Orca: com o terminal focado, ⌘=/⌘- muda **só a fonte do pane ativo** (±1 entre 8 e 32, com overlay de porcentagem). Com o foco fora do terminal, muda o zoom da UI inteira (`R/components/terminal-pane/useTerminalFontZoom.ts:26-68`, `R/hooks/ipc-events/zoom-ipc-bridge.ts:23-54`). O UI zoom vai de −3 a +5 em passos de 0,5 (`shared/ui-zoom-level.ts:4-6`).
   - Agent Box: `monospacedSystemFont(ofSize: 12, weight: .regular)` (`TerminalRuntimeManager.swift:313`). O dono usa SF Mono **14, peso 500**, line-height 1 (config real).
   - Recomendação: padrão 14/medium, ⌘=/⌘-/⌘0 por pane e persistido por terminal. O zoom de UI pode ficar para o P2.

7. **P1: a paleta ANSI nunca é instalada, então o tema não é o do dono.** Só `nativeBackgroundColor` e `nativeForegroundColor` são definidos (`TerminalRuntimeManager.swift:314-315`). As 16 cores ANSI, a cor de seleção (padrão do SwiftTerm: ciano `#00A6B2`, `ST/Mac/MacTerminalView.swift:1030`) e o cursor (padrão: `selectedControlColor`, azul do sistema, `ST/Mac/MacCaretView.swift:115`) ficam nos defaults.
   - Recomendação: `installColors(_:)` com a paleta Ghostty Default Style Dark de 04 §1.2, mais `selectedTextBackgroundColor = #5a7898` e `caretColor = #ffffff`. Cursor em bloco piscando (`terminalCursorBlink = true` na config do dono).

8. **P1: Option como Meta está fixo em `true`.**
   - Evidência: `optionAsMetaKey` é `true` por padrão (`ST/Mac/MacTerminalView.swift:1545`) e o app não muda.
   - Efeito: em layouts que compõem caracteres com Option (US-Internacional e outros), Option deixa de digitar o caractere.
   - Orca: modo `auto` decide pelo layout de teclado. U.S./ABC vira Meta; outros layouts compõem (`R/components/settings/TerminalMacKeyboardSection.tsx:21-95`). O dono usa `terminalMacOptionAsAlt = auto`.
   - Recomendação: replicar o `auto` (`TISCopyCurrentKeyboardLayoutInputSource`) e oferecer as opções Esquerdo/Direito/Sempre/Nunca.

9. **P1: verificar Shift+Enter e os atalhos de edição do macOS no Claude Code.**
   - Orca: anuncia o protocolo de teclado kitty. Shift+Enter manda CSI-u; ⌘←/→ viram ^A/^E; ⌘⌫ vira ^U; ⌥←/→ movem por palavra (`R/components/terminal-pane/terminal-shortcut-policy.ts:179-295`).
   - SwiftTerm: tem suporte a kitty (`kittyModifiers`, `ST/Mac/MacTerminalView.swift:1580`), mas ninguém testou no Agent Box. Sem Shift+Enter, o usuário não consegue quebrar linha no prompt do Claude.
   - Recomendação: caso de aceite explícito, com teste manual em Claude Code e Codex.

10. **P1: um processo que saiu com erro aparece com ✓.**
    - Evidência: `statusIcon` mostra `checkmark.circle` para qualquer `.exited`, inclusive `exit 1` e SIGKILL (`Workspace/WorkspaceView.swift:638-639`).
    - Recomendação: código 0 → bolinha cinza ("Encerrado"); código ≠ 0 → bolinha vermelha ("Saiu com erro · n").
    - Orca: o overlay "Terminal exited… exit code {{code}}. Its output is preserved." com Close/Restart aparece **só** quando o código é ≠ 0 (`R/components/terminal-pane/TerminalProcessExitOverlay.tsx:17-54`, `pty-exit-hibernate.ts:306-316`). Isso complementa 03 #23, que pede o overlay mas não diz quando ele deve aparecer.

11. **P1: o BEL vira bipe do sistema em vez de virar estado.**
    - Evidência: o padrão do SwiftTerm é `NSSound.beep()` (`ST/Mac/MacTerminalView.swift:3594-3596`).
    - Orca:
      - não toca som;
      - o BEL marca a tab e o workspace como não lidos se a tab não estiver visível (`R/store/slices/workspace-attention/workspace-attention-slice.ts:81-96`);
      - pode virar notificação do sistema (`notifications.terminalBell`, que o dono deixa **ligado**).
    - Recomendação: `bellStyle = .none` mais um delegate próprio que marca "não lido" (bolinha âmbar, 04 §5.4). O SwiftTerm também entrega OSC 777 (notify) e OSC 9;4 (progresso), em `ST/Terminal.swift:219-225` e `ST/Mac/MacTerminalView.swift:3397`. Esses sinais servem de fonte barata de estado do agente, além dos hooks citados em 05.

12. **P1: atalho ⌘K em conflito.**
    - Agent Box: ⌘K foca "Buscar sessões" (`WorkspaceView.swift:798`).
    - Em Terminal.app, iTerm, Ghostty e **no Orca**, ⌘K é "Limpar tela" (`shared/keybindings/definitions-core-3.ts:258-263`). A palette do Orca é ⌘J.
    - Recomendação: ⌘K = Limpar, ⌘J = palette/busca. O 01 AA8 tem ⌘K como palette e precisa ser corrigido.

13. **P1: não existe política de "quem é dono do atalho" entre o app e a TUI.**
    - Orca: registro central de atalhos com escopo (`global`, `tabs`, `terminal`, `browser`…), `conflictGroup`, padrão por plataforma e **atalhos remapeáveis** (gravador, filtros "Modificados/Sem atalho/Conflitos", arquivo editável, aviso de conflito com Mission Control). Fontes: `shared/keybindings/definitions-core-*.ts`, `R/components/settings/ShortcutRecorderButton.tsx:155-182`, `ShortcutFilterRail.tsx:30-150`, `ShortcutsPane.tsx:93`.
    - Agent Box: atalhos espalhados em `.keyboardShortcut` de botões, alguns dentro de um `Menu` (03 #11).
    - Recomendação: no rebuild, criar `KeyBindingRegistry` (id, título pt-BR, escopo, padrão), alimentando `.commands`, os tooltips com keycap e a palette. Remapear pode ficar para o P2, mas a estrutura é P1.

14. **P1: ⌘W fecha a única janela do app.**
    - Evidência: a cena é `Window` única (`App/AgentBoxApp.swift:57-59`) e não há comando ⌘W para "fechar pane/tab". Então ⌘W cai em Arquivo › Fechar e fecha a janela principal.
    - O app continua vivo (`applicationShouldTerminateAfterLastWindowClosed → false`, `:18`). A reabertura pelo Dock procura `sender.windows.first(where: canBecomeMain)` (`:19-22`), que pode não existir depois que o SwiftUI libera uma cena `Window`. **Não verifiquei em runtime.**
    - Recomendação: ⌘W = fechar pane, depois tab (como no Orca, `definitions-core-4.ts:49`, `definitions-core-2.ts:132`), com confirmação se houver processo rodando. Fechar a janela só por ⌘⇧W. Reabrir pelo Dock com `openWindow(id:)`.

15. **P2: configurações de terminal que o Orca expõe e o rebuild precisa decidir.** Lista completa em `R/components/settings/terminal-*-search.ts`. O mínimo para o Agent Box:
    - fonte (família, tamanho, peso), line-height;
    - cursor (forma, piscar);
    - tema escuro e claro;
    - opacidade do pane inativo;
    - scrollback (5k padrão; mín. 1k, máx. 50k; `shared/terminal-scrollback-policy.ts:1-4`);
    - copiar ao selecionar (desligado);
    - "Trim gutter on copy" (ligado);
    - OSC 52;
    - Option como Alt;
    - "Perguntar antes de fechar terminal rodando";
    - padding horizontal/vertical.

16. **P2: `onTapGesture` cobrindo o terminal.**
    - Evidência: o pane inteiro, inclusive o `TerminalSurface`, tem `.onTapGesture { … runtime.focus }` (`WorkspaceView.swift:1010-1014`). Em `NSViewRepresentable`, um gesto SwiftUI no ancestral pode atrasar ou consumir cliques, prejudicando o duplo clique para selecionar palavra, o arrasto de seleção e o mouse reporting das TUIs. **Não verificado em runtime.**
    - Recomendação: focar via `mouseDown` da própria `NSView` hospedeira (ou `acceptsFirstMouse`), sem gesto SwiftUI por cima.

17. **P2: SwiftTerm já tem renderer Metal.** `setUseMetal(_:)` existe em `ST/Mac/MacTerminalView.swift:429`. Ver a correção 7: vale medir antes de pensar em trocar de engine.

---

## B. Janela, menus e aparência

18. **P1: não há barra de menus do app.** Sem `.commands`, só aparecem os menus padrão do SwiftUI. 03 cita isso de passagem, mas o efeito é maior:
    - os atalhos não ficam descobríveis;
    - a busca do terminal não funciona (item 2);
    - o VoiceOver e o "Ajuda › Buscar" do macOS não acham ações.
    - Orca (`main/menu/register-app-menu.ts:153-342`):
      - app: Sobre, Procurar atualizações, Ajustes, Ocultar, Sair;
      - Editar: padrão;
      - Visualizar: Recarregar, Tamanho real, Zoom +/−, Paleta, Tela cheia, submenu Aparência com toggles de barra lateral, painel direito e status bar;
      - Janela: Minimizar/Zoom;
      - Ajuda: Relatar crash, Docs.
    - Recomendação: menus em pt-BR com o mesmo conjunto, gerados pelo registro do item 13.

19. **P1: o tema escuro só vale para a janela SwiftUI.**
    - Evidência: `.preferredColorScheme(.dark)` está na raiz (`AgentBoxApp.swift:58,60`). `NSAlert` (sair, computadores; `:28,39`) e `NSOpenPanel` (`WorkspaceView.swift:1373,1585,1658`) seguem a aparência do sistema. Com o macOS em modo claro, aparecem alerts **claros** sobre o app escuro.
    - Recomendação: `NSApp.appearance = NSAppearance(named: .darkAqua)` enquanto não houver tema claro.
    - Decisão de produto: o Orca tem claro/escuro/sistema (padrão: sistema; `shared/default-global-settings.ts:44`) e tema de terminal separado para o claro (o dono tem `Builtin Tango Light` configurado). Recomendo **só escuro no v1**, com os tokens de 04 §1.1 já em pares claro/escuro, para não ter de refazer depois.

20. **P1: tela cheia.** 04 §7 manda reposicionar os semáforos, mas não diz o que fazer em tela cheia. Lá os semáforos somem e o pad de 80 px precisa sumir junto.
    - Orca: `window:fullscreen-changed` remove o padding (`main/window/main-window-state-lifecycle.ts:142-147`, `R/app-shell/TitlebarLeftControls.tsx:45`).
    - Recomendação: observar `NSWindow.didEnterFullScreenNotification` e `didExitFullScreenNotification`, zerar o pad e reaplicar a posição dos semáforos na saída. Testar também Stage Manager e Split View.

21. **P2: multi-janela e pop-outs.** O Agent Box tem uma única `Window`. O Orca também tem uma janela principal, mas abre:
    - o dashboard de agentes em pop-out (960×720, mín. 480×360; `main/window/dashboard-popout-window.ts:18-21`);
    - uma janela "space" (`workspace-space-window.ts:47-48`).
    - Para o Agent Box, o candidato natural é o **viewer do desktop do computador em janela própria**: hoje é sheet sobre sheet, com mínimo de 800×560 (`Docker/BrowserComputerPanel.swift:195`). Como janela, o usuário pode colocá-lo em outro monitor enquanto o terminal roda. Recomendo `WindowGroup(for: ComputerID.self)` no P1 do viewer.

22. **P2: as sheets maiores que o mínimo da janela não foram testadas.** A janela tem mínimo de 1000×650 (`WorkspaceView.swift:183`). A sheet do computador tem mínimo de 800×560, mais `idealHeight 760` (`BrowserComputerPanel.swift:195`), e ainda empilha sobre outra sheet. Some quando as sheets forem trocadas por overlay/janela (06 C9), mas é preciso definir o comportamento de overlays em janela pequena (rolagem ou limite de altura).

---

## C. Overlays, foco e acessibilidade

23. **P0 para o rebuild: os overlays dentro da janela (04 §7, 06 C9) precisam roubar o first responder do terminal.** Com `.sheet`, o AppKit muda a janela-chave. Com um `ZStack` overlay, o `LocalProcessTerminalView` **continua first responder**: o que o usuário digita no campo do diálogo pode ir para o agente. Nenhum relatório menciona isso. Recomendação, como contrato do `OverlayPanelHost`:
    - ao abrir, `window.makeFirstResponder(campo)`;
    - ao fechar, devolver o foco ao pane anterior;
    - prender o Tab dentro do overlay;
    - Esc fecha;
    - `.accessibilityAddTraits(.isModal)`;
    - o conteúdo de trás fica `accessibilityHidden(true)`.
    - Vale também para a palette (⌘J) e para o popover do "+".

24. **P1: navegação por teclado na sidebar.**
    - Agent Box: a sidebar é `ScrollView` + `LazyVStack` de `Button(.plain)` (`WorkspaceView.swift:361-392`). Não há seta para cima/baixo, Enter, item selecionado com `isSelected`, nem foco programático.
    - Orca:
      - `role="listbox"` com `aria-activedescendant`;
      - ↑/↓ movem, Enter foca o terminal (`R/components/sidebar/worktree-list/navigation/use-keyboard.ts:150-172`);
      - ⌘⇧↑/↓ trocam de worktree em qualquer lugar;
      - ⌘⇧0 foca a lista (`definitions-core-1.ts:47-60,261-267`).
    - Recomendação: `List(selection:)` não serve (visual de sistema, 04 §7). Usar `@FocusState` na lista mais `.onKeyPress(.upArrow/.downArrow/.return)` (macOS 14) e `.accessibilityAddTraits(.isSelected)` na linha ativa.

25. **P1: foco visível e rótulos.**
    - Agent Box: todos os controles usam `.buttonStyle(.plain)`, sem anel de foco próprio. As tabs e as linhas não anunciam seleção nem estado (`WorkspaceView.swift:706-730`). A taxa de rótulos de acessibilidade é baixa: cerca de 40 ocorrências no app inteiro (grep).
    - Orca: anel de 3 px `ring/50` em `focus-visible` nos botões e inputs (`R/components/ui/button.tsx:8`, `input.tsx:15`). Cerca de 1.092 `aria-label` e 75 `aria-live` no renderer.
    - Recomendação: `ButtonStyle` próprio com anel de 2 pt `ring` (`#737373`, com o mesmo alfa de 50% que o Orca usa) quando `isFocused`. Cada tab e linha precisa anunciar o rótulo ("Claude Code, trabalhando, branch main") e o traço `isSelected`.

26. **P1: anúncios do VoiceOver para estados de agente.** 06 §3.3 cita `AccessibilityNotification.Announcement`, mas não define **quais** eventos anunciar nem a frequência. Recomendação:
    - anunciar só "precisa de você", "terminou" e "falhou", com cooldown de 5 s por terminal;
    - nunca anunciar o fluxo de saída do terminal;
    - o Orca usa o mesmo cooldown de 5 s para notificações (`main/notifications/notification-delivery-service.ts:152-162`).

27. **P2: tooltips com atalho.**
    - Orca:
      - atraso de **400 ms** no app (`R/App.tsx:92`);
      - 500 ms na faixa de tabs, 1000 ms no ✕ da tab, 200 ms nas bolinhas de estado (`R/components/tab-bar/TabStripTooltipProvider.tsx:13`, `TabCloseTooltip.tsx:8`, `R/components/StateIndicatorTooltip.tsx:4`);
      - o atalho aparece como texto esmaecido dentro do tooltip (`R/components/sidebar/sidebar-header-actions.tsx:46-76`).
    - O `.help()` nativo não mostra keycap e o atraso do sistema é maior. Ver a correção 2 sobre 04 §7.
    - Recomendação: tooltip próprio leve (popover não ativável) para os ícones da titlebar, da tab bar e do header de pane, com nome + atalho. `.help()` só no resto.

---

## D. Sidebar e tabs: interações que 03 e 04 não detalham

28. **P1: a busca da sidebar é rasa.** Complementa 03 #4.
    - Quando a busca casa com uma sessão, aparecem **todos** os terminais dela, não só os que casaram (`WorkspaceView.swift:362-367,425-434`).
    - Não há destaque do trecho encontrado, Esc não limpa e não há botão ✕.
    - Recomendação: filtrar no nível do terminal, destacar o trecho (06 B4 já anima isso, mas a regra não estava definida), Esc limpa e devolve o foco ao terminal. Estado vazio: "Nenhuma sessão encontrada" + "Limpar busca" (Orca: "No workspaces found" + Clear Filters, `R/components/sidebar/worktree-list/listing/EmptyState.tsx:22-32`).

29. **P1: o estado de recolhido não persiste.** `collapsedSessions` e `collapsedTerminals` são `@State` (`WorkspaceView.swift:117-118`): ao reabrir o app, tudo volta expandido. Recomendação: persistir junto do layout.

30. **P1: os menus de contexto do Orca, para replicar.** 04 §3.4 lista o do worktree de forma resumida. Lista completa, com fontes:
    - **Worktree** (`R/components/sidebar/WorktreeContextMenuView.tsx:157-383`): Atualizar · Abrir em ▸ (apps, "Personalizar…") · Copiar caminho · Copiar nome · Fixar/Desafixar · Marcar como lido/não lido · Grupos · Dormir · Excluir worktree (desabilitado no checkout primário, com tooltip explicando).
    - Itens de desenvolvedor só com ⌥ pressionado (`worktree-context-menu-policy.ts:44-51`). É um bom padrão para esconder ações técnicas como "Reautorizar pasta…" e "Atualizar Git".
    - **Tab de terminal** (`R/components/tab-bar/SortableTabContextMenu.tsx:30-86,176-271`; `TabWorkspaceLayoutMenuSection.tsx:33-68`): Dividir ▸ · Fixar · Copiar ID · Fechar (desabilitado se fixada) · Fechar outras · Fechar à direita/esquerda · Mudar título · Cor da tab ▸ (10 cores) · Mover para split ▸ direita/esquerda/baixo/cima.
    - Recomendação para o Agent Box: na sessão, Renomear · Novo terminal/agente ▸ · Abrir pasta no Finder/editor · Copiar caminho · Fixar · Marcar como lida · Arquivar/Excluir (com confirmação). No terminal, ver o item 3, mais "Abrir computador" e "Retomar conversa".

31. **P1: renomear inline, regras exatas.** 03 #21 só diz "sem rename inline". Orca:
    - gatilhos: duplo clique, "Mudar título" ou ⌘R (tab) e ⌘⌥R (worktree);
    - Enter confirma, Esc cancela, **blur confirma**; Enter durante composição de IME é ignorado;
    - o título é congelado ao abrir a edição, para que um OSC não sobrescreva o que está sendo digitado;
    - vazio **volta ao título automático**; em caso de erro, o campo fica aberto e aparece o toast "Failed to rename";
    - fontes: `R/components/tab-bar/use-sortable-tab-rename.ts:27-43`, `SortableTab.tsx:270-281`, `R/components/sidebar/WorktreeTitleInlineRename.tsx:14-22,206-299`.
    - Recomendação: copiar as regras. A sheet de renomear sai.

32. **P1: arrastar tabs (spec que faltava em 04 §2.3).** 03 diz só "sem drag".
    - Ativação a 12 px; Esc cancela (`R/components/tab-group/useTabDragSplit.ts:41-43,244-250`).
    - Soltar no centro (80%) do pane junta a tab ao grupo. Fora disso, o terço esquerdo/direito faz split lateral e o terço do meio faz split vertical (`tab-drop-zone.ts:8-80`).
    - Overlay "New split" de meio pane (`TabGroupDropOverlay.tsx:5-38`).
    - Panes têm alça "···" de 12 px no hover; o pane de origem fica com 40% de opacidade durante o arrasto (`assets/terminal.css:120-162`).
    - Arrastar entre worktrees ou janelas é proibido (`tab-drag-drop-commit.ts:20`).
    - Recomendação: P1 para reordenar; P2 para o split por arrasto.

33. **P1: reabrir tab fechada e fechar pane sem perder o processo.**
    - Orca: ⌘⇧T reabre até 10 tabs de terminal por worktree (`R/store/slices/recently-closed-tabs.ts:37-51`). "Perguntar antes de fechar terminal rodando" vem ligado.
    - Ligação com 03 #7 e 03 #16: hoje "fechar pane" deixa o processo órfão e invisível.
    - Recomendação: a semântica deve ser "fechar tab = encerrar processo, com confirmação" e "⌘⇧T reabre (relançando com `--resume` quando houver ID nativo)".

34. **P1: largura das tabs.**
    - Agent Box: as tabs não têm largura máxima (`WorkspaceView.swift:713-724`, só `lineLimit(1)`). Um título longo empurra as outras e não há tooltip com o título completo. A fonte é de 13 pt; no Orca é 12.
    - Orca: largura fixa de 180/220 com mínimo de 72, para que **uma mudança de título não redimensione todas as tabs** (`R/components/tab-bar/tab-width-rules.ts:1-3`).
    - Recomendação: seguir a regra do Orca e mostrar o hover card da tab com o título, o cwd e o estado.

35. **P2: tabs fixadas, cor de tab e clique do meio.** O Orca tem pin (tab fixada não fecha pelo menu), 10 cores e clique do meio para fechar (`SortableTabContextMenu.tsx:219`, `EditorFileTab.tsx:259-262`). Baixa prioridade, mas barata quando as tabs forem reescritas.

36. **P2: atrasos dos hover cards do Orca** (06 B7 propõe 350 ms sem base):
    - card do worktree abre em 250 ms e fecha em 120 ms (`R/components/sidebar/WorktreeCardMeta.tsx:74-75`);
    - card da tab abre instantâneo quando outro já está aberto (`TabHoverCard.tsx:87`).
    - Recomendação: usar esses valores.

37. **P2: a sessão terminal "selecionada" some ao trocar de sessão.** O destaque da linha de terminal exige `selectedSessionID == sessionID` (`WorkspaceView.swift:481`). Nas sessões não ativas, nada indica qual terminal estava focado. O Orca mostra o pane focado com `worktree-sidebar-accent` dentro de cada card. Recomendação: indicar o "último focado" com um tom mais fraco.

---

## E. Notificações e atenção

38. **P1: um clique na notificação não leva a lugar nenhum, e a notificação não aparece com o app em primeiro plano.**
    - Evidência: o `HumanRequestCenter` grava `session_id`, `terminal_id` e `computer_id` no `userInfo` (`Computers/HumanRequestCenter.swift:79-82`), mas **não há `UNUserNotificationCenterDelegate`** (grep vazio). Sem `willPresent`, o macOS descarta o banner com o app ativo. Sem `didReceive`, o clique só ativa o app.
    - Também não há badge no Dock nem `requestUserAttention` (grep vazio).
    - Recomendação:
      - um delegate que navega até a sessão, o pane e o computador, com o rim flash de 06 C6;
      - um `willPresent` que segue a regra do Orca (suprimir só se a janela estiver focada **e** a sessão estiver ativa, `notification-delivery-service.ts:144-149`);
      - `NSApp.dockTile.badgeLabel` com a contagem de "precisa de você".

39. **P1: a permissão negada é silenciosa.**
    - Agent Box: o toggle chama `requestAuthorization`. Se o usuário negar, o toggle simplesmente volta a "desligado", sem explicação (`App/AppSettingsView.swift:17`, `HumanRequestCenter.swift:52-61`). O estado real do sistema nunca é relido.
    - Orca: cartão "Allow notifications for Orca" com botão "Abrir Ajustes do Sistema" (`R/components/notifications/mac-notification-permission-card.tsx:161-220`) e botão "Enviar notificação de teste" (`R/components/settings/NotificationsPane.tsx:246`).
    - Notificações por evento no Orca: tarefa concluída, BEL do terminal, workspaces escondidos, som com volume, "suprimir com foco" (`NotificationsPane.tsx:115-246`). O dono usa `enabled`, `agentTaskComplete`, `terminalBell` e `suppressWhenFocused` ligados, com som "system".
    - Recomendação: seção Notificações com esses toggles, o cartão de permissão e o teste. É o par de UI do estado "esperando você" de 05.

---

## F. Desktop remoto (controle do computador)

40. **P1: ao assumir o desktop, o teclado fica preso sem saída visível.**
    - Evidência: com o viewer focado, `performKeyEquivalent` captura **todo** ⌘-atalho e manda como `ctrl+…` para a box (`Computers/RemoteDesktopView.swift:442-447,413-417`). ⌘W, ⌘Q, ⌘Tab-like e ⌘, não chegam ao Mac. Não há indicador de "teclado capturado" nem tecla de escape.
    - Recomendação: um selo "Teclado na box · ⌃⌥ para soltar" (padrão de VNC e Parallels). Uma combinação reservada que nunca vai para a box (⌘⎋ por exemplo). ⌘Q sempre chega ao app. 06 E4 desenha o handoff, mas não esse estado.

41. **P2: não há clipboard entre o Mac e a box.** O viewer não tem copiar/colar compartilhado (grep por `Pasteboard` em `RemoteDesktopView.swift` vazio). Num captcha ou num formulário, o humano não consegue colar um código. Recomendação: "Colar no desktop" (digita o clipboard via xdotool) e "Copiar seleção da box", com aviso de que o conteúdo sai do Mac.

---

## G. Modos de Docker: impacto na UI (decisão do dono, ausente da rodada 1)

A rodada 1 só trata a decisão como "pendente" (02 §4.3, 02:350). Com a decisão tomada (subagente **isolado**, com o CLI no container e o terminal como tab, ou **leve**, com o CLI no Mac e só o computador no container), estes pontos de UI precisam entrar na spec:

42. **P0: o modo precisa aparecer na criação e ficar visível depois.**
    - No lançador (composer, 04 §5.2): campo "Onde roda" com "No Mac (leve)" e "Isolado em container". O padrão por agente salvo pode ficar em Advanced, mas o modo efetivo aparece no resumo antes de criar.
    - Na tab e na linha da sidebar, um selo de container (ícone de caixa de 10 px ao lado do logo do agente) para terminais isolados.
    - No modo leve, o selo fica no **computador** (ícone de tela), não no terminal. Sem isso, o usuário não sabe se `rm -rf` roda no Mac ou na box.

43. **P0: a tab isolada tem fases antes do PTY existir** (imagem → container → CLI → pronto). O estado `idle` de 03 #17 e a "ignição" de 06 E2 assumem um processo local. Recomendação: o placeholder de 06 E2 mostra as etapas **reais** do container (pull da imagem com progresso, criação, montagem do workspace, login do CLI) e "Cancelar". Se o container cair, o pane mostra "Container parou · Reiniciar container", que é diferente de "processo saiu".

44. **P1: caminhos, links e drag-and-drop mudam de significado no modo isolado.**
    - `src/foo.ts:12` impresso pelo agente é um caminho **do container**. O ⌘-clique (item 4) precisa mapear o volume montado de volta para o Mac, ou oferecer só "Copiar".
    - Arrastar um arquivo do Finder (item 5) precisa **copiar para o volume** e colar o caminho interno, com confirmação ("Copiar 'x.png' para a box?").
    - A pasta do Git na sidebar (`terminal.cwd`) é o caminho do host do bind mount, e a UI precisa deixar isso explícito.

45. **P1: o terminal isolado e o computador são a mesma box.**
    - No modo isolado, "Abrir computador" na tab abre o desktop **do mesmo container**. Parar o container encerra os dois, e a confirmação precisa dizer isso ("Encerrar o agente e o computador desta box?").
    - No modo leve, parar o computador não mata o CLI.
    - Recomendação: um popover "Box" no header da tab com CPU, memória, modo HTTP/headless/desktop e Parar, igual nos dois modos e mudando só o texto das consequências.

46. **P2: indicador de recursos.** Com várias boxes isoladas, falta uma visão global. O Orca tem o segmento "Resource usage" e o Resource Manager na status bar (`R/components/status-bar/StatusBarSurface.tsx:171-306`). Recomendação: status bar com "3 boxes · 4,1 GB" e um popover para parar cada uma (combina com 01 §4.8).

---

## H. Configurações, onboarding e telas do Orca não inventariadas em 04

47. **P1: arquitetura de Configurações.** 04 §5.7 lista os grupos do Orca, mas não diz o que o Agent Box precisa ter. Seções mínimas:
    - Geral;
    - Agentes: agente padrão; por agente, comando, argumentos e env; "Permissões: YOLO/Manual". O Orca: `R/components/settings/AgentsPane.tsx:70-120`, `AgentLaunchDefaultsEditor.tsx:37-219`. O dono usa `--dangerously-skip-permissions` no Claude e `--dangerously-bypass-approvals-and-sandbox` no Codex, então o padrão do Agent Box precisa permitir isso em 1 clique;
    - Aparência;
    - Terminal (item 15);
    - Notificações (item 39);
    - Atalhos (item 13);
    - Computadores;
    - Credenciais.
    - Recursos: hoje é uma aba praticamente vazia (03 #40). As seções técnicas de Computadores e Credenciais (concessões, restrições) vão para "Avançado".
    - **Busca nas configurações** (Orca: `R/components/settings/settings-search.ts:99-120`, "No settings found for…", destaque de 3 s no alvo de deep link) e **deep link** a partir de mensagens de erro (ex.: "Criação desativada" abre direto o campo certo; corrige o texto de 03 #9).
    - A aba escolhida (`@State category`, `AppSettingsView.swift:6`) também não é lembrada entre aberturas.

48. **P1: onboarding.** 04 §5.8 lista os passos. O que faltou:
    - o Orca roda um **terminal inline dentro do onboarding** para instalar ou logar CLIs (`R/components/onboarding/FeatureSetupInlineTerminal.tsx`, `OnboardingInlineCommandTerminal.tsx`);
    - pular pede confirmação ("Skip onboarding?", `OnboardingSkipConfirmationDialog.tsx:16-29`);
    - o tema escolhido no preview é revertido se o usuário pular (`onboarding-flow-state.ts:146`).
    - Para o Agent Box: passo "Agente padrão" (detectado, com "Instalar" e "Entrar" rodando no terminal inline), passo "Computadores" (detectar Docker/Colima com "Iniciar Colima" e "Baixar imagem" no terminal inline, ou "Pular, uso só terminais") e passo "Notificações". Isso substitui a sheet com o formulário técnico inteiro (03 #2).

49. **P1: o painel "Agents · retomar sessões" do Orca é o modelo do "Retomar conversa".** 03 #23 mostra que a sheet atual é inutilizável, e 04 não descreve a alternativa.
    - Orca (`R/components/right-sidebar/AiVaultPanelHeader.tsx:84-184`, `AiVaultPanelControls.tsx:92-357`, `AiVaultSessionActionMenuItems.tsx:77-187`):
      - lista do histórico indexado com busca, escopo Workspace/Projeto e agrupamento;
      - cada linha com agente, mensagens e subagentes;
      - menu: Retomar em nova tab, Copiar comando de retomada, Passar para outro agente, Abrir log, Copiar ID.
    - Depois de reiniciar o app, o modal "Resume interrupted chats?" com checkboxes agrupados (`R/components/NativeChatResumeOnRestartModal.tsx:269-419`). É exatamente o que 05 (c) pede para o pós-quit.
    - Recomendação: aba "Conversas" no painel direito e o modal "Retomar agentes interrompidos" na abertura.

50. **P2: outras telas do Orca fora de 04.** Útil para o dono decidir o escopo:

    | Tela | Fonte no Orca | Adotar? |
    |---|---|---|
    | Quick Commands (split button "▷ Command") | `docs/site/content/docs/terminal.mdx` §Quick Commands | sim, P2: prompts e comandos salvos por projeto; casa com a Biblioteca |
    | Terminal flutuante ⌘⌥A | `R/components/floating-terminal/*` | P2 |
    | Dashboard de agentes kanban (Precisa de você / Trabalhando / Concluído / Ocioso) | `R/components/dashboard-popout/AgentKanbanBoard.tsx:42-48` | P2: equivale à fila "needs action" do design antigo |
    | Activity (feed com não lidos, agrupar, "Marcar tudo como lido") | `R/components/activity/*` | o sino de 04 §3.2 abre isso; P1 em versão simples |
    | Automations (agendamento cron) e Tasks (GitHub/Linear) | `R/components/automations/*`, `R/components/task-page/*` | fora do escopo v1 |
    | Status bar (uso por provedor, Caffeinate, portas) | `R/components/status-bar/StatusBarSurface.tsx:171-306` | P2; "Manter o Mac acordado enquanto agentes rodam" é barato e útil |
    | Error boundary por superfície ("Esta parte do app encontrou um erro · Tentar de novo") | `R/components/error-boundaries/RecoverableRenderErrorBoundary.tsx:68-110` | P1 em espírito: um erro numa área não pode travar a janela inteira, como faz `.disabled(loadError != nil)` em `WorkspaceView.swift:182` |
    | Relatar crash com logs redigidos | `R/components/crash-report/CrashReportDialogSurface.tsx` | P2, junto de 01 §4.11 |

51. **P1: padrão de confirmação e desfazer.**
    - Orca:
      - diálogo de confirmação com "Não perguntar de novo" e um toast "Você pode mudar isso em Ajustes" com ação (`R/components/confirmation-dialog.tsx:144`, `confirmation-skip-preference.ts:7-40`);
      - toasts com ação Desfazer ou Voltar (ex.: "Sort changed to Manual · Back to Recent", 8 s, `R/components/sidebar/manual-sort-switch-toast.ts:3-45`);
      - toast de erro dura 60 s (`R/store/repos/repo-state.ts:31`).
    - 06 C8 define o movimento do toast, mas não a política. Recomendação:
      - excluir sessão: confirmação com "Não perguntar de novo";
      - fechar tab: ⌘⇧T desfaz;
      - erro não bloqueante: toast de 60 s com "Copiar detalhes".
      - Isso substitui o alert genérico "Erro no workspace" (03 #14).

---

## I. Microcopy e idioma

52. **P1: não há infraestrutura de localização, e o Orca não tem português.**
    - Agent Box: todas as strings estão no código (`Text("…")`). Não há String Catalog (`find -name '*.xcstrings'` vazio) e não há `Info.plist` do app com `CFBundleDevelopmentRegion` (só existe `design/source/Info.plist`).
    - Orca: suporta en, es, fr, ja, ko e zh (`R/i18n/supported-languages.ts:22-40`). **Não tem pt-BR.** Então "copiar o Orca" significa traduzir cada rótulo, e o rebuild precisa de um glossário.
    - Recomendação: String Catalog com `pt-BR` como idioma de desenvolvimento. Datas e tempos relativos ("agora", "12 min", "3 h", "5 d") via `RelativeDateTimeFormatter`, porque o Orca usa "now", "12m", "3h", "5d".

53. **P1: glossário e termos inconsistentes.**
    - Evidência (grep em `Sources`):
      - "box" aparece nos dois gêneros: "a box" ×11, "o box"/"do box" ×3. Exemplo: `"O box e seus dados são preservados"` ao lado de `"desta box"`.
      - "box" e "computador" são usados para a mesma coisa: "Criar computador" × "Box: …" × "manter box …".
      - Anglicismos e jargão visíveis: pane, Daemon, Listener, runtime, adapter, broker, snapshot, hook, Remote, dataset, "Run observado", "Helper MCP", "SHA-256 do script".
    - Proposta de glossário:

      | Termo atual | Usar |
      |---|---|
      | pane | painel (ou "divisão"; "Fechar painel") |
      | box / computador | **computador** na UI ("o computador desta sessão"); "box" só em logs |
      | Remote | Remoto |
      | worktree | worktree (manter; termo do Git), com a dica "cópia de trabalho" no primeiro uso |
      | Listener | Captura de rede |
      | dataset | Conjunto de dados |
      | hook / adapter / broker / snapshot / SHA-256 | só em "Detalhes técnicos" recolhidos |

    - Também:
      - padronizar reticências (`…`) só para ações que abrem algo;
      - verbo no infinitivo nos botões ("Criar", "Iniciar");
      - mensagens de estado sem jargão: "Último evento: iniciado" vira "Iniciado há 2 min"; "PID 42634" vira "Rodando".

54. **P2: há textos de aviso demais.** As telas de Computadores e Capturas têm parágrafos de 2 a 4 linhas em `.caption` (ex.: `"Permissão de criação: vale na próxima solicitação. CPU, memória e rede: novas boxes. Teto: …"`). O Orca usa uma linha de descrição de 12–13 px e manda o detalhe para tooltip ou docs. Recomendação: cada controle com no máximo uma linha de ajuda; o resto em "Saiba mais".

---

## J. Persistência e desempenho percebido

55. **P1: arrastar um divisor regrava `workspace.json` a cada quadro.**
    - Evidência: o arrasto da sidebar e dos splits altera `snapshot` em `onChanged` (`WorkspaceView.swift:651-656,952-962`). `onChange(of: snapshot)` chama `repository.save` de forma síncrona na main thread (`:193-197`). Um clique de foco também salva.
    - 05 critica o JSON único, mas não esse efeito: engasgo durante o arrasto e escrita em disco contínua.
    - Recomendação: o estado de layout transitório fica em memória; salvar com debounce (300 ms) e no `onEnded`.

---

## Correções aos relatórios da rodada 1

1. **05 (c), "Como outros resolvem": "Splits ilimitados (`⌘\`, `⌘⇧\`)" está errado.** O registro de atalhos do Orca define o split à direita como **⌘D** e o split abaixo como **⌘⇧D** no macOS (`shared/keybindings/definitions-core-4.ts:57-75`). O `⌘\` vem da doc `docs/site/content/docs/terminal.mdx` §Shortcuts, que está desatualizada em relação ao código. 04 §6 está certo.

2. **04 §1.5 e §4: "Tooltip … delay padrão Radix ~700 ms" está errado.** O app define 400 ms (`R/App.tsx:92`). O primitivo vem com 0 ms (`R/components/ui/tooltip.tsx:8`). As tabs usam 500 ms, o ✕ da tab 1000 ms e as bolinhas de estado 200 ms. Em §7, "`.help()` nativo é suficiente" também não se sustenta para a titlebar e as tabs: o atraso do sistema é maior e não mostra o atalho (item 27).

3. **04 §0 diz "É exatamente isso que ele vê", mas a lista está incompleta e um valor está errado.** Na config real:
   - `terminalInactivePaneOpacity = 0.8`, não o 0,9 de §1.2 (0,9 é só o padrão do Orca, `shared/constants.ts:42`);
   - `terminalCursorBlink = true`, `terminalFontWeight = 500` / bold 700, `terminalScrollbackRows = 5000`;
   - `terminalThemeLight = "Builtin Tango Light"` com `terminalUseSeparateLightTheme = true`;
   - `terminalMacOptionAsAlt = auto`, `terminalClipboardOnSelect = false`, `terminalAllowOsc52Clipboard = true`, `terminalLinkClickBehavior = actions`;
   - `notifications = {enabled, agentTaskComplete, terminalBell, suppressWhenFocused: true, som "system"}`;
   - `rightSidebarOpenByDefault = true`;
   - `agentDefaultArgs`: Claude com `--dangerously-skip-permissions`, Codex com `--dangerously-bypass-approvals-and-sandbox`;
   - `defaultTuiAgent = hermes` (não é Claude);
   - `leftSidebarTintColor = #18181b` a 0,08 (com `leftSidebarAppearanceMode = default`; não verifiquei se o tint é aplicado nesse modo).
   - Esses valores mudam padrões do rebuild (itens 7, 8, 11, 39, 47).

4. **04 §2.4: "Ports" não é aba do painel direito para worktrees locais.** Ela só aparece em worktrees SSH (`R/components/right-sidebar/right-sidebar-panel-content.tsx:29`). Para worktrees locais, as portas ficam na status bar. A aba "Agents" (histórico/retomar) existe e deveria estar em destaque (item 49).

5. **06 §2 e C9 têm números inconsistentes com 04 e com o código do Orca.**
   - Scrim: 06 C9 propõe 0,45; o Orca usa `black/55` (04 §1.4).
   - Escala de entrada do dialog: 06 usa 0,96; o Orca usa 0,95 (`zoom-in-95`, `R/components/ui/dialog.tsx:115`).
   - A tabela de 06 §2 junta "Diálogos/menus … zoom-in-95 … 150 ms". No código, o dialog usa **200 ms** com zoom 95% e os menus usam **150 ms** com zoom **98%** (`R/components/ui/dropdown-menu.tsx:36`, `context-menu.tsx:62`). 04 §1.5 está certo.
   - Unificar os tokens antes do `Motion.swift`.

6. **06 A1 contradiz 03 e 05.** A1 diz "terminais restaurados aparecem já no estado 'Pronto para iniciar', sem animação". 03 #2 classifica esse estado como bug, e a proposta de 05 (c) é reanexar o processo vivo com buffer. A1 deve descrever a reanexação (buffer aparece já preenchido) e o caso "processo morreu" (último buffer esmaecido + "Retomar conversa").

7. **05 (c), "Lacunas" 8: "SwiftTerm … sem GPU" está desatualizado.** O SwiftTerm 1.20.0 travado no `Package.resolved` tem renderer Metal opcional (`setUseMetal(_:)`, `ST/Mac/MacTerminalView.swift:429`, com throttle de live-resize em `:45-46`). Medir com ele ligado antes de cogitar libghostty.

8. **01 AA1/AA11 e 04 §3 discordam, e nenhum dos dois decide.**
   - Sidebar: a spec antiga pede 288 pt (224–480); o Orca e a config do dono usam 280 (220–500).
   - Janela mínima: a spec pede 1000×650; o Orca usa 600×400 (`main/window/main-window-visual-lifecycle.ts:114-115`).
   - Recomendação: adotar 280 (220–500). Para a janela mínima, derivar do layout (sidebar 220 + centro 320 + painel direito 220 = **760** de largura), com o painel direito recolhendo sozinho abaixo disso, em vez de manter 1000×650.

9. **01 AA8 usa ⌘K como command palette.** Isso conflita com o padrão de terminais e do Orca (⌘K = limpar, ⌘J = palette). Ver item 12.

10. **03 §1 e #11 tratam a falta de `.commands {}` como problema de atalho.** É também a razão de a busca no terminal não funcionar, e de Copiar/Colar dependerem dos menus padrão do SwiftUI (item 2).

11. **03 #17: "O texto do terminal encosta na borda esquerda, sem padding" está certo, mas falta a causa.** A view do SwiftTerm é ancorada nas quatro bordas do host sem inset (`Terminal/TerminalRuntimeManager.swift:296-301`). A correção é um inset de 4 pt nessas constraints, não padding SwiftUI (que mudaria o hit-testing). O Orca expõe padding H/V como configuração.

12. **Valores de 04 que conferi e estão certos**, para dar confiança à implementação:
    - semáforos `x 16`, centro `y 18` (raio 6, `main-window-visual-lifecycle.ts:111-113`);
    - dialog 512 / confirmação 448 (`sm:max-w-lg` / `sm:max-w-md`);
    - menus com raio 11 e mínimo de 176 px;
    - tab 180/220, mínimo 72 (`tab-width-rules.ts:3`);
    - ⌘J palette, ⌘⌥←/→ histórico, Ctrl+Tab recente, ⌘⇧]/[ próxima/anterior;
    - Ctrl+1…9 seleciona a tab e ⌘1…9 seleciona o workspace (`definitions-core-2.ts:232-236`). 04 §5.5 não cita o Ctrl+1…9 das tabs.

13. **Afirmações da rodada 1 marcadas como não verificadas que continuam assim:**
    - 06 S1 (resize do PTY a cada quadro durante o recolhimento): continua dependendo de Instruments;
    - 03 #10 ("o atalho abre provavelmente a janela, não a sheet");
    - o comportamento do Esc em sheets sem `.cancelAction` (03 #1): precisa de teste em runtime, porque o macOS 14 encaminha `cancelOperation:`.
    - Sugiro uma rodada de QA com acessibilidade habilitada (o bloqueio de 03 §0 era `AXIsProcessTrusted() == false`) para fechar esses três pontos.
