#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${1:-config/homelab.env}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0 $CONFIG_FILE" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Configuration file not found: $CONFIG_FILE" >&2
  echo "Copy config/homelab.env.example to config/homelab.env and edit it first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

required_vars=(
  LAB_HOSTNAME
  LINUX_USER
  LAN_IP
  LAN_CIDR
  HOMELAB_DIR
  OLLAMA_MODEL
)

for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required setting is empty: $name" >&2
    exit 1
  fi
done

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  echo "Linux user does not exist: $LINUX_USER" >&2
  exit 1
fi

log() {
  printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

log "Installing base packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  git \
  jq \
  openssl \
  sqlite3 \
  tar \
  gzip \
  rsync \
  ufw \
  util-linux

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine from Docker's apt repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
fi

systemctl enable --now docker
usermod -aG docker "$LINUX_USER"

if ! command -v k3s >/dev/null 2>&1; then
  log "Installing single-node k3s"
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -
fi

systemctl enable --now k3s

if ! command -v tailscale >/dev/null 2>&1; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

if ! command -v ollama >/dev/null 2>&1; then
  log "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
fi

log "Applying low-memory Ollama service limits"
install -d -m 0755 /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/limits.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_KEEP_ALIVE=0"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_CONTEXT_LENGTH=2048"
Environment="OLLAMA_MAX_QUEUE=2"
Environment="OLLAMA_NO_CLOUD=1"
EOF

systemctl daemon-reload
systemctl enable --now ollama
systemctl restart ollama

log "Pulling configured model: $OLLAMA_MODEL"
sudo -u ollama ollama pull "$OLLAMA_MODEL" || ollama pull "$OLLAMA_MODEL"

log "Creating Docker Compose stack"
install -d -m 0750 -o "$LINUX_USER" -g "$LINUX_USER" "$HOMELAB_DIR"

ENV_FILE="$HOMELAB_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  MARIADB_ROOT_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
  MARIADB_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"

  cat >"$ENV_FILE" <<EOF
LAN_IP=$LAN_IP
MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD
MARIADB_DATABASE=homelab
MARIADB_USER=homelab
MARIADB_PASSWORD=$MARIADB_PASSWORD
EOF

  chown "$LINUX_USER:$LINUX_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

cat >"$HOMELAB_DIR/compose.yaml" <<'EOF'
services:
  mariadb:
    image: mariadb:11.4
    container_name: mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
      MARIADB_DATABASE: ${MARIADB_DATABASE}
      MARIADB_USER: ${MARIADB_USER}
      MARIADB_PASSWORD: ${MARIADB_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    healthcheck:
      test:
        - CMD-SHELL
        - mariadb-admin ping -uroot -p"$${MARIADB_ROOT_PASSWORD}" --silent
      interval: 15s
      timeout: 5s
      retries: 10

  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "${LAN_IP}:3001:3001"
    volumes:
      - uptime_kuma_data:/app/data
    healthcheck:
      test:
        - CMD
        - extra/healthcheck
      interval: 30s
      timeout: 10s
      retries: 3

  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: unless-stopped
    ports:
      - "${LAN_IP}:9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  mariadb_data:
    name: danzee-homelab_mariadb_data
  uptime_kuma_data:
    name: danzee-homelab_uptime_kuma_data
  portainer_data:
    name: danzee-homelab_portainer_data
EOF

chown "$LINUX_USER:$LINUX_USER" "$HOMELAB_DIR/compose.yaml"
sudo -u "$LINUX_USER" docker compose \
  --env-file "$ENV_FILE" \
  -f "$HOMELAB_DIR/compose.yaml" \
  up -d

log "Applying k3s lab workloads"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

k3s kubectl apply -f "$REPO_ROOT/k8s/guardrails.yaml"
k3s kubectl apply -f "$REPO_ROOT/k8s/hello-lab.yaml"
k3s kubectl apply -f "$REPO_ROOT/k8s/storage-demo.yaml"

log "Configuring UFW"
ufw default deny incoming
ufw default allow outgoing

ufw allow from "$LAN_CIDR" to any port 22 proto tcp \
  comment 'SSH from trusted LAN'
ufw allow in on tailscale0 to any port 22 proto tcp \
  comment 'SSH via Tailscale'

ufw allow from "$LAN_CIDR" to any port 3001 proto tcp \
  comment 'Uptime Kuma from trusted LAN'
ufw allow from "$LAN_CIDR" to any port 9443 proto tcp \
  comment 'Portainer from trusted LAN'
ufw allow from "$LAN_CIDR" to any port 30080 proto tcp \
  comment 'k3s demo from trusted LAN'
ufw allow from "$LAN_CIDR" to any port 8088 proto tcp \
  comment 'Private app from trusted LAN'
ufw allow in on tailscale0 to any port 8088 proto tcp \
  comment 'Private app via Tailscale'

ufw --force enable

log "Bootstrap complete"
cat <<EOF

Next actions:

1. Join the Tailscale network:
     sudo tailscale up

2. Log out and back in so $LINUX_USER receives Docker group membership.

3. Open services from the trusted LAN:
     Uptime Kuma: http://$LAN_IP:3001
     Portainer:    https://$LAN_IP:9443
     k3s demo:    http://$LAN_IP:30080

4. Install USB backups after identifying the existing partition UUID:
     lsblk -o NAME,TRAN,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
     sudo bash scripts/server/install-backup-system.sh --uuid UUID --user $LINUX_USER

Axiom Local is intentionally not deployed by this public repository.
EOF
