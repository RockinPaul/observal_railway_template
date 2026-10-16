# Observal Railway Template

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/observal?referralCode=YqmMB-&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway template for [Observal](https://github.com/Observal/Observal), the self-hosted registry and insight engine for coding-agent extensions: Skills, MCP servers, and Agents, with session telemetry, review workflows, and a control plane for your team's harnesses (Claude Code, Cursor, Codex, Kiro, Antigravity, Pi). It deploys the whole upstream stack at a pinned release:

| Service | Runs | Source |
|---|---|---|
| `web` | the web UI and the only public entry point; proxies `/api/` to the API | `Dockerfile.web` over `ghcr.io/observal/observal-web:1.15.1` |
| `api` | FastAPI backend; runs migrations on start | `Dockerfile.api` over `ghcr.io/observal/observal-api:1.15.1` |
| `worker` | background jobs (arq) | same image, `OBSERVAL_ROLE=worker` |
| `Postgres` | registry metadata and users | Railway's Postgres 18 image |
| `ClickHouse` | session telemetry and insights | `Dockerfile.clickhouse` over `clickhouse/clickhouse-server:26.6` with upstream's small-container tuning |
| `Redis` | job queue and cache | Railway's Redis 8 image |

Only `web` has a public domain. The browser, the `observal` CLI, and the harness telemetry hooks all talk to `https://<web-domain>/api/v1/...`, and `web` forwards that to `api` over Railway's private network. Nothing else is reachable from outside.

## First login

The template seeds Observal's four demo accounts on the first start, each with a password generated at deploy time. Open the `web` domain and sign in as the super admin:

- email: the `DEMO_SUPER_ADMIN_EMAIL` variable on `api` (default `super@demo.example`)
- password: the `DEMO_SUPER_ADMIN_PASSWORD` variable on `api`

Seeding is the practical path on Railway. Upstream's alternative, the `observal auth login` bootstrap of a first admin, only works from `localhost` on the API host, which Railway's proxy never is.

Then replace the demo accounts with real ones:

1. While signed in as the demo super admin, open Settings, Users (`/settings/users`) and use Create User to add yourself with the `super_admin` role. The same works from the CLI once you are logged in: `observal admin create-user you@example.com "Your Name" --role super_admin` (add `--password`, or read the generated one from the output).
2. Sign out and sign in as your new account.
3. Delete the four demo accounts, from the same Users page or with `observal admin delete-user super@demo.example` and so on for `admin@`, `reviewer@`, and `user@demo.example`. Observal (1.13.1 through 1.15.1) removes demo accounts on its own only when a real user arrives through SCIM provisioning; accounts created in the UI or CLI do not trigger that, so this step is manual. Seeding never runs again while any real user exists.
4. Add teammates the same way, or connect Google, OIDC, or SAML sign-in under Settings, Authentication. Upstream's [authentication guide](https://github.com/Observal/Observal/blob/main/docs/self-hosting/authentication.md) covers roles and SSO. Users who arrive through SSO get the plain `user` role until an admin promotes them. Handy commands: `observal admin users`, `observal admin reset-password <email> --generate`.
5. Optional: set `SEED_DEMO_ACCOUNTS=false` on `api` so an emptied database is never re-seeded, and pick your own `DEMO_SUPER_ADMIN_EMAIL` before the first deploy if you would rather start from a real address.

Lost the generated super admin password before creating a real account? It is still the `DEMO_SUPER_ADMIN_PASSWORD` variable on `api`. To change it, edit the variable, delete the demo user, and redeploy `api` so seeding recreates it (seeding only recreates missing demo accounts while no real user exists).

## Connect the CLI and your harness

On each developer machine:

```
curl -fsSL https://raw.githubusercontent.com/Observal/Observal/main/install.sh | bash
observal auth login --server https://<web-domain>
observal doctor patch --all-harnesses
```

`observal doctor patch --all-harnesses` installs the telemetry hooks and `/observal` commands into every harness found on the machine; plain `observal doctor` only reports. Everything the CLI sends goes to `/api/v1/...` on the web domain.

## Variables

`api` (the `worker` reads `SECRET_KEY`, `DATABASE_URL`, `CLICKHOUSE_URL`, and `REDIS_URL` from `api` by reference):

| Variable | Default | Purpose |
|---|---|---|
| `SECRET_KEY` | generated (64 chars) | Application encryption secret. Changing it invalidates sessions and encrypted settings. |
| `DATABASE_URL` | `postgresql+asyncpg://…${{Postgres.*}}…` | Built from the Postgres service. |
| `CLICKHOUSE_URL` | `clickhouse://…${{ClickHouse.*}}…/observal` | Built from the ClickHouse service. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Built from the Redis service. |
| `JWT_KEY_DIR` | `/data/keys` | EC signing key pair, generated on first start, kept on the `api` volume. |
| `CORS_ALLOWED_ORIGINS` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` | Browser origins allowed by the API's CORS middleware, read from the environment on every start. |
| `MAX_REQUEST_SIZE_MB` | unset (10) | Request body limit of the API; `web` enforces the same 10 MB at nginx. Raise both to allow bigger uploads. |
| `SEED_DEMO_ACCOUNTS` | `true` | Seed the four demo accounts when the database has no users. |
| `DEMO_*_EMAIL`, `DEMO_*_PASSWORD` | `*@demo.example`, generated | Super admin, admin, reviewer, and user demo accounts. |
| `USAGE_PING_DEFAULT` | `off` (baked into the image) | Observal 1.15.1 sends aggregate usage counts to `usage.observal.io` every six hours unless Admin > Settings > Usage Reporting is off. With `off`, the template stores "off" when no choice is stored; turn reporting on in that panel and the choice is kept. Set `on` to use upstream's default. |
| `RAILWAY_RUN_UID` | `0` | Starts the container as root so it can hand the root-owned volume to upstream's `appuser`; migrations and the server then run as `appuser`. |
| `LOG_FORMAT`, `LOG_LEVEL` | `json`, `INFO` | Boot-time logging. |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_ALLOWED_DOMAINS` | unset | Optional; imported once into the admin settings. |

`web`: `API_UPSTREAM=http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000`, `PORT=3000`. `ClickHouse`: `CLICKHOUSE_DB=observal`, `CLICKHOUSE_USER=default`, `CLICKHOUSE_PASSWORD` generated. Postgres and Redis carry Railway's standard variables.

Everything else (eval models, security policies, retention, SSO, trusted proxies) is runtime configuration in the admin UI, as upstream intends since 1.0.

## How it fits together

- `api` starts with upstream's own init script: it creates the `pg_trgm` extension, applies Alembic migrations (stamping a fresh database), and runs the ClickHouse migrations, then serves on port 8000 on both IPv4 and IPv6 so Railway's private network can reach it. On the very first start the log shows a Python traceback about a duplicate column: that is upstream's normal fresh-database path, after which the script stamps the schema and continues. The healthcheck is `/readyz`, which fails only when Postgres is unreachable and reports ClickHouse or Redis outages as degraded.
- `worker` waits until the API has migrated the database, then runs the arq worker. It has no domain and no healthcheck.
- `web` renders its nginx config at start with Railway's DNS resolver and a variable upstream, so it keeps working when `api` redeploys and changes address. It also routes `/.well-known/ard.json` (Observal's agent resource discovery manifest) to the API. Observal 1.13 built its GraphQL subscription URL as `<host>:8000`, which cannot work on Railway; the start script rewrote that one line to the page's own origin. 1.15 builds the URL from the page origin itself, so the rewrite now only applies to an older bundle.
- ClickHouse carries upstream's `config.d` and `users.d` tuning for small containers (per-query memory caps, async inserts, log retention). It needs roughly 1 to 2 GB of memory; the rest of the stack is small. Upstream's smallest sizing guide is 2 vCPU and 4 to 6 GB for a team of ten.
- Not supported here: the Admin, Settings, Data Migration screen. Its export and import jobs run on `worker` and write artifacts to a directory the `api` must read back, which upstream solves with one volume shared by both containers. Railway volumes attach to a single service, so use upstream's CLI alternative (`observal server migrate export` and `import`, run from a machine that can reach the databases, for example through Railway's TCP proxy) or plain Postgres and ClickHouse backups instead.
- Client addresses: Railway's edge proxy sends `X-Forwarded-For` as the visitor's address followed by the edge's own public address. `web` strips that last hop and passes the rest on, and the API, which trusts private-network peers by default and reads the header right to left, records the real client in the audit log and rate limiter. If you put another proxy such as Cloudflare in front of the Railway domain, it stays in the chain: add its ranges under Settings, Network, Trusted Proxies, as upstream's [trusted proxies guide](https://github.com/Observal/Observal/blob/main/docs/self-hosting/trusted-proxies.md) describes.

## Upgrading Observal

Bump the tag in `Dockerfile.api` and `Dockerfile.web` together, and the ClickHouse tag in `Dockerfile.clickhouse` when upstream moves it. Merging to `main` notifies everyone who deployed the template. Migrations run automatically when `api` starts; upstream recommends backing up Postgres and the `api` volume first. Note breaking changes in `CHANGELOG.md`.

## Files

- `Dockerfile.api`, `api-entrypoint.sh`: API and worker image, one role switch
- `Dockerfile.web`, `web/default.conf`, `web/entrypoint.sh`: UI image with the Railway-aware nginx config (and the websocket fix for pre-1.15 bundles)
- `Dockerfile.clickhouse`, `clickhouse/`: ClickHouse with upstream's tuning files (Apache-2.0, copied from `docker/clickhouse` upstream)
- `TEMPLATE_OVERVIEW.md`: the marketplace description
- `CHANGELOG.md`: what changed and how to upgrade an existing deployment
