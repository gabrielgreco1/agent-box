# S-04: reattach com replay do ring, preâmbulo de modos e redraw `cols-1`

Data: 2026-10-17. Apple M4 Pro, macOS 27.0.1, Xcode 26 (Swift 6.2.4). Sem janela, sem permissão de tela.

## Pergunta

Um cliente novo consegue reconstruir a mesma tela de uma sessão viva a partir de (a) um ring de 4 MiB de bytes brutos, (b) um preâmbulo de modos, (c) um emulador SwiftTerm novo e (d) redraw forçado por `cols-1`/`cols`? O critério do roadmap (09 §2.2) é `textSnapshot` antes e depois iguais em 20 repetições, com Claude, Codex e `vim`. O vídeo do critério não foi gravado (exigiria gravar a tela; ver "Pendências").

## Método

Protótipo em `proto/` (código descartável, 570 linhas, Swift 5 mode, GCD):

- `rackyd` simplificado: um `forkpty` por sessão, leitura do master por `DispatchSource`, ring circular de 4 MiB com offset absoluto `seq`, emulador headless (`Terminal` do SwiftTerm) alimentado com o mesmo stream, respostas de DA/DSR escritas no PTY pelo daemon (AR-105).
- Protocolo reduzido, mesmo enquadramento da 06 §1.3: `u32 len | u8 kind | payload`, `kind` 1 controle (texto), 2 saída (`seq u64 | bytes`), 3 entrada. `attach` responde `snap start end preâmbulo-base64` e depois os bytes do replay em frames de 32 KiB, depois o stream ao vivo. `redraw` faz `cols-1`, espera 50 ms e volta a `cols`.
- Ponto de corte (06 §1.5): um rastreador de bytes marca o offset do último `ESC c`, `CSI 2J`, `CSI 3J` ou entrada em alt-screen (`?1049h`, `?47h`, `?1047h`) e guarda o preâmbulo do estado **anterior** à sequência. O preâmbulo é uma sequência VT: `?1049h` se estava em alt-screen, os modos DEC vistos (`?2004`, `?1`, `?25`, `?1000`, `?1006`...), keypad (`ESC =`/`ESC >`), título (OSC 0) e o cursor (`CUP`) lido do emulador headless no instante do corte. Sem corte no ring: início do ring precedido de `ESC c`.
- Por que um rastreador próprio: a API pública do `Terminal` (1.20.0 e 1.99.0) expõe `bracketedPasteMode`, `applicationCursor`, `mouseMode`, `isCurrentBufferAlternate`, `hostCurrentDirectory`, `getCursorLocation()`, mas **não** `cursorHidden`, `applicationKeypad`, o título nem a codificação de mouse (`internal`).
- Cliente: `Terminal` novo, sem responder consultas (o delegate descarta tudo; só o daemon responde), aplica o preâmbulo e os bytes.
- Harness (`s04 harness`): por repetição sobe um daemon novo, conecta A (que digita um roteiro) e um observador O (fica conectado), espera 500 ms de silêncio, tira `sa` = snapshot de A e `dref` = snapshot do emulador do daemon, **desconecta A**. Conecta B, `attach` sem redraw, espera silêncio e tira `sb0`; depois `redraw`, espera e tira `sb1`; tira `so` do observador. Resultados: **replay-only** `sa == sb0`; **after-redraw** `so == sb1`; **daemon-ref** `dref == sa`.
- O snapshot é o texto das linhas visíveis (sem espaços à direita) mais `alt`, `bracketedPaste`, `applicationCursor`, `mouseMode`, posição do cursor e tamanho. A comparação de after-redraw usa o observador porque o redraw muda legitimamente a tela (ex. o `vim` apaga a linha de comando `:set number` ao redesenhar, e isso aparece em A e em O, mas não em `sa`).
- Cenários (cada um 20 repetições, 100x30): `modes` (script que liga `?2004`, `?1`, `ESC =`, `?25l`, `?1000`, `?1006` e título), `zsh` (`-f -i`, comandos, texto digitado e não enviado), `less -N` (arquivo de 200 linhas, rolagem), `vim` (inserção, `:set number`), `vim-after-flood` (8 MB de texto antes do `vim`, ring estoura), `flood-nocut` (8 MB e nenhum ponto de corte), `alt-overflow` (entra em alt-screen e escreve 8 MB posicionados sem nenhum `2J`: o ponto de corte sai do ring), `claude` e `codex` (TUI real).
- Isolamento: `claude` com `CLAUDE_CONFIG_DIR` e `codex` com `CODEX_HOME` apontando para diretórios vazios no scratchpad, env do agente (`CLAUDE*`, `ORCA_*`, `RACKY*`) removido do filho (06 §1.7). Sem login, os dois mostram a tela de onboarding (Claude: escolha de tema; Codex: tela inicial de login). Nada foi enviado a nenhum modelo.
- Os sockets ficam em `/tmp/s04s/` (limite de 104 bytes do `sun_path`; o diretório foi removido ao fim).

## Comandos

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd docs/evidence/spikes/S-04/proto   # Package.swift aponta para ../s02/src/st-<versão> (clones de v1.20.0 e v1.99.0)
swift build -c release                                  # SwiftTerm 1.20.0
ST=1.99.0 swift build -c release --scratch-path .build199   # SwiftTerm 1.99.0
./.build/release/s04 harness "$PWD/work" 20             # todos os cenários, 20 repetições
./.build/release/s04 harness "$PWD/work" 20 vim         # um cenário
S04_CHECKPOINTS=1 ./.build/release/s04 harness "$PWD/work" 20 alt-overflow   # com a mitigação
# daemon avulso: s04 daemon <sock> <cols> <rows> <ringBytes> <cwd> <argv...>
```

Saídas brutas: `run-1.20.0.txt`, `run-1.99.0.txt`, `run-*-ckpt-alt-overflow.txt`.

## Números (20 repetições por célula; ambas as versões do SwiftTerm dão resultado idêntico)

| Cenário | Replay-only | After-redraw | Ref. do daemon == A | Início do replay |
|---|---|---|---|---|
| modes | 20/20 | 20/20 | 20/20 | início do ring (sem corte) |
| zsh | 20/20 | 20/20 | 20/20 | início do ring |
| less | 20/20 | 20/20 | 20/20 | corte (entrada em alt-screen) |
| vim | 20/20 | 20/20 | 20/20 | corte (entrada em alt-screen) |
| vim-after-flood | 20/20 | 20/20 | 20/20 | corte, offset 8 127 068 (ring de 4 MiB já girou) |
| flood-nocut | 20/20 | 20/20 | 20/20 | início do ring, offset 3 932 688, com `ESC c` |
| **alt-overflow** | **0/20** | **0/20** | 20/20 | início do ring, sem corte: **falha** |
| alt-overflow com checkpoints | 20/20 | 20/20 | 20/20 | checkpoint de 64 KiB |
| claude (onboarding) | 20/20 | 20/20 | 20/20 | início do ring |
| codex (onboarding) | 20/20 | 20/20 | 20/20 | corte |

Total: 180 repetições por versão sem a mitigação (160 passam, 20 falham, todas no `alt-overflow`), mais 20 com a mitigação (20 passam). Nenhum buraco de `seq` detectado no cliente (`gap=false` em todas as linhas).

## O que falha

1. **`alt-overflow` (reprovado 20/20 sem mitigação).** Se o ponto de corte (entrada em alt-screen ou `2J`) já saiu do ring e o programa só escreve com cursor posicionado, o replay começa no início do ring com `ESC c`. O cliente reconstrói a tela **no buffer principal**: `alt=false` e `mouseMode=off` em vez de `alt=true` e `mouseMode=vt200`, e a primeira linha vem cortada no meio ("row of alt contentt"). É exatamente o caso de um Claude ou Codex que transmite mais de 4 MiB dentro da mesma sessão alt-screen sem limpar a tela. O "`ESC c` + ring" da 06 §1.5 não basta.
   **Mitigação testada e aprovada (20/20 nas duas versões):** o daemon grava a cada 64 KiB, quando o rastreador está fora de sequência, um checkpoint `(seq, preâmbulo, cursor)` com o estado de modos naquele ponto; sem ponto de corte no ring, o replay começa no checkpoint mais antigo ainda no ring, precedido de `ESC c` e do preâmbulo. Custo: um `Set`/dicionário de modos por 64 KiB (cerca de 64 checkpoints num ring de 4 MiB). O checkpoint só é gravado com o rastreador fora de sequência; nesse teste a primeira linha do replay saiu íntegra.
2. **O redraw muda a tela de propósito.** `vim` apaga a linha de comando ao receber `SIGWINCH`; o critério "snapshot antes igual a depois" deve ser avaliado como (a) replay antes do redraw igual ao estado de A e (b) depois do redraw igual ao de um observador que recebeu os mesmos bytes. Comparar o `sa` com o `sb1` direto reprova o `vim` em 100% dos casos e não indica defeito do reattach.
3. **Preâmbulo depende de rastreador próprio.** `cursorHidden`, keypad de aplicação, título e codificação de mouse (`?1006`, `?1015`) não são públicos no `Terminal`. O rastreador de bytes do protótipo cobre isso, mas é código nosso a manter e a testar com fixtures (sequências partidas entre chunks, `ESC` dentro de `CSI`).
4. **Não verificado pelo comparador:** atributos (cor, negrito), scrollback, forma e visibilidade do cursor, título, estado de SGR e de charset no ponto de corte. O corte em `CSI 2J` no meio de um estilo SGR aplicado antes perde esse estilo (o preâmbulo não carrega SGR). O comparador só vê texto visível e os cinco modos públicos. O critério visual (cores) precisa do vídeo ou de comparação de células por atributo no T1-06.
5. **Claude e Codex só foram exercitados até a tela de onboarding** (sem login, sem chamar o modelo). Prova modos pesados (Claude usa alt-screen, mouse e bracketed paste) e redraw, mas não o REPL com streaming de resposta, o spinner nem o rodapé de status. Repetir com sessão autenticada exige credencial e pode ter custo; não foi feito.
6. **Ring cheio exige cortar em linha.** No `flood-nocut` o replay começa no meio de uma linha; a linha parcial fica fora da tela e o teste passa, mas com texto longo sem quebra a primeira linha visível poderia aparecer cortada. Aceitável (mesmo comportamento de qualquer terminal ao reabrir um buffer circular).
7. **Backpressure não testado.** O protótipo escreve no socket de forma síncrona na fila do daemon (SO_SNDBUF de 1 MiB); um cliente lento bloquearia a sessão. O `resyncRequired` e a fila de 2 MiB por cliente da 06 §1.3 não foram implementados aqui.
8. **Armadilhas de implementação encontradas:** (a) `DispatchSource` sem referência forte para de entregar eventos (o daemon ficou mudo; guardar fonte de accept, de leitura do master e de cada cliente); (b) em Swift 6 em modo release o objeto local é liberado depois do último uso, então o daemon precisa de referência global antes de `dispatchMain()`; (c) caminho do socket tem limite de 104 bytes: o caminho do scratchpad estoura, daí `/tmp/s04s`. O `launch_activate_socket` da 06 §1.2 já resolve o (c) em produção; (a) e (b) valem para o `rackyd`.

## Conclusão

O desenho da 06 §1.5 funciona: replay de bytes mais preâmbulo mais redraw por `cols-1`/`cols` reconstrói exatamente a tela em 160 de 160 repetições de cenários que têm ponto de corte no ring ou que cabem no ring (8 de 9 cenários, `vim`, `less`, shell com bracketed paste, modos pesados, Claude e Codex em onboarding), nas duas versões do SwiftTerm. Ele falha num caso concreto e plausível, alt-screen com mais de 4 MiB de saída sem corte, e a mitigação por checkpoints a cada 64 KiB o resolve. O critério do roadmap (snapshots antes e depois iguais em 20 repetições com Claude, Codex e `vim`) está atendido em texto para os três, com as ressalvas 4 e 5.

## Recomendação

Adotar a 06 §1.5 com o texto abaixo (checkpoints, avaliação do critério em duas etapas, rastreador próprio) e acrescentar ao T1-06 um teste `alt-overflow` e uma fixture de rastreador com sequências partidas. Antes de fechar o S-04: gravar o vídeo do critério e repetir Claude/Codex autenticados em rodada agendada.

## Texto proposto para a 06 §1.5 (substitui o bullet "Ponto de corte")

> **Ponto de corte e checkpoints**: o daemon marca o offset do último `ESC c`, `CSI 2J`/`CSI 3J` ou entrada em alt-screen (`?1049h`, `?47h`, `?1047h`) e guarda, junto, o preâmbulo do estado anterior àquela sequência. Além disso, a cada 64 KiB de saída, quando o parser está fora de sequência, grava um checkpoint `(seq, preâmbulo, posição do cursor)`. O replay começa no corte mais recente que ainda está no ring; se não houver, no checkpoint mais antigo que ainda está no ring, precedido de `ESC c` e do preâmbulo; só se nem checkpoint houver, no início do ring precedido de `ESC c`. O estado de modos que o `Terminal` do SwiftTerm não expõe publicamente (cursor visível, keypad de aplicação, título, codificação de mouse) é mantido por um rastreador de bytes do próprio daemon, coberto por fixtures com sequências partidas entre frames. Critério de aceite (S-04): com `vim`, `less`, shell com bracketed paste, Claude e Codex, (a) o texto e os modos do replay antes do redraw são iguais aos do cliente que ficou conectado, e (b) depois do redraw `cols-1`/`cols` são iguais aos de um observador que recebeu os mesmos bytes; inclui um teste de alt-screen com mais de 4 MiB sem corte.

## Texto proposto para a AR-122 (parte do daemon)

> O emulador headless do daemon e o do cliente são o `Terminal` do SwiftTerm na versão fixada nesta tabela. Como a API pública não expõe `cursorHidden`, `applicationKeypad`, título nem codificação de mouse, o preâmbulo de reattach (06 §1.5) usa um rastreador de bytes próprio no `rackyd`, e o teste de reattach (`DaemonTests`) roda nas duas versões enquanto o S-02 estiver aberto.

## Pendências

- Vídeo do critério e Claude/Codex autenticados: rodada agendada com o dono (gravação de tela e credencial).
- Comparação por atributo de célula (cor/negrito) e do scrollback.
- Backpressure real (fila por cliente, `resyncRequired`) e peer auth: S-03 e T-06.
- `Package.swift` do protótipo depende dos clones locais `../s02/src/st-1.20.0` e `st-1.99.0` (`git clone --branch v1.20.0 https://github.com/migueldeicaza/SwiftTerm`); não faz parte do repositório.
