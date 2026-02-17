#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST="134.209.14.175"
SSH_USER="root"
SSH_PORT="22"
DOMAIN="ground.zerok.cloud"
PUBLIC_URL=""
BIND="127.0.0.1:7878"
BOOTSTRAP=""
REMOTE_DIR="/opt/antenna-relay"
SERVICE_NAME="antenna-relay"
CERTBOT_EMAIL=""

log() {
  printf '[deploy-relay] %s\n' "$*"
}

usage() {
  cat <<'EOF'
Deploy Antenna relay over SSH with systemd + public routing wiring.

Routing mode is auto-detected:
- Kubernetes/Traefik ingress (preferred when available)
- Caddy
- Nginx

Usage:
  scripts/deploy-relay.sh [options]

Options:
  --host <ip-or-host>            SSH host (default: 134.209.14.175)
  --user <ssh-user>              SSH user (default: root)
  --port <ssh-port>              SSH port (default: 22)
  --domain <fqdn>                Public relay domain (default: ground.zerok.cloud)
  --public-url <url>             Relay public URL (default: https://<domain>)
  --bind <host:port>             Relay bind address (default: 127.0.0.1:7878)
  --bootstrap <csv-urls>         Bootstrap relay URLs (optional)
  --remote-dir <path>            Remote install directory (default: /opt/antenna-relay)
  --service-name <name>          systemd service name (default: antenna-relay)
  --certbot-email <email>        Optional email to auto-issue TLS cert via certbot
  -h, --help                     Show this help

Examples:
  scripts/deploy-relay.sh

  scripts/deploy-relay.sh \
    --host 134.209.14.175 \
    --user root \
    --domain ground.zerok.cloud \
    --bootstrap https://relay-a.example.com,https://relay-b.example.com
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:?missing value for --host}"
      shift 2
      ;;
    --user)
      SSH_USER="${2:?missing value for --user}"
      shift 2
      ;;
    --port)
      SSH_PORT="${2:?missing value for --port}"
      shift 2
      ;;
    --domain)
      DOMAIN="${2:?missing value for --domain}"
      shift 2
      ;;
    --public-url)
      PUBLIC_URL="${2:?missing value for --public-url}"
      shift 2
      ;;
    --bind)
      BIND="${2:?missing value for --bind}"
      shift 2
      ;;
    --bootstrap)
      BOOTSTRAP="${2:?missing value for --bootstrap}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:?missing value for --remote-dir}"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="${2:?missing value for --service-name}"
      shift 2
      ;;
    --certbot-email)
      CERTBOT_EMAIL="${2:?missing value for --certbot-email}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${PUBLIC_URL}" ]]; then
  PUBLIC_URL="https://${DOMAIN}"
fi

BIND_HOST="${BIND%:*}"
BIND_PORT="${BIND##*:}"

if [[ ! -d "${REPO_ROOT}/rust/antenna-relay" ]]; then
  echo "Expected rust/antenna-relay in repo root, got: ${REPO_ROOT}" >&2
  exit 1
fi

for cmd in ssh scp rsync; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
done

SSH_TARGET="${SSH_USER}@${HOST}"
SSH_ARGS=(-p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new)
SCP_ARGS=(-P "${SSH_PORT}" -o StrictHostKeyChecking=accept-new)
RSYNC_SSH="ssh -p ${SSH_PORT} -o StrictHostKeyChecking=accept-new"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ENV_FILE="${TMP_DIR}/${SERVICE_NAME}.env"
SERVICE_FILE="${TMP_DIR}/${SERVICE_NAME}.service"
NGINX_FILE="${TMP_DIR}/${DOMAIN}.nginx.conf"
CADDY_FILE="${TMP_DIR}/${DOMAIN}.caddy"
K8S_FILE="${TMP_DIR}/${SERVICE_NAME}-${DOMAIN}.k8s.yaml"
K8S_SERVICE_NAME="${SERVICE_NAME}-external"
K8S_INGRESS_NAME="${SERVICE_NAME}-${DOMAIN//./-}"

cat > "${ENV_FILE}" <<EOF
ANTENNA_RELAY_BIND=${BIND}
ANTENNA_RELAY_PUBLIC_URL=${PUBLIC_URL}
ANTENNA_RELAY_BOOTSTRAP=${BOOTSTRAP}
RUST_LOG=info,antenna_relay=debug
EOF

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Antenna Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=antenna-relay
Group=antenna-relay
WorkingDirectory=${REMOTE_DIR}
EnvironmentFile=-/etc/default/${SERVICE_NAME}
ExecStart=${REMOTE_DIR}/bin/antenna-relay
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > "${NGINX_FILE}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://${BIND};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

cat > "${CADDY_FILE}" <<EOF
${DOMAIN} {
    reverse_proxy ${BIND}
}
EOF

cat > "${K8S_FILE}" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${K8S_SERVICE_NAME}
  namespace: default
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: ${BIND_PORT}
---
apiVersion: v1
kind: Endpoints
metadata:
  name: ${K8S_SERVICE_NAME}
  namespace: default
subsets:
- addresses:
  - ip: ${HOST}
  ports:
  - name: http
    port: ${BIND_PORT}
    protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${K8S_INGRESS_NAME}
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
spec:
  ingressClassName: traefik
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${K8S_SERVICE_NAME}
            port:
              number: 80
EOF

log "Checking SSH connectivity to ${SSH_TARGET}:${SSH_PORT}"
ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "echo connected >/dev/null"

log "Preparing remote directories and service account"
ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
id -u antenna-relay >/dev/null 2>&1 || useradd --system --home '${REMOTE_DIR}' --shell /usr/sbin/nologin antenna-relay
mkdir -p '${REMOTE_DIR}/src' '${REMOTE_DIR}/bin'
EOF

log "Syncing relay sources"
rsync -az --delete --exclude target -e "${RSYNC_SSH}" \
  "${REPO_ROOT}/rust/antenna-relay/" \
  "${SSH_TARGET}:${REMOTE_DIR}/src/antenna-relay/"
rsync -az --delete --exclude target -e "${RSYNC_SSH}" \
  "${REPO_ROOT}/rust/antenna-protocol/" \
  "${SSH_TARGET}:${REMOTE_DIR}/src/antenna-protocol/"

log "Building release binary on remote host"
ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
if [ -x "\$HOME/.cargo/bin/cargo" ]; then
  export PATH="\$HOME/.cargo/bin:\$PATH"
fi

if ! command -v cargo >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y build-essential pkg-config libssl-dev curl ca-certificates
  curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
fi

if [ -f "\$HOME/.cargo/env" ]; then
  . "\$HOME/.cargo/env"
fi

cd '${REMOTE_DIR}/src/antenna-relay'
cargo build --release --locked
install -m 0755 target/release/antenna-relay '${REMOTE_DIR}/bin/antenna-relay'
chown -R antenna-relay:antenna-relay '${REMOTE_DIR}'
EOF

log "Installing systemd unit and environment"
scp "${SCP_ARGS[@]}" "${ENV_FILE}" "${SSH_TARGET}:/etc/default/${SERVICE_NAME}"
scp "${SCP_ARGS[@]}" "${SERVICE_FILE}" "${SSH_TARGET}:/etc/systemd/system/${SERVICE_NAME}.service"

ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
systemctl daemon-reload
systemctl enable '${SERVICE_NAME}'
systemctl restart '${SERVICE_NAME}'
systemctl --no-pager --full status '${SERVICE_NAME}' | sed -n '1,40p'
EOF

log "Detecting reverse proxy"
PROXY_KIND="$(ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "if command -v kubectl >/dev/null 2>&1 && kubectl get svc -n kube-system traefik >/dev/null 2>&1; then echo k8s; elif command -v caddy >/dev/null 2>&1; then echo caddy; elif command -v nginx >/dev/null 2>&1; then echo nginx; else echo none; fi")"
log "Reverse proxy: ${PROXY_KIND}"

if [[ "${PROXY_KIND}" == "k8s" ]]; then
  log "Configuring Kubernetes/Traefik ingress for ${DOMAIN}"
  if [[ ! "${HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Kubernetes routing mode requires --host to be an IPv4 address." >&2
    exit 1
  fi
  if [[ "${BIND_HOST}" == "127.0.0.1" || "${BIND_HOST}" == "localhost" ]]; then
    K8S_BIND="0.0.0.0:${BIND_PORT}"
    log "Updating relay bind for k8s reachability: ${BIND} -> ${K8S_BIND}"
    ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
sed -i 's|^ANTENNA_RELAY_BIND=.*$|ANTENNA_RELAY_BIND=${K8S_BIND}|' '/etc/default/${SERVICE_NAME}'
systemctl restart '${SERVICE_NAME}'
EOF
  fi
  scp "${SCP_ARGS[@]}" "${K8S_FILE}" "${SSH_TARGET}:/tmp/${K8S_INGRESS_NAME}.yaml"
  ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
kubectl apply -f '/tmp/${K8S_INGRESS_NAME}.yaml'
kubectl get svc '${K8S_SERVICE_NAME}' -n default
kubectl get endpoints '${K8S_SERVICE_NAME}' -n default
kubectl get ingress '${K8S_INGRESS_NAME}' -n default
EOF
elif [[ "${PROXY_KIND}" == "caddy" ]]; then
  log "Configuring Caddy vhost for ${DOMAIN}"
  ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "mkdir -p /etc/caddy/Caddyfile.d"
  scp "${SCP_ARGS[@]}" "${CADDY_FILE}" "${SSH_TARGET}:/etc/caddy/Caddyfile.d/${DOMAIN}.caddy"
  ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
if ! grep -Fq 'import /etc/caddy/Caddyfile.d/*.caddy' /etc/caddy/Caddyfile; then
  printf '\nimport /etc/caddy/Caddyfile.d/*.caddy\n' >> /etc/caddy/Caddyfile
fi
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
EOF
elif [[ "${PROXY_KIND}" == "nginx" ]]; then
  log "Configuring Nginx vhost for ${DOMAIN}"
  scp "${SCP_ARGS[@]}" "${NGINX_FILE}" "${SSH_TARGET}:/etc/nginx/sites-available/${DOMAIN}"
  ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
ln -sfn /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
nginx -t
systemctl reload nginx
EOF

  if [[ -n "${CERTBOT_EMAIL}" ]]; then
    log "Attempting TLS certificate issuance for ${DOMAIN} with certbot"
    ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "bash -s" <<EOF
set -euo pipefail
if ! command -v certbot >/dev/null 2>&1; then
  echo 'certbot not installed on remote host' >&2
  exit 1
fi
certbot --nginx --non-interactive --agree-tos --email '${CERTBOT_EMAIL}' -d '${DOMAIN}' --redirect
EOF
  fi
else
  echo "No supported reverse proxy found on remote host (expected caddy or nginx)." >&2
  exit 1
fi

log "Running health checks"
LOCAL_HEALTH="$(ssh "${SSH_ARGS[@]}" "${SSH_TARGET}" "curl -fsS --max-time 10 http://${BIND}/v1/health")"
printf '%s\n' "${LOCAL_HEALTH}"

PUBLIC_HEALTH=""
for _ in $(seq 1 20); do
  PUBLIC_HEALTH="$(curl -kfsSL --max-time 10 "https://${DOMAIN}/v1/health" 2>/dev/null || true)"
  if [[ "${PUBLIC_HEALTH}" == *'"ok":true'* ]]; then
    break
  fi
  PUBLIC_HEALTH="$(curl -fsSL --max-time 10 "http://${DOMAIN}/v1/health" 2>/dev/null || true)"
  if [[ "${PUBLIC_HEALTH}" == *'"ok":true'* ]]; then
    break
  fi
  sleep 2
done

if [[ "${PUBLIC_HEALTH}" != *'"ok":true'* ]]; then
  echo "Public health check failed for ${DOMAIN}/v1/health" >&2
  echo "Last response: ${PUBLIC_HEALTH:-<empty>}" >&2
  exit 1
fi
printf '%s\n' "${PUBLIC_HEALTH}"

log "Deployment complete"
log "Relay: ${PUBLIC_URL}"
