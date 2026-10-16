# AB-010 · Memória versionada e histórico de agentes

## Contrato de dados

A biblioteca persiste o estado atual de definições e memórias e mantém `agentRevisions` e `memoryRevisions` imutáveis por ID/revisão. Editar, selecionar, arquivar ou excluir memória cria a revisão necessária da definição afetada; excluir impede seleção futura, preservando snapshots para auditoria. Arquivos `library.json` anteriores são decodificados com defaults para os novos campos, sem inventar revisões históricas que não existiam.

Memória tem tipo (preferência, conhecimento verificado, procedimento ou nota de tarefa), escopo (agente, projeto, tarefa, preferência global ou perfil), fonte, autor, datas e validade opcional. `LibraryContext.prepare(...)` aceita IDs de memórias e skills selecionadas por execução, exige chaves de projeto/tarefa/perfil correspondentes e rejeita memória arquivada, expirada, ausente ou de outro agente. Retorna `PreparedAgentContext` com texto revisável, revisão da definição, provedor, referências de memória (`memoryID`, revisão, título, fonte, tipo, escopo) e skill (`id`, nome, SHA-256, caminho). O limite de 200 KB falha explicitamente, sem truncar.

`LibraryMutations.recordRun(prepared:terminalID:sessionID:in:...)` só deve ser chamado pelo adapter após observar o lançamento real do CLI. O registro guarda IDs de sessão, terminal, revisão, memórias/skills selecionadas e identidade nativa quando conhecida. `finishRun` associa computadores, perfis e resultado real. Salvar ou duplicar definição não cria execução. Edições posteriores não alteram a revisão gravada no run.

## Interface

A biblioteca mostra revisões anteriores da definição e memória, tipo/fonte/validade, criação/edição/seleção/arquivamento/exclusão e campos de escopo. O preparo de contexto mostra texto local para revisão/exportação; não afirma ativação nativa ou processo em execução. Histórico só mostra registros reais, com sessão, terminal, computadores, perfis e resumo quando presentes; estado vazio permanece vazio.

## Validação e limites

Testes unitários cobrem snapshots de revisões, escopos de projeto/perfil, expiração, proveniência do contexto, IDs/revisões do histórico, exclusão e compatibilidade de JSON anterior. O Core Library passou em `swiftc -typecheck`; o integrador executará a suite Swift serial e validará a UI no build final.

A seleção em tela de projeto/tarefa/perfil aceita a chave fornecida pelo usuário somente para exportação local. No lançamento nativo, o adapter deve usar IDs verificados do workspace, aplicar o contexto apenas por mecanismo suportado e chamar `recordRun` só depois de observar o processo. Evidência de site, cookies e segredos não são promovidos automaticamente a memória textual.
