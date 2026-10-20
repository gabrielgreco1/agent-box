# Racky

Racky is a Mac app that runs your coding agents (Claude Code, Codex, OpenCode) in organized sessions and gives their subagents
their own isolated computers (a small Linux virtual machine with a browser), with nothing else to install.

## Install (for users)

**Requirements**

- A Mac with Apple silicon (M1 or later) running **macOS 26 or later**. Racky then runs computers itself, **no Docker needed**.
  On an older macOS or an Intel Mac, Racky still works if you install Docker (Docker Desktop or OrbStack) and it uses that instead.
- At least one agent CLI installed and signed in: [Claude Code](https://claude.com/claude-code), Codex or OpenCode. Racky never
  signs in for you; onboarding tells you what is missing.
- About 2 GB of free disk space for the computer runtime (see below).

**Steps**

1. Download `Racky.dmg` from the [latest release](https://github.com/gabrielgreco1/racky/releases/latest), open it and drag
   **Racky** onto **Applications**.
2. Open Racky. The first time, macOS says it can't verify the developer: click **Done**, open
   **System Settings > Privacy & Security**, scroll down and click **Open Anyway**, then confirm. Only needed once.

   Rather use Terminal? This installs and opens Racky with no prompt (run it again to update):

   ```sh
   curl -fsSL https://github.com/gabrielgreco1/racky/releases/latest/download/install.sh | bash
   ```
3. Follow the onboarding checklist: agent CLIs found and signed in, **Login Items** approval for the Racky background agent
   (System Settings > General > Login Items & Extensions, switch Racky on; it keeps your terminals alive when you close the window),
   and the computer runtime.

**What gets downloaded on first use.** The app itself is small. The first time an agent asks for a computer, Racky downloads the
computer runtime once (about **475 MB**: a Linux kernel, the guest init and the computer image), checks every file against a
SHA-256 baked into the app, prepares it (about a minute) and never needs the network for it again. Progress shows on the computer
row and in Settings > Computers > Computer runtime. After that a computer starts in about two seconds. The runtime takes about
1.4 GB on disk, under `~/Library/Application Support/Racky/vz`.

**Good to know**

- Computers are virtual machines hosted by the app: they stop when you quit Racky (Keep Running in the background keeps them).
- Nothing leaves your Mac because of Racky itself; the only download is the runtime above, from this repository's releases.
- Uninstall: quit Racky, drag it to the Trash, and delete `~/Library/Application Support/Racky` if you also want the data and
  the runtime gone. Remove the Login Item in System Settings if it is still listed.

## Releasing (for maintainers)

Nothing below publishes by itself: each script prints the `gh` command for you to run.

```sh
# 1. Runtime files (once per runtime change). Needs Docker only here, to build the computer image.
scripts/vz/fetch-kernel.sh                    # Kata kernel, ~650 MB download -> build/vz-assets
scripts/vz/build-image.sh                     # computer image + vminit -> build/vz-assets
scripts/vz/stage-release.sh                   # copies to build/release/runtime-<v>/, sha256, rewrites runtime/vz-manifest.json
# commit runtime/vz-manifest.json, then publish with the command stage-release.sh prints:
gh release create runtime-<v> ...

# 2. The app. Builds Release (arm64), signs, verifies, creates build/release/Racky.dmg + Racky.dmg.sha256.
scripts/release.sh <version>                  # ad-hoc by default
RACKY_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" RACKY_NOTARY_PROFILE=<notarytool profile> scripts/release.sh <version>
gh release create v<version> build/release/Racky.dmg build/release/Racky.dmg.sha256 ...   # printed by release.sh
```

Without `RACKY_NOTARY_PROFILE` the notarization step is skipped (users then need **Open Anyway**, as above).

## Development

> **Rebuild em andamento.** A UI e o core estão sendo refeitos do zero. Ponto de entrada: [docs/rebuild/README.md](docs/rebuild/README.md) (spec, roadmap, decisões). O app antigo foi movido, sem alterações, para `legacy/` e sai do repositório depois da release 1.0 (AR-202). O novo build nunca referencia `legacy/`.
>
> Build do app antigo: `cd legacy && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` (ou `bash legacy/scripts/build_app.sh`). Versões fixadas do novo build: `scripts/tool-versions.txt`, conferidas por `scripts/bootstrap.sh`.

---
**O texto abaixo descreve o app antigo (`legacy/`).**

App pessoal de macOS para organizar sessões com múltiplos terminais de agentes e computadores Docker opcionais, preservando os harnesses originais.

**Hierarquia:** sessão → terminais → execuções de agentes/subagentes → computadores opcionais.

## Estado atual — primeiro lote operacional

O app nativo em `legacy/Sources/` abre PTYs reais e preserva o emulador ao trocar a visualização. A interface tem sessões com múltiplos terminais, abas/splits, sidebar ajustável/recolhível e nomes persistentes. O usuário escolhe Claude Code, Codex ou shell; OpenCode também pode ser lançado se instalado, mas sua integração avançada continua no plano.

A biblioteca persiste agentes personalizados, instruções, memórias selecionadas e skills importadas. O contexto pode ser revisado, copiado ou exportado. A ativação nativa dessas definições no CLI e o histórico automático ainda não estão conectados.

Configurações consultam comandos locais de versão/login e guardam a política de Docker. A camada Docker implementa criação/início/parada de container HTTP por terminal com testes controlados; **não foi validada com daemon real**, pois Docker não está instalado no Mac usado. Browser, desktop, streaming, subagentes nativos, `.env`/Keychain e handoff continuam pendentes.

**Validação:** 23 testes passaram em Xcode, incluindo PTY real, TTY, resize, Ctrl-C, retomada da visualização, persistência, escopos de memória e comandos Docker. Os dois testes PTY passaram novamente após o ajuste de encerramento de grupos de processos. [Detalhes e limites](docs/STATUS.md).

O design anterior permanece separado em `legacy/design/`. A organização visual segue Orca; biblioteca, memória e skills seguem a intenção discutida a partir do Maestrum.

## Compilar e abrir o app

Requer macOS 14+ e Xcode com Swift 6. O script usa Xcode.app quando disponível, sem alterar `xcode-select` global.

```sh
bash legacy/scripts/build_app.sh
open "legacy/build/Racky.app"
```

Para os testes no ambiente usado:

```sh
cd legacy && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test  
```

Fechar uma visualização não encerra seu processo. Sair do aplicativo solicita encerrar os processos ativos; sobrevivência ao quit/crash depende de um serviço ainda não implementado. Metadados ficam em `~/Library/Application Support/Racky`; restaurar uma sessão não reexecuta comandos automaticamente.

## Documentação

- [Spec de produto e arquitetura](docs/spec/index.html): 18 capítulos, incluindo agentes personalizados, memória, skills, listener, credenciais e políticas.
- [Plano de execução por feature](docs/EXECUTION-PLAN.md): tarefas, dependências e frentes paralelas.
- [Critérios de aceite](docs/spec/acceptance.json) e [marcos](docs/spec/backlog.json).
- [Interface existente](design/index.html) e [fonte Swift](design/source).
- [Proveniência dos logos](design/assets/brands/sources.json).

## Abrir a documentação e interface existente

```sh
python3 -m http.server 8766 --bind 127.0.0.1
```

Abra http://127.0.0.1:8766/docs/spec/index.html ou http://127.0.0.1:8766/design/index.html.

## Compilar a base Swift existente

Requer macOS em Apple Silicon e Xcode Command Line Tools.

```sh
bash design/source/build.sh
```

A saída local é `design/Racky Preview.app`. Binários, credenciais, diretórios de runtime e arquivos `.env` não são versionados. O manifest SwiftTerm preparatório, que referenciava arquivos ausentes, foi preservado em `docs/archive/` e não é o build do app.

## Modelo de segurança (resumo)

O texto completo e a tabela de ameaças estão em `docs/rebuild/spec/08-architecture-quality.md` (AR-501 a AR-504).

- Um agente rodando no Mac (modo leve) tem **os mesmos poderes do usuário**: shell, arquivos e socket do Docker. O app não o isola nem diz que isola.
- O container (computador) isola o **navegador**, a rede e as ferramentas de trabalho; no modo isolado (v1.1) também o agente, com limites declarados na UI.
- Os sockets locais são `0600` com `getpeereid`; o daemon aceita só o app assinado. O canal `ctl` de automação vem desligado.
- Segredos ficam no cofre do app (um item no Keychain); nada de token em `argv`, em `docker inspect`, em log ou no pacote de diagnóstico (redação na escrita e na exportação).
- O app nunca pede Gravação de Tela e só pede notificações quando você aperta `Allow Notifications`.
- Nada sai da máquina por conta do app. Planos de nuvem, conta e telemetria estão fora do escopo da v1.

## Direção de implementação

1. Sessões persistentes, múltiplos PTYs reais e interface compacta.
2. Configuração inicial, biblioteca de agentes, memória e skills.
3. Docker HTTP/headless/desktop com associação explícita a uma execução.
4. Identidade de subagentes por harness, streaming e controle humano seguro.
5. Listener, evidências, perfis persistentes e transferências por checkpoint.

Claude Code e Codex são o foco inicial. OpenCode está previsto na spec como cliente adicional; não bloqueia as fundações.

As marcas de terceiros pertencem aos seus titulares. A licença OFL da fonte histórica está junto dos arquivos de fonte. Nenhuma licença de redistribuição geral é presumida para o projeto.
