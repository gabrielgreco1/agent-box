# Rebuild do Racky · índice

Reconstrução do app macOS Racky (UI refeita com o Orca 1.4.219 como referência). Três camadas: auditoria (o que existe e o que falta), revisões (o que a spec precisava corrigir) e spec (o que construir). **Em caso de conflito vale `spec/00-decisions.md`.**

## Como ler

1. `spec/00-decisions.md` (uma página; prevalece sobre tudo).
2. `spec/01-product.md` §4 (escopo e fatias) e `spec/09-roadmap.md` (ordem de execução).
3. O capítulo do tema da tarefa (02 e 03 para UI, 04 para motion, 06 e 07 para comportamento, 08 para arquitetura e DoD) e os ACs em `spec/05`.
4. A auditoria e as revisões só para entender a origem de uma decisão; elas não são requisito.

Agente de código: leia `spec/09-roadmap.md` §5 antes de qualquer tarefa.

## Spec (`spec/`)

- `00-decisions.md`: decisões fechadas do dono (P1…P16) e técnicas (T1…T14).
- `01-product.md`: visão, princípios, escopo por fatia (v1, v1.1, later, fora), modelo de domínio, máquinas de estado, glossário.
- `02-design-system.md`: tokens, tipografia, medidas, componentes base, acessibilidade, regras anti "AI generated", glossário de UI.
- `03-screens.md`: cada tela e overlay, microcopy exata, atalhos, `accessibilityIdentifier`, checklist de fidelidade com o Orca (§23), tabela de ações (§24).
- `04-motion.md`: tokens e catálogo de momentos de motion, os três momentos obrigatórios, workflow de protótipo e aceite.
- `05-journeys-and-acceptance.md`: jornadas J1…J11 e os ACs, fixtures, definição de pronto da v1, matriz requisito → AC.
- `06-terminals-and-agents.md`: terminais e daemon `rackyd`, lançamento de agentes, atividade e notificações, biblioteca, Git e GitHub, importação do Orca.
- `07-computers-and-subagents.md`: computadores Docker, egress e proxy, ferramentas MCP, orquestração e lote, controle humano, modo isolado (v1.1).
- `08-architecture-quality.md`: arquitetura, dados, concorrência, segurança, observabilidade, desempenho, testes, DoD, build, ordem técnica, spikes.
- `09-roadmap.md`: fatias 0 a 4 e v1.1, tarefas da Fatia 1 (T1-01…T1-27), regras de execução para agentes, decisões abertas do dono.

## Revisões (`review/`)

- `R1-consistency.md`: contradições entre capítulos (nomes, números, atalhos, IDs).
- `R2-coverage.md`: cobertura da auditoria 01..10 pela spec.
- `R3-implementability.md`: o que impedia implementar (spikes, tarefas grandes demais, Fatia 0 e decomposição da Fatia 1).
- `E-01-05-changelog.md`: mudanças aplicadas em 01 e 05 após R1 a R3.
- `E-02-03-changelog.md`: mudanças em 02 e 03 (inclui Settings › Computers › Proxies).
- `E-04-changelog.md`: mudanças em 04 (motion).
- `E-06-08-changelog.md`: mudanças em 06 e 08 (inclui spikes e D-Codex-1).
- `E-07-changelog.md`: mudanças em 07 (lote na v1, proxy genérico, perguntas Q1 a Q4).

## Auditoria (`audit/`)

- `01-features-requested.md`: inventário do que foi pedido e especificado.
- `02-core-audit.md`: auditoria técnica do Core, MCP, runtime e testes.
- `03-screens-and-flows.md`: telas, sheets e fluxos do app atual.
- `04-orca-reference.md`: referência de design Orca → Racky.
- `05-core-features-gaps.md`: lacunas nas funcionalidades centrais.
- `06-motion.md`: auditoria e proposta de motion.
- `07-review-ui.md`: revisão de UI/UX e paridade com o Orca.
- `08-review-features.md`: completude funcional e subagentes.
- `09-review-architecture.md`: arquitetura, confiabilidade, segurança e desempenho.
- `10-review-journeys.md`: um dia de uso real.
- `screens/`: capturas do app atual usadas pela auditoria.

## A criar na Fatia 0

- `reference/orca-1.4.219/`: pacote de referência visual do Orca (PNGs por tela e estado em 760×480 e 1440×900, tokens extraídos, `manifest.json`). Ver `spec/09-roadmap.md` §2.3.
- `../evidence/`: spikes, evidência visual por tarefa, e2e e relatórios de fatia.
