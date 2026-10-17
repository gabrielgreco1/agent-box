# Spike S9 · Exec com stdin pela Engine API (hijack sobre UDS) e cancelamento por grupo

Pergunta (07 §9, CS-102): dá para rodar `exec` com stdin, stdout e stderr independentes pela Engine API sobre o socket Unix (sem o CLI), sinalizar EOF do stdin e cancelar com SIGTERM e depois SIGKILL no grupo de processos, sem bloquear o pool cooperativo?

## Resultado: APROVADO no Docker Desktop (arm64)

Máquina: Docker Desktop, Engine 29.6.2, API 1.55, aarch64; cliente em `/v1.43`. Código: `AgentBoxDocker/DockerTransport.swift` (hijack), `ExecSession.swift`. Testes: `Tests/DockerTests/LiveDockerTests.swift` (`execStdinStdoutStderrExitCodeAndHalfClose`, `s9TerminateKillsTheProcessGroupAndEscalatesToSigkill`, `twentyConcurrentInspectsAndExecsStayResponsive`), mais os testes de unidade contra um daemon falso (`ClientTests.swift`) e `PlatformTests/HalfCloseTests`.

| Pergunta | Resultado medido |
|---|---|
| Upgrade da conexão | `POST /exec/{id}/start` com `Connection: Upgrade` + `Upgrade: tcp` responde `HTTP 101`, `Content-Type: application/vnd.docker.multiplexed-stream`. O cliente aceita também `200` (alguns runtimes) |
| Stdin e EOF | `cat` recebe o stdin inteiro e termina: o half-close (`shutdown(SHUT_WR)`) feito pelo cliente chega ao processo através do proxy do Docker Desktop. `UDSConnection.finishWriting()` (novo em `AgentBoxPlatform`) espera os bytes pendentes saírem antes do `SHUT_WR` |
| stdout e stderr | Frames de 8 bytes (`kind`, 3 zeros, tamanho big endian) separam os dois fluxos; `sh -c 'echo out; echo err >&2; exit 7'` devolve `out`, `err` e código 7 (via `GET /exec/{id}/json`) |
| Integridade e volume | 2 MiB binários de stdin voltam idênticos; 16 MiB de stdout sem perda; stdin interativo em pedaços (`a`, pausa, `b`, fecha) |
| SIGTERM no grupo | O processo do exec é líder de sessão e de grupo (`pid == pgid == sid`, verificado com `ps -o pid,pgid,sid`), então `kill -s TERM -- -<pid>` alcança os filhos. Wrapper `sh -c 'echo $$ > /tmp/.abx-exec-<uuid>; exec "$@"'` registra o PID. Medido: pai + 2 filhos `sleep` morrem, exit **143**, em ~40 ms |
| SIGKILL | Processo que ignora TERM (`trap '' TERM`): depois da graça (1 s) vem `kill -s KILL` no grupo; exit **137** em ~1,08 s; nenhum filho sobra |
| Prazo e cancelamento | `collect(timeout:)` estourado e `Task.cancel()` encerram o grupo (nenhum `sleep` sobra) e lançam `.timeout` / `.cancelled`; o socket é fechado |
| Pool cooperativo | 20 chamadas lentas em paralelo (2 s cada, daemon falso): terminam em ~2 s e um `await` trivial responde com lacuna máxima < 50 ms (AR-404). Contra o Docker real, 20 `inspect`/`exec` simultâneos: lacuna máxima de 2 ms |

Desvio em relação ao texto do spike: o transporte não usa Network.framework; usa o `UDSConnection` da Platform (`DispatchSource` sobre o socket BSD, não bloqueante), que já é o padrão do resto do app e cumpre o mesmo critério.

Limite conhecido: o wrapper de grupo exige `/bin/sh` e `/tmp` gravável na imagem (a imagem `agentbox-box` e as de teste têm; o container tem `tmpfs /tmp`). Sem `killableGroup`, `terminate` falha com `DockerError.execNotKillable` em vez de adivinhar.

Evidência bruta: `results.json`.

## Como reproduzir

```
cd Packages/AgentBoxKit
AGENTBOX_TEST_DOCKER=1 AGENTBOX_EVIDENCE_DIR=$PWD/../../docs/evidence swift test --filter LiveDockerTests
```

## Pendente

- Repetir em OrbStack e Colima quando instalados (a Engine API é a mesma; o ponto de atenção é o half-close passar pelo proxy de cada um).
