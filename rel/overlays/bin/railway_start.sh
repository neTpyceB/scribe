#!/bin/sh
set -eu

echo "[railway_start] running database migrations..."
attempt=1
max_attempts=20
migration_pool_size="${MIGRATION_POOL_SIZE:-2}"

until POOL_SIZE="$migration_pool_size" /app/bin/migrate; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "[railway_start] migration failed after ${max_attempts} attempts" >&2
    exit 1
  fi

  echo "[railway_start] migration attempt ${attempt} failed; retrying in 2s (POOL_SIZE=${migration_pool_size})..."
  attempt=$((attempt + 1))
  sleep 2
done

echo "[railway_start] migrations completed; starting server..."
exec /app/bin/server
