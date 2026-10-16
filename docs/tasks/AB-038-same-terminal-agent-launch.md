# AB-038 — Relançar agente no terminal da box

O fluxo de revisão aberto pelo painel da box agora mantém o terminal existente. A sessão, pasta, título, data de criação, panes e identidade Docker permanecem associados; o snapshot de contexto recebe uma identidade nova por execução. Não é necessário recriar o container nem mover o perfil para corrigir a associação.

## Contrato implementado

- A revisão recebe a atribuição exata de computador/terminal/agente/skill. Sessão e pasta ficam fixas para esse destino.
- O usuário pode pedir para parar o processo atual. A troca só ocorre depois de o runtime confirmar que não há processo ativo; processos iniciando ou rodando são rejeitados. Terminais ainda não iniciados também são destinos válidos.
- Antes do lançamento, o app consulta labels Docker fora da main thread e verifica que a box ainda pertence ao terminal. Revalida a atribuição persistida, o terminal, o agente e a skill selecionada.
- Binding separa `planID` de `terminalID`; versões anteriores decodificam terminalID a partir do planID. Restore valida o terminal sem mudar a localização do snapshot.
- Metadados são gravados antes do spawn e restaurados quando o lançamento falha. Histórico só é publicado após o processo correto ser observado rodando.
- O runtime registra qual plano realmente iniciou em cada PTY. Um processo antigo no mesmo terminal não pode ser confundido com o novo; o rollback não encerra um processo diferente.
- O painel só indica skill incluída no lançamento quando binding, agente, skill e plano ativo correspondem. Isso não prova que o modelo invocou a skill.

## Verificação

Suíte integrada: 82 testes sem falhas. Cobertura inclui bindings legados, snapshots diferentes no mesmo terminal, rejeição de destinos alterados, preservação de panes e execução em PTYs reais de uma fixture local. A fixture não chama Claude nem serviços externos. Build release e assinatura ad hoc passaram.

Conferência nativa: app abriu com dois terminais restaurados sem iniciar processos; a biblioteca criou o preset real Web scraping, selecionou a skill local e preparou a revisão de 50 arquivos auxiliares (344.306 bytes). Nenhum CLI foi iniciado pela conferência. A revisão expõe contexto e destino; caminhos, argumentos e hashes ficam recolhidos em detalhes para reduzir ruído visual. O pacote pessoal fica no armazenamento local, fora do Git.

## Pendências preservadas

Esse fluxo associa a execução ao terminal dono da box. Ainda não concede automaticamente ferramentas MCP nem controle de browser ao CLI. Eventos de filhos, concessões por run, prova de uso da box no histórico e takeover de um agente nativo concorrente seguem pendentes. Também faltam o aceite vertical pela UI com Docker ativo e a conferência real da mitigação de Keychain após troca de assinatura. A meta completa continua aberta.
