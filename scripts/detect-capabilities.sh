#!/bin/bash

################################################################################
# AR QUDRIX ISP OS — ENVIRONMENT CAPABILITY DETECTION
#
# Detects and reports available system features, external services, and integrations
# Returns JSON for runtime feature flag configuration
#
# Usage:
#   bash scripts/detect-capabilities.sh [--json] [--verbose]
################################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

OUTPUT_FORMAT="${1:-text}"
VERBOSE="${2:-false}"
CAPABILITIES_FILE="${CAPABILITIES_FILE:-/tmp/arq-capabilities.json}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
  if [ "$VERBOSE" = "true" ]; then
    echo "[*] $*" >&2
  fi
}

check_command() {
  if command -v "$1" &>/dev/null; then
    log "✓ Found: $1"
    return 0
  else
    log "✗ Missing: $1"
    return 1
  fi
}

check_port() {
  if (echo >/dev/tcp/127.0.0.1/"$1") 2>/dev/null; then
    log "✓ Port $1 open"
    return 0
  else
    log "✗ Port $1 closed"
    return 1
  fi
}

check_library() {
  php -r "extension_loaded('$1');" 2>/dev/null && return 0 || return 1
}

# ============================================================================
# CAPABILITY DETECTION
# ============================================================================

# Initialize JSON structure
json_output='{
  "timestamp": "'$(date -Iseconds)'",
  "hostname": "'$(hostname)'",
  "capabilities": {
    "database": {},
    "cache": {},
    "queue": {},
    "messaging": {},
    "monitoring": {},
    "integrations": {},
    "security": {},
    "performance": {}
  },
  "warnings": [],
  "errors": []
}'

# Function to add capability to JSON
add_capability() {
  local category=$1
  local key=$2
  local value=$3
  local detail=${4:-""}
  
  # Add to JSON using jq if available, otherwise build manually
  if command -v jq &>/dev/null; then
    json_output=$(echo "$json_output" | jq \
      --arg cat "$category" \
      --arg k "$key" \
      --arg v "$value" \
      --arg detail "$detail" \
      '.capabilities[$cat][$k] = {available: ($v == "true"), detail: $detail}')
  fi
  
  # Also add to text output
  local status="✓"
  [ "$value" = "false" ] && status="✗"
  log "$status $category.$key: $detail"
}

# ============================================================================
# 1. DATABASE CAPABILITIES
# ============================================================================

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "DATABASE CAPABILITIES"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# PostgreSQL
if check_command psql; then
  PG_VERSION=$(psql --version 2>/dev/null || echo "unknown")
  add_capability "database" "postgresql" "true" "$PG_VERSION"
  
  # Test connection
  if PGPASSWORD="${DB_PASSWORD:-}" psql -h "${DB_HOST:-localhost}" -U "${DB_USER:-postgres}" -d "${DB_NAME:-postgres}" -c "SELECT 1;" &>/dev/null; then
    add_capability "database" "postgresql_connection" "true" "Connected"
  else
    add_capability "database" "postgresql_connection" "false" "Connection failed"
  fi
else
  add_capability "database" "postgresql" "false" "psql not found"
fi

# MySQL/MariaDB
if check_command mysql; then
  MYSQL_VERSION=$(mysql --version 2>/dev/null || echo "unknown")
  add_capability "database" "mysql" "true" "$MYSQL_VERSION"
else
  add_capability "database" "mysql" "false" "mysql not found"
fi

# SQLite
if check_command sqlite3; then
  SQLITE_VERSION=$(sqlite3 --version 2>/dev/null || echo "unknown")
  add_capability "database" "sqlite3" "true" "$SQLITE_VERSION"
else
  add_capability "database" "sqlite3" "false" "sqlite3 not found"
fi

# PHP Database Extensions
check_library "pgsql" && add_capability "database" "php_pgsql" "true" "PHP PostgreSQL support" || add_capability "database" "php_pgsql" "false" "Missing PHP PostgreSQL extension"
check_library "mysqli" && add_capability "database" "php_mysqli" "true" "PHP MySQL support" || add_capability "database" "php_mysqli" "false" "Missing PHP MySQL extension"
check_library "pdo_sqlite" && add_capability "database" "php_pdo_sqlite" "true" "PHP SQLite support" || add_capability "database" "php_pdo_sqlite" "false" "Missing PHP SQLite extension"

# ============================================================================
# 2. CACHE & QUEUE CAPABILITIES
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "CACHE & QUEUE CAPABILITIES"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Redis
if check_command redis-cli; then
  REDIS_VERSION=$(redis-cli --version 2>/dev/null || echo "unknown")
  add_capability "cache" "redis" "true" "$REDIS_VERSION"
  
  if redis-cli -h "${REDIS_HOST:-localhost}" PING &>/dev/null; then
    add_capability "cache" "redis_connection" "true" "Connected"
  else
    add_capability "cache" "redis_connection" "false" "Connection failed"
  fi
else
  add_capability "cache" "redis" "false" "redis-cli not found"
fi

# Memcached
if check_command memcached; then
  add_capability "cache" "memcached" "true" "Memcached available"
  
  if check_port 11211; then
    add_capability "cache" "memcached_connection" "true" "Connected on port 11211"
  else
    add_capability "cache" "memcached_connection" "false" "Port 11211 not responding"
  fi
else
  add_capability "cache" "memcached" "false" "memcached not found"
fi

# PHP Cache Extensions
check_library "redis" && add_capability "cache" "php_redis" "true" "PHP Redis extension" || add_capability "cache" "php_redis" "false" "Missing PHP Redis extension"
check_library "memcached" && add_capability "cache" "php_memcached" "true" "PHP Memcached extension" || add_capability "cache" "php_memcached" "false" "Missing PHP Memcached extension"

# ============================================================================
# 3. MESSAGING & NOTIFICATIONS
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "MESSAGING & NOTIFICATIONS"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# RabbitMQ
if check_command rabbitmqctl; then
  add_capability "messaging" "rabbitmq" "true" "RabbitMQ available"
else
  add_capability "messaging" "rabbitmq" "false" "rabbitmqctl not found"
fi

# Kafka
if check_command kafka-topics.sh; then
  add_capability "messaging" "kafka" "true" "Kafka available"
else
  add_capability "messaging" "kafka" "false" "Kafka not found"
fi

# Mail (sendmail/postfix)
if check_command sendmail; then
  add_capability "messaging" "sendmail" "true" "Sendmail available"
else
  add_capability "messaging" "sendmail" "false" "Sendmail not found"
fi

check_library "mbstring" && add_capability "messaging" "php_mbstring" "true" "PHP multibyte support" || add_capability "messaging" "php_mbstring" "false" "Missing"

# ============================================================================
# 4. NETWORK INTEGRATIONS
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "NETWORK INTEGRATIONS"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# SNMP
if check_command snmpget; then
  add_capability "integrations" "snmp" "true" "SNMP tools available"
else
  add_capability "integrations" "snmp" "false" "snmpget not found"
fi

# RADIUS
if check_command radtest; then
  add_capability "integrations" "radius" "true" "RADIUS tools available"
else
  add_capability "integrations" "radius" "false" "radtest not found"
fi

# FreeRADIUS
if check_command freeradius; then
  add_capability "integrations" "freeradius_server" "true" "FreeRADIUS server available"
else
  add_capability "integrations" "freeradius_server" "false" "freeradius not found"
fi

# SSH (for device management)
if check_command ssh; then
  add_capability "integrations" "ssh" "true" "SSH available"
else
  add_capability "integrations" "ssh" "false" "ssh not found"
fi

# cURL (for API calls)
if check_command curl; then
  add_capability "integrations" "curl" "true" "cURL available"
else
  add_capability "integrations" "curl" "false" "curl not found"
fi

check_library "curl" && add_capability "integrations" "php_curl" "true" "PHP cURL support" || add_capability "integrations" "php_curl" "false" "Missing"

# ============================================================================
# 5. SECURITY CAPABILITIES
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "SECURITY CAPABILITIES"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# OpenSSL
if check_command openssl; then
  SSL_VERSION=$(openssl version 2>/dev/null || echo "unknown")
  add_capability "security" "openssl" "true" "$SSL_VERSION"
else
  add_capability "security" "openssl" "false" "openssl not found"
fi

# GnuPG
if check_command gpg; then
  add_capability "security" "gnupg" "true" "GPG available"
else
  add_capability "security" "gnupg" "false" "gpg not found"
fi

check_library "openssl" && add_capability "security" "php_openssl" "true" "PHP OpenSSL support" || add_capability "security" "php_openssl" "false" "Missing"
check_library "bcmath" && add_capability "security" "php_bcmath" "true" "PHP bcmath support" || add_capability "security" "php_bcmath" "false" "Missing"

# ============================================================================
# 6. PERFORMANCE MONITORING
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "PERFORMANCE MONITORING"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Prometheus
if check_command prometheus; then
  add_capability "monitoring" "prometheus" "true" "Prometheus available"
else
  add_capability "monitoring" "prometheus" "false" "prometheus not found"
fi

# Grafana
if check_command grafana-server; then
  add_capability "monitoring" "grafana" "true" "Grafana available"
else
  add_capability "monitoring" "grafana" "false" "grafana-server not found"
fi

# Performance PHP extensions
check_library "opcache" && add_capability "performance" "php_opcache" "true" "PHP OpCache enabled" || add_capability "performance" "php_opcache" "false" "Missing"
check_library "xdebug" && add_capability "performance" "php_xdebug" "true" "PHP Xdebug (dev only)" || add_capability "performance" "php_xdebug" "false" "Not installed"

# ============================================================================
# 7. CONTAINERIZATION
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "CONTAINERIZATION"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Docker
if check_command docker; then
  DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
  add_capability "integrations" "docker" "true" "$DOCKER_VERSION"
else
  add_capability "integrations" "docker" "false" "docker not found"
fi

# Docker Compose
if check_command docker-compose; then
  DC_VERSION=$(docker-compose --version 2>/dev/null || echo "unknown")
  add_capability "integrations" "docker_compose" "true" "$DC_VERSION"
else
  add_capability "integrations" "docker_compose" "false" "docker-compose not found"
fi

# Kubernetes
if check_command kubectl; then
  K8S_VERSION=$(kubectl version --client --short 2>/dev/null || echo "unknown")
  add_capability "integrations" "kubernetes" "true" "$K8S_VERSION"
else
  add_capability "integrations" "kubernetes" "false" "kubectl not found"
fi

# ============================================================================
# 8. SYSTEM RESOURCES
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "SYSTEM RESOURCES"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Memory
TOTAL_MEMORY=$(free -h | grep Mem | awk '{print $2}')
log "Total Memory: $TOTAL_MEMORY"

# Disk Space
AVAILABLE_DISK=$(df -h / | tail -1 | awk '{print $4}')
log "Available Disk: $AVAILABLE_DISK"

# CPU Cores
CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
log "CPU Cores: $CPU_CORES"

# PHP Configuration
PHP_MEMORY=$(php -r 'echo ini_get("memory_limit");' 2>/dev/null)
PHP_UPLOAD=$(php -r 'echo ini_get("upload_max_filesize");' 2>/dev/null)
log "PHP Memory Limit: $PHP_MEMORY"
log "PHP Upload Limit: $PHP_UPLOAD"

# ============================================================================
# OUTPUT
# ============================================================================

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "CAPABILITY DETECTION COMPLETE"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Output in requested format
if [ "$OUTPUT_FORMAT" = "--json" ] && command -v jq &>/dev/null; then
  echo "$json_output" | jq '.' > "$CAPABILITIES_FILE"
  cat "$CAPABILITIES_FILE"
else
  # Text output
  echo ""
  echo "Summary saved to: $CAPABILITIES_FILE"
fi

# Exit successfully
exit 0
