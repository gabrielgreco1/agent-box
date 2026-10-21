# Dores de quem trabalha com dados e scraping, e onde o Racky entra

Estudo de 2026-10-20, feito só com pesquisa na web (mais de 60 fontes, lista no fim).

**Como ler:**
- Não foi possível abrir Reddit, G2, Product Hunt nem X: o Reddit bloqueia busca e leitura, e não achei avaliações dos orquestradores no G2 nem no Product Hunt. As citações vêm de Hacker News, issues do GitHub, pesquisas de mercado, blogs e páginas de preço.
- Números publicados por empresas que vendem o produto estão marcados como "vendor".
- As notas de frequência e severidade são julgamento a partir da quantidade de fontes e de reações nas issues, não estatística.
- A evidência é forte para scraping, média para dados com agentes de código e fraca para "orquestrador feito para dados". Quase ninguém discute esse último ainda, o que é uma lacuna de evidência e também um sinal de nicho vazio.

## Números que resumem

- **Uso alto, confiança baixa:** 82% dos engenheiros de dados usam IA todo dia, mas só 64% passaram de tarefas pontuais (State of Data Engineering 2026).
- **Medo de alucinação:** 71% dos analytics engineers temem que uma saída inventada chegue aos stakeholders, e "priorizar confiança" subiu de 66% para 83% (dbt, 2026).
- **Confiança em queda:** a confiança na precisão da IA caiu de 40% para 29% (Stack Overflow 2025). A maior frustração é "quase certo, mas não exatamente".
- **Custo de scraping subindo:** 65,8% aumentaram o uso de proxy e 58,3% viram o gasto subir; mais de 62% gastam mais em infraestrutura, puxados por anti-bot mais forte (Apify, vendor).
- **Pouca IA no scraping:** 54,2% ainda não usam IA para coletar, por desconfiança nos resultados, custo e instabilidade (Apify, vendor).
- **Custo em degraus:** o custo por página bem-sucedida subiu 133%. Quando o site endurece, o custo sobe cerca de 10x com proxy residencial ou navegador, 25x com os dois e de 30x a 50x com bypass completo (ScrapeOps, vendor).
- **Incidentes com agentes:** 65% das empresas tiveram ao menos um incidente com agente no ano, e em 61% deles o impacto foi exposição de dados (Cloud Security Alliance).

## 1. Dados com agentes de código

- **O agente não vê os dados.** Ele não roda a query, então o engenheiro cola amostras no contexto. "Cursor is really good at writing code, but it can't execute queries on your behalf" (SYNQ, no blog do dbt).
- **Colunas e tabelas inventadas,** e falta de contexto do dbt. "LLMs hallucinate, so they can't be the thing producing your numbers" (HN 48358336).
- **Credenciais e produção.** É a dor de severidade máxima:
  - O caso Replit apagou 1.206 registros em pleno code freeze.
  - Um agente apagou o banco de produção e os backups em 9 segundos com um token achado num arquivo.
  - Um agente de notebook foi atrás da string de conexão sozinho (HN 48501759).
  - "credential exfiltration is not [recoverable]" (HN 46884228).
- **Notebooks:** o Claude Code insere células no lugar errado, não usa o kernel e uma saída de 500 MB estoura o contexto (várias issues no GitHub).
- **Jobs longos sem estado de falha:** "when it doesnt there's no failure state" (HN 45577592).
- **Custo e limites:** "Instantly hitting usage limits with Max" tem 695 👍 e 1.499 comentários; no Codex, "Burning tokens very fast" tem 630 comentários.

## 2. Orquestradores (Orca, Conductor, T3 Code, Claude Squad, vibe-kanban)

- **Orca:** pede sandbox Docker para rodar agentes (23 👍), modo headless ou servidor (25), várias assinaturas do Claude (23), multi-repo (78 e 40) e uma interface de chat porque terminal com worktrees é "clunky".
- **Conductor:** só roda no Mac, ainda não tem notificações e worktrees em paralelo ficam bagunçadas. "Duplicating well tuned Github functionality" (HN 46029331).
- **T3 Code:** pedem visibilidade de uso e quota, notificações, a opção de corrigir o rumo do agente durante a execução, imagem Docker e mais provedores. Sobre o mercado: "everyone is literally building the same shit" (HN 49983772).
- **Claude Squad e vibe-kanban:** há sinais de abandono e falhas de tmux, e os usuários querem preparar o worktree com `.env` e portas isoladas.
- **O que falta para dados, por inferência:**
  - Isolar banco, portas e ambiente, não só arquivos.
  - Prévia e diff de dados, não só de código.
  - Jobs longos e agendamento.
  - Execução remota e sem tela.
  - Credenciais por sessão.

## 3. Scraping em escala

- **Anti-bot é a dor nº 1.**
  - "you will get blocked by Cloudflare on week 2" (HN 38823766).
  - "Headless browsers are laughably easy to detect" (HN 45369261).
  - O browser-use tirou o stealth das versões novas; a PR que trocou para patchright subiu o score de confiança de 0 para 69.
  - O Crawl4AI não passa pelo Cloudflare nem com stealth ligado.
- **Humano no loop:** a issue do browser-use que pede pausar, aprovar e assumir o navegador (18 👍, 24 comentários) é o sinal mais direto do diferencial do Racky de assumir o controle.
- **Manutenção quando o site muda:** "it's insane to maintain all of that" (HN 44086884).
- **Custo do LLM por página:** o Stagehand chama o modelo em toda página; pedem para gerar um "plano de extração" reutilizável sem LLM (16 👍).
- **Agentes de navegador ainda falham muito:**
  - "almost no task over a hundred different attempts, succeeds" (HN 47119510).
  - Cada clique custa uma volta inteira do modelo.
  - O agente reaprende o site do zero a cada visita.
- **Jurídico:**
  - Google contra SerpApi: a juíza rejeitou as alegações sobre resultados simples e agregados; o Google reapresentou em agosto.
  - O Cloudflare passou a bloquear crawlers de IA por padrão em páginas com anúncio (fonte secundária).
  - No Scrapy, um crawl padrão fez 38 mil pedidos em 17 minutos ignorando o erro 429.

## 4. Qualidade e entrega

- **Dado ruim silencioso:** "decisions based on incomplete data they didn't know was incomplete". Seletores mudam no meio de testes A/B.
- **Testar dados é difícil:** muitos times não sabem testar bem, e o excesso de alertas cansa (SYNQ). Para 51% das lideranças, qualidade de dados é a prioridade de 2026.
- **Origem de cada linha e versões:** não achei evidência direta dessa dor; fica como hipótese a validar.

## 5. Times e empresas

- **Shadow AI:** 59% têm uso de IA não autorizado confirmado ou suspeito, e 70% suspeitam de vulnerabilidades no código gerado.
- **Desligar agentes:** só 21% têm processo formal para isso, e 82% descobriram agentes que ninguém conhecia.
- **Governança é paga:** auditoria, SSO e BYOK só aparecem nos planos Enterprise (Hex, Kernel, Browser Use).

## 6. Concorrentes

| Player | O que faz | Entrada | Espaço para o Racky |
|---|---|---|---|
| Apify | Catálogo de scrapers e infra | US$ 19 a US$ 999/mês; residencial US$ 7 a 8/GB | Não é agente que escreve e conserta o scraper com humano no loop |
| Browserbase | Navegadores na nuvem | US$ 20/mês (100 h) | Só infra de navegador |
| Browser Use Cloud | Agente de navegador na nuvem | US$ 0,02/h; residencial US$ 5/GB | Sem fluxo de dados nem entrega |
| Firecrawl | API de scrape e crawl | US$ 19 a 99/mês por créditos | Sem agente de código nem VM por tarefa |
| Hyperbrowser, Steel, Kernel | Navegador na nuvem | US$ 0,10/h; proxy US$ 10/GB | Só infra; stealth caro ou só no Enterprise |
| Bright Data, Zyte | Proxies e desbloqueio | Zyte: US$ 1 a 16 por mil páginas renderizadas | Sem orquestração de agentes |
| Diffbot | Extração e grafo de conhecimento | US$ 299/mês | Dados prontos, não "seu scraper" |
| Hex, Julius, Deepnote | Notebook ou análise com IA | Hex US$ 36/editor | Sem navegador nem scraping; Julius tem créditos opacos |
| Databricks, Snowflake | Assistente dentro da plataforma | Pay-as-you-go | Preso ao ecossistema deles |

**Leitura:**
- Infra de navegador virou commodity, entre US$ 0,02 e US$ 0,12 por hora.
- Nas fontes lidas, ninguém vende um orquestrador de agentes de código para profissionais de dados com VM isolada por subagente, navegador furtivo e humano assumindo o controle.

## 7. As 15 dores que mais combinam com o Racky

Pontos = frequência × severidade × encaixe com o Racky, cada um de 1 a 5.

| # | Dor | Pontos | Feature no Racky |
|---|---|---|---|
| 1 | Anti-bot, CAPTCHA, headless detectado | 125 | Fila de CAPTCHA com humano assumindo; perfil por site salvo para o agente retomar |
| 2 | Scraper quebra quando o site muda | 100 | Receitas versionadas com testes de contrato; um subagente de conserto abre sozinho e propõe o diff |
| 2 | Credenciais e produção nas mãos de agentes | 100 | Cofre por computador: segredos entram só para hosts aprovados; banco só leitura gerenciado; nenhum `.env` dentro da VM |
| 4 | Custo por página (proxy, navegador, LLM) | 80 | Escada de custo: HTTP → TLS impersonado → navegador → navegador com residencial, subindo só quando falha; custo por receita |
| 4 | Tokens e limites de assinatura | 80 | Orçamento por subagente, teto por tarefa; gerar o scraper uma vez e rodar sem LLM |
| 6 | Confiança e alucinação | 75 | Prova de execução: toda resposta traz query, linhas e schema; um segundo subagente tenta quebrar |
| 7 | Dado ruim silencioso, schema que muda | 64 | Contrato por lote: nulos e distribuição por execução, diff entre execuções, alerta |
| 7 | Agentes de navegador caros e instáveis | 64 | Gravar e repetir: explora uma vez, salva o caminho como script; LLM só na falha |
| 9 | Jobs longos e notebooks | 60 | Jobs duráveis na VM que sobrevivem ao app fechado, com aviso e retomada |
| 10 | Contexto de schema | 48 | Catálogo local: o Racky lê o warehouse só leitura e injeta resumo e amostras mascaradas |
| 10 | Governança e auditoria | 48 | Trilha por subagente: comandos, rede, arquivos e dados lidos, exportável |
| 12 | Isolamento além do git | 45 | VM por subagente com banco de teste e portas próprias, descartável |
| 13 | Jurídico e robots | 36 | Perfil de conformidade por domínio: robots, crawl-delay, limite de taxa, registro |
| 13 | Entrega ao warehouse | 36 | Destinos com idempotência, dedupe por chave e versão do dataset |
| 15 | Execução remota ou headless | 30 | Modo servidor: VMs na nuvem ou numa máquina remota, Mac só controla |

## 8. Jobs to be done

1. Quando preciso de dados de 500 sites com defesas diferentes até sexta, quero um agente por site em sua VM e só intervir nos CAPTCHAs, para entregar sem montar uma frota de proxies.
2. Quando um scraper em produção quebra de madrugada, quero que um agente reproduza, conserte e rode os testes de contrato, para acordar com um diff e não com um incidente.
3. Quando dou acesso ao warehouse a um agente, quero que ele só leia o necessário e que os segredos não saiam da VM, para não repetir o caso do banco apagado.
4. Quando o agente me entrega um número, quero ver a query, as linhas e a checagem de um segundo agente, para defender o resultado.
5. Quando o custo por página sobe, quero ver por receita para onde vai o dinheiro e cair para a rota mais barata que funciona, para manter a margem.

## 9. Personas

Hipóteses montadas a partir dos padrões do estudo, não de entrevistas.

**Marina, engenheira de dados de web data numa empresa de inteligência de preços (time de 4)**
- **8h:** dois sites deram 403 de madrugada.
- **9h30:** o custo do site mais difícil subiu, então ela leva só aquelas páginas para navegador com proxy residencial.
- **11h:** um subagente achou um endpoint JSON escondido, e ela aceita o diff.
- **14h:** resolve um CAPTCHA na VM.
- **17h:** a validação bloqueou a entrega porque os nulos de um campo dobraram.

**Rafael, analytics engineer numa fintech (dbt e Snowflake)**
- Cola amostras de dados no contexto porque o agente não roda queries.
- A segurança só libera acesso de leitura.
- Quer testes em cada modelo e um segundo agente tentando quebrá-lo.

**Camila, cientista de dados em consultoria (freelancer ou time pequeno)**
- Coleta dados públicos de dezenas de portais, sem orçamento para Bright Data.
- Já se frustrou com créditos opacos e resultados que mudam a cada execução.
- Precisa saber a origem de cada linha: URL, quando e com qual versão do scraper.

## 10. O que muda no plano do Racky

O estudo confirma a ordem combinada (dados, receitas e fila, proxies, entrega, cloud, UI). Ele também traz quatro itens que não estavam no plano e combinam muito com o Racky:

1. **Cofre de segredos com saída filtrada:** a dor nº 2, de severidade máxima. A base já existe, porque o Racky já injeta segredos e já registra toda a rede do computador. Entra junto com proxies e perfis.
2. **Escada de custo automática:** HTTP, depois TLS impersonado, depois navegador, depois navegador com proxy residencial, subindo só quando falha. Entra nas receitas.
3. **Testes de contrato e conserto automático das receitas:** a dor nº 2. Também entra nas receitas.
4. **Verificador independente:** um segundo subagente confere o resultado do primeiro. Entra nos Datasets, porque a origem por linha já vai existir.

Também ganham força os jobs duráveis (computadores que sobrevivem ao app fechado, item já conhecido) e o modo servidor (VMs remotas), que encaixa na infra de cloud.

## Lacunas

- Reddit, G2, Product Hunt e X não foram verificados.
- O texto das citações do HN veio de um modelo que resume as páginas; conferir antes de publicar.
- Os relatórios completos da Zyte, da SYNQ e da Precisely/Drexel não foram lidos, só os resumos.
- Os preços da Bright Data e da Deepnote não foram confirmados.
- Não verifiquei se os concorrentes de navegador na nuvem permitem um humano assumir o controle.
- A mudança do Cloudflare vem de fonte secundária.
- Não há evidência primária da dor de "origem de cada linha" nem de dados pessoais com agentes.

## Fontes

**Pesquisas:**
- [dbt State of Analytics Engineering 2026](https://www.getdbt.com/blog/new-dbt-labs-report-finds-ai-driven-acceleration-is-outpacing-trust-and-governance)
- [dbt: agentic coding](https://www.getdbt.com/blog/agentic-coding-in-analytics-engineering)
- [State of Data Engineering 2026](https://joereis.substack.com/p/the-2026-state-of-data-engineering)
- [Stack Overflow 2025](https://stackoverflow.blog/2025/07/29/developers-remain-willing-but-reluctant-to-use-ai-the-2025-developer-survey-results-are-here/)
- [Apify Web Scraping Report 2026](https://blog.apify.com/web-scraping-report-2026/)
- [Zyte 2026](https://www.zyte.com/whitepaper-ebook/2026-web-scraping-industry-report/)
- [ScrapeOps](https://thewebscrapinginsider.beehiiv.com/p/the-web-scraping-insider-5)
- [Cloud Security Alliance](https://cloudsecurityalliance.org/artifacts/autonomous-but-not-controlled-ai-agent-incidents-now-common-in-enterprises)
- [Shadow AI](https://securityboulevard.com/2026/03/purple-book-community-and-armorcode-survey-flags-shadow-ai-ai-generated-code-risks)

**Artigos:**
- [Browser Use, um ano](https://browser-use.com/posts/one-year-of-progress)
- [Tiger Data](https://www.tigerdata.com/blog/ai-agent-production-database-access)
- [GitGuardian](https://blog.gitguardian.com/ai-agents-security-for-developers-dont-let-your-agents-become-a-liability)
- [Zed](https://zed.dev/blog/anthropic-subscription-changes)
- [Scrapers que quebram](https://current.tinyfish.ai/issue/7/foundations/article/5941/when-scrapers-break-clean)
- [PromptCloud](https://www.promptcloud.com/blog/data-accuracy-in-web-scraping-challenges-2026/)
- [Google contra SerpApi](https://ppc.land/google-loses-dmca-bid-to-treat-search-scraping-like-dvd-piracy/)
- [Cloudflare](https://dev.to/simon_paxton/cloudflare-is-blocking-many-ai-crawlers-by-default-on-ad-supported-pages-not-charging-them-4hcm)
- [Incidente Replit](https://oecd.ai/en/incidents/2025-07-19-1eb1)
- [Anthropic](https://claude.com/blog/how-anthropic-teams-use-claude-code)
- [Orca vs Conductor](https://superset.sh/compare/orca-vs-conductor)
- [Julius](https://popularaitools.ai/blog/julius-ai/)

**Preços:**
- [Apify](https://apify.com/pricing)
- [Browserbase](https://www.browserbase.com/pricing)
- [Browser Use](https://browser-use.com/pricing)
- [Firecrawl](https://www.firecrawl.dev/pricing)
- [Hyperbrowser](https://www.hyperbrowser.ai/pricing)
- [Steel](https://www.steel.dev/pricing)
- [Kernel](https://www.kernel.sh/pricing)
- [Zyte](https://www.zyte.com/pricing/)
- [Diffbot](https://www.diffbot.com/pricing/)
- [Hex](https://hex.tech/pricing/)
- [Conductor](https://www.conductor.build)
- [Orca](https://www.onorca.dev)

**Issues do GitHub:**
- [browser-use #3074](https://github.com/browser-use/browser-use/issues/3074)
- [browser-use #857](https://github.com/browser-use/browser-use/pull/857)
- [browser-use #221](https://github.com/browser-use/browser-use/issues/221)
- [Stagehand #389](https://github.com/browserbase/stagehand/issues/389)
- [Crawl4AI #1757](https://github.com/unclecode/crawl4ai/issues/1757)
- [Orca #13665](https://github.com/stablyai/orca/issues/13665)
- [Orca #4280](https://github.com/stablyai/orca/issues/4280)
- [Orca #11557](https://github.com/stablyai/orca/issues/11557)
- [Orca #3099](https://github.com/stablyai/orca/issues/3099)
- [T3 #228](https://github.com/pingdotgg/t3code/issues/228)
- [T3 #780](https://github.com/pingdotgg/t3code/issues/780)
- [vibe-kanban #1947](https://github.com/BloopAI/vibe-kanban/issues/1947)
- [Claude Squad #260](https://github.com/smtg-ai/claude-squad/issues/260)
- [Codex #2847](https://github.com/openai/codex/issues/2847)
- [Codex #14593](https://github.com/openai/codex/issues/14593)
- [Claude Code #15379](https://github.com/anthropics/claude-code/issues/15379)
- [Claude Code #16157](https://github.com/anthropics/claude-code/issues/16157)
- [Scrapy #6597](https://github.com/scrapy/scrapy/issues/6597)

**Hacker News** (`news.ycombinator.com/item?id=`):
- Orquestradores: 46029331, 46682551, 47871018, 47949570, 48716605, 49947002, 49983772, 47602407, 44633890.
- Dados: 48117619, 48358336, 42272559, 47977587, 48501759, 44933882, 45577592, 48099580, 49263038, 45116057.
- Scraping: 38823766, 45369261, 45374667, 48870918, 49597434, 44086884, 44971458, 47119510, 49838013, 44390404, 47306634, 48685987, 46321459, 49967498.
- Segredos: 46884228, 47329033.
