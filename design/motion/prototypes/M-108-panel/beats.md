# M-108 · Painel direito, aba Computers

História: o painel ganha espaço por recorte (o conteúdo não desliza) e o terminal faz um único resize.

| MARK | Evento real | t (s) |
|---|---|---|
| PRESS / PTY_RESIZE_OPEN | botão da activity bar; resize único do terminal no quadro 0 | 0,25 |
| PANEL_OPEN_END | recorte 100%, hairline 0→1 (0,12) | 0,55 |
| CLOSE | fecha: recorte 100→0% em 0,20 `exitClip` | 1,65 |
| PTY_RESIZE_CLOSE | único resize do fechamento, no último quadro | 1,85 |

Alvo 04 §7.1.2: f2 53%, f4 79%, f8 96%, f18 100%, `expoOut` 0,30.

Variantes: A = recorte cresce da borda que encosta no terminal (texto de 04 §6.3 e §7.1.2); B = cresce da borda da janela (leitura literal de `inset(0 0 0 100%)` em §6.3). RM = crossfade 0,15, resize mantido.
