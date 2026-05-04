#!/usr/bin/env bash
# starter-pack.sh — 9 главных сценариев из docs/qa/00-yc-comparison-task.md §12.
#
# Перед запуском:
#   - yc init выполнен, default folder задан
#   - Kachō: kubectl port-forward svc/api-gateway 8080:8080 &
#   - default Organization/Cloud/Folder в Kachō созданы (bootstrap)
#
# Каждый сценарий печатает YC vs Kachō результаты + diff.
# Скрипт оставляет за собой test-ресурсы (delete вручную).

set +e
KACHO="${KACHO:-http://localhost:8080}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPARE="$DIR/compare.sh"
chmod +x "$COMPARE"

# ────────────── 1. O-CR-3: Create org с дубликатом name ──────────────

"$COMPARE" "O-CR-3" \
  'yc organization-manager organization create --name default --title Test --format json 2>&1' \
  "curl -s -X POST $KACHO/organization-manager/v1/organizations -H 'Content-Type: application/json' -d '{\"name\":\"default\",\"title\":\"Test\"}'"

# ────────────── 2. C-UP-4: Update Cloud rename to occupied ──────────────

# Готовим: создаём 2 cloud-а с разными именами, потом переименовываем второй в имя первого.
ORG_ID=$(yc resource-manager organization list --format json 2>/dev/null | jq -r '.[0].id' || echo "")
KACHO_ORG_ID=$(curl -s $KACHO/organization-manager/v1/organizations | jq -r '.organizations[0].id')

yc resource-manager cloud create --name qa-cloud-a --organization-id $ORG_ID --format json >/dev/null 2>&1
yc resource-manager cloud create --name qa-cloud-b --organization-id $ORG_ID --format json >/dev/null 2>&1
QA_B_ID=$(yc resource-manager cloud list --format json 2>/dev/null | jq -r '.[] | select(.name=="qa-cloud-b") | .id')

curl -s -X POST $KACHO/resource-manager/v1/clouds -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-cloud-a\",\"organization_id\":\"$KACHO_ORG_ID\"}" >/dev/null
curl -s -X POST $KACHO/resource-manager/v1/clouds -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-cloud-b\",\"organization_id\":\"$KACHO_ORG_ID\"}" >/dev/null
KACHO_B_ID=$(curl -s "$KACHO/resource-manager/v1/clouds?organization_id=$KACHO_ORG_ID" | jq -r '.clouds[] | select(.name=="qa-cloud-b") | .id')

"$COMPARE" "C-UP-4" \
  "yc resource-manager cloud update $QA_B_ID --new-name qa-cloud-a --format json 2>&1" \
  "curl -s -X PATCH $KACHO/resource-manager/v1/clouds/$KACHO_B_ID -H 'Content-Type: application/json' -d '{\"name\":\"qa-cloud-a\",\"update_mask\":\"name\"}'"

# ────────────── 3. C-DL-2: Delete Cloud с folders внутри ──────────────

# Готовим: создаём cloud + folder в нём.
QA_C_ID=$(yc resource-manager cloud create --name qa-cloud-with-folder --organization-id $ORG_ID --format json 2>/dev/null | jq -r '.id')
yc resource-manager folder create --name qa-folder --cloud-id $QA_C_ID --format json >/dev/null 2>&1

curl -s -X POST $KACHO/resource-manager/v1/clouds -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-cloud-with-folder\",\"organization_id\":\"$KACHO_ORG_ID\"}" >/dev/null
KACHO_C_ID=$(curl -s "$KACHO/resource-manager/v1/clouds?organization_id=$KACHO_ORG_ID" | jq -r '.clouds[] | select(.name=="qa-cloud-with-folder") | .id')
curl -s -X POST $KACHO/resource-manager/v1/folders -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-folder\",\"cloud_id\":\"$KACHO_C_ID\"}" >/dev/null

"$COMPARE" "C-DL-2" \
  "yc resource-manager cloud delete $QA_C_ID --format json 2>&1" \
  "curl -s -X DELETE $KACHO/resource-manager/v1/clouds/$KACHO_C_ID"

# ────────────── 4. SU-CIDR-2: Subnet с host-bits-set CIDR ──────────────

# Готовим: создаём network в YC и в Kachō, прицепляем subnet с невалидным CIDR.
YC_NET_ID=$(yc vpc network create --name qa-net-cidr --format json 2>/dev/null | jq -r '.id')

KACHO_FOLDER_ID=$(curl -s "$KACHO/resource-manager/v1/folders?cloud_id=$KACHO_ORG_ID" | jq -r '.folders[0].id // empty')
if [ -z "$KACHO_FOLDER_ID" ]; then
  KACHO_FOLDER_ID=$(curl -s "$KACHO/resource-manager/v1/folders" | jq -r '.folders[0].id')
fi
curl -s -X POST $KACHO/vpc/v1/networks -H 'Content-Type: application/json' \
  -d "{\"folder_id\":\"$KACHO_FOLDER_ID\",\"name\":\"qa-net-cidr\"}" >/dev/null
KACHO_NET_ID=$(curl -s "$KACHO/vpc/v1/networks?folder_id=$KACHO_FOLDER_ID" | jq -r '.networks[] | select(.name=="qa-net-cidr") | .id')

"$COMPARE" "SU-CIDR-2" \
  "yc vpc subnet create --name qa-sub-bad --network-id $YC_NET_ID --zone ru-central1-a --range 10.0.0.5/24 --format json 2>&1" \
  "curl -s -X POST $KACHO/vpc/v1/subnets -H 'Content-Type: application/json' -d '{\"folder_id\":\"$KACHO_FOLDER_ID\",\"name\":\"qa-sub-bad\",\"network_id\":\"$KACHO_NET_ID\",\"zone_id\":\"kacho-zone-a\",\"v4_cidr_blocks\":[\"10.0.0.5/24\"]}'"

# ────────────── 5. SU-CIDR-IM-1: Subnet попытка изменить CIDR через Update ──────────────

# Сначала создаём валидный subnet.
yc vpc subnet create --name qa-sub-im --network-id $YC_NET_ID --zone ru-central1-a --range 10.1.0.0/24 --format json >/dev/null 2>&1
YC_SUB_IM=$(yc vpc subnet list --format json 2>/dev/null | jq -r '.[] | select(.name=="qa-sub-im") | .id')

curl -s -X POST $KACHO/vpc/v1/subnets -H 'Content-Type: application/json' \
  -d "{\"folder_id\":\"$KACHO_FOLDER_ID\",\"name\":\"qa-sub-im\",\"network_id\":\"$KACHO_NET_ID\",\"zone_id\":\"kacho-zone-a\",\"v4_cidr_blocks\":[\"10.1.0.0/24\"]}" >/dev/null
KACHO_SUB_IM=$(curl -s "$KACHO/vpc/v1/subnets?folder_id=$KACHO_FOLDER_ID" | jq -r '.subnets[] | select(.name=="qa-sub-im") | .id')

"$COMPARE" "SU-CIDR-IM-1" \
  "yc vpc subnet update $YC_SUB_IM --range 10.2.0.0/24 --format json 2>&1" \
  "curl -s -X PATCH $KACHO/vpc/v1/subnets/$KACHO_SUB_IM -H 'Content-Type: application/json' -d '{\"v4_cidr_blocks\":[\"10.2.0.0/24\"],\"update_mask\":\"v4_cidr_blocks\"}'"

# ────────────── 6. A-CR-3: Internal Address с несуществующим subnet ──────────────

NONEXISTENT="00000000-0000-0000-0000-000000000000"

"$COMPARE" "A-CR-3" \
  "yc vpc address create --internal-ipv4-address subnet-id=$NONEXISTENT --format json 2>&1" \
  "curl -s -X POST $KACHO/vpc/v1/addresses -H 'Content-Type: application/json' -d '{\"folder_id\":\"$KACHO_FOLDER_ID\",\"name\":\"qa-addr-bad\",\"internal_ipv4_address\":{\"subnet_id\":\"$NONEXISTENT\"}}'"

# ────────────── 7. OP-3: Operation Cancel ──────────────

# Запускаем delete (длинная operation), сразу пробуем Cancel.
# YC и наша операция могут завершиться раньше — сценарий best-effort.
YC_NET_FOR_CANCEL=$(yc vpc network create --name qa-cancel --format json 2>/dev/null | jq -r '.id')
YC_DEL_OP=$(yc vpc network delete $YC_NET_FOR_CANCEL --async --format json 2>/dev/null | jq -r '.id')

curl -s -X POST $KACHO/vpc/v1/networks -H 'Content-Type: application/json' \
  -d "{\"folder_id\":\"$KACHO_FOLDER_ID\",\"name\":\"qa-cancel\"}" >/dev/null
KACHO_NET_CANCEL=$(curl -s "$KACHO/vpc/v1/networks?folder_id=$KACHO_FOLDER_ID" | jq -r '.networks[] | select(.name=="qa-cancel") | .id')
KACHO_DEL=$(curl -s -X DELETE $KACHO/vpc/v1/networks/$KACHO_NET_CANCEL)
KACHO_DEL_OP=$(echo "$KACHO_DEL" | jq -r '.id')

"$COMPARE" "OP-3" \
  "yc operation cancel $YC_DEL_OP --format json 2>&1" \
  "curl -s -X POST $KACHO/operations/$KACHO_DEL_OP:cancel -H 'Content-Type: application/json' -d '{}'"

# ────────────── 8. E-4: Multi field-violation ──────────────

"$COMPARE" "E-4" \
  'yc resource-manager cloud create --name "" --organization-id "" --description "$(printf %0.s_ {1..300})" --format json 2>&1' \
  "curl -s -X POST $KACHO/resource-manager/v1/clouds -H 'Content-Type: application/json' -d '{\"name\":\"\",\"organization_id\":\"\",\"description\":\"$(printf %0.s_ {1..300})\"}'"

# ────────────── 9. N-DEL-1: Delete Network с зависимыми Subnets ──────────────

"$COMPARE" "N-DEL-1" \
  "yc vpc network delete $YC_NET_ID --format json 2>&1" \
  "curl -s -X DELETE $KACHO/vpc/v1/networks/$KACHO_NET_ID"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "Готово! Cleanup test resources:"
echo "  yc vpc subnet delete \$(yc vpc subnet list --format json | jq -r '.[]|select(.name|startswith(\"qa-\"))|.id')"
echo "  yc vpc network delete <ids> ..."
echo "  yc resource-manager cloud delete <ids> ..."
echo "Аналогично для Kachō (curl -X DELETE)."
