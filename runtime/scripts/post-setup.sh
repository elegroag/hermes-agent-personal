#!/usr/bin/env bash
# ==============================================================
# post-setup.sh — Configuración inicial del equipo Hermes Agent
#
# Ejecutar UNA SOLA VEZ después de clonar el repositorio.
#
# Responsabilidades:
#   1. Verificar prerequisitos (Docker, Compose v2, openssl)
#   2. Crear estructura de directorios de datos por perfil
#   3. Solicitar API keys de proveedores LLM
#   4. Generar API keys de seguridad para cada agente
#   5. Generar archivo .env completo
#   6. Construir imagen Docker personalizada
#   7. Mostrar resumen de endpoints del equipo
#
# Uso:
#   chmod +x scripts/post-setup.sh
#   ./scripts/post-setup.sh
#   ./scripts/post-setup.sh --skip-build
# ==============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

# Perfiles del equipo
PROFILES=(leader coder researcher assistant reviewer)

SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --help|-h) echo "Uso: $0 [--skip-build]"; exit 0 ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

log_step() { echo -e "\n${BOLD}${BLUE}▸ $*${NC}"; }
log_ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
log_err()  { echo -e "  ${RED}✗${NC} $*" >&2; }

ask_secret() {
    local result
    read -rsp "  $1: " result; echo ""
    echo "${result}"
}

gen_key() {
    openssl rand -hex 32 2>/dev/null || \
    python3 -c "import secrets; print(secrets.token_hex(32))"
}

# ── 1. Prerequisitos ──────────────────────────────────────────
log_step "Verificando prerequisitos"

command -v docker    &>/dev/null || { log_err "Docker no encontrado"; exit 1; }
docker compose version &>/dev/null || { log_err "Docker Compose v2 no encontrado"; exit 1; }
command -v openssl   &>/dev/null || log_warn "openssl no encontrado — se usará Python para claves"

log_ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
log_ok "Docker Compose $(docker compose version --short 2>/dev/null || echo '2.x')"

# ── 2. Estructura de directorios ──────────────────────────────
log_step "Creando estructura de datos por perfil"

for profile in "${PROFILES[@]}"; do
    dir="${PROJECT_DIR}/data/${profile}"
    mkdir -p "${dir}"/{memories,skills,sessions,cron,logs,hooks}
    chmod 700 "${dir}"
    log_ok "Perfil '${profile}': ${dir}"
done

# ── 3. Recopilar API keys de LLM ─────────────────────────────
log_step "Configuración de proveedores LLM"
echo ""
echo "  Configura al menos UN proveedor. Presiona Enter para omitir."
echo ""

ANTHROPIC_API_KEY=$(ask_secret "Anthropic API Key (sk-ant-...)")
OPENAI_API_KEY=$(ask_secret    "OpenAI API Key (sk-...)")
OPENROUTER_API_KEY=$(ask_secret "OpenRouter API Key (sk-or-...)")

if [[ -z "${ANTHROPIC_API_KEY}" ]] && \
   [[ -z "${OPENAI_API_KEY}" ]]    && \
   [[ -z "${OPENROUTER_API_KEY}" ]]; then
    log_warn "Sin proveedor LLM — los agentes no podrán inferir hasta configurar uno"
fi

# ── 4. Git / registros privados (opcionales) ──────────────────
log_step "Tokens de registros privados (opcionales)"
echo ""
GITHUB_TOKEN=$(ask_secret "GitHub Token (para repos privados / hermes-coder)")
NPM_TOKEN=$(ask_secret    "NPM Token (para paquetes privados / hermes-coder)")

# ── 5. Tokens de mensajería (opcionales) ──────────────────────
log_step "Tokens de mensajería por agente (opcionales — Enter para omitir)"
echo ""

declare -A TELEGRAM_TOKENS DISCORD_TOKENS SLACK_TOKENS
for profile in "${PROFILES[@]}"; do
    echo -e "  ${BOLD}${profile}:${NC}"
    TELEGRAM_TOKENS[$profile]=$(ask_secret "  Telegram Token")
    DISCORD_TOKENS[$profile]=$(ask_secret  "  Discord Token")
done
echo -e "  ${BOLD}leader / assistant Slack:${NC}"
SLACK_LEADER=$(ask_secret    "  Slack Token (leader)")
SLACK_ASSISTANT=$(ask_secret "  Slack Token (assistant)")

# ── 6. Generar API keys de seguridad ─────────────────────────
log_step "Generando API keys de seguridad"

declare -A API_KEYS
for profile in "${PROFILES[@]}"; do
    API_KEYS[$profile]=$(gen_key)
    log_ok "hermes-${profile}: ${API_KEYS[$profile]:0:16}..."
done

cat > "${ENV_FILE}" << ENV
# ==============================================================
# Hermes Agent — Variables de Entorno
# Generado por post-setup.sh el $(date '+%Y-%m-%d %H:%M:%S')
# NO commitear este archivo.
# ==============================================================

# ── Proveedores LLM ───────────────────────────────────────────
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}

# ── Git / registros privados ──────────────────────────────────
GITHUB_TOKEN=${GITHUB_TOKEN:-}
NPM_TOKEN=${NPM_TOKEN:-}

# ── API Keys internas (generadas automáticamente) ────────────
HERMES_LEADER_API_KEY=${API_KEYS[leader]}
HERMES_CODER_API_KEY=${API_KEYS[coder]}
HERMES_RESEARCHER_API_KEY=${API_KEYS[researcher]}
HERMES_ASSISTANT_API_KEY=${API_KEYS[assistant]}
HERMES_REVIEWER_API_KEY=${API_KEYS[reviewer]}

# ── Puertos host ──────────────────────────────────────────────
HERMES_LEADER_API_PORT=8642
HERMES_LEADER_DASH_PORT=9119
HERMES_CODER_API_PORT=8643
HERMES_CODER_DASH_PORT=9120
HERMES_RESEARCHER_API_PORT=8644
HERMES_RESEARCHER_DASH_PORT=9121
HERMES_ASSISTANT_API_PORT=8645
HERMES_ASSISTANT_DASH_PORT=9122
HERMES_REVIEWER_API_PORT=8646
HERMES_REVIEWER_DASH_PORT=9123

# ── Nginx ─────────────────────────────────────────────────────
PROXY_HTTP_PORT=80
PROXY_HTTPS_PORT=443

# ── General ───────────────────────────────────────────────────
HERMES_DASHBOARD=1
API_CORS_ORIGINS=http://localhost

# ── Mensajería — Leader ───────────────────────────────────────
HERMES_LEADER_TELEGRAM_TOKEN=${TELEGRAM_TOKENS[leader]:-}
HERMES_LEADER_DISCORD_TOKEN=${DISCORD_TOKENS[leader]:-}
HERMES_LEADER_SLACK_TOKEN=${SLACK_LEADER:-}

# ── Mensajería — Coder ────────────────────────────────────────
HERMES_CODER_TELEGRAM_TOKEN=${TELEGRAM_TOKENS[coder]:-}
HERMES_CODER_DISCORD_TOKEN=${DISCORD_TOKENS[coder]:-}

# ── Mensajería — Researcher ───────────────────────────────────
HERMES_RESEARCHER_TELEGRAM_TOKEN=${TELEGRAM_TOKENS[researcher]:-}
HERMES_RESEARCHER_DISCORD_TOKEN=${DISCORD_TOKENS[researcher]:-}

# ── Mensajería — Assistant ────────────────────────────────────
HERMES_ASSISTANT_TELEGRAM_TOKEN=${TELEGRAM_TOKENS[assistant]:-}
HERMES_ASSISTANT_DISCORD_TOKEN=${DISCORD_TOKENS[assistant]:-}
HERMES_ASSISTANT_SLACK_TOKEN=${SLACK_ASSISTANT:-}

# ── Mensajería — Reviewer ─────────────────────────────────────
HERMES_REVIEWER_TELEGRAM_TOKEN=${TELEGRAM_TOKENS[reviewer]:-}
HERMES_REVIEWER_DISCORD_TOKEN=${DISCORD_TOKENS[reviewer]:-}
ENV

chmod 600 "${ENV_FILE}"
log_ok ".env generado en ${ENV_FILE}"

# ── 7. Build Docker ───────────────────────────────────────────
if [[ "${SKIP_BUILD}" == "true" ]]; then
    log_step "Build omitido (--skip-build)"
else
    log_step "Construyendo imagen Docker"
    log_warn "Primera vez puede tardar 15-20 min (compilación de Ruby y Node.js)"
    echo ""
    cd "${PROJECT_DIR}"
    DOCKER_BUILDKIT=1 docker compose build 2>&1 | while IFS= read -r line; do
        echo "    ${line}"
    done
    log_ok "Imagen construida: hermes-agent-custom:latest"
fi

# ── 8. Resumen ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║             EQUIPO HERMES AGENT — LISTO                     ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}AGENTES Y ENDPOINTS:${NC}"
echo ""

declare -A ROLES=(
    [leader]="Orquestador Kanban    "
    [coder]="Implementador          "
    [researcher]="Investigador       "
    [assistant]="Asistente operativo"
    [reviewer]="Quality Gate        "
)
declare -A PORTS=([leader]=8642 [coder]=8643 [researcher]=8644 [assistant]=8645 [reviewer]=8646)
declare -A DPORTS=([leader]=9119 [coder]=9120 [researcher]=9121 [assistant]=9122 [reviewer]=9123)

for profile in "${PROFILES[@]}"; do
    echo -e "  ${CYAN}hermes-${profile}${NC} — ${ROLES[$profile]}"
    echo "    API:       http://localhost:${PORTS[$profile]}/v1"
    echo "    Dashboard: http://localhost:${DPORTS[$profile]}"
    echo "    API Key:   ${API_KEYS[$profile]:0:16}..."
    echo ""
done

echo -e "  ${BOLD}INICIAR EL EQUIPO:${NC}"
echo ""
echo "    # Solo el líder:"
echo "    docker compose up -d"
echo ""
echo "    # Equipo completo:"
echo "    docker compose --profile team up -d"
echo ""
echo "    # Equipo completo + proxy nginx:"
echo "    docker compose --profile full up -d"
echo ""
echo "    # Ver logs del líder:"
echo "    docker compose logs -f hermes-leader"
echo ""
echo -e "  ${YELLOW}⚠  .env contiene secretos — ya está en .gitignore${NC}"
echo ""
