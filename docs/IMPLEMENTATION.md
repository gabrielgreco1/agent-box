# Plano de implementação

Os critérios detalhados estão em `spec/acceptance.json`. Um requisito só muda para concluído com evidência; UI e status de conexão devem refletir estado observado.

## Lote 1 — fundação utilizável

| Tarefa | Entrega | Dependência | Aceite |
|---|---|---|---|
| AB-001 | Contratos de domínio, Package.swift e build operacional separados do design | Base | Build reproduzível |
| AB-002 | PTYs reais, emulação SwiftTerm, CLI local e lifecycle por terminal | AB-001 | AC09–AC14; limites de persistência explícitos |
| AB-003 | Sessões/terminais, sidebar ajustável e colapsável, splits, rename | AB-001/002 | AC01–AC07, AC18 |
| AB-004 | Política inicial persistente e estado real do Docker; criar/parar box HTTP explícita | AB-001 | Parte de AC27–AC29 e AC44–AC46; sem desktop fictício |
| AB-005 | CRUD de agentes, memória selecionável, importação de skills e contexto exportável | AB-001 | AC61–AC68, com ativação nativa separada |

## Lote 2 — integração dos agentes

- Provar identidade de subagentes e atribuição de chamadas para cada harness (M5).
- Ativar agentes/skills no formato suportado pelo CLI, mantendo revisões.
- Git/worktrees e descoberta de conversas, sem capturar processos externos arbitrariamente.
- Credenciais Keychain e grants por escopo; `.env` somente como dados.

## Lote 3 — computadores completos

- Imagens versionadas HTTP, headless e desktop, health checks, fila e limites.
- Perfis persistentes, migração/backup testados e um gravador por perfil.
- Streaming e takeover com revogação/ACK/epoch em todos os caminhos de escrita.
- Pedido de ação com ping, som e alvo correto.

## Lote 4 — scraping e continuidade

- Listener por fonte, gaps, limites, sanitização e evidências.
- Memória revisável, histórico real e retomada por checkpoint entre harnesses.
- Sono/crash, recuperação, carga prolongada e distribuição local.

## Checkpoint do lote 1

Implementação inicial integrada e testada; consulte [STATUS.md](STATUS.md) para entregas, provas e partes ainda pendentes de cada tarefa. Não considerar os marcos M0–M10 integralmente concluídos.

## Execução paralela

O lote 1 será executado em módulos com propriedade de arquivos definida. Agentes não fazem push, não apagam trabalho de outros e não instalam Docker/CLIs. O integrador compila, testa, revisa e publica checkpoints. Feature parcial continua parcial no registro de progresso.
