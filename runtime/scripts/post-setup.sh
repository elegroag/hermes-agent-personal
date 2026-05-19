#!/usr/bin/env bash
# ============================================================
# post-setup.sh — Script de post-configuración Hermes Agent
#
# Ejecutar UNA SOLA VEZ después de clonar el repositorio
# y antes del primer `docker compose up`.
#
# Responsabilidades:
#   1. Verificar prerequisitos (Docker, Compose)
#   2. Crear estructura de directorios de datos por perfil
#   3. Generar archivo .env con API keys
#   4. Generar API keys de seguridad para cada agente
#   5. Construir la imagen Docker personalizada
#   6. Ejecutar wizard de configuración para el agente default
#   7. Mostrar resumen de endpoints
#
# Uso:
#   chmod +x scripts/post-setup.sh
#   ./scripts/post-setup.sh
#   ./scripts/post-setup.sh --skip-build    # omitir build
#   ./scripts/post-setup.sh --profile all   # configurar todos
# ============================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Constantes ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
DATA_DIR="${PROJECT_DIR}/data"

# Perfiles disponibles
AVAILABLE_PROFILES=("default" "coder" "researcher" "assistant")

# Argumentos
SKIP_BUILD=false
CONFIGURE_PROFILES="default"

# ── Parsear argumentos ───────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)   SKIP_BUILD=true; shift ;;
        --profile)      CONFIGURE_PROFILES="$2"; shift 2 ;;
        --help|-h)
            echo "Uso: $0 [--skip-build] [--profile default|all|coder|...]"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────
log_step()  { echo -e "\n${BOLD}${BLUE}▸ $*${NC}"; }
log_info()  { echo -e "  ${CYAN}→${NC} $*"; }
log_ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "  ${RED}✗${NC} $*" >&2; }

ask() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "${default}" ]]; then
        read -rp "  ${prompt} [${default}]: " result
        echo "${result:-${default}}"
    else
        read -rp "  ${prompt}: " result
        echo "${result}"
    fi
}

ask_secret() {
    local prompt="$1"
    local result
    read -rsp "  ${prompt}: " result
    echo ""
    echo "${result}"
}

# Generar clave aleatoria segura
generate_key() {
    openssl rand -hex 32 2>/dev/null || \
    python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || \
    cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64
}

# ── Banner ───────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║      Hermes Agent — Post-Configuración               ║"
    echo "║      v0.14.0 (2026.5.16) · NousResearch              ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Este script configura el entorno multi-agente."
    echo "  Directorio del proyecto: ${PROJECT_DIR}"
    echo ""
}

# ── Paso 1: Verificar prerequisitos ──────────────────────────
check_prerequisites() {
    log_step "Verificando prerequisitos"

    # Docker
    if ! command -v docker &>/dev/null; then
        log_error "Docker no está instalado. Instálalo desde https://docs.docker.com/get-docker/"
        exit 1
    fi
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    log_ok "Docker ${DOCKER_VERSION} disponible"

    # Docker Compose (plugin v2)
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose v2 no disponible. Actualiza Docker Desktop o instala el plugin."
        exit 1
    fi
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "2.x")
    log_ok "Docker Compose ${COMPOSE_VERSION} disponible"

    # openssl (para generar keys)
    if ! command -v openssl &>/dev/null; then
        log_warn "openssl no encontrado — se usará Python para generar claves"
    fi

    # Verificar que no haya puertos en uso
    local ports=(8642 8643 8644 8645 9119 9120 9121 9122)
    local conflicts=()
    for port in "${ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
           netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            conflicts+=("${port}")
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "Puertos en uso: ${conflicts[*]}"
        log_warn "Edita HERMES_*_PORT en .env si hay conflictos"
    else
        log_ok "Puertos disponibles"
    fi
}

# ── Paso 2: Crear estructura de datos ────────────────────────
create_data_directories() {
    log_step "Creando estructura de directorios de datos"

    local profile_dirs
    if [[ "${CONFIGURE_PROFILES}" == "all" ]]; then
        profile_dirs=("${AVAILABLE_PROFILES[@]}")
    else
        # Siempre incluir default más el perfil solicitado
        profile_dirs=("default")
        [[ "${CONFIGURE_PROFILES}" != "default" ]] && profile_dirs+=("${CONFIGURE_PROFILES}")
    fi

    for profile in "${profile_dirs[@]}"; do
        local profile_data="${DATA_DIR}/${profile}"
        local subdirs=(
            "${profile_data}/memories"
            "${profile_data}/skills"
            "${profile_data}/sessions"
            "${profile_data}/cron"
            "${profile_data}/logs"
            "${profile_data}/hooks"
        )

        for dir in "${subdirs[@]}"; do
            mkdir -p "${dir}"
        done

        # Permisos restrictivos en el directorio de datos
        chmod 700 "${profile_data}"

        log_ok "Perfil '${profile}': ${profile_data}"
    done
}

# ── Paso 3: Recopilar API keys ────────────────────────────────
collect_api_keys() {
    log_step "Configuración de proveedores LLM"
    echo ""
    echo "  Configura al menos UN proveedor. Deja vacío para omitir."
    echo "  Puedes editar ${ENV_FILE} después."
    echo ""

    ANTHROPIC_API_KEY=$(ask_secret "Anthropic API Key (sk-ant-...)")
    OPENAI_API_KEY=$(ask_secret "OpenAI API Key (sk-...)")
    OPENROUTER_API_KEY=$(ask_secret "OpenRouter API Key (sk-or-...)")

    if [[ -z "${ANTHROPIC_API_KEY}" ]] && \
       [[ -z "${OPENAI_API_KEY}" ]] && \
       [[ -z "${OPENROUTER_API_KEY}" ]]; then
        log_warn "No se configuró ningún proveedor LLM."
        log_warn "Los agentes no podrán ejecutar inferencias hasta configurar uno."
    fi
}

# ── Paso 4: Configurar plataformas de mensajería (opcional) ──
collect_messaging_tokens() {
    log_step "Configuración de plataformas de mensajería (opcional)"
    echo ""
    echo "  Los tokens son opcionales. Deja vacío para omitir."
    echo ""

    echo -e "  ${BOLD}Agente Default:${NC}"
    HERMES_DEFAULT_TELEGRAM_TOKEN=$(ask_secret "  Telegram Token del bot default")
    HERMES_DEFAULT_DISCORD_TOKEN=$(ask_secret  "  Discord Token del bot default")

    if [[ "${CONFIGURE_PROFILES}" == "all" ]]; then
        echo ""
        echo -e "  ${BOLD}Agente Coder:${NC}"
        HERMES_CODER_TELEGRAM_TOKEN=$(ask_secret "  Telegram Token del bot coder")
        HERMES_CODER_DISCORD_TOKEN=$(ask_secret  "  Discord Token del bot coder")

        echo ""
        echo -e "  ${BOLD}Agente Researcher:${NC}"
        HERMES_RESEARCHER_TELEGRAM_TOKEN=$(ask_secret "  Telegram Token del bot researcher")
        HERMES_RESEARCHER_DISCORD_TOKEN=$(ask_secret  "  Discord Token del bot researcher")

        echo ""
        echo -e "  ${BOLD}Agente Assistant:${NC}"
        HERMES_ASSISTANT_TELEGRAM_TOKEN=$(ask_secret "  Telegram Token del bot assistant")
        HERMES_ASSISTANT_DISCORD_TOKEN=$(ask_secret  "  Discord Token del bot assistant")
    fi
}

# ── Paso 5: Generar .env ──────────────────────────────────────
generate_env_file() {
    log_step "Generando archivo .env"

    # Generar API keys internas para cada agente
    local default_key    ; default_key=$(generate_key)
    local coder_key      ; coder_key=$(generate_key)
    local researcher_key ; researcher_key=$(generate_key)
    local assistant_key  ; assistant_key=$(generate_key)

    cat > "${ENV_FILE}" << EOF
# ============================================================
# Hermes Agent — Variables de Entorno
# Generado por post-setup.sh el $(date '+%Y-%m-%d %H:%M:%S')
#
# IMPORTANTE: No commitear este archivo en git.
# Agrega .env al .gitignore.
# ============================================================

# ── Proveedores LLM ─────────────────────────────────────────
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}

# ── API Keys de seguridad (generadas automáticamente) ───────
# Estas claves protegen los endpoints REST de cada agente.
# Cámbialas si las rotas o expones el servicio a internet.
HERMES_DEFAULT_API_KEY=${default_key}
HERMES_CODER_API_KEY=${coder_key}
HERMES_RESEARCHER_API_KEY=${researcher_key}
HERMES_ASSISTANT_API_KEY=${assistant_key}

# ── Puertos host (modifica si hay conflictos) ───────────────
HERMES_DEFAULT_API_PORT=8642
HERMES_DEFAULT_DASH_PORT=9119
HERMES_CODER_API_PORT=8643
HERMES_CODER_DASH_PORT=9120
HERMES_RESEARCHER_API_PORT=8644
HERMES_RESEARCHER_DASH_PORT=9121
HERMES_ASSISTANT_API_PORT=8645
HERMES_ASSISTANT_DASH_PORT=9122

# ── Nginx reverse proxy ──────────────────────────────────────
PROXY_HTTP_PORT=80
PROXY_HTTPS_PORT=443

# ── Configuración general ────────────────────────────────────
HERMES_DASHBOARD=1
API_CORS_ORIGINS=http://localhost

# ── Tokens de mensajería — Agente Default ───────────────────
HERMES_DEFAULT_TELEGRAM_TOKEN=${HERMES_DEFAULT_TELEGRAM_TOKEN:-}
HERMES_DEFAULT_DISCORD_TOKEN=${HERMES_DEFAULT_DISCORD_TOKEN:-}
HERMES_DEFAULT_SLACK_TOKEN=

# ── Tokens de mensajería — Agente Coder ─────────────────────
HERMES_CODER_TELEGRAM_TOKEN=${HERMES_CODER_TELEGRAM_TOKEN:-}
HERMES_CODER_DISCORD_TOKEN=${HERMES_CODER_DISCORD_TOKEN:-}

# ── Tokens de mensajería — Agente Researcher ────────────────
HERMES_RESEARCHER_TELEGRAM_TOKEN=${HERMES_RESEARCHER_TELEGRAM_TOKEN:-}
HERMES_RESEARCHER_DISCORD_TOKEN=${HERMES_RESEARCHER_DISCORD_TOKEN:-}

# ── Tokens de mensajería — Agente Assistant ─────────────────
HERMES_ASSISTANT_TELEGRAM_TOKEN=${HERMES_ASSISTANT_TELEGRAM_TOKEN:-}
HERMES_ASSISTANT_DISCORD_TOKEN=${HERMES_ASSISTANT_DISCORD_TOKEN:-}
EOF

    chmod 600 "${ENV_FILE}"
    log_ok "Archivo .env generado en ${ENV_FILE}"

    # Guardar las keys para mostrarlas al final
    SUMMARY_DEFAULT_KEY="${default_key}"
    SUMMARY_CODER_KEY="${coder_key}"
    SUMMARY_RESEARCHER_KEY="${researcher_key}"
    SUMMARY_ASSISTANT_KEY="${assistant_key}"
}

# ── Paso 6: Construir imagen Docker ───────────────────────────
build_docker_image() {
    if [[ "${SKIP_BUILD}" == "true" ]]; then
        log_step "Build omitido (--skip-build)"
        return
    fi

    log_step "Construyendo imagen Docker personalizada"
    log_info "Esto puede tardar varios minutos en la primera ejecución..."
    echo ""

    cd "${PROJECT_DIR}"
    docker compose build --no-cache 2>&1 | while IFS= read -r line; do
        echo "    ${line}"
    done

    log_ok "Imagen construida: hermes-agent-custom:latest"
}

# ── Paso 7: Mostrar resumen ───────────────────────────────────
show_summary() {
    log_step "Configuración completada"
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                  RESUMEN DE CONFIGURACIÓN                ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}  AGENTES Y ENDPOINTS:${NC}"
    echo ""
    echo -e "  ${CYAN}hermes-default${NC}"
    echo "    API:       http://localhost:8642/v1"
    echo "    Dashboard: http://localhost:9119"
    echo "    API Key:   ${SUMMARY_DEFAULT_KEY:0:20}..."
    echo ""
    echo -e "  ${CYAN}hermes-coder${NC} (activa con --profile coder)"
    echo "    API:       http://localhost:8643/v1"
    echo "    Dashboard: http://localhost:9120"
    echo ""
    echo -e "  ${CYAN}hermes-researcher${NC} (activa con --profile researcher)"
    echo "    API:       http://localhost:8644/v1"
    echo "    Dashboard: http://localhost:9121"
    echo ""
    echo -e "  ${CYAN}hermes-assistant${NC} (activa con --profile assistant)"
    echo "    API:       http://localhost:8645/v1"
    echo "    Dashboard: http://localhost:9122"
    echo ""
    echo -e "${BOLD}  COMANDOS PARA INICIAR:${NC}"
    echo ""
    echo "    # Solo agente default:"
    echo "    docker compose up -d"
    echo ""
    echo "    # Default + coder:"
    echo "    docker compose --profile coder up -d"
    echo ""
    echo "    # Todos los agentes + proxy nginx:"
    echo "    docker compose --profile all --profile proxy up -d"
    echo ""
    echo "    # Ver logs:"
    echo "    docker compose logs -f hermes-default"
    echo ""
    echo "    # Añadir nuevo perfil en el futuro:"
    echo "    ./scripts/create-profile.sh --name mi-agente --port 8646"
    echo ""
    echo -e "${BOLD}  ARCHIVOS IMPORTANTES:${NC}"
    echo "    .env              → Variables de entorno y API keys"
    echo "    data/default/     → Datos del agente default"
    echo "    profiles/*/SOUL.md → Personalidad de cada agente"
    echo ""
    echo -e "${YELLOW}  ⚠  Agrega .env a tu .gitignore antes de commitear.${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────
main() {
    banner
    check_prerequisites
    create_data_directories
    collect_api_keys
    collect_messaging_tokens
    generate_env_file
    build_docker_image
    show_summary
}

# Guardar variables de resumen
SUMMARY_DEFAULT_KEY=""
SUMMARY_CODER_KEY=""
SUMMARY_RESEARCHER_KEY=""
SUMMARY_ASSISTANT_KEY=""
HERMES_DEFAULT_TELEGRAM_TOKEN=""
HERMES_DEFAULT_DISCORD_TOKEN=""
HERMES_CODER_TELEGRAM_TOKEN=""
HERMES_CODER_DISCORD_TOKEN=""
HERMES_RESEARCHER_TELEGRAM_TOKEN=""
HERMES_RESEARCHER_DISCORD_TOKEN=""
HERMES_ASSISTANT_TELEGRAM_TOKEN=""
HERMES_ASSISTANT_DISCORD_TOKEN=""

main "$@"
