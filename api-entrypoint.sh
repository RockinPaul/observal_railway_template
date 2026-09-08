#!/bin/sh
# One image, two roles. Railway has no init containers, so the api role runs upstream's
# /app/entrypoint.sh (CREATE EXTENSION, create_all, alembic upgrade head, ClickHouse migrations)
# on every start and then serves. The worker role waits until that schema exists.
set -eu
: "${PORT:=8000}"
: "${OBSERVAL_ROLE:=api}"
PY=/app/.venv/bin/python

schema_ready() {
  "$PY" - <<'PYEOF'
import asyncio, sys
from sqlalchemy import text
from database import engine
async def check():
    async with engine.connect() as conn:
        ok = await conn.scalar(text("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = 'alembic_version')"))
    await engine.dispose()
    sys.exit(0 if ok else 1)
asyncio.run(check())
PYEOF
}

case "$OBSERVAL_ROLE" in
  api)
    for key in SECRET_KEY DATABASE_URL CLICKHOUSE_URL REDIS_URL; do
      eval "v=\${$key:-}"; [ -n "$v" ] || { echo "$key is empty; refusing to start" >&2; exit 1; }
    done
    [ "${#SECRET_KEY}" -ge 32 ] || { echo "SECRET_KEY must be at least 32 characters" >&2; exit 1; }
    KEYS="${JWT_KEY_DIR:-/data/keys}"
    mkdir -p "$KEYS"
    if [ "$(id -u)" = "0" ]; then
      # Railway volumes are root-owned, so the api starts as root (RAILWAY_RUN_UID=0) only to hand the
      # key directory to upstream's unprivileged user, then drops to it for everything else.
      chown -R appuser:appgroup "$KEYS"
      mkdir -p /home/appuser && chown appuser:appgroup /home/appuser
      # HOME must follow the user: asyncpg looks for client certificates under ~/.postgresql and
      # would fail on the unreadable /root.
      RUN_AS="env HOME=/home/appuser setpriv --reuid=appuser --regid=appgroup --init-groups"
    else
      RUN_AS=""
    fi
    $RUN_AS /app/entrypoint.sh
    export SKIP_DDL_ON_STARTUP=true
    # An empty host makes uvicorn/asyncio open both an IPv4 and an IPv6 listener; '::' alone is
    # IPv6-only because asyncio sets IPV6_V6ONLY on explicit IPv6 hosts.
    exec $RUN_AS "$PY" -m uvicorn main:app --host '' --port "$PORT"
    ;;
  worker)
    n=0
    until schema_ready 2>/tmp/schema_check.err; do
      n=$((n+1))
      if [ $((n % 12)) -eq 1 ]; then
        echo "worker: waiting for the api to migrate the database (attempt $n)..."
        grep -v '^\s*$' /tmp/schema_check.err | tail -1 | sed 's/^/worker: last error: /' || true
      fi
      [ "$n" -lt 360 ] || { echo "worker: schema still missing after 30 minutes; giving up" >&2; exit 1; }
      sleep 5
    done
    exec "$PY" -c "import asyncio; asyncio.set_event_loop(asyncio.new_event_loop()); from arq import run_worker; from worker import WorkerSettings; run_worker(WorkerSettings)"
    ;;
  *)
    echo "OBSERVAL_ROLE must be api or worker, got '$OBSERVAL_ROLE'" >&2; exit 1 ;;
esac
