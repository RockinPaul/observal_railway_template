# Changelog

## 2026-09 — initial release, Observal 1.13.1

- Six services: `web` (`Dockerfile.web` over `ghcr.io/observal/observal-web:1.13.1`), `api` and `worker` (`Dockerfile.api` over `ghcr.io/observal/observal-api:1.13.1`, role switch in `api-entrypoint.sh`), `Postgres` (Railway `postgres-ssl:18`), `ClickHouse` (`Dockerfile.clickhouse` over `clickhouse/clickhouse-server:26.6` with upstream's tuning), `Redis` (Railway `redis:8.2`).
- `web/default.conf` replaces upstream's nginx config: variable upstream with Railway's DNS resolver, IPv4 and IPv6 listeners, websocket upgrade on `/api/`, 25 MB upload limit. `web/entrypoint.sh` also rewrites the UI bundle's GraphQL websocket origin from `<host>:8000` to the page origin and refuses to start if that line disappears upstream.
- Demo accounts are seeded on first start with generated passwords; the super admin is the first login.
- Volumes: `Postgres`, `ClickHouse`, `Redis`, and `api` (`/data/keys`). Healthchecks: `api` `/readyz`, `web` `/`.

### Upgrading an existing deployment

Back up Postgres and the `api` volume before applying an update, as upstream recommends. The update redeploys `web`, `api`, and `worker`; `api` applies Alembic and ClickHouse migrations on its first start and only passes `/readyz` once Postgres answers. `worker` waits for the migrated schema. Databases and their volumes are never touched. Upstream does not support upgrading from pre-1.0 servers.
