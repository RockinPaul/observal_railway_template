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
        ok = await conn.scalar(text("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alembic_version')"))
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
    mkdir -p "${JWT_KEY_DIR:-/data/keys}"
    /app/entrypoint.sh
    export SKIP_DDL_ON_STARTUP=true
    # [::] binds IPv4 and IPv6: Railway's private network is IPv6-only.
    exec "$PY" -m uvicorn main:app --host '' --port "$PORT"
    ;;
  worker)
    until schema_ready 2>/dev/null; do echo "worker: waiting for the api to migrate the database..."; sleep 5; done
    exec "$PY" -c "import asyncio; asyncio.set_event_loop(asyncio.new_event_loop()); from arq import run_worker; from worker import WorkerSettings; run_worker(WorkerSettings)"
    ;;
  *)
    echo "OBSERVAL_ROLE must be api or worker, got '$OBSERVAL_ROLE'" >&2; exit 1 ;;
esac
