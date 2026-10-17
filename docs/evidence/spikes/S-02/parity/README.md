# S-02: diferença de getBufferAsData entre 1.20.0 e 1.99.0 (condição de P20)

Dump ANSI determinístico de 64 MiB (o do bench do S-02, 120x40, scrollback 10 000), `getBufferAsData(kind: .active)`: 955 841 bytes na 1.20.0 (217 293 deles NUL) e 931 868 na 1.99.0 (nenhum NUL). Fontes: `dump.swift` (corpus) e `probe.swift` (casos mínimos, saída em `probe-output.txt`).

## Causas (três, todas na 1.99.0 mais correta)

1. Célula de continuação de caractere largo (CJK, emoji): a 1.20.0 emite um byte NUL; a 1.99.0 a pula (correção #718, "Fix NUL characters in getBufferAsData output"). `日本語` sai como `日\0本\0語\0` na 1.20.0 e `日本語` na 1.99.0.
2. Célula nunca escrita no meio da linha: NUL na 1.20.0, espaço na 1.99.0 (`ab\0\0\0c` x `ab___c`).
3. Caractere largo partido por escrita, EL, ECH, ICH ou DCH sobre uma das metades: a 1.20.0 deixa a metade órfã (glifo velho sobrevivente, ex.: `日` solto); a 1.99.0 limpa a metade, como o xterm. É a única diferença de conteúdo do emulador, e só aparece com larguras mistas sobrescritas.

## Verificação

- Corpus sem caracteres largos (mesmo gerador, sem `日本語`): 932 685 bytes nas duas versões; com NUL trocado por espaço, a saída da 1.20.0 é idêntica byte a byte à da 1.99.0.
- Grade visível (`getCharData`) das 40 linhas da tela: idêntica nas duas, também com larguras mistas.

## Decisão (P20)

Explicável: adotar a 1.99.0 (rev `2dad6a1`). Nenhum consumidor nosso depende dos NUL (o `textSnapshot` do daemon divide por `\n` e corta espaços à direita); `DaemonTests`, `TerminalCoreTests` e `CoreTests` passam na 1.99.0 sem mudança de código no daemon.
