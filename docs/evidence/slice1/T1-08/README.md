# T1-08: env do shell de login

Código: `Packages/RackyKit/Sources/RackyPlatform/LoginShellEnv/` (provider, filtro, tipos, parser) e `ProcessRunner/ShellProbe.swift` (spawn, PTY, espera, kill). Testes: `Tests/PlatformTests/LoginShellEnv*Tests.swift`.

## Comportamento (06 §1.7)

- Passo 1, `-l -i -c` em PTY oculto (`openpty` + `posix_spawn` com `POSIX_SPAWN_SETSID`, `TERM=dumb`), env por arquivo `0600` (`env -0 > "$AB_ENV_OUT"`), marcador final com nonce, timeout de 5 s.
- Passo 2, `-l -c` sem PTY e sem `-i`, timeout de 3 s, resultado `nonInteractive` (banner `Using non-interactive shell environment`).
- Passo 3, `failed` com os dois motivos tipados e o env do launchd com diretórios conhecidos no PATH (banner `Using fallback environment`).
- Em todo caminho o grupo e a sessão recebem SIGKILL antes do `waitpid`. Shell interativo põe jobs em grupos próprios, então só `kill(-pgid)` deixou o `sleep` de um `cmd &` no rc vivo (achado deste teste, corrigido varrendo o sid com `proc_listallpids`/`getsid`).
- Cache em memória com coalescência de chamadas concorrentes, `reload()`, `invalidate()` (mata captura em curso) e `maxAge` opcional. Falha total não entra no cache.
- Filtro configurável (`EnvFilter`): allow vence deny; padrão = denylist de 06 §1.7 (inclui `ORCA_*`, `RACKY_*`, `CLAUDECODE`) e allowlist de `PATH`, `SSH_AUTH_SOCK` e proxies.
- Segredos: valores nunca vão para log, `description` ou diagnóstico; o diagnóstico lista só nomes e marca os que casam KEY/TOKEN/SECRET/PASS/AUTH.

## Testes

Shell sintético rápido, zsh real com rc barulhento (banner, ANSI, `sleep 0.7`), rc que trava (morto em 5 s, sem órfão, cai no `-l -c`), os dois modos travados (`failed`, sem órfãos), saída antes do marcador, shell inexistente, valores com `\n` e `\r\n` intactos, cache/reload/invalidate/concorrência/maxAge, cancelamento, denylist/allowlist, e integração com o `$SHELL` real (PATH resolve `claude` e `gh`; pula se ausentes).

## Evidência na máquina do dono

`real-shell-capture.json` (só nomes e presença, nenhum valor): fonte `interactive` com `/bin/zsh`, 5 capturas de 28 a 35 ms, `claude`/`codex`/`node` em `~/.local/bin` e `gh` em `/opt/homebrew/bin`, nenhuma `ORCA_*` nem `CLAUDECODE` no resultado mesmo com ambos no env de entrada. `SSH_AUTH_SOCK` não aparece porque o ambiente de entrada do teste não o inclui (o app lançado pelo launchd o herda).

## Pendente

- [L] `which claude codex gh` dentro de um pane do app: depende do `PTYClient`/daemon (T1-06+); a captura em si está pronta.
- Observação de lint: a regra `ui-system` de `scripts/lint.sh` usa só globs de inclusão junto de `--glob '*.swift'`, então dispara em qualquer arquivo (dava falso positivo para `FileManager` em Platform). Contornei com POSIX no provider; a regra merece correção em outra tarefa.
