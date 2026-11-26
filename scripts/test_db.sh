#!/usr/bin/env bash
# Applies every migration to an empty Postgres database and runs the smoke
# test. Needs psql and a server; uses PG* environment variables.
#   PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres ./scripts/test_db.sh
set -euo pipefail
DB="${TEST_DB:-loyalty_test}"
dropdb --if-exists "$DB"
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do
  echo "→ $f"
  # pg_cron is a Supabase extension; the stub provides cron.schedule().
  sed 's/^create extension if not exists pg_cron;//' "$f" |
    psql -q -v ON_ERROR_STOP=1 -d "$DB" -f -
done
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/10_smoke.sql
