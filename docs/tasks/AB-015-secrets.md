# AB-015 · `.env`, Keychain e concessões de credenciais

## Entregue

- `EnvFileParser.read/parse` lê até 1 MiB de UTF-8 como dados, com linhas `NOME=valor`, `export NOME=valor`, aspas simples e aspas duplas com escapes limitados. `$VAR`, `$(...)` e crases permanecem texto literal. Sintaxe não suportada falha com número da linha, sem ecoar o valor; nomes duplicados são exibidos antes da importação.
- `SecretVault` guarda valores em `SecretValueStoring`, com backend real `KeychainSecretStore` e backend falso nos testes. `SecretRepository` persiste somente UUID, nome, origem e grants em `secret-references.json` com permissões de usuário. Importação em lote não substitui nomes existentes e tenta reverter itens novos no Keychain se falhar antes de salvar metadados.
- Concessões exigem UUID de escopo (projeto, sessão, terminal ou execução), uso (ferramenta/env) e destino específico. Resolução exige correspondência exata, prazo não expirado e grant não revogado. `delegable` é metadado para broker futuro; não dá acesso implícito a filhos. Grants duplicados ativos são rejeitados. Revogação incrementa revisão e bloqueia futuras resoluções pelo vault.
- `SecretSettingsView()` permite entrada manual mascarada, seleção e preview de `.env`, importação explícita, criação e revogação de grants. Nunca mostra valores armazenados. O arquivo `.env` de origem permanece onde estava e a interface informa isso.

## Limites

O vault é uma fundação para o broker local, não um sandbox do CLI. O chamador confiável deve autenticar a identidade de sessão/terminal/run antes de construir `SecretAccessRequest`; o UUID no próprio pedido não constitui autenticação. Ainda não há injeção de env em processos ou montagem de `.env` em containers. `delegable` e revogação não retiram valores já entregues; env existente pode exigir reinício e rotação. Login dos CLIs e perfis do navegador continuam separados. Múltiplos processos escrevendo o mesmo arquivo de metadados exigirão coordenação transacional no serviço futuro.

## Verificação

O Core Secrets e `SecretSettingsView` passaram em typecheck isolado. Testes com backend falso cobrem parser literal/duplicatas/erros, metadata sem valor, grants exatos, expiração, ausência de delegação implícita, revogação, importação em lote e rollback. O integrador executará a suite Swift serial; nenhum segredo real foi criado, lido ou modificado nos testes deste agente.
