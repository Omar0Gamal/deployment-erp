#!/bin/bash

# Update script for deploying Docker services on Hetzner VPS
# Usage: ./update.sh <github_token> <github_actor> <branch_name>

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get arguments
GITHUB_TOKEN="$1"
GITHUB_ACTOR="$2"
BRANCH_NAME="$3"

# Verify we're in the right directory
if [ ! -f "docker-compose.yaml" ] && [ ! -f "docker-compose.yml" ]; then
    log_error "docker-compose.yaml not found in current directory!"
    exit 1
fi

log_info "========================================"
log_info "Starting deployment process..."
log_info "Branch: $BRANCH_NAME"
log_info "========================================"

# Login to GitHub Container Registry
log_step "Logging in to GitHub Container Registry..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin 2>&1 | grep -v "WARNING"

if [ $? -ne 0 ]; then
    log_error "Failed to login to GitHub Container Registry"
    exit 1
fi
log_info "✓ Login successful"

# Pull latest code if git repo exists
if [ -d ".git" ]; then
    log_step "Pulling latest code from branch: $BRANCH_NAME"
    git pull origin "$BRANCH_NAME" 2>&1 || log_warn "Git pull failed or already up to date"
    log_info "✓ Code updated"
else
    log_warn "Not a git repository, skipping code pull"
fi

# Load environment variables if .env file exists
if [ -f ".env" ]; then
    log_step "Loading environment variables from .env file..."
    set -a
    source .env
    set +a
    log_info "✓ Environment variables loaded"
fi

# Stop running services
log_step "Stopping running services..."
docker compose down 2>&1

if [ $? -ne 0 ]; then
    log_error "Failed to stop services"
    exit 1
fi
log_info "✓ Services stopped"

# Pull new images
log_step "Pulling new Docker images..."
log_info "This may take a while depending on image sizes..."
docker compose pull 2>&1

if [ $? -ne 0 ]; then
    log_error "Failed to pull Docker images"
    exit 1
fi
log_info "✓ Images pulled successfully"

# Start services in detached mode
log_step "Starting services..."
docker compose up -d 2>&1

if [ $? -ne 0 ]; then
    log_error "Failed to start services"
    log_info "Attempting to show logs for debugging..."
    docker compose logs --tail=50
    exit 1
fi
log_info "✓ Services started"

# Wait for services to initialize
log_step "Waiting for services to initialize..."
sleep 10

# Show running containers
log_step "Current running services:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Count running services
RUNNING_COUNT=$(docker compose ps --filter "status=running" --format json | jq -s 'length')
TOTAL_COUNT=$(docker compose ps --format json | jq -s 'length')
log_info "Running: $RUNNING_COUNT/$TOTAL_COUNT services"

# Check for unhealthy containers
log_step "Checking container health..."
UNHEALTHY=$(docker compose ps --format json | jq -r 'select(.Health == "unhealthy" or (.State != "running" and .State != "created")) | .Name' 2>/dev/null || echo "")

if [ -n "$UNHEALTHY" ]; then
    log_warn "Issues detected with the following containers:"
    echo "$UNHEALTHY"
    log_warn "Showing logs for problematic containers:"
    echo "$UNHEALTHY" | while read -r container; do
        if [ -n "$container" ]; then
            echo "--- Logs for $container ---"
            docker logs "$container" --tail=20 2>&1 || true
        fi
    done
else
    log_info "✓ All containers are healthy!"
fi

# Clean up old images to save disk space
log_step "Cleaning up old Docker images..."
BEFORE_CLEANUP=$(df -h / | awk 'NR==2 {print $4}')
docker image prune -af 2>&1 > /dev/null
AFTER_CLEANUP=$(df -h / | awk 'NR==2 {print $4}')
log_info "✓ Cleanup complete (Free space: $BEFORE_CLEANUP → $AFTER_CLEANUP)"

# Show resource usage
log_step "Resource usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || log_warn "Could not retrieve stats"

# Logout from registry
docker logout ghcr.io 2>&1 > /dev/null

log_info "========================================"
log_info "✓ Deployment completed successfully!"
log_info "========================================"

# Exit with appropriate code
if [ -n "$UNHEALTHY" ]; then
    log_warn "Deployment completed with warnings"
    exit 0
else
    exit 0
fi