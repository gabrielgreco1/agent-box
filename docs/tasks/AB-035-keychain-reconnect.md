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

## Diagnóstico e correção complementar — 16/10, AB-040

O teste do app após novo build voltou a esperar no `SecItemCopyMatching`. Uma amostra do processo confirmou o backend antigo `SecItemCopyMatching_osx → SecKeychainItemCopyContent → SecurityServer.decrypt`. O timeout protegeu a UI, mas a thread continuou ocupada e impediu nova leitura.

O backend legado não usa o caminho de LAContext observado pela API moderna. A leitura automática agora também desativa interação opcional por `SecKeychainSetUserInteractionAllowed(false)` dentro de uma seção serializada, restaura o estado anterior em `defer` e trata `errSecAuthFailed` não interativo como necessidade de autorização explícita. O caminho interativo permanece separado. Timeout também expõe a ação de autorização. O acesso e o ACL do item não são alterados e nenhum token é recuperado por outra fonte.

Uma consulta controlada ao item do próprio Agent Box, sem imprimir seu valor, retornou imediatamente status `-25293` em vez de esperar; get/set da preferência retornaram sucesso. Testes confirmam restauração da preferência quando há erro e preservação de estado previamente desativado. A API é depreciada, mantida aqui estritamente para os itens legados existentes; migração para armazenamento moderno/assinatura estável continua necessária para uma distribuição futura.

A conferência do botão e da autorização pelo app ficou pendente porque o Mac bloqueou. Não declarar reconexão resolvida ponta a ponta. Fontes: [código legado da Apple](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/SecItem.cpp) e headers `SecKeychain.h` do SDK local; [LAContext.interactionNotAllowed](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed).
