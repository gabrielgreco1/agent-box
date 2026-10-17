# R1 · Revisão de consistência entre capítulos da spec

Data: 2026-10-16. Escopo: `docs/rebuild/spec/00..08`. Nada da spec foi editado; este documento só aponta conflitos e propõe patches.

Critério de desempate usado, nesta ordem:
1. `00-decisions.md`.
2. O capítulo dono do assunto: 01 (escopo, modelo e estados de domínio, glossário), 02 (tokens visuais e acessibilidade), 03 (telas, microcopy e atalhos), 04 (durações, curvas, IDs de motion), 05 (critérios de aceite, que seguem os outros), 06 (terminais, lançamento, Git), 07 (ferramentas MCP e computadores), 08 (mecânica, identificadores técnicos, schema, metas de desempenho).
3. O código do Orca (`scratchpad/orca-src`) quando a questão é "como o Orca faz".
4. Maioria entre capítulos e bom senso.

Formato das referências: `arquivo:linha`. Em "Patch", **de** → **para** é o texto exato a substituir. Quando o mesmo termo aparece em muitas linhas, o patch é uma substituição global com a lista de linhas.

Contagem: itens K-01 a K-100 com conflitos que a regra acima resolve (§1–§8 e §10; K-89 tem 17 subitens de versão), o mapeamento completo de IDs de motion (§4), 21 referências cruzadas quebradas ou ambíguas (§9) e 11 decisões que só o dono pode tomar (§11).

---

## 0. Cânone proposto (resumo)

| Assunto | Fica | Sai |
|---|---|---|
| Latência de input | 08 AR-702: p95 ≤ 16 ms em repouso, ≤ 33 ms com 4 panes despejando saída | 50 ms de 05 |
| Opacidade de pane inativo | 0,8 (DS4) | 0,9 de 06 |
| Tooltip (animação) | 150 ms entrada, 100 ms saída (04 M-106) | 120 ms de 02 |
| Anel de foco | 3 pt (DS9) | 2 pt de 04 |
| Blur do scrim | Desligado na v1 (04 R8) | "blur 2 pt" de 02 |
| Estado "precisa de resposta" do agente | Label `Needs input` (01, 04, 05, 06, Orca `en.json`) | `Needs you` como label de estado (02). "Needs you" fica para atenção agregada (grupos, contadores, pedidos de computador) |
| Estado sem observação | `unknown` → `Status unavailable` | `State unknown` (04), `stale`/`No recent update` (02) |
| Atalhos | Tabela 03 §21 (bate com o Orca: ⌘T = terminal, ⌥⌘T = agente, ⌥⌘←/→ = histórico) | ⌘T como lançador (05, 06), ⌘⌥setas para panes (02, 04, 06), ⌘⇧T no viewer (04), ⌘⇧E (04) |
| Ferramentas MCP | Nomes de 07 §3.2 e §4.2 (`boxes_reserve`, `box_claim`, `help_request`, `help_wait`, `exec`, `http_request`, `browser_type`, `agent_wait`) | `computer_acquire`, `computer_request_help`, `computer_wait_help`, `computer_exec`, `computer_http_request`, `browser_fill`, `agent_result`, `already_claimed_by` |
| Onde vivem MCP e Docker | No app (`AgentBoxCore`), que fica em `.accessory` após ⌘Q (06 §0, 08 AR-101/AR-106/AR-108) | No `agentboxd` (07 §3.1 e vários CS) |
| Papéis de container | `runtime`, `work` (v1, `exec`), `egress` (sidecar; nome de T9), `agent` (v1.1, substitui `work`) | `gate` (07), `work` = CLI isolado (08) |
| Tipo de computador | `http` / `headless` / `desktop` (01, 03, 08) | `none` / `browser` / `desktop` (07) |
| Identificadores técnicos | 08 (`app.agentbox.mac`, `app.agentbox.ptyd.v1`, `run/ptyd-v1.sock`, `AGENTBOX_PANE_ID`…) | Os de 06 e 07 |
| Leitura do Orca | SQLite `profile-state.db` por cópia, JSON como fallback (06 §6.1, conferido na máquina) | `orca-data.json` como fonte principal (08 AR-342, 05 F-ORCA) |
| Segredos | Vault: chave mestra num único item do Keychain, valores cifrados no SQLite (08 AR-510/511) | "valores no Keychain" (01), item de Keychain por token (07) — ver §11 D-10 |
| Accessibility IDs | Convenção de 02 §17 e lista de 03 §22 | IDs de 04 (`sidebar.sessionRow…`), 05 AC-T01 e 08 AR-805 |
| Escopo v1/v1.1 | 01 §4 | Itens que 03, 06 e 07 puxaram para a v1 (ver §6) |

---

## 1. Valores numéricos divergentes

**K-01 · Latência de input.** `05:532` (AC-608) e `05:796` (AC-T07) dizem eco p95 ≤ 50 ms. `08:530` (AR-702) diz p95 ≤ 16 ms em repouso e ≤ 33 ms com 4 panes despejando saída.
Prevalece 08: é o capítulo de desempenho, e o próprio AC-608 diz "08 pode recalibrar". Os dois cenários de 05 são de carga, então valem 33 ms.
Patch:
- `05:532` **de** `o eco de tecla no pane focado tem p95 ≤ 50 ms` **para** `o eco de tecla no pane focado tem p95 ≤ 33 ms (AR-702)`
- `05:796` **de** `o eco tem p95 ≤ 50 ms` **para** `o eco tem p95 ≤ 33 ms (AR-702)`

**K-02 · CPU em repouso.** `05:535` (AC-609): app abaixo de 2 %. `08:547` (AR-705): app ≤ 1 % e daemon ≤ 0,5 %. Prevalece 08.
Patch `05:535` **de** `o app fica abaixo de 2 % de CPU na média de 60 s` **para** `o app fica em ≤ 1 % e o daemon em ≤ 0,5 % de um núcleo na média de 60 s (AR-705)`.

**K-03 · Opacidade de pane inativo.** `06:186`: 0.9 (cita a auditoria 04). `02:24` (DS4), `02:258`, `03:411` e `04:55`: 0,8, conferido na config do dono. Prevalece 0,8.
Patch `06:186` **de** `Pane inativo com opacidade 0.9 (04 §2.3).` **para** `Pane inativo com opacidade 0,8 (DS4 de 02).`

**K-04 · Animação do tooltip.** `02:519` e `02:690`: 120 ms. `04:49` e `04:325` (M-106): 150 ms de entrada (`fast`) e 100 ms de saída. Prevalece 04, porque 02 §11 diz que durações vivem em 04.
Patch:
- `02:519` **de** `| Tooltip | fade + 0,95, 120 ms, atraso DS1 |` **para** `| Tooltip | M-106 (fade + 0,95, 150 ms; saída 100 ms), atraso DS1 |`
- `02:690` **de** `- Animação: fade + zoom 0,95 + slide 8 pt do lado, 120 ms.` **para** `- Animação: M-106 (fade + zoom 0,95 + slide 8 pt do lado, 150 ms; saída 100 ms).`

**K-05 · Blur do scrim.** `02:22` (DS2), `02:70`, `02:405` e `02:711`: `black/55` + blur 2 pt. `04:44` e `04:271` (R8): blur desligado na v1 por custo sobre o terminal Metal; liga só com prova do Instruments. Prevalece 04, que tem regra de desempenho mensurável.
Patch:
- `02:22` **de** `Scrim **\`black/55\` + blur 2 pt**` **para** `Scrim **\`black/55\`** (blur 2 pt desligado na v1; só liga se o Instruments aprovar, 04 §2 e R8)`
- `02:70`, `02:405` e `02:711`: trocar `black/55 + blur 2 pt` / `black/55\` + blur 2` por `black/55` (sem blur na v1, 04 R8)`.

**K-06 · Anel de foco.** `02:29` (DS9) e `02:790`: 3 pt, conferido no Orca (`button.tsx:8`). `04:289` ("anel de 2 pt"), `04:442` (M-803) e o token `stroke.ring = 2` (`04:147`, `04:200`), que também é o traço do spinner. Prevalece 02 para o foco; o token de 2 pt continua valendo para o spinner.
Patch:
- `04:289` **de** `foco visível (anel de 2 pt)` **para** `foco visível (anel de 3 pt, DS9)`
- `04:442` **de** `Anel 2 pt aparece com fade` **para** `Anel 3 pt (DS9, token \`stroke.focusRing\`) aparece com fade`
- `04:200` **de** `"stroke": { "ring": 2.0, "liveBorder": 1.5, "rim": 1.5 }` **para** `"stroke": { "ring": 2.0, "focusRing": 3.0, "liveBorder": 1.5, "rim": 1.5 }`, e a linha `04:147` ganha `focusRing` = 3.

**K-07 · Spinner genérico.** `02:766`: "rotação contínua 0,9 s (CA)". `04:450` (M-811): o mesmo anel do M-401 (1 volta/s em 12 passos, fase global). `04:14` exige "um spinner único". Prevalece 04.
Patch `02:766` **de** `rotação contínua 0,9 s (CA)` **para** `mesmo loop do spinner de agente (1 volta/s em 12 passos, fase global; 04 M-811)`.

**K-08 · Hover da tab.** `02:612`: "hover texto `textPrimary` (100 ms)". `04:90`: token `hover` = 0,12. Prevalece 04.
Patch `02:612` **de** `(100 ms)` **para** `(token \`hover\`, 120 ms)`.

**K-09 · Miniaturas de computador.** `02:784` e `03:715`: até 2 fps. `07:32`, `07:155` (CS-133) e `07:541` (CS-403): até 1 fps, via API do runtime. Prevalece 07 (dono do contrato do runtime; PP-14 "barato por padrão").
Patch: `02:784` **de** `Atualiza no máx. 2 fps quando visível` **para** `Atualiza no máx. 1 fps quando visível (CS-403)`; `03:715` **de** `frame vivo (≤ 2 fps)` **para** `frame vivo (≤ 1 fps, CS-403)`.

**K-10 · Viewer ao vivo.** `01:110`, `05:296` e `05:338` (AC-408): 15–30 fps. `07:539` (CS-401), `07:583` e `07:761`: ≥ 20 fps com p95 de input < 100 ms. Prevalece 07, que tem meta mensurável e spike (S3).
Patch: `01:110` **de** `- Viewer noVNC a 15–30 fps` **para** `- Viewer noVNC a ≥ 20 fps (CS-401)`; `05:296` **de** `a 15–30 fps` **para** `a ≥ 20 fps`; em `05:338`, **de** `mantém entre 15 e 30 fps medidos` **para** `mantém pelo menos 20 fps medidos (CS-401)`.

**K-11 · Bloqueio máximo de ferramenta MCP.** `05:341` (AC-409): 30 s. `07:247`: nenhuma ferramenta passa de 50 s; `help_wait`, `box_claim` e `agent_wait` fazem long-poll de 45–50 s. Prevalece 07.
Patch `05:341` **de** `nenhuma chamada MCP fica bloqueada além de 30 s` **para** `nenhuma chamada MCP fica bloqueada além de 50 s (07 §3.1)`.

**K-12 · Limiar do prompt por arquivo.** `01:279`: acima de 16 KB. `06:340` e `06:409` (TA-206): acima de 64 KiB. `05:248` (AC-308) testa 40 KB indo para arquivo, o que só bate com 16 KB. Prevalece 01, que também deixa folga para o `ARG_MAX` somado ao env.
Patch: `06:340` **de** `Prompt com mais de 64 KiB` **para** `Prompt com mais de 16 KiB`; `06:409` **de** `fallback por arquivo para > 64 KiB` **para** `fallback por arquivo para > 16 KiB`.

**K-13 · Backpressure do daemon.** `06:113`: fila por cliente de 4 MiB. `08:73` (AR-102): 2 MiB. Prevalece 08, que fixa a mecânica (`08:5`).
Patch `06:113` **de** `fila por cliente limitada a 4 MiB` **para** `fila por cliente limitada a 2 MiB (AR-102)`.

**K-14 · Rotação do cold log.** `06:136`: 2 × 8 MiB. `08:79` e `08:278`: "rotativo 8 MiB". Os dois são compatíveis se 08 explicitar o número de arquivos.
Patch `08:79` **de** `log bruto rotativo \`sessions/<id>/output.log\` (8 MiB)` **para** `log bruto rotativo \`sessions/<id>/output.log\` (2 × 8 MiB, 06 §1.5)`.

**K-15 · Retenção de eventos de hook.** `06:452` e `06:516` (TA-313): 30 dias ou 50 mil linhas por terminal. `08:302`: 30 dias e 10 mil por execução. Prevalece 08 (schema).
Patch `06:452` **de** `retenção de 30 dias ou 50 mil linhas por terminal` **para** `retenção de 30 dias e 10 mil eventos por execução (AR-311)`; ajustar TA-313 igual.

**K-16 · Debounce de persistência.** `06:191`: 500 ms. `02:776`, `03:1262`, `08:318` (AR-312) e `08:559` (AR-711): 300 ms. Prevalece 300 ms.
Patch `06:191` **de** `gravados com debounce de 500 ms e no fim do gesto` **para** `gravados com debounce de 300 ms e no fim do gesto (AR-711)`.

**K-17 · Tamanho mínimo de pane.** `03:438`: 240 × 120 pt, toast `Not enough room to split. Close a pane or widen the window.`. `06:185`: 20 colunas × 5 linhas, toast `Not enough room to split`. Prevalece 03 (UI); o limite em pt é o que a tela consegue medir antes do PTY existir.
Patch `06:185` **de** `um pane não fica menor que 20 colunas × 5 linhas; abaixo disso o split é recusado com toast "Not enough room to split"` **para** `um pane não fica menor que 240 × 120 pt (03 §4.3); abaixo disso o split é recusado com o toast "Not enough room to split. Close a pane or widen the window."`

**K-18 · Hook: timeout, orçamento e caminhos.** `06:448`: timeout 300 ms, spool `AB/run/hook-spool/<terminalID>.jsonl`, < 50 ms. `08:94` (AR-109): 200 ms, `run/spool/hooks/<runID>.jsonl`; `08:551` (AR-707): p95 ≤ 30 ms. Prevalece 08.
Patch em `06:448`: **de** `envia um frame para \`AB/run/app.sock\` com timeout de 300 ms` **para** `envia um frame para \`AB/run/app.sock\` com timeout de 200 ms`; **de** `\`AB/run/hook-spool/<terminalID>.jsonl\`` **para** `\`AB/run/spool/hooks/<runID>.jsonl\``; **de** `Escreve \`{}\` no stdout e sai com 0 em < 50 ms típicos.` **para** `Escreve \`{}\` no stdout e sai com 0, p95 ≤ 30 ms (AR-707).`

**K-19 · Captura do env do shell de login.** `06:162-163`: primeiro `-l -i -c` num PTY oculto com marcador (5 s), depois `-l -c` (3 s), depois fallback. `08:77` (AR-103): `-l -c` (3 s) e fallback `-lic`. As ordens são opostas. Prevalece 06, que trata o p10k/oh-my-zsh do dono e tem teste de contrato (V11). 08 também usa rótulo de UI em português.
Patch `08:77`: **de** `(\`$SHELL -l -c 'env -0'\`, com timeout de 3 s e fallback para \`-lic\`; nunca \`zsh\` fixo)` **para** `(conforme 06 §1.7: \`-l -i -c\` num PTY oculto com marcador e timeout de 5 s, depois \`-l -c\` com 3 s, depois env do launchd mais PATH conhecido; nunca \`zsh\` fixo)`; **de** `quando o usuário pede "Recarregar ambiente"` **para** `quando o usuário pede "Reload Shell Environment"`.

**K-20 · Undo ao apagar.** `06:128`: Undo por 10 s. `02:744` e `03:660`: 8 s para ações com Undo. Prevalece 8 s.
Patch `06:128` **de** `Undo por 10 s apenas para o registro` **para** `Undo por 8 s (DS §12.19) apenas para o registro`; acrescentar em `03 §9.4` o toast `Session deleted.` · `Undo` (8 s, restaura só o registro).

**K-21 · Limiar de "Stalled?".** `05:392` (AC-426): 10 min. `07:494` (CS-321) e `07:528` (CA-304): 8 min. A versão também diverge (ver K-56). Prevalece 10 min, configurável.
Patch `07:494` **de** `(sem chamada de ferramenta nem nota há 8 min, configurável)` **para** `(v1.1: sem chamada de ferramenta nem nota há 10 min, configurável)`; `07:528` **de** `Um filho sem chamadas há 8 min` **para** `(v1.1) Um filho sem chamadas há 10 min`.

**K-22 · Memória da VM nos testes de carga.** `05:332` (AC-406): VM de 24 GB. `07:154` (CS-132): recomendação de ≈ 25 GiB para 15 + 2. `07:230` (CA-103): 28 GiB. Pela própria fórmula de CS-132, 24 GB fica abaixo do necessário.
Patch `05:332` **de** `**Dado** uma VM com 24 GB` **para** `**Dado** uma VM com 28 GiB (≥ recomendação de CS-132)`.

**K-23 · Contagens do Orca do dono.** `01:30`, `03:1033`, `05:41`, `08:362`: 6 repositórios e 103 worktrees. `06:747`: 7 repositórios e 111 entradas de `worktreeMeta`, conferido hoje no SQLite. Os números de fixture podem ficar; o aceite de 08 AR-342 não pode fixar uma contagem que já mudou.
Patch `08:362` **de** `com o Orca do dono (6 repositórios, 103 worktrees; \`10 §0\`)` **para** `com o Orca do dono (contagens do dia do teste; em 2026-10-16, 7 repositórios e 111 worktrees, 06 §6.1)`.

---

## 2. Nomes divergentes

**K-24 · Sessão sem projeto: "Scratch" × "Clean session" / seção "Sessions".** 02 e 03 usam `Scratch session` e seção `Scratch` (`02:287`, `02:292`, `02:588`, `02:625`, `02:954` — que proíbe "Clean session"; `03:25`, `03:120`, `03:309-314`, `03:531-532`, `03:1150`, `03:1172`, `03:1248`, `03:1282`). 01, 04, 05 e 06 usam `Clean session` e seção `Sessions` (`01:225`, `01:608-609`, `04:349`, `04:459`, `05:62`, `05:74`, `05:239`, `05:733-744`, `06:365-367`). O 00 só diz "sessões limpas" em português.
Recomendação: `Scratch` na UI (seção `Scratch`, `New Scratch Session`), `kind = clean` no domínio. Motivo: uma seção chamada "Sessions" ao lado de "Projects", que também contêm sessões, é ambígua. **Decisão do dono (D-01).** Patches prontos em §11.

**K-25 · Verbos de controle do computador.** `Take over` / `Hand back` em 01, 05 e 07 (`01:110`, `01:586-596`, `01:627-628`, `05:297-298`, `05:347`, `05:353`, `07:223`, `07:445`, `07:551-554`, `07:571`). `Take Control` / `Give Back` em 02, 03 e 04 (`02:462-463`, `02:964` — que proíbe "Takeover"; `03:299`, `03:402`, `03:617`, `03:646`, `03:716-717`, `03:751-800`, `03:1225`, `03:1321`; `04:416-418`, `04:616`, `04:642-645`). O Orca não tem precedente. Recomendação: `Take Over` / `Hand Back` (Title Case de 02 §18), porque 01 é o glossário de produto e as jornadas usam esse par. **Decisão do dono (D-02).**

**K-26 · Rótulo de `revoking`.** `01:587` e `04:416`, `04:616`: `Requesting control…`. `02:180` e `03:784`: `Asking for control…`. Prevalece 01 (estados de domínio e seus rótulos).
Patch `02:180` e `03:784` **de** `Asking for control…` **para** `Requesting control…`.

**K-27 · Inbox × sino.** 02 e 03 definem um item de nav `Inbox` (⇧⌘I) com feed na sidebar (`03:145`, `03:608-639`, `02:967`). 01, 05 e 06 falam de "sino" ou `Bell` (`01:99`, `01:419`, `01:641`, `05:164`, `05:168`, `05:182`, `05:392`, `05:628`, `06:494-498`, onde o sino é "botão no header da sidebar"). Prevalece 03, que desenha a superfície, e 02 já proíbe outros nomes.
Patch:
- `01:641` **de** `| **Bell** | Lista de eventos recentes e pedidos. Na v1.1 ganha "Since you were away". |` **para** `| **Inbox** | Feed de eventos recentes e pedidos na sidebar (⇧⌘I, 03 §9.1). Na v1.1 ganha "Since you were away". |`
- `01:99` **de** `sino com lista simples de eventos` **para** `Inbox com lista simples de eventos`; `01:419` **de** `para o sino e para` **para** `para a Inbox e para`.
- `06:497` **de** `- **Sino** (v1): botão no header da sidebar com contagem;` **para** `- **Inbox** (v1): item de nav da sidebar com contagem (03 §2.3 e §9.1);`. Na mesma linha, grupos `Needs You, Failed, Finished` → `Needs You · Working · Done · Earlier` (03 §9.1), `"Mark All Read"` → `"Mark All as Read"`, `"Next Needing You"` → `"Next Needing Attention"` (K-29).
- `06:498` e `06:515`: `"Since last time"` → `"Since you were away"` (01 e 05).
- Em 05, trocar "sino" por "Inbox" nas linhas 164, 168, 182, 392 e 628.

**K-28 · Agrupamentos da Inbox.** Ver K-27 (06 usa grupos diferentes de 03).

**K-29 · "Next needing attention".** `01:99`, `01:640` e `05:503`: `Next needing attention`. `03:1201` e `03:1284`: `Next Needs You`. `06:497`: `Next Needing You`. Prevalece o nome do glossário de 01, em Title Case: `Next Needing Attention`.
Patch `03:1201` e `03:1284` **de** `Next Needs You` **para** `Next Needing Attention`.

**K-30 · Indicador de perfil sem permissões.** `01:631` e `05:272` (AC-316): `Skip permissions`. `03:422`: ícone `ShieldOff` com tooltip `Permissions are skipped (--dangerously-skip-permissions)`. `06:333` e `06:408` (TA-205): chip `"Bypass"` âmbar no pane e na sidebar. `03:881`: segmento `Skip All`. Prevalece: nome `Skip permissions` (01) com o visual de 02/03 (`ShieldOff`, sem cor; 02 §1 regra 5 reserva cor para estado).
Patch:
- `06:333` **de** `- Indicador permanente: pane e linha da sidebar com chip "Bypass" (âmbar) sempre que o lançamento efetivo pula permissões.` **para** `- Indicador permanente: ícone \`ShieldOff\` no header do pane e na tab (03 §4.2), com tooltip \`Skip permissions (<flag exata>)\`, sempre que o lançamento efetivo pula permissões.`; TA-205 (`06:408`) **de** `chip "Bypass" permanente` **para** `indicador \`ShieldOff\` permanente`.
- `03:422` **de** `\`Permissions are skipped (--dangerously-skip-permissions)\`` **para** `\`Skip permissions (--dangerously-skip-permissions)\``.
- `03:881` **de** `\`Ask\` · \`Accept Edits\` · \`Skip All\`` **para** `\`Ask\` · \`Accept Edits\` · \`Skip Permissions\``; em §16.11, "perfil \`Skip All\`" → "perfil \`Skip Permissions\`".

**K-31 · Nomes dos perfis importados.** `01:291`: exemplo `Claude · Opus · skip permissions`. `03:537`: `Default · skip permissions`. `05:69` e `05:119` (AC-110): `Claude · Skip permissions` e `Codex · Bypass approvals`. `06:335`: `Claude · Default`, `Claude · Plan`. `06:757-758`: `Claude · Imported from Orca`, `Codex · Imported from Orca`. Prevalece 05 (é o que o aceite testa), com `Imported from Orca` como texto secundário (03 §13.4).
Patch: `06:757` **de** `Perfil "Claude · Imported from Orca" (padrão)` **para** `Perfil "Claude · Skip permissions" (padrão; detalhe "Imported from Orca")`; `06:758` igual com `Codex · Bypass approvals`; `03:537` **de** `\`Default · skip permissions\`` **para** `\`Claude · Skip permissions\``; `01:291` **de** `"Claude · Opus · skip permissions"` **para** `"Claude · Opus · Skip permissions"`.

**K-32 · Opções "Where" do composer.** `01:614` e `05:216`: `New worktree`, `Existing checkout`, `Folder`, `New folder (no Git)`. `02:677`: `New Worktree · Existing Branch · Folder`. `03:532`: para projeto `New Worktree · Existing Worktree · Main Checkout`; para Scratch `New Folder · Choose Folder…`. Prevalece 03, que desenha o composer e trata a sessão sem projeto pelo campo Project.
Patch:
- `01:614` **de** `"New worktree", "Existing checkout", "Folder", "New folder (no Git)"` **para** `projeto: "New Worktree", "Existing Worktree", "Main Checkout"; sem projeto (Project = "Scratch (no project)"): "New Folder", "Choose Folder…" (03 §6.1)`.
- `05:216` igual; `05:230` (AC-302) **de** `"Where" com "New worktree"` **para** `"Where" com "New Worktree"`; `05:239` (AC-305) **de** `escolhe "New folder (no Git)"` **para** `escolhe "Scratch (no project)" em Project e "New Folder" em Where` e **de** `"Folder" e "Existing checkout"` **para** `"Choose Folder…" e "Existing Worktree"`.
- `02:677` **de** `(\`New Worktree · Existing Branch · Folder\`)` **para** `(\`New Worktree · Existing Worktree · Main Checkout\`)`.
- `05:213` **de** `aparece "Reuse branch"` **para** `aparece "Reuse existing branch"` (03:533).

**K-33 · Agente e perfil no composer.** `05:214`: um campo "Agent" que lista `Claude · Skip permissions` e os perfis. `03:536-537`: dois campos, `Agent` e `Profile`. Prevalece 03.
Patch `05:214` **de** `4. "Agent": "Claude · Skip permissions" (padrão), com a lista de perfis, "Codex", "OpenCode" e "Blank terminal".` **para** `4. "Agent": "Claude Code" (padrão), "Codex", "OpenCode", "Blank Terminal"; "Profile": "Claude · Skip permissions" (padrão), filtrado pelo agente.`

**K-34 · Promover sessão sem projeto.** `01:226` e `05:738`, `05:759`: `Move to Project…` e `Convert to Project`, e `Move folder into project…` na v1 (AC-1107). `03:251`, `03:1102-1107`, `03:1208`: `Promote to Project…`, submenu `Move to Project ▸`, overlay com `New project from this folder` e checkbox `Initialize a Git repository`. `06:368-369` e `06:416-417`: `Attach to Project…` (v1), `Move Folder Into Project…` (v1.1), `Initialize Git Here` (v1.1). `04:349`: `Move to project…`. Prevalece 01 nos nomes; a versão de mover a pasta fica com 06 (v1.1), porque depende do teste V8 (resume depois de mover a pasta).
Patch:
- `03:251` **de** `\`Promote to Project…\` (só scratch; §16.8) · \`Move to Project ▸\` (só scratch)` **para** `\`Move to Project…\` (só scratch; §16.8, inclui "New Project from This Folder", que é o Convert to Project) · \`Move Folder into Project…\` (v1.1; só com terminais parados)`; `03:1208` **de** `\`Promote to Project…\`` **para** `\`Move to Project…\``.
- `03:1105` remover `que roda \`git init\` só se marcado \`Initialize a Git repository\`` (git init é v1.1, 06 §2.7).
- `06:368` **de** `"Attach to Project…"` **para** `"Move to Project…"`; TA-213 (`06:416`) igual.
- `05:762` (AC-1107) **de** `**AC-1107** · v1` **para** `**AC-1107** · v1.1`; `05:738` **de** `"Move folder into project…" só fica disponível` **para** `(v1.1) "Move Folder into Project…" só fica disponível`.
- `04:349` **de** `"Move to project…"` **para** `"Move to Project…"`.

**K-35 · Nome automático de sessão.** `01:674` e `05:734`, `05:747`: adjetivo + substantivo (`quiet-harbor`). `03:545`: derivado do prompt em kebab-case, ou nome de criatura marinha (como `sandperch` no Orca). `06:365`: `untitled-<n>` ou derivado do prompt. `05:233` (AC-303): título legível `Fix ArcGIS pagination` e pasta/branch em kebab-case. O gerador sem prompt é **decisão do dono (D-09)**. Sobre o nome com prompt, prevalece AC-303: título legível, slug só para pasta e branch.
Patch `03:545` **de** `Derivado do prompt (3–5 palavras em kebab-case)` **para** `Derivado do prompt (3–5 primeiras palavras, como digitadas; pasta e branch usam o slug kebab-case, 06 §5.2)`.

**K-36 · Linha da nota de status no card.** `01:211`: "Linha 2 do card". `05:166` e `05:194` (AC-208): linha 2, editada com duplo clique. `03:207`: linha 3, editada por `Edit Note…` (a linha 2 é branch/pasta; duplo clique no nome renomeia). Prevalece 03.
Patch: `01:211` **de** `R2.4. Linha 2 do card` **para** `R2.4. Linha 3 do card (03 §2.6)`; `05:166` **de** `na linha 2` **para** `na linha 3`; `05:194` **de** `edita a nota inline (duplo clique na linha 2)` **para** `edita a nota (\`Edit Note…\` ou duplo clique na linha da nota)` e **de** `a linha 2 do card mostra` **para** `a linha 3 do card mostra`.

**K-37 · Retomada em lote.** `05:165`, `05:191` (AC-207): `Resume session` e overlay `Resume 6 agents`. `06:148`, `06:357`, `06:413` (TA-210): `Resume 6 agents…` / `Resume N agents…`. `03:250`, `03:1095-1098`: `Resume Agents…`, título `Resume interrupted agents?`, botão `[Resume <n>]`. Prevalece 03.
Patch: em 05 e 06, `"Resume session"` → `"Resume Agents…"` e `"Resume 6 agents"` / `"Resume N agents…"` → overlay `"Resume interrupted agents?"` com o botão `"Resume <n>"`.

**K-38 · Ações de conversa.** `05:167` e `05:185` (AC-205): `Resume in new tab`, `Copy resume command`, `Copy ID`, `Open elsewhere`. `03:725-726`: `Resume in New Tab`, `Copy Resume Command`, `Copy Conversation ID`, `Open in another terminal`. `06:361`: "Continue Conversation" (lançador, aba "Recent"). Prevalece 03.
Patch: em 05, trocar pelos rótulos de 03; `06:361` **de** `"Continue Conversation" (lançador, aba "Recent")` **para** `Painel "Conversations" (03 §10.5)`.

**K-39 · Microcopy do onboarding.** Título `Set Up Agent Box` (`03:1019`) × `Set up Agent Box` (`05:62`). Estado de login `Logged in` / `Not logged in` / `[Log In]` (`03:915`, `03:1025`) × `Signed in` / `Sign in` (`05:63`, `05:101`, `05:266`). O próprio 03 usa `[Sign In]` para o `gh` (`03:700`, `03:926`, `03:1028`). `Skip for Now` (`03:1038`) × `Skip for now` (`05:98`). OpenCode: `Login can't be verified` (`03:1027`) × `Sign-in status unavailable` (`05:63`). Capacidade: `≈ 14 headless or 6 desktop computers` (`03:963`) × `about 6 headless or 3 desktop computers` (`05:65`). Prevalece 03 (Title Case de 02 §18 e o verbo dos próprios CLIs: `/login`, `codex login`, `gh auth login`).
Patch: em 05, `Set up Agent Box` → `Set Up Agent Box`, `Signed in` → `Logged in`, `Sign in` → `Log In`, `Sign in with gh` → `Log In` (abre `gh auth login`), `Codex is signed out · Sign in` → `Codex is not logged in · Log In`, `Skip for now` → `Skip for Now`, `Sign-in status unavailable` → `Login can't be verified`, `about 6 headless or 3 desktop computers` → `≈ 6 headless or 3 desktop computers`. Em 03, `[Sign In]` → `[Log In]` (linhas 700, 926, 1028) e `Sign in to GitHub CLI to see pull requests.` → `Log in to GitHub CLI to see pull requests.`.

**K-40 · Conflito com a skill global `agentbox`: quatro versões.** `03:921`, `03:1034`: `[Disable…]` / `[Disable Skill…]` · `[Keep]`; `03:868`: `[Disable Global Skill…]` · `[Keep]`. `05:73`, `05:128` (AC-113), `05:287`, `05:320`: `Use Agent Box tools`, `Disable skill`, `Keep as is`. `06:394-397` e TA-218: `Block in Agent Box launches` (padrão), `Disable globally…`, `Keep`. `07:739` (CS-722): `Disable globally`, `Keep for terminals outside Agent Box` (padrão), `Redirect`; e CS-721 aplica o bloqueio por lançamento sempre. Prevalece o desenho de 06, que é o mesmo mecanismo de 07 CS-721 apresentado como escolha, sem escrita global.
Opções canônicas: `Block in Agent Box` (padrão; `permissions.deny` por lançamento) · `Disable Globally…` (move com backup) · `Keep` (nada muda). O `Redirect` de 07 escreve fora do app e vai para **D-11**. Texto do aviso: o de 03 (`A global "agentbox" skill is installed and may compete with Agent Box tools.`).
Patch: em 03, `[Disable…]`/`[Disable Skill…]`/`[Disable Global Skill…]` · `[Keep]` → `[Block in Agent Box]` · `[Disable Globally…]` · `[Keep]`. Em 05, `"Use Agent Box tools"` → `"Block in Agent Box"`, `"Disable skill"` → `"Disable Globally…"`, `"Keep as is"` → `"Keep"`; o texto de `05:73` vai para o de 03. Em 06, `Disable globally…` → `Disable Globally…` e `Block in Agent Box launches` → `Block in Agent Box`. Em 07, CS-720 (`07:737`) usa o texto de 03 e CS-722 (`07:739`) usa as três opções acima (Redirect: ver D-11).

**K-41 · Docker parado.** `01:43` e `05:308`, `05:631`: `Docker is stopped · Start Docker`. `03:516`, `03:632`, `03:831`, `02:752`: `Docker isn't running` + `[Start Docker]`. `07:86` (CS-104): `"Docker is not running"`, `"Start Docker Desktop"`. Prevalece 03.
Patch: `01:43` **de** `("Docker is stopped · Start Docker")` **para** `("Docker isn't running · Start Docker")`; em `05:308` e `05:631`, `"Docker is stopped · Start Docker"` → `"Docker isn't running · Start Docker"`; em `07:86`, `"Docker is not running"` → `"Docker isn't running"` e `"Start Docker Desktop"` → `"Start Docker"`.

**K-42 · Orçamento esgotado e a 80 %.** `03:627`: `<computer> hit its $1.00 proxy budget` + `[Add $1]`. `05:310` e `05:368` (AC-418): `Phoenix hit its $1.00 budget · Add $1.00`. `05:716`: `Add $1.00`. `07:183` (CS-163) e `07:235`: `"Add $1"` e `"Zyte budget 80% — phoenix-az"`. `03:635`: `<scope> used 80% of its proxy budget`. Prevalece o texto de 03 com o valor no formato de 02 §18 (duas casas): `Add $1.00`.
Patch: `03:627` **de** `[Add $1]` **para** `[Add $1.00]`; em 05, `hit its $1.00 budget` → `hit its $1.00 proxy budget`; em 07, `"Add $1"` → `"Add $1.00"` e `"Zyte budget 80% — phoenix-az"` → `"phoenix-az used 80% of its proxy budget"`.

**K-43 · Porcentagem e hora na status bar.** `02:978` exige `62%` sem espaço. 05 usa `96 %`, `62 %`, `100 %` (`05:563`, `05:695`, `05:707`) e `01:508`, `05:404` usam `42 %`. Hora: `05:695` e `05:707` usam `resets 14:20`; `03:511` e `02:828` usam `Resets at 2:20 PM`; `02:752` usa `Resets at 14:20.`. Prevalece 02/03: porcentagem sem espaço; hora pelo formatador do sistema, com exemplos no formato de 03.
Patch: em 05, `\d+ %` → `\d+%` nas strings de UI; `"Claude 5h 62 % · resets 14:20 · 7d 31 %"` → `"5h 62% · 7d 31%"` (03 §5); `"Codex 5h 100 % · resets <hora>"` → `"5h 100%"` com `Resets at <time>` no popover; `"Pulling image 42 %"` → `"Pulling image 42%"` (`01:508`, `05:404`); `02:752` **de** `Resets at 14:20.` **para** `Resets at 2:20 PM.`.

**K-44 · Selo de teclado capturado e tecla de soltar.** `03:800`, `03:1226`, `03:1322`: `Keyboard captured · ⌃⌥ to release`, soltar com `⌘⎋` ou `⌃⌥`. `05:298` e `05:356`: `Keyboard in computer · ⌃⌥ to release`. `07:561` (CS-421): `Ctrl+Option+Esc`. Prevalece 03 (atalhos e microcopy), que também bate com o rótulo `Keyboard captured` de 02 e de 08 A16.
Patch: em 05, `"Keyboard in computer · ⌃⌥ to release"` → `"Keyboard captured · ⌃⌥ to release"`; `07:561` **de** `\`Ctrl+Option+Esc\` (soltar o foco do viewer)` **para** `\`⌘⎋\` ou \`⌃⌥\` (soltar o teclado, 03 §11.6)`.

**K-45 · Fechar pane com processo vivo.** `06:127`: overlay `"Terminate *claude* in this pane?"` [Terminate] [Cancel], depois `"Process didn't exit"` [Force Quit]. `03:1048-1055`: `Close this terminal?` + `[Close Terminal]` (destrutivo). Prevalece 03.
Patch `06:127` **de** `pede confirmação em overlay: "Terminate *claude* in this pane?" [Terminate] [Cancel]` **para** `pede confirmação no overlay de 03 §16.1 ("Close this terminal?" [Cancel] [Close Terminal])`. O `"Process didn't exit"` com [Force Quit] continua e deve entrar em 03 §4.6.

**K-46 · Fim de sessão do daemon na UI.** Termos técnicos não aparecem na UI fora de Diagnostics (`01:602`), e o glossário chama o daemon de "Background agents" (`01:658`). Textos atuais: `03:488` `Lost connection to the terminal daemon. Reconnecting…` + `[Restart Daemon]`; `02:752` `Reconnecting to the terminal daemon…`; `04:310` (M-003) `Reconnecting to agentboxd…`; `06:147` `Terminal ended unexpectedly`; `05:634` (AC-810) `Background agents stopped unexpectedly`; `05:637` (AC-811) `3 terminals on previous background service`; `08:705-706` (AR-904) `Restart terminal service to update`, `N terminals on previous terminal service`. Prevalece o vocabulário de 01/05: "background service" para o processo e "background agents" para o que ele mantém.
Patch: `03:488` **de** `Lost connection to the terminal daemon. Reconnecting…` **para** `Lost connection to the background service. Reconnecting…` e `[Restart Daemon]` → `[Restart Background Service]`; `02:752` **de** `Reconnecting to the terminal daemon…` **para** `Reconnecting to the background service…`; `04:310` **de** `"Reconnecting to agentboxd…"` **para** `"Reconnecting to the background service…"`; `06:147` **de** `faixa "Terminal ended unexpectedly"` **para** `banner "Background agents stopped unexpectedly" (AC-810) e, no pane, "This terminal stopped unexpectedly."`; `08:705` **de** `"Restart terminal service to update"` **para** `"Restart background service to update"`; `08:706` **de** `"N terminals on previous terminal service"` **para** `"<n> terminals on previous background service"`. Acrescentar a variante `This terminal stopped unexpectedly.` em `03:487`.

**K-47 · Overlay de processo morto ao abrir (M-002).** `04:309`: pill `Exited while Agent Box was closed` com `Resume conversation` / `Close`. `03:487`: banner `This terminal stopped while Agent Box was closed.` com `[Resume]` · `[Start Fresh]` · `[Close]`. Prevalece 03.
Patch `04:309` **de** `pill "Exited while Agent Box was closed" e botões "Resume conversation" / "Close"` **para** `banner "This terminal stopped while Agent Box was closed." e botões "Resume" / "Start Fresh" / "Close" (03 §4.6)`.

**K-48 · Saída com erro e falha ao iniciar (M-312, M-313, M-505).** `04:368`: `Terminal exited with code 1. Its output is preserved.` + `Restart` / `Close`. `03:484`: título `Terminal exited` e texto `The process ended with exit code <n>. Its output is preserved.` + `[Close]` `[Restart]` `[Resume Conversation]`. `04:369` e `04:400`: `Retry` / `Open launch log`. `03:485`: `[Retry]` · `[Open Agent Settings]` · `[Copy Details]`. `01:500`, `01:511`: `Exited with error · n`. `02:164`: `Exited with code 1` / `Killed (SIGKILL)`. Prevalece 03 no overlay e 02 no rótulo curto (`Exited with code <n>`).
Patch: `04:368` **de** `"Terminal exited with code 1. Its output is preserved." + "Restart" / "Close"` **para** `título "Terminal exited", texto "The process ended with exit code <n>. Its output is preserved.", botões "Close" / "Restart" / "Resume Conversation" (03 §4.6)`; `04:369` e `04:400` **de** `"Retry" / "Open launch log"` **para** `"Try Again" / "Open Agent Settings" / "Copy Details"`; `01:500` e `01:511` **de** `Exited with error · n` **para** `Exited with code <n>`.

**K-49 · "Retry" × "Try Again".** 01 (`01:64`, `01:476`), 05 (`05:220`, `05:257`, `05:813`) e 06 (`06:619`, `06:685`) usam `Try again` / `Try Again`, como o Orca (`en.json`: `"tryAgain": "Try Again"`). 03 mistura `[Try Again]` (`03:93`) com `[Retry]` (`03:485`, `03:563`, `03:700`, `03:831`). 04 usa `"Retry"`. Prevalece `Try Again`.
Patch: em 03 e 04, `[Retry]` / `"Retry"` → `[Try Again]` / `"Try Again"`. Em `05:257` (AC-311), `"Create from local ref"` → `"Create Without Fetching"` (03:563), e `05:220`, `05:257` passam a `Try Again` em Title Case.

**K-50 · Overlay e páginas vazias (M-901, M-902, M-903, M-904).** `04:459`: ações `"New session" ⌘N` e `"New clean session"`. `05:74` e `05:149` (AC-120): `"New clean session"` e `"Add project"`. `03:1244-1253`: `[Add Project…]` · `[New Scratch Session]` · `[Import from Orca…]`. `04:460`: `"No sessions found"` + `"Clear search"`; `03:135`: `No sessions match "<query>".` + `[Clear Search]`. `04:461`: `"Docker isn't running"` + `"Start Docker"` / `"Build image in background"`; `03:831`: `Docker isn't running.` + `[Start Docker]`. `04:462`: `"Some data couldn't be loaded"` + `"Restore backup"` / `"Details"`; `03:95`: `Agent Box couldn't read its database. Your terminals are still running.` + `[Open Diagnostics]`; `08:321`: `"Open diagnostics"`; `08:338`: `"Reveal corrupt file"`; `05:818` (AC-T13): `"Show corrupted file"`. Prevalece 03 na microcopy; os casos de 08 entram como variantes.
Patch: os textos de 04 e 05 citados passam aos de 03 (M-901 com as três ações da landing; M-902 com `No sessions match "<query>".` + `Clear Search`; M-903 sem `Build image in background`; M-904 com o banner de 03). Em 08, `"Open diagnostics"` → `"Open Diagnostics"`; em 05, `"Show corrupted file"` → `"Reveal Corrupt File"` (08 AR-331, em Title Case). Acrescentar em 03 §1.4 as variantes `Database was created by a newer Agent Box` e `Restored from the backup of <date>.` [Reveal Corrupt File].

**K-51 · Notificações do sistema: título.** `03:644`: `<project> / <session> — <Agent> needs you`. `06:489`: `"{project} / {session} — {Agent} {status}"`, ex. `Claude finished`. `05:517` (AC-603): `arizona / sandperch · Codex needs input`. `05:344` (AC-410) e `05:297`: `permits-oct · Phoenix needs you`, corpo `Captcha on aca-prod.accela.com`. 07 CS-433 limita o texto a nome, tipo e host. O Orca usa os status `needs input`, `finished`, `failed` (`en.json`, `notifications.agentStatus`). Prevalece 06 + Orca para agentes; para computador, `<session> — <computer> needs you` com corpo `<Kind> on <host>`.
Patch: `03:644` **de** `- Título: \`<project> / <session> — <Agent> needs you\` · \`— <Agent> finished\` · \`— <Agent> failed\` · \`<computer> needs you\`.` **para** `- Título: \`<project> / <session> — <Agent> needs input\` · \`— <Agent> finished\` · \`— <Agent> failed\`; computador: \`<session> — <computer> needs you\`, corpo \`<Kind> on <host>\` (CS-433).`; em `05:517`, `"arizona / sandperch · Codex needs input"` → `"arizona / sandperch — Codex needs input"`; em `05:344` e `05:297`, `"permits-oct · Phoenix needs you"` → `"permits-oct — phoenix-az needs you"`.

**K-52 · Toggles de notificação.** `03:989-990`: um switch por tipo, `Terminal bell` ligado e `Suppress when the session is visible`. `06:487`: `Bell: off` e `"Only when Agent Box isn't focused"`. Prevalece 03 na forma; o bell fica desligado por padrão (06), porque BEL já marca não lido (AC-612) e o dono não quer ruído.
Patch: `03:989` **de** `\`Terminal bell\` (on)` **para** `\`Terminal bell\` (off)`; em `06:487`, `"Only when Agent Box isn't focused"` → `"Suppress when the session is visible" (ligado)`.

**K-53 · Ícone da barra de menus: estados.** `06:209`: contorno (nada rodando), preenchido (rodando), ponto âmbar com número (precisa de você). `03:1143`: número via `button.title` quando há "needs you", ponto âmbar 4 pt só com não lidos, sem animação. Prevalece 03.
Patch `06:209` **de** `- Ícone com estado: contorno (nada rodando), preenchido (rodando), ponto âmbar com número (precisa de você).` **para** `- Ícone conforme 03 §17: número ao lado quando há pendências; ponto âmbar só com não lidos; sem animação.`

**K-54 · Badge do Dock.** `03:654`: número de "needs you". `06:491`: `needsInput` + `failed` não lidos + pedidos de ajuda. `01:391`: AttentionItems alimentam o badge (e incluem `done`, prioridade 3). Prevalece AttentionItem de prioridade 1–2 (01 §5.12), que é o que 06 descreve.
Patch `03:654` **de** `- \`NSApp.dockTile.badgeLabel\` = nº de "needs you" (vazio quando 0).` **para** `- \`NSApp.dockTile.badgeLabel\` = nº de AttentionItems de prioridade 1–2 não resolvidos (pedidos de computador, needs input, falhas; 01 §5.12), vazio quando 0.`; em `01:391`, acrescentar "(o badge conta só prioridade 1–2)".

**K-55 · Settings: seções e rótulos.** `05:143` (AC-118): `Settings › Secrets`; `03:929`: `Credentials`. `07:715`: `Settings → "Zyte"`. `05:782` (AC-T03): `Developer › Automation`; `08:599` (AR-806): `Settings › Developer › "Allow automation"` e indicador `Automation on` na titlebar; `03:1008`: `Advanced › Automation channel (agentbox ctl)`. `08:401` (AR-501): `Settings › Security`, que 03 não tem. `08:342` (AR-332): `Export database` e `Restore from backup…` em Advanced, ausentes de 03. `05:830` (AC-T17) e `08:503` (AR-603): `Export diagnostics` (zip); `03:1004` e `03:1236`: `Copy Diagnostic Report`. `06:774`: `"Import from Orca Again…"` em `Settings › General`; `03:955`: `[Import Again…]` em `Settings › Import`. `05:128` (AC-113): `"Restore skill"` em `Settings › Diagnostics`. `06:159`: `"Reload Shell Environment"` em `Settings › Terminal`, ausente de 03. Prevalece a estrutura de 03, que recebe os itens que faltam.
Patch:
- `05:143` **de** `Settings › Secrets mostra` **para** `Settings › Credentials mostra`; `07:715` **de** `Settings → \`"Zyte"\`` **para** `Settings › Credentials (\`Zyte API key\`) e Settings › Computers (orçamentos e custos)`.
- `05:782` **de** `"Developer › Automation"` **para** `"Settings › Advanced › Automation channel"`; `08:599` **de** `liga em Settings › Developer › "Allow automation"` **para** `liga em Settings › Advanced › "Automation channel (agentbox ctl)" (03 §14.2)`. Acrescentar em `03:1008`: `Enquanto ligado, a faixa da titlebar mostra \`Automation on\` (AR-806).`
- `08:401` **de** `é publicado no README e na tela Settings › Security` **para** `é publicado no README e em Settings › Advanced › "Security model" (linha com link para o texto)`; acrescentar essa linha e `Export Database…` / `Restore from Backup…` em `03 §14.2 Advanced`.
- `03:1004` **de** `\`[Reveal Logs in Finder]\` · \`[Copy Diagnostic Report]\` (redigido).` **para** `\`[Reveal Logs in Finder]\` · \`[Export Diagnostics…]\` (pacote .zip redigido, AR-603).`; `03:1236` `Copy Diagnostic Report` → `Export Diagnostics…`.
- `06:774` **de** `"Import from Orca Again…" em Settings › General` **para** `"Import Again…" em Settings › Import (03 §14.2)`.
- `05:128` **de** `"Restore skill" em Settings › Diagnostics desfaz` **para** `"Restore Skill" em Settings › Agents › Agent Box skill desfaz`.
- `03:985`: acrescentar o botão `Reload Shell Environment` (06 §1.7).

**K-56 · Rótulos de estado de computador.** Fila: `01:551` `Waiting for memory · 3 of 15`; `02:177` `Queued (waiting for memory)`; `03:790` e `04:412` `Waiting for memory · 3 of 15 queued`; `05:307` `Queued · 3 of 15 waiting for memory`; `07:153` `3 of 15 waiting for memory`. Pronto e ocioso: `01:575` `Ready`; `02:178` `Idle`; `03:769` pill `Idle`. Conexão lenta: `02:183` e `03:787` `Slow connection`; `04:420` (M-610) `Delayed`; `07:542` (CS-404) estado `lagging`. Prevalece 03/04 para a fila; `Ready` (01) para o ciclo de vida e `Idle` (03) para a pill de controle sem dono; `delayed` / `Slow connection`.
Patch: `01:551`, `02:177`, `05:307` e `07:153` passam a `Waiting for memory · 3 of 15 queued` (rótulo curto `Queued`); `02:178` **de** `| \`running\`, ninguém usando | \`Idle\`` **para** `| \`ready\`, ninguém usando | \`Ready\``; `01:590` **de** `| \`none\` | — | Sem dono |` **para** `| \`none\` | "Idle" (pill) | Sem dono |`; `04:420` **de** `pill âmbar "Delayed"` **para** `pill âmbar "Slow connection"` e `"Reconnecting"` → `"Reconnecting…"`; `07:542` **de** `\`lagging\` (último frame > 2 s, mostra o horário)` **para** `\`delayed\` ("Slow connection"; último frame > 2 s, mostra o horário)`.

**K-57 · Pedido de ajuda: tipos, estados e recusa.** `01:363` tipos `captcha | login | download | choice | permission | budget | other`; `07:389` acrescenta `mfa`. `01:365`: estados `open → takenOver → resolved | cancelled`; `07:391`: `pending | resolved | declined | expired`. `03:786`: `[Dismiss]` com `The agent will be told you declined.`; `07:572` (CS-432): `"Decline"` com motivo. Prevalece a união, com o rótulo de 07.
Patch: `01:363` acrescentar `mfa`; `01:365` **de** `\`open\` → \`takenOver\` → \`resolved\` \| \`cancelled\`` **para** `\`open\` → \`takenOver\` → \`resolved\`; \`open\` → \`declined\` \| \`cancelled\` \| \`expired\` (07 CS-432)`; `03:786` **de** `\`[Dismiss]\`` **para** `\`[Decline…]\``.

**K-58 · Faixa "Computers" da sessão.** `01:110`, `01:626`, `05:296`, `05:335` (AC-407), `05:753`, `07:444`, `07:541` (CS-403) e `04:422` (M-612) falam de uma faixa de miniaturas da sessão. 03 implementa isso como a aba `Computers` do painel direito (`03:712-719`), mais a faixa de miniaturas dentro do viewer (`03:774-776`). Prevalece 03. O hover que amplia a miniatura (04, 05, 07) entra em 03.
Patch: `01:626` **de** `| **Computers** (faixa) | Faixa da sessão com miniaturas dos computadores, URL atual, última nota do diário e gasto. |` **para** `| **Computers** (aba do painel direito, ⇧⌘C) | Miniaturas dos computadores da sessão com URL atual, última nota do diário e gasto (03 §10.4). |`; em 05 e 07, `faixa "Computers"` → `aba "Computers" do painel direito`; em `03:715`, acrescentar `Hover amplia a miniatura (M-612) e mostra a URL e a última nota.`

**K-59 · Abas do detalhe do filho/computador.** `03:804`: `Network · Journal · Files · Timeline`. `07:493` (CS-320): `Activity`, `Network`, `Journal`, `Commands`, `Files`, `Timeline`, `Result`. `05:299`: inclui `Commands`; `05:377`: `Result`. `04:332` (M-113): `Network, Journal, Commands, Files, Timeline`. Prevalece o conjunto de 07, que é o que os aceites testam (AC-415 testa `Commands`, AC-421 testa `Result`).
Patch `03:804` **de** `\`Network\` · \`Journal\` · \`Files\` · \`Timeline\`` **para** `\`Activity\` · \`Network\` · \`Journal\` · \`Commands\` · \`Files\` · \`Timeline\` · \`Result\``, com a descrição de cada aba vinda de 07 CS-320.

**K-60 · Escolha do modo do subagente.** `03:548`: `Subagent computers` com `Off · Light · Isolated`. `01:621-622` e `05:412` (AC-451): `"On this Mac"` / `"In container"`. `02:188`: tooltip `Runs in an isolated box`. Prevalece 01/05 nos rótulos de escolha.
Patch: `03:548` **de** `\`Off\` · \`Light\` · \`Isolated\`` **para** `\`Off\` · \`On This Mac\` · \`In Container\` (v1.1)`; `02:188` **de** `\`Runs in an isolated box\`` **para** `\`Runs in a container\``.

**K-61 · "Watch".** `07:223` (CS-191) e `07:579` (CS-440) usam `"Watch"`; 03 usa `Open Viewer`. Prevalece 03.
Patch: em 07, `"Watch"` → `"Open Viewer"`.

**K-62 · "Paused" durante o takeover.** `04:417` e `04:619`, `04:645` mudam a linha do filho para `"Paused"`. 03 mostra o estado do computador na linha (`You're in control`). `07:551` (CS-412) pede uma faixa âmbar `"You're in control — Hand back ⌘⇧R"`; em 02 o humano no controle é branco (`02:181`, `02:390`) e âmbar é aviso. Prevalece 02/03.
Patch: em `04:417` e `04:619`, `"Paused"` → `"You're in control"` (estado curto do computador, 03 §2.8); `07:551` **de** `uma faixa âmbar \`"You're in control — Hand back ⌘⇧R"\`` **para** `a pill \`"You're in control"\` com \`Hand Back ⇧⌘R\` (DS §2.8, borda branca de 2 pt)`.

**K-63 · Painel direito e Library.** `01:246`: o painel direito tem Library, Conversations e Changes. `01:646`: Library é um painel. `05:653`: ⌘⇧L abre a Library no painel direito, com `Agents`, `Skills` e `Instructions`. `04:327` (M-108): painel com `Computers, Requests, Agents, Library`. `04:328` (M-109): telas cheias `Settings, Library, Inbox`. 03 define o painel como `Source Control · Checks · Computers · Conversations · Context` (`03:33`, `03:676-686`), a Library como página com `Agents | Skills | Profiles` (`03:836-891`) e a Inbox como feed na sidebar. Prevalece 03.
Patch:
- `01:246` **de** `O painel direito (Library, Conversations, Changes) não é pane.` **para** `O painel direito (Source Control, Checks, Computers, Conversations, Context) e as páginas (Library, Computers) não são panes.`
- `01:646` **de** `| **Library** | Painel com agentes, skills e instruções das pastas nativas dos CLIs. |` **para** `| **Library** | Página (⇧⌘L) com agentes, skills e perfis de lançamento; instruções e ativação por sessão ficam na aba Context do painel direito. |`
- `05:653` **de** `1. ⌘⇧L abre "Library" no painel direito, com as abas "Agents", "Skills" e "Instructions"` **para** `1. ⇧⌘L abre a página "Library", com "Agents", "Skills" e "Profiles" (instruções aparecem na aba "Context")`.
- `04:327` **de** `(Computers, Requests, Agents, Library)` **para** `(Source Control, Checks, Computers, Conversations, Context)`; `04:328` **de** `(Settings, Library, Inbox)` **para** `(Settings, Library, Computers)`.

**K-64 · "Changes" × Source Control.** `01:123` e `05:463`, `05:487` (AC-507): painel `"Changes"` na v1.1, aberto por ⌘⇧G. `03:682`, `03:690-701`: ⇧⌘G abre a aba `Source Control`, que na v1 já lista as alterações (abrem no editor) e na v1.1 ganha o diff. Prevalece 03.
Patch: `01:123` **de** `- Painel "Changes" com diff só leitura;` **para** `- Diff só leitura na aba Source Control (a lista de alterações já existe na v1, 03 §10.2);`; `05:463` e AC-507 **de** `o painel "Changes"` **para** `a aba "Source Control" (diff em linha, v1.1)`.

**K-65 · Ferramentas MCP com nomes diferentes.** 07 é o dono do contrato (§3.2 e §4.2). Patch nos outros capítulos:

| Nome usado | Onde | Nome canônico (07) |
|---|---|---|
| `computer_acquire` (`computer_acquire(box: …)`) | `01:344`, `05:295`, `05:326`, `08:379`, `08:511`, `08:549`, `08:625` | `box_claim(name: …)` (filho); para medir criação: `boxes_reserve` → `ready` |
| `computer_request_help(kind:, reason:)` | `04:419`, `05:297`, `05:341` | `help_request(kind:, reason:)` |
| `computer_wait_help(request_id)` | `05:297`, `05:341`, `05:353` | `help_wait(request_id)` |
| `computer_exec` | `05:359` | `exec` |
| `computer_http_request` | `05:359` | `http_request` |
| `browser_fill` | `05:359` | `browser_type` |
| `already_claimed_by` | `05:309`, `05:326` | `already_claimed` (com o dono atual no payload) |
| `agent_result` | `01:121`, `05:408`, `05:427`, `05:979` | não existe; o resultado volta em `agent_wait` (`finished[].result`) e em `box_collect` |
| `boxes_reserve([…], mode: "headless")` | `05:294` | `boxes_reserve(names: […], display: "headless")` (ver K-69) |

**K-66 · Papéis de container e sidecar.** 07 usa `runtime` / `work` (exec na v1) / `gate` / `agent` (CLI na v1.1). 08 usa `box-runtime` / `egress` / `work` (CLI na v1.1), sem container de exec na v1 (`08:37-39`, `08:22`). `01:350` diz `runtime, egress, work (isolado)`. `04:565` usa `box.egress`. O 00 T9 chama o sidecar de "Egress sidecar". O `exec` da v1 (T12) precisa de um container que não seja o runtime: 07 CS-113 separa os dois para que o shell do agente não alcance o CDP nem o lease.
Recomendação: `runtime`, `work` (v1, `exec`), `egress` e `agent` (v1.1, substitui `work`).
Patch:
- Em 07, substituição global `gate` → `egress` e `agentbox-gate` → `agentbox-egress` (§0, §1.1, §2.2–2.6, §3.1, §5, §6.5, §7, §8; ex.: `07:15`, `07:41`, `07:96-107`, `07:110-114`, `07:125`, `07:140-149`, `07:245`, `07:539`, `07:636`, `07:646-648`, `07:681`).
- `08:37-39` (tabela de processos): acrescentar `work` (v1) com o texto "Shell e HTTP do agente (`exec`, `http_request`, Playwright próprio), `/work` do run, saída só pelo egress"; trocar a linha `work (container, v1.1)` por `agent (container, v1.1) | CLI do agente sob dtach, worktree montado`. No diagrama (`08:60-62`), `work (v1.1: CLI + dtach)` → `work (v1: exec) / agent (v1.1: CLI + dtach)`, e `docker exec -it work dtach` → `docker exec -it agent dtach`. `08:258`: `runtime/agent/ (imagem \`work\`)` → `runtime/agent/ (imagem \`agentbox-agent\`)`. `08:729`: `container \`work\` com \`dtach\`` → `container \`agent\` com \`dtach\``.
- `08:22` **de** `\`agentbox.role=runtime|egress|work\`` **para** `\`agentbox.role=runtime|work|egress|agent\``.
- `08:303`: `work_container_id` passa a significar `work` ou `agent`, conforme `mode`.
- `01:350` **de** `| \`imageDigest\`, \`containers\` | runtime, egress, work (isolado) |` **para** `| \`imageDigest\`, \`containers\` | runtime, work (v1) ou agent (isolado, v1.1), egress |`.

**K-67 · Portas e URLs do sidecar.** `07:114` (proxy em `gate:3128`) e `07:245`, `07:646` (API em `gate:8790`, `/mcp`, `/hooks`, `/git`, `/llm`). `08:102` (AR-113): hooks em `http://egress:8080/hooks/<computerID>`, MCP "servido pelo box-runtime". Prevalece 07 nos números (é o contrato mais completo), com o host renomeado para `egress`.
Patch `08:102` **de** `\`http://egress:8080/hooks/<computerID>\` e MCP por HTTP servido pelo \`box-runtime\` na rede interna` **para** `\`http://egress:8790/hooks/claude\` e MCP por HTTP em \`http://egress:8790/mcp\` (o egress repassa ao runtime as ferramentas de computador e enfileira para o app as que dependem dele; 07 CS-540/541)`.

**K-68 · Entidade "Box" × "Computer" no modelo.** `07:65` (CS-001) usa as entidades `Box` (com `Computer` embutido), `BrowserProfile`, `HelpRequest`, `BudgetLedger`, `JournalEntry`, `CommandRecord`, `RequestRecord`, "todos no SQLite". `01:335` usa `Computer`; `08:303` usa a tabela `computer` e não tem `browser_profile`, `help_request` nem fila. 07 se contradiz: CS-149 (`07:172`) grava diário, comandos e requests em arquivos append-only em `logs/`, não no SQLite. Prevalece `Computer` no domínio e no schema (01, 08); "box" só em ferramentas, logs e pastas (`01:337`).
Patch:
- `07:65` **de** `\`Box\`, \`Computer\` (embutido na Box), \`BrowserProfile\`, \`AgentRun\` (…), \`Batch\`, \`HelpRequest\`, \`BudgetLedger\`, \`JournalEntry\`, \`CommandRecord\` e \`RequestRecord\`, todos no SQLite` **para** `\`Computer\` (01 §5.10; "box" só em ferramentas e pastas), \`BrowserProfile\`, \`AgentRun\`, \`Batch\`, \`HelpRequest\` e \`Budget\` no SQLite; diário, comandos e requests ficam nos arquivos append-only de \`logs/\` (CS-149), indexados sob demanda`.
- `08:303-305`: acrescentar as tabelas `browser_profile` (`id`, `name`, `volume`, `sites_json`, `locked_by_computer_id`, `created_at`, `last_used_at`), `help_request` (campos de 01 §5.10) e `computer_queue` (`id`, `computer_id`, `position`, `requested_at`, `reason`), a fila persistente de CS-131.

**K-69 · Tipo do computador.** 07 usa `none` / `browser` / `desktop` no glossário, nos CS e nas assinaturas (`07:31-32`, `07:67`, `07:259-263`, `07:268`, `07:453`, `07:466`, `07:493`). 01 (`01:346`), 03 (`03:767`, `03:967`) e 08 (`08:303`, coluna `display`) usam `http` / `headless` / `desktop`. Prevalece 01/03/08.
Patch em 07: `"none"` → `"http"` e `"browser"` → `"headless"` sempre que o assunto é o tipo do computador; parâmetro `kind` → `display` em `boxes_reserve`, `box_claim`, `box_status` e `agent_spawn`; `computer_mode(kind: "none"|"browser"|"desktop")` → `computer_mode(display: "http"|"headless"|"desktop")`. O glossário (`07:32`) fica: "`Headless` = computador com Chromium headed em Xvfb e sem stream ao vivo".

**K-70 · Rótulos Docker e identificadores do app.** `06:60-61`, `06:89`, `06:217`, `06:224`: plist `app.agentbox.daemon.v1.plist`, socket `AB/run/daemon-v1.sock`, `AssociatedBundleIdentifiers = [app.agentbox]`, peers `app.agentbox` / `app.agentbox.helper`, `…daemon.v2`. `07:85` e `07:117` (CS-103, CS-115): `agentbox.owner=<installId>`, `agentbox.box=<boxId>`. `08:16-22`: bundle `app.agentbox.mac`, label `app.agentbox.ptyd.v<major>`, socket `run/ptyd-v1.sock`, helper `app.agentbox.cli`, `agentbox.owner=app.agentbox.mac`, `agentbox.computer=<id>`. Prevalece 08 (`08:12`: "fixados aqui para todos os capítulos"). Exceção: o valor de `agentbox.owner` deve ser um `installId` (07), porque 08 §8.1 exige recursos rotulados por execução de teste, e um valor fixo de bundle colide entre instalações de teste.
Patch:
- `06:60` **de** `"app.agentbox.daemon.v1.plist"` **para** `"app.agentbox.ptyd.v1.plist"` e `[app.agentbox]` → `[app.agentbox.mac]`; `06:61` **de** `\`AB/run/daemon-v1.sock\`` **para** `\`AB/run/ptyd-v1.sock\``; `06:89` **de** `identificador \`app.agentbox\` ou \`app.agentbox.helper\`` **para** `identificador \`app.agentbox.mac\` (só o app; AR-503)`; `06:217` `…daemon.v2` → `…ptyd.v2`; `06:224` `app.agentbox.daemon.v1` → `app.agentbox.ptyd.v1`.
- `07:117` **de** `\`agentbox.owner=<installId>\`, \`agentbox.box=<boxId>\`, \`agentbox.box_name\`` **para** `\`agentbox.owner=<installId>\`, \`agentbox.computer=<computerId>\`, \`agentbox.computer_name\``.
- `08:22` **de** `\`agentbox.owner=app.agentbox.mac\`` **para** `\`agentbox.owner=<installId>\` (UUID gerado na primeira abertura; nos testes, um por \`AGENTBOX_HOME\`)`; `08:104` (AR-114) igual.

**K-71 · Variáveis de ambiente e diretórios de lançamento.** `06:171`: `AGENTBOX_TERMINAL_ID`, `AGENTBOX_HOOK_SOCKET`, `AGENTBOX_HOOK_TOKEN`. `06:373`: `AB/run/launch/<terminalID>/<attempt>/`. `08:98` (AR-111): `AGENTBOX_PANE_ID`, `AGENTBOX_RUN_ID`, `AGENTBOX_APP_SOCK`. `08:100` (AR-112): `run/launch/<runID>/`. `07:739` (CS-722): `AGENTBOX_SESSION`. Prevalece 08. Uma retomada já cria um `AgentRun` novo (`01:320`), então `<runID>` faz o papel de `<attempt>`.
Patch: `06:171` **de** `\`AGENTBOX_TERMINAL_ID\`, \`AGENTBOX_HOOK_SOCKET\`, \`AGENTBOX_HOOK_TOKEN\` (correlação, não autenticação)` **para** `\`AGENTBOX_PANE_ID\`, \`AGENTBOX_RUN_ID\`, \`AGENTBOX_APP_SOCK\` (correlação, não autenticação; AR-111)`; `06:373` **de** `Diretório por tentativa: \`AB/run/launch/<terminalID>/<attempt>/\`` **para** `Diretório por tentativa: \`AB/run/launch/<runID>/\` (cada start ou resume cria um run)`; `06:340` `AB/run/launch/<terminalID>/prompt.md` → `AB/run/launch/<runID>/prompt.md`; em 06, `AGENTBOX_TERMINAL_ID` → `AGENTBOX_PANE_ID` nas demais ocorrências (`06:448`, `06:506`); `07:739` `AGENTBOX_SESSION` → `AGENTBOX_RUN_ID`.

**K-72 · Helper MCP.** `07:245`: helper `agentbox-mcp`, "que fala com o `agentboxd`". `06:37` e `08:34`: subcomando `agentbox mcp`, que fala com o app por `run/app.sock`. Prevalece 08 (ver também K-75).
Patch `07:245` **de** `(helper \`agentbox-mcp\`, que fala com o \`agentboxd\`)` **para** `(subcomando \`agentbox mcp\`, que fala com o app por \`run/app.sock\`, AR-106)`.

**K-73 · Rótulos de versão "depois".** `01` usa "Depois"; `05` e `06` usam `later`; `07:7` usa `v1.2+`; `08:9` usa `v2`. Prevalece `later` (é o rótulo da matriz de 05).
Patch: `07:7` **de** `\`v1.2+\` (depois)` **para** `\`later\``, e o mesmo em CS-150 (`07:173`) e CS-175 (`07:195`); `08:9` **de** `**v2** (depois)` **para** `**later**`, e o mesmo em `08:69` e `08:80`. O `ptyd.v2` de AR-904 é major de protocolo e fica como está.

**K-74 · "P2" usado como prioridade.** 00 reserva P2 para "UI em inglês". 02 e 03 usam "(P2)" como prioridade ou fase: `02:110`, `02:266`, `02:469`, `02:848`, `03:339`, `03:347`, `03:538`, `03:1196`, `03:1311`.
Patch: `02:110` e `03:347` `P2` → `v1.1, TA-119` (grupos de tab, 06); `02:266` **de** `(P2: só ⌘-clique na v1)` **para** `(popover de ações: later; na v1 só ⌘-clique)`; `02:469` **de** `Tab fixada (P2)` **para** `Tab fixada (later)`; `03:339` e `03:538` **de** `(P2)` **para** `(later, R3.6)`; `02:848`, `03:1196` e `03:1311` (zoom da UI) `P2` → `later`. Na v1, ⌘= / ⌘- / ⌘0 fora do terminal ficam desabilitados com motivo (PP-1).

---

## 3. Estados de agente, terminal e computador

**K-75 · Onde vivem MCP, Docker, lease e broker.** `06:42` e `08:33` (AR-101): o daemon só hospeda PTYs e não fala com Docker, banco nem hooks; MCP, Docker, git e catálogo ficam no app, que após ⌘Q segue em `.accessory` (AR-108). 07 põe MCP, serviço de boxes, `exec`, log de comandos, reconciliação, revogação de lease, entrega de token, broker git e ponte do container no `agentboxd`: `07:246`, `07:213` (CS-181), `07:324-325` (CS-230/231), `07:549` (CS-410), `07:624` (CS-521), `07:628` (CS-525), `07:636` (CS-530), `07:646` (CS-540), `07:649` (CS-543), `07:681` (CS-605), `07:683` (CS-607). Prevalece 06/08: T1 fala em "daemon de PTY", e o daemon pequeno é a base da AR-130 e do upgrade N-1. O ganho que 07 queria (ferramentas vivas com a UI fechada) já vem do modo `.accessory`.
Patch:
- `07:246` **de** `O MCP do app e o serviço de boxes vivem no **\`agentboxd\`**, não na UI. Fechar o app (P4) não derruba as ferramentas dos filhos.` **para** `O MCP do app e o serviço de computadores vivem no processo do app (\`AgentBoxCore\`, fora da UI), que continua vivo em modo \`.accessory\` depois do ⌘Q (AR-108). Só "Quit Agent Box Completely" derruba as ferramentas; nesse caso \`agentbox mcp\` reabre o app em segundo plano (AR-110).`
- Nos demais CS listados, onde o `agentboxd` aparece como quem fala com Docker, runtime, egress, Keychain ou git: `o \`agentboxd\`` → `o app (\`AgentBoxCore\`)`. Ficam no daemon só os PTYs de `docker exec -it agent dtach …` do modo isolado (CS-501/502), como em `08:61-62`.
- `07:681` (CS-605) **de** `quem escreve é o gate ou o \`agentboxd\`` **para** `quem escreve é o egress ou o app`.
- `07:683` (CS-607) **de** `O socket do \`agentboxd\` aceita só clientes com o mesmo uid **e** requisito de assinatura do peer (app, CLI \`agentbox\`, helper MCP).` **para** `O socket do \`agentboxd\` aceita só o app (AR-503); \`agentbox mcp\` e \`agentbox hook\` falam com \`run/app.sock\`.`

**K-76 · Ponte container → app (v1.1).** `07:646` (CS-540): o gate fala com o daemon por socket do host exposto por porta reversa ou `host.docker.internal` liberado para o gate. `08:88` (AR-107): o app não abre porta TCP; containers não alcançam o app; o app consome a fila do egress por SSE. Prevalece 08: T9 pede logs e gasto "fora do alcance do agente", e nenhuma porta do host fica exposta.
Patch `07:646` **de** `O gate é o único que fala com o \`agentboxd\`, por um socket de host exposto ao gate por mapeamento de porta reverso ou \`host.docker.internal\` liberado **só para o gate** e só para a porta do daemon.` **para** `O egress não alcança o host: ele enfileira hooks e chamadas que dependem do app, e o app consome a fila por SSE na porta admin publicada em 127.0.0.1 (AR-107/AR-113).`; `07:648` (CS-542) **de** `até 10 mil eventos` **para** `até 10 mil eventos ou 15 min (o que vier antes; AR-113)`.

**K-77 · Entrega de segredos ao container.** `07:168` (CS-145), `07:624` (CS-521) e `07:678` (CS-602): `docker exec -i` com stdin para um tmpfs depois do start. `08:450` (AR-512): arquivo `boxes/<id>/token` (0400) montado só leitura em `/run/agentbox/token`; a chave Zyte vai do mesmo jeito. `05:386` (AC-424) e `01:434` falam em "arquivo montado só leitura". Prevalece 08 (2 capítulos contra 1, e o arquivo existe antes do processo subir).
Patch: em CS-145, CS-521 e CS-602, `entregue por \`exec\` com stdin para um tmpfs` / `por \`docker exec -i\` com stdin num tmpfs` → `por arquivo 0400 em \`boxes/<id>/\` (App Support), montado só leitura em \`/run/agentbox/…\` (AR-512)`.

**K-78 · Estados de atividade do agente.** Comparação:

| Estado | 01 §6.3 | 02 §2.6 | 04 M-4xx | 06 §3.1 | 07 CS-321 | 08 `agent_run.status` |
|---|---|---|---|---|---|---|
| iniciando | `starting` "Starting" | (processo `Starting…`) | — | `starting` | `provisioning` | — |
| ocioso | `idle` = `done` visto + 30 min | `idle` > 30 min | `idle` = visto (fade imediato) | `idle` = sem turno | — | `idle` |
| trabalhando | `working` | `working` | `working` | `working` | `working` | `working` |
| precisa de resposta | `needsInput` "Needs input" (+ "esperando prompt") | `needsInput` "Needs you" | "Needs input" | `needsInput(kind)` "Needs input" | `needs_you` | `waiting` / `permission` |
| filhos rodando | `waitingOnSubagents` | igual, glifo `Activity` | igual, com contador | igual, "spinner secundário" | — | — |
| concluído | `done` | `done` | `done` | `done` | `done` | `done` |
| falhou | `failed` | `failed` | `failed` (inclui blocked e interrupted) | `failed(reason)` | `failed` | `failed` |
| bloqueado | — | `blocked` "Blocked" | dentro de `failed` | — | `blocked` | `blocked` |
| interrompido | `interrupted` | `interrupted` | dentro de `failed` | — | — | — |
| sem observação | `unknown` "Status unavailable" | `stale` "No recent update" | `unknown` "State unknown" | `estimated` | — | `unverifiable` |
| parado? | `stalled` (v1.1) | — | — | — | `stalled?` (v1) | — |
| processo saiu | (estado de processo) | (estado de processo) | — | `exited(code)` | `stopped` | — |

Canônico: estados de 01 §6.3 mais `blocked` (só subagente, journal `BLOCKED`, vermelho como em 02), com `estimated` como flag (não estado) para OpenCode e shell (06). `stale` se funde em `unknown`. `exited` é estado de processo (01 §6.2), não de agente. Um agente recém-lançado sem prompt fica `idle`, não `needsInput`, porque 06 mapeia `idle_prompt` sem turno ativo e porque cada tab nova viraria pendência.
Patch:
- `01:526` **de** `O agente pergunta, pede permissão ou fica parado esperando prompt` **para** `O agente pergunta ou pede permissão (subtipos \`question\`, \`permission\`, \`other\`)`; `01:531` **de** `\`done\` visto e sem atividade há 30 min` **para** `\`done\` visto e sem atividade há 30 min, ou agente recém-iniciado sem prompt (após \`SessionStart\`)`; acrescentar a linha `| \`blocked\` | "Blocked" | Subagente com \`BLOCKED\` no diário (CS-260) | Nova nota DOING ou fim |`; na agregação (`01:538`), `\`failed\`` → `\`failed\`/\`blocked\``.
- `02:133` **de** `| \`needsInput\` (pergunta ou permissão) | \`Needs you\` |` **para** `| \`needsInput\` (pergunta ou permissão) | \`Needs input\` |`; `02:140` **de** `| \`stale\` (PTY vivo, hooks calados além da janela) | \`No recent update\` |` **para** `| \`unknown\` (sem hooks, ou hooks calados além da janela) | \`Status unavailable\` (tooltip com o motivo) |`; `02:151` passa à ordem de 01 (com `blocked` junto de `failed`, sem `stale`); `02:600` **de** `("Needs you · 4m")` **para** `("Needs input · 4m")`; em §14.1 e §14.2 (`02:816`, `02:817`, `02:829`, `02:835`), `needs you` → `needs input` quando o assunto é estado de agente (pedido de computador continua `needs you`).
- `03:217` **de** `Claude Code needs you · 4m` **para** `Claude Code needs input · 4m`.
- `04:373` **de** `\`failed\` (inclui blocked/interrupted)` **para** `\`failed\`, \`blocked\`, \`interrupted\``, e acrescentar M-404b: `interrupted` = bolinha `#a1a1a1`, sem animação (02); `04:379` (M-403) **de** `Fica \`done\` até o usuário ver o terminal; então faz fade para \`idle\` em 0,30.` **para** `Fica \`done\` não lido até o usuário ver o terminal; depois de 30 min visto e sem atividade, passa a \`idle\` com crossfade 0,30 (M-406).`; `04:382` (M-406) **de** `Turno encerrado e visto` **para** `\`done\` visto há 30 min, ou agente recém-iniciado sem prompt`; `04:383` (M-407) **de** `"State unknown — hooks not connected"` **para** `"Status unavailable — hooks not connected"` e `04:288` **de** `"State unknown"` **para** `"Status unavailable"` e **de** `"Claude needs your input in fix-arcgis-pagination"` **para** `"Claude Code in fix-arcgis-pagination needs input"` (02 §14.2).
- `06:436` **de** `Ponto âmbar + "Needs input"` **para** `Balão \`?\` laranja + "Needs input" (DS §2.6)`; `06:437` **de** `Spinner secundário` **para** `Glifo \`Activity\` estático (DS §2.6)`; `06:439` **de** `X vermelho + motivo` **para** `Bolinha vermelha + motivo`; `06:440` remover `exited(code)` da tabela (vai para 01 §6.2); `06:443` **de** `Agregação (card de sessão, menu bar, Dock): \`needsInput\` > \`failed\` > \`working\` > \`waitingOnSubagents\` > \`done (unread)\` > \`idle\` > \`exited\`.` **para** `Agregação: a de 01 §6.3.`
- `07:494` (CS-321) **de** `Estados do filho: \`provisioning\`, \`queued\`, \`working\`, \`needs_you\` (…), \`blocked\` (…), \`stalled?\` (…), \`done\`, \`failed\` e \`stopped\`.` **para** `Estado de atividade do filho conforme 01 §6.3 (\`starting\`, \`working\`, \`needsInput\`, \`blocked\`, \`done\`, \`failed\`, \`interrupted\`, \`stalled\` na v1.1). O estado do computador (\`queued\`, \`provisioning\`…) aparece ao lado, na linha do computador (01 §6.4).`
- `08:301` **de** `\`status\` (\`working\`/\`waiting\`/\`permission\`/\`blocked\`/\`failed\`/\`done\`/\`idle\`/\`unverifiable\`)` **para** `\`status\` (\`starting\`/\`idle\`/\`working\`/\`needs_input\`/\`waiting_on_subagents\`/\`done\`/\`failed\`/\`blocked\`/\`interrupted\`/\`unknown\`/\`stalled\`), \`status_kind\` (\`question\`/\`permission\`/\`other\`), \`estimated\` (0/1)`.

**K-79 · Estados de processo/terminal.** 01 §6.2: `launching`, `containerPhases`, `running`, `exited(0)`, `exited(n≠0)`, `killed` "Stopped", `interrupted`, `containerStopped`. 02 §2.7: `starting`, `failedToStart` "Couldn't start", `reattached`, `restoredDead` "Interrupted", `containerPreparing` "Preparing box…", `containerStopped` "Box stopped", `daemonUnavailable`. 08 `terminal.state`: `starting`/`running`/`exited`/`failed`/`lost`. Prevalece 01, com `failedToStart` (02 e 03 §4.6) acrescentado ao domínio; `reattached` não é estado; `daemonUnavailable` é estado de UI.
Patch:
- 01 §6.2: acrescentar `| \`failedToStart\` | "Couldn't start" | Erro de spawn ou de injeção; ações de 03 §4.6 |`.
- `02:161` `starting` → `launching`; `02:166` remover a linha `reattached`; `02:167` `restoredDead` → `interrupted`; `02:168` **de** `| \`containerPreparing\` (isolado, v1.1) | \`Preparing box…\`` **para** `| \`containerPhases\` (isolado, v1.1) | \`Preparing container…\``; `02:169` **de** `\`Box stopped\`` **para** `\`Container stopped\``; `02:164` separar `killed` ("Stopped", pelo usuário) de "sinal externo" (`Killed (<SIGNAME>)`).
- `08:299` **de** `\`state\` (\`starting\`/\`running\`/\`exited\`/\`failed\`/\`lost\`)` **para** `\`state\` (\`launching\`/\`running\`/\`exited\`/\`killed\`/\`failed_to_start\`/\`interrupted\`/\`container_stopped\`)`; em AR-341 (`08:353`) e AR-604 (`08:507`), `lost` → `interrupted`.
- `03:489-490`: `Creating box` → `Creating container`, `The box stopped.` → `The container stopped.`, `[Restart Box]` → `[Restart Container]` (01 e 05 AC-452 já usam "Container stopped · Restart container"; ver D-02).

**K-80 · Estados do computador.** 01 §6.4: `queued`, `provisioning`, `ready`, `inUse`, `stopped`, `failed`, `removed`, `orphan`. 07 `box_status`: `provisioning|queued|ready|stopped|error`. 08 `computer.state`: `creating/running/stopped/removing/removed/orphan/failed`. Prevalece 01.
Patch: `07:260` `error` → `failed`; `08:303` **de** `\`state\` (\`creating\`/\`running\`/\`stopped\`/\`removing\`/\`removed\`/\`orphan\`/\`failed\`)` **para** `\`state\` (\`queued\`/\`provisioning\`/\`ready\`/\`in_use\`/\`stopped\`/\`failed\`/\`removing\`/\`removed\`/\`orphan\`)`.

**K-81 · Sessão no schema.** `01:203-220`: `kind` = `worktree|checkout|folder|clean`, `statusNote`, `unread`, `lifecycle`, `lastViewedAt`. `08:297`: `kind` = `worktree`/`clean`, `CHECK (kind='clean' OR worktree_id IS NOT NULL)` (proíbe sessão `folder` dentro de projeto `folder`), e faltam nota, não lido e ciclo de vida. `project` em 08 (`08:295`) não tem `kind`, `worktree_root` nem `branch_prefix` (01 §5.2). Prevalece 01.
Patch `08:297` **de** `\`kind\` (\`worktree\`/\`clean\`)` **para** `\`kind\` (\`worktree\`/\`checkout\`/\`folder\`/\`clean\`)`; acrescentar `status_note`, `status_note_author`, `status_note_at`, `unread`, `last_viewed_at`, `lifecycle`; trocar o CHECK por `CHECK ((kind IN ('worktree','checkout')) = (worktree_id IS NOT NULL) AND (kind = 'clean') = (project_id IS NULL))`. Em `08:295`, acrescentar `kind` (`git`/`folder`), `worktree_root`, `branch_prefix`, `default_profile_id`.

**K-82 · Atenção.** 01 §5.12 tem `AttentionItem` (com prioridade), `InboxEvent` e `HelpRequest`. 08 tem só `attention` (`08:306`). Prevalece 01.
Patch `08:306`: acrescentar `priority` em `attention` e as tabelas `inbox_event` (`id`, `session_id`, `kind`, `payload_json`, `created_at`, `read_at`) e `help_request` (K-68).

---

## 4. IDs de motion: mapeamento auditoria 06 → 04

02 (`02:5`) e 03 (`03:3`) citam os IDs da auditoria 06 (`A1…F6`, `E0…E4`), mas 04 renomeou tudo para `M-xxx` e não publicou o mapeamento. Atenção: a auditoria 06 usa `D1…D13` no inventário (§1.2) e `D1…D9` no catálogo (§4.D); `02:868` cita `06 D7/D13` (inventário), enquanto `02 §11` cita o catálogo.

| Auditoria 06 | Momento | 04 |
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
| C7 | Janela estreita | sem equivalente (03 §4.6 "Pane estreito" não anima) |
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
| E1 | Indicador de estado do agente | M-401…M-408 (`working` M-401, `waiting` M-402, `done` M-403, `failed`/`blocked` M-404) |
| E2 | Ignição | M-501…M-506 (placeholder: M-503; pular: M-506) |
| E3 | Subagente com Docker | M-213 (linha filha), M-507, M-601 (glifo), M-602 (fila), M-613 (parou) |
| E4 | Computador usado × takeover | M-604…M-611 |
| F1 | Abrir Biblioteca | M-109 |
| F2 | Card → detalhe | M-112 |
| F3 | Tabs internas | M-113 (segmented de 02 §12.12 também) |
| F4 | Salvar | M-809 |
| F5 | Configurações | M-109 |
| F6 | Inbox | M-705 |

Patch em 02:
- `02:5` **de** `aqui só são referenciadas pelo ID do catálogo (os IDs \`A1…F6\` e \`E0…E4\` vêm de \`audit/06-motion.md\` e são mantidos por \`04-motion\`; se \`04-motion\` renomear algum, vale o nome do momento entre parênteses)` **para** `aqui só são referenciadas pelo ID \`M-xxx\` de \`04-motion\` (mapeamento da auditoria 06 em \`review/R1-consistency.md\` §4)`.
- Tabela §11 (`02:513-531`): `D2` → `M-802 / M-210`; `D1` → `M-801`; `B2` → `M-203`; `B3` → `M-206 / M-111`; `C9 (200 ms, fade + 0,95)` → `M-101 / M-102 / M-104`; `C12 + DS3` → `M-105`; `C8` → `M-110`; `C1 / C2 / C3` → `M-301 / M-302 / M-303`; `C4 / C5 / C6` → `M-306 / M-307 / M-309`; `B8` → `M-201`; `E1` → `M-401…M-408`; `E2` → `M-501…M-506`; `E3` → `M-601 / M-602`; `E4` → `M-604…M-611`; `D6` → `M-312`; `D5` → `M-313`; `D9` → `M-812`; `F5` → `M-109`; `F6` → `M-705`.
- Outras citações: `02:121` `C6` → `M-309`; `02:132-137` `E1 working/waiting/done/failed` → `M-401 / M-402 / M-403 / M-404`; `02:168`, `02:176`, `02:770` `E3` → `M-601`; `02:389`, `02:858` `E4` → `M-604`; `02:600` `04-motion E1` → `04 M-401`; `02:618` `C1` → `M-301 / M-304`; `02:677` `F3` → `M-113`; `02:717` `C9` → `M-101 / M-102`; `02:745` `C8` → `M-110`; `02:768` `E2` → `M-503`; `02:769` `D9` → `M-812`; `02:915` `C6` → `M-309`; `02:868` `06 D7/D13` → `audit/06 §1.2 D7/D13 (inventário)`.

Patch em 03 (`M:` → `04 M-`):
`03:3` exemplo `M:C9` → `M-101`; `03:69` e `03:80` `M:B8` → `M-201`; `03:132` `M:B4` → `M-207`; `03:211` `M:B3` → `M-206`; `03:533` `M:B3` → `M-111`; `03:230` `M:B2` → `M-203`; `03:238` e `03:618` `M:C6` → `M-309`; `03:324` `M:C6 no card` → `M-211`; `03:284` `M:E3` → `M-213`; `03:387` `M:C3` → `M-303`; `03:440` `M:C5` → `M-307`; `03:480` `M:E2 regra dos 300 ms` → `M-506`; `03:481` `M:E2` → `M-503`; `03:484` `M:D6` → `M-312`; `03:485` `M:D5` → `M-313`; `03:560` `M:C9 saída; M:E2 chip voa` → `M-102 (saída); M-501 (chip voa)`; `03:780` `M:E4` → `M-604…M-610`; `03:782` `M:D9` → `M-603`; `03:906` `M:F5` → `M-109`; `03:1036` `M:A2` → `M-004`.

Patch em 05: `05:253` (AC-310) **de** `04 E2` **para** `04 M-503/M-506`; `05:294` **de** `(04 E3)` **para** `(04 M-601)`.

Patch interno em 04: `04:378` **de** `Badge de contagem: M-810.` **para** `Badge de contagem: M-701.`

**Test IDs de 04 × convenção de 02 §17 e 03 §22.** 04 inventou outra árvore de identificadores. Prevalece 02/03. Patch em 04 (colunas "Test ID" e `04:783`):

| 04 usa | Canônico (02/03) |
|---|---|
| `sidebar.list` | `sidebar` |
| `sidebar.sessionRow.<id>` (+ `.phase`, `.error`, `.agents`, `.rename`, `.revealGlow`) | `sidebar.session.<id>` (+ mesmo sufixo); pendente: `sidebar.pending.<id>` |
| `sidebar.childRow.<id>` (+ `.connector`) | `sidebar.session.<sessionId>.child.<childId>` (+ `.connector`) |
| `sidebar.agentRow.<id>.lastMessage` | `sidebar.session.<sessionId>.agent.<terminalId>.lastMessage` |
| `sidebar.container`, `sidebar.selection` | `sidebar`, `sidebar.selection` |
| `tabs.tab.<terminalId>`, `tabs.activeIndicator`, `tabs.overflow.*` | iguais (acrescentar os dois últimos em 03 §22) |
| `pane.<terminalId>.cover`, `.rimFlash`, `.attention`, `.zoomPill`, `.feedbackPill` | iguais (acrescentar em 03 §22) |
| `pane.<terminalId>.exitedOverlay` | `pane.<id>.interrupted` |
| `pane.<terminalId>.launchError` | `pane.<id>.startError` |
| `launch.ignition.<terminalId>`, `launch.step.<stepKey>` | `pane.<id>.ignition`, `pane.<id>.ignition.step.<stepKey>` |
| `launch.chip` | `overlay.composer.launchChip` |
| `overlay.scrim`, `overlay.dialog.<name>`, `overlay.dialog.confirm`, `overlay.palette` | `overlay.scrim`, `overlay.<name>`, `overlay.confirm*`, `overlay.palette` |
| `menu.<name>` | `menuPanel.<name>` (`menu.<group>.<action>` já é dos menus do app, 03 §18) |
| `tooltip`, `hoverCard.<kind>.<id>` | `tooltip`, `<host>.hoverCard` (ex.: `sidebar.session.<id>.hoverCard`) |
| `panel.right.<name>`, `panel.tabs.indicator` | `rightPanel.tab.<name>`, `rightPanel.tabs.indicator` |
| `screen.<name>` | `<page>.page` (`library.page`, `computers.page`, `settings.page`) |
| `split.divider.<id>` | `pane.divider.<id>` |
| `box.glyph.<boxId>` | `sidebar.session.<sessionId>.child.<childId>.glyph` |
| `computer.viewer.<id>.connecting` / `.status` / `.disconnected` | `viewer.<computerId>.connecting` / `.status` / `.disconnected` |
| `computer.controlFrame`, `computer.controlPill`, `computer.ghostCursor`, `computer.clickRipple`, `computer.takeControl`, `computer.helpBanner` | `viewer.<computerId>.controlFrame` / `.controlPill` / `.ghostCursor` / `.clickRipple` / `.takeControl` / `.helpBanner` |
| `computers.thumb.<id>` | `rightPanel.computers.thumb.<computerId>` |
| `titlebar.needsYouBadge` | `sidebar.nav.inbox.badge` |
| `menubar.status` | `menuBar.icon` |
| `app.daemonBanner` | `window.daemonBanner` |
| `inbox.item.<id>` | igual |
| `onboarding.step.<name>`, `onboarding.importItem.<n>` | `onboarding.step.<name>`, `onboarding.import.item.<n>` |
| `empty.sessions`, `empty.search`, `empty.<panel>` | `landing`, `sidebar.search.empty`, `<panel>.empty` |
| `banner.docker`, `banner.persistence` | `computers.dockerBanner`, `window.databaseBanner` |
| `form.disclosure.<name>`, `form.field.<name>.error`, `button.<name>` | `overlay.<name>.advanced`, `overlay.<name>.<field>.error`, `<host>.<button>` |

O mesmo vale para 05 e 08:
- `05:776` (AC-T01) **de** `(\`sidebar.session.<id>\`, \`pane.<id>.status\`, \`computer.<id>.takeover\`)` **para** `(\`sidebar.session.<id>\`, \`pane.<id>.header\`, \`viewer.<id>.takeControl\`; convenção de 02 §17)`.
- `08:597` (AR-805): `tab.<id>` → `tabs.tab.<terminalId>`, `tab.<id>.close` → `tabs.tab.<terminalId>.close`, `computer.<id>.viewer` → `viewer.<computerId>`, `computer.<id>.takeover` → `viewer.<computerId>.takeControl`, `overlay.<nome>.primary` → `overlay.<nome>.submit`. `sidebar.session.<id>.status` e `pane.<terminalID>.status` entram em 03 §22. O enum `A11yID` deve ser gerado a partir de 02 §17 e 03 §22.
- Se o dono escolher `Take Over` (D-02), `.takeControl` vira `.takeOver` e `.giveBack` vira `.handBack` em todos os capítulos.

---

## 5. Atalhos de teclado

A referência é 03 §21. Ela bate com o código do Orca: `shared/keybindings/definitions-core-2.ts` define `tab.newTerminal` = ⌘T, `tab.newAgent` = ⌥⌘T e `worktree.history.back/forward` = ⌥⌘←/→.

**K-83 · ⌘T.** `05:221` e `05:263` (AC-313): ⌘T abre um seletor de agente, perfil e prompt. `06:188`: ⌘T abre o lançador. `03:1294` e `03:1174-1175`: ⌘T = New Terminal (shell), ⌥⌘T = agente padrão, ⌥⌘N = Quick Launch (o seletor). Prevalece 03/Orca.
Patch: `05:221` **de** `11. Numa sessão existente, ⌘T abre o seletor de terminal (agente, perfil, prompt opcional) e Enter já abre a tab rodando. ⌘⌥T abre o agente padrão direto.` **para** `11. Numa sessão existente, ⌥⌘N abre o Quick Launch (agente, perfil, prompt opcional) e Enter já abre a tab rodando. ⌥⌘T abre o agente padrão direto; ⌘T abre um shell.`; `05:263` **de** `aperta ⌘T, escolhe "Codex" e Enter` **para** `aperta ⌥⌘N, escolhe "New Codex Tab" e Enter`; `06:188` **de** `⌘T abre o lançador (§2) numa tab nova` **para** `⌥⌘N abre o lançador (Quick Launch, 03 §7) numa tab nova; ⌘T abre shell e ⌥⌘T o agente padrão`.

**K-84 · ⌥⌘ setas.** 03 (`03:46`, `03:82`, `03:1203`, `03:1287`) e o Orca usam ⌥⌘←/→ para voltar/avançar no histórico. `02:801`, `06:186`, `06:235` (TA-112) e `04:364` (M-308) usam ⌘⌥ setas para foco direcional de pane. Prevalece 03/Orca; panes ficam com ⌘] / ⌘[.
Patch: `02:801` **de** `| Panes | \`⌘]\`/\`⌘[\`, \`⌘⌥←↑→↓\` | — |` **para** `| Panes | \`⌘]\`/\`⌘[\` | — |`; `06:186` **de** `⌘] / ⌘[ (próximo/anterior), ⌘⌥←↑→↓ (direcional)` **para** `⌘] / ⌘[ (próximo/anterior)`; `06:235` **de** `⌘]/⌘[ e ⌘⌥setas percorrem todos` **para** `⌘]/⌘[ percorrem todos`; `04:364` **de** `| Clique, ⌘⌥ setas |` **para** `| Clique, ⌘] / ⌘[ |`.

**K-85 · Take Control no viewer.** `04:416` (M-606): `(⌘⇧T no viewer)`. ⇧⌘T é Reopen Closed Tab (`03:1296`); o atalho do takeover é ⇧⌘R (`03:1321`, `01:588`, `07:551`).
Patch `04:416` **de** `(⌘⇧T no viewer)` **para** `(⇧⌘R)`.

**K-86 · ⌘⇧E.** `04:348` (M-211) cita ⌘⇧E para "Reveal in sidebar"; o atalho não existe em 03 §21.
Patch `04:348` **de** `clique em notificação, ⌘⇧E` **para** `clique em notificação, botão \`Reveal Current Session\` do rodapé (03 §2.12)`.

**K-87 · ⌘⇧C.** `03:684` e `03:1316`: ⇧⌘C abre a aba Computers do painel direito (da sessão). `07:579` (CS-440): ⌘⇧C abre o painel global com todas as boxes. 03 tem a página global Computers sem atalho (`03:823`).
Patch `07:579` **de** `\`"Computers"\` (⌘⇧C): tabela de todas as boxes` **para** `Página \`"Computers"\` (nav da sidebar, 03 §12.3): tabela de todos os computadores`; os atalhos ficam como em 03.

**K-88 · Foco inicial do composer.** `05:211` e `05:227` (AC-301): o foco vai para "Prompt" e "abc" digitado aparece lá. `04:487`: `Campo "Project" recebe foco`. `02:720`: "o primeiro campo do overlay". Prevalece 05, porque o aceite testa isso e o fluxo do Orca começa pelo prompt.
Patch: `04:487` **de** `Campo "Project" recebe foco` **para** `Campo "Prompt" recebe foco (AC-301)`; `02:720` **de** `chama \`window.makeFirstResponder\` no primeiro campo do overlay` **para** `chama \`window.makeFirstResponder\` no campo inicial da tela (no composer, o Prompt; nos demais, o primeiro campo)`; acrescentar em 03 §6: `Foco inicial: Prompt.`

---

## 6. Versões v1 / v1.1 divergentes

01 §4 é o capítulo de escopo e prevalece, salvo onde marcado como decisão do dono.

| # | Recurso | Diz v1 | Diz v1.1 ou depois | Fica | Patch |
|---|---|---|---|---|---|
| K-89a | `.worktreeinclude` / copiar `.env*` | `06:623`, `06:720` (TA-505) | `01:129`, `01:189`, `03:304`, `05:222`, `05:317`, `05:889` | v1.1 | `06:623` **de** `- \`.worktreeinclude\` (v1): na raiz do repo` **para** `- \`.worktreeinclude\` (v1.1, R3.4): na raiz do repo`; `06:720` **de** `\| TA-505 \| P1 \| v1 \|` **para** `\| TA-505 \| P1 \| v1.1 \|` |
| K-89b | Fixar sessão (Pin) | `03:200`, `03:249`, `03:1206` | `01:218`, `05:553` (AC-615), `05:915` | v1.1 | Em 03, marcar `Pin Session` / `Unpin Session` / `Pin` como "(v1.1)" (pela regra de `03:9`, não aparecem na v1); o hover do card fica só com `Archive` |
| K-89c | Ações no item da barra de menus | `03:1146-1151` (Take Control, Stop por computador, Pause Notifications) | `01:127`, `05:550` (AC-614), `06:211` | v1.1 | Em 03 §17, marcar o submenu `Take Control`/`Open` dos pedidos, `Computers ▸ … Stop` e `Pause Notifications for 1 Hour` como "(v1.1)" |
| K-89d | Lembrete único após 3 min | `03:648` | `01:417`, `05:505`, `05:547` (AC-613) | v1.1 | `03:648` **de** `pedido de computador sem resposta em 3 min gera **um** lembrete.` **para** `(v1.1) pedido de computador sem resposta em 3 min gera **um** lembrete.` |
| K-89e | Eventos e notificações de PR/checks | `03:631`, `03:989` (`Pull request and checks`) | `06:677`, `06:729` (TA-514), `01:411`, `05:508` | v1.1 (na v1 o chip atualiza, sem evento) | Marcar `03:631` e o switch de `03:989` como "(v1.1)"; em `01:419`, acrescentar "(PR e checks entram na v1.1, R5.4)" |
| K-89f | Abrir no login | `03:940` (`Open at login`) | `01:136` (R8.6), `05:928` | later | Remover `- \`Open at login\` — switch, off.` de `03:940` |
| K-89g | Clonar repositório | `03:1113` (`Clone from URL`) | `06:598` | v1.1 | Em `03:1113`, marcar `Clone from URL` como "(v1.1)" |
| K-89h | `git init` ao converter pasta | `03:1105` | `06:369` | v1.1 | Ver K-34 |
| K-89i | Mover a pasta da sessão para o projeto | `05:762` (AC-1107), `01:226` | `06:368`, `06:417` (TA-214) | v1.1 | Ver K-34 |
| K-89j | Detector de filho parado | `07:494`, `07:528` | `01:131`, `01:533`, `05:392` | v1.1 | Ver K-21 |
| K-89k | Worker leve do app (`agent_spawn mode:"light"`), `agent_wait`, `agent_message`, `agent_stop`, `ask_parent` | `07:304-308`, `07:280` | `01:121`, `01:131`, `01:311`, `05:427` (AC-456) | v1.1 | **Decisão do dono (D-07)** |
| K-89l | Filho Codex com MCP e box | `07:486` (CS-309) | `01:122`, `06:378`, `05:587` (AC-706) | v1.1 | `07:486` **de** `\| P1 \| v1 \|` **para** `\| P1 \| v1.1 \|` |
| K-89m | Custo de modelo por filho e lote | `07:520` (CS-350), `07:522` (CS-352) | `01:126` (R10.2), `05:719` (AC-1006) | v1.1 | Em CS-350 e CS-352, `v1` → `v1.1` |
| K-89n | Lote como entidade (painel, `New batch…`, `batch_*`) | `07:496-497` (CS-323/324), `07:461-463`, `08:304` | `01:132`, `01:441` | **Decisão do dono (D-06)** | — |
| K-89o | Orçamento em níveis (sessão/dia ou lote/mês) | `03:972`, `03:515`, `07:180`, `08:305` | `01:126`, `05:716` (AC-1005) | **Decisão do dono (D-04)** | — |
| K-89p | Isolado visível desabilitado na v1 | `07:66` (CS-002: "Isolated — coming in 1.1") | `03:9` e `03:548` (não aparece), PP-1 (`01:43`: sem "em breve") | Não aparece | `07:66` **de** `Na v1, \`isolated\` aparece desabilitado com o rótulo \`"Isolated — coming in 1.1"\`.` **para** `Na v1, a opção \`isolated\` não aparece (PP-1; 03 §0).` |
| K-89q | Grupos de tab lado a lado | `02:110` e `03:347` (marcados "P2") | `06:192`, `06:242` (TA-119) | v1.1 | Ver K-74 |

---

## 7. Requisitos que contradizem o 00

**K-90 · T5 (modais como overlays) × ⌘Q em `NSAlert`.** `02:737` e `03:1118-1125` usam `NSAlert` no ⌘Q com agentes vivos (botões `Quit` / `Stop All and Quit…` / `Cancel`, sempre). `06:197-205` (TA-115) usa overlay na janela com `[Keep Running]` (padrão) · `[Stop All and Quit]` · `[Cancel]` · `☐ Don't ask again`. `01:673` e `05:597`, `05:607` (AC-801) usam overlay só na primeira vez, com `Keep running` / `Stop all` / `Don't ask again`. Prevalece T5: overlay na janela com os botões de 06 e o texto de 03. `NSAlert` só quando não há janela aberta (quit pelo menu bar ou pelo Dock com a janela fechada). A primeira vez que 01/05 querem é o comportamento padrão do "Don't ask again".
Patch:
- `03:1120` **de** `\`NSAlert\` (escuro). Só aparece se há processos de agente vivos.` **para** `Overlay de confirmação (DS §12.18; \`NSAlert\` escuro só quando nenhuma janela está aberta). Só aparece se há processos de agente vivos e o usuário não marcou "Don't ask again".`
- `03:1123` **de** `- Botões: \`Quit\` (padrão, ↵) · \`Stop All and Quit…\`` **para** `- Botões: \`Keep Running\` (padrão, ↵; fecha a janela e deixa o app em modo accessory) · \`Stop All and Quit…\``.
- `02:737` **de** `- Exceção nativa: **⌘Q com agentes rodando** e erros fatais de inicialização usam \`NSAlert\`` **para** `- Exceção nativa: erros fatais de inicialização, e o ⌘Q quando não há janela aberta, usam \`NSAlert\``.
- `01:673` **de** `"Keep running" (padrão) e "Stop all"` **para** `"Keep Running" (padrão) e "Stop All and Quit…"`; em `05:597` e `05:607`, os mesmos rótulos.

**K-91 · P4 (ícone indica processos ativos) × opção "Never".** `03:939` oferece `Show menu bar icon` = `Never`. Com o app em modo accessory, sem ícone o usuário não teria como saber que há agentes vivos nem como voltar à janela. `06:209` oferece só `Always / While agents are running`.
Patch `03:939` **de** `- \`Show menu bar icon\` — \`Always\` · \`When agents are running\` (padrão) · \`Never\`.` **para** `- \`Show menu bar icon\` — \`Always\` · \`When agents are running\` (padrão).`

**K-92 · P2 (UI em inglês) e DS13 (só tema escuro na v1).** `08:77` usa rótulo de UI em português ("Recarregar ambiente"; patch em K-19). `08:581` (snapshot "claro/escuro") e `08:651` (AR-820: "screenshots claro/escuro") pedem tema claro, que é "depois" (`01:136`, `02:33`).
Patch: `08:581` **de** `claro/escuro, Reduce Motion` **para** `tema escuro (único na v1, DS13), Reduce Motion`; `08:651` **de** `screenshots claro/escuro (via \`ctl screenshot\`)` **para** `screenshots no tema escuro (via \`ctl screenshot\`)`.

Também contradizem o 00, mas ficam com o dono: P5 "computador no mesmo container" × containers separados em 07 (D-08); T11 × `agent_message` colando com Enter (D-07); P7 "token no Keychain" × Vault no SQLite (D-10); T10/PP-6 × `Redirect` da skill antiga (D-11).

---

## 8. Outras divergências técnicas

**K-93 · Resize do PTY: no início ou no fim.** `04:265` (R2): uma transição animada faz um resize **no início**, e o fechamento do painel é a única exceção (`04:511`). `04:339` (M-202): no arrasto, no máximo 1 resize por quadro e debounce de 50 ms ao soltar. `03:441`: "resize do PTY uma vez ao fim (M:§3.4)". `06:190`: "só no fim do arraste ou da animação". `08:557` (AR-710): "ao fim de cada gesto ou animação". Prevalece 04 (dono do motion, com o teste A6 de exatamente 1 resize por transição); para arrasto, M-202.
Patch: `03:441` **de** `resize do PTY uma vez ao fim (M:§3.4)` **para** `um resize do PTY por transição, no início (04 §4 R2; ao fechar painel, no fim)`; `06:190` **de** `Resize do PTY só no fim do arraste ou da animação (06 §3.4).` **para** `Resize do PTY: em transição animada, um só no início (04 R2); em arrasto, no máximo 1 por quadro e o final ao soltar (04 M-202).`; `08:557` **de** `um \`TIOCSWINSZ\` ao fim de cada gesto ou animação` **para** `um \`TIOCSWINSZ\` por transição animada, no início (04 R2), e no arrasto no máximo 1 por quadro mais o final (04 M-202)`.

**K-94 · Panes ocultos anexados.** `06:126`: panes visíveis e os 4 últimos usados ficam anexados (recebem bytes). `08:387` (AR-406), `08:545` e `05:535` (AC-609): panes ocultos não recebem bytes; os K=4 recentes mantêm a **view** em cache. Prevalece 08/05.
Patch `06:126` **de** `Panes visíveis e os últimos 4 panes usados ficam anexados; o resto só recebe eventos (\`subscribe\`).` **para** `Só panes visíveis ficam anexados; os 4 últimos usados mantêm a view em cache e reanexam com snapshot ao aparecer; o resto só recebe eventos (\`subscribe\`, AR-406).`

**K-95 · Quem fala com o daemon.** `06:56`: `ctl` fala com o daemon (handshake `client.kind = app|ctl`, `06:79`). `08:36` e `08:437` (AR-503): `ctl` não fala com o daemon; só o app conecta. Prevalece 08.
Patch: `06:56` **de** `Falar com o daemon fora de \`ctl\`` **para** `Falar com o daemon (nem o \`ctl\`: ele passa pelo app, AR-503)`; `06:79` **de** `"kind":"app|ctl"` **para** `"kind":"app"`.

**K-96 · Fonte da importação do Orca.** `06:740-741` (TA-601): copia `profile-state.db` (SQLite com WAL) e abre a cópia só leitura; `orca-data.json` é fallback e está desatualizado na máquina do dono (parou em 12/10). `08:361` (AR-342): `orca-data.json` como fonte. `05:41` (fixture `F-ORCA`): só `orca-data.json`. Prevalece 06, que conferiu na máquina.
Patch: `08:361` **de** `Fonte: \`~/Library/Application Support/orca/profiles/<perfil>/orca-data.json\` (só leitura; verificado com Orca 1.4.219)` **para** `Fonte: cópia só leitura de \`~/Library/Application Support/orca/profiles/<perfil>/profile-state.db\` (+ \`-wal\`, \`-shm\`), com \`orca-data.json\` como fallback (06 §6.1)`; `05:41` **de** `Cópia anonimizada de \`orca-data.json\`` **para** `Cópia anonimizada de \`profile-state.db\` (e de \`orca-data.json\`, para o fallback)`.

**K-97 · Segredos: Keychain × Vault.** `01:423`: "Valores ficam no Keychain. O banco guarda só referências." `07:623` (CS-520): setup-token num item próprio do Keychain. `05:143` e `05:418`: "vai para o Keychain". `08:443-448` (AR-510/511): um único item de Keychain com a chave mestra; os valores ficam cifrados (AES-GCM) no SQLite; "nada de item por box, por segredo ou por token". Prevalece 08 tecnicamente (evita prompts de Keychain a cada build, 09 §2.5). Como P7 diz literalmente "token de 1 ano no Keychain", a equivalência fica para o dono confirmar (D-10).
Patch (se o dono aceitar): `01:423` **de** `Valores ficam no Keychain. O banco guarda só referências.` **para** `Valores ficam cifrados no banco (AES-GCM) com a chave mestra num único item do Keychain (AR-510/511); nenhum valor em claro no disco.`; `07:623` **de** `guarda num item do Keychain do app (\`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly\`)` **para** `guarda no Vault do app (AR-511)`; em 05, "Keychain" → "Vault do app" (AC-118, AC-453) e o botão `Save to Keychain` → `Save Key`.

**K-98 · Onde ficam os logs da box.** `07:202-204` e `07:172` (CS-149): `~/AgentBox/runs/<session>/<box>/logs/`, escritos pelo egress/app e não montados no container. `08:279`: `boxes/<computerID>/egress/` dentro de App Support. `08:429` (A11): "logs append-only em volume que o agente só lê". `05:374` (AC-420) e `01:111` querem resultado e logs visíveis no host. Prevalece 07, porque o usuário vê no Finder e o agente na box não lê nada (ele consulta por `reqlog_query`).
Patch: `08:279` **de** `boxes/<computerID>/        token (0400), egress/ (só leitura para o app)` **para** `boxes/<computerID>/        token (0400), chave Zyte (0400)` (os logs vão para \`~/AgentBox/runs/<session>/<computer>/logs/\`, 07 §2.8); `08:429` **de** `logs append-only em volume que o agente só lê` **para** `logs append-only no run folder do host, sem montagem no container (CS-149)`.

**K-99 · Estrutura do run folder.** `01:352`: `result.json`, journal, logs e arquivos de `/work` direto na pasta. `03:807`: Files mapeado para `~/AgentBox/runs/<session>/<computer>/`. `07:200-206`: subpastas `work/`, `logs/`, `transcript/` e `box.json`; `result.json` em `work/`. Prevalece 07.
Patch: `01:352` **de** `\`~/AgentBox/runs/<sessão>/<label>/\`: \`result.json\`, journal, request log, command log, arquivos de \`/work\`` **para** `\`~/AgentBox/runs/<sessão>/<label>/\` com \`work/\` (inclui \`result.json\`), \`logs/\`, \`transcript/\` e \`box.json\` (07 §2.8)`; `03:807` **de** `(mapeado para \`~/AgentBox/runs/<session>/<computer>/\`)` **para** `(mapeado para \`~/AgentBox/runs/<session>/<computer>/work/\`)`.

**K-100 · Arquivar a sessão remove ou para os computadores.** `07:58`: apagar **ou arquivar** a sessão remove as boxes. `01:479` e `03:1062`: arquivar para processos e computadores e mantém tudo. Prevalece 01/03.
Patch `07:58` **de** `Apagar ou arquivar a sessão remove as boxes.` **para** `Arquivar a sessão para as boxes (03 §16.2); apagar a sessão as remove.`

---

## 9. Referências cruzadas quebradas ou ambíguas

| # | Onde | Problema | Patch |
|---|---|---|---|
| X-01 | `02:35` | "O glossário de §15" — o glossário é §18 (§15 são as regras anti-AI) | `§15` → `§18` |
| X-02 | `02:483` | `Sparkles` "proibido (§14)" — a regra está em §15 | `(§14)` → `(§15)` |
| X-03 | `02:539` | IDs "seguindo §16" — a convenção está em §17 (§16 é o mapeamento de implementação) | `seguindo §16` → `seguindo §17` |
| X-04 | `02:543` | "Title Case (§15)" — as regras de microcopy estão em §18 | `(§15)` → `(§18)` |
| X-05 | `02:346` | Composer "ver `03 §7`" — o composer é 03 §6 (§7 é Quick Launch) | `03 §7` → `03 §6` |
| X-06 | `02:615` | Renomear inline "regras em `03 §4.4`" — está em 03 §2.11 (§4.4 é a busca) | `03 §4.4` → `03 §2.11` |
| X-07 | `02:639` | Card "em `03 §3.7`" — o card é 03 §2.6 | `03 §3.7` → `03 §2.6` |
| X-08 | `02:843` | Reduce Motion em "`04-motion` §3.3" — é §5 (§3.3 são curvas) | `§3.3` → `§5` |
| X-09 | `02:888` | Janela "(`03 §2`)" — a janela é 03 §1 | `03 §2` → `03 §1` |
| X-10 | `02:916` | Captura de teclado "(`03 §12`)" — é 03 §11.6 | `03 §12` → `03 §11.6` |
| X-11 | `03:357`, `03:716` | Viewer "§12" — o viewer é 03 §11 (§12 são páginas) | `§12` → `§11` |
| X-12 | `03:441` | "M:§3.4" — 04 §3.4 são springs; a regra de resize é 04 §4 R2 | ver K-93 |
| X-13 | `03:284`, `03:288`, `03:298`, `03:734` | "N3", "N4", "N6", "N24" sem prefixo; 08 (auditoria) e 09 têm IDs N com o mesmo número | Prefixar: `audit/08 N3` etc. |
| X-14 | `05:7` | "o dia real da §0.3" — a definição de pronto é §0.4 (§0.3 são fixtures) | `§0.3` → `§0.4` |
| X-15 | `05:859` (AC-T26) | "checklist de fidelidade de 03" — 03 não tem checklist; ela está na auditoria 04 §8 (citada em 02 §15) | `a checklist de fidelidade de 03 (baseada em 04 §8 da auditoria)` → `a checklist de fidelidade da auditoria 04 §8 (referida em 02 §15)` |
| X-16 | `05:181`, `05:516` (AC-204, AC-603), `06:489` | "04 §5.4" aponta para a auditoria 04 (Notificações), mas a spec 04 §5 é Reduce Motion | `04 §5.4` → `audit/04 §5.4` (e o mesmo em `05:229`, `05:522`) |
| X-17 | `05:253`, `05:294` | "04 E2", "04 E3" são IDs da auditoria 06, não da spec 04 | ver §4 |
| X-18 | `06:186`, `06:190`, `08:384`, `08:547` | "04 §2.3", "06 §3.4" são da auditoria, mas parecem capítulos da spec | Prefixar `audit/` |
| X-19 | `08:92` (AR-108) | "cenário E2E, §8.4" — o E2E é §8.3 (§8.4 é CI) | `§8.4` → `§8.3` |
| X-20 | `04:378` (M-402) | "Badge de contagem: M-810" — o badge de atenção é M-701 | ver §4 |
| X-21 | `01:7`, `05:4` e todos os capítulos | "07 #33", "08 N1", "09 D12" etc. são da auditoria, mas os números coincidem com capítulos da spec | Regra única: toda referência à auditoria leva o prefixo `audit/NN` |

Os IDs de requisito e de AC citados nas matrizes de 05 (R*, RT*, AC-*, TA-*, CS-*, AR-*) foram conferidos: todos existem. A exceção é `agent_result` (K-65), que não é ID mas aparece como requisito em `05:979`.

---

## 10. Microcopy menor (patch direto)

- `07` usa "box" em textos de UI: `"Building box image… 2 of 14 steps"` (`07:131`), `"Update box image"` (`07:133`), `"Image out of date — restart box to update"` (`07:135`), `"Docker VM has 8 GB. 15 headless boxes need about 20 GB. Open Docker settings"` (`07:154`), `"Boxes are CPU-bound"` (`07:156`), `"Allow local network for this box"` (`07:166`), `"Keep box for 24 h"` (`07:212`), `"Stopped idle box phoenix-az"` (`07:215`), `"Reserved · waiting for subagent"` / `"Unclaimed box"` (`07:479`), `"Paste to box"` / `"Copy from box"` (`07:562`), `"Fit box to window"` (`07:564`), `"Agents in isolated boxes can read the model token…"` (`07:619`), `"An older 'agentbox' skill … built-in boxes."` (`07:737`). 03 também: `Isolated boxes`, `Test in a Box`, `Agents in isolated boxes can use this token.` (`03:927`). Pela regra de `01:337` (e D-02): "box" → "computer" (modo leve) ou "container" (modo isolado). Exemplos: `"Building computer image… 2 of 14 steps"`, `"Paste to Computer"` / `"Copy Selection from Computer"` (os de 03 §11.2), `"Stopped idle computer phoenix-az"`, `"Isolated agents"`, `"Test in a Container"`.
- `05:600` e `05:625` (AC-807): `"Interrupted by restart"` → `"Interrupted"` (tooltip `Stopped when your Mac restarted.`), como em 01 §6.3 e 03 §2.8.
- `05:807` (AC-T10): `"This worktree is also registered in Orca"` → `"This worktree is also open in Orca."` (03 §16.5); checkbox `"Remove worktree"` → o diálogo de 03 §16.5 (remove por padrão e tem `Keep the branch`).
- `06:781`: `"Orca also shows this worktree"` / `"Orca is open"` → o mesmo texto de 03 §16.5, com a variante `Orca is open.`.
- `05:813` (AC-T12): `"Copy details"` → `"Copy Details"`.
- `08:420` (A2): toast `"A terminal program copied to the clipboard"` → `"<title>" copied to the clipboard.` (02 §3 e 03 §9.4).
- `04:414` e `04:608` (M-604): a pill `"Claude has control"` (agente ocioso há > 10 s) não existe em 02 §2.8 nem em 03 §11.2. Acrescentar em 02 §2.8 como subestado de `agentControl`.

---

## 11. Conflitos que só o dono pode decidir

| # | Assunto | Opções em jogo | Recomendação | Patches se aceitar |
|---|---|---|---|---|
| D-01 | Nome na UI da sessão sem projeto (P10) | `Scratch` (02, 03) × `Clean session` + seção `Sessions` (01, 04, 05, 06) | `Scratch`. "Sessions" ao lado de "Projects", que também contêm sessões, confunde; `kind = clean` fica no domínio | 01: `01:225` `seção "Sessions"` → `seção "Scratch"`; `01:608` `**Clean session**` → `**Scratch session**`; `01:609` `**Projects / Sessions**` → `**Projects / Scratch**`. 04: `04:349` `seção "Sessions"` → `seção "Scratch"`; `04:459` `"New clean session"` → `"New Scratch Session"`. 05: `"Sessions"` → `"Scratch"` (`05:62`, `05:239`, `05:733`, `05:734`, `05:744`); `"New Clean Session"` / `"New Clean Session in Folder…"` → `"New Scratch Session"` / `"New Scratch Session in Folder…"` (`05:733`, `05:737`, `05:756`); `"New clean session"` → `"New Scratch Session"` (`05:74`, `05:149`). 06: `06:365` `"New Clean Session"` → `"New Scratch Session"`; `06:367` `seção "Sessions"` → `seção "Scratch"` |
| D-02 | Uso de "box" na UI e verbos do takeover | (a) "box" nunca na UI, só em ferramentas, logs e pastas (01); (b) "Box" só no modo isolado (02 §18); (c) "box" em todo lugar (07). Verbos: `Take Over`/`Hand Back` (01, 05, 07) × `Take Control`/`Give Back` (02, 03, 04) | (a) com `Computer` e `Container`; verbos `Take Over` / `Hand Back` | §10 (07 e 03). Em 02: `02:964` → `**Take Over** / **Hand Back**` (não usar: Take Control, Give Back); `02:961` → `Box, Container, Sandbox`; `02:962` → `**Container** ("In container")`; `02:462` → `Take Over`; `02:463` → `Hand Back`. Em 03 e 04: substituição global `Take Control` → `Take Over`, `Give Back` → `Hand Back`, `Force Take Control` → `Force Take Over`, `.takeControl` → `.takeOver`, `.giveBack` → `.handBack` (linhas em K-25) |
| D-03 | Ícone na barra de menus com o app fechado por completo | (a) helper de login separado que mantém o ícone (`01:672`, `03:1141`); (b) sem helper: o app fica em `.accessory` depois do ⌘Q e "Quit Agent Box Completely" tira o ícone até reabrir (`06:203-210`, `08:90`) | (b): um processo a menos, sem novo item de login, e P4 fica coberto pelo modo accessory. AC-804 passa a falar do app em accessory | `01:672` **de** `um helper leve mantém o ícone e a contagem enquanto houver processos no daemon; a forma técnica fica em 08.` **para** `depois do ⌘Q o app continua em modo accessory só com o item da barra de menus (AR-108); "Quit Agent Box Completely" remove o ícone até reabrir.`; `03:1141` **de** `Se o app principal está fechado, o ícone é servido pelo helper de login (arquitetura em \`08\`).` **para** `Depois do ⌘Q o app fica em modo accessory e o ícone continua (AR-108); \`Quit Agent Box Completely\` tira o ícone.`; `03:1153` **de** `\`Quit Agent Box\` (agentes continuam)` **para** `\`Quit Agent Box Completely\` (agentes continuam; o ícone some até reabrir)`; `05:616` (AC-804) **de** `**Dado** o app fechado com 3 processos no daemon` **para** `**Dado** o app em modo accessory (depois do ⌘Q) com 3 processos no daemon` |
| D-04 | Orçamento Zyte: níveis e versão | 01 e 05: computador (v1) e depois sessão + dia (v1.1). 03: computador + sessão + dia já na v1 (Settings e status bar). 07 e 08: box + lote + mês na v1 (07 Q5). | v1 só por computador (US$ 1); v1.1 com sessão (US$ 5) e dia (US$ 10). "Mês" sai, porque o dono acompanha gasto por dia na status bar | `07:180` (CS-160): níveis `computer`, `session` (v1.1), `day` (v1.1); `07:361` (`proxy_status`) e `08:305` (`budget.scope` = `computer`/`session`/`day`); `03:972`: `per session` e `per day` marcados "(v1.1)"; `03:515`: `≥ 80% do orçamento diário` → `≥ 80% do orçamento de algum computador` na v1 |
| D-06 | Lote (`Batch`) na v1 | 07 (CS-323/324, `batch_*`, `boxes_reserve(batch:)`) e 08 (`batch` P1) põem na v1; 01 (`01:132`, `01:441`) põe na v1.1 ("na v1 a sessão faz o papel de lote") | v1.1, como 01, com a coluna `batch_id` nula já no schema v1 para não migrar depois | `07:461-463` e CS-323/324: versão `v1.1`; `07:453` (`boxes_reserve`): parâmetro `batch` só v1.1 |
| D-07 | Worker leve do app e mensagens ao filho | 07 põe na v1 `agent_spawn(mode:"light")`, `agent_wait`, `agent_message` (colando no PTY **com Enter**, a pedido do pai), `agent_stop` e `ask_parent` (CS-304…308, CS-280; Q2 já pede decisão porque T11 só cobre clique do usuário). 01 e 05 deixam isso na v1.1 | v1.1. Se for v1.1, a extensão de T11 (pai colando com Enter num worker que ele criou) entra na abertura da v1.1 | `07:481-485` e `07:411`: versões → `v1.1`; `07:755` (Q2): "Quando" → "Antes da v1.1" |
| D-08 | P5 "computador no mesmo container" × containers separados | 07 §6.1 e Q1 mantêm runtime e agent em containers separados na mesma box, para que o lease e o viewer fiquem fora do alcance do shell do agente; 00 P5 diz "computador no mesmo container" | Aceitar a box com containers separados e registrar no 00 que "mesmo container" quer dizer "mesma box". É um desvio literal de uma decisão do dono | Acrescentar em `00:13` (P5): "No modo isolado, 'mesmo container' significa a mesma box: CLI e computador em containers irmãos na mesma rede, com o lease fora do alcance do CLI (07 §6.1)." |
| D-09 | Gerador de nome de sessão sem prompt | adjetivo + substantivo `quiet-harbor` (01 §8.6, 05) × criatura marinha, como o Orca (`sandperch`, 03 §6.2) × `untitled-<n>` (06 §2.7) | Um gerador só para scratch e worktree. Criatura marinha, se o dono quiser o costume do Orca; senão adjetivo + substantivo | Trocar o exemplo nos capítulos perdedores (`01:674`, `03:545`, `05:734`, `05:747`, `06:365`) |
| D-10 | P7 "token de 1 ano no Keychain" × Vault | 08 guarda todos os segredos cifrados no SQLite, com uma chave mestra num item único do Keychain; 01, 05 e 07 falam em Keychain direto | Vault de 08, desde que o dono aceite que "no Keychain" quer dizer "protegido por chave no Keychain" | K-97 |
| D-11 | Opção `Redirect` da skill global antiga | 07 CS-722 troca o link global por uma skill-shim (escrita fora do app, permitida por PP-6 só com clique e backup) | Fora da v1: `Block in Agent Box` já resolve dentro do app e não escreve nada global | `07:739`: remover `"Redirect"` ou marcá-lo `later` |
| D-12 | Comportamento do ⌘Q depois de "Don't ask again" | 01, 05 e 06: ⌘Q só fecha a janela (accessory). 03 §16.10: o padrão é `Quit` | Igual a 01/05/06 (K-90). Fica aqui só porque troca o significado de ⌘Q no macOS (o app não sai) e o dono pode preferir que ⌘Q saia de verdade, com os agentes seguindo no daemon | — |

Itens do 01 §8 ("Pontos que esta spec decidiu e o dono deve confirmar") que outros capítulos já contradizem: o item 4 (helper, D-03), o item 5 (⌘Q na primeira vez, K-90 e D-12) e o item 6 (nome automático, D-09).
