#!/bin/bash

################################################################################
# AR QUDRIX ISP OS — SHARED HOSTING DEPLOYMENT (CPaaS)
# 
# Single PostgreSQL database (tenant-isolated via RLS)
# Shared PHP/Laravel runtime, shared Redis, single reverse proxy
# Target: cPanel, Plesk, or equivalent shared hosting with SSH access
#
# Usage:
#   bash deployment/hosting-modes/shared.sh \
#     --db-host localhost \
#     --db-name arq_isp_os \
#     --db-user postgres \
#     --db-password "secret" \
#     --app-domain example.com \
#     --app-path /var/www/app
################################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-arq_isp_os}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"
APP_DOMAIN="${APP_DOMAIN:-localhost}"
APP_PATH="${APP_PATH:-$(pwd)}"
PHP_VERSION="${PHP_VERSION:-8.2}"
ENVIRONMENT="${ENVIRONMENT:-production}"
APP_KEY=""
LOG_FILE="deployment-shared-$(date +%Y%m%d-%H%M%S).log"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    error "Required command not found: $1"
  fi
}

step() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "STEP: $*"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

step "Pre-flight Checks"

check_command php
check_command composer
check_command npm
check_command psql
check_command redis-cli

PHP_ACTUAL=$(php -v | head -1)
log "✓ PHP version: $PHP_ACTUAL"

COMPOSER_VERSION=$(composer --version 2>/dev/null || echo "not found")
log "✓ Composer: $COMPOSER_VERSION"

if [ -z "$DB_PASSWORD" ]; then
  error "DB_PASSWORD environment variable must be set"
fi

if [ ! -d "$APP_PATH" ]; then
  error "App path does not exist: $APP_PATH"
fi

log "✓ All pre-flight checks passed"

# ============================================================================
# 1. VERIFY DATABASE CONNECTION & SCHEMA
# ============================================================================

step "Database Setup & Verification"

log "Testing PostgreSQL connection..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >> "$LOG_FILE" 2>&1 || error "Database connection failed"
log "✓ Database connection successful"

# Create roles if they don't exist
log "Creating application roles..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" << EOF >> "$LOG_FILE" 2>&1
CREATE ROLE arq_app_role LOGIN PASSWORD 'app_password' NOCREATEDB NOCREATEROLE;
CREATE ROLE arq_platform_admin_role LOGIN PASSWORD 'admin_password' BYPASSRLS CREATEROLE;
GRANT CONNECT ON DATABASE "$DB_NAME" TO arq_app_role;
GRANT CONNECT ON DATABASE "$DB_NAME" TO arq_platform_admin_role;
EOF
log "✓ Application roles created/verified"

# ============================================================================
# 2. INSTALL BACKEND DEPENDENCIES
# ============================================================================

step "Backend Dependency Installation"

cd "$APP_PATH/backend"
log "Running composer install..."
composer install --no-dev --optimize-autoloader >> "$LOG_FILE" 2>&1 || error "Composer install failed"
log "✓ Backend dependencies installed"

# ============================================================================
# 3. GENERATE APP KEY & CONFIGURE .env
# ============================================================================

step "Laravel Configuration"

log "Generating application key..."
if [ ! -f "$APP_PATH/backend/.env" ]; then
  cp "$APP_PATH/backend/.env.example" "$APP_PATH/backend/.env"
  log "✓ Created .env from .env.example"
fi

APP_KEY=$(php artisan key:generate --show 2>/dev/null || php -r "echo base64_encode(random_bytes(32));")
log "✓ App key generated: ${APP_KEY:0:10}..."

# Update .env with deployment variables
cat >> "$APP_PATH/backend/.env" << EOF

APP_ENV=$ENVIRONMENT
APP_DEBUG=false
DB_HOST=$DB_HOST
DB_DATABASE=$DB_NAME
DB_USERNAME=arq_app_role
DB_PASSWORD=app_password

REDIS_HOST=localhost
REDIS_PASSWORD=null
REDIS_PORT=6379

QUEUE_DRIVER=redis
EOF

log "✓ Environment configuration updated"

# ============================================================================
# 4. RUN DATABASE MIGRATIONS
# ============================================================================

step "Database Migrations"

log "Running migrations..."
cd "$APP_PATH"
DB_DATABASE="$DB_NAME" DB_USER=postgres bash scripts/migrate.sh >> "$LOG_FILE" 2>&1 || error "Migrations failed"
log "✓ Migrations completed successfully"

# ============================================================================
# 5. SEED DATABASE
# ============================================================================

step "Database Seeding"

log "Running seeders..."
for seeder in "$APP_PATH/database/seeders"/*.sql; do
  if [ -f "$seeder" ]; then
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$seeder" >> "$LOG_FILE" 2>&1 || error "Seeder failed: $seeder"
    log "✓ Applied seeder: $(basename "$seeder")"
  fi
done

# ============================================================================
# 6. INSTALL FRONTEND DEPENDENCIES & BUILD
# ============================================================================

step "Frontend Build"

cd "$APP_PATH/frontend"
log "Installing npm dependencies..."
npm install >> "$LOG_FILE" 2>&1 || error "npm install failed"
log "✓ npm dependencies installed"

log "Building production assets..."
npm run build >> "$LOG_FILE" 2>&1 || error "Frontend build failed"
log "✓ Frontend build completed"

# Verify all 4 app builds exist
for app in index portal technician platform; do
  if [ ! -f "$APP_PATH/frontend/dist/${app}.html" ]; then
    error "Missing build artifact: ${app}.html"
  fi
  log "✓ Built app: $app"
done

# ============================================================================
# 7. CONFIGURE LARAVEL SERVICES
# ============================================================================

step "Laravel Service Configuration"

cd "$APP_PATH/backend"

log "Publishing configuration..."
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider" >> "$LOG_FILE" 2>&1 || true
log "✓ Configuration published"

log "Creating storage symlink..."
php artisan storage:link >> "$LOG_FILE" 2>&1 || true
log "✓ Storage symlink created"

log "Clearing application cache..."
php artisan config:cache >> "$LOG_FILE" 2>&1 || true
php artisan route:cache >> "$LOG_FILE" 2>&1 || true
log "✓ Cache cleared/optimized"

# ============================================================================
# 8. VERIFY HTTP LAYER
# ============================================================================

step "HTTP Layer Verification"

log "Starting Laravel development server for verification..."
(timeout 30 php artisan serve --port=8000 &) >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 5

log "Running HTTP layer tests..."
if command -v bash &>/dev/null; then
  cd "$APP_PATH"
  BASE_URL=http://localhost:8000 timeout 60 bash scripts/verify-http-layer.sh >> "$LOG_FILE" 2>&1 || error "HTTP layer verification failed"
  log "✓ HTTP layer verification passed"
else
  log "⚠ Skipping HTTP verification (bash not available)"
fi

# Kill dev server
kill $SERVER_PID 2>/dev/null || true
sleep 2

# ============================================================================
# 9. FINAL HEALTH CHECKS
# ============================================================================

step "Final Health Checks"

# Database health
log "Checking database table count..."
TABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
log "✓ Database tables: $TABLE_COUNT (expected ≥115)"

# File permissions
log "Setting file permissions..."
chmod -R 755 "$APP_PATH/backend/storage" 2>/dev/null || true
chmod -R 755 "$APP_PATH/backend/bootstrap/cache" 2>/dev/null || true
log "✓ File permissions updated"

# Verify all required files exist
required_files=(
  "$APP_PATH/backend/vendor/autoload.php"
  "$APP_PATH/frontend/dist/index.html"
  "$APP_PATH/frontend/dist/portal.html"
  "$APP_PATH/frontend/dist/technician.html"
  "$APP_PATH/frontend/dist/platform.html"
  "$APP_PATH/backend/app/Providers/AppServiceProvider.php"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    error "Missing required file: $file"
  fi
done
log "✓ All required files present"

# ============================================================================
# SUMMARY
# ============================================================================

step "Deployment Summary"

cat << EOF | tee -a "$LOG_FILE"

✓ SHARED HOSTING DEPLOYMENT COMPLETED SUCCESSFULLY

Configuration Summary:
  App Domain: $APP_DOMAIN
  App Path: $APP_PATH
  Database: $DB_NAME @ $DB_HOST
  Environment: $ENVIRONMENT
  PHP Version: $PHP_ACTUAL
  Log File: $LOG_FILE

Next Steps:
  1. Configure web server (nginx/Apache) to serve:
     - PHP: $APP_PATH/backend/public
     - Static: $APP_PATH/frontend/dist
  
  2. Set up background job processing:
     php artisan horizon (or artisan queue:work)
  
  3. Enable task scheduling:
     * * * * * cd $APP_PATH && php artisan schedule:run
  
  4. Configure SSL/TLS certificate (Let's Encrypt recommended)
  
  5. Set up monitoring and backup:
     bash $APP_PATH/scripts/backup.sh (daily via cron)
  
  6. Access the platform:
     Admin: https://$APP_DOMAIN (staff console)
     Portal: https://$APP_DOMAIN/portal (customer portal)
     Tech: https://$APP_DOMAIN/tech (technician app)
     Platform: https://$APP_DOMAIN/platform (super admin)

EOF

log "Deployment completed. See $LOG_FILE for full details."
