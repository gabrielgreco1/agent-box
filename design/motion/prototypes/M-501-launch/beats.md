# M-501 → M-503 → M-504 · Agente sendo lançado (Claude Code, worktree nova)

História: o chip sai do "Create Session", viaja até a vaga na sidebar e vira a linha da sessão; o centro mostra a ignição com um checklist que só avança por eventos reais do core; o primeiro byte revela o terminal.

Fixture de eventos (`LaunchProgress`, tempos relativos ao ⌘↵, 04 §7.2.2 blocos A e B): `git.fetch` 0,05→1,15 · `git.worktree` 1,15→1,95 · `launch.config` 1,95→2,20 · `cli.exec` 2,20→3,10 (primeiro byte). `pty.spawn` confirmado em 2,35 (T_ready). O HTML deriva as linhas desses eventos: cada linha fica visível >= `checklistMinStep` 0,12 s (fila visual, o processo não espera); o check é desenhado em `medium` 0,24 `expoOut` quando o evento conclui.

| MARK | Evento real | t abs (s) |
|---|---|---|
| PRESS | ⌘↵ no composer | 0,25 |
| COMPOSER_GONE | composer fora (`exit` 0,15) | 0,40 |
| CHIP_LAND | pouso do chip (`flight` 0,42) | 0,67 |
| IGNITION_BEGIN | f35: pendente selecionado, logo 32 pt + halo, linha 1 | 0,83 |
| STEP_*_DONE | cada etapa conclui | 1,40 / 2,20 / 2,45 / 3,35 |
| T_READY | PTY ok: spinner pendente → indicador, tab "Claude" nasce (M-301), linha de fase colapsa | 2,60 |
| FIRST_BYTE | M-504: checklist sai (0,12), `PaneCover` 1→0 (0,16), indicador → working | 3,35 |

Alvo: tabela de 04 §7.2.1 (chip x/y em f3, f6, f9, f15; vaga 72% em f6; pouso f25; seleção desliza f30; spinner f35).

Variantes
- A (spec): voo 0,42, x `standard`, y `expoOut`, arco `arcLift` 56, escala 1→0,85; pouso com spring `lively` na linha + `clickRing`; pisca de seleção 0→12%→0 (0,30).
- B: linha reta com spring `panel` (sem overshoot) e varredura de brilho na linha, sem ring.
- C: só o logo voa (a cápsula esvazia no composer); o nome é revelado por recorte `standard` 0,20 na linha.
- RM: sem chip; composer em fade 0,15; linha em fade; checklist em fade, check sem desenho, halo estático, spinner = anel completo parado; cobertura em crossfade 0,15.
