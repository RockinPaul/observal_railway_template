# Deploy and Host Observal on Railway

Observal is the open-source control plane and system of record for a team's internal AI components. It is a registry for Skills, MCP servers, and Agents with review and governance, plus an insight engine that captures coding-agent sessions from Claude Code, Cursor, Codex, Kiro, Antigravity, and Pi and turns them into usage, cost, and quality analytics. This template deploys the complete upstream stack at release 1.13.1: web UI, API, background worker, PostgreSQL, ClickHouse, and Redis.

## About Hosting Observal

Hosting Observal on Railway means six services wired over the private network, with one public domain on the web service. The API runs upstream's own image and its init script on every start, so schema and ClickHouse migrations apply themselves; the worker shares the image and runs the job queue; the web service serves the UI and proxies the API, the CLI, and telemetry traffic to the backend, resolving its address through Railway DNS so redeploys never break the link. Secrets, database credentials, and the passwords of the seeded demo accounts are generated at deploy time. Everything beyond infrastructure, from SSO to retention and eval models, is configured in Observal's admin UI.

## Common Use Cases

- A private registry where a team publishes, reviews, and installs its own agent Skills, MCP servers, and Agents
- Session telemetry and insights across every developer's coding agent, with cost and quality dashboards
- Governance for internal AI components: approvals, roles, audit logs, and SSO, on infrastructure you control

## Dependencies for Observal Hosting

- A Railway account (the stack runs about 3 to 4 GB of memory, most of it ClickHouse)
- The `observal` CLI on each developer machine, installed with upstream's one-line installer
- Optional: Google, OIDC, or SAML credentials for single sign-on

### Deployment Dependencies

- Observal upstream repository: https://github.com/Observal/Observal
- Observal self-hosting docs: https://github.com/Observal/Observal/tree/main/docs/self-hosting
- Template repository: https://github.com/RockinPaul/observal_railway_template

### Implementation Details

- `web`: `ghcr.io/observal/observal-web:1.13.1` with a Railway-aware nginx config (variable upstream, DNS resolver, websocket upgrade for GraphQL subscriptions), healthcheck `/`, public domain, port 3000.
- `api`: `ghcr.io/observal/observal-api:1.13.1`, runs upstream's init script then uvicorn on port 8000, healthcheck `/readyz`, volume `/data` for the JWT signing keys.
- `worker`: same image with `OBSERVAL_ROLE=worker`, waits for the migrated schema, runs the arq worker.
- `Postgres`: Railway's `postgres-ssl:18` image with a volume. `Redis`: Railway's `redis:8.2` with a password and a volume. `ClickHouse`: `clickhouse/clickhouse-server:26.6` with upstream's small-container tuning and a volume.

First login: sign in on the web domain as the seeded super admin, whose email and generated password are the `DEMO_SUPER_ADMIN_EMAIL` and `DEMO_SUPER_ADMIN_PASSWORD` variables on `api`. Create your real super admin under Settings, Users, sign in as it, and delete the demo accounts there or with `observal admin delete-user <email>`. Add teammates the same way or connect SSO. Developers connect with `observal auth login --server https://<web-domain>` followed by `observal doctor patch --all-harnesses`.

## Why Deploy Observal on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Observal on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
