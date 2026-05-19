#!/usr/bin/env bash
# KAC-122 — authz-deny suite fixtures bootstrap.
#
# Идемпотентен. Создаёт минимальный набор Account / Project / User / AccessBinding
# чтобы 6-субъектная permission-матрица проверялась стабильно. Также активирует
# invitee per-Account через KAC-125 Invite-flow.
#
# Окружение:
#   BASE_URL         — api-gateway endpoint (default http://localhost:18080)
#   DEV_SECRET       — KACHO_API_GATEWAY_AUTHN_DEV_SECRET (default kacho-dev-jwt-secret-2026)
#   EXP_HOURS        — exp для JWT (default 24)
#   OUT_DIR          — куда писать authz-fixtures.json (default tests/authz-fixtures/out)
#   PATCH_ENV        — если true, патчит environments/*.json во всех 3 newman-suites
#                     (default true)
#   VERBOSE          — true → echo каждый curl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_URL="${BASE_URL:-http://localhost:18080}"
IAM_INTERNAL_GRPC="${IAM_INTERNAL_GRPC:-localhost:19091}"  # порт-форвард на kacho-iam-internal:9091 (grpcurl)
DEV_SECRET="${DEV_SECRET:-kacho-dev-jwt-secret-2026}"
EXP_HOURS="${EXP_HOURS:-24}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out}"
PATCH_ENV="${PATCH_ENV:-true}"
VERBOSE="${VERBOSE:-false}"

# require grpcurl for InternalUserService.UpsertFromIdentity (нет REST маппинга — KAC-125)
if ! command -v grpcurl >/dev/null 2>&1; then
  echo "[setup] FATAL: grpcurl не найден в PATH. Установи: go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

log() { echo "[setup] $*" >&2; }
vrun() { if [ "$VERBOSE" = "true" ]; then echo "+ $*" >&2; fi; "$@"; }

# 1) Mint all 6 JWTs.
log "1/8 minting JWTs (exp=${EXP_HOURS}h)"
JWTS=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --exp-hours "$EXP_HOURS" --bulk)
echo "$JWTS" > "$OUT_DIR/jwts.json"

JWT_BOOTSTRAP=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtBootstrap"])')
JWT_NO_BINDINGS=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtNoBindings"])')
JWT_PA1=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtProjectAdminA1"])')
JWT_AAA=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtAccountAdminA"])')
JWT_AAB=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtAccountAdminB"])')
JWT_INV=$(echo "$JWTS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jwtInvitee"])')

# Helper: curl with bearer; prints body to stdout.
api() {
  local method="$1" path="$2" token="${3:-}" body="${4:-}"
  local hdrs=(-H "Content-Type: application/json" -H "Accept: application/json")
  if [ -n "$token" ]; then hdrs+=(-H "Authorization: Bearer $token"); fi
  if [ -n "$body" ]; then
    vrun curl -sS -X "$method" "${hdrs[@]}" --data "$body" "$BASE_URL$path"
  else
    vrun curl -sS -X "$method" "${hdrs[@]}" "$BASE_URL$path"
  fi
}

# poll-op — ждёт Operation.done=true и возвращает response.metadata если есть.
poll_op() {
  local op_id="$1" token="$2"
  for _ in $(seq 1 30); do
    local r
    r=$(api GET "/operations/${op_id}" "$token")
    if echo "$r" | grep -q '"done":true'; then echo "$r"; return 0; fi
    sleep 0.3
  done
  echo "$r"
  return 1
}

# 2) Upsert test users via InternalUserService.UpsertFromIdentity (gRPC-direct;
#    REST-маппинг отсутствует — proto не имеет google.api.http аннотации; KAC-125).
log "2/8 upserting test users via grpcurl → $IAM_INTERNAL_GRPC"

# upsert_user_grpc возвращает userId через stdout (poll Operation.metadata.userId).
upsert_user_grpc() {
  local ext_id="$1" email="$2" display="${3:-$email}"
  local body op_id user_id
  body=$(printf '{"externalId":"%s","email":"%s","displayName":"%s"}' "$ext_id" "$email" "$display")
  local resp
  resp=$(grpcurl -plaintext -d "$body" "$IAM_INTERNAL_GRPC" \
    kacho.cloud.iam.v1.InternalUserService/UpsertFromIdentity 2>&1)
  user_id=$(echo "$resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(((d.get("metadata") or {}).get("userId","")))' 2>/dev/null || true)
  if [ -z "$user_id" ]; then
    # PENDING-row может быть активирован — get_by_email через grpc.
    user_id=$(grpcurl -plaintext -d "{\"email\":\"$email\"}" "$IAM_INTERNAL_GRPC" \
      kacho.cloud.iam.v1.InternalIAMService/LookupSubject 2>/dev/null \
      | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("subjectId",""))' 2>/dev/null || true)
  fi
  echo "$user_id"
}

USER_BOOT=$(upsert_user_grpc "admin@prorobotech.ru"                  "admin@prorobotech.ru"                  "Bootstrap Admin")
USER_NOB=$(upsert_user_grpc "auth-test-no-bindings@example.com"     "auth-test-no-bindings@example.com"     "AuthZ NoBindings")
USER_PA1=$(upsert_user_grpc "auth-test-proj-admin-a1@example.com"   "auth-test-proj-admin-a1@example.com"   "AuthZ ProjAdminA1")
USER_AAA=$(upsert_user_grpc "auth-test-account-admin-a@example.com" "auth-test-account-admin-a@example.com" "AuthZ AccountAdminA")
USER_AAB=$(upsert_user_grpc "auth-test-account-admin-b@example.com" "auth-test-account-admin-b@example.com" "AuthZ AccountAdminB")
USER_INV=$(upsert_user_grpc "auth-test-invitee@example.com"         "auth-test-invitee@example.com"         "AuthZ Invitee")
log "    users: BOOT=$USER_BOOT NOB=$USER_NOB PA1=$USER_PA1 AAA=$USER_AAA AAB=$USER_AAB INV=$USER_INV"

# 3) Accounts (idempotent by name).
log "3/8 ensuring accounts authz-test-A / authz-test-B"
find_account_by_name() {
  local name="$1"
  api GET "/iam/v1/accounts" "$JWT_BOOTSTRAP" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); n=[x for x in (d.get('accounts') or []) if x.get('name')=='$name']; print(n[0].get('id','') if n else '')" 2>/dev/null || true
}

ensure_account() {
  local name="$1" desc="$2" owner="$3"
  local found
  found=$(find_account_by_name "$name")
  if [ -n "$found" ]; then echo "$found"; return; fi
  local body op
  body=$(printf '{"name":"%s","description":"%s","ownerUserId":"%s"}' "$name" "$desc" "$owner")
  op=$(api POST "/iam/v1/accounts" "$JWT_BOOTSTRAP" "$body")
  local op_id; op_id=$(echo "$op" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
  if [ -z "$op_id" ]; then echo "[setup] FATAL: Account.Create vernuli no id: $op" >&2; return 1; fi
  poll_op "$op_id" "$JWT_BOOTSTRAP" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("metadata") or {}).get("accountId",""))'
}
ACCOUNT_A=$(ensure_account "authz-test-a" "KAC-122 fixture (account-admin-A home)" "$USER_AAA")
ACCOUNT_B=$(ensure_account "authz-test-b" "KAC-122 fixture (account-admin-B home + invitee home)" "$USER_AAB")
log "    accounts: A=$ACCOUNT_A B=$ACCOUNT_B"

# 4) Projects.
log "4/8 ensuring projects A1 / A2 / B1"
find_project_by_name_account() {
  local name="$1" acct="$2"
  api GET "/iam/v1/projects?accountId=$acct" "$JWT_BOOTSTRAP" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); n=[x for x in (d.get('projects') or []) if x.get('name')=='$name']; print(n[0].get('id','') if n else '')" 2>/dev/null || true
}
ensure_project() {
  local name="$1" acct="$2" desc="$3"
  local found
  found=$(find_project_by_name_account "$name" "$acct")
  if [ -n "$found" ]; then echo "$found"; return; fi
  local body op
  body=$(printf '{"accountId":"%s","name":"%s","description":"%s"}' "$acct" "$name" "$desc")
  op=$(api POST "/iam/v1/projects" "$JWT_BOOTSTRAP" "$body")
  local op_id; op_id=$(echo "$op" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
  poll_op "$op_id" "$JWT_BOOTSTRAP" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("metadata") or {}).get("projectId",""))'
}
PROJECT_A1=$(ensure_project "authz-test-a1" "$ACCOUNT_A" "KAC-122 fixture (project-admin-A1 home)")
PROJECT_A2=$(ensure_project "authz-test-a2" "$ACCOUNT_A" "KAC-122 fixture (cross-project in same account)")
PROJECT_B1=$(ensure_project "authz-test-b1" "$ACCOUNT_B" "KAC-122 fixture (cross-account)")
log "    projects: A1=$PROJECT_A1 A2=$PROJECT_A2 B1=$PROJECT_B1"

# 5) AccessBindings (idempotent via 5-tuple per KAC-112 §13.4).
log "5/8 ensuring access bindings"
ensure_binding() {
  local subject_id="$1" role_id="$2" resource_type="$3" resource_id="$4"
  local body
  body=$(printf '{"subjectType":"user","subjectId":"%s","roleId":"%s","resourceType":"%s","resourceId":"%s"}' \
    "$subject_id" "$role_id" "$resource_type" "$resource_id")
  api POST "/iam/v1/accessBindings" "$JWT_BOOTSTRAP" "$body" >/dev/null || true
}
# System role IDs (из seed миграции kacho_iam 0001):
#   iam{ad,ed,vw} / vpc{ad,ed,vw} / cmp{ad,ed,vw} / lbs{ad,ed,vw}.
# Owner relation в Keto cascade — не отдельный role-id, а Account membership-type;
# для тестов используем "ad" (admin) — он эквивалентен owner-у для всех практических целей.

# PA1 — project-A1 editor по всем доменам (vpc/compute/lbs).
ensure_binding "$USER_PA1" "rol00000000000000vpced" "project" "$PROJECT_A1"
ensure_binding "$USER_PA1" "rol00000000000000cmped" "project" "$PROJECT_A1"
ensure_binding "$USER_PA1" "rol00000000000000lbsed" "project" "$PROJECT_A1"
# AAA — account-A admin по всем доменам.
ensure_binding "$USER_AAA" "rol00000000000000iamad" "account" "$ACCOUNT_A"
ensure_binding "$USER_AAA" "rol00000000000000vpcad" "account" "$ACCOUNT_A"
ensure_binding "$USER_AAA" "rol00000000000000cmpad" "account" "$ACCOUNT_A"
ensure_binding "$USER_AAA" "rol00000000000000lbsad" "account" "$ACCOUNT_A"
# AAB — account-B admin по всем доменам.
ensure_binding "$USER_AAB" "rol00000000000000iamad" "account" "$ACCOUNT_B"
ensure_binding "$USER_AAB" "rol00000000000000vpcad" "account" "$ACCOUNT_B"
ensure_binding "$USER_AAB" "rol00000000000000cmpad" "account" "$ACCOUNT_B"
ensure_binding "$USER_AAB" "rol00000000000000lbsad" "account" "$ACCOUNT_B"
# INV — owner-of-B (his home) — admin по всем доменам в account-B.
ensure_binding "$USER_INV" "rol00000000000000iamad" "account" "$ACCOUNT_B"
ensure_binding "$USER_INV" "rol00000000000000vpcad" "account" "$ACCOUNT_B"
ensure_binding "$USER_INV" "rol00000000000000cmpad" "account" "$ACCOUNT_B"
ensure_binding "$USER_INV" "rol00000000000000lbsad" "account" "$ACCOUNT_B"

# 6) INV invite-flow (KAC-125): AAA invites INV into account-A as editor on project-A1.
log "6/8 invite INV to account-A (KAC-125)"
invite_body=$(printf '{"accountId":"%s","email":"auth-test-invitee@example.com","roleId":"rol00000000000000vpced","projectId":"%s"}' "$ACCOUNT_A" "$PROJECT_A1")
invite_resp=$(api POST "/iam/v1/users:invite" "$JWT_AAA" "$invite_body" 2>&1 || true)
if echo "$invite_resp" | grep -q '"id":'; then
  invite_op_id=$(echo "$invite_resp" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
  if [ -n "$invite_op_id" ]; then poll_op "$invite_op_id" "$JWT_AAA" >/dev/null || true; fi
else
  log "    WARN: Invite RPC response unexpected (KAC-125 REST mapping может отсутствовать): $(echo "$invite_resp" | head -c 200)"
  log "    INV получит admin@accountB напрямую через AccessBinding (вместо invite через project-A1)"
fi
# Re-upsert INV by external-id to activate PENDING-row (KAC-125 D-7).
upsert_user_grpc "auth-test-invitee@example.com" "auth-test-invitee@example.com" "AuthZ Invitee" >/dev/null

# 7) Seed VPC networks in A1 + B1 (admin token).
log "7/8 ensuring seed VPC networks"
ensure_network() {
  local proj="$1" name="$2"
  local found
  found=$(api GET "/vpc/v1/networks?projectId=$proj" "$JWT_BOOTSTRAP" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); n=[x for x in (d.get('networks') or []) if x.get('name')=='$name']; print(n[0].get('id','') if n else '')" 2>/dev/null || true)
  if [ -n "$found" ]; then echo "$found"; return; fi
  local body op op_id
  body=$(printf '{"projectId":"%s","name":"%s","description":"KAC-122 seed for GET probes"}' "$proj" "$name")
  op=$(api POST "/vpc/v1/networks" "$JWT_BOOTSTRAP" "$body")
  op_id=$(echo "$op" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
  if [ -z "$op_id" ]; then echo "[setup] WARN Network.Create failed: $op" >&2; echo ""; return; fi
  poll_op "$op_id" "$JWT_BOOTSTRAP" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("metadata") or {}).get("networkId",""))'
}
SEED_NET_A1=$(ensure_network "$PROJECT_A1" "authz-seed-net-a1")
SEED_NET_B1=$(ensure_network "$PROJECT_B1" "authz-seed-net-b1")
log "    seed networks: A1=$SEED_NET_A1 B1=$SEED_NET_B1"

# 8) Write authz-fixtures.json + patch env-files.
log "8/8 writing $OUT_DIR/authz-fixtures.json"
cat > "$OUT_DIR/authz-fixtures.json" <<EOF
{
  "baseUrl": "$BASE_URL",
  "jwtBootstrap": "$JWT_BOOTSTRAP",
  "jwtNoBindings": "$JWT_NO_BINDINGS",
  "jwtProjectAdminA1": "$JWT_PA1",
  "jwtAccountAdminA": "$JWT_AAA",
  "jwtAccountAdminB": "$JWT_AAB",
  "jwtInvitee": "$JWT_INV",
  "accountAId": "$ACCOUNT_A",
  "accountBId": "$ACCOUNT_B",
  "projectA1Id": "$PROJECT_A1",
  "projectA2Id": "$PROJECT_A2",
  "projectB1Id": "$PROJECT_B1",
  "seedNetworkA1Id": "$SEED_NET_A1",
  "seedNetworkB1Id": "$SEED_NET_B1",
  "userNOBId": "$USER_NOB",
  "userPA1Id": "$USER_PA1",
  "userAAAId": "$USER_AAA",
  "userAABId": "$USER_AAB",
  "userINVId": "$USER_INV"
}
EOF

if [ "$PATCH_ENV" = "true" ]; then
  log "    patching newman env files for all 3 services"
  python3 "$SCRIPT_DIR/patch-env.py" "$OUT_DIR/authz-fixtures.json" \
    "$WORKSPACE_DIR/project/kacho-vpc/tests/newman/environments/local.postman_environment.json" \
    "$WORKSPACE_DIR/project/kacho-iam/tests/newman/environments/local.postman_environment.json" \
    "$WORKSPACE_DIR/project/kacho-compute/tests/newman/environments/local.postman_environment.json"
fi

log "DONE — fixtures saved to $OUT_DIR/authz-fixtures.json"
