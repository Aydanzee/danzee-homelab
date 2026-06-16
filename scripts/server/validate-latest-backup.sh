#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${BACKUP_CONFIG:-/etc/danzee-homelab/backup.conf}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Backup configuration not found: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

LATEST="$(
  find "$DEST_DIR" \
    -maxdepth 1 \
    -type f \
    -name "$(hostname -s)_*.tar.gz.enc" \
    -printf "%T@ %p\n" \
    | sort -nr \
    | head -1 \
    | cut -d" " -f2-
)"

if [[ -z "$LATEST" ]]; then
  echo "No encrypted backups found in $DEST_DIR" >&2
  exit 1
fi

TEST_DIR="$(mktemp -d /var/tmp/danzee-restore-test.XXXXXX)"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Testing: $LATEST"

openssl enc \
  -d \
  -aes-256-cbc \
  -pbkdf2 \
  -iter 200000 \
  -pass file:"$KEY_FILE" \
  -in "$LATEST" \
  | tar -xzf - -C "$TEST_DIR"

RESTORE_ROOT="$(
  find "$TEST_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | head -1
)"

echo
echo "===== INTERNAL CHECKSUMS ====="
cd "$RESTORE_ROOT"
sha256sum -c checksums.sha256

echo
echo "===== MARIADB DUMP ====="
gzip -t docker/mariadb-all-databases.sql.gz
echo "MariaDB dump: OK"

echo
echo "===== K3S DATABASE ====="
sqlite3 kubernetes/k3s-state.db "PRAGMA integrity_check;"

echo
echo "RESTORE VALIDATION PASSED"
