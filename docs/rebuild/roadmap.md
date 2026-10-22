# Racky: roadmap (2026-10-22)

Uma ferramenta para quem trabalha com dados: agentes coletam, o dado fica num lugar que dá para ver, provar de onde veio e entregar para onde ele vai ser usado. A ordem abaixo junta o roadmap combinado em 2026-10-20 (dados, receitas e fila, proxies e perfis, entrega, cloud sem cobrança, UI nova por último) com a área **Data** pedida em 2026-10-22.

## O que muda em relação à ordem anterior

- "Entrega" (item 4 antigo) sobe: o agente já pode gravar direto no banco do usuário, então destino e conexões vêm logo depois dos datasets.
- "Datasets" vira **Data**: o que está dentro do Racky (datasets dos agentes) e o que está fora (bancos, buckets, warehouses, planilhas, webhooks), com um explorer no jeito do DBeaver.
- Antes de construir as conexões, a etapa de **modelo de UX**: deixar claro onde o usuário está, o que está vendo e a diferença entre cada tela e conexão. Validado com 10 subagentes que veem as telas sem contexto.

## Etapas

| # | Etapa | O que entra | Pronto quando |
|---|---|---|---|
| 1 | Datasets e exportação (feito) | Tabela viva, chave e dedupe, proveniência, KPIs, gráfico, filtros com pílulas e facetas por coluna, painel Data, exportação CSV/JSON | Feito; polimento contínuo |
| 2 | **Modelo de UX da área Data** (agora) | Nome e lugar na navegação; explorer com "No Racky" e "Conexões"; barra de localização em toda tela (conexão › schema › tabela); diferença visível entre dataset do Racky, tabela externa, consulta SQL, bucket e webhook; quem grava em cada lugar (agentes, syncs). Telas reais com dados de exemplo, testadas com 10 subagentes sem contexto até todos entenderem | 10 de 10 respondem certo: onde estão, de onde vem o dado, como mandar para outro lugar |
| 3 | Conexões SQL (o "DBeaver") | Postgres (Supabase, RDS, Neon), MySQL, SQL Server, SQLite. Adicionar conexão (string ou login do Supabase), segredo no Keychain, navegar schemas e tabelas, grade com filtros, editor SQL com resultado, ambiente marcado (prod/dev) | Conecta no Supabase do usuário, navega, consulta e edita com segurança (prod pede confirmação) |
| 4 | Destino do agente e entrega | Na criação da sessão, "Salvar dados em": dataset do Racky (padrão) ou tabela de uma conexão. Agente grava direto no destino (upsert pela chave, ao vivo); criar tabela a partir das colunas; diferença de schema com confirmação; copiar ou migrar um dataset para uma conexão; sync contínuo; log de entrega com retry e reenviar | O agente coleta direto no Postgres do usuário e a tela mostra o que entrou, o que falhou e quem gravou |
| 5 | Ver a extração de verdade | Replay por linha (print, HTML e requisição do momento, com o campo destacado na página); navegador ao vivo ao lado das linhas chegando; linha do tempo do agente | Clicar numa linha mostra exatamente de onde cada valor saiu |
| 6 | Qualidade e confiança | Regras por coluna (faixa, único, obrigatório), o agente é avisado e corrige; alerta quando o preenchimento cai (site mudou); diferença entre execuções (entrou, saiu, mudou de valor); revisão por amostragem com precisão estimada | Uma quebra de seletor vira alerta antes de virar dado errado |
| 7 | Receitas, fila e agendamento | O agente escreve o raspador e a fila roda em N computadores; limite por domínio; modo HTTP; retomar; fila de URLs de um CSV; agendar ("todo dia às 6h"); orçamento por execução | Uma receita salva roda sozinha todo dia e só acrescenta o que é novo |
| 8 | Buckets | S3, GCS, R2: navegar pastas, prévia de Parquet/CSV/JSONL, gravar particionado (dia, execução) | Ver e gravar no bucket do usuário sem sair do app |
| 9 | Warehouses | BigQuery, Snowflake, ClickHouse, Databricks: navegar, consultar, gravar | Mesmo fluxo do item 3/4 nos warehouses |
| 10 | Planilhas e webhooks | Google Sheets, Airtable (ler e gravar); webhook e fila como destino (só log de entrega, sem navegar) | Coleta cai direto numa planilha ou num endpoint |
| 11 | Proxies, perfis e execuções | Pools de proxy, perfis de computador, painel de execuções, custo por mil linhas | Saber quanto custou cada mil linhas e por quê |
| 12 | Consulta e análise | Editor SQL em cima dos datasets (DuckDB local), juntar datasets, pergunta em linguagem natural vira SQL e gráfico | Cruzar Booking × TripAdvisor sem exportar |
| 13 | Contrato e integração | Schema versionado (JSON Schema, dbt), API e CLI (`racky run receita --to postgres`), lineage de cada valor até a requisição | Plugar no Airflow/Dagster e provar origem para compliance |
| 14 | Cloud (sem cobrança) | Provedor próprio, burst, frota, limites de gasto | Rodar 100 computadores fora do Mac |
| 15 | UI nova | Sidebar "C" aprovada, tabs planas, breadcrumb, status bar no jeito do VS Code | Por último, como combinado |

## Etapa 2 em detalhe (o que começa agora)

1. **Modelo**: conceitos e nomes (Data, No Racky, Conexões, dataset, tabela, consulta, bucket, destino, sync), o que aparece em cada tela e a barra de localização.
2. **Telas reais** no app com dados de exemplo (sem backend de conexão ainda):
   - Data com o explorer (Racky + conexões) e um dataset aberto.
   - Tabela de um Postgres (Supabase) aberta, com quem grava nela.
   - Editor SQL numa conexão, com resultado.
   - Bucket S3 com pastas e prévia de um Parquet.
   - Webhook como destino (log de entregas).
   - Adicionar conexão (escolher o tipo).
   - Nova sessão com "Salvar dados em".
3. **Teste**: cada tela vai para 10 subagentes sem nenhum contexto, com as mesmas perguntas (onde você está, que dado é esse, de onde ele vem, qual a diferença para a outra tela, como mandaria isso para o Postgres). Onde errarem, a tela muda. Repete até todos acertarem.
4. **Entrega**: telas aprovadas viram a base das etapas 3 e 4.
