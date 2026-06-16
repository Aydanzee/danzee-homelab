#!/usr/bin/env bash
set -Eeuo pipefail

USB_UUID=""
LINUX_USER=""
USB_MOUNT="/mnt/danzee-backup"
KEEP_BACKUPS="14"
BACKUP_TIME="02:30:00"

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/server/install-backup-system.sh \
    --uuid USB_PARTITION_UUID \
    --user LINUX_USER \
    [--mount /mnt/danzee-backup] \
    [--keep 14] \
    [--time 02:30:00]

The script uses the existing filesystem. It never formats the USB drive.
EOF
}

while (($#)); do
  case "$1" in
    --uuid)
      USB_UUID="${2:?Missing value for --uuid}"
      shift 2
      ;;
    --user)
      LINUX_USER="${2:?Missing value for --user}"
      shift 2
      ;;
    --mount)
      USB_MOUNT="${2:?Missing value for --mount}"
      shift 2
      ;;
    --keep)
      KEEP_BACKUPS="${2:?Missing value for --keep}"
      shift 2
      ;;
    --time)
      BACKUP_TIME="${2:?Missing value for --time}"
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

if [[ -z "$USB_UUID" || -z "$LINUX_USER" ]]; then
  usage
  exit 1
fi

if ! id "$LINUX_USER" >/dev/null 2>&1; then
  echo "Linux user does not exist: $LINUX_USER" >&2
  exit 1
fi

DEVICE="$(blkid -U "$USB_UUID" 2>/dev/null || true)"
if [[ -z "$DEVICE" ]]; then
  echo "No attached partition found with UUID: $USB_UUID" >&2
  exit 1
fi

FSTYPE="$(blkid -s TYPE -o value "$DEVICE")"
if [[ -z "$FSTYPE" ]]; then
  echo "Could not determine filesystem type for $DEVICE" >&2
  exit 1
fi

case "$FSTYPE" in
  exfat|vfat)
    MOUNT_OPTIONS="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10s,uid=0,gid=0,fmask=0077,dmask=0077"
    ;;
  ext4|xfs|btrfs)
    MOUNT_OPTIONS="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10s"
    ;;
  *)
    echo "Unsupported backup filesystem: $FSTYPE" >&2
    echo "Supported filesystems: exfat, vfat, ext4, xfs, btrfs" >&2
    exit 1
    ;;
esac

echo "Using existing partition:"
echo "  Device:     $DEVICE"
echo "  UUID:       $USB_UUID"
echo "  Filesystem: $FSTYPE"
echo "  Mount:      $USB_MOUNT"
echo
echo "No formatting will be performed."

read -r -p "Continue? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Cancelled."; exit 0 ;;
esac

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openssl sqlite3 exfatprogs util-linux

install -d -m 0700 "$USB_MOUNT"
cp /etc/fstab "/etc/fstab.backup-$(date +%Y%m%d-%H%M%S)"

if ! grep -Fq "UUID=$USB_UUID " /etc/fstab; then
  echo "UUID=$USB_UUID $USB_MOUNT $FSTYPE $MOUNT_OPTIONS 0 0" \
    >>/etc/fstab
fi

systemctl daemon-reload

CURRENT_MOUNT="$(findmnt -n -o TARGET --source "$DEVICE" 2>/dev/null || true)"
if [[ -n "$CURRENT_MOUNT" && "$CURRENT_MOUNT" != "$USB_MOUNT" ]]; then
  umount "$CURRENT_MOUNT"
fi

mount "$USB_MOUNT"
ACTUAL_UUID="$(blkid -s UUID -o value "$(findmnt -n -o SOURCE --target "$USB_MOUNT")")"

if [[ "$ACTUAL_UUID" != "$USB_UUID" ]]; then
  echo "Mounted UUID mismatch; refusing to continue." >&2
  exit 1
fi

DEST_DIR="$USB_MOUNT/danzee-homelab-backups"
install -d -m 0700 "$DEST_DIR"
touch "$DEST_DIR/.write-test"
rm -f "$DEST_DIR/.write-test"

install -d -m 0700 /root/.config/danzee-backup
KEY_FILE="/root/.config/danzee-backup/backup.passphrase"

if [[ ! -s "$KEY_FILE" ]]; then
  umask 077
  openssl rand -base64 48 >"$KEY_FILE"
fi
chmod 600 "$KEY_FILE"

install -d -m 0755 /etc/danzee-homelab

cat >/etc/danzee-homelab/backup.conf <<EOF
USB_MOUNT=$USB_MOUNT
USB_UUID=$USB_UUID
DEST_DIR=$DEST_DIR
KEY_FILE=$KEY_FILE
KEEP_BACKUPS=$KEEP_BACKUPS
LINUX_USER=$LINUX_USER
HOMELAB_DIR=/opt/homelab
AXIOM_LOCAL_DIR=/opt/axiom-local
K3S_MANIFEST_DIR=/home/$LINUX_USER/k3s-lab
EOF

chmod 600 /etc/danzee-homelab/backup.conf

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

install -m 0700 \
  "$REPO_ROOT/scripts/server/backup.sh" \
  /usr/local/sbin/danzee-homelab-backup

install -m 0644 \
  "$REPO_ROOT/systemd/danzee-homelab-backup.service" \
  /etc/systemd/system/danzee-homelab-backup.service

sed "s/OnCalendar=.*/OnCalendar=*-*-* $BACKUP_TIME/" \
  "$REPO_ROOT/systemd/danzee-homelab-backup.timer" \
  >/etc/systemd/system/danzee-homelab-backup.timer

chmod 0644 /etc/systemd/system/danzee-homelab-backup.timer

systemctl daemon-reload
systemctl enable --now danzee-homelab-backup.timer

RECOVERY_COPY="/home/$LINUX_USER/danzee-backup-recovery-key.txt"
install -m 0600 -o "$LINUX_USER" -g "$LINUX_USER" \
  "$KEY_FILE" \
  "$RECOVERY_COPY"

echo
echo "Backup system installed."
echo
echo "Important: copy this temporary recovery key to a separate trusted device:"
echo "  $RECOVERY_COPY"
echo
echo "Compare checksums before deleting the temporary copy:"
sha256sum "$KEY_FILE"
echo
echo "Then run:"
echo "  sudo systemctl start danzee-homelab-backup.service"
echo "  sudo bash scripts/server/validate-latest-backup.sh"
echo
echo "The installer did not format the USB filesystem."
