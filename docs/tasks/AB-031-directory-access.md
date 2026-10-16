# AB-031 · Acesso explícito às pastas de trabalho

## Diagnóstico observado

- Em teste local do app, shell iniciado no repositório dentro de Documents ficou preso em `getcwd/open`, e o probe Git da mesma pasta expirou. Um shell em `/tmp` executou `printf`, `tty` e `stty`. Após escolher explicitamente o repositório em `NSOpenPanel` e reiniciar o shell, o prompt abriu. Evidência visual: `docs/evidence/terminal-split-2026-10-16.png`.
- Isso sustenta hipótese de autorização macOS/TCC ou File Provider na pasta de Documents, mas não prova ainda a causa interna nem a eficácia do bookmark após relançar o app.

## Implementação

- A escolha de pasta em novo terminal, revisão de agente e destino de worktree agora salva bookmark em `Application Support/AgentBox/directory-bookmarks.json` com arquivo `0600`. Tenta bookmark com escopo de segurança; em build sem suporte para essa criação, guarda bookmark comum sem alegar que ele concede TCC.
- Antes de iniciar PTY, lançamento de agente, probe Git e criação de worktree, `WorkspaceDirectoryAccess` resolve o bookmark e chama `startAccessingSecurityScopedResource()` quando há escopo. Um grant de pasta pai cobre descendentes. Escopo ativo fica retido durante o uso do app e há `stopAll()` para o encerramento.
- Pasta restaurada com bookmark vencido ou movido exige reautorização. O menu do terminal oferece **Reautorizar pasta…** e só aceita a mesma pasta canônica. Nenhum caminho é trocado silenciosamente.
- Pastas digitadas manualmente continuam válidas se o sistema permitir. Se precisarem de autorização, o usuário pode escolher a pasta exata pelo painel.

## Verificação pendente

- Repetir o teste em Documents após relançamento para verificar se o bookmark restaurado habilita Git e zsh. Se o bookmark comum for usado no app sem sandbox, pode ser necessário selecionar novamente pelo painel.
- Não houve abertura de app ou build por este agente; a evidência de execução foi comunicada pelo agente raiz.
