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

- Suíte Swift integrada: **82 testes, zero falhas**, incluindo snapshot de pacote completo de skills e atribuição padrão de scraping.
- Suite Python do runtime: **10 testes locais**, além do smoke Docker real descrito em `tasks/AB-019-020-browser-runtime.md`.
- Build release e assinatura ad hoc verificados. Empacotamento em staging temporário evita metadados de File Provider durante a assinatura; build recusa substituir app em execução.
- Captura operacional: `evidence/terminal-split-2026-10-16.png`.
- Detalhes por feature e limites em `tasks/`, incluindo AB-031 a AB-034.

## Pendências que impedem conclusão

- Captura ao vivo de subagentes nativos: registry/eventos documentados existem, mas hooks confiáveis ainda precisam ser instalados e comprovados em cada harness. Sem isso não há atribuição automática de box a filho comprovado.
- Orquestrador/MCP conectado, fila justa persistente/idempotência sob falhas, política de URLs e limites robustos entre processos.
- Pedidos de ação vindos do agente, notificação real, takeover de um agente nativo em execução e reconciliação de todos os caminhos de escrita. Viewer e assumir/devolver sem agente concorrente já foram exercitados pela UI.
- Grants de credenciais conectados ao broker; revogar não apaga valores já herdados por processos. CLI local continua com permissões reais do usuário no Mac.
- Listener por fonte, evidências/datasets, cobertura e redaction de rede. Nenhum tráfego do usuário é capturado por este build.
- Ativação nativa verificável de skills em todos os clientes; histórico completo de computadores/perfis; retomada de conversas externas; troca confirmada de modelo e handoff transacional entre harnesses.
- Serviço PTY sobrevivente a quit/crash, recuperação de sono, perfis com backup/restore e 60 minutos de teste sustentado.
- Reconexão de tokens após trocar o build local: espera do Keychain observada; ver AB-035.
- Persistência de autorização de pastas após relançar precisa de conferência; bookmark foi implementado a partir do bloqueio real observado.

A meta permanece ativa. Plano integral em `EXECUTION-PLAN.md`.

## Rodada paralela GPT-6 Sol medium

- AB-032: snapshot de skills nativas no plugin Claude, hashes e validação de restart. Testes locais e contrato oficial verificados; execução interativa real do catálogo ainda pendente. Pacotes com arquivos auxiliares passaram a ser copiados e verificados por hash em AB-036.
- AB-033: arraste, rolagem, atalhos e soltura de botões antes do ACK de revogação. Input real pelo viewer em conferência; teste prolongado e latência ainda pendentes.
- AB-034: inbox opt-in de hooks Claude com assinatura por execução, limite de tamanho e vínculo de sessão. Ainda não ligado ao lançamento do app; não anuncia captura ao vivo de filhos.

Recursos de teste: app encerrado, computador de teste parado e perfil Colima `agentbox-dev` desligado ao final da rodada. Imagem e volumes permanecem locais para retomada; nenhum serviço de login foi instalado.

## Scraping e navegador — AB-036/037

- Novas boxes registram o agente Web scraping e a skill local `webscraping-expert` como padrão pendente. O plugin revisado inclui os arquivos de apoio; o pacote pessoal não é publicado no Git.
- AB-038 permite iniciar o agente revisado no mesmo terminal parado que possui a box, preservando os panes. Snapshot e terminal têm identidades independentes. Ferramentas MCP, controle pelo CLI e prova de uso no histórico continuam pendentes.
- Desktop agora inicia Chromium como processo independente e conecta controle via CDP interno, sem override de user agent. Headless usa Chromium completo. Smoke real passou em navegação JS, clique, controle humano, saída limpa e persistência de localStorage ao recriar container.
- Build release/assinatura verificados. Conferência nativa criou o preset de scraping e preparou o pacote local sem iniciar CLI. AB-035 ganhou espera limitada e autorização explícita; recuperação real após troca de assinatura ainda não foi comprovada. Não foi comprovada resolução do CAPTCHA do Google, nem migração de boxes existentes.

## Continuação — AB-038

Bindings de contexto aceitam relançamento no terminal da box. Os testes reais de PTY distinguem planos e impedem substituir um processo ativo. A UI mantém sessão e pasta, verifica a skill atribuída e consulta a identidade Docker antes da troca. Detalhes em `tasks/AB-038-same-terminal-agent-launch.md`. O aceite completo de sessão → terminais → filhos → boxes segue pendente; a meta não está concluída.
