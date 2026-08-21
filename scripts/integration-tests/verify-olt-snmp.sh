#!/usr/bin/env bash
# ============================================================
# verify-olt-snmp.sh — OLT SNMP integration test.
#
# Real SNMP GET against sysDescr (.1.3.6.1.2.1.1.1.0), the universal
# OID every SNMP-speaking device answers regardless of vendor (BDCOM,
# V-SOL, ZTE, Huawei, Fiberhome). Confirms real UDP/161 reachability and
# a real community-string-authenticated response — not a mock.
#
# Usage:
#   OLT_HOST=10.0.0.5 OLT_COMMUNITY=public bash scripts/integration-tests/verify-olt-snmp.sh
# ============================================================
set -uo pipefail

HOST="${OLT_HOST:-}"
COMMUNITY="${OLT_COMMUNITY:-public}"
PORT="${OLT_SNMP_PORT:-161}"

if [ -z "$HOST" ]; then
  cat <<EOF
STATUS: EXTERNAL-CREDENTIAL-BLOCKED

OLT SNMP test requires a reachable OLT device.

Setup:
  1. A physical OLT (BDCOM/V-SOL/ZTE/Huawei/Fiberhome) or vendor SNMP
     simulator reachable from this host on UDP port 161.
  2. SNMP read community string configured on the device (default is
     often "public" but production devices should use a non-default one).

Run:
  OLT_HOST=<olt-ip> OLT_COMMUNITY=<community> \\
    bash scripts/integration-tests/verify-olt-snmp.sh

Vendor-specific ONU/PON/signal OIDs differ per manufacturer and are NOT
exercised by this script — it verifies basic SNMP reachability only.
Full vendor MIB walks (ONU discovery, RX/TX power) are implemented in
App\Services\OltService and require per-vendor MIB files to complete —
see backend/app/Services/OltService.php for the integration boundary.
EOF
  exit 2
fi

if ! command -v snmpget >/dev/null 2>&1; then
  echo "STATUS: EXTERNAL-CREDENTIAL-BLOCKED"
  echo "REASON: net-snmp tools (snmpget) not installed in this environment."
  echo "  Install: apt-get install snmp   (or equivalent for your OS)"
  exit 2
fi

echo "=== OLT SNMP — live sysDescr query against $HOST:$PORT ==="
RESULT=$(timeout 8 snmpget -v2c -c "$COMMUNITY" -t 5 -r 1 "$HOST:$PORT" 1.3.6.1.2.1.1.1.0 2>&1)
CODE=$?

if [ $CODE -ne 0 ]; then
  echo "FAIL: SNMP request failed: $RESULT"
  exit 1
fi

echo "PASS: $RESULT"
exit 0
