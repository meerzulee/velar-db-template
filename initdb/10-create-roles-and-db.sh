#!/usr/bin/env bash
set -euo pipefail

DB_NAME="$(cat /run/secrets/db_name)"
RAILS_PASS="$(cat /run/secrets/rails_app_password)"
SUPERSET_PASS="$(cat /run/secrets/superset_password)"

# Always connect to the built-in 'postgres' DB (exists in every cluster)
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "postgres" \
  -v db_name="${DB_NAME}" \
  -v rails_pass="${RAILS_PASS}" \
  -v superset_pass="${SUPERSET_PASS}" <<'SQL'
-- Create roles if missing (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rails_app') THEN
    CREATE ROLE rails_app LOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'superset') THEN
    CREATE ROLE superset LOGIN;
  END IF;
END $$;

-- Set/rotate passwords (safe to re-run)
ALTER ROLE rails_app PASSWORD :'rails_pass';
ALTER ROLE superset  PASSWORD :'superset_pass';

-- Harden roles (non-superuser)
ALTER ROLE rails_app NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
ALTER ROLE superset  NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;

-- Create database if missing; ensure rails_app is owner
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') THEN
    EXECUTE format('CREATE DATABASE %I OWNER rails_app', :'db_name');
  ELSE
    EXECUTE format('ALTER DATABASE %I OWNER TO rails_app', :'db_name');
  END IF;
END $$;

-- Reduce default PUBLIC access at the database level
REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO rails_app, superset;

\connect :"db_name"

-- Make rails_app the schema owner (Rails migrations usually operate in public)
ALTER SCHEMA public OWNER TO rails_app;

-- Rails app: read/write (and, as owner, can run migrations/DDL)
GRANT USAGE ON SCHEMA public TO rails_app;

-- Superset: read-only
GRANT USAGE ON SCHEMA public TO superset;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO superset;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO superset;

-- Ensure future tables/sequences created by rails_app are readable by superset
ALTER DEFAULT PRIVILEGES FOR ROLE rails_app IN SCHEMA public
  GRANT SELECT ON TABLES TO superset;

ALTER DEFAULT PRIVILEGES FOR ROLE rails_app IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO superset;

-- Optional guardrail: force read-only transactions for superset
ALTER ROLE superset SET default_transaction_read_only = on;
SQL

