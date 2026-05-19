#!/usr/bin/env bash
# ============================================================
# healthcheck.sh — Verificación de salud del contenedor
#
# Estrategia (en orden):
#   1. Verificar que el proceso hermes esté corriendo
#   2. Si API_SERVER_ENABLED=true, verificar el endpoint HTTP
#   3. Verificar que el directorio de datos sea accesible
# ============================================================
set -uo pipefail

API_PORT="${API_SERVER_PORT:-8642}"
API_KEY="${API_SERVER_KEY:-}"

# ── 1. Verificar proceso hermes ─────────────────────────────
if ! pgrep -f "hermes" > /dev/null 2>&1; then
    echo "UNHEALTHY: proceso hermes no encontrado"
    exit 1
fi

# ── 2. Verificar endpoint HTTP si el API server está activo ─
if [[ "${API_SERVER_ENABLED:-false}" == "true" ]]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        -H "Authorization: Bearer ${API_KEY}" \
        "http://localhost:${API_PORT}/health" 2>/dev/null || echo "000")

    if [[ "${HTTP_STATUS}" == "200" ]] || [[ "${HTTP_STATUS}" == "401" ]]; then
        # 401 = server activo pero key inválida en healthcheck (aceptable)
        echo "HEALTHY: API server respondiendo (HTTP ${HTTP_STATUS})"
        exit 0
    fi

    # Fallback: verificar que el puerto esté escuchando
    if nc -z localhost "${API_PORT}" 2>/dev/null; then
        echo "HEALTHY: puerto ${API_PORT} accesible"
        exit 0
    fi

    echo "DEGRADED: API server no responde en puerto ${API_PORT}"
    exit 1
fi

# ── 3. Verificar acceso al directorio de datos ──────────────
HERMES_HOME="${HERMES_HOME:-/opt/data}"
if [[ -d "${HERMES_HOME}" ]] && [[ -w "${HERMES_HOME}" ]]; then
    echo "HEALTHY: proceso activo y datos accesibles"
    exit 0
fi

echo "UNHEALTHY: directorio de datos no accesible: ${HERMES_HOME}"
exit 1
