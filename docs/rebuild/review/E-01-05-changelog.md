# E-01-05 · Changelog da edição de 01 e 05 após R1–R3

Data: 2026-10-16. Arquivos editados: `spec/01-product.md` e `spec/05-journeys-and-acceptance.md`, os dois com a marca "Revisado após R1–R3 em 2026-10-16" no topo. Base: `00-decisions.md` (P11–P16), `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`. Os outros capítulos não foram tocados.

## O que mudou

### Decisões novas do 00
- **P11.** A seção da sidebar é "Sessions" e a ação é "New Clean Session" (⇧⌘N) nos dois arquivos. A variante "New Clean Session in Folder…", que não existe em 03, virou o caminho do composer: sem projeto e com "Choose Folder…" em "Where" (J11, AC-1105).
- **P12.** Exceção ao PP-2: o pai pode mandar `agent_message` com Enter, mas só a filhos que ele criou, e o envio fica na timeline (v1.1). Entrou em 01 §3 e §5.9, na J4b, em AC-505 (a origem da escrita agora inclui `parentMessage`) e no novo AC-464.
- **P13.** Todo teto de orçamento saiu: `budgetUSD`, `budgetExhausted`, o tipo de ajuda `budget`, "Add $1.00", os avisos de 80% e o orçamento hierárquico. Entrou a entidade **ProxyProfile** (01 §5.15; "Proxy" na UI, mesmo nome de 07), com tipo HTTP/HTTPS/SOCKS5/providerApi, credencial, geo e capabilities, Zyte como preset e resolução computador → sessão → padrão global. Os ACs foram reescritos: AC-417 (credencial do proxy fora do alcance do agente), AC-418 (proxy por sessão e por computador, uso só quando o provedor informa), AC-1004 ("Usage unavailable" quando o provedor não informa uso) e AC-118 (importação do `.env` para o Vault, com preset Zyte opcional). AC-1005 foi removido e o ID fica reservado. O teto foi para 01 §4.4 como "Fora (P13)".
- **P14.** Aprovação visual por tela entrou em PP-12, nas regras de 01 §4 e em §0.4 item 4. AC-T26 foi reescrito: lado a lado com a fixture `F-REF` (pacote de referência do Orca 1.4.219), diff de `compare-ui.sh`, checklist da auditoria 04 §8 e OK do dono por tarefa, sem aprovação em lote.
- **P15.** 01 §8 virou "Padrões adotados pelo dono". O item 4 passou a ser o modo accessory sem helper (R1 D-03). O item 5 é o overlay do ⌘Q com "Keep Running" (D-12). O item 7 foi reescrito por P13.
- **P16.** As recomendações dos revisores foram aplicadas como estão listadas abaixo.

### R1 (conflitos e referências)
- **Números.** Eco p95 ≤ 33 ms (AC-608, AC-T07). CPU em repouso ≤ 1 % no app e ≤ 0,5 % no daemon (AC-609). Viewer ≥ 20 fps (01 §4, AC-408, J4). Bloqueio MCP de até 50 s (AC-409). Prompt por arquivo acima de 16 KiB ou quando começa com `-` (01 §5.7; AC-308 testa a fronteira). VM de 28 GiB em AC-406. "Stalled?" com 10 min.
- **Nomes.** Inbox no lugar de sino/Bell. "Next Needing Attention". "Take Over" e "Hand Back" (D-02). As opções "Where" e os campos Agent/Profile do composer como em 03. "Move to Project…" com "New Project from This Folder", e "Move Folder into Project…" na v1.1 (AC-1107 passou a v1.1). Nota de status na linha 3. "Resume Agents…" com o overlay "Resume interrupted agents?". Rótulos de Conversations. Microcopy do onboarding ("Set Up Agent Box", "Logged in", "Log In", "Skip for Now", "Login can't be verified", "≈ 6 headless…"). Skill concorrente com "Block in Agent Box", "Disable Globally…" e "Keep", e "Restore Skill" em Settings › Agents. "Docker isn't running". "Try Again", "Create Without Fetching", "Copy Details", "Reveal Corrupt File", "Export Diagnostics…". Título de notificação com "—". Settings › Credentials e Settings › Advanced › Automation channel. Fila "Waiting for memory · 3 of 15 queued". Aba "Computers" do painel direito no lugar da faixa. Abas do detalhe do filho como em 07 CS-320. "On This Mac" e "In Container". Library como página com Profiles. Diff na aba Source Control. "Interrupted" no lugar de "Interrupted by restart". "Keyboard captured · ⌃⌥ to release". Porcentagem sem espaço.
- **Estados canônicos** (K-78 a K-80) em 01 §6. Atividade com `blocked`. `idle` também para o agente recém-iniciado sem prompt. `unknown` absorve `stale`. `estimated` é uma marca, não um estado. Nova agregação. `failedToStart` entrou no processo e `reattached` deixou de ser estado. Pedido de ajuda com `mfa`, `declined` e `expired`. A pill "Idle" representa o controle `none`. Os containers são `runtime`, `work` (agora `agent` no isolado) e `egress`. Run folder com `work/`, `logs/`, `transcript/` e `box.json`. Segredos no Vault (D-10). Isolado em container irmão na mesma box (D-08). Worker leve e `agent_message` na v1.1 (D-07). "Redirect" ficou fora (D-11).
- **Ferramentas MCP** com os nomes de 07: `box_claim`, `help_request`, `help_wait`, `exec`, `http_request`, `browser_type`, `already_claimed` e `boxes_reserve(names:, display:)`. `agent_result` saiu (o resultado vem em `agent_wait` e `box_collect`).
- **Atalhos de 03 §21.** ⌥⌘N abre o Quick Launch e ⌘T abre shell (J3 passo 11, AC-313). ⇧⌘A, ⇧⌘L, ⇧⌘G, ⇧⌘R e ⇧⌘T na notação de 03. "Sessão anterior" é ⌥⌘← no lugar de ⌃Tab (J6, AC-605).
- **IDs.** Motion como `M-xxx` (M-309, M-503/504/506, M-601/602/604/612, M-501, M-204). `accessibilityIdentifier` pela convenção de 02 §17 e 03 §22 (AC-T01). Comandos `ctl` da tabela de 08 (AC-T03). `app.agentbox.ptyd.v1` (AC-811). `agentbox.owner=<installId>` (AC-423).
- **Referências quebradas.** X-14 (§0.3 → §0.4), X-15 (AC-T26), X-16 e X-17. X-21: toda referência à auditoria leva o prefixo `audit/NN`, aplicado por script nos cabeçalhos dos ACs e nas tabelas, com revisão manual dos falsos positivos. A regra ficou escrita no topo dos dois arquivos. A coluna "P" da matriz virou "Prio." para não colidir com P2.
- **F-ORCA** passa a usar `profile-state.db` com `orca-data.json` como fallback (K-96). As contagens do Orca real (7 repositórios e 111 worktrees) foram atualizadas em 01 §2.

### R2 (lacunas)
- AC-T27, para a queixa 7: nada sai da caixa em 760×480 e em 1440×900, com a fixture nova `F-LONG`.
- AC-T26 com o lado a lado do Orca por tela (P14).
- AC-429 e AttentionItem `batchDone` com resumo: a notificação de lote concluído entra na **v1**, junto com o lote.
- Regras do worker: o novo PP-15 em 01 e o AC-428, que testa o texto injetado e o comportamento em `F-SITE`.
- "Custom Command" virou um provider em 01 §5.6, no lugar de "Outro CLI fica para depois".
- A ação "Insert skill/agent" da palette entrou na v1.1 (01 §4.2).
- Os itens SEM de severidade Baixa cuja casa é 01 foram registrados como `later` ou `out` em 01 §4.3/§4.4: comentar em PR, templates, arrastar pane, split por arrasto, Settings por projeto, sparse checkout, URLs de GitLab/Jira/Linear, memória do Claude, renomear conversa, promover run, fixar ou colorir tab, terminal flutuante, kanban e gravação/replay do computador. Automations saiu de `later` (é `out`, T14).

### R3 (implementabilidade)
- **Fatia 0** de fechamento criada, e Fatia 1 redefinida conforme R3 §10. Conversations, importação do Orca e onboarding completo foram para a Fatia 2. O momento 3 de motion foi para a Fatia 3. O daemon nasce filho do app, o card mostra `unknown` sem hooks e o `ctl` mínimo existe desde o início.
- Regra de feature flag: controle de fatia futura não é renderizado (PP-1, AC-T28).
- AC-307 deixou de exigir um argv "exato" e passou a comparar com um golden file por fatia (perfil, `--session-id`, injeções de 06 §2.8 e prompt por último).
- AC-406 (memória da VM) e AC-109 ("Not started" virou o estado vazio de 03 §4.7) foram reescritos.
- AC-T02 ficou mais rígido: lint do registro, XCUITest com clique real por `ActionID`, efeito declarado e teste anti-conflito de atalho.
- AC-T08 ganhou um teste de unidade da tabela tecla → bytes. AC-T16 ganhou a correção de falsos positivos do lint. AC-312 segue a ordem de captura de 06 §1.7.
- AC-112 trata o risco do trust dos hooks do Codex: o Codex fica marcado `estimated`, e o app nunca grava trust.

### Verificação
Um script (`scratchpad/ed/check.py`) confere 01 e 05. Ele encontrou 185 ACs definidos, nenhum duplicado e nenhum AC citado que não exista (expandindo listas e intervalos da matriz). Todo AC definido aparece na matriz, exceto o exemplo de formato `AC-000`. AC-1005 aparece como removido.

### Coordenação com o editor de 07 (depois de R1–R3)
- O lote (`Batch`) é **v1**, como 07 especifica (CS-323/324). Isso substitui a recomendação R1 D-06 (v1.1). Em 01, o lote saiu de §4.2 e entrou na Fatia 3, e `batchDone` e §5.14 passaram a v1. Em 05, AC-429 e as linhas `audit/08 N7`/`N21` da matriz passaram a v1.
- A entidade de proxy se chama `ProxyProfile` (campos `proxyProfileId`), alinhada com 07.
- Os verbos "Take Over" e "Hand Back" e a remoção total do teto (P13) já estavam aplicados.

## O que NÃO apliquei, e por quê
- **R1 D-01 ("Scratch").** P11 decidiu "Sessions" e "New Clean Session".
- **R1 K-42, D-04 e K-89o (texto e níveis do orçamento).** Ficaram sem efeito com P13.
- **Patches de R1 e R3 para 02, 03, 04, 06, 07 e 08**, inclusive a checklist de fidelidade que deveria ser copiada para 03, a tabela de ações e o lint de UI. Estão fora do meu escopo. Os ACs de 05 já citam esses artefatos, e os editores dos outros capítulos precisam criá-los:
  - `scripts/compare-ui.sh`;
  - `docs/rebuild/reference/orca-1.4.219/`;
  - a tabela tecla → bytes em 06;
  - o código `not_your_child` em 07;
  - a origem de escrita `parentMessage` no protocolo de 06/08.
- **Nomes de UI do proxy em Settings.** 03 ainda não tem a seção, porque é outro editor que cuida dela. Em 05 usei "Settings" de forma genérica, "Import .env File…" (que já existe em 03), "Usage unavailable" e "Network". Se 03 escolher outros rótulos, os ACs 118, 418 e 1004 precisam acompanhar.
- **Filtros da sidebar (R2.6).** 03 §2.4 já desenha o menu Filter, mas 01 mantém o recurso como `later`. Nenhum revisor recomendou um lado, então isso fica para o dono ou para o editor de 03.
- **"Insert skill/agent" na v1.1.** R2 só pediu "decidir". Coloquei na v1.1 por causa da queixa 15 e porque não conflita com T11. É uma escolha de escopo que o dono pode reverter.
- **Spikes e Fatia 0.** Foram registrados como escopo em 01 §4.1, sem detalhar os critérios de saída, que vivem em R3 §6 e devem ir para 06/08.
- **"Ask Parent to Steer…" (AC-427).** Só passou a Title Case; o rótulo não existe em 03.
