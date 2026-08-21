#!/usr/bin/env bash
# Backup → checksum → destroy → restore → verify. Fails the build if the
# restored database does not match the original, so "backup works" is
# never assumed.
set -euo pipefail
HOST=${PGHOST:-localhost}; USER=${PGUSER:-postgres}; DB=${DB:-arq_isp_os}

Q="SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') AND table_type='BASE TABLE')||'|'||(SELECT count(*) FROM pg_class WHERE relrowsecurity=true)"
BEFORE=$(psql -h "$HOST" -U "$USER" -t -A -d "$DB" -c "$Q" | tr -d ' ')

pg_dump -h "$HOST" -U "$USER" --format=custom --no-owner --no-acl -d "$DB" -f /tmp/ci.dump
sha256sum /tmp/ci.dump > /tmp/ci.dump.sha256
sha256sum -c /tmp/ci.dump.sha256

dropdb -h "$HOST" -U "$USER" --if-exists ci_restored
createdb -h "$HOST" -U "$USER" ci_restored
pg_restore -h "$HOST" -U "$USER" --no-owner --no-acl -d ci_restored /tmp/ci.dump

AFTER=$(psql -h "$HOST" -U "$USER" -t -A -d ci_restored -c "$Q" | tr -d ' ')
echo "original=$BEFORE restored=$AFTER"
test "$BEFORE" = "$AFTER"
echo "backup/restore drill PASS"
