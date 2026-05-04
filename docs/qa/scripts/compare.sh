#!/usr/bin/env bash
# compare.sh — парный REST-запрос YC ↔ Kachō с diff-ом по ключевым полям.
#
# YC и Kachō имеют идентичные REST paths (мы взяли verbatim YC).
# Различается только base host:
#   YC:    https://<service>.api.cloud.yandex.net
#   Kachō: http://localhost:8080
#
# Service host выбирается по prefix path:
#   /organization-manager/v1/... → organization-manager.api.cloud.yandex.net
#   /resource-manager/v1/...     → resource-manager.api.cloud.yandex.net
#   /vpc/v1/...                  → vpc.api.cloud.yandex.net
#   /operations/...              → operation.api.cloud.yandex.net
#
# Usage:
#   ./compare.sh <scenario-id> <method> <path> [body-json]
#
# Examples:
#   ./compare.sh C-LIST GET   /resource-manager/v1/clouds
#   ./compare.sh C-CR-3 POST  /resource-manager/v1/clouds  '{"name":"qa-dup-cloud","organization_id":"<id>"}'
#   ./compare.sh C-DEL  DELETE /resource-manager/v1/clouds/$ID
#
# Auth: используется $YC_TOKEN (если пуст — `yc iam create-token`).

set +e

SC="${1:?scenario id required}"
METHOD="${2:?HTTP method required}"
PATH_="${3:?REST path required}"
BODY="${4:-}"

KACHO="${KACHO:-http://localhost:8080}"
YC_TOKEN="${YC_TOKEN:-$(yc iam create-token 2>/dev/null)}"

# YC base host по prefix
yc_host() {
  case "$1" in
    /organization-manager/*) echo "https://organization-manager.api.cloud.yandex.net" ;;
    /resource-manager/*)     echo "https://resource-manager.api.cloud.yandex.net" ;;
    /vpc/*)                  echo "https://vpc.api.cloud.yandex.net" ;;
    /operations/*)           echo "https://operation.api.cloud.yandex.net" ;;
    *) echo "" ;;
  esac
}

YC_BASE=$(yc_host "$PATH_")
if [ -z "$YC_BASE" ]; then
  echo "✗ Unknown YC service for path: $PATH_"
  exit 2
fi

# Kachō organization-manager — доступен через api-gateway тоже на $KACHO

curl_args=(--max-time 10 -s -w "\n__HTTP_%{http_code}")
if [ -n "$BODY" ]; then
  curl_args+=(-H 'Content-Type: application/json' -d "$BODY")
fi

echo "════════════════════════════════════════════════════════════════"
echo "Scenario: $SC"
echo "$METHOD $PATH_"
[ -n "$BODY" ] && echo "Body: $BODY"
echo "════════════════════════════════════════════════════════════════"

# YC
echo
echo "──── YC: $YC_BASE$PATH_ ────"
yc_raw=$(curl "${curl_args[@]}" -X "$METHOD" \
  -H "Authorization: Bearer $YC_TOKEN" \
  "$YC_BASE$PATH_")
yc_http=$(echo "$yc_raw" | tail -n1 | sed 's/__HTTP_//')
yc_body=$(echo "$yc_raw" | sed '$d')
echo "$yc_body" | head -c 600
echo
echo "  HTTP $yc_http"

# Kachō
echo
echo "──── Kachō: $KACHO$PATH_ ────"
k_raw=$(curl "${curl_args[@]}" -X "$METHOD" "$KACHO$PATH_")
k_http=$(echo "$k_raw" | tail -n1 | sed 's/__HTTP_//')
k_body=$(echo "$k_raw" | sed '$d')
echo "$k_body" | head -c 600
echo
echo "  HTTP $k_http"

# Diff
echo
echo "──── Diff ────"
y_code=$(echo "$yc_body" | jq -r '.code // empty' 2>/dev/null)
k_code=$(echo "$k_body" | jq -r '.code // empty' 2>/dev/null)

if [ "$yc_http" = "$k_http" ]; then
  echo "  ✓ HTTP status match: $yc_http"
else
  echo "  ✗ HTTP status MISMATCH: yc=$yc_http kacho=$k_http"
fi
if [ "$y_code" = "$k_code" ]; then
  if [ -n "$y_code" ]; then echo "  ✓ gRPC code match: $y_code"; fi
else
  echo "  ✗ gRPC code MISMATCH: yc='$y_code' kacho='$k_code'"
fi
echo
