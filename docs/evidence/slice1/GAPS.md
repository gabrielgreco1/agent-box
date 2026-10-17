# Fatia 1 — lacunas a fechar antes do fechamento (T1-25)

Lista mantida pela sessão gerente a partir dos relatórios das tarefas.

- [ ] Captura visual real (ScreenCaptureKit/screencapture) bloqueada: app ad-hoc sem permissão e Stage Manager reduz janelas em segundo plano. Fazer rodada de QA visual com o app em primeiro plano; `make-dev-cert.sh` pelo dono.
- [ ] Referência Orca 1440×900/760×480 pendente de sessão com o dono.
- [ ] XCUITest com clique real (AC-T02) — nenhuma tarefa escreveu ainda.
- [ ] T1-10: clique esquerdo no nome do app → menu (feito em T1-12, conferir).
- [ ] T1-11: ✕ do toast sem ActionID/A11yID; Motion Lab ausente.
- [ ] T1-13: hover card, chip de PR (F2), linhas filhas, headers de projeto fixos ao rolar; menu Sort/Filter usa TemporaryMenuPanel → trocar por DSMenuPanel.
- [ ] T1-19: overlay "Add a Project" (§16.9); confirmar "Remove Project"; remoção não para terminais vivos nem limpa seleção; pasta folder sem sessão automática; landing sem "New Clean Session".
- [ ] T1-09: find bar só destaca o match atual; possível bus error intermitente no teardown durante flood (bench).
- [ ] Testes de timing instáveis sob carga (OverlayHostTests.focusReturnsAtTheStartOfTheExitNotAtTheEnd).
