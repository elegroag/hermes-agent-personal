# ==============================================================
# Hermes Agent — Dockerfile Multi-Stage
# Base: Ubuntu 24.04 LTS
#
# Toolchain instalado:
#   • Python 3.11 + uv (gestor de paquetes/venvs)
#   • Node.js 22 LTS via NVM
#   • Ruby 3.3.x via rbenv (solo rbenv + bundler, sin Rails)
#   • hermes-agent v0.14.0 (extraído de imagen oficial)
#
# Usuario: hermes (UID 1000)
#   → Grupos: hermes, sudo, docker
#   → NOPASSWD: sudo completo (entorno de desarrollo)
#
# Volúmenes:
#   /opt/data   → datos persistentes del agente (config, memoria, skills)
#   /workspace  → directorio de trabajo para proyectos de desarrollo
#
# Puertos:
#   8642 → Gateway API REST (OpenAI-compatible)
#   9119 → Dashboard web
# ==============================================================

# ── ARGs globales ─────────────────────────────────────────────
ARG HERMES_IMAGE=nousresearch/hermes-agent:latest
ARG NODE_VERSION=22
ARG NVM_VERSION=0.40.1
ARG RUBY_VERSION=3.3.6
ARG USERNAME=hermes
ARG USER_UID=1000
ARG USER_GID=1000
ARG HERMES_VERSION=0.14.0

# ==============================================================
# STAGE 1 — Extractor: obtener hermes-agent desde imagen oficial
# ==============================================================
FROM ${HERMES_IMAGE} AS hermes-dist

# ==============================================================
# STAGE 2 — Runtime: entorno de desarrollo
# ==============================================================
FROM ubuntu:24.04

ARG NODE_VERSION
ARG NVM_VERSION
ARG RUBY_VERSION
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG HERMES_VERSION

# ── Metadatos ─────────────────────────────────────────────────
LABEL maintainer="infra@equipo.local"
LABEL org.opencontainers.image.title="Hermes Agent Dev Environment"
LABEL org.opencontainers.image.version="${HERMES_VERSION}"
LABEL org.opencontainers.image.description="Hermes Agent multi-perfil con toolchain de desarrollo"
LABEL org.opencontainers.image.base.name="ubuntu:24.04"
LABEL org.opencontainers.image.source="https://github.com/equipo/hermes-agent"

# ── Shell por defecto ─────────────────────────────────────────
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ==============================================================
# BLOQUE 1 — Variables de entorno del sistema
# ==============================================================
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/Bogota \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NVM_DIR="/home/${USERNAME}/.nvm" \
    RBENV_ROOT="/home/${USERNAME}/.rbenv" \
    HERMES_HOME=/opt/data \
    HERMES_DATA_DIR=/opt/data \
    HERMES_PROFILE=default

# PATH: hermes venv → uv → rbenv → local bin
ENV PATH="/opt/hermes/.venv/bin:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.rbenv/shims:/home/${USERNAME}/.rbenv/bin:${PATH}"

# ==============================================================
# BLOQUE 2 — Paquetes del sistema (cache mounts para speed)
# ==============================================================
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        # ── Utilidades base ──────────────────────────────────
        ca-certificates curl wget git git-lfs unzip xz-utils gnupg lsb-release \
        # ── Build tools ───────────────────────────────────────
        build-essential gcc g++ make cmake pkg-config autoconf bison \
        # ── Python 3.11 + dev libs ───────────────────────────
        python3.11 python3.11-dev python3.11-venv python3-pip python3-setuptools python3-wheel \
        # ── Ruby rbenv deps ───────────────────────────────────
        libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgdbm-dev libncurses5-dev \
        # ── SQLite (sesiones hermes) ─────────────────────────
        sqlite3 libsqlite3-dev \
        # ── Utilidades varias ─────────────────────────────────
        jq procps netcat-openbsd htop sudo vim nano less ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --set python3 /usr/bin/python3.11

# ==============================================================
# BLOQUE 3 — uv: gestor Python (system-wide)
# ==============================================================
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | UV_INSTALL_DIR=/usr/local/bin sh

# ==============================================================
# BLOQUE 4 — Crear usuario hermes
# ==============================================================
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && (getent group docker > /dev/null 2>&1 || groupadd --system docker) \
    && useradd \
        --uid "${USER_UID}" \
        --gid "${USER_GID}" \
        --groups sudo,docker \
        --create-home \
        --shell /bin/bash \
        "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 440 "/etc/sudoers.d/${USERNAME}"

# ==============================================================
# BLOQUE 5 — Copiar hermes-agent desde imagen oficial
# ==============================================================
COPY --from=hermes-dist /opt/hermes /opt/hermes

RUN chown -R "${USERNAME}:${USERNAME}" /opt/hermes \
    && chmod -R u+rX,go+rX /opt/hermes

# ==============================================================
# BLOQUE 6 — Estructura de directorios
# ==============================================================
RUN mkdir -p /opt/data /workspace /opt/hermes-templates \
    && chown -R "${USERNAME}:${USERNAME}" /opt/data /workspace /opt/hermes-templates

# ==============================================================
# BLOQUE 7 — NVM + Node.js (instalación optimizada)
# ==============================================================
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Instalar NVM con versión fija verificable
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
    | PROFILE=/dev/null bash

# Instalar Node.js y npm (pnpm/yarn son opcionales, se instalan bajo demanda)
RUN source "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && nvm use default \
    && nvm cache clear \
    && echo "Node: $(node --version) | npm: $(npm --version)"

# Symlinks system-wide
USER root
RUN source "/home/${USERNAME}/.nvm/nvm.sh" \
    && NODE_BIN="$(dirname "$(nvm which default)")" \
    && for bin in node npm npx; do \
        [ -f "${NODE_BIN}/${bin}" ] \
            && ln -sf "${NODE_BIN}/${bin}" "/usr/local/bin/${bin}" \
            || true; \
    done

# ── Paquetes npm globales opcionales (instalar bajo demanda) ───
# Descomentar si se necesitan:
# RUN source "/home/${USERNAME}/.nvm/nvm.sh" \
#     && npm install --global pnpm yarn

# ==============================================================
# BLOQUE 8 — rbenv + Ruby (pre-built binary, no compilation)
# ==============================================================
USER ${USERNAME}

# Instalar rbenv y ruby-build plugin
RUN git clone --depth=1 https://github.com/rbenv/rbenv.git "${RBENV_ROOT}" \
    && git clone --depth=1 https://github.com/rbenv/ruby-build.git "${RBENV_ROOT}/plugins/ruby-build"

#ruby-build soporta ruby-3.3.6 desde ubuntu 24.04 con confianza
#Usar MAKE_OPTS para compilacion paralela (si es necesario desde fuente)
RUN MAKE_OPTS="-j$(nproc)" \
    "${RBENV_ROOT}/bin/rbenv" install "${RUBY_VERSION}" \
    && "${RBENV_ROOT}/bin/rbenv" global "${RUBY_VERSION}" \
    && "${RBENV_ROOT}/bin/rbenv" rehash

# Gems esenciales (sin Rails - ocupa ~1GB+)
RUN eval "$(${RBENV_ROOT}/bin/rbenv init - bash)" \
    && gem install bundler --no-document \
    && rbenv rehash \
    && echo "Ruby: $(ruby --version) | Bundler: $(bundler --version)"

# ==============================================================
# BLOQUE 9 — Shell base del usuario hermes
# El .bashrc completo se configura en runtime via entrypoint
# ==============================================================
USER ${USERNAME}

# Shell base mínimo (completado en runtime por docker-entrypoint.sh)
RUN echo 'export HERMES_NO_BANNER=1' >> "/home/${USERNAME}/.bashrc"

# .bash_profile para login shells
RUN cp "/home/${USERNAME}/.bashrc" "/home/${USERNAME}/.bash_profile"

# ==============================================================
# BLOQUE 10 — Templates de perfiles y scripts
# ==============================================================
USER root

COPY --chown=${USERNAME}:${USERNAME} profiles/leader/SOUL.md      /opt/hermes-templates/leader/SOUL.md
COPY --chown=${USERNAME}:${USERNAME} profiles/coder/SOUL.md        /opt/hermes-templates/coder/SOUL.md
COPY --chown=${USERNAME}:${USERNAME} profiles/researcher/SOUL.md   /opt/hermes-templates/researcher/SOUL.md
COPY --chown=${USERNAME}:${USERNAME} profiles/assistant/SOUL.md    /opt/hermes-templates/assistant/SOUL.md
COPY --chown=${USERNAME}:${USERNAME} profiles/reviewer/SOUL.md     /opt/hermes-templates/reviewer/SOUL.md

COPY --chown=${USERNAME}:${USERNAME} profiles/leader/config.yaml    /opt/hermes-templates/leader/config.yaml
COPY --chown=${USERNAME}:${USERNAME} profiles/coder/config.yaml     /opt/hermes-templates/coder/config.yaml
COPY --chown=${USERNAME}:${USERNAME} profiles/researcher/config.yaml /opt/hermes-templates/researcher/config.yaml
COPY --chown=${USERNAME}:${USERNAME} profiles/assistant/config.yaml  /opt/hermes-templates/assistant/config.yaml
COPY --chown=${USERNAME}:${USERNAME} profiles/reviewer/config.yaml   /opt/hermes-templates/reviewer/config.yaml

COPY scripts/docker-entrypoint.sh /opt/hermes-entrypoint.sh
COPY scripts/healthcheck.sh       /opt/healthcheck.sh
RUN chmod +x /opt/hermes-entrypoint.sh /opt/healthcheck.sh \
    && chown "${USERNAME}:${USERNAME}" /opt/hermes-entrypoint.sh /opt/healthcheck.sh

# ==============================================================
# BLOQUE 11 — Verificación del toolchain en build time
# ==============================================================
RUN echo "=== Verificación de toolchain ===" \
    && python3 --version \
    && uv --version \
    && node --version \
    && npm --version \
    && echo "=== Toolchain OK ==="

# ==============================================================
# VOLÚMENES Y PUERTOS
# ==============================================================
VOLUME ["/opt/data", "/workspace"]

EXPOSE 8642 9119

# ==============================================================
# HEALTHCHECK
# ==============================================================
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=90s \
    --retries=3 \
    CMD /opt/healthcheck.sh

# ==============================================================
# ENTRYPOINT
# ==============================================================
USER ${USERNAME}
WORKDIR /workspace

ENTRYPOINT ["/opt/hermes-entrypoint.sh"]
CMD ["gateway", "run"]