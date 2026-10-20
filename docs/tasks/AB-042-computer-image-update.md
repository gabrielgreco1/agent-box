# AB-042 — Atualizar uma box existente

## Problema

Reconstruir a imagem local não muda os containers existentes. Uma box criada antes de AB-041 continua sem as ferramentas de extração novas, mesmo executando o app atualizado. A atualização precisa preservar a identidade e o perfil em uso nas sessões.

## Fluxo

O painel compara o digest da imagem do container com o digest da imagem configurada, disponível localmente. Não faz pull nem inicia Docker. Quando há diferença e o computador está parado, oferece **Atualizar computador**. O terminal também precisa estar parado. A atualização não inicia o novo container; o usuário pode iniciá-lo em seguida.

Um bloqueio de manutenção no gerenciador de terminais impede iniciar um processo por outra aba durante a atualização. O Core serializa a operação com criação/início/parada de computadores. Se o token requer autorização do Keychain, a UI oferece uma ação explícita; não inicia a box para obter essa autorização.

## Transação

1. Verificar ownership, terminal, metadados e volume realmente montado, estado parado, política efetiva e imagem local.
2. Resolver a imagem para um digest imutável e ler o token existente. Não criar ou apagar credenciais.
3. Registrar a operação em journal protegido junto aos metadados.
4. Criar um candidato parado, usando o mesmo volume, identidade, token e opções de isolamento. Não executar seu navegador nem modificar o perfil nesta etapa.
5. Revalidar o original, renomeá-lo como backup, colocar o candidato no nome canônico e atualizar os metadados preservando `createdAt`.
6. Após persistir os metadados, remover somente o container antigo. Nunca remover o volume. Limpar o journal e invalidar endpoints/tickets em cache.

Antes do commit dos metadados, uma falha restaura o original. Depois do commit, a recuperação mantém o novo container e conclui a remoção do backup. Identidade contraditória, container em execução ou estado Docker inconclusivo interrompem a recuperação. A UI precisa oferecer recuperação explícita mesmo quando não há container com nome canônico.

## Evidência de 16/10/2026

Build release e assinatura ad hoc do app/helper passaram. A suíte integrada passou com **123 testes, zero falhas**, incluindo o smoke opt-in Docker real (`RACKY_TEST_DOCKER_UPDATE=1`) e 9 testes focados da transação. No Docker real:

- tentativa de atualizar container ativo foi recusada sem mutações;
- atualização trocou o container e manteve IDs de computador/terminal, volume, token e data de criação;
- arquivos sintéticos em `/data/workspace` e `/data/profile` permaneceram após iniciar o novo container;
- falha injetada na segunda renomeação restaurou o container anterior e seus metadados;
- não sobrou candidato da atualização, container de teste ou imagem derivada do smoke.

A suíte também cobriu autorização explícita do token, falha ao salvar metadados, Docker inconclusivo, criação com efeito antes do erro, remoção de backup malsucedida, recuperação após renomeação/commit e bloqueio de inícios de PTY durante manutenção. Os testes de recuperação montam estados de interrupção; não são uma prova de resistência a perda física de energia.

## Verificação e limites

Testes de falha cobrem comandos, metadados e recuperação de operações interrompidas. O smoke opt-in usa contexto `colima-racky-dev`, stores temporários e token em memória; não lê o Keychain pessoal. Cria uma imagem derivada com tag exclusiva, mantém a tag normal intacta, verifica arquivos no volume e remove apenas os recursos do teste.

O mecanismo preserva arquivos; não garante compatibilidade entre quaisquer versões futuras de Chromium. Backups/versionamento de perfil continuam em AB-021. Alterações de containers por um administrador externo durante a operação não ficam sob o lock do aplicativo: por isso cada etapa revalida recursos, e recuperação incerta deve parar sem apagar dados. O CLI executado no Mac continua fora do isolamento do container.

Conferência visual e ciclo completo modelo → box → intervenção permanecem pendentes enquanto o Mac estiver bloqueado. Esta tarefa não conclui a spec global.
