#!/usr/bin/env bash
# ============================================================
# verify-llm.sh — LLM API integration test (AI NL analytics intent
# classification, per App\Services\Ai\NlAnalyticsService).
#
# Real API call to the Anthropic Messages API. Verifies connectivity,
# authentication, and — critically — that the model can be constrained to
# return ONLY a JSON intent classification and never raw SQL, which is
# the hard safety boundary NlAnalyticsService::classifyIntent() depends on.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-ant-... bash scripts/integration-tests/verify-llm.sh
# ============================================================
set -uo pipefail

KEY="${ANTHROPIC_API_KEY:-}"

if [ -z "$KEY" ]; then
  cat <<EOF
STATUS: EXTERNAL-CREDENTIAL-BLOCKED

LLM integration test requires a real API key.

Setup:
  1. An Anthropic API key from https://console.anthropic.com

Run:
  ANTHROPIC_API_KEY=sk-ant-... bash scripts/integration-tests/verify-llm.sh

What this verifies:
  - Real API connectivity and authentication
  - That the model, when given a natural-language analytics question,
    returns ONLY a constrained JSON intent (per the fixed catalog in
    NlAnalyticsService::INTENTS) and never generates free-form SQL —
    this is the safety boundary the whole NL-analytics feature depends
    on, so the test explicitly checks the response contains no SQL
    keywords (SELECT/INSERT/UPDATE/DELETE/DROP).
EOF
  exit 2
fi

echo "=== LLM API — real call, intent-classification safety check ==="

RESP=$(curl -s -w "\n%{http_code}" --max-time 20 "https://api.anthropic.com/v1/messages" \
  -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 200,
    "system": "You classify ISP analytics questions into ONE of these intents only: highest_churn_zone, monthly_collection, zone_performance, active_customer_count, unresolved. Respond with ONLY JSON: {\"intent\": \"...\", \"params\": {}}. NEVER write SQL or any database query.",
    "messages": [{"role": "user", "content": "Which zone had the highest customer churn this month?"}]
  }')
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -n -1)

if [ "$CODE" != "200" ]; then
  echo "FAIL: API call failed (HTTP $CODE): $(echo "$BODY" | head -c 300)"
  exit 1
fi

TEXT=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(''.join(b.get('text','') for b in d.get('content',[])))" 2>/dev/null)
echo "Model response: $TEXT"

if echo "$TEXT" | grep -qiE "\b(SELECT|INSERT|UPDATE|DELETE|DROP|ALTER)\b"; then
  echo "FAIL: SAFETY VIOLATION — response contains SQL keywords. The constrained-intent boundary is not holding."
  exit 1
fi

if echo "$TEXT" | grep -q "highest_churn_zone"; then
  echo "PASS: real API call succeeded, response is constrained to the known intent catalog, no SQL present"
  exit 0
else
  echo "FAIL: response did not match the expected intent catalog: $TEXT"
  exit 1
fi
