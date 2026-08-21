#!/usr/bin/env bash
# ============================================================
# verify-sms.sh — SMS gateway integration test.
#
# Real API call to a real Bangladeshi SMS aggregator (the two most common
# in this market: local providers exposing an HTTP GET/POST "send SMS"
# endpoint, typically billed per-SMS — this script targets that common
# shape generically via SMS_API_URL so it works with whichever provider
# the operator has a contract with, without hardcoding one vendor).
#
# Sends a REAL SMS to a REAL test number when credentials are supplied —
# this has a real cost per the provider's billing, which is exactly why
# it is never run automatically and always requires explicit opt-in via
# environment variables.
#
# Usage:
#   SMS_API_URL="https://sms-provider.example/api/send" \
#   SMS_API_KEY=... SMS_TEST_NUMBER=8801700000000 \
#     bash scripts/integration-tests/verify-sms.sh
# ============================================================
set -uo pipefail

URL="${SMS_API_URL:-}"
KEY="${SMS_API_KEY:-}"
TEST_NUMBER="${SMS_TEST_NUMBER:-}"

if [ -z "$URL" ] || [ -z "$KEY" ] || [ -z "$TEST_NUMBER" ]; then
  cat <<EOF
STATUS: EXTERNAL-CREDENTIAL-BLOCKED

SMS gateway test requires a real provider contract — this project does
not bundle a specific vendor because Bangladeshi ISPs typically already
have an existing SMS aggregator relationship (e.g. for BTRC/regulatory
notices) and App\Services\Communication\SmsService is written against a
generic send-SMS HTTP contract to match whichever the operator uses.

Setup:
  1. An SMS aggregator account with API access (common in this market:
     Alpha SMS, Bulk SMS BD, or similar — any provider exposing a REST
     send endpoint works).
  2. Their API URL, API key, and a real phone number you control to
     receive the real test SMS this script sends (it has a real cost).

Run:
  SMS_API_URL="https://your-provider/api/send" \\
  SMS_API_KEY="your-key" SMS_TEST_NUMBER="8801700000000" \\
    bash scripts/integration-tests/verify-sms.sh

WARNING: running this with real credentials sends a REAL, BILLABLE SMS.
EOF
  exit 2
fi

echo "=== SMS gateway — real send to $TEST_NUMBER ==="
RESP=$(curl -s -w "\n%{http_code}" --max-time 10 "$URL" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"to\":\"$TEST_NUMBER\",\"message\":\"AR Qudrix ISP OS integration verification $(date -u +%s)\"}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)

if [ "$CODE" -ge 200 ] && [ "$CODE" -lt 300 ]; then
  echo "PASS: provider accepted the send request (HTTP $CODE): $BODY"
  exit 0
else
  echo "FAIL: provider rejected the send request (HTTP $CODE): $BODY"
  exit 1
fi
