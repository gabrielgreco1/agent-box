# AB-044 — Controle independente do computador de cada subagente

O MCP de um terminal Claude agora encaminha a chamada ao computador do pai ou do filho nativo autenticado. A identidade vem dos hooks revisados e do registro ativo; o modelo não escolhe IDs de outros agentes ou computadores. Esta entrega substitui a recusa provisória de chamadas de filhos descrita em AB-043.

## Aquisição e skill padrão

`computer_acquire(mode: http | headless | desktop)` conecta a box própria do chamador. Para um filho sem box, cria uma somente quando a política efetiva permite criação automática. Política manual permite conectar uma box própria já em execução; não permite criar ou iniciar uma parada. Política desativada recusa acesso. O serviço Docker confere novamente a permissão automática sob o lock de criação, além dos limites de recursos e do dono registrado.

O filho só acessa computadores quando o lançamento real do pai contém o contexto revisado de `webscraping-expert`. A exigência vale para criação, reinício, reconexão e chamadas de um controlador já conectado. Arquivos protegidos e hashes são revalidados. Uma skill não é injetada retroativamente em filhos existentes. O conteúdo pessoal permanece fora do repositório. O painel oferece o mesmo requisito para iniciar uma box de filho.

O modo solicitado respeita a política “sempre gráfico”. Headless executa JavaScript. Cada box conserva seu volume e perfil Chromium; adquirir uma box não copia o Chrome pessoal, troca user agent nem promete eliminar CAPTCHA.

## Controle, concorrência e intervenção

- Cada filho recebe uma concessão independente, vinculada ao pai e ao identificador nativo. Não toma uma concessão humana nem reutiliza a box do pai.
- Chamadas de filhos diferentes podem progredir em paralelo. O helper stdio aceita até oito encaminhamentos simultâneos, preserva IDs JSON-RPC e escreve respostas inteiras. Erro de transporte encerra o helper mesmo quando stdin continua aberto, permitindo ao harness perceber a desconexão.
- O inbox serializa a ingestão de eventos autenticados. Uma chamada aguarda a ingestão necessária e revalida pai/filho depois de operações assíncronas. A política é conferida novamente após adquirir controle e antes da operação.
- `computer_request_help` identifica sessão, terminal, execução e box. Pausa as escritas desse controlador até o usuário assumir e devolver explicitamente. As outras boxes continuam disponíveis. Status, texto da página e screenshots continuam legíveis: takeover é exclusividade de escrita, não modo de privacidade.
- Fechar o viewer libera sua concessão, mas não equivale a autorizar a retomada de um agente que pediu ajuda.

## Encerramento e preservação

Quando o filho termina, o app impede novas chamadas, aguarda a operação aceita e libera somente sua concessão. Uma box criada ou iniciada automaticamente é parada quando fica ociosa; o volume permanece. Uma box previamente iniciada pelo usuário não é parada por essa regra.

A parada usa uma reserva de manutenção no broker compartilhado. Outra instância da bridge não pode conceder controle enquanto a parada está em andamento. Se o humano ainda controla a box, o app mostra o motivo e tenta novamente após a devolução. O término de um filho não encerra a box de um irmão nem a do terminal pai.

Uma falha de conexão após criação conserva o registro de limpeza pendente. Ao encerrar o chamador, o app tenta reconectar, verificar o estado e parar a box sem apagar arquivos. Quit explícito encerra os PTYs e aguarda a limpeza; computadores não resolvidos aparecem em uma confirmação que permite voltar ao app. Isso não implementa sobrevivência a crash do serviço PTY ou recuperação completa após sono.

## Evidência e limites

A suíte integrada executou 152 testes sem falha, com os dois opt-ins Docker ligados. O teste real criou duas boxes de filhos, executou JavaScript headless, distinguiu os perfis, assumiu controle humano em uma sem afetar a outra, recusou a concessão antiga, parou apenas uma e confirmou o perfil após reinício. Também passou o teste real de atualização/rollback de imagem. Os containers e volumes descartáveis foram removidos; as duas boxes anteriores permaneceram paradas e o perfil Colima iniciado para a validação foi desligado.

Testes do dispatcher do app usam PTY real, hooks assinados e transporte de runtime controlado para verificar dono, política manual, encerramento, pedido humano e retomada. Não são uma execução de um modelo Claude controlando Docker pela TUI. Os probes nativos de AB-043 comprovam separadamente a identidade e a entrega do contexto. Falta unir essas evidências em um fluxo completo ao vivo e conferir a interface. Codex/OpenCode, fila persistente, listener, backup/restore e os demais aceites continuam no plano integral.

Resultados consolidados em `../evidence/ab044-child-routing.json`.
