# T4-05 Endurecimento: o que precisa do dono

Nada abaixo foi feito pelo agente: cada item depende de aprovação, de uma ação no Mac do dono ou de uma sessão de uso real.
Estado em 2026-10-20 (branch `slice4-b`).

## 1. Aprovações (não dá para automatizar)

- [ ] **Snapshots de referência (AC-T26, P14).** Os PNGs de `Packages/RackyKit/Tests/UISnapshotTests/__Snapshots__` e a comparação lado a lado com o Orca
      (`scripts/compare-ui.sh`) só valem com o OK explícito do dono **em toda tela da v1**. Registrar o OK por tela em `docs/evidence/ui/`. Nenhum snapshot foi
      regravado nem "aprovado" nesta tarefa.
- [ ] **Settings › Diagnostics** (T4-04, tela nova): conferir o visual (evidência: `docs/evidence/observability/2026-10-20/diagnostics-page.png`,
      `export-preview.png`, `after-crash.png`) e dar o OK da tela.
- [ ] **M-109 da Library** (motion): aprovação visual do dono; sem OK, fica como está.
- [ ] **Modelo de ameaça (AC-T19, revisão):** ler `docs/rebuild/spec/08-architecture-quality.md` §5.1.1 (AR-504, A17 a A25) e o resumo no `README.md`; confirmar os riscos
      residuais aceitos (capability em argv, `threadId` do Codex como dica de roteamento, `ctl` ligado = igual ao usuário).
- [ ] **Release `1.0.0`** (T4-06): só depois dos itens deste arquivo e do "dia real" (J2, J3, J4, J6, J8, J11).

- [ ] **Snapshot regravado:** `subagents.settingsComputers.png` mudou só porque a nav do Settings ganhou o item `Diagnostics` (T4-04); conferir e aprovar junto com a tela.

## 2. Ações manuais no Mac do dono

- [ ] **AC-T18 (Keychain, TCC e notificações estáveis).** Com "Always Allow" no Keychain e as permissões já concedidas, instalar a build nova com
      `scripts/install.sh` **duas vezes seguidas** (assinatura local estável, `scripts/make-dev-cert.sh`) e confirmar que nenhum prompt de Keychain, de pastas
      protegidas ou de notificações reaparece. O que o código garante e está travado por teste (`TCCStabilityTests`, regra `screen-capture` do `lint.sh`):
      Keychain do Claude só por `/usr/bin/security`; Gravação de Tela nunca é pedida (só consultada); notificações só pelo botão `Allow Notifications`
      (a notificação de pedido de ajuda deixou de abrir o prompt sozinha); nenhuma API de Acessibilidade, Apple Events, câmera, contatos ou fotos.
- [ ] **AR-720 no Mac do dono antes do release:** `scripts/bench.sh` e `scripts/bench.sh --ten` (números desta máquina em `docs/evidence/perf/2026-10-20/`) e os
      traços do `xctrace` (Time Profiler, Animation Hitches, Allocations) com o app real: o `xctrace` não foi automatizado aqui.
- [ ] **AC-T23 (viewer fora do main thread).** Com Docker e um computador `desktop` navegando numa página lenta, medir o main do app (Instruments › Animation Hitches
      ou `bench`): a decodificação do noVNC roda no processo WebContent do WKWebView, não no app, mas a medição com computador real exige Docker e o `e2e.sh` (passos 4 e 5).
- [ ] **AR-706 completo** (20 terminais + 15 boxes + 2 desktop, `boxes_reserve` → `ready` p95, primeiro quadro do viewer ≤ 1,5 s): precisa de Docker e do lote real
      do `scripts/e2e.sh` (custo de modelo de US$ 1 a 2).
- [ ] **AC-T17 em E2E real:** provocar uma falha de Docker, de hook e de lançamento e exportar o pacote (o smoke desta tarefa usou o app isolado e testes automatizados).

## 3. Fora do que o agente pode decidir

- Qualquer mudança de orçamento (AR-702/703/704/705/706): só o dono altera os números de `08`.
- Remover o limite de uma sessão por pasta de dados ou ligar a automação (`RACKY_AUTOMATION`) por padrão.
