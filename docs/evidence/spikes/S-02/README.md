# S-02: SwiftTerm 1.20.0 x 1.99.0

Data da medição: 2026-10-17. Máquina: Apple M4 Pro, macOS 27.0.1, Xcode 26 (Swift 6.2.4), tela de 120 Hz. Sem permissões de tela.

## Pergunta

Qual versão do SwiftTerm a AR-122 deve fixar para v1: a 1.20.0 (`5d14406`, pin atual) ou a 1.99.0 (`2dad6a1`, 2026-10-08, pré-release da v2)? Quatro pontos do roadmap (09 §2.2 S-02): Metal, `feed` fora do main thread e `send` de outra thread, busca e OSC 133/7, e latência com 4 panes e `yes | head -c 200M`.

## Método

1. Leitura do código das duas tags (`git clone --depth 1 --branch v1.20.0|v1.99.0`) e das notas de release (`gh release view`). Não existe `CHANGELOG.md` no repositório; a fonte é a página de release.
2. Benchmark headless: `Terminal` alimentado com `feed(buffer:)` em blocos de 64 KiB (e de 1 KiB), 120x40, scrollback de 10 000, build `-c release`, melhor de 3 execuções (variação menor que 2%). Cargas: `yes | head -c 200M` (arquivo de 200 MiB lido em memória) e um dump ANSI determinístico de 64 MiB (SGR truecolor e 256 cores, CUP, EL, texto UTF-8 com CJK, box drawing e emoji).
3. Teste funcional de OSC 7 e OSC 133 em `Terminal` headless.
4. App mínimo AppKit com 4 `TerminalView` (2x2, janela de 1200x800) e `setUseMetal(true)`, medindo o intervalo entre callbacks de `CADisplayLink` (120 Hz, 8,33 ms) por 10 s, com carga ANSI ou de rolagem. Modos: `main` (feed no main com o orçamento da AR-406: 64 KiB por pane por quadro, 4 ms somados) e `bg` (uma thread por pane chamando `feed` em loop, só na 1.99).

## Comandos

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# pacotes em scratchpad/spikes/s02: bench-120 e bench-199 (headless), app-120 e app-199 (janela), osc-120 e osc-199
yes | head -c 209715200 > yes200.bin
(cd bench-120 && swift build -c release) && ./bench-120/.build/release/bench yes200.bin
(cd bench-199 && swift build -c release) && ./bench-199/.build/release/bench yes200.bin
# janela (abre uma janela por ~10 s; ver "Pendências")
./app-120/.build/release/app main 1 10 ansi      # args: modo(main|bg) metal(1|0) segundos carga(ansi|scroll)
./app-199/.build/release/app bg 1 10 scroll
```

Fontes em `docs/evidence/spikes/S-02/bench/` (`Package.swift.tmpl` com `@V@` = `1.20.0` ou `1.99.0`; o app da 1.99 define `-D BG` para o modo `bg`). Saídas brutas: `bench-120.out`, `bench-199.out`, `app-results.txt`.

## Números

### Parse headless (MiB/s, 1 thread)

| Carga | 1.20.0 | 1.99.0 | Razão |
|---|---|---|---|
| `yes` 200 MiB (blocos de 64 KiB) | 4,2 MiB/s (47,7 s) | 45,6 MiB/s (4,4 s) | 10,8x |
| ANSI pesado 64 MiB | 26,1 MiB/s (2,45 s) | 139,3 MiB/s (0,46 s) | 5,3x |
| ANSI 16 MiB em blocos de 1 KiB (leitura típica de PTY) | 26,1 MiB/s | 129,2 MiB/s | 4,9x |

Consequência para a AR-406 (4 ms de `feed` por quadro): na 1.20.0 isso são cerca de 100 KiB por quadro com ANSI e 17 KiB com `yes`; na 1.99.0, cerca de 550 KiB e 180 KiB. O teto de 256 KiB por pane por quadro só é alcançável na 1.99.0. Sobre a diferença de texto no fim: `getBufferAsData` devolve 955 841 bytes na 1.20.0 e 931 868 na 1.99.0 para o mesmo dump ANSI; no `yes` os dois dão 1 214 720. A causa não foi investigada (a release da 1.99.0 cita "Fix NUL characters in getBufferAsData output", #718, que explica parte); precisa de um teste de conformidade antes de trocar de versão.

### 4 panes com Metal, janela visível, 120 Hz (10 s por linha)

Intervalo entre quadros em ms (alvo 8,33), "perdidos" = intervalo maior que 12,5 ms.

| Versão / modo | Renderer | Carga | p50 | p99 | máx | Perdidos / quadros | Trabalho no main (p99) | Alimentado |
|---|---|---|---|---|---|---|---|---|
| 1.20.0 feed no main | Metal | ansi | 8,34 | 16,71 | 42,85 | 74 / 1161 | 6,44 ms | 13,9 MiB/s |
| 1.20.0 feed no main | CoreGraphics | ansi | 8,33 | 16,67 | 75,02 | 33 / 1263 | 6,27 ms | 14,3 MiB/s |
| 1.99.0 feed no main | Metal | ansi | 8,33 | 8,39 | 19,68 | 4 / 1310 | 3,35 ms | 29,4 MiB/s |
| 1.99.0 feed no main | CoreGraphics | ansi | 9,47 | 13,92 | 20,02 | 41 / 1124 | 3,03 ms | 24,8 MiB/s |
| 1.99.0 feed em 4 threads | Metal | ansi | 8,33 | 8,36 | 15,67 | 2 / 1310 | 0,00 ms | 432 MiB/s |
| 1.99.0 feed em 4 threads | CoreGraphics | ansi | 8,79 | 13,61 | 17,48 | 16 / 1201 | 0,00 ms | 427 MiB/s |
| 1.20.0 feed no main | Metal | rolagem | 8,34 | 16,68 | 16,74 | 239 / 1010 | 8,04 ms | 11,0 MiB/s |
| 1.20.0 feed no main | CoreGraphics | rolagem | 8,34 | 16,68 | 16,68 | 252 / 1057 | 8,04 ms | 11,2 MiB/s |
| 1.99.0 feed no main | Metal | rolagem | 8,33 | 8,35 | 8,61 | 0 / 1313 | 2,33 ms | 29,5 MiB/s |
| 1.99.0 feed no main | CoreGraphics | rolagem | 8,33 | 9,92 | 18,65 | 5 / 1299 | 1,81 ms | 29,1 MiB/s |
| 1.99.0 feed em 4 threads | Metal | rolagem | 8,33 | 8,35 | 8,61 | 0 / 1311 | 0,00 ms | 587 MiB/s |
| 1.99.0 feed em 4 threads | CoreGraphics | rolagem | 8,34 | 9,15 | 16,39 | 2 / 1301 | 0,00 ms | 594 MiB/s |

Leitura: com o mesmo orçamento do main, a 1.20.0 perde de 6% a 24% dos quadros a 120 Hz e fica em 60 Hz efetivos sob rolagem pesada (p50 8,34 ms mas p95 e p99 em 16,7 ms); a 1.99.0 com Metal quase não perde quadros e processa o dobro de bytes no mesmo orçamento. Com `feed` fora do main (só 1.99.0), o main fica sem trabalho de parse e o quadro se mantém em 8,33 ms mesmo com 430 a 590 MiB/s somados nos 4 panes. Em todos os casos Metal foi ativado nos 4 panes (`isUsingMetalRenderer`), sem erro. Metal na 1.99.0 foi melhor que CoreGraphics na mesma versão; na 1.20.0 Metal e CoreGraphics ficaram parecidos porque o gargalo é o parse no main.

Limites da medição: a carga é sintética e roda sem PTY real; o teste mede cadência de quadros (display link) e não latência de tecla até pixel; uma execução por linha; a janela foi aberta em primeiro plano (`NSApp.activate`), então a cadência não deve ter sido reduzida por oclusão, mas isso não foi verificado.

## Comparação por API (código das duas tags)

| Ponto | 1.20.0 | 1.99.0 |
|---|---|---|
| Metal, API pública na view macOS | `setUseMetal(_:) throws`, `isUsingMetalRenderer`, `metalRendererStatus` (struct pública com estado e contagem de quadros), `metalBufferingMode`, `metalScaleFactorOverride`, `drawMetalFrameNow()` | `setUseMetal(_:) throws`, `isUsingMetalRenderer`, `metalBufferingMode`, `metalScaleFactorOverride`, `drawMetalFrameNow()`, `usesMetalLayerSurface`, `setUsesMetalLayerSurface(_:)`. `metalRendererStatus` não existe mais |
| `feed` fora do main | A doc diz "pode ser chamado de thread de fundo", mas não há lock entre o parse e o desenho no main (`feedPrepare` mexe em `search` e `selection` sem lock); o desenho é agendado com `DispatchQueue.main.async`. Não é seguro como contrato | `public nonisolated func feed(byteArray:)`, serializado por `TerminalLock` (FIFO, justo); medido acima com 4 threads e Metal sem quadros perdidos de forma relevante |
| `send(data:)` de outra thread | **Só no main.** A doc (F.4) proíbe: `terminal.registerUserInput` roda a heurística do OSC 133 e corre com o parser; `assert(Thread.isMainThread)` em DEBUG | `public nonisolated func send(data:)`, documentado como "callable from any thread"; proibido apenas dentro de callback do delegate (lock já tomado; há `precondition`). Ordem entre chamadores concorrentes é do chamador |
| Delegate | `TerminalViewDelegate` sem isolamento | `@MainActor`; o app precisa de delegate isolado no main |
| Acesso ao `Terminal` a partir da view | `terminalView.terminal` público | `terminal` virou `internal`; restam `getBufferAsData`, `visibleRowsText(_:)`, `terminalDimensions`, `programStatusRecords`, `observeOscEvents`. Quem quer o `Terminal` usa `HeadlessTerminal` ou `Terminal` próprio (o daemon já faz) |
| Busca | `findNext`, `findPrevious`, `searchMatchSummary`, `clearSearch` (públicas, em `TerminalViewSearch.swift`) | Mesmas quatro, mesma assinatura |
| OSC 7 | `hostCurrentDirectoryUpdated(source:)` no `TerminalDelegate` e `hostCurrentDirectory` | Idem. Testado: um evento e `file://myhost/Users/x/proj%20a`, igual nas duas |
| OSC 133 | `semanticPromptMarks(at:)`, `semanticRowKind(at:)`, `semanticContent(at:)`, cliques semânticos | Idem. Testado com A/B/C/D: duas marcas e `rowKind` iguais nas duas |
| OSC 7501 | não existe | `programStatusRecords` (nova; não faz parte do nosso protocolo) |
| `HeadlessTerminal` | `Terminal` sem lock; `dataReceived` sem lock | Com `terminalLock` e `directDelivery` opcional |
| Pipeline de I/O | `LocalProcess` clássico | `TerminalIOPipeline` (gather + parse thread, portado do Ghostty), só relevante para `LocalProcess`, que o AR-122 já proíbe na UI |
| Ferramentas | swift-tools 6.0 | swift-tools 6.2 (Xcode 26.x atende; era o que estava instalado) |
| `clipboardRead` | método obrigatório do delegate | idem (T6 segue valendo: o delegate responde sempre `nil`) |

Notas de release da 1.99.0 (trecho relevante): "2.0 is a major performance upgrade, but it came at the expense of changing some APIs and will require some changes from applications. I am making 1.99.0 available so we can work through the various pending tasks". Nenhum teste de estabilidade de longa duração, seleção, IME, acessibilidade ou fuzz foi feito aqui; o repositório da 1.99.0 traz um alvo de fuzz (`SwiftTermFuzz`) e `Docs/fuzzing.md`.

## Conclusão

1. Na 1.20.0 o orçamento da AR-406 (4 ms por quadro no main) não sustenta 4 panes em 120 Hz com saída pesada: perde de 6% a 24% dos quadros e o parse fica entre 4 e 26 MiB/s.
2. A 1.99.0 resolve os dois pontos que a spec deixou para o S-02: `feed` seguro fora do main (medido, 430 a 590 MiB/s em 4 panes sem tocar o main) e `send` de qualquer thread. Parse de 5x a 11x mais rápido.
3. O preço é uma pré-release com API mudada: `terminal` interno, delegate `@MainActor`, `metalRendererStatus` removido. O que o app e o daemon usam (busca, OSC 7, OSC 133, Metal, `Terminal` headless) segue com a mesma assinatura.

## Recomendação

Fixar a **1.99.0 (rev `2dad6a1`) para a Fatia 3 (T-09)** em vez da 1.20.0, condicionada a dois testes de aceite antes do merge do T1-09: (a) paridade de conteúdo do `Terminal` entre 1.20.0 e 1.99.0 sobre o corpus de captura (a diferença de 955 841 x 931 868 bytes no dump ANSI precisa de explicação); (b) o `ProtocolTests`/`TerminalCoreTests` do daemon rodando na 1.99.0 (o protótipo S-04 já roda nas duas, resultado em S-04). Plano de recuo: se a v2 final mudar a API de forma incompatível ou o item (a) revelar divergência de rendering, ficar na 1.20.0 com o orçamento da AR-406 reduzido (no máximo 64 KiB por pane por quadro e 2 quadros de atraso aceitos). O dono ratifica a versão (roadmap S-02). O repositório continua com 1.20.0 até essa ratificação.

## Texto proposto para a AR-122 (linha SwiftTerm) e AR-406

> SwiftTerm **1.99.0 exato** (rev `2dad6a1`, tag `v1.99.0`), decisão do S-02 (`docs/evidence/spikes/S-02`). Medido contra a 1.20.0 num M4 Pro: parse headless 5x a 11x mais rápido (139 x 26 MiB/s em ANSI; 45,6 x 4,2 MiB/s em `yes`); com 4 panes em Metal a 120 Hz, perda de quadros de 0% a 0,3% contra 6% a 24%. `feed(byteArray:)` e `send(data:)` são `nonisolated` e seguros em qualquer thread (não chamar de dentro de callback do delegate). Como a 1.99.0 é pré-release da v2, o `Package.resolved` fixa a revisão, a troca para a 2.0 final exige nova decisão aqui, e o teste de paridade com a 1.20.0 sobre o corpus de captura é critério de aceite do T1-09. `terminal` não é público na view: o app não lê o `Terminal` da view; leitura de texto usa `getBufferAsData`/`visibleRowsText` ou o emulador headless do daemon. Mantém as proibições: `LocalProcessTerminalView`, `TerminalFindBarView`/`performFindPanelAction`.

AR-406, trecho a trocar: "Parse fora do main fica para o spike S-02: …" por: "Com a 1.99.0 (S-02), o `PTYClient` pode chamar `TerminalView.feed` de uma fila por pane fora do main; o orçamento de 256 KiB e 4 ms por quadro continua valendo como teto de fila e backpressure, mas deixa de ser trabalho do main. O backlog de 4 MiB por pane e o `resyncRequired` permanecem."

## Pendências

- **Rodada com janela visível exige agendamento do dono.** A medição de frame time abriu uma janela de 1200x800 por cerca de 10 s por configuração (12 configurações) e foi interrompida a pedido do dono por surpresa. Os números acima já estão capturados; qualquer repetição ou ampliação (por exemplo 8 panes, PTY real, latência de tecla) requer rodada agendada com o dono presente. Comando exato: `cd /private/tmp/claude-501/-Users-gabriel-orca-workspaces-agent-box-otter/5dda428d-ecea-4852-b667-584fd17012cc/scratchpad/spikes/s02 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./app-199/.build/release/app bg 1 10 scroll` (troque `app-199` por `app-120` e `bg` por `main` conforme a tabela).
- Não medido: `send` concorrente com `feed` na view da 1.99.0 (a garantia vem do código e da doc, não de teste), `feed` em thread de fundo na view da 1.20.0 (só do código: sem lock), busca sob carga, memória por pane, latência de tecla até pixel.
