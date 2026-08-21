#!/usr/bin/env bash
# restore.sh — restore a backup into a target database and verify.
set -euo pipefail
FILE="$1"; TARGET="${2:-arq_isp_os_restored}"

if [[ "$FILE" == *.enc ]]; then
  [[ -n "${BACKUP_PASSPHRASE:-}" ]] || { echo "BACKUP_PASSPHRASE required"; exit 1; }
  openssl enc -d -aes-256-cbc -pbkdf2 -in "$FILE" -out "${FILE%.enc}" -pass env:BACKUP_PASSPHRASE
  FILE="${FILE%.enc}"
fi

# Integrity check before touching the database.
[[ -f "$FILE.sha256" ]] && sha256sum -c "$FILE.sha256"

dropdb --if-exists "$TARGET"
createdb "$TARGET"
pg_restore --no-owner --no-acl --dbname="$TARGET" "$FILE"
echo "restored into: $TARGET"
