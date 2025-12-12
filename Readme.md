# Postgres 16 + Tailscale Sidecar + Superset Network (Template)

This stack runs Postgres 16 behind a Tailscale sidecar and attaches to an existing Docker network (e.g. `superset_default`) so:

- Superset can connect via Docker DNS
- You can connect remotely via your Tailscale tailnet
- No host port publishing is required

## Naming Conventions

| Resource                                   | Name              |
| ------------------------------------------ | ----------------- |
| Postgres container + hostname              | `v-db-${NAME}`    |
| Tailscale container + hostname             | `ts-v-db-${NAME}` |
| Docker network alias on `superset_default` | `v-db-${NAME}`    |

Superset connects to:

- **Host:** `v-db-${NAME}`
- **Port:** `5432`

## Users / Access Model

Three database users:

| User        | Role       | Purpose                                            |
| ----------- | ---------- | -------------------------------------------------- |
| `postgres`  | superuser  | Admin-only; never use in apps                      |
| `rails_app` | read/write | Rails runtime; also owns the DB for migrations/DDL |
| `superset`  | read-only  | Superset analytics queries                         |

## Why Not Store Postgres Credentials in `.env`?

Operationally, `.env` tends to be copied around and is easy to leak. This template uses Docker secrets for database passwords so credentials are mounted as files in `/run/secrets/...` and only provided to the containers that need them.

## Prerequisites

- Docker + Docker Compose v2
- Existing Docker network: `superset_default`

Verify:

```bash
docker network ls | grep superset_default
```

## Setup

### 1) Create `.env`

```bash
cp .env.example .env
# Edit NAME, DOCKER_NETWORK, TS_AUTHKEY, TS_EXTRA_ARGS
```

### 2) Create secrets (per instance NAME)

```bash
mkdir -p secrets/${NAME}
chmod 700 secrets/${NAME}

# postgres superuser password (required by official image)
openssl rand -base64 32 > secrets/${NAME}/postgres_password

# application database name (not secret, but kept here for a single source of truth)
printf 'myapp_production' > secrets/${NAME}/db_name

# rails_app password (Rails runtime)
openssl rand -base64 32 > secrets/${NAME}/rails_app_password

# superset password (read-only)
openssl rand -base64 32 > secrets/${NAME}/superset_password

chmod 600 secrets/${NAME}/*
```

### 3) Start

```bash
docker compose up -d
docker compose ps
```

## Connecting

### Rails (read/write)

Use `rails_app`:

```
postgresql://rails_app:<rails_app_password>@v-db-${NAME}:5432/<db_name>
```

### Superset (read-only)

Use `superset`:

```
postgresql+psycopg2://superset:<superset_password>@v-db-${NAME}:5432/<db_name>
```

### Over Tailscale

Connect to the Tailscale hostname/IP of the sidecar `ts-v-db-${NAME}` on port `5432`.

## Important Note About Init Scripts

The init script in `initdb/` runs **only on first initialization** (when the database volume is empty).

If you already initialized the volume, apply role/permission changes manually via `psql` instead of expecting the init script to re-run.
