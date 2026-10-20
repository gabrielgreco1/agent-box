# 03 — Inventário de telas, sheets e fluxos (estado atual)

Escopo: `Sources/Racky/**` (App, Workspace, Library, Settings, Docker, Computers, Capture, Terminal). Base: commit `c4418cc` (branch `gabrielgreco1/test-project-suite`). Os números de linha se referem a esse commit.

## Como foi feito / limitações

- Li o código inteiro: `WorkspaceView.swift` (1682 linhas), `LibraryView`, `AgentLaunchView`, `AppSettingsView`, `SecretSettingsView`, `DockerViews`, `BrowserComputerPanel`, `HumanRequestsView`, `ConversationResumeView`, `CapturePanel`, e os trechos de UI de `TerminalRuntimeManager`, `RemoteDesktopView` e `RackyApp`.
- **Build:** `scripts/build_app.sh` recusou rodar porque já havia uma instância deste worktree aberta (pid 41259, build de 18:53 em `~/Library/Caches/Racky/Builds/d2d2f28c18e2bf66`). Não matei esse processo, porque pode ser do usuário ou de outro agente. Usei a instância que já estava aberta, trazida para frente com `open "build/Racky.app"`.
- **Screenshots:** `screencapture -l <windowid>` funciona (id obtido via `CGWindowListCopyWindowInfo`). **Não deu para clicar:** `osascript`/System Events retorna `-1743 Not authorized`, e `AXIsProcessTrusted() == false`. Por isso só capturei a tela principal. Sheets, popovers e menus foram descritos **pela leitura do código**.
  - `screens/01-main-window.png`: janela principal com a sessão "teste-arizona" e um terminal Shell rodando.
  - `screens/01b-main-window-with-shadow.png`: a mesma captura, com sombra.

---

## 1. Mapa de navegação

```
App launch
├─ [1ª execução] Sheet "Configuração inicial" (AppRootView) ── embute AppSettingsView inteira ── "Concluir"
└─ Janela "Racky" (Window id "workspace", COM barra de título nativa)
   ├─ SIDEBAR
   │  ├─ Header: logo + "Racky" + [+] ──► Sheet Nova sessão
   │  ├─ Campo "Buscar sessões" (⌘K via menu …)
   │  ├─ Árvore: Sessão ▸ Terminais ▸ Subagentes nativos
   │  │   ├─ clique sessão → seleciona (sem destaque visual)
   │  │   ├─ menu contextual sessão: Renomear ► Sheet Rename · Novo terminal ► Sheet Novo terminal
   │  │   ├─ clique terminal → selectTerminal (troca o conteúdo do pane focado)
   │  │   ├─ menu contextual terminal: Renomear · Mostrar em pane · Dividir à direita/abaixo ·
   │  │   │   Atualizar Git · Reautorizar pasta… (NSOpenPanel) · Criar worktree… ► Sheet Worktree ·
   │  │   │   Encerrar processo · Forçar encerramento… ► confirmationDialog
   │  │   ├─ subagente → Sheet "Subagente nativo" ► "Computador do subagente…" ► Sheet BrowserComputerPanel(nativeChild)
   │  │   └─ "+ Novo terminal" (linha) ► Sheet Novo terminal
   │  └─ Rodapé: "Biblioteca" ► Sheet Biblioteca · 🔔 ► Sheet Pedidos · ⚙ ► Sheet Configurações (⌘, em conflito)
   └─ ÁREA PRINCIPAL
      ├─ Toolbar (40pt): [sidebar ⌘B] título da sessão … status/PID · [Git ▸ popover] · [▶/■/⛔] ·
      │   [🖥 ► Sheet Computador] · [split → ⌘D] · [split ↓ ⌘⇧D] · [+ ⌘T ► Sheet Novo terminal] · [… menu]
      │   Menu …: Nova sessão(⌘N) · Retomar conversa… ► Sheet Retomar · Fechar pane focado ·
      │           Biblioteca · Pedidos · Configurações · Buscar sessões(⌘K) · Estreitar/Alargar/Restaurar sidebar
      ├─ "Tabs" (35pt): uma tab por TERMINAL da sessão selecionada (não por sessão)
      └─ Conteúdo: emptyWorkspace | emptySession | emptyPane | árvore de panes (até 5) com TerminalSurface

Sheet Biblioteca ─► "Usar…" ─(fecha, onDismiss)─► Sheet "Usar agente salvo" (AgentLaunchView)
                └─► Histórico "Abrir terminal" ─(fecha)─► seleciona terminal
                └─► sub-sheets: Editor de agente, Editor de memória, Contexto, Skill, Revisão agente/memória
Sheet Computador (ComputerPanel) ─► BrowserComputerPanel
                                     ├─ "Capturas e dados" ► Sheet CapturePanel (Requisições/Dados/Captura)
                                     ├─ "Abrir desktop" ► Sheet RemoteDesktopView (Assumir/Devolver/Reconectar)
                                     └─ "Revisar e iniciar agente" ─(fecha)─► Sheet AgentLaunchView(scraping)
Sheet Pedidos ─► "Abrir terminal" ─(fecha)─► seleciona terminal
Settings scene (⌘, / menu do app) ─► janela separada com AppSettingsView (2ª superfície de Settings)
```

Toda navegação secundária é feita por **`.sheet` modal empilhado** (`WorkspaceSheet`, `WorkspaceView.swift:65-99`). Não há navegação inline, painel lateral direito, inspector nem command palette. Encadear sheets (Biblioteca → Lançar, Computador → Lançar) depende de `handleSheetDismissal` (`:1129-1143`): a primeira sheet fecha e a segunda abre logo depois, o que dá um "pisca" entre as duas.

---

## 2. Tabela por tela

| # | Tela / superfície | Como chega | O que mostra / controles (o que fazem de fato) | Estados | Problemas |
|---|---|---|---|---|---|
| 1 | **Janela principal** (`RackyApp.swift:57-59`, `WorkspaceView.body :168-331`) | Abrir o app | HStack com sidebar, divisor de 6pt e workspace. Tamanho mínimo 1000×650, padrão 1360×860. | Se o `workspace.json` não carrega, mostra um alert e **desabilita a UI inteira** (`.disabled(loadError != nil)` :182) | Barra de título nativa com o texto "Racky" ocupa cerca de 28pt acima de tudo (screenshot 01). Não usa `.windowStyle(.hiddenTitleBar)` nem `fullSizeContentView`. O nome "Racky" aparece duas vezes, no título e no header da sidebar. |
| 2 | **Sheet Configuração inicial** (`RackyApp.swift:64-79`) | 1ª execução (`@AppStorage initialSetupCompleted`) | Título, texto, AppSettingsView inteira (4 abas), "Concluir" | `interactiveDismissDisabled` | Joga ao usuário o formulário técnico inteiro de Docker, credenciais e concessões no primeiro uso. 760×620 fixo. |
| 3 | **Sidebar: header** (:335-345) | sempre | Logo 17pt + "Racky" + `+`, que abre a sheet Nova sessão | — | O `+` é ícone plain sem hover. Sem botão de "novo terminal/agente" direto. |
| 4 | **Sidebar: busca** (:347-359) | sempre; ⌘K pelo menu … | Filtra pelo título da sessão, título do terminal e tipo/ID do subagente | sem estado "nenhum resultado" | Com busca sem resultado a lista fica vazia, sem mensagem: o texto "Nenhuma sessão" só aparece quando não há sessão nenhuma (:385). |
| 5 | **Sidebar: linha de sessão** (:438-478) | — | Chevron (colapsa), título, resumo de branch ("Várias branches" ou o nome) e badge de pedidos. Menu contextual: Renomear, Novo terminal. | — | **A sessão selecionada não tem destaque** (`.background(Color.clear)` :475), só peso `.medium`. **Não há como excluir/arquivar sessão** em lugar nenhum. Sem hover, sem ícone do agente, sem status agregado. O resumo de branch só aparece quando *todos* os terminais terminaram a checagem de Git. |
| 6 | **Sidebar: linha de terminal** (:480-554) | — | Chevron (se houver subagentes), logo do provider, título, badge, ícone de status (bolinha verde / spinner / ! / ✓). Embaixo: branch, "• Alterações" e remote. Menu contextual com 9 itens. | idle sem ícone | **Não há como excluir/remover terminal.** "Mostrar em pane" faz o mesmo que o clique simples. "Encerrar processo" aparece mesmo com o terminal parado. A altura muda de 30 para 42 quando o Git resolve, e a linha "pula". |
| 7 | **Sidebar: linha de subagente nativo** (:571-591) | Subagentes do Claude observados via hook | Tipo, ID curto, "Em execução"/"Concluído"/"Último evento: iniciado" | — | Texto "Último evento: iniciado" é jargão. Clique abre sheet. |
| 8 | **Sidebar: "+ Novo terminal"** (:374-383) | abaixo de cada sessão expandida | Abre a sheet Novo terminal | — | Repetido em cada sessão, polui a árvore. |
| 9 | **Sidebar: rodapé** (:404-423) | sempre | "Biblioteca" (texto + ícone), 🔔 (Pedidos, com badge), ⚙ (Configurações, ⌘,) | erro do monitor nativo aparece em laranja acima do rodapé (:395-402) | Hierarquia desigual (um item com label, dois só com ícone). Tudo abre sheet modal. ⌘, colide com a cena `Settings` (ver bugs). |
| 10 | **Divisor da sidebar** (:645-668) | arrastar / duplo clique | Redimensiona entre 224 e 480; duplo clique volta a 288 | — | `NSCursor.push/pop` desbalanceado em hover. A cor é igual à da sidebar, então o divisor não se vê. |
| 11 | **Toolbar** (:732-813) | sempre | Ver mapa. Status: "Parado/Iniciando/PID n/Saiu · n/Falhou". Botões: Git (popover), play/stop/force, computador, split H, split V, `+`, `…` | sem sessão: "Sessões" + `+` | Mostra **PID** como status principal (screenshot 01: "PID 42634"). 8 ícones plain de 13pt sem hover, sem agrupamento e sem tooltip visível ao passar rápido. O ícone ■ (stop) é um quadrado branco que parece um checkbox. Botões de split e `+` mudam de posição conforme o estado. |
| 12 | **"Tabs"** (`sessionTabs` :706-730) | com sessão selecionada | Uma tab por **terminal** da sessão: logo + título | — | Não são tabs de sessão como no Orca. Sem botão de fechar, sem `+`, sem indicador de status, sem drag. Clicar numa tab **substitui o conteúdo do pane focado** (`layout.show` → `replacing`, `WorkspaceStore.swift:101-109`) em vez de focar o pane onde o terminal já está, o que é inesperado com split. |
| 13 | **Popover Git e pasta** (:836-892) | botão de pasta/branch na toolbar | cwd, "Verificando Git…" / "Pasta comum" / erro / branch, limpo/sujo, remote, "Abrir repositório" (Link), "Criar worktree…", "Atualizar" | loading/plain/failed/checkout | Só texto, sem PR, sem ahead/behind, sem diff. Um único `@State showGitDetails` serve para qualquer terminal. |
| 14 | **Estado vazio global** (`emptyWorkspace` :894-904) | nenhuma sessão selecionada | Ícone ultraLight, "Nenhuma sessão aberta", texto, botão "Nova sessão" | — | Genérico. Menciona OpenCode. |
| 15 | **Sessão sem terminais** (`emptySession` :906-913) | **logo depois de criar uma sessão** | "Esta sessão ainda não tem terminais", "Escolha um CLI ou shell…", botão "Novo terminal" | — | É exatamente a "tela vazia" da queixa: criar uma sessão sempre cai aqui. |
| 16 | **Pane vazio** (`emptyPane` :915-923) | ao fechar o último pane | "Selecione um terminal na barra lateral" + "Abrir X" | — | Fechar um pane não encerra o processo, que continua rodando invisível. |
| 17 | **Pane de terminal** (`terminalPane` :967-1016) | terminal no layout | Header (só com mais de 1 pane): logo, título, status, ✕ (fecha o pane). Corpo: idle mostra "Pronto para iniciar X / cwd / Sessões restauradas aguardam início manual."; failed mostra a mensagem; o resto mostra o SwiftTerm. | idle / failed / running / exited | **Terminal recém-criado cai no estado idle** com o texto "Sessões restauradas aguardam início manual." mesmo não sendo restaurado. **Não há botão Iniciar no próprio pane**; o único ▶ fica na toolbar. Quando o processo sai, o SwiftTerm morto continua na tela sem overlay de "processo encerrado / reiniciar". O texto do terminal encosta na borda esquerda, sem padding (screenshot 01). Fonte 12pt fixa. |
| 18 | **Layout de panes** (`paneNode`/`splitDivider` :925-965, :686-694) | splits | Árvore H/V, divisores de 4pt invisíveis arrastáveis, duplo clique volta a 50% | Se `largura < n×260`, **esconde silenciosamente** todos os panes menos o focado, e sem header | Divisor invisível e sem cursor de resize. Limite de 5 panes sem aviso. |
| 19 | **Sheet Nova sessão** (`SessionEditor` :1474-1494) | `+` sidebar/toolbar, ⌘N, menu, botão do empty state | Campo "Nome da sessão", Cancelar, Criar | Criar fica desabilitado com o nome vazio | Pede **só o nome**: não pergunta agente, pasta nem repositório. Esc não funciona (Cancelar sem `.cancelAction`). |
| 20 | **Sheet Novo terminal** (`TerminalEditor` :1525-1592) | `+`, ⌘T, menu contextual, linha "+ Novo terminal", split sem candidato | Picker "Cliente" (**padrão Shell**), "Título (opcional)", "Pasta de trabalho" + "Escolher…", erros | pasta inválida → texto vermelho | A pasta padrão é o cwd do último terminal ou `~`. Criar **não inicia o processo**. Picker padrão do sistema, com visual de formulário cru. |
| 21 | **Sheet Renomear** (`RenameEditor` :1496-1523) | menu contextual | Campo + Cancelar/Salvar | — | Ok funcional. Sem rename inline (duplo clique). |
| 22 | **Sheet Criar worktree** (`WorktreeEditor` :1594-1682) | popover Git ou menu contextual (só se o Git resolveu) | Repositório, "Referência de origem" (HEAD), "Nova branch", "Destino" + "Escolher pasta pai…", aviso, progress | erro inline | O destino não é sugerido automaticamente (só depois de "Escolher pasta pai…"). Ao criar, abre um terminal **com o mesmo provider, parado** (`createWorktree` :1105). |
| 23 | **Sheet Retomar conversa** (`ConversationResumeView`) | menu … › "Retomar conversa…"; ou ▶ num terminal com `nativeConversation` | Picker Cliente, status do executável, "ID da conversa" (digitado), pasta, "Buscar sessões ativas" (só Claude), lista de conversas **abertas**, checkbox "Fechei esta conversa nos outros terminais", Cancelar / Retomar | — | Não lista o histórico de conversas: só as ativas, que justamente **não podem** ser retomadas. O usuário precisa saber o UUID. "Retomar no terminal" só habilita depois de marcar o checkbox, inclusive para Codex/OpenCode. |
| 24 | **Sheet Subagente nativo** (`nativeAgentDetails` :593-628) | clique em subagente | LabeledContent: Tipo, ID, Estado, Origem, Iniciado, Fim; texto explicativo; "Computador do subagente…", "Mostrar terminal pai" | registro sumido → texto | **Sem botão Fechar**. |
| 25 | **Sheet Computador do subagente** (:291-304) | botão acima | BrowserComputerPanel com owner `nativeChild`, 480 de largura | vínculo sumido → texto | **Sem botão Fechar**. |
| 26 | **Sheet Biblioteca** (`LibraryView`) | rodapé, menu … | HSplitView. Esquerda: "Agentes", "Web scraping" (cria agente com a skill local), `+`, busca, lista, toggle "Arquivados". Direita: nome, rN, menu "Revisões", "Editar", "Usar…", menu … (Duplicar, Arquivar/Restaurar), segmentos Instruções/Memória/Skills/Histórico, "Preparar contexto". | sem seleção: `ContentUnavailableView "Sua biblioteca"` | **Não tem botão Fechar** e Esc não fecha: o usuário fica preso numa sheet de 760×500 ou mais. Ícone genérico `person.crop.square` para todo agente. Botão "Web scraping" no header é um atalho de nicho no lugar mais nobre. "Preparar contexto" só gera texto (exportar/copiar), nada roda, e o rodapé diz isso. A aba Histórico mostra UUIDs crus. |
| 27 | ↳ Editor de agente (`AgentEditor` :178-191) | `+` / Editar | Nome, Descrição, Picker CLI, TextEditor Instruções | — | `TextEditor` com borda cinza crua. |
| 28 | ↳ Editor de memória (`MemoryEditor` :193-228) | "Nova memória" / ✏︎ | Título, Tipo, Escopo, ID do escopo, Fonte, Autor, validade, conteúdo | Salvar exige "Fonte" | 8 campos para uma nota. `agentID: selection ?? UUID()` (:91). |
| 29 | ↳ Aba Memória | — | Campos "ID do projeto/tarefa/perfil" livres + lista com checkbox, menu rN, ✏︎, arquivar, 🗑 (confirmação) | "Nenhuma memória salva." | IDs de escopo digitados à mão (UUIDs). |
| 30 | ↳ Aba Skills | — | "Importar SKILL.md" (NSOpenPanel), checkbox por skill, "Ver arquivo" | "Nenhuma skill importada." | Lista **todas** as skills globais em cada agente. |
| 31 | ↳ Aba Histórico | — | Execução UUID · rN, datas, terminal/sessão UUID, "Abrir terminal", computadores, perfis… | ContentUnavailable | Só UUIDs, ilegível. |
| 32 | ↳ Sheets Contexto / Skill / Revisão agente / Revisão memória (:168-260) | botões acima | Texto monoespaçado + Fechar/Exportar/Copiar | — | Ok, mas são sheet em cima de sheet. |
| 33 | **Sheet Usar agente salvo** (`AgentLaunchView`) | Biblioteca › "Usar…" (com pisca) ou Computador › "Revisar e iniciar agente" | Passo 1: Picker Sessão (+ "Nova sessão"), nome, pasta, 3 IDs opcionais, resumo, checkbox "Observar subagentes do Claude", memórias e skills (checkbox). "Preparar revisão". Passo 2: resumo, DisclosureGroup "Detalhes do lançamento" (paths, SHA-256), preview do contexto, **checkbox "Usar este contexto"**, "Alterar seleção", "Iniciar agente" | erro em vermelho; "Aguardando o processo encerrar…" + forçar | Três cliques e um checkbox obrigatório para rodar um agente. "Iniciar agente" fica cinza até marcar o checkbox, o que parece quebrado. Mostra SHA-256 e caminhos de hook ao usuário final. 690×550 fixo. |
| 34 | **Sheet Pedidos** (`HumanRequestsView`) | 🔔 / menu | "Precisam de você", lista: resumo, tipo · data, "Abrir terminal", UUID do computador | "Nenhum pedido pendente." | **Sem botão Fechar.** Não dá para resolver/dispensar o pedido pela lista. `request.kind.rawValue` é exibido cru. |
| 35 | **Sheet Configurações** (`AppSettingsView`) | ⚙ / menu … | Segmented: Clientes locais · Computadores · Credenciais · Recursos | — | **Sem botão Fechar.** É a mesma view da janela Settings nativa, ou seja, duas superfícies diferentes. |
| 36 | ↳ Clientes locais (`LocalClientsView`) | aba padrão | Para Claude/Codex/OpenCode: logo, nome, path, auth ("Autenticado no CLI"…), versão; "Verificar novamente" | busy → spinner; "Não instalado" | Ok. Shell não aparece. OpenCode sempre "Credenciais não verificadas". |
| 37 | ↳ Computadores (`DockerSettingsView`) | aba | Picker Conexão + "Usar esta conexão", status do daemon, "Verificar novamente"; Permissões globais: Criar computadores (Desativado/Manual/Orquestrador desabilitado), Modo, Rede, Steppers CPU/Mem/Teto; Restrições por escopo (lista, 🗑, "Adicionar restrição…" ► sheet `ComputerScopeEditor`); "Salvar configurações" | não legível → seções desabilitadas | **Os padrões fazem computadores falharem**: criação = `.disabled` e memória = 768 MiB, mas o runtime exige 2048 MiB (`ComputerPolicy.swift:13,71`). Edição e remoção de restrições só persistem depois de "Salvar configurações", sem aviso de "não salvo". |
| 38 | ↳ Sheet Restrição por escopo (`ComputerScopeEditor`) | acima | Escopo, ID/caminho, Criação, 3 toggles, steppers | erro | Exige colar UUID/caminho à mão. |
| 39 | ↳ Credenciais (`SecretSettingsView`) | aba | Nome + valor + Salvar; "Selecionar arquivo .env…" com revisão; lista mascarada; Concessões: Credencial, Escopo, "ID do escopo (UUID)", Uso, Destino, delegável, prazo, "Criar concessão", lista com Revogar | "Nenhuma credencial salva." | **Não dá para excluir credencial.** Concessão exige UUID digitado. |
| 40 | ↳ Recursos | aba | Toggle de notificação + 4 seções de texto estático | — | É praticamente só texto explicativo, uma aba quase morta. |
| 41 | **Janela Settings nativa** (`RackyApp.swift:60`) | menu do app › Settings… / ⌘, | AppSettingsView | — | Duplica a sheet do item 35. |
| 42 | **Sheet Computador** (`ComputerPanel`, `DockerViews.swift:126-231`) | 🖥 na toolbar | "Computador" + BrowserComputerPanel + **segunda seção legada "Container HTTP básico"** (UUID do terminal, status do Docker, criar/iniciar/parar o container HTTP, "Política: Global → …", texto "atribuição automática ainda está em implementação", "Atualizar estado") | Verificando Docker…, erros | **Sem botão Fechar.** São dois "computadores" diferentes na mesma tela (navegador e HTTP), cada um com seus botões, e o UUID cru do terminal aparece. |
| 43 | ↳ BrowserComputerPanel (`BrowserComputerPanel.swift`) | dentro do 42/25 | Sem box: "Criar computador". Com box: Em execução/Parado, "Capturas e dados", "Autorizar acesso ao token", "Revisar e iniciar agente" / "Definir agente de scraping padrão", "Abrir desktop", "Parar"/"Iniciar", "Atualizar computador", menu "Modo" (HTTP/Headless/Desktop), "Recuperar atualização", "Atualizar" | busy → ProgressView; erro em vermelho | "Criar computador" **não fica desabilitado pela política** (ao contrário do HTTP), então o clique termina em erro com a política padrão. Muitos textos de aviso em `.caption`. |
| 44 | ↳ Sheet Desktop remoto (`RemoteDesktopView`) | "Abrir desktop" | Barra "Computador" + Fechar; "Desktop completo", Assumir/Devolver, Reconectar, canvas com mouse/teclado | live/connecting… | Ok (tem Fechar). Mínimo 800×560, como sheet sobre sheet. |
| 45 | ↳ Sheet Capturas e dados (`CapturePanel`) | "Capturas e dados" | Segmented Requisições/Dados/Captura; lista de requisições com checkbox, "Apagar capturas…"; datasets (nome, criar, JSON/CSV/Excluir…); filtros (hosts, paths, campos, limites) + Descartar/Aplicar; Atualizar, **Fechar (Esc funciona)** | confirmações | É a única sheet com `.cancelAction`. 720×550. |
| 46 | **Alerts / dialogs globais** | — | "Erro no workspace" (saveError, também usado para erros de start), "Arquivo de sessões indisponível", "Vínculos de lançamento indisponíveis", confirm "Forçar encerramento", NSAlert de sair com processos e NSAlert "Alguns computadores não puderam ser encerrados" | — | Erros de start de agente aparecem num alert genérico com o título "Erro no workspace". |

---

## 3. Bugs / coisas quebradas (arquivo:linha)

**Críticos para a sensação de que "nada funciona"**

1. **Sheets sem saída.** Biblioteca (`WorkspaceView.swift:239`), Pedidos (:248), Configurações (:265), Computador (:267), Subagente nativo (:289) e Computador do subagente (:291) não têm botão Fechar nem `.keyboardShortcut(.cancelAction)`. No macOS, uma sheet SwiftUI não fecha com Esc sem um botão `.cancelAction`, então o usuário fica preso. O único jeito de sair é acionar um botão interno que navega (ex.: "Usar…").
2. **Criar terminal não inicia o processo.** `createTerminal` (:1438-1449) só adiciona o registro. O pane mostra "Pronto para iniciar … Sessões restauradas aguardam início manual." (:990-996) e o único ▶ fica na toolbar (:818). O usuário cria o terminal e "nada acontece".
3. **Criar sessão cai numa tela vazia.** `createSession` (:1112-1117) cria a sessão sem terminal, e o resultado é `emptySession` (:906). O provider padrão do novo terminal é **Shell** (:1528), não o agente.
4. **Passado o limite de 5 panes, o novo terminal fica invisível.** `createTerminal` :1445-1447 não tem `else`: com 5 panes visíveis o terminal é criado, mas não é mostrado nem focado.
5. **Clicar numa tab troca o conteúdo do pane focado** em vez de focar o pane onde o terminal já está. `selectTerminal` → `layout.show` (`WorkspaceStore.swift:101-109`) faz `replacing(oldID…)` quando o terminal não está visível. Quando ele está visível, só foca. Com split, a tab "some" do lugar.
6. **Panes somem com a janela estreita.** Com `geometry.size.width < n*260` (:687), só o pane focado é renderizado, sem header e sem aviso.
7. **Não dá para excluir sessão nem terminal.** Não há ação de remove/delete em `WorkspaceView` (grep). "Fechar pane" (:976-980, :786-788) não encerra o processo, que continua vivo e invisível.
8. **Computador falha com a configuração padrão.** `ComputerPolicy()` vem com `creation: .disabled` e `memoryMiB: 768` (`ComputerPolicy.swift:13,71`), mas o runtime exige 2048 MiB (texto em `DockerViews.swift:38`). Em `BrowserComputerPanel.swift:150-160`, "Criar computador" não verifica a política e só falha depois do clique.
9. **Texto aponta para uma aba que não existe:** "Criação desativada em Configurações › Docker." (`DockerViews.swift:172`). A aba se chama "Computadores" (`AppSettingsView.swift:10`).
10. **Conflito de ⌘,.** O botão da sidebar usa `.keyboardShortcut(",")` (:418), e a cena `Settings {}` (`RackyApp.swift:60`) registra ⌘, no menu do app. Resultado: são duas telas de configurações (sheet e janela) e o atalho abre provavelmente a janela, não a sheet.
11. **Atalhos que só existem em certos estados.** ⌘D/⌘⇧D (:760,764) só com terminal focado; ⌘T (:769) só com sessão selecionada (sem sessão, o `+` não tem atalho). ⌘N, ⌘K e ⌘⌥[/] estão em itens de um `Menu` da toolbar (:777-806). Esses atalhos dependem do SwiftUI registrar key equivalents de itens de um `Menu` fechado, o que não é confiável. Não há `.commands {}`, então nada aparece na barra de menus.
12. **Retomar conversa é praticamente inutilizável.** Só lista conversas **ativas** do Claude (`ConversationResumeView.swift:93-125`), que são exatamente as bloqueadas (`isListedActive`). Para retomar é preciso digitar o UUID, e `canResume` exige o checkbox `externalWriterClosed` para qualquer provider (:47-50).
13. **Lançar agente salvo:** "Iniciar agente" fica desabilitado até marcar "Usar este contexto" (`AgentLaunchView.swift:106,254-256`), e um clique em "Preparar revisão" vem antes. Parece um botão quebrado.
14. **Erros de start aparecem como "Erro no workspace".** `startTerminalValidated` grava `saveError` (:1298,1306,1334), que é o mesmo alert de erro de salvar arquivo (:307).
15. **Sessão selecionada sem destaque.** `.background(Color.clear)` (:475). O usuário não sabe qual sessão está ativa.
16. **Cursor do divisor da sidebar.** `NSCursor.push()/pop()` em `onHover` (:650) pode desbalancear a pilha de cursores, por exemplo se o hover sai durante um drag.
17. **`showGitDetails` é um `@State` único** (:128). Dá para apresentar o popover para um terminal e trocar de terminal: `selectTerminal` zera o estado, mas o menu contextual não.
18. **Duplicata de UI legada.** `ComputerPanel` (`DockerViews.swift:146-179`) mostra o "Container HTTP básico" junto do computador-navegador, com o próprio texto dizendo "ainda está em implementação".
19. **Escape dos editores.** SessionEditor/RenameEditor/TerminalEditor/WorktreeEditor/AgentEditor/MemoryEditor/ComputerScopeEditor/ConversationResume/AgentLaunch têm Cancelar sem `.cancelAction` (:1485, :1514, :1564, :1642; `LibraryView.swift:189,216`; `DockerViews.swift:121`). Esc não cancela.
20. **Credenciais não podem ser excluídas** (`SecretSettingsView.swift:56-63`, sem ação de remover).
21. **Pedidos não podem ser resolvidos/dispensados** pela lista (`HumanRequestsView.swift:48-65`).
22. **Restrições de computador removidas pela 🗑** (`DockerViews.swift:49`) só persistem com "Salvar configurações". Não há indicador de alteração pendente (o `saved` não volta a `false` ao remover).
23. **Processo que saiu continua mostrando o SwiftTerm morto** (`terminalPane` `default:` :1004-1005). Não há overlay de "Encerrado · Reiniciar" e o status vira apenas "Saiu · n" na toolbar.

**Código morto / redundante**

- Menu contextual "Mostrar em pane" (:538) faz o mesmo que o clique simples.
- A aba "Recursos" das Configurações (`AppSettingsView.swift:14-27`) é texto estático, fora um toggle.
- "Preparar contexto" da Biblioteca (`LibraryView.swift:83`) e a sheet de contexto (:168) duplicam a revisão do AgentLaunchView. Só servem para exportar texto.
- O picker "Orquestrador · integração pendente" fica permanentemente desabilitado (`DockerViews.swift:32`).
- `WorkspaceChrome.paneHeader` só é usado no header de pane, e as cores ficam espalhadas sem um design system.
- A cena `Settings` duplica a sheet `.settings`.

---

## 4. Problemas visuais

- **Barra de título nativa** de cerca de 28pt com o texto "Racky". O conteúdo começa abaixo dos semáforos, e não na mesma linha como no Orca (screenshot 01). Nome repetido no header da sidebar.
- **Três faixas horizontais empilhadas** no topo: titlebar (cinza), toolbar 40pt (#191919) e strip de tabs 35pt (#191919). O título da sessão fica na toolbar, separado das tabs, o que dá o topo "desencaixado".
- Tabs são de terminal, não de sessão. A tab ativa usa a cor do canvas (#272B33) e as inativas, a da tabbar. Não há borda, ✕, status nem `+`.
- **Paleta incoerente:** sidebar #282828 (cinza neutro), canvas #272B33 (azulado), toolbar/tab #191919. A sidebar e o terminal têm temperaturas diferentes.
- **O terminal não tem padding**: o prompt encosta na borda esquerda e no topo do pane (screenshot 01). Fonte fixa 12pt.
- **Toolbar** com 8 ícones SF Symbols plain, sem hover nem grupos. O "stop" é um quadrado branco sólido. O status "PID 42634" é informação de debug.
- **Sidebar:** sessão sem highlight; terminal selecionado com fundo #333 e cantos de 4pt; nenhum hover state em nada. Rodapé "Biblioteca" com label e os outros só com ícone. "Biblioteca/Settings saem da caixa": são sheets modais de 760×500+ com `Form .grouped` padrão e sem Fechar, com aparência de outra app.
- Linhas de terminal mudam de altura (30 para 42) quando o Git resolve, e a lista "pula".
- **Animações:** só `.easeOut(0.14)` no colapso da sidebar (:179). Nada em seleção, troca de tab, abertura de pane, split, criação ou status. Não há transições, matchedGeometry nem hover.
- As sheets usam o estilo padrão do macOS (segmented, Picker, Form, TextEditor com `.border`), com tipografia e espaçamento inconsistentes: tamanhos fixos de 680, 690, 720, 760 etc., `.caption` em excesso e parágrafos longos de aviso legal/técnico.
- Divisores (sidebar e split) invisíveis, sem affordance.
- Ícone genérico `person.crop.square` para todo agente na Biblioteca. Logos dos providers só no workspace.

---

## 5. Fluxos principais como estão hoje (passo a passo)

### 5.1 Criar sessão
1. Clicar `+` (header da sidebar ou toolbar), ⌘N (pelo Menu …) ou "Nova sessão" no estado vazio.
2. A sheet "Nova sessão" pede **só o nome**. Criar.
3. A sessão aparece na sidebar (sem destaque) e a área principal mostra "Esta sessão ainda não tem terminais" com o botão "Novo terminal".
4. Nenhum terminal nem agente foi aberto. O usuário precisa ir para o fluxo 5.2.

### 5.2 Criar terminal
1. `+` da toolbar / ⌘T / "+ Novo terminal" na sidebar / menu contextual da sessão.
2. Sheet "Novo terminal": Cliente (padrão **Shell**), Título opcional, Pasta (padrão: cwd do último terminal ou `~`), "Escolher…" (NSOpenPanel e bookmark).
3. Criar: o terminal entra na árvore e no layout (vira root ou split à direita do focado). Com 5 panes, fica invisível (bug 4).
4. O pane mostra "Pronto para iniciar <Cliente> / cwd / Sessões restauradas aguardam início manual.".
5. O usuário precisa achar o ▶ na toolbar. Só então `runtime.start` executa `claude`/`codex`/`opencode`/`zsh -l` no PTY e aparece o SwiftTerm.

### 5.3 Lançar agente (salvo na Biblioteca)
1. Rodapé › Biblioteca (sheet sem Fechar).
2. Criar agente (`+` › editor: nome, descrição, CLI, instruções) ou "Web scraping".
3. Selecionar o agente › "Usar…". A Biblioteca fecha e, no `onDismiss`, abre a sheet "Usar agente salvo".
4. Escolher a sessão (ou "Nova sessão" + nome), a pasta, IDs opcionais, resumo, "Observar subagentes", memórias e skills.
5. "Preparar revisão" › tela de revisão (paths, SHA-256, preview do contexto).
6. Marcar o checkbox "Usar este contexto". Só então "Iniciar agente" habilita.
7. `launchSavedAgent` (:1145-1254) grava os bindings e o workspace, registra o MCP do computador se houver, inicia o processo e grava o histórico. Erros aparecem em vermelho e pedem nova revisão.
8. O terminal aparece com split à direita do focado e roda.

### 5.4 Abrir computador
1. Selecionar um terminal › 🖥 na toolbar › sheet "Computador" (sem Fechar).
2. Em cima, "Navegador e desktop": "Criar computador". Com a política padrão (criação desativada, 768 MiB) **falha com erro**. O usuário precisa ir em Configurações › Computadores, trocar para "Manual", subir a memória para ≥2048, "Salvar configurações", e voltar.
3. Depois de criado: "Abrir desktop" (troca o modo para desktop e abre a sheet RemoteDesktopView com Assumir/Devolver), "Modo", "Capturas e dados" (sheet CapturePanel), "Definir agente de scraping padrão" › "Revisar e iniciar agente" (fecha e abre AgentLaunchView em modo scraping, que substitui o processo do terminal).
4. Embaixo, uma 2ª seção "Container HTTP básico" com outro "Criar computador HTTP" (desabilitado pela política).

### 5.5 Biblioteca
- Lista de agentes (busca, arquivados) e detalhe com 4 abas. Memória: criar/editar/arquivar/excluir, selecionar por checkbox, IDs de escopo digitados. Skills: importar SKILL.md, selecionar. Histórico: execuções com UUIDs e "Abrir terminal". "Preparar contexto" gera texto para copiar/exportar. Revisões viram sheets de leitura. Não há como sair sem acionar uma ação que navega (bug 1).

### 5.6 Settings
- Duas portas: a sheet (⚙ / menu …) e a janela nativa (menu do app, ⌘,). Quatro abas: Clientes locais (detecção e auth dos CLIs), Computadores (Docker, política, restrições, salvar explícito), Credenciais (Keychain, .env, concessões por UUID), Recursos (toggle de notificação e textos). A sheet não tem Fechar.

### 5.7 Git
1. Automático: ao aparecer, ao mudar sessões e ao ativar o app, `refreshGit` roda `GitWorkspaceInspector` em background para cada terminal (:1028-1060).
2. Sidebar: branch, "• Alterações" e remote embaixo de cada terminal; resumo de branch na linha da sessão.
3. Toolbar: botão com pasta/branch e ponto laranja se sujo › popover "Git e pasta" (cwd, branch, limpo/sujo, remote, "Abrir repositório", "Criar worktree…", "Atualizar").
4. Criar worktree: sheet (referência, nova branch, destino). Cria via `GitWorktreeManager` e abre um terminal parado no worktree com o mesmo provider.
5. Não há integração com GitHub (PR, checks, ahead/behind, diff). "Abrir repositório" só abre a URL web do remote.

### 5.8 Atalhos de teclado existentes
| Atalho | Ação | Onde | Observação |
|---|---|---|---|
| ⌘B | toggle sidebar | toolbar :739 | ok |
| ⌘T | novo terminal (sheet) | toolbar :769 | só com sessão selecionada |
| ⌘D / ⌘⇧D | split direita / abaixo | toolbar :760/:764 | só com pane focado; pode abrir a sheet de novo terminal (:1467) |
| ⌘N | nova sessão | item do Menu … :779 | registro duvidoso (item de Menu) |
| ⌘K | focar busca | item do Menu … :798 | idem |
| ⌘⌥[ / ⌘⌥] | estreitar/alargar sidebar | Menu … :800/:802 | idem |
| ⌘, | configurações | sidebar :418 e cena Settings | conflito |
| Return | ação default das sheets | vários | ok |
| Esc | fechar | **só no CapturePanel** | nas demais sheets não funciona |

Não há atalhos para trocar de sessão/tab (⌘1…9, ⌃Tab), fechar pane (⌘W), iniciar/parar processo ou abrir a Biblioteca.
