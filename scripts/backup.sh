#!/usr/bin/env bash
# backup.sh — encrypted PostgreSQL backup with integrity manifest.
set -euo pipefail
DB="${DB_DATABASE:-arq_isp_os}"
OUT="${BACKUP_DIR:-./backups}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT"
FILE="$OUT/${DB}_${STAMP}.dump"

pg_dump --format=custom --no-owner --no-acl --dbname="$DB" --file="$FILE"

# Integrity manifest — restore is verified against this.
sha256sum "$FILE" > "$FILE.sha256"

# Encrypt at rest when a key is supplied (never store the key in the repo).
if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$FILE" -out "$FILE.enc" -pass env:BACKUP_PASSPHRASE
  rm -f "$FILE"
  sha256sum "$FILE.enc" > "$FILE.enc.sha256"
  echo "encrypted backup: $FILE.enc"
else
  echo "backup: $FILE"
fi
