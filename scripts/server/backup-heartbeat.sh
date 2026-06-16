#!/usr/bin/env bash
set -Eeuo pipefail

URL_FILE="${UPTIME_KUMA_PUSH_URL_FILE:-/etc/danzee-homelab/uptime-kuma-backup-push-url}"

if [[ ! -r "$URL_FILE" ]]; then
  logger \
    -p user.warning \
    -t danzee-backup-heartbeat \
    "Uptime Kuma Push URL is missing"

  exit 0
fi

BASE_URL="$(tr -d '\r\n' < "$URL_FILE")"

MESSAGE="$(
  printf \
    'Encrypted backup completed successfully on %s at %s' \
    "$(hostname -s)" \
    "$(date --iso-8601=seconds)"
)"

for attempt in {1..12}; do
  if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    --get \
    --data-urlencode "status=up" \
    --data-urlencode "msg=$MESSAGE" \
    --data-urlencode "ping=" \
    "$BASE_URL" \
    >/dev/null; then

    logger \
      -t danzee-backup-heartbeat \
      "Uptime Kuma backup heartbeat delivered"

    echo "Uptime Kuma backup heartbeat delivered"
    exit 0
  fi

  echo "Heartbeat attempt $attempt failed; retrying..."
  sleep 5
done

logger \
  -p user.warning \
  -t danzee-backup-heartbeat \
  "Backup succeeded, but Uptime Kuma heartbeat could not be delivered"

echo \
  "Warning: backup succeeded, but the Uptime Kuma heartbeat failed." \
  >&2

# Monitoring must not turn a valid backup into a failed backup.
exit 0
