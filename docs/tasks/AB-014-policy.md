# AB-014 · Política efetiva

Configuração versionada de criação, modo, CPU, memória, teto de boxes e rede. Cadeia global → projeto → sessão → terminal → agente, com escopos obtidos do workspace. Cada filho só restringe o resultado herdado. A UI mostra as camadas consultadas no painel de computador. IDs de projeto são caminhos canônicos. Dados inválidos não substituem o arquivo válido; migração v1→v2 preserva backup da v1.

Permissão de criação é consultada a cada solicitação. Recursos/rede se aplicam à criação de nova box; alterar configuração não redefine recursos de containers existentes nem interrompe processos. O teto é verificado em inícios/criações, com serialização entre chamadas deste processo. Não é ainda fila persistente nem lock entre múltiplos processos. Todas as boxes gerenciadas ativas contam para o teto efetivo da solicitação.

Modo sempre gráfico impede iniciar um container HTTP, pois desktop ainda não está integrado. O seletor de criação automática permanece indisponível até broker/identidade confiável. A política não reduz permissões do CLI nativo no host e não se apresenta como sandbox do Mac.

UI usa salvar explícito. Erro de leitura deixa o formulário bloqueado para evitar sobrescrever arquivo inválido. Primeiro uso já reaproveita as mesmas configurações; valores válidos salvos sobrevivem à interrupção antes de concluir onboarding.

Testes: herança sem ampliação, escopo alheio ignorado, gráfico obrigatório, validação de IDs, preservação de configuração inválida e backup de migração. A criação real com Docker continua sem prova neste host enquanto o daemon não estiver disponível.
