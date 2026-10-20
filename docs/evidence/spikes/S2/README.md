# Spike S2 · Porta publicada só pelo egress e DNS em rede `internal`

Pergunta (07 §9, CS-110/111/112): numa rede Docker `internal: true`, os containers se resolvem por nome, não têm rota para fora, e **só** o `egress` (internal + bridge) publica uma porta em `127.0.0.1`, pela qual o app alcança o runtime?

## Resultado: APROVADO no Docker Desktop (arm64). OrbStack e Colima: não testados (não instalados nesta máquina)

Máquina: Docker Desktop, Engine 29.6.2, API 1.55, aarch64, VM de 8 GB, contexto `desktop-linux`. O cliente fala `/v1.43`.

Topologia montada pelo teste (`Packages/RackyKit/Tests/DockerTests/LiveNetworkTests.swift`, `s2InternalNetworkDNSAndPortPublishedOnlyByEgress`), tudo com `racky.test=1`:

- rede `internal` (Internal=true) e rede bridge de saída;
- `runtime`: só na rede internal, alias `runtime`, serve HTTP em 9000, **sem porta publicada**;
- `egress`: criado na rede internal (alias `egress`), conectado depois à bridge, publica `127.0.0.1::8080` (porta aleatória lida via inspect), reverse proxy para `runtime:9000`;
- `work`: só na rede internal.

| Verificação | Resultado |
|---|---|
| Portas publicadas | runtime = 0, work = 0, egress = `127.0.0.1:<aleatória>` (todos os bindings em `127.0.0.1`) |
| DNS na rede internal | `work` resolve `egress` e `runtime` por alias e fala HTTP com os dois |
| Sem rota para fora | `work`: `wget 1.1.1.1` falha (`wget=1`), `ping 8.8.8.8` falha (`ping=1`), a tabela de rotas só tem `172.18.0.0/16`; `runtime`: `wget 1.1.1.1` falha |
| Egress com saída | `wget http://example.com` a partir do egress funciona (`wget=0`, pela bridge; informativo, depende da internet do host) |
| Host -> egress -> runtime | `GET /` na porta publicada devolve `egress-ok`; `GET /p.cgi` devolve `from-runtime`, ou seja, o egress alcança o runtime pela rede internal e o host só vê a porta do egress |

Conclusão para a arquitetura: o desenho de CS-111 funciona sem o container de ingress de fallback no Docker Desktop. A ordem "criar na internal, conectar a bridge depois, iniciar" publica a porta normalmente.

Evidência bruta: `results.json` (gerado pelo teste com `RACKY_EVIDENCE_DIR`).

## Como reproduzir

```
cd Packages/RackyKit
RACKY_TEST_DOCKER=1 RACKY_EVIDENCE_DIR=$PWD/../../docs/evidence swift test --filter LiveNetworkTests
```

Só cria recursos com os labels `racky.test=1` e `racky.test_run=<id>` e remove tudo ao final (o teste falha se sobrar algo).

## Pendente

- Repetir em OrbStack e em Colima quando estiverem instalados (07 CS-105). No Colima, verificar o atraso de 1 a 3 s do port-forwarder (o health do egress deve esperar a porta publicada); se a publicação a partir de um container dual-homed falhar lá, vale o fallback de CS-111 (container de ingress).
- O teste usa `busybox nc` como servidor; o egress real (T3-02) é outra imagem, mas o mecanismo de rede é o mesmo.
