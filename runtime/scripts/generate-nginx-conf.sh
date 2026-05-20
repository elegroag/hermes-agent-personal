#!/usr/bin/env bash
# ============================================================
# generate-nginx-conf.sh — Generar nginx.conf desde template
#
# Genera la configuración de nginx basada en los perfiles
# activos en docker-compose.yml.
#
# Uso:
#   ./scripts/generate-nginx-conf.sh
#   ./scripts/generate-nginx-conf.sh --dry-run
# ============================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NGINX_CONF="${PROJECT_DIR}/nginx/nginx.conf"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Uso: $0 [--dry-run]"
            echo "  --dry-run  Solo muestra el resultado sin escribir"
            exit 0
            ;;
        *) shift ;;
    esac
done

# ── Perfiles activos (desde docker-compose.yml) ──────────────
# Extrae solo servicios hermes- que no sean nginx-proxy
PROFILES=$(grep -E '^\s+hermes-' "${PROJECT_DIR}/docker-compose.yml" 2>/dev/null | \
    sed -E 's/^\s+hermes-([a-z]+).*/\1/' | grep -v '^nginx$' | sort -u || echo "leader coder researcher assistant reviewer")

# ── Generar upstream blocks ────────────────────────────────────
generate_upstreams() {
    local upstreams=""
    for profile in $PROFILES; do
        local keepalive=8
        [[ "$profile" == "leader" ]] && keepalive=16

        upstreams+="    upstream hermes_${profile} {
        server hermes-${profile}:8642;
        keepalive ${keepalive};
    }
"
    done

    # Dashboard para leader
    upstreams+="    upstream hermes_leader_dashboard {
        server hermes-leader:9119;
        keepalive 4;
    }
"
    echo "$upstreams"
}

# ── Generar location blocks ─────────────────────────────────────
generate_locations() {
    local locations=""

    for profile in $PROFILES; do
        if [[ "$profile" == "leader" ]]; then
            locations+="
        # Leader (API principal — alias /v1 y /leader)
        location /v1/ {
            proxy_pass http://hermes_leader/v1/;
            proxy_buffering off;
            proxy_cache    off;
            proxy_http_version 1.1;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
        }

        location /leader/ {
            rewrite ^/leader/(.*)$ /\$1 break;
            proxy_pass http://hermes_leader;
            proxy_buffering off;
            proxy_cache    off;
            proxy_http_version 1.1;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
        }
"
        else
            locations+="
        # ${profile^}
        location /${profile}/ {
            rewrite ^/${profile}/(.*)$ /\$1 break;
            proxy_pass http://hermes_${profile};
            proxy_buffering off;
            proxy_cache    off;
            proxy_http_version 1.1;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
        }
"
        fi
    done

    echo "$locations"
}

# ── Template de nginx.conf ─────────────────────────────────────
generate_config() {
    local upstreams=$(generate_upstreams)
    local locations=$(generate_locations)

    cat << NGINX_CONF
# ==============================================================
# nginx.conf — Reverse Proxy Hermes Agent Multi-Agente
# GENERADO AUTOMÁTICAMENTE — NO EDITAR MANUALMENTE
# Editar: scripts/generate-nginx-conf.sh.template o profiles/
#
# Rutas:
#   /v1/*           → hermes-leader (alias principal)
#   /leader/*       → hermes-leader:8642
#   /coder/*        → hermes-coder:8642
#   /researcher/*   → hermes-researcher:8642
#   /assistant/*    → hermes-assistant:8642
#   /reviewer/*     → hermes-reviewer:8642
#   /dashboard/*    → hermes-leader:9119 (dashboard)
#   /nginx-health   → liveness del proxy
# ==============================================================

events {
    worker_connections 1024;
}

http {
    log_format main '\$remote_addr [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent upstream="\$upstream_addr"';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;

    proxy_read_timeout    600s;
    proxy_connect_timeout  10s;
    proxy_send_timeout    600s;

    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

${upstreams}
    server {
        listen 80;
        server_name _;

        location /nginx-health {
            access_log off;
            return 200 "healthy\\n";
            add_header Content-Type text/plain;
        }
${locations}
        # Dashboard (WebSocket)
        location /dashboard/ {
            rewrite ^/dashboard/(.*)$ /\$1 break;
            proxy_pass http://hermes_leader_dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade    \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
NGINX_CONF
}

# ── Ejecutar ────────────────────────────────────────────────────
CONFIG=$(generate_config)

if [[ "${DRY_RUN}" == true ]]; then
    echo "$CONFIG"
else
    echo "$CONFIG" > "${NGINX_CONF}"
    chmod 644 "${NGINX_CONF}"
    echo -e "${BOLD}${GREEN}✓${NC} nginx.conf regenerado ($(echo "$PROFILES" | wc -w) perfiles)"
    echo "  ${NGINX_CONF}"
fi