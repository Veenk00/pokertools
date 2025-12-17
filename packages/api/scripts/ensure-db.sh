#!/bin/bash
# Ensures database and Redis are ready before starting the API
# This script ensures the database schema is in sync with Prisma schema

set -e

# Ensure Redis is running first
bash "$(dirname "$0")/ensure-redis.sh"

# Create runtime directory for all temporary/generated files
RUNTIME_DIR="$PWD/.runtime"
mkdir -p "$RUNTIME_DIR"

# Determine which .env file to use based on NODE_ENV
if [ "$NODE_ENV" = "test" ]; then
  ENV_FILE=".env.test"
  DEFAULT_DB_PATH="../.runtime/test.db"
else
  ENV_FILE=".env"
  DEFAULT_DB_PATH="../.runtime/dev.db"
fi

# Use DATABASE_URL from environment if set, otherwise parse from .env file
if [ -n "$DATABASE_URL" ]; then
  # Extract path from DATABASE_URL (handles both file:./path and file:path formats)
  DB_PATH=$(echo "$DATABASE_URL" | sed 's|^file:||')
  # Normalize: remove leading ./ if present
  DB_PATH=$(echo "$DB_PATH" | sed 's|^\./||')
  
  # If path starts with packages/api/, normalize it to be relative to packages/api directory
  # This handles GitHub Actions where DATABASE_URL is set relative to workspace root
  if [[ "$DB_PATH" == packages/api/* ]]; then
    DB_PATH="${DB_PATH#packages/api/}"
    export DATABASE_URL="file:$DB_PATH"
  else
    # Keep original DATABASE_URL, Prisma will resolve it relative to schema location
    export DATABASE_URL
  fi
else
  # Parse DATABASE_URL from appropriate .env file to get the database path
  ENV_DB_URL=$(grep "^DATABASE_URL=" "$ENV_FILE" 2>/dev/null | cut -d'"' -f2 || cut -d'=' -f2- | tr -d ' ' || echo "")
  if [ -n "$ENV_DB_URL" ]; then
    DB_PATH=$(echo "$ENV_DB_URL" | sed 's|^file:||' | sed 's|^\./||')
    export DATABASE_URL="$ENV_DB_URL"
  else
    DB_PATH="$DEFAULT_DB_PATH"
    export DATABASE_URL="file:$DB_PATH"
  fi
fi

# Convert relative path for file existence check
# Handle both ../.runtime/test.db and .runtime/test.db formats
if [[ "$DB_PATH" == ../* ]]; then
  DB_FILE="$DB_PATH"
else
  DB_FILE="./$DB_PATH"
fi

# Ensure the directory for the database file exists
DB_DIR=$(dirname "$DB_FILE")
mkdir -p "$DB_DIR"

# Check if database file exists
if [ ! -f "$DB_FILE" ]; then
  echo "📦 Database not found at $DB_FILE, creating..."
else
  echo "✅ Database found at $DB_FILE"
fi

# Always run prisma db push to ensure schema is in sync
# This is safe because --accept-data-loss only affects data, not schema
echo "🔄 Syncing database schema..."
npx prisma db push --skip-generate --accept-data-loss
echo "✅ Database schema synced successfully!"
