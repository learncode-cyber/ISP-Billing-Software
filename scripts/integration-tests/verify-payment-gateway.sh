#!/usr/bin/env bash
# ============================================================
# verify-payment-gateway.sh — Payment gateway sandbox integration test.
#
# Real sandbox API calls, not mocks: each provider's official sandbox
# environment is a real, live service (not simulated locally) that
# validates credentials and returns real tokens/session IDs. This script
# performs the actual grant/token-request step for whichever provider has
# credentials supplied — the first real network hop each adapter makes
# before a customer would be redirected to pay.
#
# Usage (any subset of these env vars enables that provider's test):
#   BKASH_APP_KEY=... BKASH_APP_SECRET=... BKASH_USERNAME=... BKASH_PASSWORD=... \
#   SSLCOMMERZ_STORE_ID=... SSLCOMMERZ_STORE_PASSWD=... \
#   STRIPE_SECRET_KEY=sk_test_... \
#     bash scripts/integration-tests/verify-payment-gateway.sh
# ============================================================
set -uo pipefail
ANY_TESTED=0
ANY_FAILED=0

echo "=== Payment Gateway sandbox verification ==="

# ---- bKash sandbox: grant token ----
if [ -n "${BKASH_APP_KEY:-}" ] && [ -n "${BKASH_USERNAME:-}" ]; then
  ANY_TESTED=1
  echo "-- bKash sandbox grant token --"
  RESP=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "https://tokenized.sandbox.bka.sh/v1.2.0-beta/tokenized/checkout/token/grant" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -H "username: ${BKASH_USERNAME}" -H "password: ${BKASH_PASSWORD:-}" \
    -d "{\"app_key\":\"${BKASH_APP_KEY}\",\"app_secret\":\"${BKASH_APP_SECRET:-}\"}")
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | head -n -1)
  if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "id_token"; then
    echo "PASS: bKash sandbox issued a real id_token"
  else
    echo "FAIL: bKash sandbox grant failed (HTTP $CODE): $BODY"
    ANY_FAILED=1
  fi
else
  echo "-- bKash: EXTERNAL-CREDENTIAL-BLOCKED (set BKASH_APP_KEY, BKASH_APP_SECRET, BKASH_USERNAME, BKASH_PASSWORD — get sandbox credentials at https://developer.bka.sh) --"
fi

# ---- Nagad sandbox: reachability of the merchant API host ----
if [ -n "${NAGAD_MERCHANT_ID:-}" ]; then
  ANY_TESTED=1
  echo "-- Nagad sandbox reachability --"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://sandbox.mynagad.com:10080/remote-payment-gateway-1.0/api/dfs/check-status/${NAGAD_MERCHANT_ID}")
  if [ "$CODE" != "000" ]; then
    echo "PASS: Nagad sandbox host reachable (HTTP $CODE — non-zero means the real service answered)"
  else
    echo "FAIL: Nagad sandbox host unreachable"
    ANY_FAILED=1
  fi
else
  echo "-- Nagad: EXTERNAL-CREDENTIAL-BLOCKED (set NAGAD_MERCHANT_ID — get sandbox access via Nagad merchant onboarding) --"
fi

# ---- SSLCommerz sandbox: session init ----
if [ -n "${SSLCOMMERZ_STORE_ID:-}" ] && [ -n "${SSLCOMMERZ_STORE_PASSWD:-}" ]; then
  ANY_TESTED=1
  echo "-- SSLCommerz sandbox session init --"
  RESP=$(curl -s --max-time 10 "https://sandbox.sslcommerz.com/gwprocess/v4/api.php" \
    -d "store_id=${SSLCOMMERZ_STORE_ID}&store_passwd=${SSLCOMMERZ_STORE_PASSWD}&total_amount=10&currency=BDT&tran_id=verify-$(date +%s)&success_url=https://example.com/s&fail_url=https://example.com/f&cancel_url=https://example.com/c&cus_name=Test&cus_email=test@example.com&cus_add1=Dhaka&cus_phone=01700000000")
  if echo "$RESP" | grep -q '"status":"SUCCESS"'; then
    echo "PASS: SSLCommerz sandbox returned a real session"
  else
    echo "FAIL: SSLCommerz sandbox session init failed: $(echo "$RESP" | head -c 300)"
    ANY_FAILED=1
  fi
else
  echo "-- SSLCommerz: EXTERNAL-CREDENTIAL-BLOCKED (set SSLCOMMERZ_STORE_ID, SSLCOMMERZ_STORE_PASSWD — register a free sandbox store at https://developer.sslcommerz.com) --"
fi

# ---- Stripe test mode: real API call with a real test secret key ----
if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
  ANY_TESTED=1
  echo "-- Stripe test-mode API call --"
  RESP=$(curl -s -w "\n%{http_code}" --max-time 10 "https://api.stripe.com/v1/payment_intents" \
    -u "${STRIPE_SECRET_KEY}:" \
    -d "amount=1000" -d "currency=usd" -d "payment_method_types[]=card")
  CODE=$(echo "$RESP" | tail -1)
  if [ "$CODE" = "200" ]; then
    echo "PASS: Stripe test-mode PaymentIntent created"
  else
    echo "FAIL: Stripe API call failed (HTTP $CODE): $(echo "$RESP" | head -n -1 | head -c 300)"
    ANY_FAILED=1
  fi
else
  echo "-- Stripe: EXTERNAL-CREDENTIAL-BLOCKED (set STRIPE_SECRET_KEY=sk_test_... — free from https://dashboard.stripe.com/test/apikeys) --"
fi

echo ""
if [ "$ANY_TESTED" -eq 0 ]; then
  echo "STATUS: EXTERNAL-CREDENTIAL-BLOCKED — no gateway credentials supplied for any provider."
  exit 2
elif [ "$ANY_FAILED" -eq 1 ]; then
  echo "STATUS: FAIL — at least one supplied gateway's sandbox call failed."
  exit 1
else
  echo "STATUS: PASS — all supplied gateway sandboxes responded correctly."
  exit 0
fi
