# AB-039 — Ferramentas da box no Claude Code nativo

## Entrega

O lançamento revisado do agente de scraping no terminal dono da box inclui um servidor MCP stdio temporário, usando `--mcp-config`. O executável `AgentBoxMCP` acompanha o app. Não altera a configuração global do Claude e não troca seu harness ou TUI. Codex/OpenCode ainda precisam de adapters próprios comprovados; esta entrega não anuncia suporte MCP nesses clientes.

O planner congela o JSON de configuração e uma capability aleatória por plano, com hashes e arquivos locais protegidos. A restauração verifica ambos. O token de API do container permanece no processo do aplicativo; não aparece em argumentos, variáveis de ambiente ou contexto entregue ao CLI. O helper recebe somente caminhos para socket e capability.

Antes do PTY, o app revalida a atribuição persistida, sessão, terminal, agente, identidade Docker e health autenticado. O socket só aceita operações de computador depois de confirmar que o processo do plano está rodando. Starts concorrentes no mesmo terminal são bloqueados. Encerrar o terminal fecha o canal imediatamente e revoga a lease própria após drenar uma operação em andamento. Sair do app fecha todos os seus canais; não há serviço oculto mantendo os agentes ativos.

## Ferramentas

| Ferramenta | Comportamento |
|---|---|
| `computer_status` | Modo, controle atual e espera de intervenção. |
| `computer_screenshot` | JPEG do navegador headless ou desktop inteiro; valida identidade, geração, prontidão e fonte. |
| `computer_mode` | HTTP, headless ou desktop, respeitando “sempre gráfico”. Mudar modo reinicia o browser; não promete conservar DOM. |
| `computer_navigate` | URL HTTP(S), sem credenciais embutidas, sob lease do agente. |
| `computer_input` | Mouse, tecla, texto e scroll no desktop 1280×800; argumentos estritos. |
| `computer_request_help` | Suspende escritas, libera lease do agente e registra pedido humano. Som depende da preferência de notificações do usuário. |

O pedido de ajuda armazena descrição genérica e referência ao terminal, não o texto livre do modelo. Detalhes ficam na conversa do terminal. Tentar escrever novamente não retoma controle: é necessário assumir e devolver explicitamente pelo viewer. Fechar o viewer não equivale a resolver o pedido. Callbacks antigos levam a identidade da concessão e não podem revogar uma concessão nova.

Viewer e agente compartilham a mesma bridge. Agente não revoga humano nem outro agente. Takeover espera ACK de revogação antes de habilitar input. A política efetiva vem da ancestralidade que o host validou e é relida nas chamadas. Modificar criação/rede para desativada impede novas operações.

## IPC e falhas

Socket Unix por plano, diretório 0700, socket 0600, checagem de UID do peer, capability constante na comparação, no máximo oito handlers, entrada 64 KiB e saída 12 MiB. Leituras/escritas têm prazo total; operações possuem prazo de 60 segundos. Configuração e segredo não entram em logs ou mensagens de erro do protocolo. Um diretório de socket desconhecido após crash não é removido automaticamente: preparar novo lançamento permite recuperar sem adivinhar ownership.

O canal não oferece shell arbitrário. Isso não torna o Claude local uma sandbox: o CLI continua com suas permissões normais no Mac, e outros MCPs/configurações do usuário continuam sujeitos ao próprio harness. Controle exclusivo aqui cobre as rotas da box que passam pelo broker.

## Aceite e limites

Verificação automatizada cobre JSON-RPC, handshake/listagem/chamadas, erros sanitizados, argumentos estritos, Unix socket real, helper real por stdin/stdout, arquivos alterados, bindings legados, controle concorrente e frames autenticados. O resultado integrado e build ficam em STATUS.md.

Ainda precisa de prova ao vivo: Claude invocando essas ferramentas na box real, interrompido por takeover humano e retomando após devolução. Não houve request pago a um modelo nessa rodada. Não há prova de resolução do CAPTCHA do Google. Captura de subagentes e atribuição de boxes por filho continuam outro gate. Política de destinos, fila persistente, retomada após crash e reconciliação sob sono/reinício permanecem pendentes.

## Referências de contrato

- [Claude Code — MCP](https://code.claude.com/docs/en/mcp): servidor stdio e configuração local por lançamento.
- [MCP — transportes](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports): mensagens JSON-RPC por linha, stdout reservado ao protocolo.
