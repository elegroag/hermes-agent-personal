#!/usr/bin/env bash
# ============================================================
# create-profile.sh — Crear un nuevo perfil de agente Hermes
#
# Genera los archivos necesarios para añadir un agente nuevo
# al docker-compose sin modificarlo manualmente.
#
# Uso:
#   ./scripts/create-profile.sh --name mi-agente --port 8646
#   ./scripts/create-profile.sh --name analista --port 8647 --model anthropic/claude-opus-4
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argumentos ────────────────────────────────────────────────
PROFILE_NAME=""
API_PORT=""
DASH_PORT=""
MODEL="anthropic/claude-sonnet-4"
BASE_SOUL="default"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)   PROFILE_NAME="$2"; shift 2 ;;
        --port)   API_PORT="$2"; shift 2 ;;
        --dash)   DASH_PORT="$2"; shift 2 ;;
        --model)  MODEL="$2"; shift 2 ;;
        --clone)  BASE_SOUL="$2"; shift 2 ;;
        --help|-h)
            echo "Uso: $0 --name <nombre> --port <puerto-api> [--dash <puerto-dashboard>] [--model <modelo>]"
            echo "Ejemplo: $0 --name analista --port 8646 --model anthropic/claude-opus-4"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# ── Validar argumentos requeridos ─────────────────────────────
if [[ -z "${PROFILE_NAME}" ]]; then
    echo -e "${RED}Error: --name es requerido${NC}"
    exit 1
fi

if [[ -z "${API_PORT}" ]]; then
    echo -e "${RED}Error: --port es requerido${NC}"
    exit 1
fi

# Puerto del dashboard = API port + 477 (convención del proyecto)
DASH_PORT="${DASH_PORT:-$(( API_PORT + 477 ))}"

# Validar que el nombre solo tenga caracteres válidos
if ! echo "${PROFILE_NAME}" | grep -qE '^[a-z0-9-]+$'; then
    echo -e "${RED}Error: el nombre solo puede contener letras minúsculas, números y guiones${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}${BLUE}▸ Creando perfil '${PROFILE_NAME}'${NC}"

# ── Crear directorio de datos ─────────────────────────────────
PROFILE_DATA="${PROJECT_DIR}/data/${PROFILE_NAME}"
mkdir -p "${PROFILE_DATA}"/{memories,skills,sessions,cron,logs,hooks}
chmod 700 "${PROFILE_DATA}"
echo -e "  ${GREEN}✓${NC} Directorio de datos: ${PROFILE_DATA}"

# ── Copiar template SOUL.md desde perfil base ─────────────────
SOURCE_SOUL="${PROJECT_DIR}/profiles/${BASE_SOUL}/SOUL.md"
if [[ -f "${SOURCE_SOUL}" ]]; then
    cp "${SOURCE_SOUL}" "${PROJECT_DIR}/profiles/${PROFILE_NAME}/SOUL.md" 2>/dev/null || {
        mkdir -p "${PROJECT_DIR}/profiles/${PROFILE_NAME}"
        cp "${SOURCE_SOUL}" "${PROJECT_DIR}/profiles/${PROFILE_NAME}/SOUL.md"
    }
    echo -e "  ${GREEN}✓${NC} SOUL.md copiado desde '${BASE_SOUL}'"
fi

# ── Crear config.yaml para el nuevo perfil ────────────────────
mkdir -p "${PROJECT_DIR}/profiles/${PROFILE_NAME}"
cat > "${PROJECT_DIR}/profiles/${PROFILE_NAME}/config.yaml" << EOF
# ============================================================
# config.yaml — Perfil: ${PROFILE_NAME}
# Generado por create-profile.sh el $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

model:
  default: "${MODEL}"
  fallback_providers: []

terminal:
  backend: local
  cwd: /workspace
  timeout: 180

memory:
  enabled: true
  max_memories: 500

tools:
  enabled: true

compression:
  enabled: true
  threshold: 50000
EOF
echo -e "  ${GREEN}✓${NC} config.yaml creado para perfil '${PROFILE_NAME}'"

# ── Generar bloque docker-compose para el nuevo perfil ────────
COMPOSE_BLOCK="
  # ── Agente: ${PROFILE_NAME} ──────────────────────────────
  hermes-${PROFILE_NAME}:
    build:
      context: .
      dockerfile: Dockerfile
    image: hermes-agent-custom:latest
    container_name: hermes-${PROFILE_NAME}
    hostname: hermes-${PROFILE_NAME}
    restart: unless-stopped
    command: gateway run
    profiles: [\"${PROFILE_NAME}\", \"all\"]

    environment:
      HERMES_PROFILE: \"${PROFILE_NAME}\"
      HERMES_HOME: \"/opt/data\"
      ANTHROPIC_API_KEY:  \${ANTHROPIC_API_KEY:-}
      OPENAI_API_KEY:     \${OPENAI_API_KEY:-}
      OPENROUTER_API_KEY: \${OPENROUTER_API_KEY:-}
      API_SERVER_ENABLED: \"true\"
      API_SERVER_HOST:    \"0.0.0.0\"
      API_SERVER_PORT:    \"8642\"
      API_SERVER_KEY:     \${HERMES_$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY:?Requerido}
      HERMES_DASHBOARD:      \${HERMES_DASHBOARD:-1}
      HERMES_DASHBOARD_HOST: \"0.0.0.0\"
      HERMES_DASHBOARD_PORT: \"9119\"
      TELEGRAM_TOKEN: \${HERMES_$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_TELEGRAM_TOKEN:-}
      DISCORD_TOKEN:  \${HERMES_$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_DISCORD_TOKEN:-}

    ports:
      - \"\${HERMES_$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_PORT:-${API_PORT}}:8642\"
      - \"\${HERMES_$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_DASH_PORT:-${DASH_PORT}}:9119\"

    volumes:
      - ./data/${PROFILE_NAME}:/opt/data
      - /var/run/docker.sock:/var/run/docker.sock:ro

    networks:
      - hermes-net

    healthcheck:
      test: [\"/opt/healthcheck.sh\"]
      interval: 30s
      timeout: 10s
      start_period: 60s
      retries: 3
"

# ── Generar variables .env para el nuevo perfil ───────────────
NEW_API_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
UPPER_NAME=$(echo "${PROFILE_NAME}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

ENV_ADDITIONS="
# ── Agente: ${PROFILE_NAME} ──────────────────────────────────
HERMES_${UPPER_NAME}_API_KEY=${NEW_API_KEY}
HERMES_${UPPER_NAME}_API_PORT=${API_PORT}
HERMES_${UPPER_NAME}_DASH_PORT=${DASH_PORT}
HERMES_${UPPER_NAME}_TELEGRAM_TOKEN=
HERMES_${UPPER_NAME}_DISCORD_TOKEN=
"

if [[ -f "${PROJECT_DIR}/.env" ]]; then
    echo "${ENV_ADDITIONS}" >> "${PROJECT_DIR}/.env"
    echo -e "  ${GREEN}✓${NC} Variables añadidas a .env"
else
    echo -e "  ${YELLOW}⚠${NC} .env no encontrado — ejecuta post-setup.sh primero"
fi

# ── Guardar bloque compose en archivo de referencia ───────────
COMPOSE_SNIPPET="${PROJECT_DIR}/data/${PROFILE_NAME}/docker-compose-snippet.yml"
echo "${COMPOSE_BLOCK}" > "${COMPOSE_SNIPPET}"

echo ""
echo -e "${BOLD}${GREEN}✓ Perfil '${PROFILE_NAME}' creado exitosamente${NC}"
echo ""
echo -e "  ${BOLD}Siguiente paso:${NC}"
echo "  Añade el siguiente bloque a tu docker-compose.yml"
echo "  bajo la sección 'services:'"
echo ""
echo -e "${CYAN}$(cat "${COMPOSE_SNIPPET}")${NC}"
echo ""
echo "  El snippet también está guardado en:"
echo "  ${COMPOSE_SNIPPET}"
echo ""
echo -e "  ${BOLD}Para iniciar el agente:${NC}"
echo "  docker compose --profile ${PROFILE_NAME} up -d hermes-${PROFILE_NAME}"
echo ""
