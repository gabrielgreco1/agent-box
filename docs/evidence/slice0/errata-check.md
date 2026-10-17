# Fatia 0 · Verificação da errata (F0-1 e F0-4)

Data: 2026-10-17. Base: `docs/evidence/slice0/F0-1-F0-4-report.md`. Capítulos editados: 02, 03, 04, 06, 07 e 09 (marcação de F0-1, F0-4, S-05, S-06 e S-08). Decisões aplicadas: P17 (tokens reais do Orca), P18 (Codex com trust inline e `--no-daemon`), P19.

## Verificações repetidas (sobre `docs/rebuild/spec/*.md`)

| Verificação | Comando ou método | Resultado |
|---|---|---|
| Códigos de motion antigos | `grep -n "M:[A-F][0-9]" *.md` | **0 ocorrências.** A nota histórica de `04-motion.md:12` foi reescrita sem a forma antiga |
| IDs de auditoria fora da tabela de correspondência de 04 | grep de `A1…F6`/`E0…E4` em 04 fora das linhas 10–62 | **0.** `04:118` agora diz "Abrir o app (M-001)" |
| Critérios de aceite de motion `A1…A13` | renomeados `MA1…MA13` em 04 §11.1; citações atualizadas em 04 (§11.2, §12) e em `09-roadmap.md` (`04 MA1`, `04 MA6`) | **0 linhas `\| A<n> \|` fora da tabela histórica** |
| Códigos de auditoria sem prefixo `audit/NN` | `06:709` `(F4)` e `06:390` `(E9)` | Corrigidos para `(`audit/01` F4)` e `(`audit/01` E9)`. Nenhuma outra forma `(X<n>)` de auditoria nos capítulos 02–07 e 09 (as restantes são P/T de decisões e R/J/Q/S de revisões e perguntas) |
| Notação de atalho fora da ordem `⌃ ⌥ ⇧ ⌘` | `grep -c "⌘⇧"` em todos os capítulos | **0** (06 e 04 corrigidos: `⇧⌘D`, `⇧⌘↵`, `⇧⌘E`) |
| Atalhos duplicados em 03 §21 | script sobre a tabela (64 linhas), agrupando por (tecla, escopo) | **0 colisões no mesmo escopo.** Teclas em escopos distintos, todas com regra declarada: `⌘↵` e `⇥` (Overlay × **Palette**, escopo novo que substitui Overlay), `⌘W` e `⇧⌘R` (Global × Viewer, regra em 03 §11.6), `⌘C` e `⌘V` (Terminal × Viewer), `Esc` (App/Find/Overlay, mais específico vence), `⇧↵` (Find × Palette), `⇧⌘⌫` (App/Sidebar) |
| Atalhos de 03 §24 existentes em §21 | cruzamento da coluna Atalho com §21 | **Todos presentes** (206 linhas na tabela; `⌘1…⌘9` está em §21 como `⌘1 … ⌘9`) |
| Estrutura de 03 §24 | 7 colunas em todas as 206 linhas (`Ação, ActionID, Atalho, Efeito, Desabilitado, Versão, Teste`) | OK |
| ActionID duplicado em §24 | script | **0** (`composer.manageAgents` e `composer.editProfiles` chamam `agent.openSettings` e `library.profiles` sem repetir o ID) |
| Hex da paleta v3 em 02 e 03 | grep dos 10 valores antigos | **0** em todos os capítulos; substituídos pelos valores de `tokens/colors.json` |
| p10k / oh-my-zsh como premissa | grep | Removida de 06 §1.7 e de 09 S-06. Restam duas menções negativas em 06 ("sem p10k nem oh-my-zsh") e uma em `08-architecture-quality.md:879` (fora do escopo desta passada) |

## Correções de F0-1 aplicadas

- A1 em 04 (linha 118) e `A1…A9` de 04 §11.1: ver acima.
- `(F4)` sem prefixo em 06: corrigido (e `(E9)`).
- Colisões de §21 no escopo da palette: escopo **Palette** criado e regra de substituição escrita no texto de §21; teste do `KeyBindingRegistry` ajustado.
- Conflito Viewer × Global: 03 §11.6 reescrito (reservados: ⌘Q, ⌘W, ⇧⌘R, ⌘⎋, ⌃⌥, ⌘H, ⌘M, ⌃⌘F; demais Global vão ao computador) e linhas Viewer novas em §21 para ⌘W, ⌘C e ⌘V; 07 CS-421 alinhado. Observação: o relatório cita "07 §11.6"; a seção é 03 §11.6 (07 só a referencia).
- ⌃C e a convenção ⌥ de menus agora têm linhas em §21 (escopos Terminal e Menu).
- `⌘⇧D` / `⌘⇧↵` em 06: corrigidos.

## F0-4

03 §24 ganhou as colunas Atalho e Teste (`testAction_<ActionID>`) e linhas para: composer inteiro (§24.8), linha pendente e falhas de criação (`session.cancelLaunch`, `retryLaunch`, `useExistingBranch`, `createWithoutFetch`, `discardPending`), `[Open Agent Settings]` (`agent.openSettings`), estados do pane (`terminal.retryStart`, `copyStartError`, `cancelClose`), diálogos de §16 (§24.9), toggles da busca (`find.caseSensitive`, `find.regex`, `find.query`), menu ⋯ (`tabs.paneActions`), reordenar tab, divisor do split, palette e Quick Launch (§24.7). ⌘L e `Resume a Conversation…` ficam na Fatia 2 (painel direito oculto na Fatia 1); `sidebar.search` também (não está em 01 §4.1 nem em T1-13).

## Pendências que esta passada não resolve

- Settings (T1-26) segue coberto por regra (`settings.<section>.<key>`), não por linha por controle.
- `scratchpad`: 7 negações na spec (e o próprio item do checklist de 09 §2.6). Decisão de política não tomada.
- 08 §0: faltam `AGENTBOX_CAPACITY_ESTIMATES`, `boxes/` e `previous/`; 08 S-06 (linha 879) ainda cita p10k. 01 não foi tocado (fora do escopo).
- `success` (`#86efac`), `overlayCard`, `menuMaterial`, `terminalBackground` sem variável no CSS extraído (conferir no JS do Orca em F0-3). F0-3 segue parcial (screens/crops/manifest).
- Hooks do Codex: payloads de `PreToolUse`/`PostToolUse`/`Stop` dependem de reexecutar o spike S-05 depois de 22/10/2026.
