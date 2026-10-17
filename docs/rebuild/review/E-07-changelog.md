# E-07 · Changelog da revisão de `spec/07-computers-and-subagents.md`

Data: 2026-10-16. Editor: só o capítulo 07. Base: `00-decisions.md` (P11–P16), `review/R1-consistency.md`, `R2-coverage.md` e `R3-implementability.md`. O capítulo foi reescrito por inteiro e marcado no topo "Revisado após R1–R3 em 2026-10-16".

## 1. Decisões do 00 aplicadas

| Decisão | O que mudou em 07 |
|---|---|
| P13 (proxy genérico, sem teto) | §2.6 "Orçamento" foi substituída por "Proxies configurados pelo usuário": `ProxyProfile` (HTTP/HTTPS/SOCKS5, host, porta, credenciais no Vault, geo opcional, CA extra, render opcional, preço informativo opcional), presets Zyte proxy / Zyte API / Custom e `"Test Proxy"` (CS-160). Seleção em cascata global → lote → reserva → menu, com lista de proxies permitidos por computador (CS-161). Uso medido pelo egress (requests, túneis, bytes, renders) e custo só informativo ou informado pelo provedor (CS-162). Erros de proxy (CS-163). **Removidos:** níveis box/lote/mês, ledger com reserva, 402 `budget_exhausted`, avisos de 80 %, `"Add $1"`, `HelpRequest(kind: budget)`, `"Raise batch budget"`, `budget_usd` em `boxes_reserve`/`batch_create`, CA-108 antigo, Q5 e a entidade `BudgetLedger`. `proxy_set(mode:"direct"|"zyte")` virou `proxy_set(proxy: ProxyRef)`; `render` virou "render via proxy configurado, se suportado" (`not_supported` sem render; adaptador Zyte API na v1, outros `later`); `source` `zyte-api` virou `render-api`; `via` passa a ser o nome do proxy. Chave Zyte virou "credenciais do proxy", só no egress. Import do `.env` cria um proxy preset Zyte e ignora `ZYTE_BUDGET_USD`. Novo CA-108 (SOCKS5 genérico, 10 mil requests sem corte). |
| P12 (pai envia mensagem com Enter a filho que criou) | CS-307 reescrito: Enter permitido só para filhos criados pelo próprio pai, registro em `logs/messages.jsonl` e na timeline, indicador na tab; para outros terminais vale T11 (`blocked_by_policy`). CS-261 inclui mensagens. CS-543 alinhado. Q2 fechada. |
| P15 (termo "Computer") | Glossário e microcopy: "box" saiu de todo texto de UI (R1 §10): `"Building computer image…"`, `"Update Computer Image"`, `"Image out of date — restart computer to update"`, `"Computers are CPU-bound"`, `"Allow Local Network for This Computer"`, `"Keep for 24 Hours"`, `"Stopped idle computer …"`, `"Unclaimed computer"`, `"Paste to Computer"` / `"Copy Selection from Computer"`, `"Fit Computer to Window"`, `"Agents in isolated containers…"`, `"Attach Computer"`. "box" ficou só em ferramentas, labels, logs e pastas. |
| P16 / R1 item 7 (K-66, K-75, K-76) | MCP e Docker no **app** (`AgentBoxCore`, `.accessory` após ⌘Q); `agentboxd` só PTY (inclui os PTYs do isolado). Sidecar renomeado `gate` → `egress` (imagem `agentbox-egress`, `egress:3128`, `egress:8790`). Ponte do isolado: egress não alcança o host, app consome fila SSE (CS-540), retenção 10 mil eventos ou 15 min (CS-542). Helper `agentbox mcp` por `run/app.sock` (K-72). Socket do daemon só aceita o app (CS-607). Todas as menções a `agentboxd` falando com Docker, runtime, Keychain ou git trocadas para o app. |
| P11 | Seção "Sessions" para sessões limpas citada no diagrama de relações. |

## 2. Patches de R1 aplicados

- **K-65** ferramentas canônicas: declaração explícita no topo do §3 de que os nomes de 07 são os canônicos e lista dos nomes que não existem; `already_claimed` com `details.owner`.
- **K-67** portas `3128`/`8790` mantidas, host `egress`.
- **K-68** entidades: `Computer` em vez de `Box`, sem `BudgetLedger`/`JournalEntry`/`CommandRecord`/`RequestRecord` no SQLite (logs append-only); entram `ProxyProfile`, `ComputerQueue` e `ProxyUsage` (CS-001).
- **K-69** display `http`/`headless`/`desktop` e parâmetro `display` em `boxes_reserve`, `box_claim`, `box_status`, `computer_mode`, `agent_spawn`, `batch_create`.
- **K-70** labels `agentbox.computer`, `agentbox.computer_name`, `agentbox.role=runtime|work|egress|agent`; `owner=<installId>`.
- **K-71** `AGENTBOX_SESSION` sumiu junto com o `Redirect` (D-11); correlação por `AGENTBOX_RUN_ID`.
- **K-73** `v1.2+` → `later` (CS-150, CS-175, render de outros provedores).
- **K-77** segredos por arquivo (ver §4 abaixo).
- **K-78 / K-80** estados canônicos: atividade do filho = 01 §6.3 + `blocked` (CS-321, tipo `ActivityState`); estado do computador = 01 §6.4 (`BoxState`, `error` → `failed`); estados do pedido de ajuda = 01 §6.5 (`HelpStatus`: `open|taken_over|resolved|declined|cancelled|expired`).
- **K-21** stalled em 10 min e v1.1.
- **K-25 / D-02** par `"Take Over"` / `"Hand Back"` (recomendação de R1, por P16), `"Force Take Over"`, IDs `.takeOver` / `.handBack`.
- **K-40 / D-11** opções da skill antiga: `"Block in Agent Box"` (padrão) · `"Disable Globally…"` · `"Keep"`, texto de 03; `"Redirect"` → `later`.
- **K-41** `"Docker isn't running"` / `"Start Docker"`; código `docker_unavailable`.
- **K-44** soltar teclado com ⌘⎋ ou ⌃⌥, selo `"Keyboard captured · ⌃⌥ to release"`.
- **K-56** `"Waiting for memory · 3 of 15 queued"`, viewer `delayed` / `"Slow connection"`, `"Reconnecting…"`.
- **K-57** `"Decline…"` com `decline_reason`; `mfa` mantido; `budget` saiu dos tipos.
- **K-58** "faixa Computers" → aba `"Computers"` do painel direito (03 §10.4), hover M-612.
- **K-59** abas do filho de CS-320 declaradas canônicas.
- **K-61** `"Watch"` → `"Open Viewer"`.
- **K-62** pill `"You're in control"` com `"Hand Back ⇧⌘R"` (sem faixa âmbar).
- **K-87** página `"Computers"` pela nav da sidebar; ⇧⌘C fica para a aba da sessão.
- **K-89** versões conforme 01 §4: CS-002 (isolado não aparece na v1), CS-004 (Codex v1.1), CS-309 v1.1, CS-350/352 v1.1, CS-321 stalled v1.1, D-07 → CS-280/304/306/307/308 v1.1. Lembrete de 3 min marcado v1.1 (CS-430).
- **K-98 / K-99** run folder em `~/AgentBox/runs/…` mantido; segredos fora dele, em App Support `boxes/<id>/`.
- **K-100** arquivar a sessão para os computadores; apagar remove.
- **K-51** notificação de computador: `"<session> — <computer> needs you"`, corpo `"<Kind> on <host>"`.
- **K-60** rótulos de modo `"On This Mac"` / `"In Container"` no glossário e em CS-609.
- **D-10** Vault (08 AR-510/511) em vez de item de Keychain por token (CS-520, CS-524, CS-532, segredos de tarefa), registrando que é assim que 07 cumpre "no Keychain" de P7.
- **§4 (IDs de acessibilidade)**: nova §5.6 cita os IDs da lista canônica de 03 §22 (com `.takeOver`/`.handBack`) e lista os IDs propostos para superfícies que 03 §22 ainda não tem.
- **X-21** referências à auditoria com prefixo `audit/NN`.

## 3. Patches de R2 aplicados (itens atribuídos a 07)

- **SEM #2 (audit/08 N21)** notificação de lote concluído: CS-326 + CA-306.
- **SEM #3 (audit/01 Y4)** validação de caminhos contra `../` e symlinks, no container e no host com `O_NOFOLLOW`: CS-234 + CA-207, citada em CS-212, CS-262, CS-423.
- **SEM #4 (audit/01 V7)** backup automático do perfil nomeado quando o Chromium sobe de versão, com `"Restore Previous Profile"` e `"Use Previous Image"`: CS-176 + CA-111. Inclui V9 (perfil corrompido) e a declaração de V6 (sem cifra em repouso na v1).
- **SEM #5 (audit/01 R9)** regras de conduta do worker (APIs oficiais primeiro; nunca comprar, criar conta, alterar conta, contatar pessoas; login só pelo humano): CS-331 + CA-307.
- **SEM #12** spike `codex exec-server` (S7). **SEM #13** SSH no container sem repassar ssh-agent (CS-535).
- **Parcial cap.37** retomar filho nativo que não volta: CS-185 (`previous_run` no `box_claim`).
- **Parcial AC-406/CS-132** capacidade: conta de referência explícita em §2.4 (15 × 1,2 + 2 × 2,2 = 22,4 GiB; recomendação 26 GB; aceites de carga em 28 GB; VM de 8 GB → 4 headless e o 5º na fila). CA-103, CA-104 e CS-132 seguem a conta; estimativas fixas nos testes (CS-130). CA-502 ganhou o dimensionamento do modo isolado (40 GB).
- **Parcial 08 N7 / lote** lote na **v1** (decisão do dono passada nesta rodada: ele usa lotes de ~15), com `batch_*`, painel e `"New Batch…"`.
- **Parcial R10.3** orçamento: resolvido por P13 (removido).
- **Parcial 05 b8 / R7.4** MCP no Codex: v1.1 (CS-004).

## 4. Patches de R3 aplicados

- **§11.3 Segredos — escolha: arquivo no host montado só leitura** (não tmpfs via `docker exec -i`). Justificativa escrita em §7.2: existe antes do processo subir (sem corrida), sobrevive a restart sem o app, é o que P7 pede literalmente ("arquivo read-only") e o que 08 AR-512 já especifica, e evita exec sequestrado no caminho crítico. O valor em disco fica em App Support `boxes/<id>/` (0700/0400), fora do run folder, montado só no container que usa e apagado com o computador. Fallback se o uid do container não ler o bind no virtiofs: volume populado por `PUT /archive` (spike S8). Fórmula do token alinhada com 08: `HMAC(master, "box|"+id+"|"+generation)` (CS-601).
- **§11.10** Engine API: detecção do contexto sem o CLI (lê `~/.docker/config.json` e `contexts/meta`), exec com stdin por upgrade/hijack especificado (CS-102, spike S9); exceções declaradas de `docker exec -it` dentro de PTY (`"Open Shell"`, attach do isolado).
- **§11.6** schema: tabelas de computador numa migração `v2_computers` da Fatia 3 (CS-001).
- **§11.5** admissão: 07 mantém a soma das estimativas e registra que 08 AR-407 deve segui-la (CS-130).
- **§11.12** S1 antecipado para a Fatia 0.
- **§6.2** marcadores "(verificar)" mantidos, todos ligados a um spike de §9.

## 5. Não aplicado, e por quê

| Item | Motivo |
|---|---|
| Q1 (container separado × P5 "mesmo container") / R1 D-08 | Mantida **aberta** para a abertura da v1.1, como pedido. 07 registra a proposta (mesmo computador, containers irmãos) e a alternativa (lease cooperativo com aviso). |
| R1 D-06 (lote na v1.1) | Contrariado por decisão do dono nesta rodada: lote fica na v1. **01 §4.2 ainda lista o lote na v1.1** e precisa ser ajustado pelo editor de 01; 08 `batch` (P1) já está compatível. |
| R1 D-04 (orçamento computador → sessão/dia) | Superado por P13: não há teto de orçamento. |
| R1 K-42 (microcopy de orçamento) | Superado por P13. |
| `agent_message` para filho nativo já na v1 | Não aplicado: P12 decide **o quê**, não a versão; 01 §4.2 (R4.11) e R1 D-07 põem mensagens e workers na v1.1. Na v1 o filho nativo fala com o pai pelo harness e pelo diário. |
| Microcopy `statusBar.proxySpend` | Mantido o ID atual de 03 §22, com nota para usar o nome final se o editor de 03 renomear para uso (sem gasto). |
| IDs novos do painel de lote, `"New Batch…"` e Settings › Proxies | Propostos em §5.6, mas não inventados como canônicos: precisam entrar em 03 §22 (editor de 03). |
| Verbos em 03 (`Take Control`/`Give Back`) | 07 já usa `Take Over`/`Hand Back` (R1). A troca em 02/03/04 é dos editores desses capítulos. |
| Settings › Computers › Proxies | Nome da seção depende de 03 §14 (editor de 03); 07 cita "nome final em 03 §14". |
| R2 N6 (tabela de capacidades por harness por versão) | Baixa severidade; os requisitos já marcam Claude v1 e Codex v1.1. Fica para quando S1 e os spikes de Codex rodarem. |
| R2 SEM #14/#15 detalhados (recuperar perfil corrompido, proteção em repouso) | Cobertos de forma mínima em CS-176 (restore do backup; declaração de que não há cifra em repouso na v1). Cifra de volume: não planejada. |
| R3 §11.4 (`~/AgentBox/runs` × App Support) | Mantido `~/AgentBox/runs` (R1 K-98 decide a favor de 07). Ajuste de 08 AR-301 é do editor de 08. |
| R3 §11.2 (publicação só pelo egress × API/VNC/admin publicados em 08) | 07 mantém só o egress publicado (com API e VNC por reverse proxy), compatível com R1 K-76 ("porta admin publicada"). O ajuste de 08 AR-107/AR-311 (`api_port`, `vnc_port`) é do editor de 08. |
| Ajustes em 01, 03, 05, 06 e 08 que R1 lista "a partir de 07" | Fora do escopo deste editor (só 07). |
