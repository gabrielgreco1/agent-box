# Fatia 0 · F0-1, F0-4 e pacote de tokens do Orca (F0-3 parcial)

Data: 2026-10-17. Worktree: `/Users/gabriel/orca/workspaces/agent-box/otter`. Base: `docs/rebuild/spec/09-roadmap.md` §2.1 e §2.3.

Nenhum capítulo da spec foi editado. Nada foi commitado nem guardado em stash.

Arquivos desta entrega:
- `scripts/extract-orca-reference.sh` (implementado; cabeçalho de contrato preservado)
- `docs/rebuild/reference/orca-1.4.219/README.md`, `tokens/{colors,typography,spacing,radii,motion}.json`, `source/index.json`
- este relatório

Legenda: **OK** = conferido e bate · **FALHA** = viola o critério de F0-1 ou de F0-4 · **DECISÃO** = conflito entre capítulos que precisa do dono.

---

## 1. F0-1 · Errata (grep e script sobre `docs/rebuild/spec/*.md`)

| Verificação | Resultado | Situação |
|---|---|---|
| `M:[A-F][0-9]` | 0 códigos de motion. Único match: `04-motion.md:12`, nota histórica que descreve a forma antiga `M:C9`. | OK (nota histórica; dono decide se fica) |
| IDs antigos `A1…F6` / `E0…E4` fora da tabela de correspondência de 04 (linhas 10–62) | `04-motion.md:118`: `A1 (abrir o app)` na tabela de divergências (§2). ID de auditoria citado direto. | **FALHA** |
| | `04-motion.md:820–828` (§11.1) usa `A1…A9` como critérios de aceite de motion. Mesma forma textual dos IDs antigos. `09-roadmap.md:143` e `:236` citam "04 A1" e "04 A6". | **DECISÃO**: renomear o prefixo dos critérios (ex.: `MA1…MA9`) |
| | `06-terminals-and-agents.md:709`: `(F4)` sem prefixo `audit/`. | **FALHA** (ID de auditoria sem prefixo) |
| Nomes canônicos de 08 §0 (bundle, labels, sockets, `AGENTBOX_*`, spool, dirs, Keychain, subsystems, comandos `agentbox ctl`/`hook`) | Valores batem em todos os capítulos. Números também batem: hook 200 ms e 5 s; backpressure 2 MiB; ring 4 MiB; cold log 2×8 MiB; prompt 16 KiB; frame 1 MiB; coalescência 16 ms/64 KiB. | OK |
| Nomes presentes na spec mas ausentes de 08 §0 (sem conflito de valor) | `AGENTBOX_CAPACITY_ESTIMATES` (`07-computers-and-subagents.md:162`, env de teste). `~/Library/Application Support/AgentBox/boxes/<computerId>/` (`07:221`, `:752`). `…/AgentBox/previous/` (`08:812`). `/run/agentbox/pty.sock` (`07:675`, dentro do container). | **FALHA** (completar §0 ou marcar como fora da tabela). Não é divergência de valor |
| `AGENTBOX_HOOK_TOKEN` e `AGENTBOX_TERMINAL_ID` | Só aparecem negados (`06:505`, `08:47`). | OK |
| `AGENTBOX_PTYD_SOCK_V2`, `app.agentbox.ptyd.v2` | Major futuro (`06:239`, `08:832`). | OK |
| Atalhos: colisão **dentro** de 03 §21, escopo Overlay | `⌘↵` = Submit (Overlay) e New Session "<text>" (Overlay palette). `⇥` / `⇧⇥` = próximo/anterior campo (Overlay) e Cycle filter (Overlay palette). A palette é overlay, então o teste de colisão de 03 §21 falha. | **FALHA** |
| Atalhos: Viewer × Global | `07-computers-and-subagents.md:§11.6` manda **todo** atalho ao computador com o canvas focado, exceto ⌘Q, ⇧⌘R, ⌘⎋ e ⌃⌥. `03 §21` declara ⌘W, ⌘N, ⌘T, ⌘1…9, ⌘J e ⌘, como Global. `08 A16` lista "⌘W indo para a box" como risco. `05` (linha 370) só fala de ⌘⎋/⌃⌥ e diz que ⌘Q chega ao app. A regra "escopo mais específico vence" daria prioridade ao Viewer. | **DECISÃO**: definir quais Global valem com o Viewer focado; criar linhas de escopo Viewer para ⌘W, ⌘C e ⌘V (`07 CS-422` usa ⌘V no viewer, e §21 não lista) |
| Atalhos: notação | `06-terminals-and-agents.md:206`, `:208` e `:257` escrevem `⌘⇧D` e `⌘⇧↵`. 03 §0 manda a ordem `⌃ ⌥ ⇧ ⌘`, e §21 usa `⇧⌘D` e `⇧⌘↵`. Mesma ação. | **FALHA** (correção de texto em 06) |
| Atalhos: ações de 03 §24 com atalho fora de §21 | `Send Interrupt (⌃C)` (`03:503` e §24). Itens com gesto `⌥` (Refresh Git, Copy Project/Session ID, Show Launch Details, Rename Branch, Copy Terminal/Conversation/Pane ID, Show Hook Log). §21 não documenta o gesto ⌥ nem ⌃C como ação. | **FALHA** (§21 deve listar ou declarar a convenção) |
| Demais atalhos citados (01, 02, 04, 05, 06, 07, 09) | ⌘J, ⌘N, ⇧⌘N, ⌘T, ⌥⌘T, ⌥⌘N, ⌘W, ⌘D, ⇧⌘D, ⇧⌘R, ⇧⌘H, ⇧⌘I, ⇧⌘L, ⇧⌘G, ⇧⌘C, ⌘L, ⌃⇥, ⌃1, ⌘K, ⌘R, ⌥⌘R, ⌘1…9 batem com §21. | OK |
| `scratchpad` na spec | 7 linhas: `01-product.md:96`, `02-design-system.md:3`, `04-motion.md:6`, `08-architecture-quality.md:736`, `09-roadmap.md:61`, `:108` (checklist, é uma citação), `:470`. Todas proíbem o uso do scratchpad. | **DECISÃO**: se o critério é literal ("nenhuma citação"), as 7 saem |

Resumo F0-1: **os critérios de código de motion e de nomes canônicos passam**. Ficam pendentes as falhas de texto (04:118, 06:709, 06:206/208/257), as colisões de atalho em §21 (Overlay, Viewer) e as decisões acima.

---

## 2. F0-4 · Tabela de ações (03 §24) × controles da Fatia 1

**Estrutura.** §24 tem as colunas `Ação | ActionID | Efeito | Desabilitado (tooltip) | Versão`. F0-4 pede seis campos: ID, rótulo, atalho, efeito, desabilitado com motivo e teste. **Faltam as colunas atalho e teste.** O atalho fica só em §21, e o teste aparece só como regra no preâmbulo de §24. Isso precisa de decisão de formato antes de F0-4 fechar.

Os controles abaixo são de 09 §3 (tarefas T1-10…T1-27) e 01 §4.1 (Fatia 1). Não há linha em §24, salvo indicação.

**A. Composer ⌘N (03 §6): quase sem linhas.** Só existe `session.new` (abre o composer).
- Create Session (⌘↵), Cancel (Esc), Create More (switch).
- Where (`DSSegmented`: New Worktree, Existing Worktree, Main Checkout, New Folder, Choose Folder…).
- Create from (campo + chip "Branch exists" + "Reuse existing branch").
- Worktree (combobox), Folder `[Choose…]`, Agent (combobox, Set as Default, Manage Agents…), Profile (combobox), Advanced (disclosure), Session name, Branch name, Worktree location `[Change…]` (só `settings.pickPath` genérico).
- Overlay de "Discard this session?" (`[Keep Editing]`, `[Discard]`) e link `Reuse it`.

**B. Linha pendente e falhas de lançamento (03 §2.9, §4.6, §6.4).**
- `[Cancel]` da linha pendente (`sidebar.pending.cancel`).
- `[Use Existing Branch]`, `[Create Without Fetching]`, `[Discard]` (T1-18 cita os dois primeiros).
- `[Open Agent Settings]` do estado "Couldn't start" (T1-16 cita explicitamente).
- `[Cancel]` da ignição (`pane.<id>.ignition`) e `[Cancel]` do estado "Closing".

**C. Diálogos de confirmação (03 §16) com botões sem ID próprio.** As linhas de §24 só apontam para a seção (`§16.x`).
- 16.1 fechar terminal: `[Cancel]`, `[Close Terminal]`, `Don't ask again`, variante "Close 3 terminals?".
- 16.10 ⌘Q: `[Keep Running]`, `[Stop All and Quit…]`, segunda confirmação, `Don't ask again`.
- 16.2 `[Archive]`; 16.5 `[Delete Session]` e checkboxes "Move folder to Trash" / "Also delete run folders"; 16.6 `[Remove Project]`; 16.8 `[Move]` / `[Convert]`.

**D. Barra de busca do terminal (03 §4.4).** Faltam `find.caseSensitive` (`[Case Sensitive]`), `find.regex` (`[Regex]`), `find.field` e o contador `find.count`. Existem só `find.open/next/previous/close`.

**E. Tab row e panes (03 §3, §4).**
- `tabs.paneActions` (menu ⋯, com 2+ panes).
- `pane.<id>.zoomPill` ("N hidden panes").
- Reordenar tab por arrasto (M-303, §3.4).
- Arrastar o divisor e duplo clique para igualar (§4.3). Existe `pane.equalize`, mas só para o menu.

**F. Sidebar (03 §2).**
- Expandir e recolher projeto por clique na linha (`sidebar.project.<id>.toggle`, M-806).
- Campo Search (`sidebar.search`, §2.2). **DECISÃO**: entra na Fatia 1? 01 §4.1 e T1-13 não o citam.
- `+` da seção Sessions: mapeado a `session.newClean`, mas o botão não tem linha própria. Aceitável se o texto disser.

**G. Quick Launch (03 §7).**
- "Resume a Conversation…" abre o painel direito, que é **oculto** na Fatia 1 (T1-10). **DECISÃO**: o item some na Fatia 1?
- "Agent Settings…" e ⇧↵ (abrir em split).

**H. Command palette (03 §8).** Sem ActionID para abrir (`Jump To…`, ⌘J), para o filtro (Tab) e para `New Session "<text>"` (⌘↵). `Insert Skill or Agent…` tem linha, marcada Fatia 4 (ok).

**I. Settings mínimo (T1-26).** §24.6 cobre por **regra** (`settings.<section>.<key>`), não por linha. F0-4 pede linha por controle.

**J. Inconsistência de versão.** `view.toggleRightPanel` (⌘L) e `tabs.rightPanelToggle` estão marcados "v1" sem fatia, mas T1-10 manda o painel direito **oculto** na Fatia 1.

Confirmados com linha (amostra): janela e chrome, toggles de sidebar, sessões (`session.newClean`, `newCleanInFolder`, `rename`, `archive`, `delete`, `moveToProject`), projetos (`project.add`, `showMore`, `collapseAll`, `hide`, `remove`), tabs (`tab.quickLaunch`, `newAgent`, `newTerminal`, `newWithAgent`, `close`, `reopen`, `rename`, `resetTitle`, `closeOthers`, `closeRight`), panes (`splitRight/Down`, `next/previous`, `toggleExpand`, `close`), estados de terminal (`terminal.resume`, `restart`, `startFresh`, `forceQuit`, `sendInterrupt`), erro (`app.errorTryAgain`, `app.copyDetails`, `app.restartBackgroundService`, `app.openDiagnostics`), onboarding (`agent.detect`, `agent.installHelp`, `account.logIn`, `docker.start`, `notifications.request`, `app.allowLoginItem`, `onboarding.skip/done`), landing (§19) e menus do card de sessão (§2.6).

---

## 3. F0-3 · Pacote de tokens do Orca 1.4.219 (parcial)

**Script.** `scripts/extract-orca-reference.sh` implementado. Extrai `app.asar` com `npx --yes @electron/asar@4.3.1 extract` para um diretório temporário, calcula SHA-256 e lê só o CSS do renderer (nunca executa código do Orca). Aborta se a versão não for 1.4.219.

- Execução: exit 0.
- Reprodutível: duas execuções geram MD5 idênticos nos JSON.
- Diretório temporário removido ao final.

**Entrada.** `/Applications/Orca.app/Contents/Resources/app.asar`, 125 667 563 bytes, SHA-256 `579d814bca0d04448414d07ac9547ca06b1c84ff9d008c98951fb6a91a066218`. CSS usado: `out/renderer/assets/I18nProvider-b7VZ0bXG.css` (`:root,:host` dentro de `@layer theme`, `:root` e `.dark`).

**Saídas.**
- `tokens/colors.json`: 107 variáveis do tema escuro, 117 do claro, 85 da escala Tailwind v4.
- `tokens/typography.json`, `spacing.json` (base `.25rem` = 4 px), `radii.json` (`--radius` = 10 px), `motion.json`.
- `source/index.json`: índice com SHA-256. Os arquivos não são copiados. A licença do Orca é MIT, então copiar trechos seria permitido. **DECISÃO** do dono.
- `README.md`: versão, data, hash, ferramenta e instruções de recaptura.

**Pendente de F0-3** (não feito aqui): `screens/`, `crops/` e `manifest.json`. Exigem captura com Gravação de Tela. Não bloqueiam os tokens.

### 3.1 Divergências entre `docs/rebuild/spec/02-design-system.md` e os tokens do Orca

**Divergência 1 · paleta de estados usa Tailwind v3; o Orca 1.4.219 usa v4 (02 §2.6–2.9).**

| Linha 02 | Token da spec | Spec | Orca 1.4.219 (v4) |
|---|---|---|---|
| 124 | `locate` (blue-400) | `#60a5fa` | `#54a2ff` |
| 125 | `aiAccent` (violet-400) | `#a78bfa` | `#a685ff` |
| 137 | `needsInput` (orange-500) | `#f97316` | `#fe6e00` |
| 137 | (orange-300) | `#fdba74` | `#ffb96d` |
| 139 | `done` (emerald-500) | `#10b981` | `#00bb7f` |
| 140 | `failed` (red-500) | `#ef4444` | `#fb2c36` |
| 144 | `stalled` (amber-500) | `#f59e0b` | `#f99c00` |
| 211 | `prMerged` (purple-400) | `#c084fc` | `#c07eff` |
| 213 | `checksFailing` (rose-500) | `#f43f5e` | `#ff2357` |

Observação: `#ef4444`, `#f97316`, `#eab308` e `#10b981` existem em outros pontos do renderer (JS de cores de grupo e CSS). `#60a5fa`, `#c084fc`, `#f43f5e` e `#fdba74` não existem em lugar nenhum do renderer. Pelo princípio "É o Orca" (02 §1), é divergência. **DECISÃO** do dono: manter a paleta da spec ou adotar a v4 do Orca.

**Divergência 2 · raios (02 §6).**

| Token | Spec | Orca |
|---|---|---|
| `rSM` | 4 | `--radius-sm` = `calc(var(--radius) * .6)` = **6** |
| `rMD` | 6 | `--radius-md` = `calc(var(--radius) * .8)` = **8** |

`rXS` (2), `rCard` (10), `rLarge` (14 = `--radius-xl`) batem. `rControl` (8), `rMenu` (11) e `rTile` (18) aparecem nos raios usados, mas sem variável com esse nome.

**Divergência 3 · line-height da escala tipográfica (02 §4.2).** Cálculo: `line-height` do Orca = `calc(lh/size) × size` para os `text-*` do Tailwind.

| Token | Spec | Orca (`text-*`) |
|---|---|---|
| `composerTitle` | 16/600/**22** | `text-base` lh 24 |
| `paletteInput` | 16/400/**22** | `text-base` lh 24 |
| `dialogTitle` | 18/600/**24** | `text-lg` lh 28 |
| `pageTitle` | 24/600/**30** | `text-2xl` lh 32 (02 diz "Orca `text-2xl`") |
| `menuItem` | 12/450/**17** | `text-xs` lh 16 (conferir a classe real) |

Batem: `label` (12/16), `sectionLabel` (12/16), `control` (14/20), `input` (14/20), `dialogBody` (14/20). Tamanhos 9, 10, 11, 12, 13, 14, 16, 18 e 28 existem em `font-size` do Orca. O 24 só aparece via `var(--text-2xl)`.

**Divergência 4 · valores sem variável no CSS (não verificáveis só com tokens).**
- `overlayCard` = `rgba(23,23,23,0.96)`: 0 ocorrências no CSS. Pode estar em JS. Verificar.
- `menuMaterial` = `rgba(0,0,0,0.72)`: idem.
- `terminalBackground` = `#282c34`: existe no JS como preset "Ghostty Default Style Dark", e 02 diz "tema do dono". Confirmar.
- `scrim` = `black/55`: classe `.bg-black\/55` existe no CSS (`#0000008c`). OK.

**Divergência 5 · motion.** 02 §11 remete a 04, então não há valor de 02 para comparar em `motion.json`. Os atrasos de tooltip da DS1 (400/500/1000/200 ms) vêm de `App.tsx` (JS), não do CSS. 400 e 1000 não aparecem nas durações do CSS. 150 (menus e tooltip) e 200 (dialog) aparecem.

**Conferidos e batendo.**
- Superfícies de 02 §2.1: 9 de 9 com variável (`canvas`=`--background`, `chrome`=`--card`, `sidebar`=`--worktree-sidebar` #2a2a2a, `sidebarSelected`=`--worktree-sidebar-accent` #353535, `panel`=`--sidebar`, `panelSelected`=`--sidebar-accent`, `secondary`=`--muted`/`--secondary` #262626, `accent` #404040, `editor`=`--editor-surface` #1e1e1e).
- Texto: `textPrimary` #fafafa, `textSecondary` #a1a1a1, `textOnPrimary` #171717.
- Bordas: `border` = `#ffffff12` (≈ white/7); `input` = `#ffffff26` (≈ white/15); `ring` #737373; `paneDivider` #3f3f46 (zinc-700); `destructive` #ff6568.
- Escala de espaçamento (02 §5.1): `s0_5`…`s10` (10 de 10) batem com `--spacing` = 4 px.
- Família: `Geist` em `@font-face` (weight 100–900, compatível com DS11); `--font-mono` começa com "SF Mono".

---

## 4. Decisões pendentes do dono (resumo)

1. Paleta de estados da 02 §2.6–2.9: v3 (spec atual) ou v4 (Orca). Afeta 9 linhas.
2. Raios `rSM` e `rMD` da 02 §6 (4 e 6 contra 6 e 8 no Orca).
3. Line-heights de 02 §4.2 (5 tokens).
4. Atalhos com viewer focado: quais Global valem (⌘W, ⌘N, ⌘T, ⌘1…9) e linhas de escopo Viewer (⌘C, ⌘V).
5. Colisões em §21 (escopo Overlay/palette: `⌘↵` e `⇥`).
6. Formato de §24: incluir colunas atalho e teste (F0-4).
7. IDs `A1…A9` dos critérios de motion (04 §11.1) e `(F4)` em 06:709.
8. "scratchpad": 7 negações. Sair da spec ou manter?
9. Search da sidebar e painel direito (⌘L) na Fatia 1 ou não.
10. `source/`: copiar trechos (MIT) ou manter só o índice.
11. Completar 08 §0 com `AGENTBOX_CAPACITY_ESTIMATES`, diretórios `boxes/` e `previous/`.

---

## 5. Como reproduzir

```
scripts/extract-orca-reference.sh          # usa /Applications/Orca.app
scripts/extract-orca-reference.sh --asar <caminho>
```

Cada execução sobrescreve `docs/rebuild/reference/orca-1.4.219/tokens/*.json`, `source/index.json` e `README.md`. Com o mesmo `app.asar`, o resultado é idêntico.
