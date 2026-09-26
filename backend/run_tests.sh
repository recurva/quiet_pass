#!/usr/bin/env bash
# The one command: brings up Postgres/Redis if they aren't already running,
# waits for them to be healthy, then runs the full pytest suite. The suite
# itself creates and migrates a fresh quietpass_test database on every run
# (see tests/conftest.py) — nothing here needs to know about that.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

docker compose up -d

echo "Waiting for Postgres and Redis to report healthy..."
for i in $(seq 1 30); do
  pg_status=$(docker inspect -f '{{.State.Health.Status}}' quietpass_postgres 2>/dev/null || echo "starting")
  redis_status=$(docker inspect -f '{{.State.Health.Status}}' quietpass_redis 2>/dev/null || echo "starting")
  if [ "$pg_status" = "healthy" ] && [ "$redis_status" = "healthy" ]; then
    break
  fi
  sleep 1
done

if [ "$pg_status" != "healthy" ] || [ "$redis_status" != "healthy" ]; then
  echo "Postgres/Redis did not become healthy in time (pg=$pg_status, redis=$redis_status)." >&2
  exit 1
fi

python -m pytest "$@"
