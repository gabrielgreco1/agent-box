# Racky

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
