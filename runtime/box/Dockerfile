# agentbox-box: imagem dos papéis `runtime` e `work` de um computador (07 §2.3, CS-120..122).
#
# Reprodutibilidade (08 AR-114, audit/09 N11):
#   - a base é fixada por DIGEST (a tag `v1.63.0-noble` é só legenda; o digest manda);
#   - nenhum pin de versão de apt (as versões de apt somem dos espelhos): os pacotes vêm da base fixada no
#     momento do build e a imagem resultante é identificada pelo digest e pela tag de hash do contexto
#     (`agentbox-box:ctx-<sha12>`, scripts/build-runtime-image.sh);
#   - pacotes Python com versão exata em requirements.txt.
# A API de ações, o listener CDP e as ferramentas da box entram na T3-03; aqui fica o chão: usuários, pacotes e
# entrypoint por papel.
FROM mcr.microsoft.com/playwright/python:v1.63.0-noble@sha256:72bd171a9ffc2b4b59532aaa6210e21014d07093120dc25528870c0b840da1f0

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        xvfb openbox tint2 x11vnc websockify novnc xdotool dtach curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
# --ignore-installed: o typing_extensions da base veio do apt (sem RECORD) e o pip não consegue desinstalá-lo.
RUN python -m pip install --ignore-installed -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# runtime (10001) e work (10002); o egress usa a própria imagem (T3-02, uid 10003).
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin runtime \
    && useradd --uid 10002 --create-home --shell /usr/sbin/nologin work \
    && mkdir -p /opt/agentbox /work \
    && chown work:work /work

# Sem `COPY --chmod`: sintaxe só do BuildKit; o contexto também precisa buildar pelo builder clássico da Engine API.
COPY entrypoint.sh /opt/agentbox/entrypoint.sh
RUN chmod 0755 /opt/agentbox/entrypoint.sh

ENV AGENTBOX_ROLE=work
ENTRYPOINT ["/opt/agentbox/entrypoint.sh"]
CMD []
