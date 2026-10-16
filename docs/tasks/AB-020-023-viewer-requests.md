# AB-020/023 · Viewer real e pedidos humanos

## Implementado

- `RemoteDesktopView` é um NSView nativo que recebe JPEGs do MJPEG em `GET /v1/stream` por `URLSession`, com Bearer apenas no header. Recusa endereço fora de loopback, redirect, health não autenticado, `computer_id` ou `generation` divergentes, modo diferente de `desktop`, `display_ready=false` e `frame_source` diferente de `desktop`. Não gera imagem de exemplo.
- A UI diferencia conectando, ao vivo, atrasado, desconectado e erro. Stream atrasado ou interrompido suspende input e chama o host broker para desconectar. Fechar o viewer cancela só o stream, não a box.
- `RemoteDesktopControlActions` é o contrato de host para assumir/devolver e enviar mouse/teclado. O viewer habilita input apenas após receber `ControlGrant` humano do computador correto com permissão `.input`; o host deve fazer revoke → ACK → grant no runtime e manter o token efêmero fora da View. Sem essas ações, o viewer é somente leitura.
- `HumanRequestStore` persiste alvo `sessionID/terminalID/runID/computerID`, estado e IDs já notificados. Reentrega do mesmo `requestID` não duplica pedido ou som; ID reaproveitado para outro alvo falha. Badges consultam pedidos pendentes por escopo.
- `HumanRequestCenter` agenda `UNUserNotificationCenter` com som somente quando o usuário chama `enableNotifications()` explicitamente. Inicialização nunca solicita autorização. `HumanRequestsView` lista somente pedidos reais e abre o alvo por callback.
- A sidebar mostra badge global e por sessão/terminal somente para pedidos persistidos. Fechar um pane não remove o terminal: abrir o pedido seleciona seu ID e recria o pane visual. Se sessão/terminal não existir mais, a lista preserva o pedido e informa que não é possível navegar.

## Integração pendente de contratos de host

- O serviço Docker/root deverá construir `BrowserRuntimeEndpoint` a partir da porta publicada e do token efêmero, passando-o ao viewer somente após health real. O painel de computadores existente ainda é HTTP apenas; não mostra botão de desktop até esse contrato estar ligado.
- O host broker deverá implementar `RemoteDesktopControlActions` com `ControlBroker` e `/v1/control/revoke`/`grant`; a View não chama essas rotas diretamente. A confirmação da revogação e o ticket de input precisam vir do serviço, nunca de um toggle visual.
- Um adaptador autenticado de `ask_user` deverá chamar `HumanRequestCenter.ingest`. Sem ele, não há pedido fictício nem notificação. O toggle de autorização do macOS depende da integração do dono de Settings.

## Evidência

- Testes de persistência/idempotência/escopo/conflito de IDs em `HumanRequestsTests`.
- Sem build ou app aberto nesta tarefa; teste integrado será executado em série pelo agente raiz após o endpoint Core estar disponível.
