# Agent Box

App pessoal de macOS para organizar sessões com múltiplos terminais de agentes e computadores Docker opcionais, preservando os harnesses originais.

**Hierarquia:** sessão → terminais → execuções de agentes/subagentes → computadores opcionais.

## Estado atual

A base versionada contém o código SwiftUI e a interface web existentes, assets oficiais, estudo de movimento e uma spec consolidada. O build de design compila e exporta 16 telas no Mac de desenvolvimento. Os terminais dessa base ainda não executam processos; Docker, streaming, memória persistente e associação de subagentes são requisitos, não funcionalidades entregues neste commit.

A próxima implementação está organizada em [tarefas](docs/IMPLEMENTATION.md). A referência visual é Orca: sidebar ajustável/recolhível, árvore de sessões e terminais divididos. A biblioteca de agentes, memória e skills segue a organização discutida a partir do Maestrum.

## Documentação

- [Spec de produto e arquitetura](docs/spec/index.html): 18 capítulos, incluindo agentes personalizados, memória, skills, listener, credenciais e políticas.
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

A saída local é `design/Agent Box Preview.app`. Binários, credenciais, diretórios de runtime e arquivos `.env` não são versionados. O manifest SwiftTerm preparatório, que referenciava arquivos ausentes, foi preservado em `docs/archive/` e não é o build do app.

## Direção de implementação

1. Sessões persistentes, múltiplos PTYs reais e interface compacta.
2. Configuração inicial, biblioteca de agentes, memória e skills.
3. Docker HTTP/headless/desktop com associação explícita a uma execução.
4. Identidade de subagentes por harness, streaming e controle humano seguro.
5. Listener, evidências, perfis persistentes e transferências por checkpoint.

Claude Code e Codex são o foco inicial. OpenCode está previsto na spec como cliente adicional; não bloqueia as fundações.

As marcas de terceiros pertencem aos seus titulares. A licença OFL da fonte histórica está junto dos arquivos de fonte. Nenhuma licença de redistribuição geral é presumida para o projeto.
