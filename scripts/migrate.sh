#!/usr/bin/env bash
# migrate.sh — tracked migration runner.
#
# Root cause this fixes: the raw .sql files under database/migrations/
# apply cleanly in a single pass against a fresh database (proven: 0
# failures, 117 tables) but files 001-022 predate the IF-NOT-EXISTS
# convention adopted from migration 023 onward, so re-running an already-
# applied file directly with `psql -f` is not itself safe.
#
# Real deployments don't need file-level idempotency — they need a
# migration ledger so each file runs exactly once, ever. That's what this
# script provides: a schema_migrations table recording which files have
# already been applied, skipping them on subsequent runs. This is the
# same mechanism Laravel's own migrator uses internally.
set -euo pipefail
PSQL_HOST_ARG=""; [ -n "${DB_HOST:-}" ] && PSQL_HOST_ARG="-h $DB_HOST"
USER="${DB_USER:-postgres}"; DB="${DB_DATABASE:-arq_isp_os}"
DIR="$(dirname "$0")/../database/migrations"

psql $PSQL_HOST_ARG -U "$USER" -d "$DB" -v ON_ERROR_STOP=1 -q -c "
  CREATE TABLE IF NOT EXISTS public.schema_migrations (
    filename    TEXT PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );"

applied=0; skipped=0
for f in "$DIR"/*.sql; do
  name=$(basename "$f")
  already=$(psql $PSQL_HOST_ARG -U "$USER" -d "$DB" -t -A -c \
    "SELECT 1 FROM public.schema_migrations WHERE filename = '$name';")
  if [ "$already" = "1" ]; then
    echo "  skip   $name (already applied)"
    skipped=$((skipped+1))
    continue
  fi
  echo "  apply  $name"
  psql $PSQL_HOST_ARG -U "$USER" -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"
  psql $PSQL_HOST_ARG -U "$USER" -d "$DB" -v ON_ERROR_STOP=1 -q -c \
    "INSERT INTO public.schema_migrations (filename) VALUES ('$name');"
  applied=$((applied+1))
done
echo ""
echo "migrate.sh: $applied applied, $skipped already up to date"
