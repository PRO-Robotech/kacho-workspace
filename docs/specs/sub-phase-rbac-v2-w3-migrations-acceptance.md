# Sub-phase RBAC v2 / W3 — kacho-iam migrations acceptance

**Tracking**: [[KAC-216]] (parent: [[KAC-214]])
**Repo**: `kacho-iam`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.7
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 3
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- `internal/migrations/0025_rbac_v2_grammar_and_scope.sql`:
  - Create `_pre_rbac_v2_roles`, `_pre_rbac_v2_access_bindings` snapshots.
  - Drop `roles_permissions_valid` CHECK; create `iam_permissions_valid_v2(jsonb)` PL/pgSQL validator (strict 4-segment regex, allowing `*` per segment).
  - In-place promote any 3-segment permission `M.R.V` → `M.R.*.V`. 4-segment rows untouched.
  - Re-attach `roles_permissions_valid` CHECK using v2 validator.
  - `ALTER TABLE access_bindings ADD COLUMN scope SMALLINT`; backfill from `resource_type` table in design §3.7 step 3; `SET NOT NULL`; CHECK `IN (1,2,3)`; index `(scope, resource_type)`.
- `internal/migrations/0026_drop_scim_saml_break_glass.sql`:
  - `DROP TABLE` of `scim_user_mappings`, `scim_gdpr_reviews`, `organization_saml_configs`, `cluster_break_glass_grants` (+ CASCADE for any FK/INDEX).
- Integration tests `internal/repo/kacho/pg/migration_0025_integration_test.go`, `migration_0026_integration_test.go` (testcontainers Postgres 16).

## Scope (out)

- No Go code referencing `scope` outside repo dto-mapping (handler/service in [[KAC-217]]).
- No proto regen consumption beyond what W2 provides.
- No FGA store changes (only DB schema).

## Scenarios

### S3.1 — 3-segment permission promotion is faithful

**Given** a fresh Postgres 16 brought up to migration `0024` with seed:
```sql
INSERT INTO kacho_iam.roles(id, name, is_system, permissions)
VALUES ('rol00000000000000seed1','seed-3seg',false,
  '["compute.instance.read","vpc.network.create","iam.role.delete"]'::jsonb);
```
**When** migration `0025` is applied.
**Then** `SELECT permissions FROM kacho_iam.roles WHERE id='rol00000000000000seed1'` returns a JSONB array equal to
`["compute.instance.*.read","vpc.network.*.create","iam.role.*.delete"]` in some order.

### S3.2 — 4-segment permission rows pass through unchanged

**Given** seed `INSERT permissions = '["compute.instance.inst-A.read","vpc.network.*.create"]'`.
**When** migration `0025` is applied.
**Then** the same value is observed post-migration.

### S3.3 — Malformed permissions reject on subsequent INSERT

**Given** migration `0025` is applied.
**When** `INSERT INTO kacho_iam.roles(...) VALUES ('rol...','bad',false,'["compute.instance.bad..verb"]')` is attempted.
**Then** Postgres returns SQLSTATE `23514` referencing constraint `roles_permissions_valid`.

### S3.4 — Wildcard-only permission passes the v2 validator

**Given** migration `0025` applied.
**When** INSERT with `permissions='["*.*.*.*"]'`.
**Then** the INSERT succeeds.

### S3.5 — `access_bindings.scope` backfill matches resource_type

**Given** seed access_bindings with `resource_type` in `{cluster, account, project, organization, cloud, folder, vpc_network, compute_instance}`.
**When** migration `0025` is applied.
**Then** `scope` column is non-NULL on all rows AND values match:
- `cluster`/`organization` → 1
- `account`/`cloud` → 2
- `project`/`folder` → 3
- any per-domain `resource_type` (`vpc_network`, `compute_instance`, …) → 3.

### S3.6 — `access_bindings.scope` enforces CHECK + NOT NULL

**Given** migration `0025` applied.
**When** attempting `INSERT INTO access_bindings(..., scope=4)`.
**Then** SQLSTATE `23514` referencing `access_bindings_scope_ck`.
**And** `INSERT INTO access_bindings(... no scope ...)` returns SQLSTATE `23502` (NOT NULL).

### S3.7 — Migration is idempotent (re-run is no-op)

**Given** migration `0025` is applied.
**When** the migration is applied a second time (using a fresh `goose up` after marking the row removed manually — to exercise the body).
**Then** the body completes without error; no row count changes; CHECK still in place.

### S3.8 — Backup tables carry pre-state

**Given** migration `0025` is applied to a non-empty schema.
**Then** `kacho_iam._pre_rbac_v2_roles` and `kacho_iam._pre_rbac_v2_access_bindings` exist, are non-empty, and carry the pre-migration data (verify by row count match against the saved snapshot).

### S3.9 — Migration 0026 drops the four target tables

**Given** migration `0025` is applied (so the v2 grammar is enforced).
**And** the four target tables exist (seeded by older migrations).
**When** migration `0026` is applied.
**Then** `SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='kacho_iam' AND table_name=$1)` returns FALSE for each of: `scim_user_mappings`, `scim_gdpr_reviews`, `organization_saml_configs`, `cluster_break_glass_grants`.
**And** any associated INDEX/CONSTRAINT/SEQUENCE is also gone (verified via `pg_indexes`, `pg_constraint`, `pg_sequences`).

### S3.10 — `roles.permissions` does not contain any 3-segment row post-migration

**Given** migration `0025` is applied across all seeded data of the deployed environment.
**When** `SELECT id FROM kacho_iam.roles WHERE EXISTS (SELECT 1 FROM jsonb_array_elements_text(permissions) p WHERE array_length(string_to_array(p,'.'),1) <> 4)`.
**Then** zero rows returned.

## Definition of Done

- [ ] Branch `KAC-216-rbac-v2-migrations` exists; commits per Plan §Wave 3 tasks 3.1..3.4.
- [ ] Integration tests cover scenarios S3.1..S3.10; RED→GREEN pair documented in PR body.
- [ ] PR `PRO-Robotech/kacho-iam#<N>` open; CI green (`make test` + lint).
- [ ] PR URL added to [[KAC-216]] frontmatter `prs:`.
- [ ] [[KAC-216]] → `In Progress` at PR-open; → `Done` after merge.
