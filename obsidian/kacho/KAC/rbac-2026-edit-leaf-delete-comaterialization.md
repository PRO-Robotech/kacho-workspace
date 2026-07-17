---
title: "RBAC — v_delete co-materialized with v_update on leaf objects (edit@project delete-403)"
ticket_id: rbac-2026-edit-leaf-delete
status: test
type: fix
repos:
  - kacho-iam
prs: []
opened: 2026-07-17
tags:
  - kac
  - kacho-iam
  - fix
  - usecase
---

# RBAC — leaf-editor `v_delete` co-materialization (BUG #1) + account-owner content check (BUG #2)

**Status**: test (branch `qa/iam-acb-fixture-green`, not pushed)
**Type**: fix — materialization-logic defect in the reconciler tuple builder.
**Continues**: [[rbac-2026-contract-a-fix-iam-content-forward]], [[rbac-2026-224-owner-wildcard-content]]

## BUG #1 (DOMINANT, suite-wide delete-403) — FIXED

Creator of a resource holds the system **`edit`@project** role. Migration `0040` widened the
edit roles from `["update"]` → `["get","list","update"]` (read verbs, so an editor can read what
it edits under the decoupled verb-bearing model) but **omitted `delete`**. The reconciler
materializes EXACTLY a role's authored verbs (`reconcile/tuples.go::ruleObjectTuples` iterates
`sel.Verbs`), so a freshly-created object got `{v_get, v_list, v_update, editor}` and **never
`v_delete`** → every `delete`/cleanup of the creator's OWN resource 403'd
`lacks relation "v_delete" … current direct relations: [v_get, v_list, v_update, editor]`
(uniform across vpc network/subnet/sg/route-table/address/nic + nlb lb/listener/target-group).

**Root**: `services/iam/internal/apps/kacho/api/access_binding/reconcile/tuples.go`
`ruleObjectTuples` — the per-object verb loop emitted only the authored closed verbs; the edit
role's authored set lacked `delete`. Pre-existing (migration 0040, 2026), **not** a regression of
the owner-tuple commits `d4b8f84`/`f06c1a0` (those touched batch atomicity + idempotent sync-write,
not the verb set).

**Fix**: co-materialize `v_delete` with `v_update` at the single materialization path
(`ruleObjectTuples`): a grant that carries `v_update` on an object also carries `v_delete`
(create.go:435 invariant — a CRUD editor deletes what it edits). This does NOT touch the
back-compat tier (stays `editor`, no admin escalation), needs NO migration / no role-fingerprint
change, and is fail-closed (only a grant that already updates gains delete).

**Anti over-grant**: EXCLUDED the hierarchy scopes `account`/`project` (`isHierarchyScopeType`).
`ProjectService/AccountService.Delete` gate `v_delete` **on the scope object** (permission
catalog), so auto-adding `v_delete` there would let a project-editor delete the project. An
edit-tier grant on `account`/`project` (scope-self OR as content of an account-owner binding)
keeps update but not delete; only a role that explicitly authored `delete` (owner/admin `*.*`)
retains it (the verb loop already emits it → the addition is purely additive for leaf types).

## BUG #2 (account-owner → project/service_account) — NOT a static defect on HEAD

Investigated with a testcontainers matrix + a full-flow e2e (real Account.Create → ServiceAccount.
Create). The reconciler **correctly** materializes the account-owner's per-object `v_*`+`admin` on
`iam.project` and `iam.serviceAccount`: owner-role selectors cover the iam-native types
(migrations 0038/0039 → `AllMaterializableTypes`), `FeedSourceForType("iam.*")=FeedIAMDirect`,
`MatchAllInScopeIAMDirect`+`IsContainedIn(account)` include them, and the forward triggers
(`project.Create`/`serviceAccount.Create` → `reconcileObject`) are wired. All 3 BUG #2 tests are
GREEN on HEAD → the live 403 on the stand is a stale-build / non-materialization issue, not a
static logic defect. `service_accounts.account_id` is `NOT NULL`, so there is no transitive-account
gap for SAs analogous to the mirror fix `8d44019`.

## Затронутые сущности vault
- [[iam-access-binding]] — reconciler per-object verb set (adds `v_delete` for leaf editors).
- [[rbac-2026-contract-a-fix-iam-content-forward]] — account-owner iam-content forward-mat (BUG #2 path).

## Артефакты
- `services/iam/internal/apps/kacho/api/access_binding/reconcile/tuples.go` (fix + `isHierarchyScopeType`).
- `services/iam/internal/repo/kacho/pg/reconcile_materialization_matrix_integration_test.go` (matrix: BUG#1 RED→GREEN + anti-over-grant + BUG#2 GREEN guards).
- `services/iam/internal/apps/kacho/api/access_binding/account_owner_content_e2e_integration_test.go` (BUG#2 full-flow e2e, GREEN).

## DoD
- [x] RED matrix on BUG #1 (v_delete missing), GREEN after fix.
- [x] Anti over-grant: no `v_delete` on `project`/`account` for edit-tier.
- [x] BUG #2 matrix + full-flow e2e GREEN (materialization correct on HEAD).
- [x] `go test ./services/iam/... -race -p1` + `golangci-lint` green (reconcile/pg/access_binding suites verified).
