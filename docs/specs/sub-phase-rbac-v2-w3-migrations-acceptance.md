# Sub-phase RBAC v2 / W3 — kacho-iam migrations acceptance

**Tracking**: [[KAC-216]] (parent: [[KAC-214]])
**Repo**: `kacho-iam`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.7
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 3
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- `internal/migrations/0005_rbac_v2_grammar_and_scope.sql`:
  - Create `_pre_rbac_v2_roles`, `_pre_rbac_v2_access_bindings` snapshots.
  - Drop `roles_permissions_valid` CHECK; create `iam_permissions_valid_v2(jsonb)` PL/pgSQL validator (strict 4-segment regex, allowing `*` per segment).
  - In-place promote any 3-segment permission `M.R.V` → `M.R.*.V`. 4-segment rows untouched.
  - Re-attach `roles_permissions_valid` CHECK using v2 validator.
  - `ALTER TABLE access_bindings ADD COLUMN scope SMALLINT`; backfill from `resource_type` table in design §3.7 step 3; `SET NOT NULL`; CHECK `IN (1,2,3)`; index `(scope, resource_type)`.
- `internal/migrations/0006_drop_scim_saml_break_glass.sql`:
  - `DROP TABLE` of `scim_user_mappings`, `scim_gdpr_reviews`, `organization_saml_configs`, `cluster_break_glass_grants` (+ CASCADE for any FK/INDEX).
- Integration tests `internal/repo/kacho/pg/migration_0025_integration_test.go`, `migration_0026_integration_test.go` (testcontainers Postgres 16).

## Scope (out)

- No Go code referencing `scope` outside repo dto-mapping (handler/service in [[KAC-217]]).
- No proto regen consumption beyond what W2 provides.
- No FGA store changes (only DB schema).
- **fga_outbox re-emit catch-up** (design §3.7 step 6) is moved to W4 — emission code lives in W4 and re-emit without the new emit logic would write stale tuples.

## Scenarios

### S3.1 — 3-segment permission promotion is faithful

**Given** a fresh Postgres 16 brought up to migration `0004` (current head on `kacho-iam/main` — post KAC-198 squash; CLAUDE.md §6 "count=24" is stale, archived under `docs/architecture/migrations-history/`) with seed:
```sql
INSERT INTO kacho_iam.roles(id, name, is_system, permissions)
VALUES ('rol00000000000000seed1','seed-3seg',false,
  '["compute.instance.read","vpc.network.create","iam.role.delete"]'::jsonb);
```
**When** migration `0005` is applied.
**Then** `SELECT permissions FROM kacho_iam.roles WHERE id='rol00000000000000seed1'` returns a JSONB array equal to
`["compute.instance.*.read","vpc.network.*.create","iam.role.*.delete"]` in some order.

### S3.2 — 4-segment permission rows pass through unchanged

**Given** seed `INSERT permissions = '["compute.instance.inst-A.read","vpc.network.*.create"]'`.
**When** migration `0005` is applied.
**Then** the same value is observed post-migration.

### S3.3 — Malformed permissions reject on subsequent INSERT

**Given** migration `0005` is applied.
**When** `INSERT INTO kacho_iam.roles(...) VALUES ('rol...','bad',false,'["compute.instance.bad..verb"]')` is attempted.
**Then** Postgres returns SQLSTATE `23514` referencing constraint `roles_permissions_valid`.

### S3.4 — Wildcard-only permission passes the v2 validator

**Given** migration `0005` applied.
**When** INSERT with `permissions='["*.*.*.*"]'`.
**Then** the INSERT succeeds.

### S3.5 — `access_bindings.scope` backfill matches resource_type

**Given** seed access_bindings with `resource_type` in `{cluster, account, project, organization, cloud, folder, vpc_network, compute_instance, user, service_account, group, iam_role}`.
**When** migration `0005` is applied.
**Then** `scope` column is non-NULL on all rows AND values match:
- `cluster`/`organization` → 1
- `account`/`cloud` → 2
- `project`/`folder` → 3
- any per-domain `resource_type` (`vpc_network`, `compute_instance`, …) → 3
- IAM-subject `resource_type`s (`user`, `service_account`, `group`, `iam_role`) → 3 (via the `ELSE 3` fallback per design §3.7).

### S3.6 — `access_bindings.scope` enforces CHECK + NOT NULL

**Given** migration `0005` applied.
**When** attempting `INSERT INTO access_bindings(..., scope=4)`.
**Then** SQLSTATE `23514` referencing `access_bindings_scope_ck`.
**And** `INSERT INTO access_bindings(... no scope ...)` returns SQLSTATE `23502` (NOT NULL).

### S3.7 — Migration is idempotent (re-run is no-op)

**Given** migration `0005` is applied successfully on a non-empty schema.
**When** `DELETE FROM goose_db_version WHERE version_id = 5;` is executed (forcing goose to re-apply), THEN `goose up` is invoked a second time.
**Then** the migration body completes without error AND `SELECT COUNT(*) FROM kacho_iam.roles` returns the same value as after the first run AND `SELECT COUNT(*) FROM kacho_iam.access_bindings` returns the same value AND `SELECT COUNT(*) FROM kacho_iam._pre_rbac_v2_roles` is unchanged (the backup `INSERT … SELECT *` is wrapped in `ON CONFLICT (id) DO NOTHING` or the table is `TRUNCATE`d before the INSERT so the backup is overwritten, not duplicated — implementation MUST pick one and the test asserts the chosen behaviour) AND `roles_permissions_valid` CHECK is still attached.

### S3.8 — Backup tables carry pre-state

**Given** migration `0005` is applied to a non-empty schema.
**Then** `kacho_iam._pre_rbac_v2_roles` and `kacho_iam._pre_rbac_v2_access_bindings` exist, are non-empty, and carry the pre-migration data (verify by row count match against the saved snapshot).

### S3.9 — Migration 0026 drops the four target tables

**Given** migration `0005` is applied (so the v2 grammar is enforced).
**And** the four target tables exist (seeded by older migrations).
**When** migration `0006` is applied.
**Then** `SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='kacho_iam' AND table_name=$1)` returns FALSE for each of: `scim_user_mappings`, `scim_gdpr_reviews`, `organization_saml_configs`, `cluster_break_glass_grants`.
**And** any associated INDEX/CONSTRAINT/SEQUENCE is also gone (verified via `pg_indexes`, `pg_constraint`, `pg_sequences`).

### S3.10 — `roles.permissions` does not contain any 3-segment or malformed row post-migration

**Given** migration `0005` is applied across all seeded data of the deployed environment.
**When**
```sql
SELECT id FROM kacho_iam.roles
WHERE EXISTS (
  SELECT 1 FROM jsonb_array_elements_text(permissions) p
  WHERE array_length(string_to_array(p,'.'),1) <> 4
     OR p ~ '^\\.|\\.\\.|\\.$'      -- empty segment (leading/inner/trailing dot)
     OR p !~ '^(\\*|[a-zA-Z][a-zA-Z0-9_-]*)\\.(\\*|[a-zA-Z][a-zA-Z0-9_-]*)\\.(\\*|[a-zA-Z0-9_-]+)\\.(\\*|[a-z][a-zA-Z0-9_-]*)$'
);
```
**Then** zero rows returned.

### S3.11 — Validate-or-abort: a malformed row blocks the migration without data loss (design §3.7 step 5)

**Given** seed contains a row with a 5-segment permission (`'["a.b.c.d.e"]'`) that cannot be promoted by the v2 validator.
**When** migration `0005` is applied.
**Then** the migration transaction aborts (non-zero exit; SQLSTATE `23514` on the re-attach of `roles_permissions_valid`).
**And** the original row is preserved unchanged in `kacho_iam.roles` (transaction rolled back).
**And** the audit-snapshot row exists in `kacho_iam._pre_rbac_v2_roles` (created BEFORE the failing UPDATE-then-CHECK; if the backup INSERT is inside the same transaction, it MAY also be rolled back — in that case the migration script MUST log the offending row id to PG `RAISE NOTICE` so the operator can find it in the migration logs).
**And** the operator can manually fix the row and re-run.

### S3.12 — fga_outbox catch-up (design §3.7 step 6)

> **Scope decision**: design §3.7 step 6 ("Rebuild `fga_outbox`: enqueue re-emit jobs for every active AccessBinding so the FGA store gets the new tuple shape") MOVES TO **W4** (kacho-iam code wave), where the new emit logic lives. W3 is schema-only; the catch-up SQL alone without the new emit code would write stale tuples. Acceptance doc [[KAC-217]] / W4 picks up this scenario.

**No-op for W3.** This scenario is intentionally moved out of W3 scope; see W4 acceptance doc for the actual GWT.

## Definition of Done

- [ ] Branch `KAC-216-rbac-v2-migrations` exists; commits per Plan §Wave 3 tasks 3.1..3.4.
- [ ] Integration tests cover scenarios S3.1..S3.11; PR body shows the RED→GREEN pair (test fails first with migration-missing, passes after migration body added) for at least S3.1, S3.3, S3.5, S3.6, S3.11 per workspace CLAUDE.md §«Запреты» #12.
- [ ] PR `PRO-Robotech/kacho-iam#<N>` open; CI green (`make test` + lint).
- [ ] PR URL added to [[KAC-216]] frontmatter `prs:`.
- [ ] [[KAC-216]] → `In Progress` at PR-open; → `Done` after merge.
