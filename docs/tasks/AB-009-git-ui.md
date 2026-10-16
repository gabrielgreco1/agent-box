# AB-009 · Git e worktrees na UI do workspace

## Implementação

- `WorkspaceView` consulta `GitWorkspaceInspector<GitProcessRunner>` fora da thread principal para cada terminal real. A observação diferencia checkout, pasta comum, verificação em curso e erro. Ela é atualizada ao abrir o workspace, selecionar terminal, reativar o app ou pedir **Atualizar Git**. Uma geração por consulta impede que respostas antigas substituam as novas.
- Para checkout observado, a linha do terminal mostra branch ou HEAD destacado, alterações locais e remote normalizado. A sessão mostra **Várias branches** quando seus terminais Git observados divergem. O inspector da toolbar exibe o caminho, estado dirty, remote completo e link web somente quando o normalizador fornece uma URL. Pasta comum mostra explicitamente que não é repositório.
- **Criar worktree…** aparece apenas para checkout observado. O usuário escolhe referência local, nova branch e destino; o Core valida commit, branch, colisão e destino antes de executar `git worktree add` com argv. O sheet preserva o erro real do Core. Sucesso adiciona um novo terminal do mesmo CLI, na pasta do novo worktree, com título local da branch e estado parado. Nenhum comando do CLI é iniciado automaticamente.
- A UI não executa stash, reset, clean, remoção de worktree, push nem escrita no GitHub. O botão **Abrir repositório** apenas abre a URL normalizada quando ela existe; remote configurado não é apresentado como autenticação.

## Critérios de aceite

- **AC16 (parcial, dependente de integração):** pasta comum continua válida; branch efetiva, dirty state e remote são observados por terminal; criação explícita de worktree usa validação do Core para branch/ref/destino, incluindo caminhos com espaços e colisões. O novo terminal fica parado até início manual.
- **AC17 (parcial):** remote é apresentado em leitura e URL GitHub normalizada pode ser aberta. Auth GitHub e resolução de PR ainda não existem; a UI não sugere que remote implique conta conectada.
- **AC18 (parcial):** nomes locais continuam independentes da branch e do título nativo da conversa. Esta etapa não implementa renomeação de conversa CLI nem retomada nativa.

## Verificação e limites

O Core Git já possui `GitWorkspaceTests` para inspeção e criação segura. Nenhum build, teste ou app foi iniciado nesta etapa, por instrução do integrador. A compilação e verificação visual da UI ficarão com a integração serial. O estado Git é uma observação pontual, atualizada nas ações acima; não há watcher de filesystem nem GitHub auth/PR nesta etapa.
