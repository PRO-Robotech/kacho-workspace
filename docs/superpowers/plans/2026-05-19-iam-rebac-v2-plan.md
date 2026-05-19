# IAM ReBAC v2 — Implementation Plan (KAC-126 epic)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Расширить IAM-модель Kachō поверх KAC-108 baseline: cluster-root (`kacho-system:*`), custom Role project-scope, auto-admin binding на каждый `Project.Create`, project-level invite, ServiceAccount tokens через Hydra OAuth2 client_credentials, scoped grants по списку имён (N per-id AccessBinding), List-side filtering через OpenFGA `ListObjects` RPC, Internal API для default-role catalog.

**Architecture:** новый `cluster:singleton` OpenFGA-объект (cascade `system_admin from cluster` пронизывает всю модель account/project/resource), миграция `roles.account_id → project_id` для custom (system остаётся cluster-wide), `access_bindings.status ∈ {PENDING,ACTIVE}`, `corelib/authz/listobjects.go` (cache+LISTEN-invalidate, как Check), per-service List-handler фильтрация через ListObjects, kacho-iam ↔ Hydra admin для SA-keys (mapping `sva-id ↔ hydra_client_id` в БД, secret — в Hydra).

**Tech Stack:** Go 1.22, protobuf + buf, pgx/pgxpool + goose миграции, OpenFGA `ListObjects/Check/Write/Delete` API, ORY Hydra admin API v2, Kratos admin API (recovery-link для invite), Helm 3.

**Reference docs:**
- Spec: `docs/superpowers/specs/2026-05-19-iam-rebac-redesign-design.md` (этот эпик)
- Baseline spec (предусловие, должно быть merged): `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` (KAC-108)
- Existing IAM model: vault `obsidian/kacho/resources/iam-*.md`
- Workspace policy: `CLAUDE.md` (KAC ticketing, Conventional Commits, branch naming `KAC-<N>`, vault discipline, acceptance-gate)

---

## Workflow notes (Kacho-specific)

Этот план **не TDD per-step**. В проекте Kachō TDD выполняется внутри work каждого task через специальных агентов:
- `acceptance-author` пишет Given-When-Then (red phase — тесты not yet implemented).
- `integration-tester` конвертирует GWT в Go integration tests + bash e2e.
- `rpc-implementer` имплементит handler/service/repo/proto после APPROVED acceptance.
- `go-style-reviewer` / `db-architect-reviewer` / `proto-api-reviewer` проверяют.
- `qa-test-engineer` extend'нет newman regression suite.

План — это **roadmap**: каждый task ссылается на нужного агента и target deliverable. Внутри task агент сам делает test-first.

**Coding-gate**: §«Запреты #1» CLAUDE.md — никакого кода до APPROVED acceptance doc. Это Phase 1.

---

## Phase 0: Ticketing & branches (workspace policy)

### Task 0.1: Создать YouTrack-эпик KAC-126

**Files:** none (внешний tracker — YouTrack `prorobotech.youtrack.cloud`, проект `KAC`).

- [ ] **Step 1:** Через MCP `mcp__youtrack__create_issue` создать issue в проекте `KAC`:
  - summary: `[EPIC] IAM ReBAC v2 — cluster-root + scoped grants + ListObjects + project-roles + SA-tokens + invite-per-project`
  - description: ссылка на spec `docs/superpowers/specs/2026-05-19-iam-rebac-redesign-design.md`; ссылка на baseline KAC-108; декомпозиция (см. ниже); cross-repo порядок выполнения (spec §12.3); DoD (spec §14).
  - link as `subtask of` → KAC-104 (IAM master epic).

- [ ] **Step 2:** Добавить эпик в текущий спринт (`POST /api/commands` с `Board kacho <sprint-name>`). На 2026-05 — «Первый спринт», id `186-22`.

- [ ] **Step 3:** Создать 10 subtasks (KAC-127 .. KAC-136), каждый описан, привязан к эпику через `subtask of`, добавлен в текущий спринт, проставлен `агент`:

| Subtask | Summary | Агент | Зависит от |
|---|---|---|---|
| KAC-127 | acceptance doc Given-When-Then (35-40 scenarios) | `acceptance-author` | — |
| KAC-128 | kacho-proto: new .proto + регенерация stubs | `proto-sync` + `proto-api-reviewer` | KAC-127 |
| KAC-129 | kacho-corelib: authz/listobjects.go + hydra-admin client | `rpc-implementer` + `go-style-reviewer` | KAC-128 |
| KAC-130 | kacho-iam: migration 0010 + Cluster domain/repo/handler + Role refactor + AccessBinding status + Bootstrap-worker + SA-keys + ListMyAccounts | `migration-writer` + `rpc-implementer` + `db-architect-reviewer` + `go-style-reviewer` | KAC-128, KAC-129 |
| KAC-131 | kacho-vpc / kacho-compute / kacho-loadbalancer: ListAllowedIDs integration в каждый List-handler | `rpc-implementer` + `go-style-reviewer` (3 PRs) | KAC-130 |
| KAC-132 | kacho-api-gateway: register InternalClusterService + InternalRoleService (internal mux) + SA-key/InvitePending/ListMyAccounts (public mux) | `api-gateway-registrar` | KAC-130 |
| KAC-133 | kacho-deploy: openfga-bootstrap-job DSL update + Hydra config + KACHO_IAM_BOOTSTRAP_ROOT_EMAIL env + helm values | `claude` | KAC-130, KAC-132 |
| KAC-134 | kacho-ui: ListMyAccounts cascader + Project-invite modal + SA-keys page + cluster-admin badge | `claude` | KAC-130, KAC-132 |
| KAC-135 | newman regression (≥30 cases) + k6 List-filter load test | `qa-test-engineer` + `load-testing-coach` | KAC-131, KAC-133 |
| KAC-136 | vault updates (12+ files) + final KAC-126 trail update | `claude` | all above |

- [ ] **Step 4:** Verify subtasks visible на board `agiles/183-12` через `mcp__youtrack__get_all_issues`.

### Task 0.2: Создать ветки `KAC-126` в 10 репо

**Files:** none (только git operations).

- [ ] **Step 1:** Pre-condition: KAC-108 должен быть merged в `main` каждого репо. Если нет — block KAC-126 work, finish KAC-108 first.

```bash
for repo in kacho-proto kacho-corelib kacho-iam kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway kacho-deploy kacho-ui kacho-workspace; do
  cd "project/$repo" 2>/dev/null || cd "$repo"
  git fetch origin main && git checkout main && git pull
  cd -
done
```

- [ ] **Step 2:** В каждом из 10 репо создать ветку:

```bash
for repo in kacho-proto kacho-corelib kacho-iam kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway kacho-deploy kacho-ui kacho-workspace; do
  cd "project/$repo" 2>/dev/null || cd "$repo"
  git checkout -b KAC-126
  cd -
done
```

(Для `kacho-workspace` ветка `KAC-126` уже создана этим планом.)

---

## Phase 1: Acceptance doc (canonical Given-When-Then)

### Task 1.1: Acceptance-author пишет Given-When-Then doc

**Files:**
- Create: `docs/specs/sub-phase-2.0-KAC-126-acceptance.md`

- [ ] **Step 1:** Dispatch `acceptance-author` агент с промптом:
  > Прочитай `docs/superpowers/specs/2026-05-19-iam-rebac-redesign-design.md`. Напиши Given-When-Then acceptance doc в `docs/specs/sub-phase-2.0-KAC-126-acceptance.md` (35-40 сценариев) с обязательным покрытием: cluster-root bootstrap (3-4 GWT), GrantClusterAdmin RPC (2-3 GWT), Role.Create project-scope (2-3 GWT), system-role Internal RPC (2-3 GWT), AccessBinding batch + status PENDING (3-4 GWT), Bootstrap signup → Account+Project+admin (2-3 GWT), ProjectService.Create auto-admin (2-3 GWT), InvitePending (Case A/B/C — 3-4 GWT), Activation on first OIDC (2-3 GWT), SA-key Create/Delete (3-4 GWT), List-filter ListObjects (3-4 GWT), cross-account leak prevention (2-3 GWT), reactivity ≤10s revoke cluster-admin (1-2 GWT), fail-modes (Hydra/Kratos/OpenFGA unavailable — 2-3 GWT). Decision Log spec'а — нормативно. **Out-of-scope** запрещён.

- [ ] **Step 2:** Acceptance-author commit'ит файл в ветке `KAC-126` репо `kacho-workspace`.

### Task 1.2: Acceptance-reviewer ревью acceptance doc

**Files:** read-only review.

- [ ] **Step 1:** Dispatch `acceptance-reviewer` агент с промптом:
  > Ревью `docs/specs/sub-phase-2.0-KAC-126-acceptance.md`. Проверь: (a) coverage all spec sections, (b) scenarios complete (positive/negative/edge), (c) traceability to design doc decision log, (d) realism (testable on e2c825 stand), (e) scope adherence (out-of-scope не нарушен). Вернуть ✅ APPROVED или ❌ CHANGES REQUESTED со списком issues.

- [ ] **Step 2:** Если ❌ — `acceptance-author` правит, повторный review. Цикл пока не ✅ APPROVED.

- [ ] **Step 3:** Commit final APPROVED файла. Это **gate** на Phase 2+ (запрет CLAUDE.md #1).

### Task 1.3: Создать YouTrack комментарий в KAC-127 с PR-URL

- [ ] **Step 1:** PR в `kacho-workspace/KAC-126`: «KAC-127 acceptance doc APPROVED».
- [ ] **Step 2:** Через `mcp__youtrack__add_comment` приложить PR URL к KAC-127 + перевести KAC-127 в `Test` → `Done`.

---

## Phase 2: kacho-proto (новые .proto + регенерация stubs)

### Task 2.1: Новый proto — `internal_cluster_service.proto`

**Files:**
- Create: `proto/kacho/cloud/iam/v1/cluster.proto`
- Create: `proto/kacho/cloud/iam/v1/internal_cluster_service.proto`

- [ ] **Step 1:** Dispatch `proto-sync` агент:
  > Создай envelope-style сообщение `Cluster {metadata:{id,name,description,created_at}, spec:{}, status:{}}` в `cluster.proto`. Service `InternalClusterService` в `internal_cluster_service.proto`: `Get(GetClusterRequest) returns (Cluster)` — sync; `GrantClusterAdmin(GrantClusterAdminRequest{subject_type,subject_id}) returns (operation.Operation)` — async; `RevokeClusterAdmin(...)` async; `ListClusterAdmins(...)` sync paginated. Все поля — `buf.validate` annotations.

- [ ] **Step 2:** `proto-api-reviewer` ревью: package = `kacho.cloud.iam.v1`, envelope metadata/spec/status, reserved field numbers, buf.validate, buf lint clean, buf breaking clean.

### Task 2.2: Новый proto — `internal_role_service.proto`

**Files:**
- Create: `proto/kacho/cloud/iam/v1/internal_role_service.proto`

- [ ] **Step 1:** Dispatch `proto-sync`:
  > Service `InternalRoleService`: `UpsertSystemRole(UpsertSystemRoleRequest{name, description, permissions[]}) returns (operation.Operation)`, `DeleteSystemRole(DeleteSystemRoleRequest{name}) returns (operation.Operation)`, `ListSystemRoles(ListSystemRolesRequest{page_size,page_token}) returns (ListSystemRolesResponse{roles[],next_page_token})`. Permissions — array string `<module>.<resource>.<verb>` с regex validation.

- [ ] **Step 2:** `proto-api-reviewer` ревью.

### Task 2.3: Новый proto — `service_account_key_service.proto`

**Files:**
- Create: `proto/kacho/cloud/iam/v1/service_account_key_service.proto`

- [ ] **Step 1:** Dispatch `proto-sync`:
  > Service `ServiceAccountKeyService`: `Create(CreateServiceAccountKeyRequest{service_account_id}) returns (operation.Operation{response=ServiceAccountKey})`, `Delete(DeleteServiceAccountKeyRequest{key_id}) returns (operation.Operation)`, `List(ListServiceAccountKeysRequest{service_account_id,page_size,page_token}) returns (ListServiceAccountKeysResponse)`. Message `ServiceAccountKey {metadata:{id=hydra_client_id,sva_id,created_at}, spec:{}, status:{}}` + одноразовое поле `client_secret` в Operation.response (вне самого ServiceAccountKey message — иначе оно появится в Get/List, что нельзя).

- [ ] **Step 2:** `proto-api-reviewer` ревью: client_secret должен быть **только** в Operation.response для Create, не в самом ServiceAccountKey message.

### Task 2.4: Изменения в existing proto

**Files:**
- Modify: `proto/kacho/cloud/iam/v1/role.proto` — `account_id → project_id` в `Role.metadata`.
- Modify: `proto/kacho/cloud/iam/v1/role_service.proto` — `CreateRoleRequest.project_id` (replace `account_id`).
- Modify: `proto/kacho/cloud/iam/v1/access_binding.proto` — добавить `AccessBinding.status` (enum STATUS_UNSPECIFIED/PENDING/ACTIVE).
- Modify: `proto/kacho/cloud/iam/v1/access_binding_service.proto` — `UpsertAccessBindingRequest` поддержка `oneof resource_target { string resource_id = N; ResourceIDs resource_ids = M; }`; новый RPC `InvitePending(InvitePendingRequest{email,role_id,resource_type,resource_id}) returns (operation.Operation{response=InvitePendingResponse{user_id,invited_inline:bool,magic_link:string optional}})`.
- Modify: `proto/kacho/cloud/iam/v1/user_service.proto` — `ListMyAccounts(ListMyAccountsRequest{page_size,page_token}) returns (ListMyAccountsResponse{accounts[],next_page_token})`. principal — из ctx, не в request.

- [ ] **Step 1:** Dispatch `proto-sync`. Acceptance ref §5.2.

- [ ] **Step 2:** `proto-api-reviewer`: backward-compat check (`buf breaking` — field renumber запрещён, `account_id` → reserved + new field `project_id`).

### Task 2.5: Регенерация Go stubs + commit

**Files:**
- Modify: `gen/go/kacho/cloud/iam/v1/*.pb.go` (auto-generated)

- [ ] **Step 1:** `cd project/kacho-proto && buf generate`.
- [ ] **Step 2:** `git add -A && git commit -m "feat(proto): KAC-126 — Cluster + InternalRoleService + SAKeys + Role.project_id + AB.status + InvitePending + ListMyAccounts"`.
- [ ] **Step 3:** PR в `kacho-proto/KAC-126` → review → merge.
- [ ] **Step 4:** YouTrack: PR URL → KAC-128 → Done.

---

## Phase 3: kacho-corelib (authz/listobjects.go + hydra-admin client)

### Task 3.1: `corelib/authz/listobjects.go`

**Files:**
- Create: `corelib/authz/listobjects.go`
- Create: `corelib/authz/listobjects_test.go`

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Создай пакет с интерфейсом `ListObjectsClient interface { ListAllowedIDs(ctx, principal Principal, objectType, relation string) ([]string, error) }`. Реализация `openfgaListObjectsClient`: cache 5s TTL в memory (sync.Map с TTL-eviction), key = principal.ID + objectType + relation. Miss → `openfga.ListObjects(authorization_model_id, user, relation, type)` через corelib `openfgaClient` (KAC-108 reuse). LISTEN на channel `kacho_iam_subjects` (NOTIFY pushes subject_id) → invalidate всех cached entries для этого subject. Fail-closed на openfga error.

- [ ] **Step 2:** Tests: testcontainers OpenFGA + Postgres NOTIFY simulation. Cache hit / miss / invalidate-on-revoke scenarios.

- [ ] **Step 3:** `go-style-reviewer` ревью.

### Task 3.2: `corelib/clients/hydra_admin.go`

**Files:**
- Create: `corelib/clients/hydra_admin.go`
- Create: `corelib/clients/hydra_admin_test.go`

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Создай HTTP client wrapper для Hydra admin API v2: `CreateOAuthClient(ctx, clientID, scope, grantTypes) → (client_id, client_secret, error)`, `DeleteOAuthClient(ctx, clientID) → error`, `GetOAuthClient(ctx, clientID) → (Client, error)`. Bearer-auth через env `KACHO_HYDRA_ADMIN_TOKEN`. Timeout 5s. Idempotent — повторный Create на тот же clientID отдаёт existing (Hydra возвращает 409 → wrap в `ErrAlreadyExists`).

- [ ] **Step 2:** Tests с httptest mock Hydra. Happy-path / 401 / 409 / 5xx / timeout.

- [ ] **Step 3:** `go-style-reviewer` ревью.

### Task 3.3: Commit + PR

- [ ] **Step 1:** `git add -A && git commit -m "feat(authz,clients): KAC-126 — ListObjectsClient + HydraAdmin wrapper"`.
- [ ] **Step 2:** PR `kacho-corelib/KAC-126` → review → merge.
- [ ] **Step 3:** YouTrack: PR URL → KAC-129 → Done.

---

## Phase 4: kacho-iam migration + Cluster + Role refactor + AB status + Bootstrap-worker + SA-keys + ListMyAccounts

> Это самая большая фаза (≈30-40 файлов). Разбита на 9 sub-tasks. Каждая sub-task = один commit.

### Task 4.1: Migration `0010_kac126_bootstrap.sql`

**Files:**
- Create: `internal/migrations/0010_kac126_bootstrap_cluster_root.sql`

- [ ] **Step 1:** Dispatch `migration-writer`:
  > Goose миграция (spec §3.4): (a) CREATE TABLE clusters + INSERT singleton row `cluster_kacho_root`; (b) CREATE TABLE cluster_admin_grants (subject_type/subject_id/granted_at/granted_by_user_id); INSERT seed (env KACHO_IAM_BOOTSTRAP_ROOT_EMAIL → external_id lookup, или placeholder user-row + dataset); (c) CREATE TABLE service_account_oauth_clients (sva_id PK, hydra_client_id UNIQUE); (d) ALTER TABLE roles DROP COLUMN account_id, ADD COLUMN project_id TEXT NULL FK→projects(id) RESTRICT + roles_system_xor_project CHECK + roles_custom_unique partial UNIQUE; (e) ALTER TABLE access_bindings ADD COLUMN status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK IN ('PENDING','ACTIVE'); (f) INSERT seed system-role roles/kacho-system.admin (perms `*.*.*`), roles/kacho-system.viewer; (g) INSERT outbox FGA-tuple write для seed-cluster-admin.

- [ ] **Step 2:** `db-architect-reviewer` ревью: проверить advisory locks, statement_timeout, CHECK constraints, partial UNIQUE синтаксис, нет cross-service FK.

### Task 4.2: Cluster domain + repo

**Files:**
- Create: `internal/domain/cluster.go`
- Create: `internal/repo/kacho/pg/cluster.go`
- Create: `internal/repo/kacho/pg/cluster_integration_test.go`

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Domain `Cluster {ID, Name, Description, CreatedAt}`. Repo: `Get(ctx) (Cluster, error)` — singleton (без id-параметра), `GrantClusterAdmin(ctx, subjectType, subjectID, grantedBy) error` — INSERT cluster_admin_grants + INSERT outbox FGA-tuple write одной TX, idempotent (UNIQUE). `RevokeClusterAdmin` — DELETE row + INSERT outbox FGA-tuple delete. `ListClusterAdmins(ctx, limit, offset)`.

- [ ] **Step 2:** Integration tests (testcontainers Postgres) — happy-path, idempotent re-grant, race на параллельный grant (UNIQUE → idempotent), revoke + outbox row.

### Task 4.3: Role refactor (account_id → project_id)

**Files:**
- Modify: `internal/domain/role.go` — replace AccountID → ProjectID.
- Modify: `internal/repo/kacho/pg/role.go` — все queries.
- Modify: `internal/apps/kacho/api/role/*.go` — handler signatures.
- Modify: `internal/repo/kacho/pg/role_integration_test.go`.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Role.AccountID → Role.ProjectID. Все handler (Create/Update/Delete/List/Get) принимают/отдают project_id. `RoleService.Create` permission check: principal должен быть `admin` на target project (через interceptor). System-role (`is_system=true`) — `project_id` NULL обязательно.

- [ ] **Step 2:** Integration tests updated.

### Task 4.4: AccessBinding extension (status + batch resource_ids)

**Files:**
- Modify: `internal/domain/access_binding.go` — добавить Status enum.
- Modify: `internal/repo/kacho/pg/access_binding.go` — Upsert принимает []resourceID, INSERT batch one TX.
- Modify: `internal/apps/kacho/api/access_binding/upsert.go` — handler unwraps oneof, batch.
- Modify: `internal/repo/kacho/pg/access_binding_integration_test.go`.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > AccessBinding.Status enum {PENDING, ACTIVE}. Default = ACTIVE. Status PENDING → НЕ INSERT outbox FGA-tuple write (subject ещё не активен). ACTIVE → INSERT outbox. UpsertAccessBinding(...) принимает либо single resource_id (legacy), либо []resource_ids; внутри — for-loop INSERT (один TX); UNIQUE constraint = idempotent. Activate(ctx, userID) — UPDATE status=ACTIVE WHERE subject_id=userID AND status=PENDING + INSERT outbox for each affected row, всё одной TX.

- [ ] **Step 2:** Integration tests: batch Upsert (5 ids), идемпотентный re-Upsert (один INSERT), PENDING без outbox, Activate → outbox rows.

### Task 4.5: InvitePending handler (3 cases: ACTIVE existing / PENDING re-invite / new email)

**Files:**
- Create: `internal/apps/kacho/api/access_binding/invite_pending.go`
- Modify: `internal/clients/kratos_admin.go` — GenerateRecoveryLink реализация (KAC-125 был stub).
- Create: `internal/apps/kacho/api/access_binding/invite_pending_integration_test.go`

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > InvitePendingHandler: (1) permission check principal admin on target project; (2) determine account-owner project; (3) resolve email → user candidate в этом account; (4) Case A ACTIVE found → Upsert AB status=ACTIVE; (5) Case B PENDING found → Upsert AB status=PENDING + Kratos regenerate recovery-link; (6) Case C new → INSERT users(PENDING) + INSERT AB PENDING + Kratos create-identity → recovery-link; (7) return InvitePendingResponse.

- [ ] **Step 2:** Integration tests: 3 cases + idempotent re-invite + invalid email (RFC5321 reject).

### Task 4.6: Bootstrap-worker rewrite (signup → Account + default Project + 2 bindings)

**Files:**
- Modify: `internal/apps/kacho/jobs/bootstrap_worker.go` (KAC-117 worker; rewrite).
- Modify: `internal/apps/kacho/api/user/internal_upsert.go` — UpsertFromIdentity now activates PENDING.
- Modify: integration tests.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Bootstrap-worker реагирует на NOTIFY users_inserted. Если user.invite_status = PENDING — Activate (вместо Account create); если ACTIVE & first-time (no Account yet) — create Account+default-Project+2 bindings (account.admin + project.admin) одной TX.

- [ ] **Step 2:** Integration tests: signup → all 4 rows + 2 outbox tuples; signup идемпотент (повторный = no-op); invited user activation = только UPDATE PENDING bindings.

### Task 4.7: ProjectService.Create auto-admin

**Files:**
- Modify: `internal/apps/kacho/api/project/create.go`.
- Modify: `internal/repo/kacho/pg/project_integration_test.go`.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > ProjectService.Create handler: (1) permission check (viewer/editor/admin на parent Account); (2) BEGIN TX — INSERT projects + INSERT access_bindings(creator, role=roles/project.admin, resource=project:<new_id>, status=ACTIVE) + INSERT outbox FGA-tuple + creator-tuple sync write (KAC-108 D-11 pattern); (3) COMMIT; (4) return Operation{response=Project}.

- [ ] **Step 2:** Integration tests: Create → AB row created same TX; creator immediately Gets (no async wait); idempotent re-Create на existing project name → AlreadyExists.

### Task 4.8: SA-keys через Hydra admin

**Files:**
- Create: `internal/apps/kacho/api/sa_key/create.go`, `delete.go`, `list.go`.
- Create: `internal/repo/kacho/pg/service_account_oauth_client.go`.
- Modify: composition root `cmd/kacho-iam/main.go` — wire hydra-admin client.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > ServiceAccountKeyService.Create: (1) permission check; (2) hydra-admin.CreateOAuthClient(client_id=sva_<id>, scope='kacho.iam', grant_types=['client_credentials']) → (id, secret); (3) INSERT service_account_oauth_clients (sva_id, hydra_client_id); (4) return Operation{response=ServiceAccountKey + client_secret one-shot}. Delete — hydra.DeleteOAuthClient + DELETE row. List — SELECT (без secrets).

- [ ] **Step 2:** Integration tests: happy-path Create (mock Hydra), Hydra-409 idempotent, Hydra-5xx → Operation.error=Unavailable + no DB row, Delete idempotent.

### Task 4.9: UserService.ListMyAccounts

**Files:**
- Create: `internal/apps/kacho/api/user/list_my_accounts.go`.
- Modify: integration test.

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > ListMyAccounts handler: principal.external_id из ctx → SELECT users WHERE external_id=$1 AND status='ACTIVE' → JOIN accounts → return Account[] с is_owner field (accounts.owner_user_id = user.id).

- [ ] **Step 2:** Integration tests: один identity → 3 user-rows в 3 accounts → ListMyAccounts returns 3; один identity без invited → returns 1 (own).

### Task 4.10: Commit + PR + YouTrack

- [ ] **Step 1:** Single PR `kacho-iam/KAC-126` со всеми 9 task. Conventional Commits per task (или squash в финале — depends на git policy).
- [ ] **Step 2:** Review (`go-style-reviewer`, `db-architect-reviewer`, `system-design-reviewer`). Цикл правок до approved.
- [ ] **Step 3:** Merge → YouTrack PR URL → KAC-130 → Done.

---

## Phase 5: kacho-vpc / kacho-compute / kacho-loadbalancer (ListAllowedIDs integration)

> 3 параллельных репо, идентичный pattern. Один task per repo.

### Task 5.1: kacho-vpc — все List-handler через ListAllowedIDs

**Files (kacho-vpc):**
- Modify: `internal/apps/kacho/api/network/list.go`
- Modify: `internal/apps/kacho/api/subnet/list.go`
- Modify: `internal/apps/kacho/api/security_group/list.go`
- Modify: `internal/apps/kacho/api/route_table/list.go`
- Modify: `internal/apps/kacho/api/address/list.go`
- Modify: `internal/apps/kacho/api/gateway/list.go`
- Modify: `internal/apps/kacho/api/private_endpoint/list.go`
- Modify: `internal/apps/kacho/api/network_interface/list.go`
- Modify: `internal/apps/kacho/api/address_pool/list.go` (Internal — но тоже фильтруется)
- Modify: composition root — wire ListObjectsClient.
- Modify: all integration tests (новые scenarios: empty grants → {}, 2-id grants → 2 networks).

- [ ] **Step 1:** Dispatch `rpc-implementer`:
  > Каждый List-handler в kacho-vpc: первая строка handler'а — `allowedIDs, err := s.authz.ListAllowedIDs(ctx, principal, "<vpc_type>", "viewer")`; if err → Unavailable; if empty → return empty response (не 403); else SELECT WHERE id IN(allowedIDs) с page filter.

- [ ] **Step 2:** Integration test extension: scenarios `user_with_no_bindings_sees_empty`, `user_with_2_network_bindings_sees_2`, `user_with_account_admin_sees_all`, `service_account_with_bindings_sees_filtered`.

- [ ] **Step 3:** PR `kacho-vpc/KAC-126` → review → merge → YouTrack PR URL.

### Task 5.2: kacho-compute — все List-handler через ListAllowedIDs

**Files:** аналогично 5.1 для compute (Instance, Disk, Image, Snapshot, плюс Internal: Hypervisor, DiskType, Region, Zone).

- [ ] **Step 1-3:** Same pattern. Internal resources (Hypervisor) — фильтруются только для не-cluster-admin (cluster-admin видит все).

### Task 5.3: kacho-loadbalancer — все List-handler

**Files:** NetworkLoadBalancer, TargetGroup List-handler.

- [ ] **Step 1-3:** Same pattern.

### Task 5.4: YouTrack KAC-131 → Done (3 PR URLs)

- [ ] **Step 1:** Все 3 PR merged.
- [ ] **Step 2:** YT comment в KAC-131 с 3 PR URLs.

---

## Phase 6: kacho-api-gateway (register new RPCs)

### Task 6.1: Register new public + internal services

**Files:**
- Modify: `internal/restmux/mux.go` — register on public TLS mux: `UserService.ListMyAccounts`, `AccessBindingService.InvitePending`, `ServiceAccountKeyService.*`; on internal mux: `InternalClusterService.*`, `InternalRoleService.*`.
- Modify: `internal/allowlist/list.go` — добавить новые public RPCs (НЕ Internal* — гарантия запрета #6).
- Modify: `internal/opsproxy/proxy.go` — register Operation prefixes для long-running ops.
- Modify: integration tests.

- [ ] **Step 1:** Dispatch `api-gateway-registrar` агент:
  > Регистрируй: на TLS public mux 443 — UserService.ListMyAccounts, AccessBindingService.InvitePending, ServiceAccountKeyService.*; на internal-mux 8081 — InternalClusterService.*, InternalRoleService.*. **НЕ** добавлять Internal* в allowlist (запрет #6). Тесты director_test.go scenarios: A_InternalClusterBlocked, A_InternalRoleBlocked (на public), A_ListMyAccountsAllowed.

- [ ] **Step 2:** PR `kacho-api-gateway/KAC-126` → review → merge → YT PR URL → KAC-132 → Done.

---

## Phase 7: kacho-deploy (helm + openfga-bootstrap-job + Hydra)

### Task 7.1: openfga-bootstrap-job DSL update

**Files:**
- Modify: `helm/umbrella/templates/openfga-model-stub-configmap.yaml` — replace stub DSL на v2 (см. spec §4).
- Modify: `helm/umbrella/templates/openfga-bootstrap-job.yaml` — bump checksum для re-run.

- [ ] **Step 1:** Подставь DSL из spec §4 (с type cluster + cascade `system_admin from cluster` в account/project/resource).
- [ ] **Step 2:** Idempotency: helm upgrade with same DSL → job видит current model_id matches → skip. Verify smoke.

### Task 7.2: Hydra deployment + admin endpoint config

**Files:**
- Modify: `helm/umbrella/Chart.yaml` — bump version, `hydra.enabled=true`.
- Modify: `helm/umbrella/values.dev.yaml` — `hydra.config.urls.self.public/admin`, secrets, oauth2 issuer.
- Modify: `helm/umbrella/charts/kacho-iam/values.yaml` — `KACHO_HYDRA_ADMIN_URL`, `KACHO_HYDRA_ADMIN_TOKEN_SECRET_NAME`.

- [ ] **Step 1:** Включить hydra dep, прописать URLs/secrets.
- [ ] **Step 2:** Local smoke: `helm install ... && curl https://hydra.kacho.local/.well-known/openid-configuration` returns valid JSON.

### Task 7.3: KACHO_IAM_BOOTSTRAP_ROOT_EMAIL env + docs

**Files:**
- Modify: `helm/umbrella/charts/kacho-iam/values.yaml` — `bootstrapRootEmail` value.
- Modify: `helm/umbrella/charts/kacho-iam/templates/deployment.yaml` — env from value.
- Modify: `helm/umbrella/charts/kacho-iam/README.md` — документация.

- [ ] **Step 1:** Default = `""`; production = required (Helm `required` template func).
- [ ] **Step 2:** Smoke: deploy with `bootstrapRootEmail=root@example.com` → SELECT cluster_admin_grants WHERE granted_by_user_id IS NULL → expected 1 row после first login.

### Task 7.4: Deploy на e2c825 + KAC-133 → Done

- [ ] **Step 1:** `make ci-images` (новые образы iam + apigw).
- [ ] **Step 2:** `helm upgrade kacho-umbrella . -f values.dev.yaml -f clusters/e2c825/overrides.yaml`.
- [ ] **Step 3:** Smoke: cluster:singleton tuple появился в OpenFGA (через playground); kacho-iam logs clean.
- [ ] **Step 4:** YT PR URL → KAC-133 → Done.

---

## Phase 8: kacho-ui (cascader + invite + SA-keys + cluster-admin badge)

### Task 8.1: ListMyAccounts cascader

**Files:**
- Modify: `src/pages/iam/access/AccountCascader.tsx` — call ListMyAccounts; show all Account'ы (own + invited).
- Modify: `src/pages/iam/access/AccountCrumb.tsx`.

- [ ] **Step 1:** Cascader rendering всех Account'ов от ListMyAccounts; для каждого Account вложенный список Projects (от ProjectService.List — уже фильтруется ListObjects).

### Task 8.2: Project-level invite modal

**Files:**
- Modify: `src/pages/iam/access/InviteModal.tsx` — теперь target = Project (вместо Account); resource_type = `project`, resource_id = selected Project ID. Cascader role catalog (KAC-125 уже сделал) — переиспользуется.

- [ ] **Step 1:** Backend call → InvitePending. Если response.invited_inline=true — Toast "Added existing user". Если magic_link — show modal с copy-button.

### Task 8.3: SA-keys page

**Files:**
- Create: `src/pages/iam/sa-keys/SAKeysPage.tsx` + `IssueKeyModal.tsx`.

- [ ] **Step 1:** Table keys (id, created_at, status). "Issue Key" button → IssueKeyModal — Create → show client_id + client_secret one-shot с warning "save now".

### Task 8.4: Cluster-admin badge для system_admin user'а

**Files:**
- Modify: `src/components/UserAvatar.tsx` — add badge "ROOT" if user is_cluster_admin (через UserService.GetMe extension).

- [ ] **Step 1:** Endpoint UserService.GetMe (или existing) дополнен `is_cluster_admin: bool` (true если user — в cluster_admin_grants).

### Task 8.5: PR + Playwright tests

- [ ] **Step 1:** PR `kacho-ui/KAC-126`.
- [ ] **Step 2:** Playwright tests: signup → cascader shows own Account → create Project → admin badge; invite by email (existing) → toast; invite by email (new) → modal with magic-link; SA-key issue → secret shown once; root-user has ROOT badge.
- [ ] **Step 3:** YT PR URL → KAC-134 → Done.

---

## Phase 9: Newman regression + k6 load test

### Task 9.1: Newman regression cases (≥30 scenarios)

**Files:**
- Modify: `kacho-test/tests/newman/cases/*.py` — добавить:
  - `iam_cluster_*.py` — GrantClusterAdmin/RevokeClusterAdmin (3-4 cases)
  - `iam_role_*.py` — system-role InternalRPC (2-3 cases)
  - `iam_role_project_*.py` — custom-role create в project + cross-project deny (2-3 cases)
  - `iam_invite_*.py` — InvitePending Cases A/B/C (3-4 cases)
  - `iam_sa_keys_*.py` — Create/Delete/List + JWT auth (4-5 cases)
  - `iam_list_filter_*.py` — empty grants / 2-id grants / cluster-admin sees-all (4-5 cases)
  - `iam_cross_account_*.py` — cross-account leak prevention (2-3 cases)
  - `iam_revoke_reactivity_*.py` — revoke cluster-admin → access denied ≤10s (1-2 cases)
- Run: `python3 gen.py` → emits Postman collection.

- [ ] **Step 1:** Dispatch `qa-test-engineer`:
  > Заведи 30+ test cases в `kacho-test/tests/newman/cases/`. Best practice: boundary value (zero / 1 / N binding'ов), equivalence partitioning, error guessing, state transitions (PENDING → ACTIVE). Каждый case = одна `pm.test()` assertion за happy + 1 negative.

- [ ] **Step 2:** Newman run против e2c825 → все PASS.

### Task 9.2: k6 load test для ListObjects-based List-filter

**Files:**
- Create: `kacho-test/tests/k6/list_filter_kac126.js`.

- [ ] **Step 1:** Dispatch `load-testing-coach`:
  > Сценарий: 100 networks per project, 10 users with N bindings (N ∈ {1, 10, 50, 100}); 100 RPS sustained 5 min; assert p95 ListObjects ≤ 100ms, p99 ≤ 250ms.

- [ ] **Step 2:** Run на e2c825 → results в `kacho-test/tests/k6/results/KAC-126-list-filter.md`.

### Task 9.3: PR + YT KAC-135 → Done

- [ ] **Step 1:** PR `kacho-test/KAC-126` + `kacho-workspace/KAC-126` (если k6 results там).
- [ ] **Step 2:** YT PR URL → KAC-135 → Done.

---

## Phase 10: Vault docs update (12+ records) + final KAC-126 trail

### Task 10.1: Vault updates

**Files:**
- Create: `obsidian/kacho/resources/iam-cluster.md`
- Modify: `obsidian/kacho/resources/iam-role.md` (project_id)
- Modify: `obsidian/kacho/resources/iam-access-binding.md` (status PENDING/ACTIVE)
- Modify: `obsidian/kacho/resources/iam-service-account.md` (SA-keys через Hydra)
- Create: `obsidian/kacho/rpc/iam-internal-cluster-service.md`
- Create: `obsidian/kacho/rpc/iam-internal-role-service.md`
- Create: `obsidian/kacho/rpc/iam-service-account-key-service.md`
- Modify: `obsidian/kacho/rpc/iam-user-service.md` (ListMyAccounts)
- Modify: `obsidian/kacho/rpc/iam-access-binding-service.md` (InvitePending + batch)
- Create: `obsidian/kacho/edges/iam-to-hydra-admin.md`
- Modify: `obsidian/kacho/edges/iam-to-openfga-check.md` (cluster: tuples + ListObjects)
- Modify: `obsidian/kacho/packages/iam-clients.md` (hydra_admin.go)
- Create: `obsidian/kacho/packages/corelib-authz.md` (listobjects.go)

- [ ] **Step 1:** Каждый файл — узкий (1-3KB), kepano-style frontmatter, wikilinks. Cмотри prior art `obsidian/kacho/resources/iam-account.md`.

### Task 10.2: Update KAC-126.md trail

**Files:**
- Modify: `obsidian/kacho/KAC/KAC-126.md` — добавить all PR URLs (10 шт), status='done', closed=2026-MM-DD.

- [ ] **Step 1:** Set frontmatter `status: done`, `closed: <date>`, fill `prs:` list.
- [ ] **Step 2:** Acceptance / DoD checklist — все галочки.

### Task 10.3: PR + YT KAC-136 → Done

- [ ] **Step 1:** Single PR `kacho-workspace/KAC-126` (vault + plan checkboxes).
- [ ] **Step 2:** YT PR URL → KAC-136 → Done.

### Task 10.4: Close KAC-126 эпик

- [ ] **Step 1:** Все subtasks Done.
- [ ] **Step 2:** Через `mcp__youtrack__update_issue_state` → KAC-126 → Done.

---

## Phase 11: Cleanup branches

### Task 11.1: Удалить feature-branches

- [ ] **Step 1:** После merge всех 10 PRs:

```bash
for repo in kacho-proto kacho-corelib kacho-iam kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway kacho-deploy kacho-ui kacho-workspace; do
  cd "project/$repo" 2>/dev/null || cd "$repo"
  git checkout main && git pull
  git branch -D KAC-126
  git push origin --delete KAC-126
  cd -
done
```

- [ ] **Step 2:** YT KAC-126 в Done; ветки cleaned.

---

## Estimated effort

| Phase | Tasks | Эквивалент LOC | Calendar (1 engineer) |
|---|---|---|---|
| 0. Ticketing | 2 | — | 0.5d |
| 1. Acceptance doc (red phase) | 3 | — | 1.5d (acceptance-author + reviewer rounds) |
| 2. Proto | 5 | ~600 | 1d |
| 3. Corelib | 3 | ~400 | 1d |
| 4. kacho-iam (big) | 10 | ~3500 | 5-7d |
| 5. vpc/compute/lb | 4 | ~1200 (по 400 на репо) | 2-3d |
| 6. api-gateway | 1 | ~200 | 0.5d |
| 7. kacho-deploy | 4 | ~300 | 1d |
| 8. kacho-ui | 5 | ~1500 | 3-4d |
| 9. Newman + k6 | 3 | ~1000 | 2d |
| 10. Vault | 3 | ~3KB × 12 | 0.5d |
| 11. Branch cleanup | 1 | — | 0.5d |
| **Total** | **44** | **~8700 LOC** | **~18-22d** (single engineer) |

---

## Risk register

| Risk | Mitigation |
|---|---|
| KAC-108 не закрыт | Phase 0 Task 0.2 Step 1 — explicit pre-condition. Block KAC-126 work until KAC-108 в Done. |
| OpenFGA DSL migration breaks existing tuples | OpenFGA сам поддерживает versioned models — старая модель остаётся доступна с prev model_id; smoke verify через playground после deploy. Rollback план в spec §12.2. |
| Hydra admin недоступен на стенде | KACHO_HYDRA_ADMIN_URL должен быть valid в helm values; smoke в Task 7.2 проверяет. |
| Acceptance-author не справится с 35-40 GWT в одном файле | acceptance-reviewer round-trip 3+ итерации — заложено. Если слишком сложно — декомпозировать на 3-5 acceptance файлов post-hoc. |
| User invited в 2 Accounts одновременно (race) | UNIQUE constraint на (external_id, account_id) — second INSERT → idempotent path в bootstrap_worker. Integration test scenarios. |
| Hydra OAuth2 token validation in api-gateway не работает offline | Hydra JWKS cached 5 min; smoke в Task 7.2. Если совсем не работает — fallback на Hydra `/oauth2/introspect` (online check, slower). |
| List filtering p95 не дотягивает SLA | Phase 9.2 k6 load test обнаружит до production; mitigation: increase OpenFGA replicas (HPA уже есть в deploy?), tune Consistency mode (MINIMIZE_LATENCY default). |

---

**Конец плана**. Implementation начинается ПОСЛЕ APPROVED acceptance doc (Phase 1 gate, запрет CLAUDE.md #1).
