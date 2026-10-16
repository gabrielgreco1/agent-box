# AB-035 · Reconexão após substituir o build local

Estado: mitigação implementada em código; conferência no app real pendente. Encontrado pela conferência real após AB-033.

O app criou o computador, abriu o desktop, recebeu frames, assumiu/devolveu controle e enviou input. Depois de substituir o executável com nova assinatura ad hoc, a reconexão permaneceu esperando `SecItemCopyMatching`. A amostra de processo mostrou uma chamada aguardando SecurityServer e outra esperando o lock interno do Keychain. Nenhum token foi exposto. Não atribuir a causa definitiva à assinatura sem investigar o fluxo de autorização do macOS.

## Próxima entrega

- Coalescer reconexões concorrentes do mesmo computador (a tarefa inicial do painel e o botão podem executar juntas).
- Separar consulta automática sem interação da autorização explícita, usando APIs suportadas do Keychain; não desabilitar proteções nem ampliar ACLs silenciosamente.
- Exibir estado recuperável quando o token exige autorização ou o Keychain estiver bloqueado. Não deixar operação pendente indefinidamente nem criar novas chamadas ilimitadas.
- Preservar computador, volume e identidade ao falhar; não recriar recursos como solução para autenticação.
- Exercitar relançamento do mesmo build, substituição do build, recusa e nova tentativa. Testar também a correção de Shift pelo viewer real.

## Mitigação implementada

- A consulta automática usa `LAContext.interactionNotAllowed`; autorização com UI só ocorre após o usuário clicar em **Autorizar acesso ao token**.
- Uma leitura de Keychain em andamento impede novas leituras concorrentes. A espera do app é limitada a 8 s no caminho automático e 60 s na autorização explícita; se o SecurityServer continuar bloqueado, a chamada existente pode permanecer em seu worker e novas leituras falham rapidamente até ela terminar. O contexto de autenticação é invalidado no timeout. Nenhum computador, volume ou token é recriado nesse caminho.
- Reconexões concorrentes para o mesmo computador compartilham uma tarefa no store. Falhas de autorização ou timeout interrompem a sequência de tentativas automáticas.
- Testes com token store falso cobrem autorização explícita e o gate de timeout sem consultar credenciais reais. A recuperação após troca de assinatura, a recusa do diálogo macOS e o fluxo visual ainda exigem conferência no app.

Os 70 testes Swift da rodada passaram; essa falha só foi observada no ambiente real. A meta não está concluída.
