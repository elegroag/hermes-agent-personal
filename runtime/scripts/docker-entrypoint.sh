#!/usr/bin/env bash
# ============================================================
# docker-entrypoint.sh — Entrypoint personalizado Hermes Agent
#
# Responsabilidades:
#   1. Inicializar /opt/data con templates si es un perfil nuevo
#   2. Mezclar variables de entorno en el .env del perfil
#   3. Validar que exista al menos un API key configurado
#   4. Delegar la ejecución al entrypoint oficial de Hermes
#
# Variables de entorno que controlan el comportamiento:
#   HERMES_PROFILE  → nombre del perfil (default, coder, etc.)
#   HERMES_HOME     → directorio de datos (/opt/data)
#   HERMES_SKIP_INIT → "true" para omitir inicialización
# ============================================================
set -euo pipefail

# ── Colores para logs ───────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[hermes-init]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[hermes-init]${NC} ✓ $*"; }
log_warn()  { echo -e "${YELLOW}[hermes-init]${NC} ⚠ $*"; }
log_error() { echo -e "${RED}[hermes-init]${NC} ✗ $*" >&2; }

# ── Configuración base ──────────────────────────────────────
HERMES_HOME="${HERMES_HOME:-/opt/data}"
HERMES_PROFILE="${HERMES_PROFILE:-default}"
TEMPLATE_DIR="/opt/hermes-templates/${HERMES_PROFILE}"
SKIP_INIT="${HERMES_SKIP_INIT:-false}"

# ── Función: inicializar estructura del perfil ──────────────
initialize_profile() {
    log_info "Inicializando perfil '${HERMES_PROFILE}' en ${HERMES_HOME}..."

    # Crear estructura de directorios del perfil
    local dirs=(
        "${HERMES_HOME}/memories"
        "${HERMES_HOME}/skills"
        "${HERMES_HOME}/sessions"
        "${HERMES_HOME}/cron"
        "${HERMES_HOME}/logs"
        "${HERMES_HOME}/hooks"
        "${HERMES_HOME}/skins"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done

    log_ok "Estructura de directorios creada"

    # Copiar template de config.yaml si no existe
    if [[ ! -f "${HERMES_HOME}/config.yaml" ]]; then
        if [[ -f "${TEMPLATE_DIR}/config.yaml" ]]; then
            cp "${TEMPLATE_DIR}/config.yaml" "${HERMES_HOME}/config.yaml"
            log_ok "config.yaml copiado desde template '${HERMES_PROFILE}'"
        else
            log_warn "No hay template config.yaml para '${HERMES_PROFILE}', Hermes usará defaults"
        fi
    else
        log_ok "config.yaml existente — no sobreescribir"
    fi

    # Copiar SOUL.md si no existe
    if [[ ! -f "${HERMES_HOME}/SOUL.md" ]]; then
        if [[ -f "${TEMPLATE_DIR}/SOUL.md" ]]; then
            cp "${TEMPLATE_DIR}/SOUL.md" "${HERMES_HOME}/SOUL.md"
            log_ok "SOUL.md copiado desde template '${HERMES_PROFILE}'"
        fi
    else
        log_ok "SOUL.md existente — no sobreescribir"
    fi
}

# ── Función: sincronizar API keys al .env del perfil ────────
# Las variables de entorno del contenedor tienen prioridad
# sobre los valores existentes en el .env del volumen
sync_env_file() {
    local env_file="${HERMES_HOME}/.env"

    log_info "Sincronizando variables de entorno en ${env_file}..."

    # Crear .env si no existe
    touch "${env_file}"
    chmod 600 "${env_file}"

    # Mapeo de variables de entorno → claves del .env
    # Solo se escriben si la variable está definida y no vacía
    declare -A ENV_MAP=(
        ["ANTHROPIC_API_KEY"]="ANTHROPIC_API_KEY"
        ["OPENAI_API_KEY"]="OPENAI_API_KEY"
        ["OPENROUTER_API_KEY"]="OPENROUTER_API_KEY"
        ["API_SERVER_KEY"]="API_SERVER_KEY"
        ["API_SERVER_ENABLED"]="API_SERVER_ENABLED"
        ["API_SERVER_HOST"]="API_SERVER_HOST"
        ["API_SERVER_PORT"]="API_SERVER_PORT"
        ["API_SERVER_CORS_ORIGINS"]="API_SERVER_CORS_ORIGINS"
        ["HERMES_DASHBOARD"]="HERMES_DASHBOARD"
        ["HERMES_DASHBOARD_HOST"]="HERMES_DASHBOARD_HOST"
        ["HERMES_DASHBOARD_PORT"]="HERMES_DASHBOARD_PORT"
        ["TELEGRAM_TOKEN"]="TELEGRAM_TOKEN"
        ["DISCORD_TOKEN"]="DISCORD_TOKEN"
        ["SLACK_BOT_TOKEN"]="SLACK_BOT_TOKEN"
        ["OPENAI_COMPATIBLE_KEY"]="OPENAI_COMPATIBLE_KEY"
        ["OPENAI_COMPATIBLE_URL"]="OPENAI_COMPATIBLE_URL"
    )

    for env_var in "${!ENV_MAP[@]}"; do
        local key="${ENV_MAP[$env_var]}"
        local value="${!env_var:-}"

        if [[ -n "${value}" ]]; then
            # Eliminar la línea existente con esa clave y agregar la nueva
            sed -i "/^${key}=/d" "${env_file}" 2>/dev/null || true
            echo "${key}=${value}" >> "${env_file}"
        fi
    done

    log_ok ".env sincronizado"
}

# ── Función: validar configuración mínima ───────────────────
validate_config() {
    log_info "Validando configuración del agente '${HERMES_PROFILE}'..."

    local has_provider=false

    for key in ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY; do
        if [[ -n "${!key:-}" ]]; then
            has_provider=true
            break
        fi
    done

    # Verificar en el .env del volumen si no se pasó por entorno
    if [[ "${has_provider}" == "false" ]] && [[ -f "${HERMES_HOME}/.env" ]]; then
        if grep -qE "^(ANTHROPIC|OPENAI|OPENROUTER)_API_KEY=.+" "${HERMES_HOME}/.env" 2>/dev/null; then
            has_provider=true
        fi
    fi

    if [[ "${has_provider}" == "false" ]]; then
        log_warn "No se detectó ningún API key de proveedor LLM."
        log_warn "El agente '${HERMES_PROFILE}' iniciará pero no podrá ejecutar inferencias."
        log_warn "Configure al menos uno: ANTHROPIC_API_KEY, OPENAI_API_KEY o OPENROUTER_API_KEY"
    else
        log_ok "Proveedor LLM configurado"
    fi
}

# ── Función: mostrar banner de inicio ───────────────────────
show_banner() {
    local version
    version=$(/opt/hermes/.venv/bin/hermes --version 2>/dev/null | head -1 || echo "v0.14.0")

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Hermes Agent ${version} (2026.5.19)       ║${NC}"
    echo -e "${BLUE}║       Perfil: ${GREEN}${HERMES_PROFILE}${BLUE}$(printf '%*s' $((29 - ${#HERMES_PROFILE})) '')║${NC}"
    echo -e "${BLUE}║       Data:   ${HERMES_HOME}$(printf '%*s' $((29 - ${#HERMES_HOME})) '')║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Función: configurar .bashrc del usuario ───────────────────
configure_bashrc() {
    local bashrc="${HOME}/.bashrc"

    cat > "${bashrc}" << 'BASHRCEOF'
# ── NVM ────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

# ── rbenv ──────────────────────────────────────────────────────
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:$PATH"
command -v rbenv &>/dev/null && eval "$(rbenv init - bash)"

# ── Python / uv ───────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
export PYTHONUNBUFFERED=1

# ── Hermes Agent ─────────────────────────────────────────────
export PATH="/opt/hermes/.venv/bin:$PATH"
export HERMES_HOME="${HERMES_HOME:-/opt/data}"

# ── Workspace ─────────────────────────────────────────────────
export WORKSPACE="/workspace"
alias cdw="cd $WORKSPACE" 2>/dev/null || true

# ── Aliases ───────────────────────────────────────────────────
alias ll="ls -lah --color=auto" 2>/dev/null || true
alias gs="git status" 2>/dev/null || true
alias glog="git log --oneline --graph --decorate" 2>/dev/null || true
alias py="python3" 2>/dev/null || true

# ── Banner (solo en shells interactivos) ─────────────────────
if [ -n "$PS1" ] && [ -z "$HERMES_NO_BANNER" ]; then
    echo ""
    echo "  Hermes Agent Dev Environment"
    echo "  ─────────────────────────────────────────────────"
    echo "  Python:  $(python3 --version 2>/dev/null || echo 'N/A')"
    echo "  Node:    $(node --version 2>/dev/null || echo 'N/A')"
    echo "  Ruby:    $(ruby --version 2>/dev/null | cut -d' ' -f1-2 || echo 'N/A')"
    echo "  uv:      $(uv --version 2>/dev/null || echo 'N/A')"
    echo "  Perfil:  ${HERMES_PROFILE:-default}"
    echo "  Workspace: $WORKSPACE"
    echo "  ─────────────────────────────────────────────────"
    echo ""
fi
BASHRCEOF

    log_ok ".bashrc configurado"
}

# ── Main ────────────────────────────────────────────────────
main() {
    show_banner

    if [[ "${SKIP_INIT}" != "true" ]]; then
        configure_bashrc
        initialize_profile
        sync_env_file
        validate_config
    else
        log_warn "HERMES_SKIP_INIT=true — omitiendo inicialización"
    fi

    log_info "Ejecutando comando: hermes $*"
    echo ""

    # Delegar al binario oficial de hermes con los argumentos recibidos
    exec /opt/hermes/.venv/bin/hermes "$@"
}

main "$@"
