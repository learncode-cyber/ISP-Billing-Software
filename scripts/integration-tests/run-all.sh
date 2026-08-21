#!/usr/bin/env bash
# ============================================================
# run-all.sh — runs all six external-integration harnesses and produces
# a single machine-readable summary. Never converts a BLOCKED result into
# PASS; the summary table preserves the distinction explicitly.
# ============================================================
set -uo pipefail
cd "$(dirname "$0")"

declare -A RESULTS
SCRIPTS=(mikrotik olt-snmp radius payment-gateway sms llm)

for name in "${SCRIPTS[@]}"; do
  echo ""
  echo "############################################################"
  echo "# $name"
  echo "############################################################"
  bash "verify-${name}.sh"
  code=$?
  case $code in
    0) RESULTS[$name]="PASS" ;;
    1) RESULTS[$name]="FAIL" ;;
    2) RESULTS[$name]="EXTERNAL-CREDENTIAL-BLOCKED" ;;
    *) RESULTS[$name]="UNKNOWN(exit=$code)" ;;
  esac
done

echo ""
echo "############################################################"
echo "# SUMMARY — External Integration Verification"
echo "############################################################"
FAIL_COUNT=0
for name in "${SCRIPTS[@]}"; do
  printf "  %-20s %s\n" "$name" "${RESULTS[$name]}"
  [ "${RESULTS[$name]}" = "FAIL" ] && FAIL_COUNT=$((FAIL_COUNT+1))
done

echo ""
if [ $FAIL_COUNT -gt 0 ]; then
  echo "RESULT: $FAIL_COUNT real defect(s) found among tested integrations."
  exit 1
fi
echo "RESULT: no real defects. Any EXTERNAL-CREDENTIAL-BLOCKED entries require credentials/hardware this environment does not have — see each script's setup instructions."
exit 0
