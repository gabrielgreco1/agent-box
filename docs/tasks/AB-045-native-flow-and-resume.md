# AB-045 — Fluxo nativo de computador e retomada de conversas

## Fluxo Claude até o Docker

O teste opt-in `AGENTBOX_TEST_NATIVE_CHILD_FLOW=1` agora percorre o lançamento revisado, PTY real, Claude instalado, hooks de produção, helper MCP, dispatcher do app e Docker real. O teste não fabrica eventos de filhos ou chamadas de ferramentas.

Um subagente nativo adquire uma box independente, navega até a página descartável servida por outro container próprio e retorna um marcador que só existe nessa página. O marcador é produzido por JavaScript. Depois ele chama `computer_request_help`; a callback do teste assume e devolve controle pelo broker compartilhado, e o subagente navega novamente. A segunda visita fica registrada no perfil e é capturada antes da parada automática. A box do pai continua em modo HTTP.

O teste usa Claude em modo `-p`, com limite de US$ 0,25, ferramentas explicitamente restritas, configurações da fixture e sem persistência de conversa. Usa skill sintética, metadados temporários e tokens em memória; não altera o Keychain, o Chrome pessoal ou a skill instalada. O resultado passou com um filho, takeover confirmado, duas visitas e custo informado de US$ 0,00309765. A primeira execução, antes de acrescentar intervenção, também passou e informou US$ 0,002802725.

A suíte integrada executou 160 testes sem falhas; os dois opt-ins Docker já exercitados em AB-044 ficaram desativados. Esse teste une os mecanismos antes comprovados separadamente. Não comprova permissões na TUI, notificações visuais, cliques humanos ou todos os harnesses. Evidência: `../evidence/ab045-native-child-flow.json`.

## Retomada no aplicativo

O menu do workspace oferece **Retomar conversa…**. Claude, Codex e OpenCode usam seus comandos nativos de retomada por ID; a disponibilidade do executável é conferida. A descoberta de sessões ativas está implementada para Claude. A identidade nativa é persistida separadamente do nome editável do terminal. Retomar não substitui o harness e não anexa silenciosamente instruções de um agente salvo a uma conversa externa.

O runtime mantém uma reserva de escrita até a saída real do PTY e consulta a lista ativa do Claude antes de iniciar. O registro salvo não dispara retomada automática ao abrir o app. Falha de início deixa o terminal parado para nova tentativa. O fechamento do app cancela consultas pendentes para impedir que iniciem processos depois do encerramento. Detalhes e limites de exclusividade externa em `AB-013-conversation-discovery.md`.

## Interface e aceite restante

A divisória da sidebar ganhou ajuste acessível em passos de 24 pt; atalhos e arraste compartilham os mesmos limites. Buscar reabre a sidebar recolhida. O menu restaura a largura de 288 pt. A revisão de lançamento passou a caber em uma altura de 550 pt, com ações fora do conteúdo rolável.

A tabela em `AB-006-visual.md` compara o print fornecido com o estado do código: canvas cinza-azulado, ausência de contorno claro, menos cabeçalhos repetidos e hierarquia compacta. O Mac permaneceu bloqueado nesta rodada, portanto não houve nova captura nem aceite visual. Listener, datasets, filas persistentes, backup, troca de modelo/harness, serviço PTY sobrevivente e auditoria integral continuam no plano.

## Build de desenvolvimento

O build release passou, mas a cópia do bundle dentro de Documentos voltou a receber `FinderInfo` do File Provider depois da assinatura. Remover o atributo não foi estável. O script agora guarda um único bundle por checkout em `~/Library/Caches/AgentBox/Builds/<chave>/Agent Box.app` e mantém `build/Agent Box.app` como link. A assinatura é verificada no cache e pelo link; o script recusa substituir o executável em uso em qualquer um dos caminhos. O cache é artefato de desenvolvimento, não uma instalação. O runtime Colima iniciado para os testes foi desligado e os containers/volumes descartáveis foram removidos.
