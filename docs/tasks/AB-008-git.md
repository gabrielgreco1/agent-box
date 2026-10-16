# AB-008 · Git e worktrees locais

## API para integração

- `GitWorkspaceInspector().inspect(at: URL) throws -> GitCheckout?`: `nil` para pasta comum ou shell fora de checkout Git. `GitCheckout` contém `rootURL`, `branch` opcional (`nil` em detached HEAD), `isDirty` e `remote` opcional. A branch é consultada no checkout efetivo, então terminais em worktrees diferentes mostram branches diferentes.
- `GitWorktreeManager().createWorktree(repositoryURL: URL, reference: String, newBranch: String, destinationURL: URL) throws -> GitCheckout`: ação explícita que cria um worktree e uma nova branch a partir de commit local validado. Aceita pasta de destino inexistente ou vazia, fora do checkout atual. Caminhos com espaço e metacaracteres são passados como argumentos, nunca concatenados em shell.
- `GitRemoteNormalizer.normalize(_:)` converte remotes HTTPS/HTTP/SSH/Git e formato `git@host:path` em host/caminho para exibição sem usuário, senha, query ou fragmento. `webURL` só é fornecida para `github.com`; remote sozinho não afirma autenticação GitHub.

## Comportamento e limites

As leituras usam comandos Git locais e timeout. O runner limita saída a 1 MiB por stream, usa stdin nulo e desativa prompt interativo. Não há fetch, push ou comando de rede. Dirty considera mudanças rastreadas e arquivos não rastreados normais; ignorados ficam fora do indicador. Falhas de leitura da branch indicam detached HEAD como `nil`.

Antes de criar um worktree, o serviço valida diretório Git, referência resolvida a commit, nome da branch, colisão com branch existente e destino vazio/escrevível. O `worktree add -b` recebe o hash do commit validado. Não faz stash, reset, clean, remoção de worktree nem alteração automática do checkout atual. Se `worktree add` falhar, limpa apenas pasta nova ainda vazia e branch nova sem worktree que continue apontando para o commit inicial; caso contrário preserva o estado e informa que a limpeza ficou incompleta. Fechar terminal não remove worktree.

O módulo não interpreta uma URL remota como sessão autenticada, PR, ou origem confiável de dados. GitHub read-only, escolha de branch em UI e políticas de criação de branch são integração posterior.

## Verificação

Testes em `GitWorkspaceTests.swift` criam repositórios descartáveis e cobrem pasta comum, branch/dirty/remote sem credenciais, criação de worktree com espaço e metacaracteres, branch colidente e destino ocupado. O comando `git worktree add -b <branch> -- <destino> <sha>` foi verificado manualmente em repositório temporário: saída 0 e worktree criado. O integrador executará build/testes Swift em série após as edições paralelas; este agente não rodou o build completo conforme contrato da tarefa.

Integração: comparação de destinos usa caminhos canônicos, pois URLs Foundation equivalentes podem diferir na codificação de ponto e vírgula e barra final. O teste com metacaracteres cobre a regressão.
