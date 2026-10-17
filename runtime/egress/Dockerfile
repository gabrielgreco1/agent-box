# agentbox-egress: sidecar de saída de um computador (07 §2.5, CS-140..149; 00 T9).
#
# Reprodutibilidade (08 AR-114): a base é fixada por DIGEST do índice multi-arquitetura (a tag `3.13-alpine` é só legenda).
# Só biblioteca padrão do Python: nenhuma dependência para fixar além da base. Roda como uid 10003, rootfs somente leitura
# (o app monta /tmp como tmpfs e `/logs` como bind rw só para este container).
FROM python:3.13-alpine@sha256:2d9aefe2fef018a7eb2c13064c89c71929800fd2e5dccdbf52ea5da5bb8d929a

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/opt/egress

RUN adduser -D -H -u 10003 -s /sbin/nologin egress \
    && mkdir -p /opt/egress /logs \
    && chown egress:egress /logs

COPY agentbox_egress /opt/egress/agentbox_egress

USER 10003
EXPOSE 3128 8790
HEALTHCHECK --interval=5s --timeout=3s --start-period=2s --retries=5 \
    CMD ["python", "-m", "agentbox_egress.healthcheck"]
ENTRYPOINT ["python", "-m", "agentbox_egress"]
