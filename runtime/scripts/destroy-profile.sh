#!/usr/bin/env bash
# ============================================================
# destroy-profile.sh — Eliminar un perfil de agente Hermes
#
# Uso:
#   ./scripts/destroy-profile.sh --name mi-agente
#   ./scripts/destroy-profile.sh --name mi-agente --remove-data
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argumentos ────────────────────────────────────────────────
PROFILE_NAME=""
REMOVE_DATA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)         PROFILE_NAME="$2"; shift 2 ;;
        --remove-data)  REMOVE_DATA=true; shift ;;
        --help|-h)
            echo "Uso: $0 --name <nombre> [--remove-data]"
            echo ""
            echo "  --name         Nombre del perfil a eliminar"
            echo "  --remove-data  También elimina datos y configuración del perfil"
            exit 0
            ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# ── Validar argumentos ─────────────────────────────────────────
if [[ -z "${PROFILE_NAME}" ]]; then
    echo -e "${RED}Error: --name es requerido${NC}"
    exit 1
fi

VALID_PROFILES=("leader" "coder" "researcher" "assistant" "reviewer")
if [[ ! " ${VALID_PROFILES[*]} " =~ " ${PROFILE_NAME} " ]]; then
    echo -e "${RED}Error: perfil '${PROFILE_NAME}' no es un perfil del sistema${NC}"
    echo "  Perfiles del sistema: ${VALID_PROFILES[*]}"
    exit 1
fi

if [[ "${PROFILE_NAME}" == "leader" ]]; then
    echo -e "${RED}Error: no se puede eliminar el perfil 'leader' — es requerido${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}${RED}▸ Eliminando perfil '${PROFILE_NAME}'${NC}"

# ── Detener contenedor si está corriendo ──────────────────────
if docker ps --format '{{.Names}}' | grep -q "^hermes-${PROFILE_NAME}$"; then
    echo -e "  ${YELLOW}⚠${NC} Contenedor '${PROFILE_NAME}' está corriendo — deteniendo..."
    docker stop "hermes-${PROFILE_NAME}" 2>/dev/null || true
    docker rm "hermes-${PROFILE_NAME}" 2>/dev/null || true
fi

# ── Eliminar volumen de datos ─────────────────────────────────
if [[ -d "${PROJECT_DIR}/data/${PROFILE_NAME}" ]]; then
    if [[ "${REMOVE_DATA}" == true ]]; then
        echo -e "  ${RED}✗${NC} Eliminando directorio de datos..."
        rm -rf "${PROJECT_DIR}/data/${PROFILE_NAME}"
    else
        echo -e "  ${YELLOW}⚠${NC} Directorio de datos preservado en ./data/${PROFILE_NAME}"
    fi
fi

# ── Eliminar profile config ────────────────────────────────────
if [[ -d "${PROJECT_DIR}/profiles/${PROFILE_NAME}" ]]; then
    if [[ "${REMOVE_DATA}" == true ]]; then
        echo -e "  ${RED}✗${NC} Eliminando configuración del perfil..."
        rm -rf "${PROJECT_DIR}/profiles/${PROFILE_NAME}"
    else
        echo -e "  ${YELLOW}⚠${NC} Perfil conservado en ./profiles/${PROFILE_NAME}"
    fi
fi

# ── Regenerar nginx.conf si existe ────────────────────────────
if [[ -x "${SCRIPT_DIR}/generate-nginx-conf.sh" ]]; then
    echo -e "  ${BLUE}▸${NC} Regenerando nginx.conf..."
    "${SCRIPT_DIR}/generate-nginx-conf.sh" 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${GREEN}✓ Perfil '${PROFILE_NAME}' eliminado${NC}"
echo ""
echo -e "  Nota: El bloque de docker-compose.yml para '${PROFILE_NAME}'"
echo "        debe removerse manualmente del archivo."
echo ""