# T1-24 · Daemon como LaunchAgent e ⌘Q mantém agentes

Cobre P4, T1, TA-101, TA-107, TA-115…TA-118 (parte), AC-801…805 (parte). Base: S-01 (`docs/evidence/spikes/S-01/README.md`, **aprovado**: o plano B do socket não foi necessário nem adotado).

## O que existe

| Peça | Onde |
|---|---|
| Daemon recebe o socket do launchd (`launch_activate_socket("Listeners")` por `dlsym`, nunca `bind`/`unlink`); `--launchd [nome]`, `--socket-fd <n>` (simula o launchd nos testes), `--build <n>` | `agentboxd/AgentBoxD.swift`, `DaemonServer.swift`, `AgentBoxPlatform/Launchd/LaunchdSocketActivation.swift` |
| Launcher estável do job (`agentboxd-launch`, C, só faz `exec` do `agentboxd`) | `Sources/agentboxd-launch/main.c`, `scripts/build.sh` |
| Plist embutido (`SecureSocketWithKey=AGENTBOX_PTYD_SOCK_V1`, `SockPathMode=384`, sem `RunAtLoad`/`KeepAlive`) | `App/LaunchAgents/app.agentbox.ptyd.v1.plist` → `Contents/Library/LaunchAgents/` |
| Registro, aprovação, fingerprint do launcher, re-registro seguro | `AgentBoxPlatform/Launchd/BackgroundAgentHost.swift` (`SMAppService` em `BackgroundAgentService.swift`, `launchctl` em `LaunchdQuery.swift`, labels de teste em `BackgroundAgentIdentity.swift`) |
| App conecta pelo socket do launchd; fallback para o daemon filho | `AgentBoxUI/Panes/TerminalRuntime.swift` (`hostMode`, `prepareHost`, `establish`, `respawnDaemon`), `PTYClient.updateSocketPath` |
| Política de ⌘Q, upgrade do daemon, estado da barra de menus (puros) | `AgentBoxCore/AppLifecycle/` |
| ⌘Q com overlay, accessory, Quit Completely, Stop All | `AgentBoxUI/Shell/AppLifecycleCoordinator.swift`, `AppDelegate.swift`, `Overlay/ConfirmationOverlay.swift` |
| Item da barra de menus (contagem, Open Agent Box, Stop All Agents…, Quit Agent Box Completely) | `AgentBoxUI/MenuBar/MenuBarController.swift` (`NSStatusItem`) |
| Settings › General: "Background agents need approval" + "Allow in Login Items" (só abre os Itens de Início por clique) | `GeneralSettingsView.swift`, `SettingsModel.backgroundNeedsApproval` |

Spec tocada (gerador de IDs): 03 §24 ganhou `app.openMainWindow`, `app.stopAllAgents`, `settings.general.allowLoginItems`; §22 ganhou `overlay.confirmQuit.stopAllConfirm`. 06 §1.2 ganhou o resultado do S-01; 08 §0.1 e 09 §7 item 2 foram atualizados.

## Modos

| Modo | Quando | Efeito |
|---|---|---|
| LaunchAgent | app dentro do `.app`, plist embutido, item de login habilitado | daemon do launchd (`PPID 1`), socket em `/var/run/com.apple.launchd.<id>/Listeners`, app lê `launchctl getenv`, nenhum processo filho |
| Fallback (daemon filho, o modo atual) | sem plist no bundle, `requiresApproval`, registro falhou, sem caminho do socket, ou o daemon não respondeu no socket do launchd (3 tentativas de 2 s) | tudo como antes: daemon filho do app que sobrevive ao ⌘Q por reparent; Settings mostra "Background agents need approval" com botão quando for aprovação |
| Filho escolhido | `AGENTBOX_HOME`, automação, fixtures ou `AGENTBOX_DAEMON` definidos (testes) sem `AGENTBOX_LAUNCHD=1` | sem tocar no launchd |

## ⌘Q, accessory, barra de menus

- ⌘Q: `QuitPolicy` decide. Sem agente vivo: sai (escreve a saída limpa). Com agente: overlay na janela (nunca `NSAlert`; se não há janela, ela volta) com `[Cancel] [Stop All and Quit…] [Keep Running ↵]` e "Don't ask again" **marcado só na primeira vez** (P15). Keep Running esconde a janela, vai para `.accessory` e deixa o ícone. Com "Don't ask again" desliga "Ask before quitting". `Stop All and Quit…` abre a segunda confirmação; confirmar faz `kill graceful`, espera 5 s e **força** o que sobrou. Logout/reinício/desligamento nunca perguntam. "Keep agents running when you quit" desligado: variante "Quitting stops them", ↵ = Cancel.
- Fechar a última janela com agente vivo: vai para accessory (não sai). Reabrir (item, Dock, Spotlight) volta a `.regular` e mostra a janela.
- Barra de menus: número de agentes vivos ao lado do ícone, cabeçalho "N agents running", `Open Agent Box`, `Stop All Agents…` (desabilitado sem agentes), `Quit Agent Box Completely` (sai do processo, tira o ícone, os PTYs seguem no daemon). Reabrir reanexa pelo T1-23.
- Bug achado pelo e2e e corrigido: `NSApp.terminate` chamado de dentro de uma tarefa do main actor (ação do registro, item de menu) ou de um bloco da fila principal abre um laço aninhado que não roda a tarefa que responde ao `applicationShouldTerminate`: o app travava e o `ctl` dava timeout. Agora o pedido sai como bloco do run loop (`AppLifecycleCoordinator.requestTermination`). Isso valia também para o ⌘Q do menu desde a T1-10.

## Provas

- `scripts/e2e-launchd.sh` (app real, cópia em `/tmp` com bundle id e label de TESTE, `AGENTBOX_HOME` próprio; limpa tudo no fim) em `e2e-launchd/`: `report.txt` (todos PASS: job do launchd, `getenv`, socket 0600, daemon com `PPID 1`, agente filho do daemon, overlay `overlay.confirmQuit`, Keep Running mantém app/daemon/agente, accessory, `ctl` responde em segundo plano, Quit Completely e reabrir com **mesmo PID de daemon e de agente**, pane de volta na árvore, daemon novo sobe sem novo registro depois da troca do binário), `quit-overlay-1440x900.png`, `after-reopen-1440x900.png`, `launchctl-print-*.txt`, `ui-tree-*.json`.
- Testes: `QuitPolicyTests` (política, upgrade, barra de menus), `BackgroundAgentHostTests` (registro, `notFound` antes do primeiro register, aprovação pendente, falha, plist ausente, espera do socket, re-registro só com o daemon parado, nunca com sessão viva, job `failed`), `LaunchdSocketTests` (daemon real recebe o fd 3, conexão enfileirada antes de o daemon existir, ocioso sai e **não** apaga o socket, sessão viva o mantém, `drainWhenIdle`), `DaemonHostingTests` (fallback por aprovação: daemon filho funciona, sobrevive ao "⌘Q" e a reabertura reencontra o PTY; socket do launchd sem resposta cai no filho; sem agente configurado), `AppLifecycleTests` (overlay, Keep Running, Don't ask again, Stop All em duas etapas, Cancel, Quit Completely, accessory, reabrir, menu).
- Não coberto por teste automatizado: `requiresApproval` real (não foi possível provocá-lo sem mexer em Ajustes do Sistema; só com serviço falso), Developer ID, kill -9 do daemon sob o LaunchAgent (o launchd relança na próxima conexão; a reconciliação do T1-23 marca as sessões como interrompidas, já testada com o daemon filho).

## Divergências e pendências

1. `BundleProgram` = `agentboxd-launch` (08 §0.1 dizia `agentboxd`): necessário por causa do cdhash (S-01). **Dono ratifica.**
2. Botão de confirmação final da parada é "Stop and Quit" (a spec diz "Stop All and Quit"): o Xcode recusa duas chaves do catálogo que gerariam o mesmo símbolo ("Stop All and Quit…" e "Stop All and Quit").
3. TA-118 diz que sem aprovação o ⌘Q avisa "Agents will stop when you quit". Aqui o fallback é o daemon filho **que sobrevive por reparent**, então Keep Running funciona também nele (instrução da tarefa). O aviso de TA-118 não foi implementado.
4. Stop All: depois de 5 s força o que sobrou sem oferecer `[Force Quit]` (06 §1.9 pede a lista de quem falta e o botão).
5. Keep Running só esconde a janela; as views de terminal não são liberadas (06 §1.9). A janela volta já anexada.
6. Barra de menus: sem seções "Needs You"/"Working", sem "New Session…" (dependem da atividade, Fatia 2); ícone é um símbolo do sistema (`terminal`), não o glifo da marca; sem a opção "Show menu bar icon: Always / When agents are running" em Settings (o padrão "When agents are running" está fixo; em accessory o ícone é sempre visível).
7. A segunda confirmação de Stop All fala só de agentes (sem computadores, Fatia 3).
8. O contador de agentes vem do banco (terminais `running`/`launching` com provider agente). O e2e não roda agente real: marca o terminal `custom` como `claude` no SQLite do `AGENTBOX_HOME` de teste (`fixture.txt`).
9. `Restart Background Service` e a linha "Daemon update pending" do Diagnostics não existem (Settings › Diagnostics é de outra tarefa); o app já pede `drainWhenIdle` e expõe `daemonUpdatePending` no runtime.
10. `scripts/e2e.sh` (passos AR-810 1–3 e 7) segue esqueleto; o que a T1-24 provou está em `scripts/e2e-launchd.sh`. Cold restore depois de kill -9 do **app** é do T1-23.

## O que exige ação do dono

- Ratificar os desvios 1 e 2 (e a regra "daemon novo só entra quando a última sessão do antigo termina", S-01).
- Aprovar o item de login do Agent Box real em Ajustes do Sistema › Geral › Itens de Início, se o macOS pedir (o botão "Allow in Login Items" abre o painel; nada o clica por você).
- Conferir se sobraram entradas de teste (bundles `app.agentbox.s01test*` e `app.agentbox.mac.test*`) em Itens de Início; `sudo sfltool resetbtm` limpa a lista de todos os apps (não foi rodado).
- Decidir sobre uma identidade de assinatura estável (S-03/AR-530): com ad-hoc o app e o `agentboxd` mudam a cada build; o launcher evita o re-registro, mas Keychain/TCC seguem instáveis.
