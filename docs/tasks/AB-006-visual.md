# AB-006 · Ajuste visual do workspace

Referência: comparação fornecida em 16/10/2026 (`image-1.png`, Racky acima e Orca abaixo). O ajuste afeta apenas `Sources/Racky/Workspace/WorkspaceView.swift` e preserva o fluxo de sessão, terminal, layout, redimensionamento e PTY.

## Diferenças corrigidas

- O canvas do workspace agora usa `#272B33`, a sidebar `#282828` e a barra de abas/toolbar `#191919`. A superfície SwiftTerm recebe a mesma cor de fundo pelo trabalho de runtime separado.
- Removidos os traços entre sidebar e conteúdo, abaixo da toolbar, entre abas e acima do terminal. O divisor de sidebar e os divisores de panes continuam arrastáveis, mas sem regra visível. O contorno branco de foco foi retirado.
- Aba selecionada usa somente o fundo plano do canvas e texto claro. Aba não selecionada fica na barra escura, sem sublinhado ou borda.
- Uma sessão com um único pane mostra toolbar, abas e terminal. O cabeçalho de pane repetindo título, PID e ações deixa de aparecer. Quando há splits, um cabeçalho compacto de 28 pt identifica cada terminal; o pane focado usa tom discreto.
- Estado do terminal e ações de iniciar/parar/forçar parada, computador e splits ficam na toolbar de 40 pt. As ações continuam acessíveis por ícones com rótulos de acessibilidade e menus. Texto de chrome é regular em 13 pt; metadados permanecem menores.
- O cabeçalho da sidebar usa `Brands/racky.png` quando o recurso estiver no bundle, com símbolo funcional como fallback. A marca selecionada será carregada sem inventar conteúdo.
- Recolher a sidebar usa transição de 140 ms. A opção do sistema de reduzir movimento elimina essa animação. Arrastar divisórias continua imediato.
- Selecionar terminal, aba ou pane envia foco ao renderer real via `TerminalRuntimeManager.focus(_:)` e `TerminalSurface(isFocused:)`.

## Verificação e limite

Nenhum app, build ou teste foi iniciado nesta etapa, conforme pedido. O integrador fará a compilação e inspeção visual. O fundo do terminal depende da mudança de SwiftTerm realizada no módulo de runtime. Em layouts divididos, os cabeçalhos compactos continuam necessários para distinguir panes independentes.

## Comparação com a referência

| Diferença observada no print | Estado do código atual | Verificação pendente |
| --- | --- | --- |
| Terminal preto no Racky; cinza-azulado no Orca | `WorkspaceView.swift` define canvas `#272B33`; a superfície do terminal depende da configuração SwiftTerm no runtime. | Confirmar em captura do app que o PTY preenche o canvas nessa cor. |
| Contorno claro destacado ao redor do pane | `WorkspaceView.swift` não desenha contorno de foco; o pane focado recebe apenas tom de cabeçalho quando há split. | Conferir foco visível pelo sistema e ausência do contorno antigo. |
| Três faixas repetindo o terminal | `WorkspaceView.swift` mantém toolbar e abas compactas; omite cabeçalho de pane quando há um só terminal visível. | Verificar alturas e truncamento em 1000×650. |
| Hierarquia de projetos/sessões e tipografia mais densa no Orca | A sidebar mostra sessões, terminais e filhos observados, com chrome de sistema em 13 pt e metadados menores. | Conferir árvore e legibilidade com nomes longos; nenhuma captura nova foi produzida. |

AC01/AC02/AC07: a divisória da sidebar agora expõe largura e ajuste acessível em passos de 24 pt; o menu oferece os mesmos passos, restauração para 288 pt e ⌘K para busca. A largura e o estado recolhido já são persistidos no `WorkspaceSnapshot`. A sheet de revisão do agente passou de 640 para 550 pt de altura para manter a barra de ações disponível na janela mínima de 1000×650. Essas mudanças têm inspeção estática apenas; o integrador deve validar build, VoiceOver, atalhos, persistência após relançar e alcance dos botões nessa dimensão.
