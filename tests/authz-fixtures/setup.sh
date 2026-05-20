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
#   RESET_FGA        — KAC-127 RC-1b: если true, удаляет stale OpenFGA-tuples,
#                      указывающие на test-объекты (account:authz-* / project:* /
#                      iam_*:* субъектов матрицы) ПЕРЕД повторным seed'ом, чтобы
#                      прогоны не накапливали дубликаты от прошлых моделей. По
#                      умолчанию false — Write-тuples и так идемпотентны (409 =
#                      success), reset нужен только при смене FGA-модели.
#                      Требует OPENFGA_HTTP (default http://localhost:18081) +
#                      OPENFGA_STORE_ID.
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
RESET_FGA="${RESET_FGA:-false}"
OPENFGA_HTTP="${OPENFGA_HTTP:-http://localhost:18081}"
OPENFGA_STORE_ID="${OPENFGA_STORE_ID:-}"

# require grpcurl for InternalUserService.UpsertFromIdentity (нет REST маппинга — KAC-125)
if ! command -v grpcurl >/dev/null 2>&1; then
  echo "[setup] FATAL: grpcurl не найден в PATH. Установи: go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

log() { echo "[setup] $*" >&2; }
vrun() { if [ "$VERBOSE" = "true" ]; then echo "+ $*" >&2; fi; "$@"; }

# 0) Optional OpenFGA store-tuple reset (KAC-127 RC-1b).
#
# Across repeated `dev-up` / `make authz-test-setup` runs the OpenFGA store
# retains every tuple ever written. Tuple writes are idempotent (409 ==
# success), so a re-seed never duplicates a tuple — but if the FGA *model*
# changed between runs, stale tuples that reference removed relations linger.
# When RESET_FGA=true we delete the tuples the matrix subjects/objects own
# before re-seeding, guaranteeing a clean slate. Default off (safe; the model
# is stable). Requires OPENFGA_HTTP + OPENFGA_STORE_ID.
reset_fga_tuples() {
  if [ "$RESET_FGA" != "true" ]; then
    log "0/8 OpenFGA store-reset skipped (RESET_FGA != true)"
    return 0
  fi
  if [ -z "$OPENFGA_STORE_ID" ]; then
    log "0/8 RESET_FGA=true but OPENFGA_STORE_ID is empty — skipping reset"
    return 0
  fi
  log "0/8 resetting stale OpenFGA tuples for test objects (store=$OPENFGA_STORE_ID)"
  # Read every tuple in the store, then delete the ones that point at
  # authz-test objects. OpenFGA Read with an empty tuple_key returns all.
  local page tuples
  page=$(curl -sS -X POST "$OPENFGA_HTTP/stores/$OPENFGA_STORE_ID/read" \
    -H "Content-Type: application/json" --data '{"page_size":100}' 2>/dev/null || echo '{}')
  tuples=$(echo "$page" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in d.get("tuples", []):
    k = t.get("key", {})
    obj, user = k.get("object", ""), k.get("user", "")
    # only delete tuples that touch the matrix fixture objects/subjects.
    if "authz-test" in obj or "authz-test" in user or obj.startswith(("iam_", "account:", "project:")):
        print(json.dumps({"user": user, "relation": k.get("relation", ""), "object": obj}))
' 2>/dev/null || true)
  local n=0
  while IFS= read -r tk; do
    [ -z "$tk" ] && continue
    curl -sS -X POST "$OPENFGA_HTTP/stores/$OPENFGA_STORE_ID/write" \
      -H "Content-Type: application/json" \
      --data "{\"deletes\":{\"tuple_keys\":[$tk]}}" >/dev/null 2>&1 || true
    n=$((n + 1))
  done <<< "$tuples"
  log "    deleted $n stale fixture tuple(s)"
}
reset_fga_tuples

# 1) Mint all 6 JWTs.
log "1/10 minting JWTs (exp=${EXP_HOURS}h)"
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
log "2/10 upserting test users via grpcurl → $IAM_INTERNAL_GRPC"

# upsert_user_grpc возвращает userId через stdout.
#
# КРИТИЧНО (KAC-127): UpsertFromIdentity возвращает Operation-envelope —
# `metadata.userId` выставлен сразу, НО bootstrap-Account + per-Account
# AccessBinding + FGA grant/hierarchy-tuples этого юзера пишутся в
# Operation-worker'е АСИНХРОННО. Если фикстура двинется к шагу 3
# (Account.Create) до того, как эти tuple'ы закоммичены, api-gateway authz
# Check ещё не видит принципала в OpenFGA → `code 7 permission denied`
# (наблюдалось в newman-e2e: FGA-tuple для AAA записан в .04, Account.Create
# в .21 → race). Поэтому здесь ОБЯЗАТЕЛЬНО дожидаемся Operation.done — после
# чего bootstrap-state юзера (и его FGA-tuple'ы) гарантированно есть.
upsert_user_grpc() {
  local ext_id="$1" email="$2" display="${3:-$email}"
  local body resp op_id user_id
  body=$(printf '{"externalId":"%s","email":"%s","displayName":"%s"}' "$ext_id" "$email" "$display")
  resp=$(grpcurl -plaintext -d "$body" "$IAM_INTERNAL_GRPC" \
    kacho.cloud.iam.v1.InternalUserService/UpsertFromIdentity 2>&1)
  # Дождаться завершения upsert-Operation — её worker создаёт bootstrap-Account
  # и пишет FGA-tuple'ы. Без этого Account.Create ниже ловит authz race.
  op_id=$(echo "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
  if [ -n "$op_id" ]; then
    poll_op "$op_id" "$JWT_BOOTSTRAP" >/dev/null 2>&1 || true
  fi
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

# Fail-fast — a missing user id (grpcurl could not reach kacho-iam-internal, or
# UpsertFromIdentity/LookupSubject errored) silently cascades into empty
# subjectId on every AccessBinding and a stack that "passes" with the wrong
# authz state. Surface it here with an actionable message instead of producing
# a misleading newman run.
for _pair in "BOOT:$USER_BOOT" "NOB:$USER_NOB" "PA1:$USER_PA1" \
             "AAA:$USER_AAA" "AAB:$USER_AAB" "INV:$USER_INV"; do
  if [ -z "${_pair#*:}" ]; then
    echo "[setup] FATAL: user ${_pair%%:*} resolved to an empty id — UpsertFromIdentity/LookupSubject failed." >&2
    echo "[setup]        Check IAM_INTERNAL_GRPC=$IAM_INTERNAL_GRPC is reachable via grpcurl and kacho-iam is up." >&2
    exit 1
  fi
done

# 3) Accounts (idempotent by name).
log "3/10 ensuring accounts authz-test-A / authz-test-B"
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
log "4/10 ensuring projects A1 / A2 / B1"
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
log "5/10 ensuring access bindings"
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
log "6/10 invite INV to account-A (KAC-125)"
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
log "7/10 ensuring seed VPC networks"
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

# 9) KAC-127 model 5-6 — ServiceAccounts + SA-keys (Hydra OAuth clients).
log "9/10 ensuring ServiceAccounts + SA-keys (KAC-127 models 5-6)"

# SA-A — granted SA (vpc-editor on project-A1). SANG — no-grant SA.
find_sa_by_name() {
  local name="$1" acct="$2"
  api GET "/iam/v1/serviceAccounts?accountId=$acct" "$JWT_BOOTSTRAP" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); n=[x for x in (d.get('serviceAccounts') or []) if x.get('name')=='$name']; print(n[0].get('id','') if n else '')" 2>/dev/null || true
}
ensure_sa() {
  local name="$1" acct="$2"
  local found
  found=$(find_sa_by_name "$name" "$acct")
  if [ -n "$found" ]; then echo "$found"; return; fi
  local body op op_id
  body=$(printf '{"accountId":"%s","name":"%s","description":"KAC-127 authz fixture"}' "$acct" "$name")
  op=$(api POST "/iam/v1/serviceAccounts" "$JWT_BOOTSTRAP" "$body")
  op_id=$(echo "$op" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
  if [ -z "$op_id" ]; then echo "[setup] WARN ServiceAccount.Create failed: $op" >&2; echo ""; return; fi
  poll_op "$op_id" "$JWT_BOOTSTRAP" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("metadata") or {}).get("serviceAccountId",""))'
}
SVA_A=$(ensure_sa "authz-sa-a" "$ACCOUNT_A")
SVA_NOGRANT=$(ensure_sa "authz-sa-nogrant" "$ACCOUNT_A")
log "    service accounts: A=$SVA_A NOGRANT=$SVA_NOGRANT"

# Grant SA-A vpc-editor on project-A1 (subject_type=service_account).
ensure_sa_binding() {
  local subject_id="$1" role_id="$2" resource_type="$3" resource_id="$4"
  local body
  body=$(printf '{"subjectType":"service_account","subjectId":"%s","roleId":"%s","resourceType":"%s","resourceId":"%s"}' \
    "$subject_id" "$role_id" "$resource_type" "$resource_id")
  api POST "/iam/v1/accessBindings" "$JWT_BOOTSTRAP" "$body" >/dev/null || true
}
ensure_sa_binding "$SVA_A" "rol00000000000000vpced" "project" "$PROJECT_A1"
# SVA_NOGRANT — intentionally NO bindings (model 5 negative).

# Issue SA-key (Hydra OAuth client) for SA-A via SAKeyService.Issue.
# `client_secret` returned ONCE; не персистится, в env не кладётся.
issue_sa_key() {
  local sva_id="$1"
  local body op op_id
  body=$(printf '{"serviceAccountId":"%s","description":"KAC-127 authz fixture key","createdByUserId":"%s"}' \
    "$sva_id" "$USER_BOOT")
  op=$(api POST "/iam/v1/serviceAccounts/${sva_id}/keys" "$JWT_BOOTSTRAP" "$body")
  op_id=$(echo "$op" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
  if [ -z "$op_id" ]; then
    log "    WARN SAKeyService.Issue вернул не Operation (proto может быть не зарегистрирован): $(echo "$op" | head -c 160)"
    echo ""
    return
  fi
  poll_op "$op_id" "$JWT_BOOTSTRAP" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("metadata") or {}).get("keyId",""))' 2>/dev/null || true
}
SA_KEY_A=$(issue_sa_key "$SVA_A")
log "    SA-key for SA-A: keyId=$SA_KEY_A (client_secret returned once — НЕ персистится)"

# 10) Mint SA + API tokens (dev-mode HS256 equivalents of Hydra-issued JWTs).
#     Реальный client_credentials grant — Hydra /oauth2/token; на стенде
#     api-gateway authn dev-mode принимает HS256 dev-secret JWT, поэтому
#     SA-токен моделируется minter'ом с kacho_principal_type=service_account.
log "10/10 minting SA + API tokens (KAC-127 models 5-6)"
EXP_SECONDS=$((EXP_HOURS * 3600))
JWT_SAA=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --sa "$SVA_A" --exp-seconds "$EXP_SECONDS")
JWT_SANG=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --sa "$SVA_NOGRANT" --exp-seconds "$EXP_SECONDS")
API_TOKEN_VALID=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --api-token "$SVA_A" \
  --scope "vpc.* project:$PROJECT_A1" --exp-seconds "$EXP_SECONDS")
# Expired API token — exp 1h в прошлом.
API_TOKEN_EXPIRED=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --api-token "$SVA_A" \
  --scope "vpc.* project:$PROJECT_A1" --exp-seconds "-3600")
# Revoked API token: валидный по подписи, но keyId отозван через
# SAKeyService.Revoke → kacho-iam authn-слой отвергает (session_revocations).
API_TOKEN_REVOKED=$(python3 "$SCRIPT_DIR/setup-jwt.py" --secret "$DEV_SECRET" --api-token "$SVA_A" \
  --scope "vpc.* project:$PROJECT_A1" --exp-seconds "$EXP_SECONDS")
if [ -n "$SA_KEY_A" ]; then
  api DELETE "/iam/v1/serviceAccounts/${SVA_A}/keys/${SA_KEY_A}" "$JWT_BOOTSTRAP" >/dev/null 2>&1 || true
  log "    SA-key $SA_KEY_A revoked (apiTokenRevoked → expect 401)"
fi
# Malformed token — синтаксически битый JWS (2 сегмента вместо 3).
API_TOKEN_MALFORMED="eyJhbGciOiJIUzI1NiJ9.bm90LWEtcmVhbC10b2tlbg"

# Write authz-fixtures.json + patch env-files.
log "writing $OUT_DIR/authz-fixtures.json"
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
  "userINVId": "$USER_INV",
  "svaAId": "$SVA_A",
  "svaNoGrantId": "$SVA_NOGRANT",
  "jwtSAA": "$JWT_SAA",
  "jwtSANoGrant": "$JWT_SANG",
  "apiTokenValid": "$API_TOKEN_VALID",
  "apiTokenRevoked": "$API_TOKEN_REVOKED",
  "apiTokenExpired": "$API_TOKEN_EXPIRED",
  "apiTokenMalformed": "$API_TOKEN_MALFORMED"
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
