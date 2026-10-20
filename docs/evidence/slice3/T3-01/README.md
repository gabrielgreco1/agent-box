# T3-01 · Docker e imagens

Alvo `RackyDocker` (`Packages/RackyKit/Sources/RackyDocker/`), imagem do runtime da box (`runtime/box/`), migração `v3_computers` no Store e os spikes S2 e S9 (`docs/evidence/spikes/S2`, `S9`). Base: 08 AR-114/AR-121/AR-404, 07 §2.1 a §2.4 e §2.8, 00 T7/T9/P13.

## O que entrou

| Peça | Arquivo(s) | Notas |
|---|---|---|
| Transporte HTTP/1.1 sobre UDS | `DockerTransport.swift`, `HTTPCodec.swift` | Sobre o `UDSConnection` da Platform (DispatchSource, não bloqueante). Uma conexão por requisição, chunked, content-length, streaming, hijack (`101`/`200`). Prazo por operação (`withDeadline`) e cancelamento real (fecha o socket) |
| Cliente da Engine API | `DockerClient.swift` | `_ping`, `version`, `info`; imagens (inspect, list, tag, remove, **pull por digest** com progresso, **build com contexto tar**); containers (create, start, stop, kill, remove, inspect, list, wait, logs, stats, exec); redes (`internal`), volumes; `events` com filtro por label. Início/stop `304` e remove/`404` são idempotentes |
| Exec hijacked | `ExecSession.swift` | stdin, stdout e stderr independentes, half-close do stdin (`UDSConnection.finishWriting()`, novo na Platform), código de saída por inspect, `terminate` (SIGTERM, depois SIGKILL no grupo) com wrapper opcional `killableGroup` |
| Detecção do runtime | `RuntimeDetector.swift` | Ordem de 07 CS-101: `DOCKER_HOST` (`unix://`), contexto ativo (`DOCKER_CONTEXT`/`currentContext` + `contexts/meta/<sha256>/meta.json`, o mesmo que `docker context inspect`) e sockets conhecidos (Desktop, OrbStack, `~/.colima/<perfil>`, `/var/run`). Sem CLI, sem PATH. Valida com ping, version e info; classifica Desktop/OrbStack/Colima; `startCommand` por runtime |
| Capacidade | `Capacity.swift` | `MemTotal` da VM -> admissão `soma(estimativas) + nova <= M - 2 GiB`, fila (`.queue(reason: "memory")`), recusa por disco, média móvel de 20 amostras, aviso `Docker VM has 8 GB. 15 headless and 2 desktop computers need about 26 GB.` |
| Eventos | `EventMonitor.swift` | `events` filtrado por label com reconexão e `since`; emite `.resync` a cada (re)conexão para o chamador reconciliar (CS-103) |
| GC por labels | `GarbageCollector.swift`, `Labels.swift` | Inventário por label (nunca sem filtro), plano órfão/efêmero-terminado (CS-181), remoção na ordem containers, redes, volumes, `removeComputer` que mantém perfil nomeado (CS-180) |
| Imagens | `Images/BuildContext.swift`, `Images/ImageManager.swift` | Hash determinístico do contexto, tag `repo:ctx-<sha12>`, tar ustar determinístico; `ImageManager.ensure`: presente, pull por digest do GHCR (confere o label `racky.context_hash`), ou build local; progresso (`building(step, of)`) |
| Erros tipados | `DockerError.swift` | `runtimeUnavailable` (-> `docker_unavailable`), `notFound`, `conflict`, `timeout`, `cancelled`, `imagePullFailed`, `imageBuildFailed`, `execNotKillable`... |
| Imagem `racky-box` | `runtime/box/{Dockerfile,requirements.txt,entrypoint.sh}`, `runtime/images.json`, `scripts/build-runtime-image.sh` | Base Playwright Python por digest, **sem pins de apt**, pip com versões exatas; usuários 10001/10002; entrypoint ocioso por papel (API de ações e ferramentas entram na T3-03). O script calcula o mesmo hash do Swift (teste compara) e builda com `docker build` |
| `v3_computers` | `RackyStore/Schema.swift` | `computer`, `computer_queue`, `browser_profile`, `help_request`, `proxy`, `proxy_usage` conforme 08 §3.2, sem colunas de limite/orçamento (P13) |

CS-106 (create que estoura o prazo): `createContainer` repete `rm -f` pelo nome determinístico por ~2,5 s, porque o create pode ainda chegar ao daemon depois do timeout. Isso foi um bug real achado pelo teste vivo: a primeira versão fazia um `rm -f` só e deixou dois containers órfãos, que removi (eram meus, com `racky.test=1`).

## Testes (todos passam)

`swift test` com `RACKY_TEST_DOCKER=1`: **572 testes, 0 falhas** (`swift-test-summary.out`). `scripts/gen.sh`, `scripts/build.sh` e `scripts/lint.sh` (+ `--self-test`) passam. Sem `RACKY_TEST_DOCKER=1` as suítes vivas ficam `skipped` e o Docker não é tocado.

- Unidade (`DockerTests`, sem Docker): codec HTTP (head, chunked byte a byte, linhas JSON, demux 8 bytes), modelos com **fixtures capturadas do Docker real** (info Desktop; OrbStack e Colima sintéticos; inspect, list, network, volume, image, eventos, erros 404/409) e de pull/build, `ContainerSpec` (hardening de CS-114), detecção com sistema de arquivos falso, capacidade (conta de referência de 07), contexto de build (hash estável, igual ao do script, tar lido pelo `bsdtar`), GC, `EventMonitor` e o cliente completo contra um **daemon falso em UDS** (status -> erro tipado, 304/404 idempotentes, chunked fatiado, pull/build com erro, logs demultiplexados, hijack com half-close, prazo/cancelamento, create atrasado reconciliado, 20 chamadas de 2 s em paralelo com lacuna do pool < 50 ms: AR-404).
- Integração com o Docker real (`LiveDockerTests`, `LiveNetworkTests`; só com `RACKY_TEST_DOCKER=1`, tudo com `racky.test=1` + `racky.test_run=<id>`, o teste falha se sobrar recurso): runtime detectado igual ao `docker context inspect`; pull por digest e build por tar; tag por hash e fallback do GHCR; create/start/inspect/wait/logs/stop/remove com eventos `create,start,die,destroy`; conflito de nome; exec (stdin, stderr, exit 7, 2 MiB ida e volta, 16 MiB de saída, stdin interativo, 6 execs concorrentes); S9; GC; S2; 20 inspects/execs simultâneos.
- Teste lento opcional (`RACKY_TEST_BUILD_RUNTIME_IMAGE=1`): builda o `runtime/box` real pela Engine API (builder clássico), 14 de 14 passos em ~61 s, e roda o smoke (uid 10002, Python com `curl_cffi`, `httpx`, `lxml`, `bs4`, `openpyxl`, `requests`, `playwright`; Xvfb, x11vnc, websockify, xdotool, dtach, jq). O mesmo contexto também builda com `scripts/build-runtime-image.sh` (BuildKit): `box-image-cli-build.log`.
- Store: `ComputersMigrationTests` (migra de fixture v1 com dados e backup pré-migração, CHECKs, FKs e cascatas, ausência de colunas de orçamento, linha completa) e `MigrationTests` atualizado (agora v1 + v3).
- Platform: `HalfCloseTests` para `finishWriting`.

## Evidência [L]

`live-runtime.json` (Desktop, Engine 29.6.2, API 1.55, aarch64, MemTotal 8,32 GB, 14 CPUs, 4 headless e 2 desktop cabem, aviso de 26 GB), `live-images.json`, `live-lifecycle.json`, `live-exec.json`, `live-gc.json`, mais `spikes/S2/` e `spikes/S9/` (README + `results.json`).

## Cobertura dos ACs (o que esta tarefa fecha e o que não)

| AC | Estado |
|---|---|
| AC-T21 (tag = hash do contexto; build local sem pins de apt com o registry fora) | Coberto: unidade (hash/tag, script igual ao Swift) e vivo (pull de digest inexistente cai para build local; `runtime/box` sem pins de apt) |
| AC-T22 (create estourando prazo, nenhum container sem registro) | Coberto na camada Docker: reconciliação por `rm -f` com repetição + teste vivo e de unidade. A reconciliação pelos **eventos** com o banco é do `ComputerService` (T3-04): `EventMonitor` e `GarbageCollector.plan` já entregam as peças |
| AC-T20 (Desktop, OrbStack, Colima, app aberto pelo Finder, credential helpers) | **Parcial**: tudo pela Engine API com eventos no Docker Desktop, sem depender do PATH. OrbStack e Colima não estão instalados aqui (detecção e classificação cobertas por unidade). Credential helpers: o pull é pela Engine API (aceita `X-Registry-Auth`); o caminho com CLI + PATH ampliado para registry privado não foi feito (GHCR público, decisão 12) |
| AC-105, AC-106, AC-107 | **Só a base de engine**: detecção, `startCommand`, capacidade/`vmSizeWarning`, pull com progresso, `ensure` e build local. Os itens de checklist do onboarding ("Start Docker", "Download", "Build Locally", "Ready") são UI de outra tarefa; "Start Docker" precisa de `Process` no app (fora da Platform proibido por lint) e espera de socket |

## O que **não** foi feito

- Computadores de ponta a ponta (`ComputerService`, rede + egress + runtime + work, token por arquivo, ComputerScheduler/fila persistente): T3-02 a T3-04. `ComputerQueue` existe só como tabela.
- Imagem `racky-egress` e o runtime/API de ações dentro de `racky-box` (T3-02, T3-03). O entrypoint atual só fica ocioso.
- Publicação no GHCR e digest embutido: `runtime/images.json` tem `ghcr`/`digest` nulos; sem `push` (instrução da tarefa). O caminho de pull por digest está testado contra um digest real do Docker Hub (alpine) e contra um GHCR inexistente.
- Build com BuildKit/`--progress=rawjson` pelo CLI dentro do app (CS-121): a Engine API só faz o builder clássico (BuildKit exigiria o protocolo de sessão gRPC). O app tem o build clássico por tar; `scripts/build-runtime-image.sh` usa o BuildKit.
- Teste em OrbStack e Colima (S2, S9, AC-T20): não instalados.
- Dockerfile sem `COPY --chmod` de propósito (builder clássico não entende).
- `v2_activity` ainda não existe na branch: `computer.owner_run_id`, `help_request.run_id` e `proxy.secret_id` não têm FK (como `batch_id` em 08). Quando `v2_activity` entrar, a ordem dos ids no migrator precisa continuar `v1, v2, v3` (GRDB aplica pendentes em ordem de registro).
- Estimativas de memória (07 §2.4) continuam números de partida, sem medição com o lote de 15.

## Limpeza

Todos os recursos de teste tinham `racky.test=1`. Ao final: 0 containers, redes, volumes e imagens com esse label. Também removi as imagens que as tarefas puxaram sem label (`alpine@sha256:d9e853e8...` e a base `mcr.microsoft.com/playwright/python:v1.63.0-noble@sha256:72bd171a...`); `docker images` voltou às 3 imagens que já existiam (`racky:latest`, `hacker-ops-worker:local`, `pgvector/pgvector`). O cache do BuildKit cresceu com os builds (não removi: `docker builder prune` não distingue o que é meu).
