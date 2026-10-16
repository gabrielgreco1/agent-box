# AB-037 — Navegador visível com perfil próprio

## Pedido e diagnóstico

O usuário quer um navegador utilizável manualmente, com sessões persistentes, além da skill de scraping padrão. O navegador anterior era Chromium iniciado diretamente por Playwright com perfil exclusivo da box. Não era o Chrome pessoal do Mac. Não há evidência suficiente para atribuir o CAPTCHA observado ao user agent, à automação ou à rede especificamente.

Uma falha de digitação anterior transformou uma URL local em busca. Isso explica a consulta inesperada, não prova a causa do bloqueio. A correção de Shift está documentada na rodada anterior; sua última conferência visual ainda depende da reconexão de Keychain descrita em AB-035.

## Implementação

- Desktop: Chromium completo, iniciado como processo independente no Xvfb/Openbox. Perfil em `/data/profile`, downloads em `/data/workspace/downloads`.
- O agente conecta via CDP interno com `no_defaults=True`. Sem substituir user agent, copiar perfil do Mac ou alterar fingerprints.
- CDP em loopback dentro do container; somente API autenticada publicada em loopback do host. Processos arbitrários no mesmo container continuam fora do isolamento de leases.
- Headless usa o mesmo binário Chromium completo. Alternância fecha e reabre o navegador; cookies e armazenamento persistente podem sobreviver, formulários e estado em memória não são preservados.
- Navegação traz a página controlada para frente. Isso corrigiu um clique que atingia uma aba vazia durante o teste real.
- SIGTERM encerra o servidor, fecha o navegador e aguarda sua saída antes de encerrar o display. `--init` reaproveita o mesmo contrato do serviço Docker do app e recolhe processos filhos. Não removemos locks de perfil às cegas.
- Nenhuma pesquisa repetitiva no Google, resolução automática de CAPTCHA ou mudança de proxy faz parte desta validação.

## Evidência de 16/10/2026

Smoke arm64 no Colima `agentbox-dev`, imagem `sha256:43bf099353c79148d8b960389f2359864a121183585e10b61d1c54ef7509166c`:

1. JavaScript headless executou fixture local: pixel vermelho `[254, 0, 2]`.
2. Desktop inteiro 1280×800; clique XTEST mudou fixture para verde `[0, 127, 0]`.
3. Revogação teve ACK; token anterior foi rejeitado; novo controle humano funcionou.
4. Container encerrou com status zero, foi removido e outro usou o mesmo volume.
5. localStorage persistiu: fixture azul `[0, 0, 254]` após reinício.
6. CDP informou `Chrome/153.0.8010.12`; user agent padrão do binário: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36`. Essa string não foi fabricada pelo app; não representa necessariamente a arquitetura física.
7. Porta 9222 não estava publicada. Containers e volume exclusivos do smoke foram removidos.

## Limites

O teste prova navegação, input e persistência local, não preservação de autenticação em todos os sites. Downloads via CDP, recuperação de crash, migração de perfil e atualização de containers existentes ainda exigem validação própria. Containers existentes mantêm a imagem antiga; rebuild de uma tag não os migra. Não anunciar que o CAPTCHA foi resolvido ou que o navegador é indistinguível de navegação pessoal.

Fontes: [Google — tráfego incomum](https://support.google.com/websearch/answer/86640?hl=pt-BR), [Playwright — connect_over_cdp e no_defaults](https://playwright.dev/python/docs/api/class-browsertype#browser-type-connect-over-cdp), [Chrome — perfil dedicado para remote debugging](https://developer.chrome.com/blog/remote-debugging-port).
