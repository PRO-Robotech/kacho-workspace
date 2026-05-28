# RBAC Redesign + IAM Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote permission grammar to `module.resource.resourceName.verb` (4 segments), add explicit `scope` enum to AccessBinding, ensure every `List<Resource>` RPC filters rows by per-subject FGA `ListObjects`, and physically remove SCIM/SAML/Break-Glass surfaces across kacho-* repos.

**Architecture:** Reuse the existing OpenFGA model (cluster ▶ account ▶ project ▶ per-domain). Concrete-resourceName grants become direct per-object FGA tuples. Scope-level grants become tier tuples at the matching hierarchy node. Subjects' `ListObjects` results drive `WHERE id = ANY($ids)` filters on List handlers, with explicit `wildcard_grant` short-circuit.

**Tech Stack:** Go 1.25, protobuf/grpc-gateway, sqlc + handwritten pgx, OpenFGA HTTP, testcontainers-go, newman/postman, goose migrations, k8s-helm.

**Design doc:** `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` (read before starting). Approved by user 2026-05-28.

**TDD policy (strict):** Per workspace CLAUDE.md §12/§13. For every behavioural change: RED test first (run, see fail with the right reason) → minimal GREEN → commit. Each PR body shows the RED→GREEN pair. NO TODO/FIXME/skip in any new file (test or prod).

**Branch convention:** `KAC-<N>-<wave-slug>` per wave, per repo. Don't push to main directly. Each wave merges in topological order.

---

## File Structure (component map)

Reference §4 of the design doc. The matrix below pins exact paths used by the tasks.

### kacho-proto (`project/kacho-proto/proto/kacho/cloud/iam/v1/`)
- **Modify**: `access_binding.proto` — add `Scope` enum + `scope` field (15).
- **Modify**: `authorize_service.proto` — add `bool wildcard_grant = 4` to `ListObjectsResponse`.
- **Modify**: `fga_model.fga` — remove `emergency_admin`, `break_glass_window`; collapse `any_admin`.
- **Delete**: `break_glass_service.proto`, `cluster_break_glass_grant.proto`, `scim_user_mapping.proto`.
- **Modify**: `proto/kacho/cloud/iam/v1/internal_iam_service.proto` — remove any BG-specific RPCs (`ListBreakGlassGrants*`).
- **Regen**: `gen/go/kacho/cloud/iam/v1/**` via `make gen`.

### kacho-iam (`project/kacho-iam/`)
- **Create migration**: `internal/migrations/0025_rbac_v2_grammar_and_scope.sql`.
- **Create migration**: `internal/migrations/0026_drop_scim_saml_break_glass.sql`.
- **Create**: `internal/authzmap/fga_types.go` — `(module,resource) → fga_object_type` table.
- **Rewrite**: `internal/authzmap/permissions_to_relations.go` — 4-segment grammar parser; per-resourceName direct-tuple emission.
- **Rewrite**: `internal/service/fga_tuple_writer.go` — emit per §3.5 of design.
- **Add**: `internal/domain/access_binding_scope.go` — `Scope` type + Validate.
- **Modify**: `internal/apps/kacho/api/access_binding/{create,update,read}*.go` — pipe `scope`.
- **Modify**: `internal/repo/kacho/pg/access_binding*.go` — read/write `scope` column.
- **Regen**: `internal/apps/kacho/seed/embedded/permission_catalog.json` — 4-segment.
- **Delete**: `internal/apps/kacho/api/scim/`, `internal/apps/kacho/api/saml/`.
- **Delete**: `internal/repo/kacho/pg/{scim_repos.go, scim_gdpr_reviews_repos.go, organization_sso_repos.go, break_glass_repos.go, sso_scim_integration_test.go}`.
- **Delete**: `internal/service/{break_glass_service.go, break_glass_service_test.go}`.
- **Delete**: `internal/domain/{scim_user_mapping.go, cluster_break_glass_grant.go, cluster_break_glass_grant_test.go}`.
- **Delete**: `internal/clients/{jackson_client.go, jackson_client_test.go}`.
- **Delete**: `internal/fuzz/fuzz_saml_assertion_test.go`.
- **Modify**: `cmd/kacho-iam/{serve.go, wiring.go, governance_wiring.go, grpc_register.go, listeners.go}` — strip BG/SCIM/SAML wiring.

### kacho-api-gateway (`project/kacho-api-gateway/`)
- **Modify**: `internal/middleware/embed/permission_catalog.json` — regen 4-segment.
- **Modify**: `internal/restmux/mux.go` — remove SCIM/SAML/BG routes.
- **Modify**: `internal/grpcproxy/allowlist.go` — remove BG/SCIM methods.

### kacho-vpc (`project/kacho-vpc/`)
- **Audit**: every `internal/apps/kacho/api/<resource>/list*.go` — ensure `listauthz.Adapter` is wired.
- **Add**: tests for each `List` RPC under list-filter matrix (empty/some/wildcard).

### kacho-compute (`project/kacho-compute/`)
- **Audit**: every `internal/apps/kacho/api/<resource>/list*.go` — ensure `listauthz.Adapter` is wired.
- **Add**: tests under list-filter matrix.

### kacho-deploy (`project/kacho-deploy/`)
- **Modify**: `helm/kacho-iam/values.yaml` — drop `breakGlass.*`, `scim.*`, `saml.*`.
- **Modify**: `helm/openfga/bootstrap-job.yaml` (or equivalent) — drop `emergency_admin`/`break_glass_window`.
- **Delete**: `tests/newman/cases/iam-scim-*.py`, `iam-saml-*.py`, `iam-break-glass-*.py`.
- **Add**: `tests/newman/cases/list-filter-{vpc,compute,iam}-*.py`.

### kacho-workspace (`./`)
- **Add**: `docs/specs/sub-phase-rbac-v2-w<N>-<wave>-acceptance.md` per wave.
- **Update vault**: `obsidian/kacho/resources/iam-access-binding.md`, `iam-role.md` (4-segment grammar + scope).
- **Update vault**: `obsidian/kacho/rpc/iam-authorize-service.md` (`wildcard_grant`).
- **Mark deprecated in vault**: `iam-scim-user-mapping.md`, `iam-cluster-break-glass-grant.md`, `iam-saml-sp.md`, `iam-scim-v2.md`.
- **Add KAC notes**: one per wave + epic root.

---

## Wave 0 — Bootstrap (workspace meta)

### Task 0.1: Create YouTrack epic + wave subtasks

- [ ] **Step 1: Create epic**

Use REST against `prorobotech.youtrack.cloud` (perm-token in memory note `youtrack-credentials.md`).

```bash
curl -s -X POST "$YT_URL/api/issues" -H "Authorization: Bearer $YT_TOKEN" -H "Content-Type: application/json" -d '{
  "project": {"id": "0-5"},
  "summary": "[EPIC] RBAC v2 — 4-segment grammar, scoped AccessBinding, list-filter, SCIM/SAML/BG removal",
  "description": "<paste design-doc Goals + Waves sections>"
}'
```

- [ ] **Step 2: Create one subtask per wave (W2..W8)**, link as `subtask of <epic>`, add to current sprint.

- [ ] **Step 3: Create per-wave vault notes** under `obsidian/kacho/KAC/KAC-<N>.md`, frontmatter status=`To do`, type=`feature|refactor`.

- [ ] **Step 4: Commit** workspace changes (vault + spec link).

```bash
git -C kacho-workspace add docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md obsidian/kacho/KAC/
git -C kacho-workspace commit -m "docs(KAC-EPIC): RBAC v2 design + plan + per-wave KAC trail"
```

### Task 0.2: Create per-wave acceptance docs (Given-When-Then)

- [ ] **Step 1**: Create `docs/specs/sub-phase-rbac-v2-w2-proto-acceptance.md` with scenarios listed in §6 of THIS plan (W2 acceptance criteria).
- [ ] **Step 2**: Same for W3..W8 — six more docs.
- [ ] **Step 3**: Dispatch `acceptance-reviewer` agent on each; mark `APPROVED` (or iterate until approved). Per workspace §1 gate.
- [ ] **Step 4**: Commit + push to workspace `main` (these are pre-code docs).

---

## Wave 2 — kacho-proto: schema additive + drops

Branch: `KAC-<W2>-rbac-v2-proto` from `kacho-proto/main`.

### Task 2.1: Add `Scope` enum + `scope` field to AccessBinding

**Files:**
- Modify: `proto/kacho/cloud/iam/v1/access_binding.proto`

- [ ] **Step 1: Write proto-level test for additive-only breaking baseline**

Run baseline `buf breaking` first to confirm clean tree:
```bash
cd project/kacho-proto && buf breaking --against '.git#branch=main'
```
Expected: empty output (clean).

- [ ] **Step 2: Apply the additive edit**

```protobuf
// At the end of the existing AccessBinding message (before closing brace):
  enum Scope {
    SCOPE_UNSPECIFIED = 0;
    CLUSTER           = 1;
    ACCOUNT           = 2;
    PROJECT           = 3;
  }
  // Explicit scope tier; backfill default for legacy rows is computed from
  // resource_type during migration 0025.
  Scope scope = 15;
```

- [ ] **Step 3: Re-run buf breaking**

```bash
buf breaking --against '.git#branch=main'
```
Expected: empty output (additive change — no breaking).

- [ ] **Step 4: `make gen` to regen go-stubs**

```bash
make gen && go build ./...
```

- [ ] **Step 5: Commit**

```bash
git checkout -b KAC-<W2>-rbac-v2-proto
git add proto/kacho/cloud/iam/v1/access_binding.proto gen/go/
git commit -m "feat(iam/proto): add AccessBinding.Scope enum + scope field (KAC-<W2>)"
```

### Task 2.2: Add `wildcard_grant` to ListObjectsResponse

**Files:**
- Modify: `proto/kacho/cloud/iam/v1/authorize_service.proto`

- [ ] **Step 1: Add the field**

In `message ListObjectsResponse`:
```protobuf
  // True when the subject has unbounded reach under (resource_type, action)
  // — the caller MUST skip the WHERE-IN filter and return all rows.
  bool wildcard_grant = 4;
```

- [ ] **Step 2: `make gen` + `go build ./...`**

- [ ] **Step 3: Commit** — `feat(iam/proto): ListObjectsResponse.wildcard_grant for list-filter bypass (KAC-<W2>)`

### Task 2.3: Edit `fga_model.fga` — drop emergency_admin

**Files:**
- Modify: `proto/kacho/cloud/iam/v1/fga_model.fga`

- [ ] **Step 1: Apply edit**
  - Remove `define emergency_admin: [user with break_glass_window]`.
  - Remove the `condition break_glass_window {...}` block.
  - Change `define any_admin: system_admin or emergency_admin` to `define any_admin: system_admin`.

- [ ] **Step 2: Validate**: `make openfga-model-validate` (or `openfga model validate --file fga_model.fga` if the helm script generates the JSON via this CLI).

- [ ] **Step 3: Commit** — `refactor(iam/fga): drop emergency_admin + break_glass_window relation (KAC-<W2>)`

### Task 2.4: Delete BG/SCIM/SAML protos

**Files:**
- Delete: `proto/kacho/cloud/iam/v1/break_glass_service.proto`
- Delete: `proto/kacho/cloud/iam/v1/cluster_break_glass_grant.proto`
- Delete: `proto/kacho/cloud/iam/v1/scim_user_mapping.proto`

- [ ] **Step 1: Confirm no SAML .proto exists** (SAML lives only in handler code per design §3.6). `ls proto/kacho/cloud/iam/v1/saml*.proto` → expected: empty / not found.

- [ ] **Step 2: Delete the three files**

- [ ] **Step 3: Drop BG-specific RPCs from `internal_iam_service.proto`** — search for `BreakGlass`, remove `rpc` lines + their request/response messages.

- [ ] **Step 4: `make gen`** — go-stubs disappear; `go build ./...` fails for any consumer that imported them (intentional — kacho-iam consumers updated in W4).

- [ ] **Step 5: Commit** — `refactor(iam/proto): drop break_glass / scim_user_mapping (KAC-<W2>)`

### Task 2.5: Open PR + merge

- [ ] **Step 1**: Open PR in `PRO-Robotech/kacho-proto` titled `[KAC-<W2>] RBAC v2 proto changes`. Body lists each task + RED→GREEN evidence (the `buf breaking` clean baseline + intentional consumer break in kacho-iam is documented).

- [ ] **Step 2**: Wait for downstream W3+W4 to land their consumer-side updates pinning kacho-proto to this PR branch (via `ref:` in CI). Then merge after PRs are stacked.

- [ ] **Step 3**: Add PR URL to `obsidian/kacho/KAC/KAC-<W2>.md`.

---

## Wave 3 — kacho-iam migrations

Branch: `KAC-<W3>-rbac-v2-migrations` from `kacho-iam/main`, with `replace ../kacho-proto` pointing at the W2 branch.

### Task 3.1: Migration `0025_rbac_v2_grammar_and_scope.sql` — backup tables

**Files:**
- Create: `internal/migrations/0025_rbac_v2_grammar_and_scope.sql`

- [ ] **Step 1: Write integration test FIRST**

Create `internal/repo/kacho/pg/migration_0025_integration_test.go`:

```go
package pg

import (
	"context"
	"testing"

	"github.com/PRO-Robotech/kacho-iam/internal/migrations"
	"github.com/jackc/pgx/v5"
)

func TestMigration0025_AddsScopeColumnAndPromotes3SegToWildcard(t *testing.T) {
	ctx := context.Background()
	pool := startPostgresUpTo(t, "0024")
	// seed: one 3-segment role + one access_binding per scope-class
	mustExec(t, pool, `INSERT INTO kacho_iam.roles(id, name, is_system, permissions) VALUES
	  ('rol00000000000000test01', 'test.viewer', false, '["compute.instance.read","vpc.network.create"]'::jsonb);`)
	mustExec(t, pool, `INSERT INTO kacho_iam.accounts(id, name, owner_user_id) VALUES ('acc00000000000000test1','t','usr00000000000000test1');`)
	mustExec(t, pool, `INSERT INTO kacho_iam.access_bindings(id, subject_type, subject_id, role_id, resource_type, resource_id, status, granted_by_user_id) VALUES
	  ('acb00000000000000acc01','user','usr00000000000000test1','rol00000000000000test01','account','acc00000000000000test1','ACTIVE','usr00000000000000test1');`)

	// Run migration 0025.
	migrations.UpTo(t, pool, "0025")

	// Assertions: 3-segment permissions promoted to 4-segment.
	var perms []string
	row := pool.QueryRow(ctx, `SELECT jsonb_array_elements_text(permissions) FROM kacho_iam.roles WHERE id='rol00000000000000test01' ORDER BY 1`)
	for { ... } // collect to perms
	require.Equal(t, []string{"compute.instance.*.read","vpc.network.*.create"}, perms)

	// Assertions: access_bindings.scope = ACCOUNT(2).
	var scope int
	pool.QueryRow(ctx, `SELECT scope FROM kacho_iam.access_bindings WHERE id='acb00000000000000acc01'`).Scan(&scope)
	require.Equal(t, 2, scope)
}
```

- [ ] **Step 2: Run test — expect compile or migration-not-found failure**

```bash
go test ./internal/repo/kacho/pg/ -run TestMigration0025 -v
```
Expected: FAIL (migration `0025` doesn't exist).

- [ ] **Step 3: Write the migration**

```sql
-- 0025_rbac_v2_grammar_and_scope.sql
BEGIN;

-- 1. Backup tables.
CREATE TABLE IF NOT EXISTS kacho_iam._pre_rbac_v2_roles
  AS TABLE kacho_iam.roles WITH NO DATA;
INSERT INTO kacho_iam._pre_rbac_v2_roles SELECT * FROM kacho_iam.roles;

CREATE TABLE IF NOT EXISTS kacho_iam._pre_rbac_v2_access_bindings
  AS TABLE kacho_iam.access_bindings WITH NO DATA;
INSERT INTO kacho_iam._pre_rbac_v2_access_bindings SELECT * FROM kacho_iam.access_bindings;

-- 2. Drop the old CHECK then swap the validator.
ALTER TABLE kacho_iam.roles DROP CONSTRAINT IF EXISTS roles_permissions_valid;

CREATE OR REPLACE FUNCTION kacho_iam.iam_permissions_valid_v2(perms jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  e text;
  re text := '^(\*|[a-zA-Z][a-zA-Z0-9_-]*)\.(\*|[a-zA-Z][a-zA-Z0-9_-]*)\.(\*|[a-zA-Z0-9_-]+)\.(\*|[a-z][a-zA-Z0-9_-]*)$';
BEGIN
  IF perms IS NULL OR jsonb_typeof(perms) <> 'array' THEN RETURN false; END IF;
  FOR e IN SELECT jsonb_array_elements_text(perms) LOOP
    IF e !~ re THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END;
$$;

-- 3. Promote 3-segment → 4-segment in-place (idempotent on already-4-seg rows).
UPDATE kacho_iam.roles
SET permissions = (
  SELECT jsonb_agg(
    CASE
      WHEN array_length(string_to_array(p, '.'), 1) = 3
        THEN split_part(p,'.',1)||'.'||split_part(p,'.',2)||'.*.'||split_part(p,'.',3)
      WHEN array_length(string_to_array(p, '.'), 1) = 4 THEN p
      ELSE p  -- malformed; CHECK below will trip and abort migration
    END
  )
  FROM jsonb_array_elements_text(permissions) p
)
WHERE permissions IS NOT NULL AND jsonb_array_length(permissions) > 0;

-- 4. Re-attach CHECK using the new validator.
ALTER TABLE kacho_iam.roles
  ADD CONSTRAINT roles_permissions_valid
  CHECK (kacho_iam.iam_permissions_valid_v2(permissions));

-- 5. Add scope column to access_bindings; backfill.
ALTER TABLE kacho_iam.access_bindings ADD COLUMN scope SMALLINT;
UPDATE kacho_iam.access_bindings SET scope = CASE resource_type
  WHEN 'cluster'      THEN 1
  WHEN 'organization' THEN 1
  WHEN 'account'      THEN 2
  WHEN 'cloud'        THEN 2
  WHEN 'project'      THEN 3
  WHEN 'folder'       THEN 3
  ELSE 3
END;
ALTER TABLE kacho_iam.access_bindings ALTER COLUMN scope SET NOT NULL;
ALTER TABLE kacho_iam.access_bindings
  ADD CONSTRAINT access_bindings_scope_ck CHECK (scope IN (1,2,3));
CREATE INDEX IF NOT EXISTS access_bindings_scope_idx
  ON kacho_iam.access_bindings(scope, resource_type);

COMMIT;
```

- [ ] **Step 4: Register migration in `internal/migrations/migrations.go`** (the `embed.FS` typically picks up `*.sql` automatically — verify by reading existing migration registration; if there's an explicit list, append `0025_rbac_v2_grammar_and_scope.sql`).

- [ ] **Step 5: Re-run test** — expect PASS.

- [ ] **Step 6: Commit** — `feat(iam/migrations): 0025 — promote permissions to 4-segment, add access_bindings.scope (KAC-<W3>)`

### Task 3.2: Migration validator rejects malformed permissions

- [ ] **Step 1: Add test**

```go
func TestMigration0025_RejectsMalformedPermissionsOnInsert(t *testing.T) {
	pool := startPostgresUpTo(t, "0025")
	_, err := pool.Exec(ctx, `INSERT INTO kacho_iam.roles(id, name, is_system, permissions)
	  VALUES ('rol00000000000000bad01','bad',false,'["compute.instance.bad..verb"]'::jsonb)`)
	require.ErrorContains(t, err, "23514") // CHECK violation
	require.ErrorContains(t, err, "roles_permissions_valid")
}
```

- [ ] **Step 2: Run test — PASS (already covered by validator from Task 3.1)**.

- [ ] **Step 3: Commit** — `test(iam/migrations): assert v2 validator rejects malformed 4-segment perms (KAC-<W3>)`

### Task 3.3: Migration `0026_drop_scim_saml_break_glass.sql`

- [ ] **Step 1: Write integration test asserting tables removed**

```go
func TestMigration0026_DropsScimSamlBreakGlassTables(t *testing.T) {
	pool := startPostgresUpTo(t, "0026")
	tables := []string{"scim_user_mappings","scim_gdpr_reviews","organization_saml_configs","cluster_break_glass_grants"}
	for _, tbl := range tables {
		var exists bool
		pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='kacho_iam' AND table_name=$1)`, tbl).Scan(&exists)
		require.False(t, exists, "table %s still exists after 0026", tbl)
	}
}
```

- [ ] **Step 2: Run test — FAIL** (migration missing).

- [ ] **Step 3: Write migration**

```sql
-- 0026_drop_scim_saml_break_glass.sql
BEGIN;
DROP TABLE IF EXISTS kacho_iam.scim_user_mappings CASCADE;
DROP TABLE IF EXISTS kacho_iam.scim_gdpr_reviews CASCADE;
DROP TABLE IF EXISTS kacho_iam.organization_saml_configs CASCADE;
DROP TABLE IF EXISTS kacho_iam.cluster_break_glass_grants CASCADE;
COMMIT;
```

- [ ] **Step 4: Run test — PASS**.

- [ ] **Step 5: Commit** — `feat(iam/migrations): 0026 — drop scim/saml/break-glass tables (KAC-<W3>)`

### Task 3.4: Open W3 PR

- [ ] **Step 1**: PR titled `[KAC-<W3>] RBAC v2 migrations` against `kacho-iam/main`, depends on W2 (proto branch ref in CI).

- [ ] **Step 2**: Verify CI green; merge after W4 code-changes land.

---

## Wave 4 — kacho-iam code: authzmap + tuple writer + scope plumbing + removal

Branch: `KAC-<W4>-rbac-v2-code` from `kacho-iam/main`. Stacks on W3.

### Task 4.1: `authzmap.fga_types.go` — closed type table

**Files:**
- Create: `internal/authzmap/fga_types.go`
- Create: `internal/authzmap/fga_types_test.go`

- [ ] **Step 1: Test first**

```go
package authzmap

import "testing"

func TestFGAObjectType_KnownPairs(t *testing.T) {
	cases := []struct{ module, resource, want string }{
		{"compute","instance","compute_instance"},
		{"compute","disk","compute_disk"},
		{"vpc","network","vpc_network"},
		{"vpc","subnet","vpc_subnet"},
		{"iam","project","project"},
		{"iam","account","account"},
		{"iam","serviceAccount","iam_service_account"},
		{"iam","group","iam_group"},
		{"iam","role","iam_role"},
		{"iam","accessBinding","iam_access_binding"},
	}
	for _, tc := range cases {
		got, ok := FGAObjectType(tc.module, tc.resource)
		if !ok || got != tc.want {
			t.Errorf("FGAObjectType(%s,%s)=%s,%v want %s,true", tc.module, tc.resource, got, ok, tc.want)
		}
	}
}

func TestFGAObjectType_UnknownReturnsFalse(t *testing.T) {
	if got, ok := FGAObjectType("unknown","thing"); ok || got != "" {
		t.Errorf("expected (\"\",false), got (%q,%v)", got, ok)
	}
}
```

- [ ] **Step 2: Run — FAIL** (no `FGAObjectType` symbol).

- [ ] **Step 3: Implement**

```go
package authzmap

// FGAObjectType maps a permission's (module, resource) pair to the
// OpenFGA object_type used in tuple emission and ListObjects calls.
// Closed table — extending requires updating fga_model.fga in lockstep.
func FGAObjectType(module, resource string) (string, bool) {
	key := module + "." + resource
	o, ok := fgaTypes[key]
	return o, ok
}

var fgaTypes = map[string]string{
	"compute.instance":   "compute_instance",
	"compute.disk":       "compute_disk",
	"compute.image":      "compute_image",
	"compute.snapshot":   "compute_snapshot",
	"compute.hypervisor": "compute_hypervisor",
	"vpc.network":             "vpc_network",
	"vpc.subnet":              "vpc_subnet",
	"vpc.address":             "vpc_address",
	"vpc.securityGroup":       "vpc_security_group",
	"vpc.routeTable":          "vpc_route_table",
	"vpc.gateway":             "vpc_gateway",
	"vpc.privateEndpoint":     "vpc_private_endpoint",
	"vpc.networkInterface":    "vpc_network_interface",
	"vpc.addressPool":         "vpc_address_pool",
	"lb.networkLoadBalancer": "lb_network_load_balancer",
	"lb.targetGroup":         "lb_target_group",
	"lb.listener":            "lb_listener",
	"iam.account":        "account",
	"iam.project":        "project",
	"iam.user":           "iam_user",
	"iam.serviceAccount": "iam_service_account",
	"iam.group":          "iam_group",
	"iam.role":           "iam_role",
	"iam.accessBinding":  "iam_access_binding",
	"iam.condition":      "iam_condition",
}
```

- [ ] **Step 4: Run — PASS**. `go vet ./...`.

- [ ] **Step 5: Commit** — `feat(iam/authzmap): closed (module,resource) → fga_object_type table (KAC-<W4>)`

### Task 4.2: `permissions_to_relations.go` — 4-segment grammar

**Files:**
- Modify: `internal/authzmap/permissions_to_relations.go`
- Modify: `internal/authzmap/permissions_to_relations_test.go`

- [ ] **Step 1: Add failing tests for 4-segment shape**

```go
func TestPermissionsToRelations_4Seg_WildcardName_TierMap(t *testing.T) {
	rels := PermissionsToRelations([]string{"compute.instance.*.read"})
	require.Equal(t, []Relation{"viewer"}, rels)

	rels = PermissionsToRelations([]string{"vpc.network.*.create"})
	require.Equal(t, []Relation{"editor"}, rels)

	rels = PermissionsToRelations([]string{"*.*.*.*"})
	require.Equal(t, []Relation{"admin"}, rels)
}

func TestPermissionsToRelations_4Seg_RejectsLegacy3Seg(t *testing.T) {
	rels := PermissionsToRelations([]string{"compute.instance.read"})
	require.Equal(t, []Relation{"viewer"}, rels, "least-privilege fallback for malformed")
}
```

- [ ] **Step 2: Add resource-grant helper test** (new API for concrete-resourceName emission)

```go
func TestSplitGrants_4Seg_ResourceLevelEmit(t *testing.T) {
	gs := SplitGrants([]string{"compute.instance.inst-abc.read", "vpc.network.*.read"})
	require.Equal(t, []Grant{
		{Module:"compute", Resource:"instance", ResourceName:"inst-abc", Verb:"read", Tier:"viewer", FGAType:"compute_instance"},
		{Module:"vpc",     Resource:"network",  ResourceName:"*",        Verb:"read", Tier:"viewer", FGAType:"vpc_network"},
	}, gs)
}
```

- [ ] **Step 3: Run — FAIL** on new symbols.

- [ ] **Step 4: Implement**

Add `parsePermission` to split into 4 segments + return Grant{} struct; keep `PermissionsToRelations` as the tier-only summarizer; introduce `SplitGrants` returning the structured form for fga_tuple_writer.

```go
// Grant — parsed view of one permission string.
type Grant struct {
	Module       string
	Resource     string
	ResourceName string  // "*" allowed
	Verb         string
	Tier         string  // "viewer"/"editor"/"admin"
	FGAType      string  // empty if (Module,Resource) not in fgaTypes — caller falls back
}

func SplitGrants(perms []string) []Grant {
	out := make([]Grant, 0, len(perms))
	for _, p := range perms {
		segs := strings.Split(p, ".")
		if len(segs) != 4 { continue }
		t := tierFromVerb(segs[3])
		fga, _ := FGAObjectType(segs[0], segs[1])
		out = append(out, Grant{
			Module: segs[0], Resource: segs[1], ResourceName: segs[2], Verb: segs[3],
			Tier: t, FGAType: fga,
		})
	}
	return out
}

func tierFromVerb(verb string) string {
	switch verbClass(verb) {
	case classAdmin: return "admin"
	case classWrite: return "editor"
	case classRead:  return "viewer"
	}
	return "viewer"
}
```

Adjust `PermissionsToRelations` to:
- Accept only 4-segment (anything else → least-privilege `viewer`).
- Tier-summarize as today.

- [ ] **Step 5: Run — PASS** all tests including pre-existing tier ones (with adjusted inputs in pre-existing tests — they used 3-seg strings; change to 4-seg).

- [ ] **Step 6: Commit** — `refactor(iam/authzmap): 4-segment grammar + Grant struct (KAC-<W4>)`

### Task 4.3: Domain `AccessBindingScope` type

**Files:**
- Create: `internal/domain/access_binding_scope.go`
- Create: `internal/domain/access_binding_scope_test.go`

- [ ] **Step 1: Test**

```go
func TestAccessBindingScope_Validate(t *testing.T) {
	ok := []struct{ s domain.Scope; rt, rid string }{
		{domain.ScopeCluster, "cluster", "cluster_kacho_root"},
		{domain.ScopeAccount, "account", "acc00000000000000a001"},
		{domain.ScopeProject, "project", "prj00000000000000p001"},
	}
	for _, c := range ok {
		require.NoError(t, c.s.ValidateAgainst(c.rt, c.rid))
	}
	err := domain.ScopeCluster.ValidateAgainst("project", "prj01")
	require.ErrorIs(t, err, domain.ErrScopeMismatch)
}
```

- [ ] **Step 2: Implement**

```go
package domain

import "errors"

type Scope int8

const (
	ScopeUnspecified Scope = 0
	ScopeCluster     Scope = 1
	ScopeAccount     Scope = 2
	ScopeProject     Scope = 3
)

var ErrScopeMismatch = errors.New("scope does not match resource_type")

func (s Scope) ValidateAgainst(resourceType, resourceID string) error {
	switch s {
	case ScopeCluster:
		if resourceType != "cluster" || resourceID != "cluster_kacho_root" { return ErrScopeMismatch }
	case ScopeAccount:
		if resourceType != "account" || !strings.HasPrefix(resourceID, PrefixAccount) { return ErrScopeMismatch }
	case ScopeProject:
		if resourceType != "project" || !strings.HasPrefix(resourceID, PrefixProject) { return ErrScopeMismatch }
	default:
		return ErrScopeMismatch
	}
	return nil
}
```

- [ ] **Step 3: Run — PASS**.

- [ ] **Step 4: Commit** — `feat(iam/domain): AccessBindingScope type + ValidateAgainst (KAC-<W4>)`

### Task 4.4: Plumb `scope` through repo (read + write)

**Files:**
- Modify: `internal/repo/kacho/pg/access_binding_repos.go` (or wherever the writer/reader DTO lives)
- Modify: `internal/repo/kacho/pg/access_binding_*_integration_test.go`

- [ ] **Step 1: Integration test — write + read-back persists scope**

```go
func TestAccessBindingRepo_WriteReadScope(t *testing.T) {
	repo := setupRepo(t)
	id, err := repo.Insert(ctx, domain.AccessBinding{
		ID:"acb00000000000000sco01", SubjectType:"user", SubjectID:"usr...", RoleID:"rol...",
		ResourceType:"account", ResourceID:"acc...", Scope: domain.ScopeAccount,
		GrantedByUserID:"usr...", Status: domain.StatusActive,
	})
	require.NoError(t, err)
	ab, err := repo.GetByID(ctx, id)
	require.NoError(t, err)
	require.Equal(t, domain.ScopeAccount, ab.Scope)
}
```

- [ ] **Step 2: Run — FAIL** (no Scope field on domain.AccessBinding or repo SELECTs).

- [ ] **Step 3: Add `Scope` field to `domain.AccessBinding`** + update repo INSERT/UPDATE SELECT to include `scope` column.

- [ ] **Step 4: Run — PASS**.

- [ ] **Step 5: Commit** — `feat(iam/repo): persist AccessBinding.Scope (KAC-<W4>)`

### Task 4.5: Handler — accept + validate `scope`

**Files:**
- Modify: `internal/apps/kacho/api/access_binding/create.go`
- Modify: `internal/apps/kacho/api/access_binding/handler_test.go` (or equiv unit test path)

- [ ] **Step 1: Test — Create rejects scope-mismatch**

```go
func TestCreate_RejectsScopeMismatch(t *testing.T) {
	h := newHandler(t)
	_, err := h.Create(ctx, &iamv1.CreateAccessBindingRequest{
		Subject: &..., RoleId:"rol...",
		Resource: &iamv1.ResourceRef{Type:"project", Id:"prj..."},
		Scope:    iamv1.AccessBinding_CLUSTER,
	})
	require.Equal(t, codes.InvalidArgument, status.Code(err))
}
```

- [ ] **Step 2: Run — FAIL** (handler ignores scope).

- [ ] **Step 3: Implement** — extract `req.Scope`, call `domain.Scope(...).ValidateAgainst(...)`, fail-fast on mismatch. Bubble through to repo.

- [ ] **Step 4: Run — PASS**.

- [ ] **Step 5: Commit** — `feat(iam/handler/access_binding): validate scope vs resource_type (KAC-<W4>)`

### Task 4.6: Rewrite fga_tuple_writer — emit per §3.5

**Files:**
- Modify: `internal/service/fga_tuple_writer.go`
- Modify: `internal/service/fga_tuple_writer_test.go`

- [ ] **Step 1: Table-driven test covering each (pattern × scope) cell from §3.5**

```go
func TestFGATupleWriter_EmitMatrix(t *testing.T) {
	tests := []struct{
		perm string; scope domain.Scope; resID string
		want []FGATuple
	}{
		{"*.*.*.*", domain.ScopeCluster, "cluster_kacho_root",
			[]FGATuple{{Object:"cluster:cluster_kacho_root", Relation:"system_admin", User:"user:usr-X"}}},
		{"compute.instance.*.read", domain.ScopeAccount, "acc-A",
			[]FGATuple{{Object:"account:acc-A", Relation:"viewer", User:"user:usr-X"}}},
		{"compute.instance.inst-abc.read", domain.ScopeProject, "prj-P",
			[]FGATuple{{Object:"compute_instance:inst-abc", Relation:"viewer", User:"user:usr-X"}}},
		// ... add the rest from §3.5
	}
	for _, tc := range tests {
		got := EmitForBinding("user:usr-X", domain.AccessBinding{
			Scope: tc.scope, ResourceID: tc.resID, ResourceType: scope2rt(tc.scope),
		}, []string{tc.perm})
		require.Equal(t, tc.want, got, "perm=%s scope=%v", tc.perm, tc.scope)
	}
}
```

- [ ] **Step 2: Run — FAIL** on signature change.

- [ ] **Step 3: Implement `EmitForBinding`** consuming `authzmap.SplitGrants` + `domain.AccessBinding` + tier semantics.

- [ ] **Step 4: Run — PASS**.

- [ ] **Step 5: Commit** — `refactor(iam/service): fga_tuple_writer emits 4-seg + scope-aware tuples (KAC-<W4>)`

### Task 4.7: Strip break-glass code

**Files:**
- Delete: `internal/service/break_glass_service.go`, `_test.go`
- Delete: `internal/domain/cluster_break_glass_grant.go`, `_test.go`
- Delete: `internal/repo/kacho/pg/break_glass_repos.go`
- Modify: `cmd/kacho-iam/wiring.go`, `governance_wiring.go`, `grpc_register.go`

- [ ] **Step 1: Delete files**

```bash
git rm internal/service/break_glass_service.go internal/service/break_glass_service_test.go
git rm internal/domain/cluster_break_glass_grant.go internal/domain/cluster_break_glass_grant_test.go
git rm internal/repo/kacho/pg/break_glass_repos.go
```

- [ ] **Step 2: Strip references**

```bash
grep -rn "break.glass\|BreakGlass\|cluster_break_glass_grant" cmd/ internal/ | cut -d: -f1 | sort -u
```
For each file: remove imports + variable declarations + wiring lines. After edits, run `goimports -w .`.

- [ ] **Step 3: Build**

```bash
go build ./... && go vet ./...
```
Expected: clean.

- [ ] **Step 4: Commit** — `refactor(iam): remove break-glass service + cluster_break_glass_grant (KAC-<W4>)`

### Task 4.8: Strip SCIM code

**Files:**
- Delete: `internal/apps/kacho/api/scim/` (entire dir)
- Delete: `internal/domain/scim_user_mapping.go`
- Delete: `internal/repo/kacho/pg/scim_repos.go`, `scim_gdpr_reviews_repos.go`, `sso_scim_integration_test.go`
- Modify: `cmd/kacho-iam/{serve.go, listeners.go, wiring.go}`

- [ ] **Step 1: Delete files**

```bash
git rm -r internal/apps/kacho/api/scim
git rm internal/domain/scim_user_mapping.go
git rm internal/repo/kacho/pg/scim_repos.go internal/repo/kacho/pg/scim_gdpr_reviews_repos.go internal/repo/kacho/pg/sso_scim_integration_test.go
```

- [ ] **Step 2: Strip wiring** (`scim.Mount`, `scimRepo`, listener registration, env vars).

- [ ] **Step 3: `go build ./... && go vet ./...`** — clean.

- [ ] **Step 4: Commit** — `refactor(iam): remove SCIM v2 surface (KAC-<W4>)`

### Task 4.9: Strip SAML code

**Files:**
- Delete: `internal/apps/kacho/api/saml/`
- Delete: `internal/repo/kacho/pg/organization_sso_repos.go`
- Delete: `internal/clients/jackson_client.go`, `_test.go`
- Delete: `internal/fuzz/fuzz_saml_assertion_test.go`
- Modify: `cmd/kacho-iam/{serve.go, wiring.go, listeners.go}`

- [ ] **Step 1: Delete files**.

- [ ] **Step 2: Strip wiring** (boxyhq jackson client, SAML SP routes).

- [ ] **Step 3: Build clean**.

- [ ] **Step 4: Commit** — `refactor(iam): remove SAML SP + boxyhq jackson client (KAC-<W4>)`

### Task 4.10: Regenerate permission_catalog.json (4-segment)

**Files:**
- Modify: `internal/apps/kacho/seed/embedded/permission_catalog.json`

- [ ] **Step 1: Run the catalog generator** (lives in `kacho-proto/scripts/permission-catalog-gen/` typically). Verify the generator emits 4-segment after a `make catalog` invocation. If not, patch it (separate one-line tweak).

- [ ] **Step 2: Copy to iam mirror**:

```bash
cp ../kacho-proto/gen/permission_catalog.json internal/apps/kacho/seed/embedded/permission_catalog.json
```

- [ ] **Step 3: Run integration test** `LoadPermissionRegistry` — assert every entry is 4-segment (`strings.Count(p, ".") == 3`).

- [ ] **Step 4: Commit** — `chore(iam/seed): regenerate permission_catalog.json (4-segment) (KAC-<W4>)`

### Task 4.11: Open W4 PR + merge after W3

- [ ] **Step 1: PR `[KAC-<W4>] RBAC v2 code` against `kacho-iam/main`**; CI pins kacho-proto to W2 PR branch.
- [ ] **Step 2: Merge after W3 migrations + W2 proto are green and merged**.

---

## Wave 5 — kacho-api-gateway: route + catalog cleanup

Branch: `KAC-<W5>-rbac-v2-gateway` from `kacho-api-gateway/main`.

### Task 5.1: Regenerate permission_catalog.json

**Files:**
- Modify: `internal/middleware/embed/permission_catalog.json`

- [ ] **Step 1: Test — middleware loads and routes correctly with 4-segment catalog**

Find the existing middleware test that parses the catalog (`internal/middleware/authz_interceptor_test.go` or similar); add a case that any entry's `permission` field, if non-empty, has exactly 3 dots (4 segments).

- [ ] **Step 2: Copy regenerated catalog from kacho-proto**.

- [ ] **Step 3: Run tests — PASS**.

- [ ] **Step 4: Commit** — `chore(gateway): regenerate 4-segment permission_catalog.json (KAC-<W5>)`

### Task 5.2: Drop SCIM/SAML/BG routes

**Files:**
- Modify: `internal/restmux/mux.go`
- Modify: `internal/grpcproxy/allowlist.go`

- [ ] **Step 1: Identify the lines**

```bash
grep -n "scim\|saml\|breakGlass\|BreakGlass" internal/restmux/mux.go internal/grpcproxy/
```

- [ ] **Step 2: Add integration test asserting these REST paths return 404**

```go
func TestREST_RouteRemoved_SCIM(t *testing.T) {
	mux := buildMux(t)
	rec := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/scim/v2/Users", nil)
	mux.ServeHTTP(rec, req)
	require.Equal(t, http.StatusNotFound, rec.Code)
}
// same for /saml, /iam/v1/breakGlass...
```

- [ ] **Step 3: Run — FAIL** (routes still mounted).

- [ ] **Step 4: Remove lines**.

- [ ] **Step 5: Run — PASS**.

- [ ] **Step 6: Commit** — `refactor(gateway): drop SCIM/SAML/break-glass REST routes (KAC-<W5>)`

### Task 5.3: Open W5 PR

- [ ] PR depends on W2 (proto), W4 (iam).

---

## Wave 6 — kacho-vpc + kacho-compute: list-filter audit

Branches: `KAC-<W6>-rbac-v2-list-filter` in each of `kacho-vpc` and `kacho-compute`.

### Task 6.1: Inventory every List handler

- [ ] **Step 1**: For each repo, grep all gRPC `List<Resource>` handlers:

```bash
cd project/kacho-vpc && grep -rn 'func .*) List' internal/apps/ | grep -v _test
cd project/kacho-compute && grep -rn 'func .*) List' internal/apps/ | grep -v _test
```

Write the inventory to `docs/audit/2026-05-28-list-handlers-vpc.md` and `…-compute.md`.

- [ ] **Step 2**: For each handler, note whether `listauthz.Adapter.ListAllowedIDs` is called. Flag missing handlers.

- [ ] **Step 3: Commit audit doc** — `docs(audit): list-handler inventory pre-W6 (KAC-<W6>)`

### Task 6.2: Wire list-filter into every flagged handler

For each flagged handler `<resource>` (Compute Instance, Compute Disk, VPC Network, VPC Subnet, VPC Address, VPC SecurityGroup, VPC RouteTable, VPC Gateway, VPC PrivateEndpoint, VPC NetworkInterface, VPC AddressPool, LB NLB, LB TargetGroup, LB Listener — adjust to actual inventory):

- [ ] **Step a: Integration test — subject sees only granted ids**

```go
func TestList<Resource>_FiltersBySubject_TwoIdsGranted(t *testing.T) {
	srv := startServer(t, withFakeIAM(map[string][]string{
		"user:usr-bob": {"net-A","net-B"},  // wildcard_grant=false
	}))
	// seed three networks: net-A, net-B, net-C
	resp, err := srv.<Resource>Client().List(ctx, &<Req>{...})
	require.NoError(t, err)
	ids := collectIDs(resp.Items)
	require.ElementsMatch(t, []string{"net-A","net-B"}, ids)
}

func TestList<Resource>_WildcardGrant_BypassesFilter(t *testing.T) {
	srv := startServer(t, withFakeIAM(map[string]wildcardGrant{
		"user:usr-admin": {wildcard: true},
	}))
	// seed three networks
	resp, _ := srv.<Resource>Client().List(ctx, &<Req>{...})
	require.Len(t, resp.Items, 3)
}

func TestList<Resource>_EmptyAccess_ReturnsEmpty(t *testing.T) {
	srv := startServer(t, withFakeIAM(map[string][]string{
		"user:usr-nobody": {},
	}))
	resp, _ := srv.<Resource>Client().List(ctx, &<Req>{...})
	require.Empty(t, resp.Items)
	require.Equal(t, "", resp.NextPageToken)
}
```

- [ ] **Step b: Run — FAIL** if handler currently returns all rows regardless of fake-IAM grants.

- [ ] **Step c: Wire `listauthz.Adapter` in the handler** following the pattern in any already-wired handler (e.g. `kacho-vpc/internal/apps/kacho/api/network/list.go`). Pass action `<module>.<resource>.*.read`.

- [ ] **Step d: Run — PASS**.

- [ ] **Step e: Commit** — `feat(<resource>/list): wire ListObjects-based filter (KAC-<W6>)`

Repeat 6.2 per resource. Cluster the commits per handler (one commit per resource); each commit ships its tests.

### Task 6.3: CI gate — `make audit-list-filter`

**Files:**
- Create: `tools/audit-list-filter.sh` in both kacho-vpc and kacho-compute
- Modify: `.github/workflows/ci.yaml`

- [ ] **Step 1: Test — script flags unwired handler**

Seed test fixture with a handler that returns rows without calling listauthz; assert the script exits 1 with the right error.

- [ ] **Step 2: Implement script** (regex on `func .*List` + nearby `listauthz.Adapter|ListAllowedIDs` reference).

- [ ] **Step 3: Add Makefile target** `make audit-list-filter`; CI invokes it.

- [ ] **Step 4: Commit** — `ci(<repo>): list-filter coverage gate (KAC-<W6>)`

### Task 6.4: Open W6 PRs (one per repo)

---

## Wave 7 — kacho-deploy: helm + newman

Branch: `KAC-<W7>-rbac-v2-deploy` from `kacho-deploy/main`.

### Task 7.1: Drop SCIM/SAML/BG helm artifacts

**Files:**
- Modify: `helm/kacho-iam/values.yaml`
- Modify: `helm/openfga/bootstrap-job.yaml` (or wherever FGA tuples are seeded)

- [ ] **Step 1: Identify lines** (`grep -rn 'breakGlass\|scim\|saml\|emergency_admin\|break_glass_window' helm/`).
- [ ] **Step 2: Remove + re-run `helm template` to confirm no orphaned refs**.
- [ ] **Step 3: Commit** — `refactor(deploy/helm): drop SCIM/SAML/BG values + FGA bootstrap (KAC-<W7>)`

### Task 7.2: Delete BG/SCIM/SAML newman cases

```bash
git rm tests/newman/cases/iam-scim-*.py tests/newman/cases/iam-saml-*.py tests/newman/cases/iam-break-glass-*.py
make -C tests/newman regen
```
- [ ] Commit.

### Task 7.3: Add list-filter newman collections

For each (service × resource) cell of the matrix, add a newman case asserting list-filter behaviour against the deployed stack.

- [ ] **Step 1: Write cases** (use existing `gen.py` DSL).
- [ ] **Step 2: Regen collections**.
- [ ] **Step 3: Run newman locally against `kacho-deploy` dev-stack** — expect RED before W2-W6 are merged + GREEN after.
- [ ] **Step 4: Commit** — `test(newman): list-filter regression matrix (KAC-<W7>)`

### Task 7.4: Open W7 PR + dev-up smoke

- [ ] **Step 1**: PR depends on W2-W6.
- [ ] **Step 2: `make dev-up && make newman-iam-list-filter`** — newman green.

---

## Wave 8 — vault refresh + epic close

Branch: `KAC-<EPIC>-vault-refresh` from `kacho-workspace/main`.

### Task 8.1: Update vault — AccessBinding + Role notes (4-seg grammar + scope)

- [ ] **Step 1**: Edit `obsidian/kacho/resources/iam-access-binding.md` — add `scope` to field table, link KAC notes, update Gotchas.
- [ ] **Step 2**: Edit `obsidian/kacho/resources/iam-role.md` — note 4-segment grammar.
- [ ] **Step 3**: Edit `obsidian/kacho/rpc/iam-authorize-service.md` — note `wildcard_grant`.
- [ ] **Step 4**: Edit `obsidian/kacho/edges/vpc-to-iam-listobjects.md`, `compute-to-iam-listobjects.md` — confirm now mandatory for every List RPC.

### Task 8.2: Mark deprecated vault entries

- [ ] **Step 1**: `iam-scim-user-mapping.md`, `iam-cluster-break-glass-grant.md`, `rpc/iam-saml-sp.md`, `rpc/iam-scim-v2.md`, `edges/iam-to-jackson-saml.md`, `edges/iam-to-scim-*.md` — front-matter `status: deprecated` + body callout `> [!warning] Removed in KAC-<EPIC> (2026-05-28).`

### Task 8.3: Close epic in YouTrack

- [ ] **Step 1**: All subtasks W2-W7 → Done with PR-URLs in comments.
- [ ] **Step 2**: Epic → Done; final comment listing PRs + design+plan doc-paths.

### Task 8.4: Commit + push workspace

```bash
git -C kacho-workspace add obsidian/ docs/
git -C kacho-workspace commit -m "docs(KAC-<EPIC>): vault refresh post-RBAC v2 (KAC-<EPIC>)"
git -C kacho-workspace push origin main
```

---

## Wave acceptance criteria (consolidated)

Per wave, this is the **APPROVED** Given-When-Then to write into `docs/specs/sub-phase-rbac-v2-w<N>-…-acceptance.md` (workspace §1 gate).

### W2 (proto)
- **Given** kacho-proto on `KAC-<W2>` branch; **When** `make gen && buf lint && buf breaking --against '.git#branch=main'`; **Then** lint green AND breaking output contains ONLY the deletions of BG/SCIM/SAML protos AND the `fga_model.fga` change — no unexpected breaks.
- **Given** consumer (`kacho-iam`) pinned via `replace ../kacho-proto` on this branch; **When** `go build ./...`; **Then** build fails ONLY on import sites slated for removal in W4 (BG/SCIM/SAML consumers); other call-sites compile.

### W3 (migrations)
- **Given** Postgres seeded with 3-segment role permissions + access_bindings of various resource_types; **When** migration 0025 applied; **Then** all permissions are 4-segment; `access_bindings.scope` is non-NULL and in `{1,2,3}`; CHECK constraint `access_bindings_scope_ck` exists; backup tables `_pre_rbac_v2_*` carry pre-state.
- **Given** an INSERT of a role with `["a.b.invalid"]` (3-seg); **When** insert runs; **Then** PG error 23514 referencing `roles_permissions_valid`.
- **Given** migration 0026 applied; **Then** four SCIM/SAML/BG tables no longer exist.

### W4 (iam code)
- **Given** AccessBinding Create with scope=CLUSTER but resource_type=project; **Then** `InvalidArgument`.
- **Given** AccessBinding Create with `compute.instance.inst-A.read` + scope=PROJECT/prj-X; **Then** fga_outbox row enqueues tuple `compute_instance:inst-A#viewer@<subject>`.
- **Given** kacho-iam build; **Then** zero references to break-glass / scim / saml / jackson in any package (`grep -ri ... internal/ cmd/` returns nothing).

### W5 (gateway)
- **Given** REST request to `/scim/v2/Users`, `/saml/acs`, or `/iam/v1/breakGlass:approve`; **Then** 404.
- **Given** permission_catalog.json reload; **Then** every entry with non-empty `permission` is 4-segment.

### W6 (vpc/compute list-filter)
- **Given** a subject with `compute.instance.inst-A.read, compute.instance.inst-B.read` and 5 instances seeded (inst-A..inst-E); **When** `List`; **Then** response contains exactly inst-A, inst-B; no PermissionDenied; pagination valid.
- **Given** subject with no read access; **When** `List`; **Then** empty list, OK status.
- **Given** subject is system_admin (`wildcard_grant=true`); **When** `List`; **Then** all 5 instances.
- **Given** CI gate `make audit-list-filter`; **Then** zero unwired List handlers.

### W7 (deploy/newman)
- **Given** `make dev-up`; **When** `make newman-iam-list-filter`; **Then** 100% green.
- **Given** helm template render; **Then** zero `breakGlass`/`scim`/`saml`/`emergency_admin` strings.

### W8 (vault + close)
- **Given** epic-closure walk-through; **Then** every KAC note has PR-URL filled; deprecated vault entries marked; design doc + plan doc linked from epic comments.

---

## Self-Review

**1. Spec coverage:**
- Permission grammar (§3.1) — Task 3.1 validator + Task 4.2 parser. ✅
- AccessBinding shape (§3.2) — Task 2.1 proto + Task 3.1 column + Task 4.3 domain + Task 4.4 repo + Task 4.5 handler. ✅
- List-filter contract (§3.3) — Task 2.2 wildcard_grant + Task 6.2 wiring matrix + Task 6.3 CI gate. ✅
- Inheritance rules (§3.4) — Encoded in fga_model.fga (unchanged); FGA tuple emission covers it (Task 4.6). ✅
- FGA tuple emission (§3.5) — Task 4.6 matrix tests. ✅
- Removal scope (§3.6) — Tasks 2.3, 2.4, 4.7, 4.8, 4.9, 5.2, 7.1, 7.2, 8.2. ✅
- Data migration (§3.7) — Tasks 3.1, 3.3. ✅
- Test strategy (§3.8) — woven into every TDD step. ✅
- Cross-repo waves (§5) — Wave 0-8 alignment. ✅

**2. Placeholder scan:** No TODO/TBD in steps. The phrase "TBD" appears once in the design-doc reference (`Tracking: YouTrack epic — TBD`) — that's a meta-state, resolved by Task 0.1. ✅

**3. Type consistency:**
- `domain.Scope` int8 — used identically in 4.3, 4.4, 4.5, 4.6. ✅
- `FGAObjectType(module, resource) (string, bool)` — used identically in 4.1 and 4.6. ✅
- `Grant{Module, Resource, ResourceName, Verb, Tier, FGAType}` — used in 4.2 and 4.6. ✅
- `ListObjectsResponse.wildcard_grant` — added in 2.2, consumed in 6.2. ✅

No gaps — moving on.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md`.
