#!/bin/bash
set -e

# ==========================================
# Configuration
# ==========================================
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"

# ==========================================
# Function: Generate random password
# ==========================================
generate_password() {
  openssl rand -base64 24
}

# ==========================================
# Function: Create .env if missing
# ==========================================
if [ ! -f "$ENV_FILE" ]; then
  echo "🔐 Generating new environment file..."
  
  POSTGRES_USER="admin"
  POSTGRES_PASSWORD=$(generate_password)
  POSTGRES_DB="appdb"

  REDIS_PASSWORD=$(generate_password)

  MINIO_ROOT_USER="minioadmin"
  MINIO_ROOT_PASSWORD=$(generate_password)

  cat > "$ENV_FILE" <<EOF
# Auto-generated environment file
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB

REDIS_PASSWORD=$REDIS_PASSWORD

MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
EOF

  chmod 600 "$ENV_FILE"
  echo "✅ Environment file created: $ENV_FILE"
else
  echo "ℹ️ Using existing environment file: $ENV_FILE"
fi

# ==========================================
# Show summary
# ==========================================
echo "-----------------------------------------"
echo "Loaded environment variables:"
grep -v '^#' "$ENV_FILE" | grep -E 'USER|DB|PASSWORD' | sed 's/^/  /'
echo "-----------------------------------------"

# ==========================================
# Build and start containers
# ==========================================
echo "🚀 Building and starting Docker Compose stack..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

echo "✅ Stack is up and running!"
