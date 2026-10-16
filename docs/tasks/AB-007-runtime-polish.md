# AB-007 · Cores, foco e sondagens locais

## Alterações

- O renderer do SwiftTerm recebe `nativeBackgroundColor` `#272b33` e `nativeForegroundColor` `#dadce2`. Essas APIs ajustam também as cores padrão do emulador; sequências ANSI de um CLI continuam decidindo suas próprias cores.
- `TerminalRuntimeManager.focus(id)` torna o renderer real o first responder. `TerminalSurface` recebe `isFocused` e repõe o foco ao montar, selecionar ou substituir o renderer após restart. `start` foca um terminal já montado. A UI do workspace chama essa interface ao mudar de pane.
- `CLICommandProbe` põe o diretório do executável no PATH do subprocesso, necessário para CLIs instalados por NVM com shebang `#!/usr/bin/env node` num app aberto pelo Finder. O processo agora é esperado na mesma thread onde foi iniciado; um timer externo envia SIGTERM e, se necessário, SIGKILL. A captura permanece limitada a 16 KiB, sem exibir saída bruta de autenticação.
- Status Claude/Codex usa `CLIAuthStatus.interpret` e timeout de 8 s. O parser diferencia `Not logged in` de `Logged in` antes de classificar, e só expõe estados resumidos na UI. OpenCode continua não verificado.

## Evidência

- Um utilitário temporário que chama o mesmo `CLICommandProbe` executou `codex login status` sem imprimir a resposta. Antes do ajuste de PATH, com PATH de Finder, terminou em 0,07 s com código 127 (Node ausente). Depois do ajuste, terminou em 0,07 s com código 0. Com o PATH de Node presente, terminou em 0,05 s com código 0. A causa exata do timeout observado na instância anterior do app não foi isolada; o runner e o ambiente mudaram para remover as diferenças reproduzíveis.
- `ProcessesProbeTests` cobre CLI com intérprete no diretório do executável e respostas de autenticação sintéticas. `ProcessesPTYTests` verifica os componentes RGB do tema do renderer. O integrador executa a suíte completa após este patch.

## Limite

O foco só é aplicado a um renderer anexado a uma janela; `TerminalSurface` agenda o foco após a montagem quando necessário. A sondagem informa estado do CLI no momento da consulta, sem testar aceitação de uma chamada de modelo ou copiar credenciais.
