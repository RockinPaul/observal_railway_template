# Changelog

## 2026-10-16 — Observal 1.15.1

- `web`, `api` and `worker` run `ghcr.io/observal/observal-web` and `-api` `:1.15.1` (were 1.13.1).
- Security fixes since 1.13.1 include blocking private hosts when fetching a SKILL.md (SSRF), user-wide token revocation that sticks, and patched JavaScript and Python dependencies.
- **`web/entrypoint.sh` no longer refuses to start when the old websocket line is missing.** 1.15 builds its GraphQL subscription URL from the page origin, so the line the template used to rewrite is gone. Without this change the 1.15.1 UI would not start at all (verified: the previous entrypoint exits with "websocket patch target not found"). The rewrite still runs on an older bundle.
- `web/default.conf` routes `/.well-known/ard.json` and `/.well-known/ai-catalog.json` to the API (new in 1.14, the agent resource discovery manifest); before, the UI's fallback would have answered them with the web page.
- `ClickHouse` gets upstream's new `telemetry.xml`: no crash reports to ClickHouse's developers, and table functions such as `url()` may not reach remote hosts.
- **Usage reporting stays off.** 1.15.1 turns on aggregate usage reporting to `usage.observal.io` every six hours (counts of users, teams, agents, components and sessions, which features are enabled, the public hostname), and its migration erases any choice already stored. The `api` entrypoint now stores "off" when no choice is stored (`USAGE_PING_DEFAULT=off`, baked into the image). Turn it on in Admin > Settings > Usage Reporting and the choice is kept across redeploys; set `USAGE_PING_DEFAULT=on` on `api` to use upstream's default instead.
- Also in 1.14 and 1.15: the Leaderboard is deprecated and off by default (super admins can turn it back on under Settings > Interface), PR-style reviews, agent component pins and share manifests.

### Upgrading an existing deployment

Back up Postgres, ClickHouse and the `api` volume first. `api` applies the Alembic migrations from `026_usage_ping_state` to `045_usage_ping_default_on` and two ClickHouse migrations on its first start, then backfills pending reviews; `worker` waits for the migrated schema. Nothing to change by hand. If you had turned Usage Reporting **on**, the upgrade resets it and the template stores off: turn it on again in the admin panel. If the `observal` CLI on a developer machine reports a version mismatch after the update, upgrade the CLI.

Verified locally on images rebuilt from upstream's Dockerfiles at both tags (ghcr.io layers are blocked in this sandbox; the test builds skipped the apt step that adds the `git` and `xmlsec1` command-line tools): a 1.13.1 database with the seeded super admin, a second admin and the JWT signing key upgraded in place, both accounts logged in, the key file stayed owned by `appuser` (uid 1001), and the worker started. Through the updated `web`, the 1.15.1 UI loads, logins work, `/.well-known/ard.json` returns the manifest and a GraphQL websocket gets `connection_ack`. A fresh 1.15.1 deploy creates the schema, seeds the demo super admin and stores usage reporting as off; an admin's "on" survives a redeploy.

## 2026-09 — initial release, Observal 1.13.1

- Six services: `web` (`Dockerfile.web` over `ghcr.io/observal/observal-web:1.13.1`), `api` and `worker` (`Dockerfile.api` over `ghcr.io/observal/observal-api:1.13.1`, role switch in `api-entrypoint.sh`), `Postgres` (Railway `postgres-ssl:18`), `ClickHouse` (`Dockerfile.clickhouse` over `clickhouse/clickhouse-server:26.6` with upstream's tuning), `Redis` (Railway `redis:8.2`).
- `web/default.conf` replaces upstream's nginx config: variable upstream with Railway's DNS resolver, IPv4 and IPv6 listeners, websocket upgrade on `/api/`, security headers on assets, 10 MB body limit matching the API default, `X-Forwarded-For` trimmed of Railway's edge hop so the API sees the real client, gzip for text assets, and a trailing slash in `API_UPSTREAM` tolerated. `web/entrypoint.sh` also rewrites the UI bundle's GraphQL websocket origin from `<host>:8000` to the page origin and refuses to start if that line disappears upstream.
- `api` starts as root only to hand the volume to upstream's `appuser`, then drops privileges; uvicorn listens on IPv4 and IPv6.
- Demo accounts are seeded on first start with generated passwords; the super admin is the first login.
- Not supported: the Admin Data Migration screen (export and import artifacts need a volume shared by `api` and `worker`); use upstream's `observal server migrate` CLI or database backups.
- Volumes: `Postgres`, `ClickHouse`, `Redis`, and `api` (`/data`, holding the JWT signing keys under `/data/keys`). Healthchecks: `api` `/readyz`, `web` `/`.

### Upgrading an existing deployment

Back up Postgres and the `api` volume before applying an update, as upstream recommends. The update redeploys `web`, `api`, and `worker`; `api` applies Alembic and ClickHouse migrations on its first start and only passes `/readyz` once Postgres answers. `worker` waits for the migrated schema. Databases and their volumes are never touched. Upstream does not support upgrading from pre-1.0 servers.
