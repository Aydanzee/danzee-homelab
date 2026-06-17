#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

BESZEL_VERSION="0.18.7"
LAN_IP=""
LAN_CIDR=""
INSTALL_DIR="/opt/beszel"
SECRETS_DIR="/etc/danzee-beszel"
BACKUP_DIR="/var/backups/beszel"
COMPOSE_FILE="$INSTALL_DIR/compose.yaml"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROLLBACK_ARCHIVE=""

usage() {
  cat <<'USAGE'
Usage:
  sudo bash scripts/server/install-beszel-monitoring.sh \
    --lan-ip LAN_IP \
    [--lan-cidr LAN_CIDR] \
    [--version BESZEL_VERSION]

Example:
  sudo bash scripts/server/install-beszel-monitoring.sh \
    --lan-ip 192.168.1.20 \
    --lan-cidr 192.168.1.0/24

The script:
  - deploys a pinned Beszel Hub and Agent with Docker Compose;
  - uses a loopback-only Docker socket proxy;
  - restricts the dashboard to the trusted LAN and tailscale0;
  - stores Beszel agent credentials in root-only files;
  - installs setup and status helper commands;
  - creates a rollback snapshot before replacing an existing installation.

It never writes credentials into this repository.
USAGE
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --lan-ip)
      LAN_IP="${2:?--lan-ip requires a value}"
      shift 2
      ;;
    --lan-cidr)
      LAN_CIDR="${2:?--lan-cidr requires a value}"
      shift 2
      ;;
    --version)
      BESZEL_VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$EUID" -eq 0 ]] || fail "Run this installer with sudo."
[[ -n "$LAN_IP" ]] || {
  usage
  fail "--lan-ip is required."
}

if [[ -z "$LAN_CIDR" ]]; then
  IFS=. read -r octet1 octet2 octet3 _ <<<"$LAN_IP"
  [[ -n "${octet1:-}" && -n "${octet2:-}" && -n "${octet3:-}" ]] || {
    fail "Could not derive a /24 LAN CIDR from $LAN_IP. Pass --lan-cidr explicitly."
  }
  LAN_CIDR="${octet1}.${octet2}.${octet3}.0/24"
fi

for command_name in docker ss ufw curl tar install; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done

docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is unavailable."
systemctl is-active --quiet docker || fail "Docker is not running."

if ss -ltnH '( sport = :8090 )' | grep -q .; then
  if ! docker ps --format '{{.Names}}' | grep -qx beszel; then
    fail "TCP port 8090 is already in use by another service."
  fi
fi

if [[ -d "$INSTALL_DIR" ]]; then
  install -d -m 0700 "$BACKUP_DIR"
  ROLLBACK_ARCHIVE="$BACKUP_DIR/beszel-before-$STAMP.tar.gz"
  log "Creating rollback snapshot"
  tar -C "$(dirname "$INSTALL_DIR")" -czf "$ROLLBACK_ARCHIVE" "$(basename "$INSTALL_DIR")"
fi

rollback() {
  local exit_code="$?"
  trap - ERR

  echo
  echo "Beszel deployment failed. Attempting rollback..." >&2

  if [[ -n "$ROLLBACK_ARCHIVE" && -f "$ROLLBACK_ARCHIVE" ]]; then
    docker compose -f "$COMPOSE_FILE" --profile agent down >/dev/null 2>&1 || true
    rm -rf "$INSTALL_DIR"
    tar -C "$(dirname "$INSTALL_DIR")" -xzf "$ROLLBACK_ARCHIVE"
    docker compose -f "$COMPOSE_FILE" up -d >/dev/null 2>&1 || true
    echo "Previous installation restored from: $ROLLBACK_ARCHIVE" >&2
  fi

  exit "$exit_code"
}
trap rollback ERR

log "Preparing persistent directories"
install -d -m 0750 "$INSTALL_DIR"
install -d -m 0750 "$INSTALL_DIR/data"
install -d -m 0750 "$INSTALL_DIR/socket"
install -d -m 0750 "$INSTALL_DIR/agent-data"
install -d -m 0700 "$SECRETS_DIR"
install -d -m 0700 "$BACKUP_DIR"

cat >"$COMPOSE_FILE" <<COMPOSE
name: danzee-beszel

services:
  beszel:
    image: henrygd/beszel:${BESZEL_VERSION}
    container_name: beszel
    restart: unless-stopped
    network_mode: host
    environment:
      APP_URL: http://${LAN_IP}:8090
    volumes:
      - ./data:/beszel_data
      - ./socket:/beszel_socket
    healthcheck:
      test: ["CMD", "/beszel", "health", "--url", "http://127.0.0.1:8090"]
      interval: 60s
      timeout: 5s
      start_period: 15s
      retries: 3
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 256m
    cpus: 0.75

  socket-proxy:
    image: lscr.io/linuxserver/socket-proxy:latest
    container_name: beszel-socket-proxy
    restart: unless-stopped
    environment:
      CONTAINERS: "1"
      EVENTS: "1"
      INFO: "1"
      PING: "1"
      VERSION: "1"
      POST: "0"
      AUTH: "0"
      BUILD: "0"
      COMMIT: "0"
      CONFIGS: "0"
      EXEC: "0"
      IMAGES: "0"
      NETWORKS: "0"
      NODES: "0"
      PLUGINS: "0"
      SECRETS: "0"
      SERVICES: "0"
      SESSION: "0"
      SWARM: "0"
      SYSTEM: "0"
      TASKS: "0"
      VOLUMES: "0"
      TZ: "UTC"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "127.0.0.1:2375:2375"
    read_only: true
    tmpfs:
      - /run
    security_opt:
      - no-new-privileges:true
    mem_limit: 64m
    cpus: 0.25

  beszel-agent:
    profiles: ["agent"]
    image: henrygd/beszel-agent:${BESZEL_VERSION}
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    depends_on:
      socket-proxy:
        condition: service_started
    env_file:
      - ${SECRETS_DIR}/agent.env
    environment:
      LISTEN: /beszel_socket/beszel.sock
      HUB_URL: http://127.0.0.1:8090
      DOCKER_HOST: tcp://127.0.0.1:2375
      KEY_FILE: /run/secrets/beszel-agent-key
      FILESYSTEM: /
    volumes:
      - ./agent-data:/var/lib/beszel-agent
      - ./socket:/beszel_socket
      - ${SECRETS_DIR}/agent-key:/run/secrets/beszel-agent-key:ro
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro
    healthcheck:
      test: ["CMD", "/agent", "health"]
      interval: 60s
      timeout: 5s
      start_period: 15s
      retries: 3
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    mem_limit: 192m
    cpus: 0.50
COMPOSE

chmod 0640 "$COMPOSE_FILE"

cat >"$SECRETS_DIR/agent.env.example" <<'ENV_EXAMPLE'
# Created automatically by:
#   sudo danzee-beszel-agent-setup
TOKEN=replace-me
ENV_EXAMPLE
chmod 0600 "$SECRETS_DIR/agent.env.example"

cat >/usr/local/sbin/danzee-beszel-agent-setup <<'AGENT_SETUP'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

INSTALL_DIR="/opt/beszel"
SECRETS_DIR="/etc/danzee-beszel"

[[ "$EUID" -eq 0 ]] || {
  echo "Run this command with sudo." >&2
  exit 1
}

echo
echo "In Beszel:"
echo "1. Create the initial admin account."
echo "2. Select Add System -> Docker."
echo "3. Name the system."
echo "4. Use /beszel_socket/beszel.sock as Host / IP."
echo "5. Copy the public key and token."
echo

read -r -p "Paste the Beszel public key: " BESZEL_KEY
[[ -n "$BESZEL_KEY" ]] || {
  echo "The key cannot be empty." >&2
  exit 1
}

read -r -s -p "Paste the Beszel token (input stays hidden): " BESZEL_TOKEN
echo
[[ -n "$BESZEL_TOKEN" ]] || {
  echo "The token cannot be empty." >&2
  exit 1
}

printf '%s\n' "$BESZEL_KEY" >"$SECRETS_DIR/agent-key"
printf 'TOKEN=%s\n' "$BESZEL_TOKEN" >"$SECRETS_DIR/agent.env"
chmod 0600 "$SECRETS_DIR/agent-key" "$SECRETS_DIR/agent.env"

docker compose -f "$INSTALL_DIR/compose.yaml" --profile agent up -d beszel-agent

for attempt in {1..24}; do
  status="$(
    docker inspect \
      -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      beszel-agent 2>/dev/null || true
  )"

  case "$status" in
    healthy|running)
      break
      ;;
    unhealthy|exited|dead)
      docker logs --tail 100 beszel-agent 2>&1 || true
      echo "Beszel agent failed to start: $status" >&2
      exit 1
      ;;
  esac

  sleep 5
done

echo
docker compose -f "$INSTALL_DIR/compose.yaml" --profile agent ps
echo
echo "Agent configuration completed."
AGENT_SETUP
chmod 0700 /usr/local/sbin/danzee-beszel-agent-setup

cat >/usr/local/sbin/danzee-beszel-status <<'STATUS_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

echo "===== BESZEL CONTAINERS ====="
docker compose -f /opt/beszel/compose.yaml --profile agent ps

echo
echo "===== BESZEL HUB HEALTH ====="
curl -fsS http://127.0.0.1:8090/api/health 2>/dev/null || \
  docker inspect \
    -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    beszel

echo
echo "===== RESOURCE SNAPSHOT ====="
docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}' \
  beszel beszel-agent beszel-socket-proxy 2>/dev/null || true
STATUS_SCRIPT
chmod 0755 /usr/local/sbin/danzee-beszel-status

log "Validating the Compose configuration"
docker compose -f "$COMPOSE_FILE" config >/dev/null

log "Pulling Beszel images"
docker compose -f "$COMPOSE_FILE" pull beszel socket-proxy

log "Starting the Beszel Hub and restricted Docker socket proxy"
docker compose -f "$COMPOSE_FILE" up -d beszel socket-proxy

log "Applying LAN- and Tailscale-scoped firewall access"
ufw allow from "$LAN_CIDR" to any port 8090 proto tcp comment "Beszel LAN" >/dev/null

if ip link show tailscale0 >/dev/null 2>&1; then
  ufw allow in on tailscale0 to any port 8090 proto tcp comment "Beszel Tailscale" >/dev/null
fi

log "Waiting for the Beszel Hub"
for attempt in {1..30}; do
  if curl -fsS --max-time 3 http://127.0.0.1:8090/api/health >/dev/null 2>&1; then
    break
  fi

  if (( attempt == 30 )); then
    docker logs --tail 100 beszel 2>&1 || true
    fail "Beszel did not become healthy."
  fi

  sleep 3
done

log "Verifying the Docker socket proxy is loopback-only"
PROXY_BIND="$(docker port beszel-socket-proxy 2375/tcp 2>/dev/null || true)"
[[ "$PROXY_BIND" == *"127.0.0.1:2375"* ]] || {
  fail "Socket proxy is not restricted to 127.0.0.1."
}

log "Deployment completed"
docker compose -f "$COMPOSE_FILE" ps

echo
echo "Beszel Hub:"
echo "  LAN:       http://${LAN_IP}:8090"
echo "  Tailscale: http://TAILSCALE_IP:8090"
echo
echo "Next:"
echo "  1. Open the dashboard and create the first admin account."
echo "  2. Select Add System -> Docker."
echo "  3. Use /beszel_socket/beszel.sock as Host / IP."
echo "  4. Run: sudo danzee-beszel-agent-setup"
echo
echo "Health check:"
echo "  sudo danzee-beszel-status"

if [[ -n "$ROLLBACK_ARCHIVE" ]]; then
  echo
  echo "Rollback snapshot retained at: $ROLLBACK_ARCHIVE"
fi

trap - ERR
