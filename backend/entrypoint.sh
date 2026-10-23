#!/usr/bin/env bash
set -e

# Optional debug
if [ "$DEBUG" = "true" ]; then
  set -x
fi

echo "=== [Entrypoint] Starting container initialization..."

# Validate required env vars (example)
required_vars=("DATABASE_HOST" "DATABASE_USER" "DATABASE_PASSWORD" "PORT")
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Environment variable $var is not set." >&2
    exit 1
  fi
done

# Run migrations if flag set
if [ "$RUN_MIGRATIONS" = "true" ]; then
  echo "=== [Entrypoint] Running DB migrations..."
  # Example command, adjust for your stack
  # npx prisma migrate deploy
  # flask db upgrade
fi

echo "=== [Entrypoint] Initialization complete. Launching app..."
exec "$@"