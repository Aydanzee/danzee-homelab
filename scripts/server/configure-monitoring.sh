#!/usr/bin/env bash
set -Eeuo pipefail

LAN_IP=""
KUMA_CONTAINER="uptime-kuma"
AXIOM_PORT="8088"
PORTAINER_PORT="9443"
URL_FILE="/etc/danzee-homelab/uptime-kuma-backup-push-url"
HEARTBEAT_SCRIPT="/usr/local/sbin/danzee-backup-heartbeat"
DROPIN_DIR="/etc/systemd/system/danzee-homelab-backup.service.d"
DROPIN_FILE="$DROPIN_DIR/uptime-kuma-heartbeat.conf"

usage() {
  cat <<'USAGE'
Usage:
  sudo bash scripts/server/configure-monitoring.sh --lan-ip LAN_IP

This script:
  - allows only the Uptime Kuma Docker subnet to reach Axiom Local and Portainer;
  - verifies both services from inside the Uptime Kuma container;
  - stores the Uptime Kuma backup Push URL as a root-only file;
  - installs the backup heartbeat and systemd drop-in.

The Push URL is requested interactively and is never written to shell history.
USAGE
}

while (($#)); do
  case "$1" in
    --lan-ip)
      LAN_IP="${2:?Missing value for --lan-ip}"
      shift 2
      ;;
    --kuma-container)
      KUMA_CONTAINER="${2:?Missing value for --kuma-container}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

if [[ -z "$LAN_IP" ]]; then
  usage
  exit 1
fi

for command_name in docker ufw curl systemctl systemd-analyze; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Required command not found: $command_name" >&2
    exit 1
  }
done

docker inspect "$KUMA_CONTAINER" >/dev/null 2>&1 || {
  echo "Uptime Kuma container not found: $KUMA_CONTAINER" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KUMA_NETWORK="$(
  docker inspect \
    -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
    "$KUMA_CONTAINER" |
    head -n 1
)"

KUMA_SUBNET="$(
  docker network inspect \
    -f '{{(index .IPAM.Config 0).Subnet}}' \
    "$KUMA_NETWORK"
)"

if [[ -z "$KUMA_NETWORK" || -z "$KUMA_SUBNET" ]]; then
  echo "Could not determine the Uptime Kuma Docker network." >&2
  exit 1
fi

echo "Uptime Kuma network: $KUMA_NETWORK"
echo "Uptime Kuma subnet:  $KUMA_SUBNET"

add_rule() {
  local port="$1"
  local comment="$2"

  if ufw status | grep -Fq "$comment"; then
    echo "Firewall rule already exists: $comment"
  else
    ufw allow \
      from "$KUMA_SUBNET" \
      to any port "$port" \
      proto tcp \
      comment "$comment"
  fi
}

add_rule "$AXIOM_PORT" "Uptime Kuma to Axiom Local"
add_rule "$PORTAINER_PORT" "Uptime Kuma to Portainer"
ufw reload >/dev/null

echo
echo "Testing Axiom Local from Uptime Kuma"
docker exec \
  -e DANZEE_LAN_IP="$LAN_IP" \
  "$KUMA_CONTAINER" \
  node -e '
const url = `http://${process.env.DANZEE_LAN_IP}:8088/api/health`;
fetch(url)
  .then(async response => {
    const body = await response.text();
    console.log("HTTP status:", response.status);
    console.log(body);
    if (!response.ok || !body.includes("\"online\":true")) process.exit(1);
  })
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
'

echo
echo "Testing Portainer from Uptime Kuma"
docker exec \
  -e DANZEE_LAN_IP="$LAN_IP" \
  "$KUMA_CONTAINER" \
  node -e '
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
const url = `https://${process.env.DANZEE_LAN_IP}:9443`;
fetch(url)
  .then(response => {
    console.log("HTTP status:", response.status);
    if (response.status >= 500) process.exit(1);
  })
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
'

echo
printf 'Paste the Uptime Kuma backup Push URL: ' >/dev/tty
IFS= read -r -s PUSH_URL </dev/tty
printf '\n' >/dev/tty

BASE_URL="${PUSH_URL%%\?*}"

case "$BASE_URL" in
  http://*/api/push/*|https://*/api/push/*)
    ;;
  *)
    echo "That does not look like an Uptime Kuma Push URL." >&2
    exit 1
    ;;
esac

TEMP_URL_FILE="$(mktemp)"
cleanup() {
  rm -f "$TEMP_URL_FILE"
}
trap cleanup EXIT

printf '%s\n' "$BASE_URL" > "$TEMP_URL_FILE"
chmod 600 "$TEMP_URL_FILE"

install -d -m 0700 /etc/danzee-homelab
install -m 0600 -o root -g root "$TEMP_URL_FILE" "$URL_FILE"
install -m 0700 -o root -g root \
  "$REPO_ROOT/scripts/server/backup-heartbeat.sh" \
  "$HEARTBEAT_SCRIPT"

install -d -m 0755 "$DROPIN_DIR"
install -m 0644 \
  "$REPO_ROOT/systemd/danzee-homelab-backup.service.d/uptime-kuma-heartbeat.conf" \
  "$DROPIN_FILE"

systemctl daemon-reload
systemd-analyze verify \
  /etc/systemd/system/danzee-homelab-backup.service \
  /etc/systemd/system/danzee-homelab-backup.timer

"$HEARTBEAT_SCRIPT"

echo
echo "Monitoring integration installed."
echo "Run a complete test with:"
echo "  sudo systemctl start danzee-homelab-backup.service"
echo "  sudo journalctl -u danzee-homelab-backup.service -n 60 --no-pager"
echo "  sudo journalctl -t danzee-backup-heartbeat -n 20 --no-pager"
