#!/bin/bash
set -Eeuo pipefail

# Move to the script directory (handles paths with spaces)
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMPOSE_FILE="docker-compose.yaml"
ENV_FILE=".env"

DC="docker compose"

# Basic checks
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed or not in PATH." >&2
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: $COMPOSE_FILE not found in $(pwd)" >&2
    exit 1
fi

# Create a starter .env if missing
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'EOF'
# Logging
LOG_LEVEL=warn

# Database (required)
DB_HOST=
DB_PORT=5432
DB_NAME=
DB_PASSWORD=

# Redis (optional)
REDIS_HOST=
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# SMTP (optional)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=

# JWT/Secrets (required)
AUTH_JWT_SECRET=
ADMIN_JWT_SECRET=

# Documents/S3 (required for documents-service)
S3_ACCESS_KEY=
S3_SECRET_KEY=
S3_ENDPOINT=

# Optional tags (default: latest)
# TAG_AUTH=
# TAG_ADMIN=
# TAG_USER=
# TAG_TENANT=
# TAG_AUTHZ=
# TAG_STAFF=
# TAG_PAYROLL=
# TAG_PROJECTS=
# TAG_CRM=
# TAG_DOCS=
# TAG_NOTIFICATIONS=
# TAG_ANALYTICS=
# TAG_APP_FRONTEND=
# TAG_ADMIN_DASHBOARD=

# Optional GHCR auth (only if images are private)
# GHCR_USERNAME=
# GHCR_TOKEN=
EOF
    echo "Created $ENV_FILE. Fill it with correct values and re-run." >&2
    exit 1
fi

# Load .env safely (strip CRLF and comments)
set -a
# shellcheck disable=SC1090
source <(sed -e 's/\r$//' "$ENV_FILE" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' || true)
set +a

# Validate required variables
required_vars=(
    DB_HOST DB_NAME DB_USER DB_PASSWORD
    AUTH_JWT_SECRET ADMIN_JWT_SECRET
    S3_ACCESS_KEY S3_SECRET_KEY S3_ENDPOINT
)
missing=()
for v in "${required_vars[@]}"; do
    if [ -z "${!v:-}" ]; then
        missing+=("$v")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: Missing required variables in $ENV_FILE:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

# Optional GHCR login if credentials provided
if [ -n "${GHCR_USERNAME:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
fi

# Deploy
$DC --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull
$DC --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

echo "Deploy complete."
echo "Check status with: $DC -f $COMPOSE_FILE ps"
echo "Follow logs with:  $DC -f $COMPOSE_FILE logs -f --tail=200"