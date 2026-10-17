# Protótipos de motion: obrigatórios 1 e 2

Momentos: M-101/M-102 (composer nasce do "+"), M-108 (painel direito), M-109 (Settings) e M-501 → M-504 (agente sendo lançado). Cada pasta tem `beats.md` (beat sheet com MARKs e eventos reais) e `index.html` (UI recriada em HTML/CSS com `lib/ui-kit.css`, sem screenshots). Parâmetros de URL: `?v=A|B|C` (variante), `?rm=1` (Reduce Motion), `?t=<s>` (um quadro), `?play=1` (tempo real).

Rodar: `design/motion/prototypes/render_all.sh` (Playwright em Chromium headless, 1440x900, 60 fps, sem motion blur, ffmpeg libx264). Vídeos em `docs/evidence/motion/<momento>/` (`A.mp4`, `A-slow4x.mp4`, `A-rm.mp4`, `*-keyframes.png`). Para ver lado a lado, abra `index.html` desta pasta. Paridade matemática: `node design/motion/tests/parity.js` (confere `lib/motion.js` contra as tabelas de 04 §3.3/§3.4; passa).

Motor: `design/motion/lib/motion.js` (novo) implementa o `UnitBezier` do WebKit (Newton + bissecção, eps 1e-6) e o spring analítico de 04 §9.4; toda duração, curva, spring, distância, escala, opacidade, stagger e loop vem de `MOTION.*` (`tokens.js`). Nenhum literal de tempo no HTML, exceto os tempos da fixture de eventos reais e os instantes de disparo da cena (T0).

## Valores de 04 usados
- M-101/M-102: scrim `ease` 0,15 → `opacity.scrim` 0,55; cartão `standard` `base` 0,20; escala `dialogFrom` 0,95; offset `medium` 12; stagger `list` 0,035 em 3 grupos; press 0,97 (`press` 0,08, volta em `snappy`); saída `exit` `fast` 0,15, escala `exitTo` 0,98. B usa spring `panel` e `children`.
- M-108: abre `panel` 0,30 `expoOut`; fecha `base` 0,20 `exitClip`; hairline `hover` 0,12; resize único no quadro 0 e no último quadro do fechamento.
- M-109: saída `press` 0,08 `exit`; entrada `disclosure` 0,18 `cssEaseOut`, `small` 8, começando em f5 (83 ms).
- M-501: saída do composer `fast` `exit`; voo `flight` 0,42 (x `standard`, y `expoOut`), `arcLift` 56, escala 1 → 0,85; pouso `lively`, `clickRing` (keyframes de tokens); vaga e tab `snappy`; seleção `snappy` a partir de 0,5 s; logo 32 pt com `halo` (loop de tokens); spinner 12 passos/s de fase global; check `medium` 0,24 `expoOut`; `checklistMinStep` 0,12; saída da ignição `hover` 0,12; cobertura 0,16 `standard`; troca de fase `standard` ~0,16 com `micro` 4; spinner pendente após `ignitionSkip`/f35 com fade `hover`.
- Reduce Motion (04 §5): tudo vira crossfade `policy.reducedCrossfade` 0,15 `ease`; sem chip, sem halo, spinner = anel completo parado, check sem desenho.

## Ajustes e dúvidas propostos (para o dono/04)
1. **M-108, direção do recorte.** 04 §6.3 escreve `inset(0 0 0 100%) → inset(0)`, que cresce a partir da borda da janela (painel à direita), mas o mesmo texto e §7.1.2 dizem "a partir da borda que encosta no terminal". Renderizei as duas (A = borda do terminal, B = borda da janela). Pendente: escolha do dono; se for A, corrigir a fórmula de §6.3 para `inset(0 100% 0 0)`.
2. **Altura da linha pendente.** 04 §7.2.1 diz vaga 0 → 28 pt; 03 §2.9 diz 32 pt (e a linha tem 2 linhas de texto). O protótipo usa 40 pt com a fase na linha 2, colapsando para 26 pt em T_ready. Sugiro fixar a altura em 03 e copiar para 04.
3. **Tempos de f2/f4 do M-501.** Os x/y de 04 §7.2.1 (0,46/0,56 em f3 etc.) não batem exatamente com `standard`/`expoOut` em 0,42 s; usei as curvas dos tokens, sem tabela alvo exata. Conferir no Motion Lab por medição, não pelo número de §7.
4. **Fonte.** Geist não está instalada na máquina de render; os vídeos usam a fonte do sistema (SF), com larguras ligeiramente diferentes. Não afeta o motion.
5. **Sem tokens novos.** Nenhum token foi adicionado ao `tokens.json`. O brilho de varredura da variante B e o recorte de 28 pt da variante B de M-101 usam só valores geométricos locais (candidatos a `draft` se o dono escolher B).
6. **Selo "pronto"/M-204.** A troca de fase usa `standard` com duração 0,16 calculada como `disclosure - 0,02` (o 04 diz 0,16 sem token próprio); proponho o token `phaseSwap` = 0,16.

## Recomendação
M-101: A (segue a spec e o gesto "nasce do botão" fica legível). M-501: A (arco + pouso `lively` mostram a chegada); B é a opção mais calma, C é a mais limpa em Reduce Motion parcial. Aprovação do dono pendente (P14/P19), então o status é `draft`.
