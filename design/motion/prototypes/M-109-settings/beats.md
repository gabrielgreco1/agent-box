# M-109 · Settings (página do centro)

História: o conteúdo antigo some rápido, o Settings sobe 8 pt; sidebar e tab bar ficam paradas.

| MARK | Evento real | t (s) |
|---|---|---|
| CLICK | ⌘, | 0,25 |
| OLD_GONE | conteúdo antigo 1→0 (`press` 0,08, `exit`) | 0,33 |
| ENTER_BEGIN | f5: Settings começa (y +8, fade) | 0,33 |
| SETTINGS_END | `cssEaseOut` 0,18 | 0,51 |
| SECTION_SWITCH | General → Agents: só a entrada se repete, sem saída | 1,45 |

Alvo 04 §7.1.3: f8 0,42 · y 4,6; f13 0,90 · y 0,8; f16 1 · 0. RM = crossfade 0,15.
