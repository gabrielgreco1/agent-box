# Data (área de dados): modelo de UX

Status: etapa 2 do roadmap (docs/rebuild/roadmap.md). Telas reais com dados de exemplo; conexões de verdade vêm na etapa 3.

## O problema

O usuário vai lidar com dados em lugares diferentes: o que os agentes coletaram e está guardado no Racky, e o que está fora (o Postgres do Supabase dele, um bucket S3, um warehouse, uma planilha, um webhook). O agente pode gravar num ou noutro. Se as telas forem parecidas demais, ele não sabe onde está, o que está vendo, nem o que um clique vai mudar. A regra desta área: **em qualquer tela, sem ler nada além do topo, o usuário sabe (1) em que lugar está, (2) que tipo de coisa está vendo, (3) de onde aquele dado veio e para onde vai, (4) se pode mudar algo e com que risco**.

## Conceitos e nomes (o usuário vê exatamente estes)

| Nome na UI | O que é |
|---|---|
| **Data** | A área inteira (item da sidebar, troca "Datasets"). |
| **Racky** | O armazenamento local do app. Onde os agentes guardam o que coletam quando ninguém pediu outro lugar. |
| **Dataset** | Uma tabela dentro do Racky, criada por um agente numa sessão. Sempre ligada a uma sessão. |
| **Connection** | Um lugar fora do Racky que o usuário conectou: banco, warehouse, bucket, planilha ou webhook. Tem nome dado pelo usuário e, se for o caso, ambiente (`prod`, `dev`). |
| **Table** | Uma tabela de um banco ou warehouse conectado. |
| **Query** | Um editor SQL aberto numa conexão (ou no Racky). |
| **Bucket / folder / file** | Armazenamento de objetos (S3, GCS, R2). |
| **Sheet** | Uma aba de planilha (Google Sheets, Airtable). |
| **Webhook** | Um destino que só recebe: não dá para navegar, só ver o que foi entregue. |
| **Writer** | Quem grava num lugar: um agente (e a sessão dele) ou um sync. |
| **Sync** | Uma cópia contínua (ou única) de um dataset do Racky para uma conexão. |

## Estrutura da tela Data

```
┌ Explorer ────────────┬ tabs: [▦ books2] [⛁ public.hotels] [⌘ Query 1] ───────────────────────────┐
│ RACKY                │ ┌ Location bar ─────────────────────────────────────────────────────────┐ │
│  ▾ Teste dos subag…  │ │ [Racky] Teste dos subagentes › books2        Dataset · 80 rows        │ │
│     ▦ books2  ●live  │ │ ← Codex 1, Codex 2 (live)   → Supabase prod › public.books (sync on)  │ │
│  ▸ Hotel prices      │ └───────────────────────────────────────────────────────────────────────┘ │
│ CONNECTIONS          │  conteúdo do objeto (dataset, tabela, query, bucket, webhook)             │
│  ▾ ⛁ Supabase  PROD  │                                                                           │
│     ▾ public         │                                                                           │
│        ▦ hotels      │                                                                           │
│        ▦ books ●live │                                                                           │
│     ⌘ New query      │                                                                           │
│  ▸ ⛁ Analytics  DEV  │                                                                           │
│  ▸ ☁ scrapes-raw (S3)│                                                                           │
│  ▸ ⤴ Orders webhook  │                                                                           │
│ + Add connection     │                                                                           │
└──────────────────────┴───────────────────────────────────────────────────────────────────────────┘
```

- **Explorer** (esquerda, sempre visível na área Data): duas seções com título fixo, **Racky** e **Connections**. No Racky, os datasets agrupados por sessão. Em Connections, cada conexão com ícone do tipo, nome e selo de ambiente; expande para schemas → tabelas, buckets → pastas, planilhas → abas. Webhook não expande. Um ponto verde "live" em todo lugar onde algo está gravando agora. Rodapé: `+ Add connection`.
- **Tabs**: cada objeto aberto é uma tab (como editores no DBeaver). O ícone da tab diz o tipo (dataset, tabela, query, pasta, webhook).
- **Location bar** (topo do conteúdo, em toda tela): o lugar como trilha clicável — chip do lugar (`Racky` ou o tipo + nome da conexão + ambiente) › schema/sessão › objeto — e à direita o tipo do objeto e o tamanho. Embaixo, uma linha de **fluxo**: `←` quem grava ali (agentes, syncs) e `→` para onde aquilo vai. É a linha que responde "de onde vem e para onde vai".
- **Ambiente**: `PROD` em âmbar, `DEV` neutro. Em `PROD`, ações que escrevem pedem confirmação e o editor SQL mostra "Running on Supabase · PROD" em âmbar.

## Telas de objeto

1. **Dataset (Racky)**: a página atual (cartões, gráfico, filtro, facetas, grade). Ações: `Send to…` (copiar ou sincronizar para uma conexão), `Export`.
2. **Table (conexão)**: sub-abas `Data` (grade com filtro), `Structure` (colunas, tipos, chave, índices), `Writers` (agentes e syncs que gravam aqui, com o último envio). Selo `Read only` / `Editable`.
3. **Query**: editor SQL, conexão alvo bem visível na barra (`Running on …`), `Run` (⌘↩), resultado em grade, tempo e linhas.
4. **Bucket**: trilha de pastas, lista de arquivos (nome, formato, tamanho, alterado), prévia de Parquet/CSV/JSONL em grade ao lado.
5. **Webhook**: endpoint, formato, log de entregas (hora, status, linhas, duração), `Send test`.
6. **Add connection**: tipos agrupados (Databases, Warehouses, Storage, Spreadsheets, Outgoing); cada tipo diz se é `Browse and write` ou `Write only`.

## Onde o agente grava

No formulário de nova sessão, uma linha **Save data to**: `Racky` (padrão; cria um dataset da sessão) ou uma conexão (escolher conexão › schema › tabela existente ou nova). A sessão na sidebar mostra o destino. Na Data, o lugar escolhido ganha o agente como writer na linha de fluxo.

## Como validar

Prints das telas com dados de exemplo vão para 10 subagentes sem nenhum contexto, com perguntas fixas:
1. Que aplicativo é este e o que esta tela mostra?
2. Em que lugar está o dado que você está vendo (no app ou fora dele)? Qual?
3. De onde esse dado veio? Ele está indo para algum outro lugar?
4. Qual a diferença entre esta tela e a outra (par de prints)?
5. Se você clicar em X, o que muda e onde? Há algum risco?
6. Como você mandaria estes dados para o Postgres de produção?
Critério: 10 de 10 acertam 1–5 e descrevem um caminho válido em 6. Cada erro vira uma mudança na tela, e a rodada se repete.
