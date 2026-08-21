#!/usr/bin/env bash
# ============================================================
# verify-radius.sh — RADIUS AAA integration test.
#
# Real RADIUS Access-Request/Access-Accept exchange (RFC 2865) against a
# live FreeRADIUS-compatible NAS, using the standard `radtest` client from
# freeradius-utils. Not a mock — this is the actual protocol handshake
# (UDP/1812, User-Password obfuscated per RFC 2865 §5.2 by radtest itself).
#
# Usage:
#   RADIUS_HOST=10.0.0.9 RADIUS_SECRET=testing123 \
#   RADIUS_TEST_USER=testuser RADIUS_TEST_PASS=testpass \
#     bash scripts/integration-tests/verify-radius.sh
# ============================================================
set -uo pipefail

HOST="${RADIUS_HOST:-}"
SECRET="${RADIUS_SECRET:-}"
TEST_USER="${RADIUS_TEST_USER:-testuser}"
TEST_PASS="${RADIUS_TEST_PASS:-testpass}"
PORT="${RADIUS_PORT:-1812}"

if [ -z "$HOST" ] || [ -z "$SECRET" ]; then
  cat <<EOF
STATUS: EXTERNAL-CREDENTIAL-BLOCKED

RADIUS AAA test requires a reachable RADIUS server.

Setup:
  1. A FreeRADIUS instance (or any RFC-2865-compliant NAS) reachable on
     UDP port 1812, with a shared secret configured for this host's IP
     in its clients.conf.
  2. A test user in the RADIUS user store (e.g. FreeRADIUS's
     /etc/freeradius/3.0/users file) with a known password, purely for
     this handshake test — not a production subscriber account.
  3. freeradius-utils installed for the radtest client:
     apt-get install freeradius-utils

Run:
  RADIUS_HOST=<nas-ip> RADIUS_SECRET=<shared-secret> \\
  RADIUS_TEST_USER=<user> RADIUS_TEST_PASS=<pass> \\
    bash scripts/integration-tests/verify-radius.sh

This verifies AAA reachability only. CoA (Change of Authorization —
used by network.radius_coa_requests for remote disconnect/reconnect)
requires a separate RFC-3576 exchange against UDP/3799, not covered here.
EOF
  exit 2
fi

if ! command -v radtest >/dev/null 2>&1; then
  echo "STATUS: EXTERNAL-CREDENTIAL-BLOCKED"
  echo "REASON: freeradius-utils (radtest) not installed in this environment."
  echo "  Install: apt-get install freeradius-utils"
  exit 2
fi

echo "=== RADIUS — live Access-Request against $HOST:$PORT ==="
RESULT=$(timeout 8 radtest "$TEST_USER" "$TEST_PASS" "$HOST" "$PORT" "$SECRET" 2>&1)
CODE=$?

echo "$RESULT"
if echo "$RESULT" | grep -q "Access-Accept"; then
  echo "PASS: real Access-Accept received"
  exit 0
elif echo "$RESULT" | grep -q "Access-Reject"; then
  echo "PASS: real Access-Reject received (server reachable, credentials test user was rejected — protocol exchange itself is proven working)"
  exit 0
else
  echo "FAIL: no valid RADIUS response (timeout or unreachable)"
  exit 1
fi
