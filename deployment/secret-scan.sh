#!/usr/bin/env bash
# Blocks the build if credentials or debug artefacts would ship.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

if find . -name '.env' -not -path './node_modules/*' | grep -q .; then
  echo "FAIL: .env committed"; fail=1
fi

# Real assignments only — the word appearing in a comment or key name is fine.
HITS=$(grep -rInE "(password|secret|api[_-]?key|token)[[:space:]]*=[[:space:]]*['\"][A-Za-z0-9/+=_-]{16,}['\"]" \
  --include='*.php' --include='*.js' --include='*.jsx' \
  backend/app frontend/src 2>/dev/null \
  | grep -viE "encrypted|placeholder|example|\.env|config\(|env\(" || true)
if [ -n "$HITS" ]; then echo "FAIL: possible hardcoded secret:"; echo "$HITS"; fail=1; fi

DBG=$(grep -rIn "var_dump(\|dd(\|print_r(" --include='*.php' backend/app 2>/dev/null || true)
if [ -n "$DBG" ]; then echo "FAIL: debug statement in backend:"; echo "$DBG"; fail=1; fi

[ $fail -eq 0 ] && echo "secret scan PASS" || exit 1
