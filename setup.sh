#!/usr/bin/env bash
set -euo pipefail

echo "=== Velar DB Setup ==="
echo

# Service name
read -p "Service name: " NAME
if [[ -z "$NAME" ]]; then
  echo "Error: Service name is required"
  exit 1
fi

# Tailscale login server
read -p "Tailscale login server [https://headscale.velar.kg]: " TS_LOGIN_SERVER
TS_LOGIN_SERVER="${TS_LOGIN_SERVER:-https://headscale.velar.kg}"

# Tailscale auth key
read -p "Tailscale auth key: " TS_AUTHKEY
if [[ -z "$TS_AUTHKEY" ]]; then
  echo "Error: Tailscale auth key is required"
  exit 1
fi

# Docker network
read -p "Docker network [superset_default]: " DOCKER_NETWORK
DOCKER_NETWORK="${DOCKER_NETWORK:-superset_default}"

# Database name
read -p "Database name [production]: " DB_NAME
DB_NAME="${DB_NAME:-production}"

# Generate passwords
generate_password() {
  openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

POSTGRES_PASS=$(generate_password)
RAILS_APP_PASS=$(generate_password)
SUPERSET_PASS=$(generate_password)

# Write .env file
cat > .env <<EOF
NAME=${NAME}
DOCKER_NETWORK=${DOCKER_NETWORK}
TS_AUTHKEY=${TS_AUTHKEY}
TS_LOGIN_SERVER=${TS_LOGIN_SERVER}
TS_EXTRA_ARGS=--advertise-tags=tag:postgres
EOF

echo "Created .env"

# Create secrets directory
mkdir -p secrets

# Write secrets
echo -n "$POSTGRES_PASS" > secrets/postgres_password
echo -n "$RAILS_APP_PASS" > secrets/rails_app_password
echo -n "$SUPERSET_PASS" > secrets/superset_password
echo -n "$DB_NAME" > secrets/db_name

chmod 644 secrets/*

echo "Created secrets/"
echo
echo "=== Setup Complete ==="
echo
echo "Service name:     $NAME"
echo "Database name:    $DB_NAME"
echo "Docker network:   $DOCKER_NETWORK"
echo "TS login server:  $TS_LOGIN_SERVER"
echo
echo "Generated passwords:"
echo "  postgres:   $POSTGRES_PASS"
echo "  rails_app:  $RAILS_APP_PASS"
echo "  superset:   $SUPERSET_PASS"
echo
echo "Connection strings:"
echo "  Rails:    postgresql://rails_app:${RAILS_APP_PASS}@v-db-${NAME}:5432/${DB_NAME}"
echo "  Superset: postgresql+psycopg2://superset:${SUPERSET_PASS}@v-db-${NAME}:5432/${DB_NAME}"
echo
echo "Run 'docker compose up -d' to start the database."
