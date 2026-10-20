# BK-12 · Computadores na nuvem: estudo de viabilidade e avaliação de riscos

> Racky (ex-Agent Box) · Roadmap `09-roadmap.md` §4.4b, item BK-12 · Pesquisa feita em **20/10/2026** · Nenhum código foi alterado.
> Público: dono do produto (não especialista), com rigor técnico suficiente para o time de engenharia decidir.

---

## Decisões do dono (2026-10-20)

Respostas às perguntas da §10 (registradas como P27 em `spec/00-decisions.md`):

1. **Para que serve a nuvem:** paralelismo e mais capacidade de computação do que o Mac aguenta. Não é "computadores 24 h".
2. **O Mac continua sendo o controlador.** Um computador na nuvem só existe enquanto um subagente está mandando trabalho para ele. A chave morta na VM está certa; **não há controlador do lado da nuvem**.
3. **Tetos de gasto:** o USUÁRIO define o teto diário e o mensal.
4. **Região:** o USUÁRIO escolhe, com latência e preço visíveis.
5. **Conta do usuário final, com acabamento:** login pelo navegador (`aws login`, credenciais de curta duração; Identity Center/SSO para empresas) + um clique de CloudFormation quick-create que cria um papel de privilégio mínimo restrito a recursos com a tag Racky e um alarme de orçamento. O app só opera com esse papel.
6. **Proxy upstream:** o USUÁRIO decide se usa.
7. **Aviso de uso aceitável:** aviso completo com confirmação na primeira conexão de cada conta/provedor; depois, uma linha curta sempre visível no card de aprovação e no viewer de todo computador na nuvem; reconfirmar quando o AUP do provedor mudar.
8. **Portabilidade:** todos os provedores, o usuário escolhe. A interface de provedor é central desde o MVP (AWS primeiro; cada provedor é um adaptador depois do próprio spike).
9. **Modo isolado (CLI do agente dentro do computador) na nuvem:** vai depois, em dois passos (máquina primeiro; depois máquina com o agente dentro). O desenho das credenciais do agente é pré-requisito do passo 2.
10. **Arquivos do agente:** o que ele escreve em `/work` volta ao Mac automaticamente (mesma pasta do run, como no local) antes de a VM ser apagada.

Consequências já implementadas na fundação (BK-12 Fase 1, T-01 a T-07): `ComputerHost` (`.local`/`.remote`), `CloudProvider` com provedor falso, transporte Docker por túnel SSH, política de chave morta/vida máxima/reaper/teto de gasto e volta dos arquivos por API de arquivo.

---

## 0. Resumo executivo

1. **É possível?** Sim, mas não "do jeito que está" em qualquer nuvem. O nosso container precisa de `NET_ADMIN` (firewall por usuário), Xvfb, Chromium e acesso de rede cru. Isso roda em **uma máquina virtual (VM) comum** com Docker e **não roda** em ECS Fargate nem em Cloud Run (a documentação proíbe a capacidade).
2. **Melhor caminho:** **AWS EC2 com Docker**, uma "máquina anfitriã" (host) que hospeda vários computadores, reaproveitando o `DockerClient` atual por um túnel SSH autenticado. É a rota que reaproveita mais código (estimativa: 70% a 80% do backend Docker) e a única que mantém o container idêntico (P24), o viewer, o egress e as ferramentas MCP sem redesenho.
3. **Segundo provedor:** Fly.io (máquinas Firecracker com `gru` = São Paulo) ou Hetzner (token único, preço mínimo). Cloudflare **não é o lugar para rodar o computador** hoje; serve melhor como túnel de acesso (v2).
4. **Quanto custa:** um computador de 2 vCPU/4 GB custa cerca de **US$ 0,03 a 0,07 por hora** em VM própria (EC2 `t4g.medium` US$ 0,0336/h; `c7g.large` US$ 0,0725/h), e **US$ 0,17 a 0,24 por hora** nos serviços de sandbox (E2B, Daytona, Modal). Um lote de 15 headless + 2 desktop numa única VM `c7g.4xlarge` custa **~US$ 0,58/h (~US$ 0,034 por computador-hora)**. Mais IPv4 público (US$ 0,005/h) e tráfego de saída.
5. **Riscos principais:** (a) **instância órfã cobrando para sempre** (o maior); (b) credencial da nuvem do usuário vazar ou ser permissiva demais; (c) VNC/admin exposto à internet por erro de configuração; (d) IP de datacenter bloqueado por sites-alvo, então o proxy continua necessário; (e) o IP e a conta são do usuário, então scraping abusivo vira problema de conta suspensa; (f) latência do viewer a partir do Brasil (~115 ms até us-east-1).
6. **Esforço estimado:** spike de 3 dias, MVP em AWS em **~30 agent-days**, v1.1 de endurecimento ~12, segundo provedor ~12.
7. **O que NÃO fazer:** Fargate/Cloud Run com o container atual; abrir portas do Docker/VNC/admin para a internet; guardar chave AWS de longa duração com permissão de administrador; deixar a limpeza de órfãos só para o app (o app pode estar fechado).
8. **Condição para começar:** decidir o modelo de segurança do túnel (§4.2) e a política de custo-teto (§6). Perguntas em aberto na §10.

---

## 1. O que precisa ser replicado (leitura do código)

Fontes: `docs/rebuild/spec/07-computers-and-subagents.md` (§2.2, CS-110 a CS-116), `00-decisions.md` (P24), `runtime/computer/Dockerfile`, `agentbox_supervisor/firewall.py`, `Packages/AgentBoxKit/Sources/AgentBoxDocker/`.

### 1.1 O computador hoje

Um container por computador (`ab-<id8>`), imagem única, base Playwright Python (noble). Dentro:

| Peça | Detalhe | Exigência para a nuvem |
|---|---|---|
| Xvfb + Openbox + Chromium headed | Chromium com `--no-sandbox --disable-dev-shm-usage` (`browser.py`) | Não precisa de `/dev/shm` grande nem de user namespaces. Bom: roda em quase qualquer lugar. |
| Servidor de controle `:8765` | Só em loopback, CDP por **pipe** | Nada a expor. |
| x11vnc `:5900` | Só loopback; ponte WebSocket com ticket de uso único (60 s) | Nada a expor diretamente. |
| Proxy de egress `:3128`, admin `:8790` | Reqlog com corpos, SSRF, cadeia para proxy upstream (Zyte etc.). **O admin `:8790` é a única porta publicada** | Esta é a porta que a nuvem precisa tornar alcançável de forma segura. |
| Dois uids (`agent` 10001, `egress` 10003) | Segredos em tmpfs `/run/agentbox` 0700 | Exige kernel Linux padrão e tmpfs. |
| **Firewall por uid** (`iptables -m owner --uid-owner`) | O supervisor roda como root com `NET_ADMIN, SETUID, SETGID, SETPCAP, KILL`; se o iptables falhar, **o container sai (fail closed)** (`firewall.py`, `__main__.py`) | **O requisito mais restritivo.** Elimina Fargate, Cloud Run e provedores que não deixam adicionar capacidades. |
| Hardening | `--read-only`, `CapDrop ALL`, `no-new-privileges`, `--init`, `PidsLimit 1536`, tmpfs `/tmp` 1 GiB | VM com Docker real cobre tudo. |
| Memória estimada | headless 1,2 GiB, desktop 2,2 GiB (07 §2.4); alvo 15 headless + 2 desktop = 22,4 GiB | Define o tamanho do host (§4.3). |
| Imagem | arm64 é o alvo verificado; **amd64 está marcado "Unverified"** (CS-122) | Graviton (arm64) combina; provedores só-amd64 exigem validar a imagem antes. |

### 1.2 Como o app fala com ele hoje

| Capacidade usada | Onde | Observação para a nuvem |
|---|---|---|
| Docker Engine API (create, start, stop, rm, inspect, list, exec, stats, events, volumes, networks, labels) | `DockerClient.swift` | Funciona igual contra qualquer Docker remoto. |
| **Transporte somente Unix Domain Socket** | `DockerTransport.swift` (`UDSConnection`) | **Não há transporte TCP/TLS nem SSH hoje.** Para reaproveitar o cliente, o socket remoto precisa aparecer como um UDS local (túnel) ou o transporte ganha um modo TCP+TLS. |
| Exec com stdin e conexão sequestrada (`Upgrade: tcp`), como usuário `agent` | `ExecSession.swift`, `ComputerToolService+Exec.swift` | Funciona por qualquer túnel que preserve a conexão (SSH sim). |
| Porta efêmera publicada em `127.0.0.1` | `ComputerProvisioner.containerSpec` (`PortBindings`), `EgressAdminClient` (URL fixa `http://127.0.0.1:<porta>`) | Em nuvem, "127.0.0.1" é a VM, não o Mac; precisa de um forward local por computador. |
| **Binds de pastas do Mac** (`work/`, `logs/`, segredos de tarefa) | `ContainerSpec.binds` | **Não existem na VM.** Trabalho, reqlog e segredos precisam de caminho alternativo (§4.4). |
| Eventos por label, GC por label `agentbox.owner` | `EventMonitor.swift`, `GarbageCollector.swift`, `Labels.swift` | Excelente base para o "reaper" de órfãos. |
| Capacidade (`MemTotal`, `NCPU`) e fila | `Capacity.swift`, CS-130/131 | Reaproveitável: o host remoto responde `/info`. |
| Viewer: noVNC em WKWebView sobre WebSocket ao admin `/vnc?ticket=…` | spec CS-401, `Viewer/` | Só precisa que a URL do WebSocket chegue ao host (via forward). |
| Ferramentas MCP do agente rodam no app (`app.sock`), que faz exec no container | `ComputerToolService*` | **O CLI do agente continua no Mac** (modo leve). Só o "computador" vai para a nuvem. O modo isolado (CLI dentro do container, v1.1) levaria credenciais do Claude/Codex para a nuvem; recomendo **não** fazer isso no BK-12. |

---

## 2. Provedores analisados

Convenção do veredito: **Serve como está** (container atual sem mudar), **Serve com redesenho** (exige mudar P24 ou o firewall), **Não serve para o computador completo**. Preços para ~2 vCPU/4 GB, em US$/hora, **sem** tráfego e IP. "(3ª)" = fonte de terceiros, conferir antes de usar.

### 2.1 Visão geral

| Provedor | Veredito | `NET_ADMIN`/iptables | Preço 2 vCPU/4 GB | Arm64 | Alcance pelo Mac | Partida estimada* | Região no Brasil |
|---|---|---|---|---|---|---|---|
| **AWS EC2 + Docker** | **Serve como está** | Sim (VM comum; qualquer capacidade) | `t4g.medium` US$ 0,0336 (3ª); `c7g.large` US$ 0,0725 (3ª) | Sim (Graviton) | SSH / Instance Connect / SSM / mTLS | 40 a 90 s com AMI pronta; 2 a 4 min instalando; 2 a 5 s para um computador novo num host já ligado | sa-east-1 (São Paulo) |
| AWS ECS em EC2 | Serve, mas sem ganho | Sim (modo EC2 aceita capacidades) | Igual ao EC2 | Sim | ECS Exec (SSM) | Igual ao EC2 | sa-east-1 |
| **AWS ECS Fargate** | **Não serve sem redesenho** | **Não**: só `SYS_PTRACE` pode ser adicionado | x86 ≈ US$ 0,099; ARM ≈ US$ 0,079 (calculado) | Sim | ECS Exec (não há API Docker) | ~30 a 60 s | sa-east-1 |
| AWS Lightsail | Serve, mas inferior ao EC2 | Sim (VM) | US$ 24/mês (≈ US$ 0,033/h, teto mensal) | x86 | Chave SSH | ~1 min | sa-east-1 (metade da franquia de tráfego) |
| **Cloudflare Containers** | **Não confirmado; exige gateway em Worker** | Não documentado | Memória provisionada + CPU só quando ativa; `standard-3` (2 vCPU, 8 GiB) ≈ US$ 0,07 a 0,22 | **Só amd64** (relato de beta; conferir) | Só via Worker/Durable Object (HTTP/WebSocket); sem TCP cru; sem API de exec documentada | 1 a 3 s (documentação) | Mais próximo do usuário |
| Cloudflare Browser Rendering | **Não replica o computador** | n/a | US$ 0,09/h após 10 h/mês | n/a | CDP/Playwright | rápido | borda |
| Cloudflare Workers | Não roda container nem Chromium próprio | n/a | n/a | n/a | n/a | n/a | n/a |
| **Fly.io Machines** | **Provavelmente serve** (VM Firecracker, root) | Provável; a equipe da Fly disse em 2021 que a VM tem os privilégios dentro do próprio kernel (fórum); **exige spike** | `shared-cpu-2x` 4 GB US$ 0,0353 (iad); ×1,62 em `gru` ≈ US$ 0,057; `performance-2x` 4 GB US$ 0,0917 | Não confirmado | Fly proxy / WireGuard (6PN); IP público compartilhado | ~1 a 5 s (marketing da Fly; medir) | `gru` (São Paulo) |
| Google Cloud Run | **Não serve** | Não: "não é possível adicionar nem remover capacidades"; sem privileged | n/a | n/a | HTTP | n/a | southamerica-east1 |
| Google Compute Engine | Serve como está (VM) | Sim | não verificado (~ `e2-medium`) | Sim (Axion/T2A) | SSH/IAP | ~1 min | southamerica-east1 |
| **Hetzner Cloud** | Serve como está (VM) | Sim | CX23: €0,0088/h (US$ 0,0104); CAX11: €0,0096/h (US$ 0,0112), **só Alemanha/Finlândia** | Sim (CAX) | SSH | ~30 a 60 s | Nenhuma; nos EUA só as linhas CPX/CCX (mais caras) |
| DigitalOcean Droplet | Serve como está (VM) | Sim | US$ 0,03571/h (4 TB incluídos) | Não (x86) | SSH | ~1 min | Nenhuma na lista oficial |
| E2B | Serve com ressalvas | Não verificado | ≈ US$ 0,17/h (sandbox padrão) + plano | Não verificado | SDK próprio (exec, portas) | rápido (não medido) | não informado |
| Daytona | Serve com ressalvas | Não verificado | ≈ US$ 0,166/h (calculado) | Não verificado | SDK próprio | não medido | não informado |
| Modal Sandboxes | Serve com ressalvas | Não verificado (sandbox tipo gVisor) | ≈ US$ 0,24/h (calculado) | Não verificado | SDK Python/JS | não medido | região com sobretaxa de 1,15 a 1,75× |
| Browserbase / Steel | **Não replicam o computador** | n/a (só o browser) | Browserbase US$ 0,12/h excedente; Steel US$ 0,10 a 0,08/h | n/a | CDP / API | rápido | n/a |

\* Partida: onde há número citado, a fonte está na lista; os demais valores são **estimativas minhas, a medir no spike**.

### 2.2 Detalhe por provedor

**AWS EC2 com Docker (recomendado).** É uma VM Linux inteira; Docker, capacidades, tmpfs, `/dev/shm`, iptables funcionam como no Mac. `t4g.medium` (2 vCPU, 4 GiB, Graviton2) custa US$ 0,0336/h sob demanda e US$ 0,016/h em Spot ([Vantage, 3ª](https://instances.vantage.sh/aws/ec2/t4g.medium)). Atenção: a família `t` é "burstável" (CPU com créditos); um Chromium sob carga contínua esgota os créditos e passa a cobrar US$ 0,04 por vCPU-hora de créditos ilimitados ([AWS](https://aws.amazon.com/ec2/pricing/on-demand/)). Para carga contínua, `c7g.large` (2 vCPU, 4 GiB) custa US$ 0,0725/h ([Vantage, 3ª](https://instances.vantage.sh/aws/ec2/c7g.large)). IPv4 público custa US$ 0,005/h por endereço desde 01/02/2024 ([AWS Blog](https://aws.amazon.com/blogs/aws/new-aws-public-ipv4-address-charge-public-ip-insights)). Acesso sem abrir porta: Session Manager faz port forwarding sem porta de entrada, exige SSM Agent e o plugin local ([docs AWS](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)); EC2 Instance Connect empurra uma chave pública temporária (60 s) por API IAM ([docs AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html)).
Cotas: contas novas podem ter limite baixo de vCPUs (Service Quotas); **verificar** no spike, não consegui confirmar um número oficial.

**AWS ECS Fargate (não serve).** Segundo a documentação de definição de tarefa, no Fargate o campo `capabilities.add` aceita **somente `SYS_PTRACE`**, e `sharedMemorySize` não é suportado ([ECS task definition parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)). O guia de segurança afirma que `CAP_SYS_ADMIN` e `CAP_NET_ADMIN` são restritas e que containers privilegiados não existem no Fargate ([Fargate security considerations](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-security-considerations.md)). O nosso supervisor **recusa subir sem iptables** (`firewall.py`: "iptables ausente; recusando subir"), então o container morreria no start. Além disso não há Docker Engine API: o acesso seria por ECS Exec, ou seja, um backend novo inteiro.
Preço (calculado a partir das tarifas US East): x86 US$ 0,04048/vCPU-h e US$ 0,004445/GB-h, ARM US$ 0,03238 e US$ 0,00356 ([AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/)). Um redesenho possível (mas fora do MVP): dividir em duas tarefas (navegador e proxy) e impor a saída por **security group** em vez de iptables. Isso desfaz o P24 (um container), dobra custo e complexidade e perde o `exec` Docker.

**AWS ECS em EC2.** Aceita capacidades e privileged, mas acrescenta cluster, capacity provider e agente ECS sem trazer nada que um Docker puro em EC2 já não dê. Descartado para o MVP.

**AWS Lightsail.** Pacote de 2 vCPU/4 GB a US$ 24/mês (4 TB de tráfego), US$ 20 só-IPv6; em São Paulo a franquia de tráfego é metade ([Lightsail pricing](https://aws.amazon.com/lightsail/pricing/)). Funciona como VM, mas a API de rede/tags/IAM é mais pobre que a do EC2 e dificulta o IAM mínimo e a limpeza por tag. Sem vantagem.

**Cloudflare Containers.** Cada instância roda numa microVM Firecracker com kernel próprio; cold start "frequentemente 1 a 3 s"; construir para `linux/amd64`; disco efêmero; `sleepAfter` padrão de 10 min; **o usuário final não faz TCP/UDP cru** e **não há API de exec documentada** ([arquitetura](https://developers.cloudflare.com/containers/platform-details/architecture/)). Tipos: de `lite` (1/16 vCPU) até `standard-4` (4 vCPU, 12 GiB); um tipo customizado precisa de ao menos 3 GiB por vCPU ([limites](https://developers.cloudflare.com/containers/platform-details/limits/)). Preço: memória e disco pelo provisionado, CPU só pelo uso ativo, com 25 GiB-h, 375 vCPU-min e 200 GB-h inclusos no plano Workers Paid (US$ 5/mês); excedente US$ 0,0000025/GiB-s, US$ 0,00002/vCPU-s; saída US$ 0,025/GB (América do Norte e Europa), US$ 0,04 nas demais regiões ([preços](https://developers.cloudflare.com/containers/pricing/)). Cada container usa também um Durable Object e um Worker, cobrados à parte.
Problemas para nós: (1) **não confirmei** se root/`NET_ADMIN` funcionam (a documentação consultada não trata); (2) sem exec e sem TCP, o app precisaria de um **Worker gateway escrito por nós** (código JS/TS novo, fora do stack Swift) que traduza HTTP/WebSocket para dentro do container e substitua o `docker exec`; (3) amd64 apenas (relato de beta de 2025 em [devclass](https://devclass.com/2025/07/01/cloudflare-container-platform-in-public-preview-with-scale-to-zero-pricing-some-initial-limitations/); **conferir se continua valendo**); (4) o egress seria da rede Cloudflare, cujos IPs não são os do usuário. Resultado: **experimento interessante para v3**, não para o início.

**Cloudflare Browser Rendering e Workers.** Browser Rendering dá Chromium gerenciado por CDP/Puppeteer/Playwright: 10 h/mês incluídas, depois US$ 0,09/h; 10 navegadores concorrentes no plano pago, US$ 2 por navegador extra ([preços](https://developers.cloudflare.com/browser-rendering/pricing/)). Não tem shell, não tem Xvfb/VNC para "Take Over", não tem nosso proxy com reqlog de corpos. Serve, no máximo, como um modo "só browser" no futuro. Workers não rodam container nem Chromium próprio; só servem de gateway.
O melhor papel da Cloudflare no BK-12 é **rede**: um túnel de saída (`cloudflared`) a partir da VM evita abrir porta de entrada. Não analisei a documentação do Cloudflare Tunnel/Access nesta pesquisa; tratar como hipótese a verificar na v2.

**Fly.io Machines.** VMs Firecracker criadas de imagem Docker; API REST própria com `guest.cpu_kind/cpus/memory_mb`, `metadata`, `auto_destroy`, política de restart ([API](https://docs.fly.io/machines/api/machines-resource)). A página de API consultada não lista endpoint de exec nem capacidades. No fórum, em 16/04/2021, a Fly disse que a VM deveria ter os privilégios necessários como root no próprio kernel e reconstruiu o kernel com a tabela `raw` do iptables ([fórum Fly](https://community.fly.io/t/runtime-linux-capabilities-running-dsvpn-as-a-fly-app/1183)). **Isso é indício, não prova**: o spike precisa rodar o `firewall.py` real. Preços: `shared-cpu-2x` 4 GB em Ashburn ≈ US$ 25,40/mês (≈ US$ 0,0353/h); `performance-2x` 4 GB US$ 66/mês (≈ US$ 0,0917/h); em `gru` o multiplicador é ~1,62 (cálculo meu); rootfs de máquina parada US$ 0,15/GB-mês; saída US$ 0,02/GB (América do Norte e Europa), US$ 0,04/GB (América do Sul); IPv4 dedicado US$ 2/mês; IP de saída estático US$ 0,005/h ([preços Fly](https://docs.fly.io/about/pricing)). CPU "shared" é estrangulada sob carga; o Chromium headed prefere `performance`. Vantagem: faturamento por segundo, máquinas que dormem, região em São Paulo. Desvantagem: sem Docker Engine API; o backend seria o "Machines API + exec", ou seja, trabalho de integração parecido com um provedor novo (e possivelmente só x86).

**Google Cloud Run (não serve).** "Containers não podem adicionar nem remover capacidades Linux, e o modo privilegiado não está disponível"; o sistema de arquivos é em memória; há limite de timeout de requisição ([container contract](https://docs.cloud.google.com/run/docs/container-contract)). Mesmo problema do Fargate. **GCE** é uma VM e se comporta como EC2 (serve), com login OAuth muito amigável, mas não verifiquei preços; candidato a v3.

**Hetzner Cloud.** O mais barato. Em 2026 houve dois reajustes (01/04/2026 e 15/06/2026). Na página oficial atual: CAX11 (Arm) €5,99/mês, €0,0096/h; CX23 €5,49/mês, €0,0088/h, **listados só para Alemanha e Finlândia**; para EUA e Singapura a página não lista CX/CAX ([Hetzner, atualizado em 08/07/2026](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)). Não confirmei que CAX11/CX23 sejam exatamente 2 vCPU/4 GB; conferir. Latência do Brasil para a Europa tende a ser alta (não medi). Vantagem de UX: **um único token de API** colado pelo usuário. Desvantagem: faixas de IP muito usadas e frequentemente sinalizadas (impressão geral do setor, não medida aqui).

**DigitalOcean.** Droplet 2 vCPU/4 GiB: US$ 24/mês ou US$ 0,03571/h, 4.000 GiB de saída incluídos; regiões listadas: SF, Richmond, NYC, Kansas City, Atlanta, Toronto, Amsterdam, Londres, Frankfurt, Bangalore, Singapura, Sydney ([DO pricing](https://www.digitalocean.com/pricing/droplets)); **nenhuma na América do Sul**. Serve como VM, só sem vantagem sobre EC2 para nós.

**Sandboxes especializados (E2B, Daytona, Modal).** Vendem exatamente "um computador descartável por API".
- E2B: US$ 0,000014/vCPU-s e US$ 0,0000045/GiB-s; sandbox de 2 vCPU/4 GiB ≈ US$ 0,17/h. Hobby: 20 concorrentes e **1 h de sessão máxima**; Pro: US$ 150/mês, 100 concorrentes, 24 h ([E2B pricing](https://e2b.dev/pricing)).
- Daytona: US$ 0,0504/vCPU-h, US$ 0,0162/GiB-h (≈ US$ 0,166/h para 2/4); US$ 200 de crédito grátis ([Daytona pricing](https://www.daytona.io/pricing)).
- Modal: US$ 0,00003942 por núcleo-físico-s (1 núcleo = 2 vCPU) e US$ 0,00000667/GiB-s (≈ US$ 0,24/h para 2 vCPU/4 GiB, cálculo meu); US$ 30 de crédito/mês no Starter ([Modal pricing](https://modal.com/pricing)).
Custam **4 a 7 vezes** uma VM, travam o produto num SDK de terceiro, e eu **não consegui confirmar** root/`NET_ADMIN`, arm64 nem port forwarding de VNC. Úteis como "provedor premium com partida rápida" depois que existir uma interface de provedor; não como base.

**Browserbase / Steel.** São navegadores como serviço. Browserbase: Developer US$ 20/mês, 100 h incluídas, US$ 0,12/h excedente, proxies US$ 12/GB ([pricing](https://www.browserbase.com/pricing)). Steel: Scale US$ 250/mês, US$ 0,08/h, proxy US$ 6/GB; Launch tem sessão máxima de 15 min ([pricing](https://steel.dev/pricing)). Sem shell, sem nosso egress/reqlog, sem Take Over equivalente garantido. Não replicam o computador.

---

## 3. Arquiteturas possíveis

### 3.1 As três opções

**(a) App fala direto com cada caixa, por endpoint próprio autenticado (TLS/mTLS ou token).**
Cada computador (ou cada VM) expõe um endpoint HTTPS/WebSocket público. O app usaria a admin API (`:8790`, que já faz proxy do runtime e do VNC) e precisaria de **um substituto para o `docker exec`** (hoje feito pelo Engine API).
- Complexidade: alta. Exec, upload de segredos, logs, eventos e o ciclo de vida inteiro precisariam virar uma API nova no admin, escrita em Python no container, com todo o código de exec do lado do app a reescrever.
- Segurança: a superfície pública é a admin API inteira; qualquer bug é remoto.
- Reuso de código: baixo (~30%).
- Viewer: bom (TLS direto, sem camadas).

**(b) VM anfitriã ("Racky Host") com Docker, acessada pelo Engine API por túnel.**
Uma VM por conta/projeto roda Docker e hospeda vários computadores (como a "VM Docker" local). O app usa o **mesmo `DockerClient`**, apontado para o socket remoto através de um túnel SSH autenticado; as portas de admin são encaminhadas pelo mesmo túnel.
- Complexidade: média. Falta o transporte remoto, o provisionamento da VM, o tratamento das pastas que hoje são binds do Mac e o "reaper".
- Segurança: boa. **Nenhuma porta de aplicação é pública.** A única porta de entrada é o SSH (chave efêmera, restrito ao IP do usuário), ou nenhuma se usar SSM.
- Reuso: **alto (70% a 80%)**: `DockerClient`, `ContainerSpec`, `EventMonitor`, `GarbageCollector`, `Capacity`, `EgressAdminClient`, MCP, viewer.
- Custo: o mais barato por computador (vários por VM, partida em segundos num host ligado).
- Viewer/Take Over: VNC dentro de WebSocket dentro de SSH; funciona, mas é TCP sobre TCP (sob perda de pacotes, atraso soma). Aceitável.

**(c) Sandboxes nativos do provedor (E2B, Daytona, Modal, Cloudflare Containers, Fly Machines).**
Cada computador é um recurso do provedor, criado por API própria.
- Complexidade: alta por provedor (um backend por SDK), mas cada um é pequeno.
- Segurança: o isolamento é do provedor; a autenticação é um token dele.
- Reuso: baixo (~20% a 40%); o Docker Engine API não existe.
- Custo: 4 a 7× (sandboxes) ou competitivo (Fly).
- Risco: mudança de preço/limite do fornecedor; amarração.

### 3.2 Comparação

| Critério | (a) Direto por endpoint | **(b) Host Docker + túnel** | (c) Sandboxes do provedor |
|---|---|---|---|
| Complexidade (1 baixa a 5 alta) | 5 | **3** | 4 (por provedor) |
| Segurança (superfície exposta) | Ruim: API pública | **Boa: nada público além do túnel** | Média: depende do provedor |
| Custo por computador-hora | médio | **menor** | maior |
| Latência do viewer | menor (sem túnel) | um pouco maior (SSH) | varia |
| Reuso do código atual | ~30% | **~70-80%** | ~20-40% |
| Mantém o container P24 intacto | só se houver exec novo | **sim** | depende |
| Provedores que cabem | qualquer VM | **EC2, GCE, Hetzner, DO, Lightsail** | Fly, E2B, Daytona, Modal, CF |

**Recomendação de arquitetura: (b) como base**, com uma **interface de provedor** (`CloudProvider`) que só sabe "criar host, descobrir endereço, destruir host, listar por tag, estimar preço". Depois, (c) entra como segundo tipo de provedor sem tocar no resto.

### 3.3 Detalhe de (b): um host por computador ou um host para vários?

| Modelo | Vantagem | Desvantagem |
|---|---|---|
| **B1: uma VM por computador** | Limpeza trivial (derrubar a VM mata tudo); isolamento máximo; mapeia 1:1 com o que o usuário "vê" | Partida lenta (40 a 90 s mínimo); custo por computador maior; 15 VMs = 15 IPv4 (US$ 0,075/h só de IP); cota de vCPU da conta |
| **B2: um host compartilhado por vários computadores** | Partida em segundos; custo/computador menor; igual ao modelo local (o spec já dimensiona 15+2 numa VM de ~28 GiB) | Falha do host derruba todos; isolamento entre computadores é só o do Docker (mesmo que hoje no Mac) |

Exemplo de custo B2: 15 headless + 2 desktop pedem 22,4 GiB (07 §2.4). Uma `c7g.4xlarge` (16 vCPU, 32 GiB) custa 8× a `c7g.large`, ou ~US$ 0,58/h (AWS cobra linear dentro da família; 3ª fonte do preço base). Dá ~US$ 0,034 por computador-hora; em B1 seriam 15 × US$ 0,0725 ≈ US$ 1,09/h. **Atenção:** 16 vCPU para 19 vCPUs de pedido (15×1 + 2×2) é justo; o spec já aceita CPU sobrecarregada (CS-134), mas é preciso medir.

**Recomendo B2 com host elástico:** liga sob demanda no primeiro computador, desliga sozinho depois de N minutos sem computadores (§6). Para o usuário, o host é invisível ("Cloud · AWS · us-east-1 · 3 computers").

---

## 4. Como o app alcança a nuvem (rede e transporte)

### 4.1 Os três caminhos de acesso ao host

| Caminho | Como funciona | Prós | Contras |
|---|---|---|---|
| **SSH direto** com chave efêmera por host | O app gera um par ed25519 por host, injeta a pública via `user-data` ou Instance Connect, abre `ssh -L` para o socket do Docker e para as portas de admin | Simples; `ssh` já existe no macOS; reaproveita UDS; o socket remoto vira um UDS local | Porta 22 aberta ao IP do usuário (troca de IP quebra); precisa fixar a chave do servidor (host key) para evitar MITM; gerenciar um processo `ssh` filho |
| **AWS Session Manager** (SSM) | Túnel por API da AWS, sem nenhuma porta de entrada | Zero portas públicas; autenticação por IAM; sem gerir chaves | Exige o `session-manager-plugin` no Mac (empacotar ou instalar); o log de sessão fica **indisponível** para port forwarding e SSH sobre SSM ([docs AWS](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)); mais um binário |
| **mTLS direto** num mini-daemon na VM | Um "racky-hostd" na porta 443 aceita só clientes com certificado emitido pelo app, e encaminha ao Docker | Sem plugin, sem SSH; latência menor | Código novo (daemon + transporte TLS com certificado de cliente no app); superfície pública mínima, porém existente |

Docker também oferece TLS com certificados de cliente na porta 2376, mas avisa que quem tem a chave de cliente tem **root no host** ([docs Docker](https://docs.docker.com/engine/security/protect-access/)). Expor 2376 à internet, mesmo com mTLS, é desnecessário se houver SSH/SSM.

**Decisão sugerida:** MVP com **SSH** (menor esforço, reaproveita o socket) restrito ao IP de origem do usuário e com chave de host verificada; v1.1 com **SSM ou Instance Connect** para que a VM não tenha **nenhuma** porta de entrada aberta. mTLS fica como alternativa se o plugin do SSM virar problema.

### 4.2 O que passa pelo túnel

1. **Engine API** (socket do Docker): `ssh -L /caminho/local.sock:/var/run/docker.sock` (a forma documentada pela comunidade para encaminhar socket Unix por SSH; ver [exemplo](https://www.shore.co.il/blog/docker_socket_over_ssh/), exemplos antigos, testar com o OpenSSH do macOS). O `DockerTransport` atual (só UDS) funciona sem mudar. **O exec com conexão sequestrada precisa passar intacto**; isso é um item do spike.
2. **Admin de cada computador** (`127.0.0.1:<porta efêmera>` na VM): um `-L` extra por computador, ou um único forward para um mini-roteador na VM. O `EgressAdminClient` hoje usa `http://127.0.0.1:<porta>`, então basta o app alocar uma porta local por computador. O ticket de VNC e o token continuam valendo.
3. **VNC no viewer**: o WKWebView fala com `ws://127.0.0.1:<porta local>/vnc?ticket=…` e o túnel leva ao admin remoto. Nenhuma mudança no noVNC.

### 4.3 Dimensionamento e escolha de região (do ponto de vista do dono, no Brasil)

- **Latência**: o AWS inter-região entre sa-east-1 e us-east-1 aparece como ~115 ms ([Economize](https://www.economize.cloud/resources/aws/latency/sa-east-1-vs-us-east-1/), terceiro, sem dizer se é ida ou volta); dentro de sa-east-1 ~2,5 ms. Medição própria no spike (um `ping`/`curl` simples) vale mais que essa referência. Regra prática: **100 a 150 ms de ida e volta** no viewer de us-east-1 tornam o mouse e o teclado do "Take Over" perceptivelmente atrasados, mas utilizáveis para cliques e digitação curta; em sa-east-1 fica comparável a uso local.
- **Mas o que importa para o trabalho é a latência entre o computador e o site-alvo**, e os alvos do dono (portais de permissão dos EUA: Accela, ArcGIS) ficam nos EUA. Rodar em us-east-1 acelera as páginas e o agente; rodar em sa-east-1 acelera só o seu olhar. Além disso, **portais públicos americanos podem bloquear IP brasileiro** (prática comum, não medida aqui; testar).
- **Sugestão:** padrão **us-east-1** para o trabalho do agente, com **sa-east-1** como opção para quem usa o Take Over muito. A tela de escolha explica a troca em uma linha.
- **Preço varia por região**: sa-east-1 tende a ser bem mais caro que us-east-1 (não verifiquei a tarifa; **mostrar o preço da região escolhida na UI**, §6.5).

### 4.4 O que muda em dados e arquivos (lacunas reais no código)

| Hoje (Mac) | Na nuvem | Esforço |
|---|---|---|
| `work/` é um bind do Mac em `/work`, e os resultados do agente ficam na pasta do run | A pasta fica na VM; o app precisa **trazer os arquivos de volta** (`GET /containers/{id}/archive` do Engine API ou exec + tar) e no encerramento | médio |
| `logs/` (reqlog, diário) é bind do run no host | O reqlog fica na VM (tmpfs ou disco cifrado); o app lê pela admin API (`/v1/reqlog…`) e grava no Mac | médio |
| Segredos de tarefa em `/run/abx-secrets:ro` por bind | Não há pasta do Mac na VM. Enviar por exec com stdin para um **tmpfs** do container (nunca escrever em disco da VM, nunca por env) | médio |
| Volume de perfil do Chromium (`ab-prof-…`) | Vive no disco da VM; perfis nomeados persistentes só fazem sentido com host persistente | baixo/médio |
| Imagem por digest do GHCR | A VM puxa a imagem pública por digest (alguns GB; entrada é gratuita na AWS) ou usa AMI com a imagem pré-carregada; sem segredos na imagem (já é regra do projeto) | baixo |
| `RuntimeDetector`, contexto Docker local | Novo tipo de "runtime remoto" com ciclo próprio | médio |

---

## 5. Credenciais e segurança

### 5.1 Onde ficam as credenciais da nuvem

- **No Mac, no Vault do app / Keychain** (já existem `Packages/AgentBoxKit/Sources/AgentBoxPlatform/Vault`), nunca em arquivo de texto, nunca em log, nunca enviadas ao agente nem ao container. As credenciais do **host** (chave SSH efêmera) existem só enquanto o host existir.
- **O container na nuvem não recebe nenhuma credencial da nuvem.** O agente não deve poder chamar a API da AWS. A VM não tem papel IAM (ou tem um papel mínimo só para autodestruição, §6.3).

### 5.2 Como o usuário "conecta a AWS" com atrito baixo

| Método | Experiência | Segurança | Observação |
|---|---|---|---|
| **Colar chaves de acesso de um usuário IAM dedicado** com a política mínima fornecida pelo app | 3 passos manuais no console AWS | Chave de longa duração (risco se vazar) | Funciona hoje; o app oferece um botão "Copy policy" e um template de CloudFormation. |
| **Perfil local do AWS CLI** (`~/.aws`) | Zero atrito se já usa | Herda permissões amplas do perfil do usuário | Útil, mas o usuário pode estar com administrador; avisar. |
| **`aws login`** (credenciais de console, anunciadas em 19/11/2025): credenciais temporárias de 15 min, renovadas por até 12 h, sem criar chave ([anúncio](https://aws.amazon.com/about-aws/whats-new/2025/11/console-credentials-aws-cli-sdk-authentication/)) | "Login pelo navegador" real | Curta duração | Exige o AWS CLI v2.32 ou superior instalado; o app teria de chamar o CLI ou implementar o fluxo. Mais amigável, mas a permissão ainda é a do usuário que fez login. |
| IAM Identity Center (SSO) com fluxo de dispositivo | Login amigável em conta com SSO | Curta duração, papéis por conjunto de permissões | Exige que a conta tenha Identity Center configurado (pouco comum em contas pessoais); não pesquisei a fundo. |

**Papel (role) com `AssumeRole`:** não é viável como primeira escolha, porque o Racky é um app local sem conta AWS própria que seja a "parte confiável"; seria preciso um backend nosso. Evitar.

**Recomendação:** MVP com **chaves de um usuário IAM dedicado e de permissão mínima** (guiado pela UI) ou perfil local; v1.1 com **`aws login`/SSO** para credenciais temporárias. Em todos os casos, **nunca pedir nem aceitar a chave raiz** (a UI detecta e recusa).

### 5.3 Política IAM de privilégio mínimo (esboço)

Ações: `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:DescribeInstances`, `ec2:CreateTags`, `ec2:CreateSecurityGroup`/`AuthorizeSecurityGroupIngress`/`RevokeSecurityGroupIngress`/`DeleteSecurityGroup`, `ec2:DescribeImages`/`DescribeSubnets`/`DescribeVpcs`, `ec2-instance-connect:SendSSHPublicKey` (opcional), `pricing:GetProducts` e `ce:GetCostAndUsage` (leitura de custo). Condições:
- `aws:RequestedRegion` restringe às regiões escolhidas pelo usuário.
- `ec2:InstanceType` restringe aos tipos que o app usa (impede subir instâncias enormes se a chave vazar).
- `ec2:ResourceTag/racky:owner = <installId>` para `Terminate`/`Describe` só sobre o que o Racky criou (nunca derruba instâncias que não são dele).
- `aws:RequestTag/racky:owner` obrigatório no `RunInstances` (tudo nasce etiquetado).

**Limite honesto:** o IAM **não consegue impor "no máximo N instâncias"**. Esse teto é aplicado pelo app (e, de forma dura, pela cota de serviço da conta). A política só limita **tipo, região e dono**.

### 5.4 Dados em trânsito e em repouso

- **Em trânsito:** tudo passa por SSH (ou SSM, ou mTLS). Nenhum VNC, admin ou socket Docker em texto claro na internet.
- **Em repouso:** o reqlog guarda **corpos de requisição e resposta**, que podem conter cookies, tokens e dados pessoais. Na VM: volume EBS **cifrado** (padrão habilitável), reqlog em tmpfs sempre que possível, cópia para o Mac e **apagamento seguro** na destruição do computador. O volume de perfil do Chromium contém sessões logadas; vale a mesma regra. O spec já declara que o perfil não é cifrado na v1 (CS-176); na nuvem isso passa a ser **mais grave**, então o EBS cifrado vira obrigatório.
- **Segredos:** só em tmpfs do container (como hoje), enviados por exec/stdin pelo túnel; nunca em `user-data` (o `user-data` fica legível pela API da AWS e pelo serviço de metadados).
- **Metadados da instância:** exigir **IMDSv2** e `HttpPutResponseHopLimit=1`; o iptables do container já recusa `169.254.169.254` para o agente. Isso fecha o roubo de credenciais da VM.

### 5.5 Isolamento entre computadores

No host compartilhado (B2) o isolamento entre computadores é o do Docker, **o mesmo nível de hoje no Mac**; o socket Docker nunca é montado em container. Computadores de **donos diferentes** nunca dividem host: o host pertence a **um** usuário/instalação (`racky:owner`). Fica fora de escopo qualquer cenário multi-inquilino do nosso lado.

### 5.6 Abuso e exposição legal

O IP de saída passa a ser **um IP de datacenter da conta do usuário**. Scraping agressivo, tentativa de burlar bloqueios ou acesso não autorizado pode gerar queixas de abuso, **suspensão da conta AWS** e exposição contratual e legal para o usuário. O código de uso aceitável de cada provedor vale (não revisei o AUP da AWS nesta pesquisa; tratar como pendência). Mitigações no produto: aviso claro no primeiro uso, "limite de requisições por minuto por computador" opcional no proxy, e **os logs completos continuarem existindo** (já existem) para o usuário se defender. O Racky não deve sugerir contorno de bloqueio.

---

## 6. Custo e risco de "instância órfã"

Este é o risco que mais pode causar dano real: **uma VM esquecida cobra enquanto existir**. Exemplos de pior caso: 1 `c7g.4xlarge` esquecida = US$ 0,58/h = **~US$ 418 por mês**; cinco `c7g.large` = US$ 0,36/h = ~US$ 261/mês; uma instância parada ainda cobra EBS e IPv4 elástico.

### 6.1 Camadas de proteção (todas juntas, nenhuma sozinha)

| Camada | O que faz | Funciona com o app fechado/Mac desligado? |
|---|---|---|
| **1. Chave morta (dead-man switch) na VM** | Serviço `systemd` na VM: se o app não renovar um "lease" (curta duração, ex.: 20 min) por uma chamada simples, a VM faz `shutdown -h now`. Com `InstanceInitiatedShutdownBehavior=terminate`, desligar **apaga** a instância. Não precisa de papel IAM | **Sim, é a proteção principal** |
| **2. Vida máxima dura** | Tag `racky:expires_at` e o mesmo serviço desliga a VM no teto (padrão sugerido: 8 h, ajustável, com aviso antes) | Sim |
| **3. Desligar sozinha quando vazia** | O host sem computadores por N minutos (padrão 10) se encerra | Sim |
| **4. Tags em tudo** | `racky:owner=<installId>`, `racky:host`, `racky:created`, `racky:expires_at`; custo e limpeza por tag | n/a |
| **5. Reaper no app** | Ao abrir (e a cada N minutos), lista por tag em **cada região habilitada** e mostra "N instâncias suas, X horas, ~US$ Y" com botão "Encerrar"; reconcilia host sem lease | Só com o app aberto |
| **6. Teto de quantidade no app** | "Máximo 5 computadores na AWS" e "máximo 2 hosts": o scheduler existente (`ComputerScheduler`, fila) recusa ou enfileira além do teto | Só com o app aberto; o teto duro é a **cota de vCPU** da conta |
| **7. Teto de tipo e região** | IAM com `aws:RequestedRegion` e `ec2:InstanceType` (§5.3) | Sim |
| **8. AWS Budgets** | O app cria um orçamento mensal com alerta por e-mail/SNS, e opcionalmente uma **ação** que aplica uma política IAM de negação ou aponta instâncias EC2 ([docs](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-controls.html)). **Atraso:** os dados do Budgets atualizam até 3 vezes por dia, com 8 a 12 h entre atualizações ([docs](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)); o gasto já terá ocorrido | Sim, mas **tardio**: é uma rede de segurança, não um freio |
| **9. Custo visível antes e durante** | Antes de iniciar: "≈ US$ 0,034/h + IPv4 US$ 0,005/h + tráfego". Durante: contador por host na barra de status ("Cloud hoje US$ 1,87"); depois: reconciliação com Cost Explorer (atrasada) | Parcial |

A camada 1 resolve o caso "o Mac desligou, o app travou, o usuário viajou". Ela é pequena (um script na VM) e deve ser **a primeira coisa construída e testada**, antes de qualquer UI.

### 6.2 Auto-encerramento ao fechar o app / crash

- **Fechamento normal:** o app destrói os computadores da sessão e, se não restar nenhum, pede o término do host. Se o usuário escolher "manter rodando", a UI **declara o custo por hora** e o lease passa a ter prazo explícito.
- **Crash ou Mac dormindo:** o lease expira; a VM se apaga sozinha (camada 1).
- **Quit com "Stop All and Quit…" (P25):** encerra também os hosts de nuvem (confirmação mostrando o custo).

### 6.3 Papel IAM mínimo na VM (opcional)

O desligamento por `shutdown` dispensa papel IAM. Se quisermos terminar também o volume e liberar o IP por API, um papel de instância com só `ec2:TerminateInstances` condicionado à própria tag basta. Preferir **sem papel**, e deixar a limpeza residual para o reaper.

### 6.4 Custos ocultos a mostrar

IPv4 público (US$ 0,005/h por IP, ~US$ 3,60/mês); EBS (volumes soltos continuam cobrando após terminar a instância se `DeleteOnTermination` não estiver ligado: **forçar ligado**); tráfego de saída (a AWS dá 100 GB/mês grátis agregados; acima disso há tarifa por GB, **que não consegui capturar da página oficial**, conferir); transferência entre regiões; NAT Gateway (**nunca criar**: cobra por hora e por GB).

### 6.5 Estimativa mostrada ao usuário

Ao escolher região e tamanho, o app mostra um preço por hora. Fonte: tabela embutida e atualizada por versão do app (rápida, offline) com checagem opcional via `pricing:GetProducts` (a API de preços da AWS). **Rotular sempre como estimativa** e nunca como garantia.

---

## 7. Realidades de rede

### 7.1 Reputação de IP

IPs de datacenter chegam com pontuação de risco alta nas camadas antibot; a documentação de fornecedores de proxy afirma que os blocos dos grandes provedores são conhecidos e bloqueados com frequência ([Massive](https://www.joinmassive.com/blog/why-ai-agents-get-blocked-on-datacenter-ips-and-how-to-fix-it)). **Atenção:** essa fonte tem interesse comercial em proxies residenciais; a conclusão é direcional, não uma medição. O IP é só uma camada; o antibot também olha impressão digital TLS/HTTP2, JavaScript e comportamento.
Consequência para o produto: **o proxy upstream (Zyte, residencial) continua necessário** para alvos protegidos; a nuvem não substitui isso, e rodar na AWS **piora** a taxa de bloqueio em relação ao Mac residencial do dono. Vale mostrar essa expectativa na UI ("Cloud computers use datacenter IPs; some sites will block them. Use a proxy.").

### 7.2 Custos de tráfego

- Saída para a internet da VM (páginas, downloads do agente) e saída do **viewer** (VNC) e dos **logs** para o Mac, tudo conta como saída. Tarifas: AWS tem 100 GB/mês grátis, depois tarifa por GB (capturar o valor exato na página de preços); Fly cobra US$ 0,02/GB (América do Norte e Europa) e US$ 0,04/GB (América do Sul); Cloudflare Containers US$ 0,025 a US$ 0,04/GB; DigitalOcean inclui 4.000 GiB no droplet de 2 vCPU/4 GiB.
- **Banda do VNC (estimativa minha, medir):** de ~0,2 Mbit/s com tela quase parada a alguns Mbit/s quando há vídeo ou rolagem intensa. Uma hora a ~1 Mbit/s são ~450 MB, ou seja, centavos por hora de viewer aberto. O app já limita viewer ao vivo a 2 por padrão (CS-133).

### 7.3 Latência do Take Over a partir do Brasil

Ver §4.3. Resumo: us-east-1 é bom para o trabalho do agente e **tolerável** para clique e digitação ocasional; sa-east-1 é melhor para o olhar, mas mais caro e com IP brasileiro (que alguns portais americanos recusam). A decisão deve ser do usuário, com os dois custos visíveis.

---

## 8. Matriz de riscos

Escala: probabilidade e impacto em Baixa/Média/Alta. "Residual" é o que sobra depois da mitigação.

| # | Risco | Prob. | Impacto | Mitigação | Residual |
|---|---|---|---|---|---|
| R1 | **Instância órfã cobrando indefinidamente** (app fechado, crash, bug do reaper) | Média | **Alta** | Chave morta na VM, vida máxima, auto-desligar vazio, tags, reaper, teto de quantidade, alerta Budgets (§6) | Baixa (custo limitado a no máximo 20 min + o teto de vida) |
| R2 | Credencial da nuvem vazar (Mac comprometido, log, backup) | Baixa | **Alta** | Keychain/Vault, política mínima com condições, usuário IAM dedicado, preferir `aws login` temporário, nunca no container nem em log, recusar chave raiz | Média (chave de longa duração ainda é risco) |
| R3 | Permissão IAM ampla demais que o usuário concede "para funcionar" | Média | Alta | Template de política pronto, verificador que lê as permissões efetivas e avisa; recusar administrador | Média |
| R4 | VNC, admin ou Docker exposto à internet por erro (security group aberto) | Baixa | **Alta** | Security group criado pelo app só com SSH ao IP do usuário (ou nenhum com SSM); teste automático que **varre as portas** da VM e falha se algo além de 22 abrir; nunca publicar portas do host | Baixa |
| R5 | MITM no SSH (host key não fixada) | Baixa | Alta | Fixar a chave do host (impressão digital recebida pelo console da instância ou por `user-data` assinado) e `StrictHostKeyChecking=yes` | Baixa |
| R6 | **O iptables não funciona** no ambiente (kernel, provedor) e o agente fica sem firewall | Baixa em EC2/GCE/Hetzner; Média em Fly/CF | Alta | O supervisor já **falha fechado**; spike por provedor antes de liberar; teste de contrato na partida | Baixa |
| R7 | Reqlog com corpos (dados sensíveis) vaza ou fica na VM | Média | Alta | EBS cifrado, tmpfs para o reqlog, cópia para o Mac e apagamento, destruir volume ao terminar, aviso na UI | Média |
| R8 | Segredos de tarefa gravados em disco da VM | Baixa | Alta | Só por exec/stdin para tmpfs; nunca `user-data`/env; teste que procura o valor no disco | Baixa |
| R9 | **Bloqueio por IP de datacenter** torna a nuvem pior que o Mac | **Alta** | Média | Proxy upstream continua; expectativa na UI; permitir escolher região; alerta quando a taxa de bloqueio sobe (reqlog já tem status) | Média (limitação estrutural) |
| R10 | Uso abusivo leva a suspensão da conta AWS do usuário | Média | Alta | Aviso no primeiro uso, limites de taxa opcionais, logs completos, sem sugestão de contorno | Média |
| R11 | Latência do viewer ruim (us-east-1) | Alta | Baixa/Média | Opção sa-east-1, métrica de RTT mostrada, VNC com compressão adequada | Baixa |
| R12 | Host compartilhado cai e derruba todos os computadores | Média | Média | Tratamento de reconexão no app (eventos Docker), estado do trabalho em `/work` com cópia periódica, aviso claro | Média |
| R13 | Cota de vCPU da conta nova impede subir | Média | Média | Verificar `ServiceQuotas` antes, mensagem guiada para pedir aumento | Baixa |
| R14 | Tempo de partida alto (instalar Docker e baixar imagem em cada host) | Alta (se sem AMI) | Média | AMI própria por região com a imagem pré-carregada (custo de cópia entre regiões e manutenção da AMI); host ligado enquanto houver uso | Baixa/Média |
| R15 | Deriva de preço/limite do provedor (Hetzner reajustou duas vezes em 2026) | Alta | Baixa/Média | Preços lidos por versão/API, rotulados como estimativa; não prometer valor fixo | Baixa |
| R16 | Lock-in em SDK de sandbox de terceiro | Média | Média | Só como provedor opcional, atrás da interface `CloudProvider` | Baixa |
| R17 | Divergência de arquitetura (amd64 não verificado, CS-122) | Média (se sair do Graviton) | Média | Manter arm64 no MVP; validar amd64 antes de provedores x86-only | Baixa |
| R18 | Expansão de escopo do modo isolado (CLI na nuvem com credenciais do Claude) | Média | **Alta** | Fora do BK-12; documentar como proibido até haver desenho de credenciais (08/audit) | Baixa |
| R19 | App rodando "invisivelmente" (`.accessory` depois de ⌘Q, 08 AR-108) mantém hosts ligados | Média | Média | Quit com custo à vista, lease curto, ícone/indicador de "nuvem ativa" na barra de menus | Baixa |
| R20 | Erro de contabilidade (custo mostrado diferente do cobrado) | Alta | Baixa | Sempre "estimativa"; reconciliação com Cost Explorer; Budgets como árbitro | Baixa |

---

## 9. Recomendação

### 9.1 Qual provedor primeiro e por quê

1. **AWS EC2 (arm64/Graviton), arquitetura (b2), SSH no MVP.** É a única opção que mantém o container idêntico, o fail-closed do firewall, o `exec` Docker, o viewer e o egress sem redesenho. Graviton casa com a imagem arm64 já verificada. O usuário-alvo já tem ou cria uma conta AWS facilmente. A etiquetagem, o IAM com condições e o desligamento por `shutdown` dão o melhor controle de custo.
2. **Segundo: Fly.io (com região `gru`) ou Hetzner**, escolhendo conforme o objetivo:
   - Hetzner: menor preço e login de uma chave só, mas só Europa nos planos baratos; IP bastante sinalizado; sem Brasil.
   - Fly.io: faturamento por segundo, região em São Paulo, máquinas Firecracker; porém exige backend próprio (Machines API) e **um spike** para confirmar root/iptables, exec e arquitetura.
3. **Cloudflare:** não rodar o computador lá agora. Avaliar Cloudflare Tunnel como solução de acesso na v1.1/v2 e **Containers** como experimento (v3), depois de confirmar privilégios, arquitetura e exec.
4. **Sandboxes (E2B, Daytona, Modal):** só como provedores opcionais "premium" depois que a interface `CloudProvider` existir.

### 9.2 O que NÃO fazer

- Não tentar **Fargate** nem **Cloud Run** com o container atual (a documentação os exclui); não enfraquecer o firewall por uid para "caber".
- Não expor **Docker (2375/2376), VNC (5900) ou admin (8790)** para a internet, nem mesmo "temporariamente".
- Não pedir **chave raiz** nem **administrador**; não gravar chaves em texto ou no log.
- Não depender **só do app** para limpar órfãos: o app pode estar fechado.
- Não criar **NAT Gateway**, Elastic IPs soltos, nem volumes sem `DeleteOnTermination`.
- Não levar o **modo isolado** (CLI do Claude/Codex com credenciais) para a nuvem no BK-12.
- Não prometer preço fixo nem "garantia de custo máximo": só estimativas e tetos configuráveis.

### 9.3 Plano em fases e esforço (agent-days, estimativa grossa)

**Fase 0: Spike de viabilidade (3 dias).** Em uma `c7g.large`/`t4g.medium` na AWS: subir a imagem real; confirmar o `firewall.py` (fail-closed), Xvfb/Chromium, VNC pelo túnel, exec sequestrado por `ssh -L` do socket; medir latência sa-east-1 vs us-east-1, tempo de partida (AMI vs instalar) e banda do VNC; confirmar se a conta nova tem cota. Saída: `docs/evidence/spikes/bk12/`. **Só prosseguir se o exec e o iptables passarem.**

**Fase 1: MVP AWS (≈ 30 dias).**

| Bloco | Dias |
|---|---|
| Interface `CloudProvider`/`ComputerHost` (local vs remoto) sem quebrar o caminho local | 4 |
| Transporte remoto: túnel SSH gerenciado, socket Docker, forwards por computador, reconexão | 4 |
| Cliente AWS mínimo (EC2 Query + SigV4, ou SDK), AMI/cloud-init, security group, tags | 5 |
| Chave morta na VM, vida máxima, auto-desligar vazio, reaper e limites de quantidade | 4 |
| Arquivos e segredos: `/work` de volta ao Mac, reqlog via admin API, segredos em tmpfs por exec | 4 |
| UI: Settings › Computers › Cloud (conectar, região, limite, custo estimado e do dia, órfãos) | 5 |
| Testes (contrato do túnel, varredura de portas, caos: matar o app, derrubar a rede) e evidências | 4 |

**Fase 2: v1.1 de endurecimento (≈ 12 dias).** SSM ou Instance Connect (sem porta de entrada), `aws login`/SSO, Budgets automático com ação, sa-east-1 com preço visível, Spot opcional (US$ 0,016/h para `t4g.medium`, mas pode ser interrompida), AMI por região automatizada, medição de custo real por Cost Explorer.

**Fase 3: segundo provedor (≈ 12 dias cada).** Hetzner (token único) ou Fly.io, atrás de `CloudProvider`. Cloudflare Tunnel como transporte opcional (≈ 6 dias, depois de validar).

**Fase 4: experimentos (≈ 15 dias).** Cloudflare Containers via Worker gateway; GCE; sandboxes premium.

**Marco de decisão após a Fase 0:** o dono decide se o MVP vale ~30 dias de trabalho dado o ganho real (paralelismo sem pesar o Mac, e computadores que continuam rodando com o Mac fechado).

---

## 10. Perguntas em aberto para o dono

1. **Para que serve a nuvem para você?** Mais paralelismo que o Mac aguenta, computadores 24 h com o Mac desligado, ou IP diferente? A resposta muda a prioridade de tudo (chave morta, host persistente, proxy).
2. **Os computadores precisam continuar vivos com o Mac fechado ou dormindo?** Hoje a chave morta os apaga em ~20 min. Se a resposta for "sim, por horas", é outro produto (precisa de um controlador na nuvem, não só o app).
3. **Qual teto de gasto você aceita por mês e por dia?** Define os padrões de vida máxima (sugiro 8 h), tamanho do host e o orçamento automático.
4. **Região padrão:** us-east-1 (melhor para os portais dos EUA, 100 a 150 ms de latência no viewer) ou sa-east-1 (viewer rápido, preço maior, IP brasileiro talvez bloqueado)?
5. **Quem vai conectar a conta?** Só você (aceita criar usuário IAM com política guiada) ou usuários finais sem conhecimento de AWS? No segundo caso, a UX de "Cloudflare/OAuth em um clique" é muito mais cara de construir.
6. **Aceita os bloqueios por IP de datacenter** e o uso do proxy upstream obrigatório para alvos protegidos?
7. **Política de risco legal:** o Racky mostra o aviso de uso aceitável no primeiro uso e mantém os logs; isso basta? Alguém precisa ler o AUP de cada provedor antes de liberar.
8. **Segundo provedor:** prefere preço mínimo e simplicidade (Hetzner), ou São Paulo e faturamento por segundo (Fly.io)?
9. **O modo isolado (CLI dentro do computador) algum dia irá para a nuvem?** Se sim, o desenho de credenciais do Claude/Codex precisa existir antes (hoje é proibido por este estudo).
10. **Dados:** os arquivos que o agente gera em `/work` precisam voltar ao Mac automaticamente ao final (sincronização), ou o usuário os baixa manualmente?

---

## Anexo A. Fontes e datas

Todas consultadas em **20/10/2026**. "(3ª)" indica site de terceiros. Itens marcados **não verificado** no texto não tiveram confirmação em fonte oficial.

- AWS Fargate, parâmetros de definição de tarefa (capacidades, `sharedMemorySize`): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
- AWS Fargate, considerações de segurança: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-security-considerations.md
- AWS Fargate, preços: https://aws.amazon.com/fargate/pricing/
- AWS EC2, preços sob demanda (franquia de tráfego, créditos T4g): https://aws.amazon.com/ec2/pricing/on-demand/
- `t4g.medium` (3ª, Vantage): https://instances.vantage.sh/aws/ec2/t4g.medium
- `c7g.large` (3ª, Vantage): https://instances.vantage.sh/aws/ec2/c7g.large
- IPv4 público AWS: https://aws.amazon.com/blogs/aws/new-aws-public-ipv4-address-charge-public-ip-insights
- AWS Session Manager (port forwarding): https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html
- EC2 Instance Connect: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html
- AWS Budgets (ações): https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-controls.html
- AWS Budgets (atraso de 8 a 12 h): https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- AWS Lightsail, preços: https://aws.amazon.com/lightsail/pricing/
- `aws login` (19/11/2025): https://aws.amazon.com/about-aws/whats-new/2025/11/console-credentials-aws-cli-sdk-authentication/
- Latência entre regiões AWS (3ª): https://www.economize.cloud/resources/aws/latency/sa-east-1-vs-us-east-1/
- Cloudflare Containers: arquitetura https://developers.cloudflare.com/containers/platform-details/architecture/ · limites https://developers.cloudflare.com/containers/platform-details/limits/ · preços https://developers.cloudflare.com/containers/pricing/
- Cloudflare Browser Rendering, preços: https://developers.cloudflare.com/browser-rendering/pricing/
- Cloudflare Containers em beta, amd64 (3ª, 2025): https://devclass.com/2025/07/01/cloudflare-container-platform-in-public-preview-with-scale-to-zero-pricing-some-initial-limitations/
- Fly.io, preços: https://docs.fly.io/about/pricing · API de Machines: https://docs.fly.io/machines/api/machines-resource · fórum (iptables, 2021): https://community.fly.io/t/runtime-linux-capabilities-running-dsvpn-as-a-fly-app/1183
- Google Cloud Run, contrato do container: https://docs.cloud.google.com/run/docs/container-contract
- Hetzner, ajuste de preços (atualizado 08/07/2026): https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/
- DigitalOcean Droplets: https://www.digitalocean.com/pricing/droplets
- E2B: https://e2b.dev/pricing · Daytona: https://www.daytona.io/pricing · Modal: https://modal.com/pricing
- Browserbase: https://www.browserbase.com/pricing · Steel: https://steel.dev/pricing
- Docker, acesso remoto por SSH e TLS: https://docs.docker.com/engine/security/protect-access/
- Docker socket por SSH (3ª, exemplo antigo): https://www.shore.co.il/blog/docker_socket_over_ssh/
- Reputação de IP de datacenter (3ª, interesse comercial): https://www.joinmassive.com/blog/why-ai-agents-get-blocked-on-datacenter-ips-and-how-to-fix-it

## Anexo B. Lacunas desta pesquisa (declaradas)

- Preços de `sa-east-1`, tarifa de tráfego da AWS por GB, preço do GCE e cota inicial de vCPU de conta nova: **não capturados** de fonte oficial.
- Root/`NET_ADMIN`/iptables em Cloudflare Containers, Fly, E2B, Daytona e Modal: **não confirmados**; dependem de spike.
- Arquitetura (arm64/amd64) em Fly e nos sandboxes: **não confirmada**.
- Cloudflare Tunnel/Access e o AUP da AWS: **não lidos** nesta pesquisa.
- Tempos de partida, banda do VNC e latência real a partir do Brasil: **estimativas**, a medir na Fase 0.
- Preços de terceiros (Vantage) devem ser conferidos na página oficial de preços da AWS ou no Pricing Calculator antes de aparecerem em qualquer tela do produto.
