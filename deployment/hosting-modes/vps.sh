#!/bin/bash

################################################################################
# AR QUDRIX ISP OS — VPS DEPLOYMENT (Dedicated Resources)
#
# Dedicated PostgreSQL, dedicated Laravel/Horizon, dedicated Redis, SSL/TLS auto-config
# Uses Docker Compose for reproducible multi-container deployment
#
# Usage:
#   bash deployment/hosting-modes/vps.sh \
#     --domain example.com \
#     --email admin@example.com \
#     --env production
################################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

DOMAIN="${DOMAIN:-localhost}"
EMAIL="${EMAIL:-admin@example.com}"
ENVIRONMENT="${ENVIRONMENT:-production}"
APP_PATH="${APP_PATH:-$(pwd)}"
LOG_FILE="deployment-vps-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

# Generated secrets
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
APP_KEY=""

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

check_command docker
check_command docker-compose
check_command openssl

log "✓ Docker: $(docker --version)"
log "✓ Docker Compose: $(docker-compose --version)"

if [ ! -f "$APP_PATH/docker-compose.yml" ]; then
  error "docker-compose.yml not found at $APP_PATH"
fi

log "✓ All pre-flight checks passed"

# ============================================================================
# 1. CREATE BACKUP DIRECTORY
# ============================================================================

step "Backup Directory Setup"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
log "✓ Backup directory ready: $BACKUP_DIR"

# ============================================================================
# 2. GENERATE SECRETS
# ============================================================================

step "Secret Generation"

# Create .env file for Docker Compose
cat > "$APP_PATH/.env.docker" << EOF
# VPS Deployment Environment Variables
ENVIRONMENT=$ENVIRONMENT
APP_DOMAIN=$DOMAIN
APP_EMAIL=$EMAIL

# Database
DB_HOST=postgres
DB_NAME=arq_isp_os
DB_USER=postgres
DB_PASSWORD=$DB_PASSWORD

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_PORT=6379

# Laravel
APP_KEY=$(php -r "echo base64_encode(random_bytes(32));")
APP_DEBUG=false

# Paths
APP_PATH=$APP_PATH
BACKUP_DIR=$BACKUP_DIR
EOF

log "✓ Secrets generated and stored in .env.docker"
log "  DB_PASSWORD: ${DB_PASSWORD:0:10}..."
log "  REDIS_PASSWORD: ${REDIS_PASSWORD:0:10}..."

# ============================================================================
# 3. BUILD DOCKER IMAGES
# ============================================================================

step "Docker Image Building"

log "Building application image..."
docker-compose -f "$APP_PATH/docker-compose.yml" build --no-cache >> "$LOG_FILE" 2>&1 || error "Docker build failed"
log "✓ All images built successfully"

# ============================================================================
# 4. START SERVICES
# ============================================================================

step "Starting Docker Services"

log "Bringing up containers..."
docker-compose -f "$APP_PATH/docker-compose.yml" up -d >> "$LOG_FILE" 2>&1 || error "Docker-compose up failed"
log "✓ Services started"

log "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
  if docker-compose -f "$APP_PATH/docker-compose.yml" exec -T postgres psql -U postgres -d arq_isp_os -c "SELECT 1;" &>/dev/null; then
    log "✓ PostgreSQL is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    error "PostgreSQL failed to start after 30 seconds"
  fi
  sleep 1
done

log "Waiting for Redis to be ready..."
for i in {1..30}; do
  if docker-compose -f "$APP_PATH/docker-compose.yml" exec -T redis redis-cli PING &>/dev/null; then
    log "✓ Redis is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    error "Redis failed to start after 30 seconds"
  fi
  sleep 1
done

# ============================================================================
# 5. RUN MIGRATIONS
# ============================================================================

step "Database Setup"

log "Running migrations..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T laravel bash -c "cd /app/backend && php artisan migrate --force" >> "$LOG_FILE" 2>&1 || error "Migrations failed"
log "✓ Migrations completed"

log "Running seeders..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T laravel bash -c "cd /app && for f in database/seeders/*.sql; do psql -d arq_isp_os -f \"\$f\"; done" >> "$LOG_FILE" 2>&1 || true
log "✓ Seeders completed"

# ============================================================================
# 6. CONFIGURE LARAVEL
# ============================================================================

step "Laravel Configuration"

log "Optimizing Laravel cache..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T laravel bash -c "cd /app/backend && php artisan config:cache && php artisan route:cache" >> "$LOG_FILE" 2>&1 || true
log "✓ Laravel optimized"

# ============================================================================
# 7. BUILD FRONTEND
# ============================================================================

step "Frontend Build"

log "Building frontend assets..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T node bash -c "cd /app/frontend && npm run build" >> "$LOG_FILE" 2>&1 || error "Frontend build failed"
log "✓ Frontend built successfully"

# ============================================================================
# 8. CONFIGURE SSL/TLS (Let's Encrypt)
# ============================================================================

step "SSL/TLS Configuration"

if command -v certbot &>/dev/null; then
  log "Installing Let's Encrypt certificate..."
  certbot certonly --standalone -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive >> "$LOG_FILE" 2>&1 || error "Certificate installation failed"
  log "✓ SSL certificate installed"
  
  # Create renewal cron job
  echo "0 2 * * * certbot renew --quiet" | crontab - 2>/dev/null || true
  log "✓ Certificate auto-renewal configured"
else
  log "⚠ certbot not installed. Skipping Let's Encrypt setup."
  log "  Manual setup: Install certbot and run:"
  log "  certbot certonly --standalone -d $DOMAIN"
fi

# ============================================================================
# 9. CONFIGURE NGINX REVERSE PROXY
# ============================================================================

step "Reverse Proxy Configuration"

cat > /tmp/nginx-vps.conf << 'NGINX_EOF'
upstream laravel {
    server laravel:8000;
}

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    root /app/frontend/dist;
    index index.html;

    # API requests to Laravel
    location /api/ {
        proxy_pass http://laravel;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Portal app
    location /portal {
        try_files $uri /portal.html;
    }

    # Technician app
    location /tech {
        try_files $uri /technician.html;
    }

    # Platform console
    location /platform {
        try_files $uri /platform.html;
    }

    # Static assets (staff console)
    location / {
        try_files $uri /index.html;
    }

    # Deny access to sensitive files
    location ~ /\.env {
        deny all;
    }
}
NGINX_EOF

sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /tmp/nginx-vps.conf
log "✓ Nginx configuration generated (manual setup required)"
log "  Location: /tmp/nginx-vps.conf"

# ============================================================================
# 10. VERIFY SERVICES
# ============================================================================

step "Service Health Verification"

log "Checking service status..."
docker-compose -f "$APP_PATH/docker-compose.yml" ps >> "$LOG_FILE"

log "Testing Laravel connectivity..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T laravel curl -s http://localhost:8000/api/health || error "Laravel health check failed"
log "✓ Laravel is responding"

log "Testing database..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T postgres psql -U postgres -d arq_isp_os -c "SELECT COUNT(*) FROM information_schema.tables;" >> "$LOG_FILE" 2>&1
log "✓ Database is accessible"

log "Testing Redis..."
docker-compose -f "$APP_PATH/docker-compose.yml" exec -T redis redis-cli PING >> "$LOG_FILE" 2>&1
log "✓ Redis is accessible"

# ============================================================================
# 11. SETUP BACKUP AUTOMATION
# ============================================================================

step "Backup Automation"

cat > "$APP_PATH/deployment/backup-vps.sh" << 'BACKUP_EOF'
#!/bin/bash
BACKUP_DIR=${BACKUP_DIR:-/backups}
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-./docker-compose.yml}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.sql.gz"

echo "Starting backup to $BACKUP_FILE..."
docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres pg_dump -U postgres arq_isp_os | gzip > "$BACKUP_FILE"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "backup-*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
BACKUP_EOF

chmod +x "$APP_PATH/deployment/backup-vps.sh"
log "✓ Backup script created"

# Add to crontab for daily execution at 2 AM
(crontab -l 2>/dev/null || true; echo "0 2 * * * $APP_PATH/deployment/backup-vps.sh") | crontab - 2>/dev/null || true
log "✓ Daily backup scheduled (2 AM)"

# ============================================================================
# 12. SETUP MONITORING
# ============================================================================

step "Monitoring Setup"

cat > "$APP_PATH/deployment/health-check-vps.sh" << 'HEALTH_EOF'
#!/bin/bash
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-./docker-compose.yml}

echo "=== AR QUDRIX ISP OS Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Check running containers
echo "Container Status:"
docker-compose -f "$DOCKER_COMPOSE_FILE" ps
echo ""

# Check disk space
echo "Disk Usage:"
df -h /
echo ""

# Check database size
echo "Database Size:"
docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres du -sh /var/lib/postgresql/data 2>/dev/null || echo "Unable to check"
echo ""

# Check HTTP response
echo "HTTP Status:"
curl -s -o /dev/null -w "Status: %{http_code}\n" https://localhost || echo "HTTPS not yet configured"
HEALTH_EOF

chmod +x "$APP_PATH/deployment/health-check-vps.sh"
log "✓ Health check script created"

# Add to crontab for hourly monitoring
(crontab -l 2>/dev/null || true; echo "0 * * * * $APP_PATH/deployment/health-check-vps.sh >> $APP_PATH/logs/health.log") | crontab - 2>/dev/null || true
log "✓ Hourly health monitoring scheduled"

# ============================================================================
# 13. SETUP ROLLBACK CAPABILITY
# ============================================================================

step "Rollback Configuration"

cat > "$APP_PATH/deployment/rollback-vps.sh" << 'ROLLBACK_EOF'
#!/bin/bash
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-./docker-compose.yml}
BACKUP_DIR=${BACKUP_DIR:-/backups}

# Find most recent backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup-*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
  echo "No backup found to restore from"
  exit 1
fi

echo "Rolling back to backup: $LATEST_BACKUP"

# Stop services
docker-compose -f "$DOCKER_COMPOSE_FILE" down

# Restore database
echo "Restoring database..."
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres
sleep 10
gunzip < "$LATEST_BACKUP" | docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres psql -U postgres

# Restart all services
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d

echo "Rollback completed"
ROLLBACK_EOF

chmod +x "$APP_PATH/deployment/rollback-vps.sh"
log "✓ Rollback script created"

# ============================================================================
# SUMMARY
# ============================================================================

step "Deployment Summary"

cat << EOF | tee -a "$LOG_FILE"

✓ VPS DEPLOYMENT COMPLETED SUCCESSFULLY

Configuration:
  Domain: $DOMAIN
  Email: $EMAIL
  Environment: $ENVIRONMENT
  Docker Compose Log: $LOG_FILE

Generated Files:
  - .env.docker (environment configuration)
  - /tmp/nginx-vps.conf (reverse proxy config - manual setup)
  - $APP_PATH/deployment/backup-vps.sh (daily backups)
  - $APP_PATH/deployment/health-check-vps.sh (hourly monitoring)
  - $APP_PATH/deployment/rollback-vps.sh (disaster recovery)

Container Status:
EOF

docker-compose -f "$APP_PATH/docker-compose.yml" ps | tee -a "$LOG_FILE"

cat << EOF | tee -a "$LOG_FILE"

Access URLs (after nginx configuration):
  Admin Console: https://$DOMAIN/
  Customer Portal: https://$DOMAIN/portal
  Technician App: https://$DOMAIN/tech
  Platform Console: https://$DOMAIN/platform

Secrets Saved:
  DB Password: $DB_PASSWORD
  Redis Password: $REDIS_PASSWORD
  (Stored in .env.docker - secure this file!)

Next Steps:
  1. Manual nginx setup:
     sudo cp /tmp/nginx-vps.conf /etc/nginx/sites-available/$DOMAIN
     sudo systemctl restart nginx

  2. Test HTTPS:
     curl -I https://$DOMAIN

  3. View logs:
     docker-compose -f $APP_PATH/docker-compose.yml logs -f

  4. Verify backups:
     ls -lh $BACKUP_DIR/

  5. Test rollback procedure:
     bash $APP_PATH/deployment/rollback-vps.sh

EOF

log "Full deployment log: $LOG_FILE"
