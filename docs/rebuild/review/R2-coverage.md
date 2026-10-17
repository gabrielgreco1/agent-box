# R2 · Revisão de cobertura: auditoria 01..10 → spec 00..08

Data: 2026-10-16. Escopo: verificar se cada achado, requisito, bug, lacuna, sugestão e recomendação da auditoria (`docs/rebuild/audit/01..10`) foi coberto pela spec (`docs/rebuild/spec/00..08`, com `00-decisions.md` prevalecendo) ou descartado com motivo explícito. A spec não foi editada; este documento só registra o que encontrei.

## 1. Método

1. Extraí as listas de cada relatório com os IDs do próprio relatório: 01 §1.A–1.AB, §2, §3.1, §3.2, §4 e §5.2; 02 §2–§7; os 23 bugs e os problemas visuais de 03; 04 §4–§9; 06 §3–§6; os 55 achados de 07 e as correções; os P0/P1/P2 de 05 e as lacunas (a)–(e) e transversais; os 27 achados N* de 08, a §1 (login no container), a lista de capacidades da §3 e as correções; os 19 achados de 09, as seções §2, §3, §4 (D1–D12), as correções e a §6; os R*.* e RT.* de 10 e as seções §11, §12 e §13. Onde o relatório não numerava, criei IDs como `03-B1`, `04-F5c` ou `06-C7`.
2. Procurei cada item na spec por termo-chave e conferi o texto do requisito ou do AC citado. A matriz de `spec/05` (requisito → jornada → AC) não foi usada como prova: cada AC dela foi aberto e lido. Todos os ACs citados na matriz existem.
3. Cada item recebeu uma classificação: **COBERTO** (requisito, AC ou tela), **DESCARTADO** (later ou fora, com motivo escrito: T14, 01 §4.3 ou 01 §4.4), **PARCIAL** ou **SEM**. Os itens puramente descritivos do app antigo (13, todos em 01) ficaram como N/A e saíram da conta.
4. Quatro agentes leram em paralelo, cada um com um grupo de relatórios. Eu verifiquei por amostragem os achados que pesam: M-606 com ⌘⇧T, AC-406 contra CS-132, CS-160, "Outro CLI" em 01 §5.6, bookmark em 03 §6.1, ⌘T e o nome da seção "Scratch"/"Sessions". As tabelas completas, com uma linha por item, ficaram no scratchpad da sessão (`cov-01-02.md`, `cov-03-04-06.md`, `cov-05-08-10.md`, `cov-07-09.md`).

## 2. Taxa de cobertura

| Relatório | Itens | Coberto | Descartado | Parcial | Sem | Coberto + descartado |
|---|---|---|---|---|---|---|
| 01 (inventário, capacidades, contradições, sugestões, v0.4) | 401 (+13 N/A) | ~317 | ~50 | ~24 | 10 | 91,5% |
| 02 (core, bugs §6, lógica na UI, recomendações) | 65 | 64 | 1 | 0 | 0 | 100% |
| 03 + 04 + 06 (telas, 23 bugs, visuais, Orca, motion) | 274 | 251 | 14 | 6 | 3 | 96,7% |
| 05 + 08 + 10 (P0/P1/P2, login, N*, capacidades, R*.*) | 301 | 242 | 31 | 21 | 7 | 90,7% |
| 07 + 09 (55 achados UI, 19 N arquitetura, D1–D12, correções) | 144 | 137 | 0 | 7 | 0 | 95,1% |
| **Total** | **1185** | **~1011** | **~96** | **58** | **20** | **93,4%** |

Somando os parciais, 98,3% dos itens têm algum tratamento. Apenas 20 itens (1,7%) não aparecem em lugar nenhum, e nenhum deles é P0 nem severidade Alta. Os riscos maiores estão nas **contradições internas** entre capítulos (§5), não na falta de cobertura.

Alguns blocos fecham inteiros:
- 23 bugs de 03: 23/23 cobertos.
- 20 bugs e riscos de 02 §6: 20/20.
- 19 achados de 09: 19/19 com AC.
- 55 achados de 07: 51 cobertos e 4 parciais.
- R*.* de 10: todos com AC ou com descarte explícito ("later"/"out" na matriz de 05 e em 01 §4.3).
- P0 de 05 (P0.1–P0.13): todos com AC.
- Capacidades de subagente (01 §2 e 08 §3): todas em 07 §3.2 A–K. As exceções são cap.37 (retomar filho nativo, parcial) e N6 (tabela de capacidades por harness, parcial).

## 3. Itens SEM cobertura nem descarte (20)

| # | Origem | Item | Sev. | Onde deveria entrar |
|---|---|---|---|---|
| 1 | 05 e3, backlog P1 #14 | Paleta "Insert skill/agent" que insere no prompt do pane focado. Atende à queixa da biblioteca fácil (§6, item 15) | **Média** | 03 §8 (palette) e 06 §4.2 |
| 2 | 08 N21 | Notificação "lote concluído" com resumo | **Média** | 03 §9.1 (tipos de evento) e 07 §4.3 |
| 3 | 01 Y4 | Validar caminhos contra `../` e symlinks (`/work`, `browser_upload`, `save_as`, `body_file`, upload pelo painel Files) | **Média** | 07 §3.2 D/H e CS-423 |
| 4 | 01 V7 | Migração ou backup do perfil de browser quando a imagem atualiza o Chromium | **Média** | 07 §2.7, junto de CS-123 |
| 5 | 01 R9 | Regra do worker: preferir APIs oficiais e nunca comprar, mandar mensagem ou alterar conta | **Média** | 07 CS-330/331 (skill e prompt do worker) |
| 6 | 04 F2b | Sparse checkout e parent workspace no Advanced do composer | Baixa | 03 §6.2, ou descarte em 01 §4.4 |
| 7 | 04 F2c | "Create from" aceitar URL de GitLab, Linear ou Jira | Baixa | 03 §6.1, ou descarte |
| 8 | 04 F7b | Settings por projeto | Baixa | 03 §14.2, ou descarte |
| 9 | 05 e5 | Visualizador da memória automática do Claude | Baixa | 06 §4.1 |
| 10 | 05 d4 | Comentar em PR | Baixa | 01 §4.3 (later) |
| 11 | 05 c5 | Arrastar pane para reorganizar | Baixa | 06 §1.8 ou 03 §4.3 |
| 12 | 08 §1.4D | Spike do `codex exec-server` ("terceiro modo") | Baixa | 07 §9 (spikes) |
| 13 | 08 §1.5 | SSH na box: deploy key, sem repassar o ssh-agent | Baixa | 07 §6.4 |
| 14 | 01 V9 | Recuperar perfil de browser corrompido | Baixa | 07 §2.7 |
| 15 | 01 V6 | Proteção em repouso do perfil de browser | Baixa | 07 §2.7 ou 08 §5 |
| 16 | 01 E8 | Renomear a conversa nativa | Baixa | 06 §2.5 |
| 17 | 01 G7 | Promover uma execução a agente salvo | Baixa | 06 §4.3 (v1.1) |
| 18 | 01 N9 | Gravação ou replay da sessão da box | Baixa | 01 §4.3/§4.4 (falta só o descarte explícito) |
| 19 | 01 AA10 | Ícone e marca do app no Dock | Baixa | 02 §9 |
| 20 | 01 sug. 9 | Templates de sessão e de layout | Baixa | 01 §4.3 ou 03 §6/§7 |

## 4. Itens PARCIAIS mais relevantes

A lista completa dos 58 está nas tabelas de scratchpad. Ficam aqui os de severidade Média e os que tocam queixas do dono.

| Origem | O que falta | Sev. | Onde |
|---|---|---|---|
| 03-B22 | Settings sem regra de salvar: falta dizer que salva ao sair do campo, que não há botão Salvar e como aparece a mudança pendente. A Library › Profiles tem essa regra, Settings não. Toca a queixa 8 | Média | 03 §14.1 |
| 04-F5c | Arrastar tab até a borda para fazer split: M-306 cita o gesto, 03 §3.4 só reordena e TA-119 manda para v1.1 | Média | 03 §3.4 e versão em 01 §4 |
| 07 #45 | Variante isolada do diálogo "Stop computer" e popover "Box" (CPU, memória, modo) no header da tab | Média (v1.1) | 03 §16.3 e §4.2 |
| 09 §2.7d / correção 9 | AR-533 descarta bookmarks, mas 03 §6.1 diz "Pasta escolhida vira bookmark" e os menus de 03 §2.6 mantêm "Reauthorize Folder…" | Média | 03 §6.1, §2.5 e §2.6 |
| 01 C15 / sug. 20 | "Outro CLI": 06 §2.1/§2.2 tem `.custom(argv)` e "Custom Command", e 01 §5.6 diz "fica para depois" | Média | 01 §5.6 e 08 AR-311 |
| R10.3 / 08 N10 | Níveis do orçamento Zyte: 10, 05 e 03 dizem box⊂sessão⊂dia; 07 CS-160 diz box, lote e mês. A versão também diverge: v1 em 07 e 03, v1.1 em 01 e 05 | Média | unificar em 00 ou em 07 §2.6 |
| AC-406 | Exige 15 headless + 2 desktop em 24 GB, mas CS-132 calcula ≈ 25 GiB e CA-103 usa 28 GiB. Do jeito que está escrito, o AC reprova | Média | 05 AC-406 |
| 05 b8 / R7.4 | MCP do computador no Codex: CS-004 diz v1; 06 §2.8 e R7.4 dizem v1.1 | Média | 00 ou 07 CS-004 |
| R5.3 | Diff só leitura: AC-507 e 01 dizem v1.1, TA-515 diz later e 06 não tem TA de diff | Média | 06 §5 |
| 08 N7 | Lote como entidade: CS-323/324 dizem v1, 01 §4.2 diz v1.1 | Média | 01 §4 ou 07 |
| R8.4, cap.37, N6, 08 N1 | "Manter acordado" só tem AC, sem requisito. Retomar filho nativo não está definido. Falta a tabela de capacidades por harness verificada por versão. `agent_spawn` no modo leve (CS-304) não tem AC | Baixa | 07 e 05 |
| 07 #35, #50 | Fixar e colorir tab, terminal flutuante ⌘⌥A e kanban de agentes sem decisão (nem later, nem fora) | Baixa | 01 §4.3/§4.4 |
| 09 §2.8 | Teto de memória por sessão no daemon (40 MB e 10 mil linhas) | Baixa | 06 §1.5 ou 08 |
| Divergências de versão | R3.4 (TA-505 v1 × AC-317 v1.1), R4.10 (8 min v1 × 10 min v1.1), R4.11, R6.7, R7.3, clone, Automations (T14 "fora" × 01 §4.3 "later"), R8.6 (later, mas o switch já está em 03 §14) | Baixa | matriz de 05 e 01 §4 |

## 5. Contradições internas da spec

Não são lacunas de cobertura, mas fazem o implementador construir a coisa errada. Recomendo resolver antes de começar a Fatia 1.

| Sev. | Contradição | Arquivos |
|---|---|---|
| **Alta** | **⌘T.** Em 03 §3.3, §18 e §21, ⌘T = `New Terminal` (shell) e o lançador é Quick Launch em ⌘⌥N. Em 06 §1.8, "⌘T abre o lançador". Em 05 J3 passo 11 e AC-313, "⌘T abre o seletor… escolhe Codex". O teste AC-313 falha contra a tela de 03. Atinge as queixas 4 e 16 | 03, 05, 06 |
| **Alta** | **Nome da seção de sessões limpas.** 03 §2.10, §16.8 e Settings usam "Scratch" (⌘⇧N "New Scratch Session"). 01 §5.3, §7, 05 J1/J11, AC-305, AC-1101 e 06 §2.7 usam "Sessions" e "clean session". AC-1105 cita "New Clean Session in Folder…", que não existe em 03 | 01, 03, 04 (M-212), 05, 06 |
| Média | AC-T26 manda comparar com a "checklist de fidelidade de 03", que não existe em spec/03. A 04 §8 da auditoria precisa ser copiada para 03 ou para DS §15 | 05, 03 |
| Média | M-606: "Take control" em ⌘⇧T, mas em 03 é ⇧⌘R, e ⇧⌘T é Reopen Closed Tab | 04, 03 |
| Média | spec/03 tem 22 referências `M:B8`, `M:C9`, `M:E2` (IDs da auditoria 06); spec/04 usa `M-xxx` e não há tabela de equivalência | 03, 04 |
| Média | `accessibilityIdentifier`: spec/04 usa `sidebar.sessionRow.<id>` e `computer.viewer.<id>`; 03 §22 usa `sidebar.session.<id>` e `viewer.<id>`. Os testes A3 e A12 dependem disso | 03, 04 |
| Média | Anexar arquivo arrastado ao prompt aparece em 03 §6.1 e §2.14, mas R3.6 está em "Depois". O rótulo "(P2)" usado ali colide com P2 de 00 ("UI em inglês") | 03, 01 |
| Média | `session.kind`: 08 AR-311 tem `worktree`/`clean`; 01 §5.3 tem `worktree\|checkout\|folder\|clean` | 01, 08 |
| Baixa | Library: M-108 a trata como painel lateral, 03 como página do centro. Inbox: M-109 a trata como tela cheia, 03 como feed na sidebar. M-112 anima card e avatar, mas a Library é lista e DS §15 proíbe avatar. Foco: M-803 diz 2 pt, DS9 diz 3 pt. M-211 usa ⌘⇧E, que não está na tabela de atalhos. Modos do computador: HTTP/Headless/Desktop em 03 §14, none/browser/desktop em 07. Filtros da sidebar: R2.6 está em "later", mas 03 §2.4 já especifica o menu Filter | 01, 02, 03, 04, 07 |

## 6. Queixas originais do dono, uma a uma

| # | Queixa | Onde a spec resolve | Veredito |
|---|---|---|---|
| 1 | Barra de título sobrando; o conteúdo deve começar na linha dos semáforos | T5; 03 §1.1 (`fullSizeContentView`, sem `NSToolbar`), §1.2 (semáforos em y=18, x=16/36/56), §1.3 (faixa de 36 na sidebar; tab row 32 + 4 de arrasto = 36 alinhada); DS §15 regra 18 (nome do app uma vez só) | **Resolvido.** Falta um AC visual específico: hoje só AC-T26, que aponta para uma checklist inexistente (§5) |
| 2 | Tabs estilo Orca com logo do agente e nome; topo "desencaixado" | DS §12.7 (indicador → `AgentLogo 12` → título; barra ativa de 2 pt; 32 de altura); 03 §3.1–§3.5; alinhamento de 36 entre faixa da sidebar, tab row e activity bar (03 §1.3, §10.1); M-301 | **Resolvido** |
| 3 | Criar sessão abre sozinha o terminal do agente escolhido | P9; 03 §6.4 ("abre a tab já rodando o agente… sem tela vazia, sem ▶"); 06 §2.4; AC-307, AC-306, AC-1101 | **Resolvido** |
| 4 | Tela de novo terminal "ridícula" | Some a tela própria: Quick Launch em popover de 300 (03 §7), "+" da tab row, ⌘⌥T direto no agente padrão; DS §15 (anti-AI) | **Resolvido no desenho, com a contradição do ⌘T** (§5): 03 diz shell, 05 e 06 dizem lançador |
| 5 | Estado vazio sem terminal | P9; 03 §6.4; §4.7 (o vazio só aparece quando o usuário fecha a última tab, e oferece `New Claude Code Tab`); §19 landing só sem projetos; AC-1101 | **Resolvido** |
| 6 | Sessão bonita na sidebar com GitHub integrado | 03 §2.6 (card com branch, ponto de alterações, ↑n, chip de PR com glifo de checks, hover card com PR e checks, menu Open/Create PR); DS §12.9, §2.9; 06 §5.3–§5.6; AC-501, AC-503, AC-504 | **Resolvido.** Diff e "Send failures" ficaram para v1.1 (R5.3, R5.5) |
| 7 | Biblioteca, agentes e Settings "saindo da caixa", espaçamento ruim, nav mal feita | Settings: 03 §14.1 (nav de 240, conteúdo até 720, controles de 240, linhas de 30). Library: 03 §13.1 (lista 320 + detalhe). Nav da sidebar: 03 §2.3 e DS §12.8. Escalas: DS §5–§7 e §15 regra 15 | **Parcial.** O layout está fixado, mas nenhum AC verifica que nada transborda ou corta texto na largura mínima (760) nem com nomes longos. Só A11 de 04 §11 ("conteúdo fora do container") cobre isso, e só para motion. Sugestão: AC em 05 JT "cada página do centro e o Settings a 760×480 e a 1440×900 sem clipping nem scroll horizontal, com fixtures de nomes longos". Também falta a regra de salvamento do Settings (03-B22) |
| 8 | "Tudo que clico parece que não funciona" | PP-1 (01 §3); AC-T01 (identificador em todo controle), AC-T02 (toda ação registrada tem teste com efeito; desabilitado tem tooltip com motivo); RT.3 / AC-T12 (ação longa com estado no lugar); AC-306 (overlay fecha em menos de 100 ms); M-801 (press) | **Resolvido** |
| 9 | Animações ao abrir tela, com o agente usando tela e com o agente sendo lançado, seguindo o workflow da skill de motion | P8; 04 §7.1 (abrir telas: M-101/102, M-108, M-109), §7.2 (lançamento: M-501→504, M-507), §7.3 (computador: M-604–M-609); §9 (workflow com a skill `motion-designer`: beats, HTML com tokens, variações A/B/C, render Playwright a 60 fps, revisão do dono, port, `compare.sh`); §11 (critérios A1–A13); AC-T25, AC-310 | **Resolvido.** Contradições de M-108/M-109/M-112/M-606 em §5 |
| 10 | Sessões limpas além de projetos e worktrees | P10; 01 §5.3; 06 §2.7; 03 §2.10, §6.1 (Scratch no composer), §16.8 (promover); J11 com AC-1101 a 1108 | **Resolvido, com a contradição do nome** "Scratch" × "Sessions" (§5) |
| 11 | CLI no container já logado | P7; 03 §14.2 Accounts › Isolated boxes; J4b com AC-453 (logado sem ação humana, token fora de argv e `inspect`), AC-454 (8 h sem logout), AC-455 (broker de git) | **Resolvido para v1.1**, por decisão do dono (P6). Na v1 o CLI roda no Mac e já está logado |
| 12 | Spawn de subagentes headless e com GUI, com todas as capacidades | P5/P6; 07 §2 (runtime, Xvfb sempre, troca de tipo sem recarregar §2.9) e §3.2 A–K (browser, desktop, shell, HTTP, reqlog, proxy, diário, ajuda humana, pai); 07 §4; J4 com AC-401 a 425; J4b para o isolado | **Resolvido.** Pequenas lacunas: Y4 (validação de caminho), V7 (perfil após atualizar o Chromium), R9 (regras do worker), cap.37 (retomar filho) |
| 13 | Multi-terminal | 06 §1.8 e TA-112/113 (tabs como grupos de panes, splits ilimitados, foco por teclado, zoom, persistência); 03 §3–§4; daemon §1 (TA-101 a 118); AC-611, AC-801 a 803 | **Resolvido.** Arrastar pane (05 c5) e split por arrastar tab (04-F5c) estão abertos |
| 14 | GitHub direto | 06 §5 (gh, GraphQL `statusCheckRollup`, abrir PR, credenciais git); 03 §2.6 e §10.2/§10.3; AC-501 a 506, AC-115 | **Resolvido** na v1 para leitura de PR e checks e para criar PR. Diff, "Send failures" e comentar PR ficam em v1.1/later; comentar PR não tem registro (SEM #10) |
| 15 | Biblioteca integrada e fácil, com agents e skills | 06 §4; 03 §13 (Agents, Skills, Profiles; "New Session with Agent", "Enable in This Session"); J9 com AC-901 a 908; AC-904 "Loaded in this run" | **Parcial.** Na v1 a Biblioteca só lê e ativa; criar e editar ficam para v1.1 (decisão registrada em 01 §4.2). Falta a ação mais "fácil": inserir skill ou agente no prompt pela palette (SEM #1) |
| 16 | Abrir terminal direto no agente escolhido | P9; 03 §7 (Quick Launch com "Start Claude Code with <texto>" e ⇧↵ em split), §3.3 (duplo clique na tab row = agente padrão), §4.7, §2.6 (menu New Tab ▸ agente); ⌘⌥T; AC-313, AC-307, AC-309 | **Resolvido**, mas o atalho ⌘T contradiz entre 03 e 05/06 (§5) |

Resumo das queixas: 12 resolvidas, 3 resolvidas com contradição a corrigir (4, 10, 16) e 2 parciais (7 sem AC de "não transborda"; 15 sem inserir pela palette e com edição só na v1.1).

## 7. O que fazer, em ordem

1. Resolver as duas contradições Altas de §5 (⌘T e "Scratch" × "Sessions") em `00-decisions.md` e propagar para 03, 05 e 06.
2. Criar a checklist de fidelidade que AC-T26 cita e um AC de "sem clipping" para páginas e Settings (queixa 7).
3. Escrever a regra de salvamento do Settings (03-B22) e decidir a paleta "Insert skill/agent" (05 e3).
4. Unificar versão e níveis do orçamento Zyte, do MCP no Codex, do lote e do diff, e corrigir a memória do AC-406.
5. Incluir os 5 SEM de severidade Média (§3, itens 1–5) em 07 e 03 e registrar como later ou fora os 15 de severidade Baixa.
6. Uniformizar IDs de motion (`M:` → `M-`) e `accessibilityIdentifier` entre 03 e 04.
