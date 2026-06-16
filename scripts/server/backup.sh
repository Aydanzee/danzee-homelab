#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

exec 9>/run/lock/danzee-homelab-backup.lock

if ! flock -n 9; then
  echo "Another Danzee backup is already running; exiting."
  exit 0
fi

: "${USB_MOUNT:?USB_MOUNT is required}"
: "${USB_UUID:?USB_UUID is required}"
: "${DEST_DIR:?DEST_DIR is required}"
: "${KEY_FILE:?KEY_FILE is required}"
: "${KEEP_BACKUPS:?KEEP_BACKUPS is required}"
: "${LINUX_USER:?LINUX_USER is required}"
: "${HOMELAB_DIR:?HOMELAB_DIR is required}"
: "${K3S_MANIFEST_DIR:?K3S_MANIFEST_DIR is required}"
: "${AXIOM_LOCAL_DIR:=/opt/axiom-local}"

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
HOST_SHORT="$(hostname -s)"

WORK_DIR="$(mktemp -d "/var/tmp/danzee-backup.${STAMP}.XXXXXX")"
STAGE_DIR="$WORK_DIR/${HOST_SHORT}_${STAMP}"
ARCHIVE_FILE="$WORK_DIR/${HOST_SHORT}_${STAMP}.tar.gz"
FINAL_FILE="$DEST_DIR/${HOST_SHORT}_${STAMP}.tar.gz.enc"
TEMP_FINAL="${FINAL_FILE}.partial"

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

STOPPED_CONTAINERS=()

stop_container_for_backup() {
  local container="$1"

  if docker inspect "$container" >/dev/null 2>&1 \
    && [[ "$(docker inspect -f '{{.State.Running}}' "$container")" == "true" ]]; then
    log "Stopping $container briefly for a consistent volume snapshot"
    docker stop --time 30 "$container" >/dev/null
    STOPPED_CONTAINERS+=("$container")
  fi
}

restart_backup_containers() {
  local container

  for container in "${STOPPED_CONTAINERS[@]}"; do
    log "Restarting $container"
    docker start "$container" >/dev/null
  done

  STOPPED_CONTAINERS=()
}

cleanup() {
  local exit_code="$1"

  set +e
  restart_backup_containers
  rm -rf "$WORK_DIR"
  rm -f "$TEMP_FINAL"

  exit "$exit_code"
}

trap 'cleanup $?' EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for command_name in \
  docker sqlite3 openssl tar gzip sha256sum \
  findmnt blkid flock mountpoint
do
  require_command "$command_name"
done

if [[ ! -r "$KEY_FILE" ]]; then
  echo "Encryption key is missing or unreadable: $KEY_FILE" >&2
  exit 1
fi

if ! mountpoint -q "$USB_MOUNT"; then
  log "Mounting backup drive at $USB_MOUNT"
  mount "$USB_MOUNT"
fi

SOURCE_DEVICE="$(findmnt -n -o SOURCE --target "$USB_MOUNT")"
ACTUAL_UUID="$(blkid -s UUID -o value "$SOURCE_DEVICE")"

if [[ "$ACTUAL_UUID" != "$USB_UUID" ]]; then
  echo "Refusing backup: mounted UUID is $ACTUAL_UUID; expected $USB_UUID" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
mkdir -p \
  "$STAGE_DIR/config" \
  "$STAGE_DIR/docker/volumes" \
  "$STAGE_DIR/kubernetes" \
  "$STAGE_DIR/system"

log "Collecting system inventory"
{
  echo "Backup timestamp: $(date --iso-8601=seconds)"
  echo "Hostname: $(hostname -f 2>/dev/null || hostname)"

  echo
  echo "===== UPTIME ====="
  uptime || true

  echo
  echo "===== FILESYSTEMS ====="
  df -hT || true

  echo
  echo "===== MEMORY ====="
  free -h || true

  echo
  echo "===== DOCKER CONTAINERS ====="
  docker ps --all || true

  echo
  echo "===== DOCKER VOLUMES ====="
  docker volume ls || true

  echo
  echo "===== KUBERNETES NODES ====="
  k3s kubectl get nodes -o wide || true

  echo
  echo "===== OLLAMA MODELS ====="
  ollama list || true
} >"$STAGE_DIR/backup-report.txt" 2>&1

log "Backing up project and system configuration"
[[ -d "$HOMELAB_DIR" ]] && cp -a "$HOMELAB_DIR" "$STAGE_DIR/config/"
[[ -d "$AXIOM_LOCAL_DIR" ]] && cp -a "$AXIOM_LOCAL_DIR" "$STAGE_DIR/config/"
[[ -d "$K3S_MANIFEST_DIR" ]] && cp -a "$K3S_MANIFEST_DIR" "$STAGE_DIR/config/"

cp -a /etc/fstab "$STAGE_DIR/system/fstab"
cp -a /etc/systemd/system/ollama.service "$STAGE_DIR/system/" 2>/dev/null || true
cp -a /etc/systemd/system/ollama.service.d "$STAGE_DIR/system/" 2>/dev/null || true
cp -a /etc/rancher/k3s "$STAGE_DIR/system/" 2>/dev/null || true
cp -a /etc/systemd/system/k3s.service "$STAGE_DIR/system/" 2>/dev/null || true

ufw status verbose >"$STAGE_DIR/system/ufw-status.txt" 2>&1 || true
ollama list >"$STAGE_DIR/system/ollama-models.txt" 2>&1 || true

log "Creating consistent MariaDB logical dump"
docker inspect mariadb >/dev/null 2>&1 || {
  echo "MariaDB container not found." >&2
  exit 1
}

docker exec mariadb sh -c \
  'exec mariadb-dump --all-databases --single-transaction --quick --routines --events --triggers -uroot -p"$MARIADB_ROOT_PASSWORD"' \
  | gzip -9 \
  >"$STAGE_DIR/docker/mariadb-all-databases.sql.gz"

gzip -t "$STAGE_DIR/docker/mariadb-all-databases.sql.gz"

log "Archiving Docker application volumes"

PORTAINER_VOLUME=/var/lib/docker/volumes/danzee-homelab_portainer_data/_data
UPTIME_KUMA_VOLUME=/var/lib/docker/volumes/danzee-homelab_uptime_kuma_data/_data

for volume_path in "$PORTAINER_VOLUME" "$UPTIME_KUMA_VOLUME"; do
  if [[ ! -d "$volume_path" ]]; then
    echo "Required Docker volume path not found: $volume_path" >&2
    exit 1
  fi
done

stop_container_for_backup portainer
stop_container_for_backup uptime-kuma

tar --numeric-owner \
  -czf "$STAGE_DIR/docker/volumes/portainer-data.tar.gz" \
  -C "$PORTAINER_VOLUME" .

tar --numeric-owner \
  -czf "$STAGE_DIR/docker/volumes/uptime-kuma-data.tar.gz" \
  -C "$UPTIME_KUMA_VOLUME" .

restart_backup_containers

log "Creating online backup of the k3s SQLite datastore"
sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  ".backup '$STAGE_DIR/kubernetes/k3s-state.db'"

if [[ "$(sqlite3 "$STAGE_DIR/kubernetes/k3s-state.db" 'PRAGMA integrity_check;')" != "ok" ]]; then
  echo "k3s SQLite integrity check failed." >&2
  exit 1
fi

tar --numeric-owner \
  -czf "$STAGE_DIR/kubernetes/k3s-server-config.tar.gz" \
  --exclude='server/db' \
  --exclude='server/kine.sock' \
  -C /var/lib/rancher/k3s \
  server

tar --numeric-owner \
  -czf "$STAGE_DIR/kubernetes/k3s-local-storage.tar.gz" \
  -C /var/lib/rancher/k3s \
  storage

k3s kubectl get all -A -o yaml \
  >"$STAGE_DIR/kubernetes/all-workloads.yaml" 2>&1 || true
k3s kubectl get pv,pvc -A -o yaml \
  >"$STAGE_DIR/kubernetes/persistent-volumes.yaml" 2>&1 || true
k3s kubectl get configmap -A -o yaml \
  >"$STAGE_DIR/kubernetes/configmaps.yaml" 2>&1 || true
k3s kubectl get crd -o yaml \
  >"$STAGE_DIR/kubernetes/custom-resource-definitions.yaml" 2>&1 || true

log "Generating internal checksums"
(
  cd "$STAGE_DIR"
  find . -type f ! -name checksums.sha256 -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    >checksums.sha256
)

log "Creating compressed archive"
tar -C "$WORK_DIR" -czf "$ARCHIVE_FILE" "$(basename "$STAGE_DIR")"

ARCHIVE_KIB="$(du -k "$ARCHIVE_FILE" | awk '{print $1}')"
FREE_KIB="$(df -Pk "$USB_MOUNT" | awk 'NR == 2 {print $4}')"
REQUIRED_KIB="$((ARCHIVE_KIB * 2 + 102400))"

if (( FREE_KIB < REQUIRED_KIB )); then
  echo "Not enough USB space. Need about ${REQUIRED_KIB} KiB; have ${FREE_KIB} KiB." >&2
  exit 1
fi

log "Encrypting archive to USB"
openssl enc \
  -aes-256-cbc \
  -salt \
  -pbkdf2 \
  -iter 200000 \
  -pass file:"$KEY_FILE" \
  -in "$ARCHIVE_FILE" \
  -out "$TEMP_FINAL"

mv "$TEMP_FINAL" "$FINAL_FILE"

(
  cd "$DEST_DIR"
  sha256sum "$(basename "$FINAL_FILE")" \
    >"$(basename "$FINAL_FILE").sha256"
)

log "Verifying encrypted backup"
openssl enc \
  -d \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 200000 \
  -pass file:"$KEY_FILE" \
  -in "$FINAL_FILE" \
  | tar -tzf - >/dev/null

log "Applying retention policy: keep newest $KEEP_BACKUPS backups"
find "$DEST_DIR" \
  -maxdepth 1 \
  -type f \
  -name "${HOST_SHORT}_*.tar.gz.enc" \
  -printf '%T@ %p\n' \
  | sort -nr \
  | tail -n "+$((KEEP_BACKUPS + 1))" \
  | cut -d' ' -f2- \
  | while IFS= read -r old_backup; do
      [[ -n "$old_backup" ]] || continue
      rm -f "$old_backup" "${old_backup}.sha256"
    done

sync

log "Backup completed: $FINAL_FILE"
log "Encrypted size: $(du -h "$FINAL_FILE" | awk '{print $1}')"
