AGENT BOX · DESIGN v0.4
Preparado para Gabriel · 15 outubro 2026

COMECE AQUI
Abra index.html para a prévia interativa, ou Agent Box Preview.app para o app nativo.
No navegador, a página adapta o split à largura; o app mostra terminal + desktop lado a lado.
A referência de uso é Orca: terminais originais, workspaces e troca de clientes.
Maestrum informa a biblioteca de agentes. Nenhuma configuração desses apps foi importada.

EXPERIMENTE
• Agora: miniaturas em movimento, atividades e agentes. Hover nas sessões abre a prévia.
• Atlas: terminal ilustrativo e desktop; Assumir → Devolver muda a posse do controle.
• Seletor Claude Code/Codex: abre a passagem com checkpoint. Modelo troca dentro do cliente.
• Nova sessão: cliente ou Shell; Pasta, Worktree ou Avulso; desktop Docker opcional.
• Agentes → Atlas: AI memory, seleção de memórias, histórico, boxes e skills.
• Clientes locais: status de login já existente no terminal, sem “Conectar conta”.
• Testar ping / Testar som: toca somente ao clicar. Não solicita permissão de notificação.
• ⌘N abre Nova sessão; Escape fecha diálogos; ⌘Q encerra o app nativo.

CONTEÚDO
index.html                  Protótipo web local e interativo
Agent Box Preview.app       Protótipo SwiftUI/AppKit para Apple Silicon
Agent-Box-Preview.zip        App compactado
screens/                    16 telas nativas 2880×1800 e folha de contato
docs/spec.html              Especificação detalhada em 19 capítulos
docs/review.html            Verificações e limites observados
source/                     Código Swift, build, fonte Manrope e licença OFL
motion/agentbox-walkthrough.mp4  Estudo de navegação, 24 s / 60 fps
motion/box-loop.mp4          Asset reutilizável, 4 s / 60 fps
motion/timeline.html        Composição determinística window.seek(t)
motion/render.sh            Reprodução do pipeline 240 fps → 60 fps

O QUE ESTA ENTREGA FAZ
Demonstra a interface, o ritmo e as transições. Tem dados fictícios, estado de UI,
preview animado, navegação, seleção de agente/modelo/skills e controle humano simulado.
A versão web prioriza os fluxos de terminal, agentes e memória; Boxes e Resultados
usam as telas nativas exportadas como referência. Há botões ilustrativos de importação,
exportação, perfil e criação de agente. O código fonte os identifica como demonstração.

O QUE AINDA PERTENCE À IMPLEMENTAÇÃO
Não há PTY real, CLI em execução, Docker, stream remoto, autenticação consultada,
criação real de worktree, persistência de memória/perfil, coleta, notificação do macOS
ou transferência real de contexto. Nenhuma conta pessoal é consultada por este pacote.
Os nomes de modelos são exemplos de design, não um catálogo de acesso da sua conta.
Troca de CLI não transfere contexto interno oculto: a spec exige checkpoint verificável.
Os dados de UI reiniciam ao recarregar/fechar. As prévias de sites são ilustrações.

RECOMPILAR
Requer Xcode Command Line Tools e SDK macOS:
  bash source/build.sh
Swift 6.2.4; arm64, deployment target macOS 14; validado no Mac atual macOS 26.3.1.
Versões anteriores não foram testadas. Build local de desenvolvimento, não notarizado.
Não instala em /Applications nem altera preferências do sistema.

SERVIR A PRÉVIA WEB
  python3 -m http.server 8765 --bind 127.0.0.1 --directory .
Depois abra http://127.0.0.1:8765/index.html
A fonte e os assets são locais; não exige internet nem assinatura para abrir o design.

MOTION
Skill motion-designer; render determinístico com Playwright em 240 fps e blend de
4 frames para saída H.264 60 fps. Sem áudio no vídeo. Abra timeline.html com
?ar=1920x1200&play=1 ou box-loop.html com ?ar=512x512&play=1.
source/MotionAssetView.swift mostra AVPlayerLooper com poster para Reduce Motion.
O app usa animação por estado para interações; MP4 é somente asset visual reutilizável.

REVISÃO DE MARCAS · 16 outubro 2026
Logos oficiais de Claude, Codex, Docker, LinkedIn, X, Google e Crunchbase.
Origem, membro do kit e SHA-256 de cada asset: assets/brands/sources.json.
Os assets são locais e acompanham o app; não há hotlink nem busca de ícone em runtime.
As marcas identificam integrações e continuam pertencendo aos seus titulares.
