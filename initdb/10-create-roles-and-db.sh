#!/usr/bin/env bash
set -euo pipefail

DB_NAME="$(cat /run/secrets/db_name)"
RAILS_PASS="$(cat /run/secrets/rails_app_password)"
SUPERSET_PASS="$(cat /run/secrets/superset_password)"

# Connect to the built-in 'postgres' DB
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "postgres" <<SQL
-- Create roles if missing (idempotent)
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rails_app') THEN
    CREATE ROLE rails_app LOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'superset') THEN
    CREATE ROLE superset LOGIN;
  END IF;
END \$\$;

-- Set/rotate passwords
ALTER ROLE rails_app PASSWORD '${RAILS_PASS}';
ALTER ROLE superset  PASSWORD '${SUPERSET_PASS}';

-- Harden roles (non-superuser)
ALTER ROLE rails_app NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
ALTER ROLE superset  NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;

-- Create database if missing; ensure rails_app is owner
SELECT 'CREATE DATABASE ${DB_NAME} OWNER rails_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec

ALTER DATABASE ${DB_NAME} OWNER TO rails_app;

-- Reduce default PUBLIC access
REVOKE ALL ON DATABASE ${DB_NAME} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${DB_NAME} TO rails_app, superset;
SQL

# Now connect to the app database for schema setup
psql -v ON_ERROR_STOP=1 --username "postgres" --dbname "${DB_NAME}" <<SQL
-- Make rails_app the schema owner
ALTER SCHEMA public OWNER TO rails_app;

-- Rails app: read/write
GRANT USAGE ON SCHEMA public TO rails_app;

-- Superset: read-only
GRANT USAGE ON SCHEMA public TO superset;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO superset;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO superset;

-- Future tables/sequences created by rails_app are readable by superset
ALTER DEFAULT PRIVILEGES FOR ROLE rails_app IN SCHEMA public
  GRANT SELECT ON TABLES TO superset;

ALTER DEFAULT PRIVILEGES FOR ROLE rails_app IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO superset;

-- Force read-only transactions for superset
ALTER ROLE superset SET default_transaction_read_only = on;
SQL

echo "Database '${DB_NAME}' initialized with rails_app (rw) and superset (ro) users."
