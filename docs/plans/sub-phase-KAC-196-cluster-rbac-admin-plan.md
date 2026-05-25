# KAC-196 Cluster RBAC Admin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** UI-facing control-plane mechanism to grant/revoke `system_admin@cluster:cluster_kacho_root` FGA tuples + persistent audit trail via DB `cluster_admin_grants` rows.

**Architecture:** New `InternalClusterService` (kacho-iam:9091) registered on api-gateway internal mux at `/iam/v1/internal/cluster/admins`. Single mutation flow: handler validates user existence + gate (`admin@cluster` via `InternalIAMService.Check`) → INSERT `cluster_admin_grants` row + INSERT `fga_outbox` (`system_admin@cluster_kacho_root for user:<id>`) in single TX → return Operation. Outbox-drainer in kacho-iam (existing) pushes tuple to OpenFGA. UI page `/system/cluster/admins` consumes `ListAdmins` / `GrantAdmin` / `RevokeAdmin`.

**Tech Stack:** Go 1.23, gRPC, sqlc + pgx, OpenFGA, React + Vite + AntD 5, testcontainers-go, Newman, Playwright.

**Reference inputs (read before each task)**:
- `kacho-workspace/docs/specs/sub-phase-KAC-196-cluster-rbac-admin-acceptance.md` — 17 GWT scenarios, 13 Decisions, DoD. **Source of truth for behaviour.**
- `kacho-workspace/obsidian/kacho/rpc/iam-internal-cluster-service.md` — planned RPCs.
- `kacho-workspace/obsidian/kacho/resources/iam-cluster-admin-grant.md` — DB schema reference.
- `kacho-workspace/project/kacho-iam/internal/migrations/0011_kac127_identity_extension.sql` lines 92-164 — existing tables (no new migration).
- `kacho-workspace/project/kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga:89` — `define admin: system_admin or emergency_admin`.
- `kacho-workspace/project/kacho-api-gateway/internal/middleware/embed/permission_catalog.json` lines 560-588 — `compute.zones.admin` entries as catalog shape reference.
- `kacho-workspace/project/kacho-iam/internal/apps/kacho/api/internal_iam/handler.go` — handler pattern.
- `kacho-workspace/project/kacho-iam/internal/repo/kacho/pg/fga_outbox_emitter.go` — `EmitWriteTx` / `EmitDeleteTx` adapter.
- `kacho-workspace/project/kacho-iam/internal/repo/kacho/pg/access_binding_fga_outbox_integration_test.go` — outbox-in-tx integration-test pattern.
- `kacho-workspace/project/kacho-iam/cmd/kacho-iam/main.go` — wiring template (line ~993 `iamv1.RegisterInternalIAMServiceServer`, line ~669 internal-mux block).
- `kacho-workspace/project/kacho-api-gateway/internal/restmux/mux.go` lines 266-451 — `iamInternalAddr` block.
- `kacho-workspace/project/kacho-ui/src/lib/service-modules.tsx` — `/system/*` nav reference (`to: () => "/system/regions"` etc.).
- `kacho-workspace/CLAUDE.md` — workspace rules, naming, запреты #6, #9, #10, #11, #12.

**Branch convention**: each repo gets branch `KAC-196` (workspace rule). PR titles `[KAC-196] <short>`.

---

## Task 0 — Pre-flight (read & confirm)

Estimated: 15 min.

- [ ] **0.1** Read full acceptance doc end-to-end (845 lines). Note the 17 GWT scenarios (`KAC-196-00 … KAC-196-17`), 13 Decisions (D-1 … D-13), §5 DoD, §6 scenarios, §7 risks.
- [ ] **0.2** Open `kacho-iam/internal/migrations/0011_kac127_identity_extension.sql` lines 92-164 — confirm `cluster_admin_grants` columns + `cluster_admin_grants_subject_unique` partial UNIQUE + FK to `clusters(id) RESTRICT` + `granted_until > granted_at` CHECK. **No new migration this ticket** (acceptance §5.2, workspace запрет #11).
- [ ] **0.3** Open `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` line ~89 — confirm `define admin: system_admin or emergency_admin`. This is the basis for D-11 (gate = `admin`, not raw `system_admin`).
- [ ] **0.4** Open `kacho-iam/internal/apps/kacho/api/internal_iam/handler.go` — skim handler shape (constructor, port-iface fields, RPC methods are thin pass-through to use-cases).
- [ ] **0.5** Open `kacho-iam/internal/repo/kacho/pg/fga_outbox_emitter.go` lines 23-41 — note exported API: `FGAOutboxEmitter{}.EmitWriteTx(ctx, tx, []service.FGATuple) error` and symmetric `EmitDeleteTx`. Both take `service.Tx` opaque handle (recovered via `txAsPgx`). **Reuse this — do not re-implement.**
- [ ] **0.6** Open `kacho-iam/internal/repo/kacho/pg/access_binding_fga_outbox_integration_test.go` — integration-test template for outbox-in-tx contract (rollback semantics, tuple-emit assertion via `SELECT event_type FROM kacho_iam.fga_outbox WHERE event_type = $1`).
- [ ] **0.7** Open `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` lines 560-588 — confirm catalog entry shape:
  ```json
  {
    "fqn": "kacho.cloud.compute.v1.InternalZoneService/Create",
    "permission": "compute.zones.admin",
    "required_relation": "system_admin",
    "scope_extractor": { "object_type": "cluster", "from_request_field": "*" },
    "required_acr_min": "3"
  }
  ```
  For KAC-196 we use `"required_relation": "admin"` (D-11 computed alias), `"required_acr_min": "3"`.
- [ ] **0.8** Open `kacho-api-gateway/internal/restmux/mux.go` lines 266-451 — note `iamInternalAddr` block (line 447). New `RegisterInternalClusterServiceHandlerFromEndpoint` will sit there.
- [ ] **0.9** Open `kacho-ui/src/lib/service-modules.tsx` — note existing `/system/regions`, `/system/search` shape (`to: () => "/system/regions"`, `matches: (p) => p.startsWith("/system/regions")`).
- [ ] **0.10** **Acceptance D-13 row** — add to acceptance §0.3 Decisions table (zero-cost edit). Use `Edit` tool on `sub-phase-KAC-196-cluster-rbac-admin-acceptance.md`. Append after D-12:
  ```
  | **D-13** | **OpenFGA outage = fail-fast Operation** (terminal `done=true, error.code=Unavailable` after drainer retry-exhaustion ≤30s); DB row in `cluster_admin_grants` стands (TX независим от FGA); tuple eventually present after FGA recovery; Operation **не resume**'ится. | Async-divergence acceptable for admin-tooling; alternative (2-phase commit с rollback DB row при FGA-failure) — overkill, cross-system stronger consistency не нужен. Documented in scenario KAC-196-17. UI должна refresh `ListAdmins` после Operation error чтобы увидеть real state. |
  ```
- [ ] **0.11** Confirm openfga-Postgres is reachable on dev stand (`cd project/kacho-deploy && make dev-up` if not), and `kacho-iam` env has `KACHO_IAM_OPENFGA_STORE_ID` populated — otherwise FGAOutboxDrainer logs the "NOT started" warning (see main.go:476) and tuples queue silently.

**Exit criteria**: you can answer "what does scenario KAC-196-08b test?" and "where is the partial UNIQUE that backs the idempotent grant?" without re-reading.

---

## Task 1 — kacho-proto: define `InternalClusterService`

Estimated: 60 min. Branch: `KAC-196`. PR target: `PRO-Robotech/kacho-proto`.

**Files**:
- `project/kacho-proto/proto/kacho/cloud/iam/v1/internal_cluster_service.proto` (NEW)
- `project/kacho-proto/gen/go/kacho/cloud/iam/v1/internal_cluster_service.pb.go` (regen)
- `project/kacho-proto/gen/go/kacho/cloud/iam/v1/internal_cluster_service_grpc.pb.go` (regen)
- `project/kacho-proto/gen/go/kacho/cloud/iam/v1/internal_cluster_service.pb.gw.go` (regen — grpc-gateway)

### 1.1 RED — buf lint baseline

- [ ] `cd project/kacho-proto && buf lint` → expect zero output (green baseline before new file).
- [ ] Plan the messages now (write nothing yet). 4 RPCs + 11 messages:
  - Messages: `Cluster`, `ClusterAdminEntry`, `ClusterAdminGrant`, `GetClusterRequest`, `GrantClusterAdminRequest`, `GrantClusterAdminMetadata`, `RevokeClusterAdminRequest`, `RevokeClusterAdminMetadata`, `ListClusterAdminsRequest`, `ListClusterAdminsResponse`, `SubjectType` (enum).
  - `SubjectType` enum: `SUBJECT_TYPE_UNSPECIFIED = 0;` `SUBJECT_TYPE_USER = 1;` `SUBJECT_TYPE_SERVICE_ACCOUNT = 2;` (only `USER` accepted by handler this ticket — D-2; enum is forward-compat).

### 1.2 GREEN — write proto file

- [ ] Create `project/kacho-proto/proto/kacho/cloud/iam/v1/internal_cluster_service.proto`:
  - Package `kacho.cloud.iam.v1`. Go-package option matches sibling files.
  - Imports: `google/api/annotations.proto`, `google/protobuf/timestamp.proto`, `kacho/cloud/operation/v1/operation.proto`.
  - Service skeleton (signatures — fill body per acceptance §4.1-§4.4):
    ```protobuf
    service InternalClusterService {
      rpc Get(GetClusterRequest) returns (Cluster) {
        option (google.api.http) = { get: "/iam/v1/internal/cluster" };
      }
      rpc GrantAdmin(GrantClusterAdminRequest) returns (kacho.cloud.operation.v1.Operation) {
        option (google.api.http) = {
          post: "/iam/v1/internal/cluster/admins"
          body: "*"
        };
      }
      rpc RevokeAdmin(RevokeClusterAdminRequest) returns (kacho.cloud.operation.v1.Operation) {
        option (google.api.http) = {
          delete: "/iam/v1/internal/cluster/admins/{subject_id}"
        };
      }
      rpc ListAdmins(ListClusterAdminsRequest) returns (ListClusterAdminsResponse) {
        option (google.api.http) = { get: "/iam/v1/internal/cluster/admins" };
      }
    }
    ```
  - `ClusterAdminEntry` fields per acceptance §4.4: `cluster_admin_grant_id`, `subject_type` (SubjectType enum), `subject_id`, `subject_email`, `subject_display_name`, `granted_by_user_id`, `granted_by_email`, `granted_at` (Timestamp).
  - `GrantClusterAdminMetadata` / `RevokeClusterAdminMetadata`: `{cluster_admin_grant_id, subject_id}` (per acceptance §4.2, §4.3).
- [ ] Add file comment header: `// InternalClusterService — KAC-196. Internal-only (workspace §6). Managed by api-gateway internal mux.`

### 1.3 GREEN — lint + breaking + generate

- [ ] `cd project/kacho-proto && buf lint` → expect zero output.
- [ ] `cd project/kacho-proto && buf breaking --against '.git#branch=main'` → expect zero (new file is additive).
- [ ] `cd project/kacho-proto && buf generate` → generates `gen/go/kacho/cloud/iam/v1/internal_cluster_service.pb.go`, `_grpc.pb.go`, `.pb.gw.go`. Verify all three exist:
  ```bash
  ls project/kacho-proto/gen/go/kacho/cloud/iam/v1/internal_cluster_service*
  ```
- [ ] `cd project/kacho-proto && go build ./...` → expect green.

### 1.4 Commit + PR

- [ ] `cd project/kacho-proto && git checkout -b KAC-196`
- [ ] `git add proto/kacho/cloud/iam/v1/internal_cluster_service.proto gen/go/kacho/cloud/iam/v1/internal_cluster_service*`
- [ ] Commit message: `feat(KAC-196): add InternalClusterService proto (4 RPCs + Operation envelope)`. Body: list the 4 RPCs + REST paths + `Closes KAC-196 (partial — proto only)`.
- [ ] `git push -u origin KAC-196 && gh pr create --title "[KAC-196] kacho-proto: InternalClusterService" --body "<body referencing acceptance §4.1-§4.4>"`.
- [ ] Post PR URL as comment to YouTrack KAC-196.

**Exit criteria**: PR open with green `buf lint` + `buf breaking` + `go build ./...`. Downstream repos (kacho-iam, kacho-api-gateway) will `replace ../kacho-proto` (already pinned via go.work) — no version bump needed for dev.

---

## Task 2 — kacho-iam: domain + repo layer (sqlc + pgx)

Estimated: 4 hours. Branch: `KAC-196`. PR target: `PRO-Robotech/kacho-iam` (single PR for backend; UI separate).

**Files (NEW)**:
- `project/kacho-iam/internal/domain/cluster_admin_grant.go`
- `project/kacho-iam/internal/repo/kacho/pg/cluster_admin_grant_writer.go`
- `project/kacho-iam/internal/repo/kacho/pg/cluster_admin_grant_reader.go`
- `project/kacho-iam/internal/repo/kacho/pg/cluster_reader.go`
- `project/kacho-iam/internal/repo/kacho/pg/cluster_admin_grant_integration_test.go`
- `project/kacho-iam/internal/repo/kacho/pg/cluster_reader_integration_test.go`

### 2.1 RED — domain newtype + Validate

- [ ] Create `internal/domain/cluster_admin_grant.go`. Mirror `evgeniy §4` (self-validating newtype). Skeleton:
  ```go
  package domain

  import (
      "fmt"
      "regexp"
      "time"
  )

  var subjectIDPattern = regexp.MustCompile(`^usr_[0-9a-hjkmnp-tv-z]{17}$`)

  type SubjectID string
  func (s SubjectID) Validate() error {
      if !subjectIDPattern.MatchString(string(s)) {
          return fmt.Errorf("subject_id %q is invalid (must match ^usr_[crockford]{17}$)", string(s))
      }
      return nil
  }

  type ClusterAdminGrant struct {
      ID, ClusterID, SubjectType string
      SubjectID                  SubjectID
      GrantedBy                  string
      GrantedAt                  time.Time
      GrantedUntil               *time.Time
  }
  func (g *ClusterAdminGrant) IsActive() bool { return g.GrantedUntil == nil }
  func (g *ClusterAdminGrant) Validate() error { /* subject_type, granted_by length, SubjectID.Validate() */ }
  ```
- [ ] Write `internal/domain/cluster_admin_grant_test.go` — unit-test the Validate paths (good `usr_xxx`, bad regex, empty granted_by, etc.). Run: `cd project/kacho-iam && go test ./internal/domain/...` → expect FAIL (file missing); now compile after writing → expect GREEN.

### 2.2 RED — integration tests for repo (write first, run, see compile-fail)

- [ ] Create `internal/repo/kacho/pg/cluster_admin_grant_integration_test.go` with the 11 tests from acceptance §5.5 first paragraph:
  - `TestGrant_Idempotent`
  - `TestGrant_ConcurrentSameSubject` (10 goroutines)
  - `TestRevoke_LastAdmin_Sequential`
  - `TestRevoke_ConcurrentLastAdmin` (KAC-196-08b race; setup count=2, two goroutines revoking each other)
  - `TestRevoke_Self` (subject_id == principal_id)
  - `TestRevoke_NotAdmin` (no row at all → ErrNotFound)
  - `TestRevoke_AlreadyRevoked` (history row with `granted_until IS NOT NULL` → ErrNotFound, D-12)
  - `TestGrantRevoke_ConcurrentSameSubject` (invariants per acceptance §5.5)
  - `TestList_JoinsUsers` (denormalised email/display_name)
  - `TestGet_Singleton` (cluster_kacho_root row from migration 0011 seed)
  - `TestGrant_OpenFGAOutage` (stops openfga testcontainer mid-test, asserts Operation terminal + DB row persists)
- [ ] Use existing helpers from `access_binding_fga_outbox_integration_test.go` for the testcontainer setup (Postgres + migrations + openfga sidecar where needed). Same imports.
- [ ] Each test asserts both DB-side state (`SELECT count(*) FROM kacho_iam.cluster_admin_grants WHERE granted_until IS NULL`) and outbox-side state (`SELECT event_type, payload FROM kacho_iam.fga_outbox`).
- [ ] Run: `cd project/kacho-iam && go test ./internal/repo/kacho/pg/ -run 'TestGrant|TestRevoke|TestList|TestGet_Singleton' -count=1` → expect **compile errors** (Writer/Reader types missing). **This is the RED-evidence — capture the output for the PR description.**

### 2.3 GREEN — implement Writer with atomic SQL

- [ ] Create `internal/repo/kacho/pg/cluster_admin_grant_writer.go`. Constructor signature `NewClusterAdminGrantWriter(pool *pgxpool.Pool, ids ids.Generator) *ClusterAdminGrantWriter`. Methods:
  - `Grant(ctx, tx service.Tx, subject domain.SubjectID, grantedBy string) (domain.ClusterAdminGrant, bool /*created*/, error)`:
    ```sql
    INSERT INTO kacho_iam.cluster_admin_grants
        (id, cluster_id, subject_type, subject_id, granted_by, granted_at, granted_until)
    VALUES ($1, 'cluster_kacho_root', 'user', $2, $3, now(), NULL)
    ON CONFLICT (subject_type, subject_id)
        WHERE granted_until IS NULL
        DO NOTHING
    RETURNING id, cluster_id, subject_type, subject_id, granted_by, granted_at, granted_until;
    ```
    If 0 rows (conflict) → SELECT existing active row → return `(grant, created=false, nil)`. Else `(grant, true, nil)`. D-4 idempotency satisfied here.
  - `Revoke(ctx, tx service.Tx, subject domain.SubjectID, principalID string) (domain.ClusterAdminGrant, error)`:
    ```sql
    UPDATE kacho_iam.cluster_admin_grants
       SET granted_until = now()
     WHERE subject_type = 'user'
       AND subject_id   = $1
       AND granted_until IS NULL
       AND subject_id  != $2  -- D-5 self-revoke guard
       AND (SELECT count(*) FROM kacho_iam.cluster_admin_grants WHERE granted_until IS NULL) > 1  -- D-6
    RETURNING id, cluster_id, subject_type, subject_id, granted_by, granted_at, granted_until;
    ```
    If 0 rows → run **diagnostic SELECTs** to determine which guard fired:
    1. Is `subject_id == principalID`? → `errs.ErrSelfRevoke` (FailedPrecondition).
    2. Are there active rows for this subject? If none → `errs.ErrNotFound` (D-12).
    3. Is `count(*) WHERE granted_until IS NULL == 1`? → `errs.ErrLastAdmin` (FailedPrecondition).
    4. Else (shouldn't happen) → `errs.ErrInternal`.
- [ ] Add `errs` sentinels (in `internal/errors/sentinels.go` or service-level file): `ErrSelfRevoke`, `ErrLastAdmin` (reuse `ErrNotFound`, `ErrFailedPrecondition` already exist).

### 2.4 GREEN — implement Reader + cluster Reader

- [ ] Create `internal/repo/kacho/pg/cluster_admin_grant_reader.go`. Methods:
  - `ListActive(ctx, tx service.Tx) ([]ClusterAdminEntry, error)` — single SQL:
    ```sql
    SELECT g.id, g.subject_type, g.subject_id,
           u_subj.email, u_subj.display_name,
           g.granted_by,
           CASE WHEN g.granted_by = 'bootstrap' THEN ''
                ELSE u_by.email END AS granted_by_email,
           g.granted_at
      FROM kacho_iam.cluster_admin_grants g
      LEFT JOIN kacho_iam.users u_subj ON u_subj.id = g.subject_id
      LEFT JOIN kacho_iam.users u_by   ON u_by.id   = g.granted_by
     WHERE g.granted_until IS NULL
     ORDER BY g.granted_at ASC;
    ```
    Return `[]ClusterAdminEntry` (plain struct in same file or `domain/`).
  - `GetBySubject(ctx, tx service.Tx, subject domain.SubjectID) (domain.ClusterAdminGrant, error)` — used by diagnostic-SELECTs in Writer.Revoke.
- [ ] Create `internal/repo/kacho/pg/cluster_reader.go`. Single method `Get(ctx, tx) (domain.Cluster, error)` — `SELECT id, name, description, created_at FROM kacho_iam.clusters WHERE id='cluster_kacho_root'`. Add `domain.Cluster` newtype (id, name, description, created_at).

### 2.5 GREEN — run integration tests

- [ ] `cd project/kacho-iam && go test ./internal/repo/kacho/pg/ -run 'TestGrant|TestRevoke|TestList|TestGet_Singleton' -count=1 -timeout=10m` → expect **all 11 green**. If `TestGrant_OpenFGAOutage` is flaky, mark with `testing.Short()` skip and note as follow-up in PR description **only if** acceptance §5.5 explicitly allows (it doesn't — this test is required, get it green).
- [ ] Capture pass-log for PR.

### 2.6 Commit (split: domain, repo, tests in single squash-able series)

- [ ] `git add internal/domain/cluster_admin_grant.go internal/domain/cluster_admin_grant_test.go && git commit -m "feat(KAC-196): domain.ClusterAdminGrant + SubjectID newtype"`
- [ ] `git add internal/repo/kacho/pg/cluster_admin_grant_writer.go internal/repo/kacho/pg/cluster_admin_grant_reader.go internal/repo/kacho/pg/cluster_reader.go internal/errors/... && git commit -m "feat(KAC-196): pg writer/reader for cluster_admin_grants (atomic CAS guards)"`
- [ ] `git add internal/repo/kacho/pg/cluster_admin_grant_integration_test.go internal/repo/kacho/pg/cluster_reader_integration_test.go && git commit -m "test(KAC-196): integration tests for cluster admin grants (concurrent races)"`

**Do not push yet** — combine with Task 3 in a single iam PR.

**Exit criteria**: `make test` green for new tests; existing tests still green; no schema changes (acceptance §5.2).

---

## Task 3 — kacho-iam: service + handler + main wiring

Estimated: 3 hours. Same branch `KAC-196` in kacho-iam.

**Files (NEW)**:
- `project/kacho-iam/internal/apps/kacho/api/cluster/get.go`
- `project/kacho-iam/internal/apps/kacho/api/cluster/grant_admin.go`
- `project/kacho-iam/internal/apps/kacho/api/cluster/revoke_admin.go`
- `project/kacho-iam/internal/apps/kacho/api/cluster/list_admins.go`
- `project/kacho-iam/internal/apps/kacho/api/cluster/ports.go` (port-interfaces)
- `project/kacho-iam/internal/apps/kacho/api/cluster/handler.go` (thin gRPC handler)
- `project/kacho-iam/internal/apps/kacho/api/cluster/handler_integration_test.go`
- `project/kacho-iam/internal/dto/toproto/cluster.go` (DTO mapping)

**Files (MODIFY)**:
- `project/kacho-iam/cmd/kacho-iam/main.go` — register new server on internal :9091.

### 3.1 RED — handler integration test first

- [ ] Create `internal/apps/kacho/api/cluster/handler_integration_test.go`. Use existing `internal_iam/handler_test.go` as template. Tests covering scenarios:
  - `TestCluster_Get_OK` (KAC-196-00) + `TestCluster_Get_403_Ordinary`
  - `TestCluster_GrantAdmin_HappyPath` (KAC-196-01) — assert Operation envelope, metadata, DB row, outbox row, audit row.
  - `TestCluster_GrantAdmin_403_Ordinary` (KAC-196-02)
  - `TestCluster_GrantAdmin_Idempotent` (KAC-196-03)
  - `TestCluster_GrantAdmin_InvalidUser` (KAC-196-04)
  - `TestCluster_GrantAdmin_InvalidSubjectType` (KAC-196-05) — SERVICE_ACCOUNT rejected
  - `TestCluster_RevokeAdmin_HappyPath` (KAC-196-06)
  - `TestCluster_RevokeAdmin_Self_FP` (KAC-196-07) — message `"cannot revoke own cluster admin grant"`
  - `TestCluster_RevokeAdmin_LastAdmin_FP` (KAC-196-08a)
  - `TestCluster_RevokeAdmin_NotAdmin_NotFound` (KAC-196-09) — message `"User %s is not an active cluster admin"`
  - `TestCluster_RevokeAdmin_AlreadyRevoked_NotFound` (KAC-196-09b)
  - `TestCluster_ListAdmins_OK` (KAC-196-10) — assert join populated `subject_email`, ordering by `granted_at ASC`
  - `TestCluster_EmergencyAdmin_GatePass` (KAC-196-12) — fixture inserts `cluster_break_glass_grants` row in ACTIVE + outbox emergency_admin tuple; assert Grant proceeds.
  - `TestCluster_Operation_PrincipalPropagated` (KAC-196-16) — assert `Operation.created_by == "usr_s00000000000000000"` (real principal, not "anonymous").
- [ ] Run → expect compile errors (no `cluster` package). Capture log for PR.

### 3.2 GREEN — define port-interfaces

- [ ] Create `internal/apps/kacho/api/cluster/ports.go`:
  ```go
  package cluster

  type ClusterReader interface {
      Get(ctx context.Context, tx service.Tx) (domain.Cluster, error)
  }
  type GrantReader interface {
      ListActive(ctx context.Context, tx service.Tx) ([]ClusterAdminEntry, error)
      GetBySubject(ctx context.Context, tx service.Tx, s domain.SubjectID) (domain.ClusterAdminGrant, error)
  }
  type GrantWriter interface {
      Grant(ctx context.Context, tx service.Tx, s domain.SubjectID, grantedBy string) (domain.ClusterAdminGrant, bool, error)
      Revoke(ctx context.Context, tx service.Tx, s domain.SubjectID, principalID string) (domain.ClusterAdminGrant, error)
  }
  type UserLookup interface {
      Exists(ctx context.Context, tx service.Tx, id string) (bool, error)
  }
  type FGAOutboxEmitter interface {
      EmitWriteTx(ctx context.Context, tx service.Tx, tuples []service.FGATuple) error
      EmitDeleteTx(ctx context.Context, tx service.Tx, tuples []service.FGATuple) error
  }
  type AuditOutboxEmitter interface {
      EmitInTx(ctx context.Context, tx service.Tx, event string, payload map[string]any) error
  }
  type Transactor interface {
      WithinTx(ctx context.Context, fn func(tx service.Tx) error) error
  }
  type OperationsWriter interface {
      Enqueue(ctx context.Context, tx service.Tx, kind string, principal string, metadata proto.Message) (string /*op_id*/, error)
  }
  ```
  Reuse existing types where they exist — e.g. `service.Tx`, `service.FGATuple`, `service.Transactor` are already defined in service-layer (see `internal_iam/handler.go`). Adjust paths as needed; do NOT introduce new packages just for cluster.

### 3.3 GREEN — implement 4 use-cases

- [ ] `get.go` — single `GetCluster(ctx) (domain.Cluster, error)` — reader-TX, just SELECT.
- [ ] `grant_admin.go`:
  ```go
  func (uc *GrantAdminUseCase) Run(ctx, subjectType SubjectType, subjectID SubjectID) (*operation.Operation, error) {
      if subjectType != SubjectType_USER { return InvalidArgument("Illegal argument subject_type: only 'user' supported in this version") }
      if err := subjectID.Validate(); err != nil { return InvalidArgument("Illegal argument subject_id") }
      principalID := principal.FromCtx(ctx)
      var op *operation.Operation
      err := tx.WithinTx(ctx, func(tx) error {
          exists, _ := userLookup.Exists(ctx, tx, string(subjectID))
          if !exists { return InvalidArgument(fmt.Sprintf("User %s not found", subjectID)) }
          grant, _, err := writer.Grant(ctx, tx, subjectID, principalID)
          if err != nil { return err }
          if err := fgaOutbox.EmitWriteTx(ctx, tx, []service.FGATuple{{
              Object: "cluster:cluster_kacho_root", Relation: "system_admin", User: "user:"+string(subjectID)}}); err != nil { return err }
          if err := auditOutbox.EmitInTx(ctx, tx, "cluster_admin_granted", map[string]any{
              "grant_id": grant.ID, "subject_id": string(subjectID), "principal_id": principalID}); err != nil { return err }
          opID, err := operations.Enqueue(ctx, tx, "cluster.grant_admin", principalID, &iamv1.GrantClusterAdminMetadata{
              ClusterAdminGrantId: grant.ID, SubjectId: string(subjectID)})
          if err != nil { return err }
          op = &operation.Operation{Id: opID, Done: false, Metadata: anypb(metadata)}
          return nil
      })
      return op, err
  }
  ```
- [ ] `revoke_admin.go` — analogous, with `EmitDeleteTx` for outbox and `"cluster_admin_revoked"` audit event; map repo sentinel errors → gRPC codes (`ErrSelfRevoke` → FailedPrecondition `"cannot revoke own cluster admin grant"`, `ErrLastAdmin` → FailedPrecondition `"cannot revoke last active cluster admin"`, `ErrNotFound` → NotFound `"User %s is not an active cluster admin"`).
- [ ] `list_admins.go` — reader-TX `ListActive`, map to proto `ListClusterAdminsResponse{admins[]}`.

### 3.4 GREEN — handler.go (thin transport)

- [ ] `handler.go`: struct `Handler` holding 4 use-cases. Methods just `parseReq → uc.Run → buildResp`. No business logic. Pattern from `internal_iam/handler.go`.
- [ ] `dto/toproto/cluster.go` — `ToProtoClusterAdminEntry(domain → iamv1.ClusterAdminEntry)`.

### 3.5 GREEN — wire in main.go

- [ ] Edit `cmd/kacho-iam/main.go`. Pattern reference: line ~993 `iamv1.RegisterInternalIAMServiceServer(srv, svcs.internalIAMHandler)`. Add **before** that:
  ```go
  clusterHandler := cluster.NewHandler(cluster.Deps{
      ClusterReader:      pg.NewClusterReader(pool),
      GrantReader:        pg.NewClusterAdminGrantReader(pool),
      GrantWriter:        pg.NewClusterAdminGrantWriter(pool, idsGen),
      UserLookup:         pg.NewUserReader(pool),
      FGAOutbox:          pg.NewFGAOutboxEmitter(pool),
      AuditOutbox:        svcs.auditOutbox,
      Transactor:         svcs.txr,
      Operations:         svcs.operationsWriter,
  })
  iamv1.RegisterInternalClusterServiceServer(srv, clusterHandler)
  ```
- [ ] Register on **internal-only** listener (the same `srv` instance bound to `:9091`, see line ~669 block). Do NOT register on the external listener.
- [ ] `cd project/kacho-iam && go build ./...` → expect green.

### 3.6 GREEN — re-run handler tests

- [ ] `cd project/kacho-iam && go test ./internal/apps/kacho/api/cluster/... -count=1 -timeout=5m` → expect all 14 tests green. If `TestCluster_Operation_PrincipalPropagated` fails because main.go does not mount `UnaryPrincipalExtract` on the internal listener — **this is a blocker** (acceptance scenario KAC-196-16). Fix by adding the interceptor to the internal-server chain in main.go (mirror what kacho-compute did in KAC-178 §2).

### 3.7 Commit + push iam PR

- [ ] `git add internal/apps/kacho/api/cluster/ internal/dto/toproto/cluster.go cmd/kacho-iam/main.go`
- [ ] Commit: `feat(KAC-196): InternalClusterService handler + use-cases (Grant/Revoke/List/Get)`
- [ ] `git push -u origin KAC-196`
- [ ] **Temporarily pin kacho-proto branch** in this PR's CI workflow if `kacho-proto#KAC-196` is not yet merged. Edit `.github/workflows/ci.yaml`: change `ref: main` → `ref: KAC-196` for kacho-proto checkout step. Revert after kacho-proto PR merges.
- [ ] `gh pr create --title "[KAC-196] kacho-iam: InternalClusterService (grant/revoke admin)" --body "<acceptance §5.2 DoD ticked; RED→GREEN log from Tasks 2.2 + 3.1; Closes KAC-196 (partial — iam only)>"`.
- [ ] Post PR URL to YouTrack KAC-196.

**Exit criteria**: PR green, integration tests +14 handler-tests green, no new migrations, all 13 Decisions visible in code review.

---

## Task 4 — kacho-api-gateway: catalog + restmux registration

Estimated: 90 min. Branch: `KAC-196`. PR target: `PRO-Robotech/kacho-api-gateway`.

**Files (MODIFY)**:
- `project/kacho-api-gateway/internal/middleware/embed/permission_catalog.json` — add 4 entries.
- `project/kacho-api-gateway/internal/restmux/mux.go` — register InternalClusterService on internal mux only.
- `project/kacho-api-gateway/tests/newman/cases/cluster_admin.py` (NEW)
- `project/kacho-api-gateway/tests/newman/cases/cluster_admin.postman_collection.json` (generated)
- `project/kacho-api-gateway/internal/restmux/mux_test.go` — assert route NOT registered on external mux.

### 4.1 RED — newman cases first

- [ ] Create `tests/newman/cases/cluster_admin.py` with 13 cases per acceptance §5.5 second list:
  - `CLUSTER-ADMIN-GET-OK`, `CLUSTER-ADMIN-GET-403-ORDINARY`
  - `CLUSTER-ADMIN-GRANT-OK`, `CLUSTER-ADMIN-GRANT-403-ORDINARY`, `CLUSTER-ADMIN-GRANT-400-INVALID-USER`, `CLUSTER-ADMIN-GRANT-OK-IDEMPOTENT`
  - `CLUSTER-ADMIN-REVOKE-OK`, `CLUSTER-ADMIN-REVOKE-403-SELF`, `CLUSTER-ADMIN-REVOKE-403-LAST`, `CLUSTER-ADMIN-REVOKE-404-NOT-ADMIN`
  - `CLUSTER-ADMIN-LIST-OK`, `CLUSTER-ADMIN-LIST-403-ORDINARY`
  - `CLUSTER-ADMIN-INTERNAL-NOT-ON-EXTERNAL-TLS`
- [ ] Each case uses `pm.expect(...).to.eql(...)` (exact match per acceptance §4.5 Newman note) for error messages. Pre-request scripts set Authorization header (re-use existing `auth_helper.py` pattern from `tests/newman/cases/`).
- [ ] `cd project/kacho-api-gateway/tests/newman && python gen.py` → generates `*.postman_collection.json`.
- [ ] Run against current `main` stand: `newman run cases/cluster_admin.postman_collection.json --env-var base_url=http://localhost:8080 --env-var token_admin=$TKN_S --env-var token_ordinary=$TKN_U3`. Expect **13 FAIL** (routes return 404 — endpoints not registered). Capture log.

### 4.2 GREEN — catalog entries (4 entries)

- [ ] Edit `permission_catalog.json`. Insert 4 entries (sorted alphabetically by `fqn`; find correct insertion point near other `kacho.cloud.iam.v1.*` entries):
  ```json
  {
    "fqn": "kacho.cloud.iam.v1.InternalClusterService/Get",
    "permission": "iam.cluster.get",
    "required_relation": "admin",
    "scope_extractor": { "object_type": "cluster", "from_request_field": "*" },
    "required_acr_min": "3"
  },
  {
    "fqn": "kacho.cloud.iam.v1.InternalClusterService/GrantAdmin",
    "permission": "iam.cluster.admin.grant",
    "required_relation": "admin",
    "scope_extractor": { "object_type": "cluster", "from_request_field": "*" },
    "required_acr_min": "3"
  },
  {
    "fqn": "kacho.cloud.iam.v1.InternalClusterService/RevokeAdmin",
    "permission": "iam.cluster.admin.revoke",
    "required_relation": "admin",
    "scope_extractor": { "object_type": "cluster", "from_request_field": "*" },
    "required_acr_min": "3"
  },
  {
    "fqn": "kacho.cloud.iam.v1.InternalClusterService/ListAdmins",
    "permission": "iam.cluster.admin.list",
    "required_relation": "admin",
    "scope_extractor": { "object_type": "cluster", "from_request_field": "*" },
    "required_acr_min": "3"
  }
  ```
- [ ] **Important — D-11**: `required_relation` is `admin` (computed alias `system_admin OR emergency_admin`), NOT `system_admin`. Reviewer must confirm.
- [ ] `cd project/kacho-api-gateway && make sync-permission-catalog` (if Makefile target exists; otherwise `go generate ./...`) → expect green.

### 4.3 GREEN — restmux registration (internal-only)

- [ ] Edit `internal/restmux/mux.go`. Find `iamInternalAddr` block (line ~447). Add **after** existing two `RegisterInternal*ServiceHandlerFromEndpoint` calls:
  ```go
  if err := iampb.RegisterInternalClusterServiceHandlerFromEndpoint(ctx, mux, iamInternalAddr, opts); err != nil {
      return fmt.Errorf("register InternalClusterService: %w", err)
  }
  ```
- [ ] **Do NOT add to public `gw.go`** (workspace запрет #6). Verify by `grep -n "InternalClusterService" project/kacho-api-gateway/cmd/kacho-api-gateway/gw.go` → expect zero hits.
- [ ] Add `mux_test.go` test `TestPublicMuxDoesNotExposeInternalCluster` — start public gw, request `POST /iam/v1/internal/cluster/admins`, assert 404.

### 4.4 GREEN — re-run newman

- [ ] Bump api-gateway image tag, `cd project/kacho-deploy && make reload-svc SVC=api-gateway` (or `helm upgrade kacho-umbrella ./helm/umbrella -n kacho --reuse-values --set apiGateway.image.tag=KAC-196-<sha>`).
- [ ] Re-run newman → expect **13 GREEN**. Capture log for PR.

### 4.5 Commit + PR

- [ ] `git checkout -b KAC-196`
- [ ] `git add internal/middleware/embed/permission_catalog.json internal/restmux/mux.go internal/restmux/mux_test.go tests/newman/cases/cluster_admin.py tests/newman/cases/cluster_admin.postman_collection.json`
- [ ] Commit: `feat(KAC-196): register InternalClusterService on internal mux + 4 catalog entries + 13 newman cases`
- [ ] Pin `kacho-proto` and `kacho-iam` to `KAC-196` branches in CI workflow if not yet merged (revert after).
- [ ] `git push -u origin KAC-196 && gh pr create --title "[KAC-196] api-gateway: InternalClusterService internal mux" --body "<acceptance §5.3 + newman RED→GREEN evidence>"`.
- [ ] Post PR URL to YouTrack KAC-196.

**Exit criteria**: PR green, 13 newman cases green on stand, no public route exposure.

---

## Task 5 — kacho-ui: `/system/cluster/admins` page

Estimated: 4 hours. Branch: `KAC-196`. PR target: `PRO-Robotech/kacho-ui`.

**Files (NEW)**:
- `project/kacho-ui/src/pages/system/ClusterAdminsPage.tsx`
- `project/kacho-ui/src/components/system/GrantAdminModal.tsx`
- `project/kacho-ui/src/api/iam/cluster.ts` (typed REST client)
- `project/kacho-ui/tests/e2e/cluster-admins.spec.ts` (Playwright)

**Files (MODIFY)**:
- `project/kacho-ui/src/lib/service-modules.tsx` — add `/system/cluster/admins` nav entry.
- `project/kacho-ui/src/router.tsx` (or `App.tsx`) — add route + lazy import.

### 5.1 RED — Playwright e2e

- [ ] Create `tests/e2e/cluster-admins.spec.ts`:
  - `test('KAC-196-14 admin grants new admin flow', ...)` — login as S (`s@prorobotech.ru`), navigate `/system/cluster/admins`, expect table row with S, click "Добавить admin", search "u2@", select, click "Выдать", expect toast, expect table to contain U2 within 3s.
  - `test('KAC-196-15 ordinary user gets 403 / redirect', ...)` — login as U3, navigate `/system/cluster/admins`, expect 403 page OR redirect to `/dashboard` with toast.
- [ ] Run: `cd project/kacho-ui && npx playwright test cluster-admins.spec.ts` → expect compile-error / page-missing fail. Capture log.

### 5.2 GREEN — REST client

- [ ] Create `src/api/iam/cluster.ts`. Export:
  ```ts
  export type ClusterAdminEntry = {
    clusterAdminGrantId: string;
    subjectType: 'USER';
    subjectId: string;
    subjectEmail: string;
    subjectDisplayName: string;
    grantedByUserId: string;
    grantedByEmail: string;
    grantedAt: string;
  };
  export const listAdmins = (): Promise<ClusterAdminEntry[]> =>
    apiClient.get('/iam/v1/internal/cluster/admins').then(r => r.data.admins);
  export const grantAdmin = (subjectId: string): Promise<Operation> =>
    apiClient.post('/iam/v1/internal/cluster/admins', { subjectType: 'USER', subjectId }).then(r => r.data);
  export const revokeAdmin = (subjectId: string): Promise<Operation> =>
    apiClient.delete(`/iam/v1/internal/cluster/admins/${subjectId}`).then(r => r.data);
  ```
  Re-use existing `apiClient` (axios instance) and `Operation` polling helper.

### 5.3 GREEN — page component

- [ ] Create `src/pages/system/ClusterAdminsPage.tsx`. Use AntD `<Table>`:
  - Columns: Email, Display name, Granted by, Granted at, Actions.
  - Header button "Добавить admin" → opens `GrantAdminModal`.
  - Row action "Отозвать" → AntD `<Popconfirm>` → call `revokeAdmin` + poll Operation.
  - Disable "Отозвать" when: `row.subjectId === currentUserId` (tooltip "Cannot revoke self") OR `admins.length === 1` (tooltip "Cannot revoke last admin").
  - On load: `useQuery(['cluster-admins'], listAdmins)`; on grant/revoke success: `queryClient.invalidateQueries(['cluster-admins'])`.

### 5.4 GREEN — GrantAdminModal

- [ ] Create `src/components/system/GrantAdminModal.tsx`. AntD `<Modal>` + `<AutoComplete>`:
  - Debounced (300ms) input → calls existing `UserService.List` with `filter: 'email contains $q'` (already in `src/api/iam/users.ts`).
  - On select: stores selected `userId`. On "Выдать" click: `grantAdmin(userId)` → poll Operation → toast + close.

### 5.5 GREEN — nav + route

- [ ] Edit `src/lib/service-modules.tsx` — add entry near existing `/system/regions`:
  ```tsx
  {
    id: 'system-cluster-admins',
    label: 'Cluster admins',
    section: 'system',
    to: () => '/system/cluster/admins',
    matches: (p) => p.startsWith('/system/cluster/admins'),
    requirePermission: 'iam.cluster.admin.list',
  },
  ```
- [ ] Edit router (`src/router.tsx` or `src/App.tsx`) — add lazy route `/system/cluster/admins → ClusterAdminsPage`.

### 5.6 GREEN — route-guard

- [ ] In `ClusterAdminsPage.tsx`: if `listAdmins()` returns 403, render `<ForbiddenPage />` (existing component). No client-side permission pre-check needed — server is source of truth.

### 5.7 GREEN — re-run Playwright + visual check

- [ ] `cd project/kacho-ui && npm run build && npm run preview` → open `http://localhost:4173/system/cluster/admins` as S → verify table render manually + click "Добавить admin" → search → grant → see new row.
- [ ] `npx playwright test cluster-admins.spec.ts` → expect both tests green.

### 5.8 Commit + PR

- [ ] `git checkout -b KAC-196 && git add src/api/iam/cluster.ts src/pages/system/ClusterAdminsPage.tsx src/components/system/GrantAdminModal.tsx src/lib/service-modules.tsx src/router.tsx tests/e2e/cluster-admins.spec.ts`
- [ ] Commit: `feat(KAC-196): /system/cluster/admins page (grant/revoke cluster admins)`
- [ ] **Image build/push** per workspace memory: `make image-build PUSH_REGISTRY=docker.io/prorobotech IMAGE_TAG=KAC-196-$(git rev-parse --short HEAD)`. Tag `KAC-196-<sha>`. **NOT** to `ttl.sh`.
- [ ] `git push -u origin KAC-196 && gh pr create --title "[KAC-196] kacho-ui: /system/cluster/admins page" --body "<screenshots + Playwright RED→GREEN evidence>"`.
- [ ] Post PR URL to YouTrack KAC-196.

**Exit criteria**: PR green, both Playwright tests green, manual smoke flow works on dev stand.

---

## Task 6 — vault updates + KAC-196 trail

Estimated: 30 min. Done in `kacho-workspace` repo, branch `KAC-196`.

**Files (MODIFY / CREATE)** — all under `obsidian/kacho/`:
- `rpc/iam-internal-cluster-service.md` — `status: planned → done`, `methods_count: 0 → 4`. Mark Phase 2 rows as done; leave Phase 7 (break-glass) rows as planned.
- `resources/iam-cluster-admin-grant.md` — `status: planned → done`. Add new section `## RPC operations`:
  ```
  - `Get` / `ListAdmins` — sync, see [[../rpc/iam-internal-cluster-service]].
  - `GrantAdmin` / `RevokeAdmin` — async (Operation), single TX insert + fga_outbox + audit_outbox.
  - Atomic guards: idempotent ON CONFLICT (D-4), CAS WHERE count(*)>1 last-admin (D-6), CAS WHERE subject_id != principal self-revoke (D-5).
  ```
- `resources/iam-cluster.md` — `status: planned → done`. Update Lifecycle: "Get RPC доступен (KAC-196)".
- `packages/iam-handler-internal-cluster.md` (NEW, 1-3KB) — front-matter (`repo: kacho-iam`, `layer: handler`), exported types (`cluster.Handler`, `cluster.Deps`), use-cases list, imports.
- `packages/iam-apps-cluster-usecases.md` (NEW, 1-3KB) — 4 use-cases + port-interfaces table.
- `edges/ui-to-apigw-cluster-admins.md` (NEW, 1-3KB) — front-matter (`caller_repo: kacho-ui`, `callee_repo: kacho-api-gateway`, `sync_async: mixed`, `protocol: REST/JSON`), REST contract, sync vs async per RPC, error handling.
- `KAC/KAC-196.md` (NEW, ≤3KB) — full trail per workspace CLAUDE.md format:
  - Status: in-progress → done (update at merge).
  - Type: feature.
  - Repos: kacho-proto, kacho-iam, kacho-api-gateway, kacho-ui, kacho-workspace.
  - PRs: list 5 PR URLs as merged.
  - YT: link.
  - Section "Что и зачем" — 2 abzace summarising acceptance §0.
  - Section "Затронутые сущности vault" — link the 6 vault files updated/created.
  - Section "Acceptance / DoD" — copy 6 checkboxes from acceptance §5.
  - Section "Связанные тикеты" — `[[KAC-178]]` (parent epic), `[[KAC-127]]` (W1.4 propagation), `[[KAC-188]]` (related FGA work if relevant).
  - Tag: `#kac #feature`.
- `KAC/KAC-178.md` — append to "Followups" section a line: `- KAC-196 (cluster admin tooling) — DONE 2026-05-25 — replaces kubectl exec workflow`.
- (Optional) `MEMORY.md` — add link to KAC-196.md if it captures a reusable lesson.

- [ ] Commit + push workspace PR: `docs(KAC-196): vault trail + 3 new packages/edges, mark resources done`.
- [ ] `gh pr create --title "[KAC-196] vault: cluster admin trail + status updates" --body "<acceptance §5.6 ticked>"`.
- [ ] Post URL to YouTrack KAC-196.

**Exit criteria**: vault frontmatter `status: done` reflects reality, KAC-196.md is primary trail node.

---

## Task 7 — Deploy + smoke test

Estimated: 60 min. No code changes — verify only.

**Files**: none. This is a verify-on-stand task.

### 7.1 Deploy

- [ ] Ensure all 4 prior PRs merged in order: **kacho-proto → kacho-iam → kacho-api-gateway → kacho-ui**.
- [ ] Bump tags in `kacho-deploy/helm/umbrella/values.dev.yaml` (or use `--set image.tag=KAC-196-<sha>` for the 3 services: iam, api-gateway, ui). Image registry is `docker.io/prorobotech/<svc>` (workspace memory rule).
- [ ] `cd project/kacho-deploy && helm upgrade kacho-umbrella ./helm/umbrella -n kacho -f helm/umbrella/values.dev.yaml --reuse-values`
- [ ] Wait for rollout: `kubectl -n kacho rollout status deploy/kacho-iam deploy/kacho-api-gateway deploy/kacho-ui --timeout=5m`
- [ ] Check pods healthy: `kubectl -n kacho get pods -l 'app in (kacho-iam,kacho-api-gateway,kacho-ui)'`

### 7.2 Smoke (manual, end-to-end)

- [ ] Open browser → `https://console.kacho.local` → login as `s@prorobotech.ru` (bootstrap admin).
- [ ] Navigate to `/system/cluster/admins` → expect table with S row, disabled "Отозвать" tooltip "Cannot revoke last admin".
- [ ] Click "Добавить admin" → search a known test user email → select → "Выдать" → expect toast "Admin granted".
- [ ] Within 3s table refreshes, U2 row appears.
- [ ] Click "Отозвать" on U2 row → confirm → expect toast → row disappears within 3s.
- [ ] Logout, login as ordinary user U3 → navigate `/system/cluster/admins` → expect 403 / redirect.

### 7.3 Newman regression suite

- [ ] `cd project/kacho-api-gateway/tests/newman && newman run cases/cluster_admin.postman_collection.json --env-var base_url=https://api.kacho.local --env-var token_admin=$TKN_S --env-var token_ordinary=$TKN_U3` → expect **13/13 green**.
- [ ] Run full IAM newman regression to confirm no regression: `newman run cases/iam-*.postman_collection.json ...` — expect 100% pass.

### 7.4 Close KAC-196

- [ ] Move YouTrack KAC-196 from `Test` → `Done`.
- [ ] Final comment in KAC-196: list 5 PR URLs + smoke evidence + newman pass log.
- [ ] Delete `KAC-196` branches in all 5 repos: `for repo in kacho-proto kacho-iam kacho-api-gateway kacho-ui kacho-workspace; do (cd project/$repo && git push origin --delete KAC-196 && git branch -D KAC-196); done`. (Skip if `gh pr merge --delete-branch` already cleaned them.)
- [ ] Update `KAC/KAC-196.md` `status: done`, `closed: 2026-05-25`.

**Exit criteria**: stand has working cluster-admin UI; YT ticket Done; all branches cleaned; vault closed.

---

## Final — PR merge order + dependency closure

| # | PR | Repo | Depends on | Notes |
|---|---|---|---|---|
| 1 | kacho-proto: InternalClusterService | kacho-proto | none | merge first — generated stubs needed downstream |
| 2 | kacho-iam: handler + repo + use-cases | kacho-iam | (1) merged OR CI pinned to KAC-196 branch | tests in-PR per запрет #12 |
| 3 | kacho-api-gateway: catalog + restmux + newman | kacho-api-gateway | (1) + (2) merged | newman runs against stand built from (1)+(2) |
| 4 | kacho-ui: page + Playwright | kacho-ui | (3) merged on dev stand | Playwright runs against (3) |
| 5 | kacho-workspace: vault trail | kacho-workspace | merge anytime (independent) | KAC-196.md trail finalised at end |

**Rollback plan**: revert in reverse order. Catalog entries + restmux are idempotent (4 entries → remove; restmux registration → unregister). DB rows in `cluster_admin_grants` persist even after rollback (they are valid records, FGA tuples remain valid). To "undo grants" cleanly: use the same `RevokeAdmin` RPC.

**No tech-debt left behind** (workspace запрет #11): every TODO closed in-PR. Acceptance §5 DoD = source of truth — if all checkboxes tick, KAC-196 is done.
