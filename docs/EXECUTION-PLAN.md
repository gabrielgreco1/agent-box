# Execução da spec completa

Atualizado em 16/10/2026. Fonte de requisitos: `spec/index.html` e os 68 casos de `spec/acceptance.json`. Este plano transforma os marcos em entregas integráveis; não substitui nem reduz a spec. Distribuição/instalador não é prioridade agora. OpenCode permanece no contrato, sem deslocar as fundações.

## Modelo do produto

Projeto/pasta → sessão → terminais reais → execuções de agentes/subagentes → computador opcional. Uma definição de agente é reutilizável; não é uma sessão, um processo ou uma box. Cada execução fixa revisões da definição, memórias e skills. Um terminal pode receber seu próprio computador. Nenhum filho aparece como terminal interativo se o harness não fornecer PTY próprio.

## Como executamos

Três agentes GPT-6 Sol, esforço medium, com arquivos de responsabilidade separados. O integrador mantém contratos comuns, roda builds/testes em série, revisa diffs e publica commits pequenos no repositório. Agentes não abrem cópias do aplicativo nem fazem push. As tarefas abaixo têm dependências técnicas, mas trabalho independente pode avançar antes de um marco inteiro terminar.

Estados: **parcial** significa código funcional com limites; **em integração** ainda depende de testes conjuntos; **em execução** indica trabalho em curso; **planejada** ainda não entregue. Testes com runners falsos não comprovam Docker, streaming ou integração real com um harness.

## Tarefas

| ID | Entrega e saída verificável | Depende de | Aceite | Estado / responsável |
|---|---|---|---|---|
| AB-001 | Targets operacionais separados do design; build reprodutível | — | Base | Parcial / integrador |
| AB-002 | PTY real, sinais, resize e retenção do renderer por terminal | 001 | AC09–AC14 | Parcial / terminais |
| AB-003 | Sessões, cinco panes, abas, rename, layout persistente | 002 | AC01–AC07, AC18 | Parcial / interface |
| AB-004 | Política Docker, detecção e ciclo de vida HTTP com ownership | 001 | AC27, AC29, AC44–AC46 | Parcial / computadores |
| AB-005 | Biblioteca de definições, importação de skills e seleção de memória | 001 | AC25–AC26, AC61–AC68 | Parcial / integrador |
| AB-006 | Chrome Orca: tons cinza-azulados, sem bordas/glow, hierarquia compacta | 003 | AC01–AC07 | Em integração / interface |
| AB-007 | Foco nativo, cores do emulador e autenticação no ambiente Finder | 002 | AC09–AC14 | Em integração / terminais |
| AB-008 | Inspeção Git e criação explícita de worktree, sem mutações implícitas | 001 | AC16–AC17 | Em integração / computadores |
| AB-009 | Git/worktree na sessão e no fluxo de criar terminal; erros recuperáveis | 008, 003 | AC16–AC18 | Em integração / interface |
| AB-010 | Memórias por escopo, revisões imutáveis, edição/arquivo/exclusão e histórico real | 005 | AC26, AC61–AC64, AC67–AC68 | Em integração / biblioteca |
| AB-011 | Plano de lançamento revisável por CLI, contexto fixado e skills com mecanismo comprovado | 005, 010 | AC10, AC23, AC25–AC26, AC63, AC65–AC68 | Em integração / terminais |
| AB-012 | UI de lançamento da biblioteca ligada a sessão/terminal; registro de início/fim e falha | 009–011 | AC61–AC68 | Em integração / integrador |
| AB-013 | Registro de conversas: descoberta, origem, resume suportado e escrita exclusiva | 007, 009 | AC15, AC18, AC23 | Planejada |
| AB-014 | Política efetiva por escopo, tetos, primeiro uso retomável e aplicação de mudanças | 004 | AC44–AC46, AC50 | Parcial / integração |
| AB-015 | .env como dados, Keychain, grants/revogação e redaction sem valores nos logs | 014 | AC47–AC50 | Parcial / integração |
| AB-016 | Adapter/eventos de filhos por harness; identidade e capabilities comprovadas | 011, 014 | AC19, AC22–AC25 | Parcial / integração |
| AB-017 | Broker: actor/run/computer IDs autenticados, concessões e revogação no cancelamento | 016, 015 | AC19–AC24 | Parcial / integração |
| AB-018 | Reservas Docker idempotentes, fila justa/cancelável, quotas e HTTP real | 004, 014 | AC27–AC29, AC37 | Planejada |
| AB-019 | Imagem browser headless, JS real, health checks e promoção de modo recuperável | 018 | AC30, AC32–AC33, AC37 | Parcial / integração |
| AB-020 | Desktop e viewer em streaming; iniciar/parar stream independente do browser | 019 | AC08, AC31–AC33, AC36–AC37 | Parcial / integração |
| AB-021 | Perfis persistentes fora de imagens, lock de escritor, backup/restore | 018, 015 | AC34–AC35, AC59 | Parcial / integração |
| AB-022 | Takeover com revogação/ACK/epoch em todos os caminhos de escrita e reconciliação | 017, 020 | AC38–AC41, AC43 | Parcial / integração |
| AB-023 | Pedidos de intervenção, badge/som deduplicado, foco no alvo certo e previews | 022 | AC04, AC08, AC40, AC42–AC43 | Parcial / integração |
| AB-024 | Listener browser/HTTP com cobertura declarada, filtros e retenção/backpressure | 019, 015 | AC51–AC54 | Planejada |
| AB-025 | Resultados CSV/JSON com proveniência, evidências e deduplicação auditável | 024 | AC55 | Planejada |
| AB-026 | Troca de modelo confirmada por execução, capacidades específicas por CLI | 016, 012 | AC56 | Planejada |
| AB-027 | Handoff entre harnesses com checkpoint e controlador único; falha recuperável | 026, 021, 022 | AC57, AC67–AC68 | Planejada |
| AB-028 | Serviço PTY, reconexão após crash/sono e migração versionada com backup | 002, 017, 021 | AC11–AC13, AC58–AC59 | Planejada |
| AB-029 | Aceite completo: TUIs, acesso por teclado, cinco panes, boxes e 60 min de carga | Todas as necessárias | AC01–AC68, especialmente AC60 | Planejada |
| AB-031 | Acesso explícito a pastas, bookmark e restauração para Git/PTY | 009, 012 | AC09, AC16, AC18, AC58 | Em integração / interface |
| AB-030 | Marca própria, ícone Dock, recurso empacotado e higiene de processos/builds | 001, 006 | AC05–AC07, AC60 | Em integração / integrador |

## Entregas que não podem ficar implícitas

**Agentes personalizados e memória:** criar/editar/duplicar/arquivar definição; revisão permanente; memória selecionada por escopo; preview antes do lançamento; histórico navegável até sessão, terminal, execução e computador; excluir não promete apagar contexto já enviado; reutilização oferece nova execução ou retomada suportada. AB-010/012 não terminam com um formulário que apenas salva texto.

**Skills:** catálogo, origem/hash, importação sem execução, seleção por agente, snapshot por execução e ativação verificada pelo adapter. Incompatibilidade aparece com motivo. Exportar um contexto não equivale a ativar uma skill. Cada harness é testado separadamente; não presumir que flags de um funcionam em outro.

**Computadores e controle:** o orquestrador escolhe HTTP/headless/desktop dentro da política efetiva. Headless executa JavaScript; desktop não é pré-requisito para JS. A política “sempre gráfico” é aplicável às boxes atribuídas. Escalar preserva IDs/arquivos/progresso, mas não promete preservar DOM ou submissões incertas. Controle humano exige ACK de revogação antes de habilitar input.

## Gates de integração

1. Contratos Core compilam; testes de persistência, erros e isolamento passam. Nenhuma fixture entra no runtime.
2. UI chama a implementação, não um estado simulado. Erro aparece no lugar certo e permite recuperação sem descartar dados.
3. Evidência de processo/container/CLI é registrada sem credenciais. Smoke usa recursos descartáveis e encerra somente processos próprios.
4. Fluxo vertical: sessão com dois terminais, dois filhos comprovados e duas boxes; takeover em uma não afeta a outra.
5. Auditoria final percorre os 68 casos. Critério global fica pendente enquanto qualquer parte exigida não foi exercitada. A meta continua aberta até cumprir a spec.

## Próxima integração concreta

Checkpoint: 70 testes Swift passaram, e o runtime Docker passou no smoke arm64 real. Biblioteca, permissões/Keychain, broker e viewer têm implementação; hooks/automação de filhos, listener e continuidade completa seguem pendentes. Veja STATUS.md para distinguir prova de módulo e fluxo ao vivo.


Integrar e testar as entregas existentes antes de avançar seus aceites. Rodada paralela executada em GPT-6 Sol, esforço medium; módulos entregues e integração em curso:

| Subtarefa | Ligação com a spec | Responsável | Resultado exigido |
|---|---|---|---|
| AB-032 · Skills nativas | AB-011/012, AC65–68 | skills_activation | Snapshot por execução e carregamento Claude suportado, sem alterar configuração global. |
| AB-033 · Input do desktop | AB-020/022, AC38–43 | desktop_input | Arraste, scroll e modificadores reais sob o mesmo controle exclusivo. |
| AB-034 · Eventos nativos | AB-016, AC19/22–25 | run_events | Payloads documentados, vínculo de sessão e ingestão verificável; não inferir filhos do texto de terminal. |

O integrador mantém testes/builds em série, a conferência do app e os commits. Os três agentes não abrem apps nem executam tarefas pagas dos CLIs. A execução automática via hooks, o ciclo completo de skills nos demais clientes e os demais marcos seguem com seus próprios gates.
