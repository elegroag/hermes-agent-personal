# ============================================================
# Hermes Agent — Imagen personalizada (v0.14.0 / 2026.5.16)
# Extiende la imagen oficial de NousResearch con:
#   • Templates de perfiles pre-configurados
#   • Script de entrypoint con inicialización automática
#   • Healthcheck nativo con liveness endpoint
#   • Utilidades adicionales de sistema
# ============================================================
FROM nousresearch/hermes-agent:latest

LABEL maintainer="infra@equipo.local"
LABEL org.opencontainers.image.title="Hermes Agent (Multi-Profile)"
LABEL org.opencontainers.image.version="0.14.0"
LABEL org.opencontainers.image.description="Hermes Agent con soporte multi-perfil y auto-configuración"

# ── Variables de entorno base ──────────────────────────────
# HERMES_HOME se sobreescribe por perfil vía docker-compose
ENV HERMES_DATA_DIR=/opt/data
ENV HERMES_HOME=/opt/data
ENV HERMES_PROFILE=default
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# ── Instalación de herramientas adicionales ─────────────────
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        jq \
        procps \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# ── Directorio de templates internos de perfiles ───────────
# Estos templates se copian a /opt/data si el perfil no existe
RUN mkdir -p /opt/hermes-templates/{default,coder,researcher,assistant}

# Copiar templates de configuración (SOUL + config base)
COPY --chown=hermes:hermes profiles/default/SOUL.md     /opt/hermes-templates/default/SOUL.md
COPY --chown=hermes:hermes profiles/coder/SOUL.md        /opt/hermes-templates/coder/SOUL.md
COPY --chown=hermes:hermes profiles/researcher/SOUL.md   /opt/hermes-templates/researcher/SOUL.md
COPY --chown=hermes:hermes profiles/assistant/SOUL.md    /opt/hermes-templates/assistant/SOUL.md

COPY --chown=hermes:hermes profiles/default/config.yaml      /opt/hermes-templates/default/config.yaml
COPY --chown=hermes:hermes profiles/coder/config.yaml         /opt/hermes-templates/coder/config.yaml
COPY --chown=hermes:hermes profiles/researcher/config.yaml    /opt/hermes-templates/researcher/config.yaml
COPY --chown=hermes:hermes profiles/assistant/config.yaml     /opt/hermes-templates/assistant/config.yaml

# ── Script de entrypoint personalizado ─────────────────────
COPY --chown=hermes:hermes scripts/docker-entrypoint.sh /opt/hermes-entrypoint.sh
RUN chmod +x /opt/hermes-entrypoint.sh

# ── Script de healthcheck interno ──────────────────────────
COPY --chown=hermes:hermes scripts/healthcheck.sh /opt/healthcheck.sh
RUN chmod +x /opt/healthcheck.sh

# ── Volumen de datos — punto de montaje único por perfil ───
VOLUME ["/opt/data"]

# ── Exponer puertos ────────────────────────────────────────
# 8642 → Gateway API (OpenAI-compatible)
# 9119 → Dashboard web
EXPOSE 8642 9119

# ── Healthcheck integrado ──────────────────────────────────
# Verifica que el gateway responde en el puerto 8642
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=60s \
    --retries=3 \
    CMD /opt/healthcheck.sh

USER hermes

ENTRYPOINT ["/opt/hermes-entrypoint.sh"]
CMD ["gateway", "run"]
