# Spike S-06: captura do env do shell de login

Data: 2026-10-17. Máquina: Mac do dono (darwin, arm64), `$SHELL=/bin/zsh` (zsh 5.9).
Roteiro: `docs/rebuild/spec/09-roadmap.md` §2.2 (S-06) e `docs/rebuild/spec/06-terminals-and-agents.md` §1.7.
Script: `docs/evidence/spikes/S-06/measure.py` (usa `SCR` apontando para a scratchpad da sessão; ajustar se rodar de novo).

## Resultado

**Critério de saída passou nesta máquina, com ressalvas** (ver "Problemas"): captura em 32 ms (mediana), sem lixo fora dos marcadores, `claude`, `node`, `gh` e `codex` resolvem pelo PATH capturado.

## Ambiente medido

- Não há Oh My Zsh (`~/.oh-my-zsh`) nem Powerlevel10k (`~/.p10k.zsh`). O `~/.zshrc` tem 35 linhas: exports de PATH, funções `glm`/`kimi`, `source ~/.llm-keys.env` e `source ~/.claude/scripts/hunt.sh`. A premissa "provavelmente p10k/oh-my-zsh" não se confirma. O caso real com instant prompt não foi medido.
- Ambiente do processo medido: mínimo, no estilo do launchd (`HOME`, `USER`, `SHELL`, `PATH` do sistema, `TMPDIR`, `LANG`, e `SSH_AUTH_SOCK` obtido com `launchctl getenv`). Não foi usado o env da sessão do Claude, que tem variáveis próprias.
- `TERM=dumb` em todas as medições, como manda §1.7.

## Método

Cada configuração foi rodada 5 vezes. O tempo vai do início do processo até o marcador final (ou até o fim do processo). Para cada execução o script separa: bytes antes do primeiro marcador (lixo de entrada), bytes depois do marcador final (lixo de saída), nomes das variáveis, e `shutil.which` sobre o PATH capturado.

### Comandos

1. Sem PTY, `-l` sem `-i`:
   `$SHELL -l -c 'printf MARK; env -0; printf MARK'`, stdin em `/dev/null`, timeout 10 s.
2. Interativo de login num PTY oculto (`pty.fork`), `TERM=dumb`, stdin vazio:
   `$SHELL -l -i -c 'printf "\n__AB_ENV__\n"; /usr/bin/env -0; printf "\n__AB_ENV_END__\n"'`, timeout 10 s.
2b. Igual ao 2, com `ZDOTDIR` sintético (banner, sequências ANSI, `sleep 0.7`). Não é a config do dono; serve para medir o efeito de rc barulhento.
2c. Igual ao 2, com `ZDOTDIR` sintético que faz `sleep 60`. Serve para testar travamento.
3. Extra (teste de onlcr): valor de variável com `\n` passado pelo PTY, e o mesmo com `/usr/bin/env -0 > "$AB_OUT"` dentro do PTY.

## Tempos (segundos, 5 execuções salvo indicação)

| Configuração | Mediana | Máx | Mín | Timeouts | Marcadores encontrados | Lixo antes / depois |
|---|---|---|---|---|---|---|
| 1. `-l -c`, sem PTY | 0,020 | 0,026 | 0,019 | 0 | 5/5 | 0 / 0 bytes |
| 2. `-l -i -c`, PTY, dumb | 0,032 | 0,037 | 0,024 | 0 | 5/5 | 2 / 2 bytes (CRLF) |
| 2b. PTY + rc sintético barulhento | 0,762 | 0,779 | 0,746 | 0 | 5/5 | 105 bytes com ANSI / 2 bytes |
| 2c. PTY + rc sintético que trava | 10,0 (cortado) | — | — | 1 de 1 | 0/1 | — |

No teste 2c, o processo foi morto com SIGKILL no grupo do PTY e não ficou processo órfão (verificado com `ps`).

## Variáveis e PATH (só nomes e presença)

- `SSH_AUTH_SOCK`: presente (vem do launchd da sessão, `launchctl getenv`). Na configuração 2 ele aparece no env capturado.
- Proxy (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `ALL_PROXY` e minúsculas): nenhuma definida nesta máquina. Não dá para confirmar a regra de "passa como está" só com esta máquina.
- `ORCA_*`: nenhuma no env capturado desta máquina. Isso só mostra a origem; a denylist de §1.7 (remoção) ainda não foi testada aqui.
- Nomes que parecem segredo, vindos do `~/.llm-keys.env` pelo `.zshrc` (só na configuração 2, não na 1): `ZAI_API_KEY`, `MOONSHOT_API_KEY`, `OPENROUTER_API_KEY`. Os valores não foram impressos nem copiados para o repo.
- `which` pelo PATH capturado: `claude` em `~/.local/bin`, `node` em `~/.local/bin`, `gh` em `/opt/homebrew/bin`, `codex` em `~/.local/bin`. Igual nas configurações 1 e 2.
- PATH: a configuração 1 tem 14 entradas e a 2 tem 16. As duas extras são `~/.opencode/bin` e um `~/.local/bin` duplicado, ambas vindas do `.zshrc`.

## Problemas

1. **`-l -c` sem `-i` perde o PATH do `.zshrc`.** Na configuração 1, `~/.opencode/bin` não entra no PATH. Por isso a fallback 3 de §1.7 não serve sozinha como caminho normal. Precisa ser marcada como "ambiente não interativo" no Diagnostics.
2. **PTY troca `\n` por `\r\n` em valores de env** (teste 3: `linha1\r\nlinha2`). Isso corrompe valores multilinha (certificados, por exemplo). Com `env -0 > arquivo` dentro do PTY, o valor sai byte a byte (teste 3: 0 CR, `linha1\nlinha2`). O marcador continua servindo só como sinal de fim.
3. **Premissa do p10k não confirmada** (ver "Ambiente medido"). O caso real com instant prompt ficou sem medição. Com o rc sintético barulhento, o tempo subiu para 0,76 s, quase no limite de 1 s. Um p10k real pode passar disso, e então o timeout de 5 s do §1.7 é o que protege o app.
4. **`TERM=dumb`** pode mudar o comportamento de temas como o p10k (instant prompt pode ser desligado). Vale testar de novo com o tema real, se o dono instalar.
5. **Source de segredos no rc.** O `.zshrc` exporta chaves de API. O §1.7 aceita isso (é o mesmo comportamento de qualquer terminal), mas o Diagnostics deve listar só os nomes, que é o que está no spec.

## Recomendação

Estratégia principal: configuração 2 (`-l -i -c` em PTY oculto, `TERM=dumb`), com duas mudanças em relação a §1.7:
- o env vai para um arquivo (`/usr/bin/env -0 > "$AB_ENV_OUT"` dentro do PTY), não para o stdout do PTY, para evitar a troca de `\n`;
- o marcador `__AB_ENV_END__` continua valendo como sinal de fim, com timeout de 5 s e `SIGKILL` no grupo do PTY.

Fallback: configuração 1 (`-l -c` sem PTY, timeout 3 s), que é a mais rápida, mas perde o PATH do `.zshrc`. Se ela for usada, o Diagnostics deve dizer "Using non-interactive shell environment". A fallback 4 (env do launchd com diretórios conhecidos) fica como última linha. Ela é a que mais perde: não tem nada do `.zshrc`.

## Critério de saída

| Critério | Resultado |
|---|---|
| Captura em menos de 1 s | Passa (32 ms mediana). Com rc barulhento sintético, 0,76 s. |
| Sem lixo | Passa no rc real (2 bytes CRLF fora dos marcadores). Com lixo sintético de 105 bytes, o parse por marcador ignora tudo. |
| `which claude node gh` resolve | Passa (também `codex`). |
| Não trava | Passa com timeout; o caso que trava foi cortado em 10 s sem processo órfão. |

**Passou**, com as ressalvas 1 a 4 acima. A ressalva 1 é a que muda o código: o fallback não pode ser silencioso.
