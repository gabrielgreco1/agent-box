# M-101 + M-102 · Composer "New Session" nasce do "+" (e fecha com Esc)

História: o cartão de 560 pt nasce do botão "+" da sidebar, assenta em 200 ms e some em 150 ms.

| MARK | Evento real | t (s) |
|---|---|---|
| PRESS | clique no "+" / ⌘N (M-801: botão 0,97, fundo ativo, terminal perde foco) | 0,25 |
| SETTLED | cartão e scrim assentados (`base`) | 0,45 |
| ESC | Esc: foco volta ao terminal já no quadro 0 | 1,75 |
| CLOSED | overlay removido (M-102) | 1,90 |

Alvo: tabela de 04 §7.1.1 (f2 scrim 0,19 / cartão 0,61 · 0,981 · 4,7 pt; f4 0,41 / 0,86; f6 0,51 / 0,95; f9 scrim 0,55; saída f3' 0,84, f6' 0,49, f9' 0).

Variantes
- A (spec): scrim `ease` 0,15 → 0,55; cartão `standard` 0,20, opacidade 0→1, escala 0,95→1 ancorada no ponto do botão projetado na borda, 12 pt de offset na direção do botão; 3 grupos com stagger `list` 0,035 (fade + 4 pt).
- B: morph por recorte, o cartão cresce a partir do ponto do botão com a spring `panel`; conteúdo entra com stagger a partir de `children` 0,06.
- C: linha de base do Orca (`zoom-in-95`): escala 0,95→1 no centro, sem offset nem stagger.
- RM: scrim e cartão em crossfade `reducedCrossfade` 0,15 (`ease`), sem escala/offset/stagger.

Saída (todas, exceto RM): `exit` 0,15, cartão 1→0 e escala 1→0,98 (âncora no botão), scrim 0,55→0 `ease`; fundo ativo do "+" some em `hover` 0,12.
