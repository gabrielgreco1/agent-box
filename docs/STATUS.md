# Estado de implementação — 16/10/2026

A spec completa continua sendo o contrato de entrega. Código compilado, teste de módulo e fluxo ao vivo são evidências diferentes; nenhuma delas isoladamente equivale ao aceite dos 68 requisitos.

## Funcionando e verificado

- PTYs reais, múltiplos panes, início/parada explícitos, foco nativo, resize e Ctrl-C. Smoke visual executou `printf`, `tty` e `stty size` no terminal do aplicativo; dois panes com PIDs/TTYs distintos. A pasta do projeto em Documentos precisou de seleção explícita no NSOpenPanel e reinício do shell.
- Visual com terminal cinza-azulado, tabs tonais, sem contorno branco e barras redundantes; sidebar ajustável/recolhível. Marca própria empacotada em PNG/ICNS, usada na interface e no Dock. Recursos do app não dependem mais do checkout `.build`.
- Git local: branch/dirty/remote sanitizado, pasta sem Git, worktree explícito com espaços/metacaracteres, proteção contra colisões. Git não faz fetch/push ao abrir uma sessão.
- Biblioteca com agentes personalizados, seleção de memória/skills, revisões de definição e memória, validade/escopos, preview de contexto e histórico de execuções reais.
- Plano de lançamento Claude com arquivo de contexto protegido, preservando harness; vínculo persistente valida hash/executável/argv antes de restart explícito. Codex/OpenCode mantêm seus terminais nativos; ativação de contexto de agente salvo ainda é export-only nesses adapters. Anexar texto de skill não é instalação nativa da skill.
- Importação `.env` como dados, sem expansão; armazenamento de valores via Keychain, metadados separados, grants exatos/revogação. Testes usaram backend em memória, sem acessar credenciais pessoais.
- Política global/projeto/sessão/terminal/agente com tetos que filhos não ampliam, recursos por box e conexão Docker própria do app. Criação/início serializados no processo; fila persistente ainda pendente.

## Runtime Linux testado de verdade

Docker CLI e Colima instalados via Homebrew oficial. Perfil de desenvolvimento `agentbox-dev`: 2 CPUs, 4 GiB, disco virtual 24 GiB, sem mounts do host, sem ativar contexto global e sem serviço automático no login.

Imagem `agentbox-browser:ab019-dev`, arm64, ID `sha256:43bf099353c79148d8b960389f2359864a121183585e10b61d1c54ef7509166c`:

- Página JavaScript em modo headless, captura de desktop Xvfb/Openbox inteiro em 1280×800 e input real via XTEST.
- Clique mudou o resultado visual; revogação retornou ACK; token antigo deixou de funcionar; concessão humana nova funcionou.
- Perfil `/data` persistiu localStorage após reinício do container.
- Smoke com root filesystem read-only, cap-drop ALL, no-new-privileges, 1 CPU/2 GiB, 256 PIDs, tmpfs e porta somente loopback.
- Containers/volumes do smoke foram removidos pelo seu criador. Não extrapolar este teste para perfis de sites reais, backup/restore ou segurança contra shell arbitrário no mesmo container.

O viewer nativo, bridge de leases e serviço Docker autenticado estão integrados em código. A interface criou um container real, promoveu HTTP para desktop, exibiu streaming ao vivo e confirmou assumir/devolver controle humano. Corrigidos dois erros encontrados nesse fluxo: geração inicial zero rejeitada e respostas JPEG individuais do CFNetwork tratadas como stream inválido. A digitação remota funcionou, mas expôs símbolos com Shift descartados; a correção passou em teste de regressão. A última conferência visual dessa correção ficou pendente: após substituir o build ad hoc, duas reconexões aguardaram `SecItemCopyMatching` no Keychain. Esse estado ainda precisa de erro recuperável e autorização explícita, sem spinner indefinido.

## Evidências

- Suíte Swift com Docker integrado: **152 testes, zero falhas**, incluindo dois computadores de filhos, takeover isolado, persistência de perfil e atualização/rollback de imagem. Execução com Xcode e scratch de build isolado; resultados posteriores de regressão em `evidence/ab044-child-routing.json`.
- Suite Python do runtime: **20 testes locais**, além do smoke Docker real descrito em `tasks/AB-019-020-browser-runtime.md`.
- Build release e assinatura ad hoc verificados. O bundle fica no cache local por checkout, com link em `build/Agent Box.app`, para evitar metadados reaplicados pelo File Provider em Documentos. Build recusa substituir app em execução.
- Captura operacional: `evidence/terminal-split-2026-10-16.png`.
- Detalhes por feature e limites em `tasks/`, incluindo AB-031 a AB-034.

## Pendências que impedem conclusão

- Captura de subagentes Claude ligada ao lançamento revisado em AB-040; smoke do CLI real comprovou eventos assinados. Aquisição automática e despacho por filho implementados em AB-044. Falta conferir o fluxo completo TUI → sidebar → box ao vivo e implementar os demais harnesses.
- MCP de computador ligado ao lançamento Claude em AB-039 e provado com modelo Claude real em AB-045, em modo não interativo. Falta o fluxo interativo na TUI. Despacho e isolamento de filhos testados em AB-044; fila justa persistente/idempotência sob falhas, política de URLs e limites robustos entre processos continuam pendentes.
- Pedido de ação nativo, takeover pelas APIs do app e retomada de navegação passaram no fluxo real não interativo AB-045. Notificação visual e cliques humanos com o agente concorrente ainda precisam de prova, assim como a reconciliação de todos os caminhos de escrita. Viewer e assumir/devolver sem agente concorrente já foram exercitados pela UI.
- Grants de credenciais conectados ao broker; revogar não apaga valores já herdados por processos. CLI local continua com permissões reais do usuário no Mac.
- Listener e datasets parcialmente integrados em AB-046: faltam coleta restaurada após relançar, política herdada, cobertura adicional, acesso MCP e aceite visual. A captura é desativada por padrão; nesta rodada só foi ativada na fixture descartável.
- Ativação nativa verificável de skills em todos os clientes; histórico completo de computadores/perfis; retomada de conversas externas; troca confirmada de modelo e handoff transacional entre harnesses.
- Serviço PTY sobrevivente a quit/crash, recuperação de sono, perfis com backup/restore e 60 minutos de teste sustentado.
- Reconexão de tokens após trocar o build local: espera do Keychain observada; ver AB-035.
- Persistência de autorização de pastas após relançar precisa de conferência; bookmark foi implementado a partir do bloqueio real observado.

A meta permanece ativa. Plano integral em `EXECUTION-PLAN.md`.

## Checkpoint atual — AB-045

Claude real em PTY criou um filho, recebeu sua própria box, executou JavaScript, pediu intervenção e voltou a navegar após takeover/devolução pelas APIs do app. A box do pai permaneceu em HTTP e a do filho foi parada automaticamente. A suíte integrada passou em 160 testes, com dois opt-ins Docker anteriores desativados. Este fluxo foi não interativo e não substitui o aceite visual. Evidência em `evidence/ab045-native-child-flow.json`.

Retomada explícita por ID foi ligada ao menu, seleção de CLI/pasta e PTY, com identidade persistente e reserva por conversa até a saída do processo. Teste de PTY confirmou argv, duplicata recusada, liberação e cancelamento durante quit; retomada de históricos reais nos três clientes continua pendente. Acesso por teclado à sidebar e layout da revisão de lançamento também avançaram. Ver `tasks/AB-013-conversation-discovery.md`, `tasks/AB-045-native-flow-and-resume.md` e a comparação visual em AB-006.

## Estado atual do controle por filho — AB-044

Chamadas autenticadas agora chegam à box própria de cada filho. `computer_acquire` cria/inicia apenas sob política automática, com a skill revisada obrigatória. Controle humano em uma box não interrompe irmãos. O encerramento libera a concessão do filho e para suas boxes automaticamente iniciadas quando ociosas, preservando perfis e controle humano. O helper encaminha chamadas em paralelo com limite e encerra diante de falha de transporte.

Docker real confirmou dois computadores separados, navegação JS, takeover, revogação e persistência. O dispatcher do app foi exercitado com PTY e transporte controlado. O fluxo completo pela TUI e a conferência visual continuam pendentes; esses testes não completam os 68 aceites. Detalhes em `tasks/AB-044-native-child-routing.md`. As seções de continuação abaixo registram checkpoints históricos.

## Rodada paralela GPT-6 Sol medium

- AB-032: snapshot de skills nativas no plugin Claude, hashes e validação de restart. Testes locais e contrato oficial verificados; execução interativa real do catálogo ainda pendente. Pacotes com arquivos auxiliares passaram a ser copiados e verificados por hash em AB-036.
- AB-033: arraste, rolagem, atalhos e soltura de botões antes do ACK de revogação. Input real pelo viewer em conferência; teste prolongado e latência ainda pendentes.
- AB-034: inbox opt-in de hooks Claude com assinatura por execução, limite de tamanho e vínculo de sessão. Ainda não ligado ao lançamento do app; não anuncia captura ao vivo de filhos.

Recursos de teste: app encerrado, computador de teste parado e perfil Colima `agentbox-dev` desligado ao final da rodada. Imagem e volumes permanecem locais para retomada; nenhum serviço de login foi instalado.

## Scraping e navegador — AB-036/037

- Novas boxes registram o agente Web scraping e a skill local `webscraping-expert` como padrão pendente. O plugin revisado inclui os arquivos de apoio; o pacote pessoal não é publicado no Git.
- AB-038 permite iniciar o agente revisado no mesmo terminal parado que possui a box, preservando os panes. Snapshot e terminal têm identidades independentes. AB-039 liga as ferramentas MCP ao lançamento; invocação pelo modelo e prova de uso no histórico continuam pendentes.
- Desktop agora inicia Chromium como processo independente e conecta controle via CDP interno, sem override de user agent. Headless usa Chromium completo. Smoke real passou em navegação JS, clique, controle humano, saída limpa e persistência de localStorage ao recriar container.
- Build release/assinatura verificados. Conferência nativa criou o preset de scraping e preparou o pacote local sem iniciar CLI. AB-035 ganhou espera limitada e autorização explícita; recuperação real após troca de assinatura ainda não foi comprovada. Não foi comprovada resolução do CAPTCHA do Google, nem migração de boxes existentes.

## Continuação — AB-038

Bindings de contexto aceitam relançamento no terminal da box. Os testes reais de PTY distinguem planos e impedem substituir um processo ativo. A UI mantém sessão e pasta, verifica a skill atribuída e consulta a identidade Docker antes da troca. Detalhes em `tasks/AB-038-same-terminal-agent-launch.md`. O aceite completo de sessão → terminais → filhos → boxes segue pendente; a meta não está concluída.

## Continuação — AB-039

Claude Code recebe ferramentas MCP do computador atribuído no lançamento revisado, mantendo o harness nativo. O app e o viewer compartilham controle exclusivo; pedido de ajuda pausa as escritas até assumir/devolver explicitamente. O helper local não recebe o token do container. Configuração, binding, ownership e arquivos são revalidados no lançamento/restauração.

Testes: 103 passaram, incluindo helper e sockets reais, leases concorrentes, tampering, argumentos e frames autenticados. Build release e assinatura ad hoc passaram, incluindo o helper empacotado em `Contents/MacOS`. Não houve execução paga do Claude, abertura do app ou Docker nesta rodada. O próximo gate é a interação ao vivo Claude → box → pedido humano → takeover → retomada. Detalhes e limites em `tasks/AB-039-native-computer-mcp.md`.

## Continuação — AB-040

Observação nativa Claude integrada ao runtime e à árvore sessão → terminais → filhos, com opt-in revisado e identidade nova a cada início. 110 testes passaram, incluindo PTYs reais e proteção contra colisão de diretórios de invocação. Smoke do Claude instalado confirmou SessionStart/SubagentStart/SubagentStop de um subagente real, com HMAC válido, sem ferramentas ou arquivos pessoais. Build release/assinatura passaram.

A tentativa de conferir MCP no app encontrou novamente Keychain legado bloqueado; a correção de leitura sem UI retornou imediatamente em consulta controlada. O Mac bloqueou antes da conferência visual da correção e dos filhos. Não há prova do ciclo Claude → box → takeover → retomada ainda. O app e boxes de teste estão parados ao encerrar a rodada; o runtime de desenvolvimento também será desligado. Ver AB-035 e AB-040.

## Continuação — AB-041

Extração HTTP pública e leitura de texto/links da página conectadas ao MCP do Claude. 113 testes Swift, 20 Python, build/assinatura e smoke Docker real arm64 passaram. O smoke comprovou HTTP HTTPS, identidade, recusa de IP local na rota HTTP, extração JS headless/desktop, campos de formulário excluídos, Unicode, revogação e persistência após recriar o container. Evidência em `evidence/ab041-scraping-runtime.json`; contratos e limites em `tasks/AB-041-scraping-tools.md`.

A skill padrão e o perfil persistente foram auditados. Não se comprovou ausência de CAPTCHA, uso dessas ferramentas pelo modelo no app nem migração de boxes antigas. O Chromium da box tem perfil próprio, separado do Chrome pessoal. App e boxes de teste encerrados; perfil de desenvolvimento desligado após a rodada.

## Continuação — AB-042

Atualização explícita da imagem de boxes paradas integrada ao painel, preservando volume, identidade, token e data de criação. Journal protegido permite recuperar troca interrompida; guardas bloqueiam início de terminal e acesso por endpoints antigos durante a manutenção. O painel oferece autorização do Keychain sem iniciar a box e recuperação mesmo sem container canônico.

123 testes passaram, incluindo Docker real com troca de imagem, persistência de arquivos no workspace/perfil e rollback por falha de rename. Testes locais cobrem janelas de interrupção e falhas de metadados. Build release e assinatura ad hoc passaram. App e recursos de teste encerrados; perfil Colima de desenvolvimento desligado ao concluir. Nenhuma box existente do usuário foi migrada automaticamente. A conferência visual permanece impedida pelo Mac bloqueado. Ver `tasks/AB-042-computer-image-update.md`.

## Continuação — AB-043

Computadores agora distinguem dono terminal de dono subagente nativo, preservando metadados antigos. O painel do filho permite gerenciar sua box sem criar um PTY fictício, valida pai/filho ativos antes de criar/reiniciar e mantém boxes históricas visíveis. Chamadas MCP do Claude recebem proveniência assinada pelo hook nativo, com validade e recusa de replay. A identidade do pai é conferida no registro de eventos autenticados. Uma chamada de filho ainda é recusada com motivo explícito: **o despacho de ferramentas para a box própria do filho permanece pendente**; nunca cai no computador do pai. Ver `tasks/AB-043-native-child-computers.md`.

O lançamento revisado de scraping agora entrega a skill `webscraping-expert` também ao contexto inicial de subagentes Claude, em partes verificadas por hash. Criar a box de um filho exige esse contexto no lançamento do pai; não existe injeção retroativa em um agente já aberto. Conteúdo pessoal fica somente no pacote local protegido. Um probe Claude real recebeu todas as partes de uma fixture de 40 KB; outro distinguiu chamadas nativas do pai e do filho. Evidências em `evidence/ab043-child-skill-context.json` e `evidence/ab043-native-routing-probe.json`.

135 testes Swift executados sem falhas (um teste Docker opt-in ignorado) e cinco testes Python de hooks passaram. Build release e verificação da assinatura ad hoc passaram. Não houve inicialização de Docker ou app nesta rodada. Fluxo completo na TUI, controle da box pelo filho e inspeção visual seguem como gates. O Chromium mantém perfil próprio persistente; a skill não garante ausência de CAPTCHA e a causa do bloqueio no Google não foi determinada.

## Continuação — AB-046

Captura opt-in por box integrada ao runtime e ao painel **Capturas e dados**. Observa metadados do navegador e JSON escalar selecionado da ferramenta HTTP controlada, com hosts explícitos, retenção, limites e perdas declaradas. Coleta do host continua em segundo plano enquanto o app está aberto; abrir o painel não ativa captura. Histórico e datasets ficam disponíveis offline, exportação CSV/JSON inclui manifesto e proveniência, e apagar capturas não apaga os resultados.

Verificação: **172 testes Swift, zero falhas, três opt-ins anteriores ignorados**; o novo smoke Docker foi executado. **30 testes Python** passaram. O smoke local comprovou opt-in, hosts, redirecionamento, fetch JavaScript durante ociosidade, nova aba desktop, URLs sanitizadas, rotação de captura, exportação de metadados e perfil preservado após reinício. Não prova captura de corpos JSON do navegador, que continua explicitamente fora da cobertura. Evidência: `evidence/ab046-capture-results.json`.

Não houve nova busca no Google. `webscraping-expert` segue como padrão no lançamento revisado de scraping e nos filhos Claude desse lançamento; Chromium usa perfil próprio persistente, sem override de user agent. Não há diagnóstico conclusivo para o CAPTCHA observado nem promessa de ausência de desafios. A UI continua pendente de conferência porque o Mac está bloqueado. Imagem nova exige atualização explícita de boxes existentes; as duas boxes anteriores não foram alteradas. Ver `tasks/AB-046-capture-results.md` para os gates restantes. A meta global continua ativa.
