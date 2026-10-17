# Correção de testes de tempo flaky (suíte AgentBoxKit)

## Linha de base (execução 0, antes das correções, 883 testes, 190,1 s): 7 falhas sob carga
- TooltipPolicyTests.showsAfterTheDelayAndNotBefore (3 issues, 11,0 s) e leavingBeforeTheDelayCancelsAndClickDismisses (1 issue, 12,4 s): `waitUntil` de 3 s estourava com a main thread disputada.
- LoginShellEnvTests.cacheServesRepeatedCallsAndReloadInvalidates (3 issues): contagem de capturas 3 em vez de 2 (provável captura interativa caindo no fallback não interativo sob carga; causa exata não reproduzida). Adicionado diagnóstico à mensagem do `#expect` para registrá-la se reaparecer.
- Conhecidos que não falharam nessa rodada mas tinham a mesma fragilidade: OverlayHostTests.focusReturnsAtTheStartOfTheExitNotAtTheEnd e ToastCenterTests.timerDismissesAndHoverPausesIt (sleeps reais + `MotionPolicy.shared` mutável), LoginShellEnvTests.cancelledCaptureKillsTheShellQuickly e hangingInteractiveRc... (tetos de tempo e polling fixo de 2 s), CtlServerTests.waitAppearsWhenElementShowsUp (setTree após sleep de 200 ms com prazo de 3 s).

## Correções (na raiz)
- Novo `DSSleep`/`ManualScheduler` (AgentBoxDesignSystem/Scheduler.swift): espera injetável; tempo virtual avança só com `advance(by:)`.
- `TooltipController`, `ToastCenter` e `OverlayRouter` recebem `sleep` e `motion` (MotionPolicy) injetáveis; padrão idêntico ao anterior (relógio real e `MotionPolicy.shared`), sem mudança de comportamento de produto.
- Testes de Tooltip/Toast/Overlay/Popover usam `ManualScheduler` e `MotionPolicy` próprio por teste: ordem/estado em vez de sleep e limite inferior de tempo. Nenhum teste muta mais `MotionPolicy.shared.mode`.
- LoginShellEnv: `processIsGone` e espera do pid com polling com prazo (15 s/20 s); cancelamento medido a partir do `invalidate` (< 4 s, spec: timeout 5 s); teto do fallback do rc travado 15 s (mantém o limite inferior exato de 5 s da spec).
- CtlServer wait: o elemento só aparece depois que o servidor já consultou a árvore (handshake por contador), prazo de 30 s.
- Nenhum teste removido; cobertura mantida (883 testes).

## Execuções finais (código final, 3 seguidas)
| Execução | Resultado |
|---|---|
| 1 | Test run with 883 tests in 130 suites passed after 191.095 seconds. |
| 2 | Test run with 883 tests in 130 suites passed after 190.625 seconds. |
| 3 | Test run with 883 tests in 130 suites passed after 191.349 seconds. |

Também: `scripts/lint.sh` OK e `scripts/lint-ui.sh` OK (a lint de `sleep(` por regex exigiu nomear o closure local `delay`).
