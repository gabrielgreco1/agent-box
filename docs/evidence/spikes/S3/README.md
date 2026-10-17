# Spike S3 · noVNC em WKWebView: ≥ 20 fps e p95 de input < 100 ms

Pergunta (07 §9, CS-401, CA-401): o viewer noVNC (WKWebView, sem internet) mostra uma página animada a ≥ 20 fps em 1280×800 e responde ao input com p95 < 100 ms em loopback?

Caminho medido: Chromium headed → Xvfb `:99` → `x11vnc` (127.0.0.1:5900, só dentro do container `runtime`) → ponte WebSocket do servidor de controle (ticket de uso único, filtro de input pelo lease) → túnel do egress (`ws://127.0.0.1:<porta publicada>/vnc?ticket=…`) → cliente.

## Resultado: APROVADO nos dois clientes (Docker Desktop, Engine 29.6.2, arm64)

| Medida | Cliente | Resultado | Critério |
|---|---|---|---|
| fps, canvas animado 640×400 contínuo, 6 s em regime | WebSocket puro, codificação **Raw** (pior caso para a ponte: ~4 MB/s) | **35,4 fps** (212 quadros) | ≥ 20 |
| Latência de input, 40 amostras (mouse move → próximo quadro) | WebSocket puro | **p50 36 ms, p95 51 ms**, máx 124 ms | p95 < 100 ms |
| fps e latência dentro do WKWebView com o noVNC real (Tight/ZRLE negociados) | app Agent Box, janela em segundo plano | **42,96 fps** (mín. 41), **p50 44 ms, p95 74 ms** (40 amostras; página oculta para o WebKit, app em segundo plano) — `webview-results.json`; no teste `LiveViewerWebViewTests`: 44,8 fps, p95 67 ms (`webview-test-results.json`) | ≥ 20 fps, p95 < 100 ms |

`ws-results.json` é o registro bruto do teste vivo (`LiveViewerTests`); o mesmo teste confere ABNT2, o lease e o isolamento do x11vnc (`docs/evidence/slice3/T3-05/live-viewer.json`).

## Como o fps e a latência foram medidos

- **WebSocket puro** (`Tests/CoreTests/Computers/Viewer/LiveViewerTests.swift`): cliente RFB mínimo sobre `URLSessionWebSocketTask`. Pede só Raw para poder contar `FramebufferUpdate` sem decodificador; cada resposta a um pedido incremental é um quadro. A latência é o tempo entre mandar um `PointerEvent` e chegar o próximo `FramebufferUpdate`, com a tela parada antes (a página só muda de cor quando o mouse mexe). Inclui o polling de 0,4 ms do leitor do teste.
- **WKWebView**: `viewer.js` conta um `flip()` do `Display` do noVNC por `FramebufferUpdate` (fora da fila) e posta `fps` a cada segundo; a sonda de latência despacha `mousemove` sintético no canvas e mede até o próximo `flip`. Só roda com `AGENTBOX_VIEWER_MEASURE=<arquivo>` (dev).

## Como reproduzir

```
cd Packages/AgentBoxKit
AGENTBOX_TEST_DOCKER=1 AGENTBOX_EVIDENCE_DIR=$PWD/../../docs/evidence swift test --filter LiveViewerTests
```
