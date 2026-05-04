#!/usr/bin/env bash
# compare.sh — парный запрос YC ↔ Kachō с diff-ом по ключевым полям.
#
# Usage:
#   ./compare.sh <scenario-id> <yc-cmd> <kacho-curl-cmd>
#
# Пример:
#   ./compare.sh O-CR-3 \
#     'yc organization-manager organization create --name default --title T 2>&1' \
#     'curl -s -X POST $KACHO/organization-manager/v1/organizations -d "{\"name\":\"default\",\"title\":\"T\"}"'
#
# Требует jq.

set +e

SC="${1:-?}"
YC_CMD="${2:?need yc command}"
KACHO_CMD="${3:?need kacho curl command}"
KACHO="${KACHO:-http://localhost:8080}"
export KACHO

echo "════════════════════════════════════════════════════════════════"
echo "Scenario: $SC"
echo "════════════════════════════════════════════════════════════════"

echo
echo "──── YC ────"
echo "\$ $YC_CMD"
yc_out=$(eval "$YC_CMD")
yc_rc=$?
echo "$yc_out"
echo "  rc=$yc_rc"

echo
echo "──── Kachō ────"
echo "\$ $KACHO_CMD"
k_out=$(eval "$KACHO_CMD")
k_rc=$?
echo "$k_out"
echo "  rc=$k_rc"

echo
echo "──── Diff (key fields) ────"
y_code=$(echo "$yc_out" | jq -r '.code // empty' 2>/dev/null)
k_code=$(echo "$k_out" | jq -r '.code // empty' 2>/dev/null)
y_msg=$(echo "$yc_out" | jq -r '.message // empty' 2>/dev/null)
k_msg=$(echo "$k_out" | jq -r '.message // empty' 2>/dev/null)

if [ "$y_code" != "$k_code" ]; then
  echo "  ✗ MISMATCH code: yc='$y_code' kacho='$k_code'"
else
  echo "  ✓ code match: '$y_code'"
fi
if [ -n "$y_msg" ] || [ -n "$k_msg" ]; then
  if [ "$y_msg" = "$k_msg" ]; then
    echo "  ✓ message match"
  else
    echo "  • messages differ (это часто OK):"
    echo "    yc:    $y_msg"
    echo "    kacho: $k_msg"
  fi
fi
echo
