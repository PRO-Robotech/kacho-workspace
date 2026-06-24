---
title: "RBAC explicit-model 2026 — sub-phase P6 (owner role + auto-binding + deletion_protection) iam"
aliases:
  - rbac-p6-owner-deletion-protection
  - rbac-explicit-2026-P6
ticket_id: "(epic — acceptance-anchored, MCP youtrack unavail)"
category: kac
status: test
type: feature
repos:
  - kacho-proto
  - kacho-iam
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-proto
  - security
  - architecture
---

# RBAC explicit-model 2026 — sub-phase P6 (iam)

> [!note] Anchor
> Epic: [[rbac-explicit-model-2026]]. Acceptance: `docs/specs/rbac-explicit-model-2026-acceptance.md` §0 D-8/D-8a/D-10, §4 C-01/C-01b/C-02/C-03/C-04, §10 P6.

**Status**: 🧪 test — код-комплит на ветках; integration (testcontainers) зелёные; unit зелёные; newman happy+neg добавлены. Pending: db-architect + system-design + go-style ревью → merge.
**Type**: feature

## Что и зачем
- **owner system-role** (net-new, D-8): cluster-scoped `is_system`, rules `[{module:*, resources:[*], verbs:[*]}]` (`*.*.*` selector all), permissions `["*.*.*.*"]` (4-segment grammar mig 0005). Детерминированный id `rol72122ce96bfec66e2` (`rol||md5('owner')[:17]`).
- **Account.Create auto-binding** (C-01 / ВЗ-3): owner AccessBinding (subject=creator, role=owner, scope=ACCOUNT:<A>, `deletion_protection=true`) co-commit в ОДНОЙ writer-tx с account INSERT + audit + FGA owner-tuple. Per-object доступ материализуется FORWARD reconciler'ом post-commit (scope-self verb-bearing на `account:<A>` + ARM_ANCHOR над содержимым — C-01b, единый P4-путь).
- **deletion_protection** (D-10): колонка `access_bindings.deletion_protection` (migration 0035). Delete на protected → sync FAILED_PRECONDITION + атомарный CAS-backstop `DELETE … WHERE deletion_protection=false` (C-02/C-04, образец vpc.address.DeleteGuarded). Снятие — `Update(update_mask=["deletion_protection"], false)` (C-03, новый RPC).

## Затронутые сущности vault
- [[resources/iam-access-binding]] — новое поле `deletion_protection`; новый RPC Update; DeleteGuarded CAS.
- [[resources/iam-role]] — net-new system-роль `owner`.
- [[rpc/iam-access-binding-service]] — `+rpc Update (UpdateAccessBindingRequest)`.
- [[packages/iam-domain]] — `AccessBinding.DeletionProtection`, `OwnerRoleID` const.
- [[packages/iam-repo-kacho-pg]] — `DeleteGuarded`, `SetDeletionProtection`, abCols/scanAB/Insert +deletion_protection.

## Артефакты
- proto branch `rbac-p6-update-deletion-protection` (`e11971c`): `AccessBindingService.Update` + `UpdateAccessBindingRequest`/`UpdateAccessBindingMetadata`; buf lint+breaking green; gen регенерирован.
- iam branch `rbac-p6-owner-deletion-protection`: migration 0035; domain field+const; repo CAS+set; delete sync-precheck+guard; account owner auto-bind co-commit+reconcile; Update use-case+handler; wiring.
- Tests: `pg/access_binding_deletion_protection_integration_test.go` (CAS + concurrent race C-04), `pg/owner_role_seed_integration_test.go`, `pg/account_owner_binding_integration_test.go` (co-commit + rollback ВЗ-3), `access_binding/account_owner_binding_e2e_integration_test.go` (use-case C-01), `access_binding/deletion_protection_test.go` (unit C-02/C-03 mask). Newman: `IAM-ACB-DP-NEG-DELETE-PROTECTED`, `IAM-ACB-DP-CRUD-CLEAR-THEN-DELETE`.

## RED→GREEN
- RED1: missing `DeletionProtection`/`DeleteGuarded`/`SetDeletionProtection`/`OwnerRoleID` (compile). GREEN: domain+repo+const.
- RED2: migration 0035 `roles_permissions_valid` 23514 на `["*.*.*"]` (3-segment). GREEN: 4-segment `["*.*.*.*"]` (mig 0005 grammar).
- RED3: owner seed RoleName type-assert. GREEN: `string(role.Name)`.

## Ревью
- **db-architect-reviewer**: ✅ APPROVED (migration additive/idempotent; DeleteGuarded CAS race-safe; owner seed satisfies all CHECKs; concurrent test genuine).
- **go-style-reviewer**: ✅ APPROVED (error-wrap/ctx/slog/thin-handler/clean-arch OK; non-blocking nit: `OwnerBindingReconciler` дублирует `SelectorReconciler` — оставлено как consumer-owned port).
- **system-design-reviewer**: ✅ APPROVED-с-замечаниями (distributed core OK; DIST-1 + DIST-2 закрыты в этом PR).
- **proto-api-reviewer**: (in-flight) для `AccessBindingService.Update`.

### DIST-1 (закрыто): owner content-access = FGA tier-cascade, не per-object
owner `*.*.*` → `dottedTypes` пуст → reconciler материализует только scope-self на `account:<A>`; доступ к содержимому (включая late-created) — через FGA каскад `account.admin(or owner) → project.admin from account → <leaf>.admin from project`. **No-access-loss**. Расхождение с буквой C-01b (per-object) — by-design: `docs/architecture/owner-role-content-access-cascade.md` (тот же класс что D-9 cluster-admin; per-object `*.*.*` cluster-wide = unbounded churn — анти-паттерн A-05).

### DIST-2 (закрыто): concurrent delete-vs-rearm
`TestAB_P6_DeleteVsRearm_ConcurrentCAS` — SetDeletionProtection(true) ↔ DeleteGuarded; row-lock сериализует: Delete победил (gone, rearm→NotFound) ЛИБО rearm победил (protected, Delete→FailedPrecondition). Никогда «удалён И защищён».

## Кросс-репо
- proto branch `rbac-p6-update-deletion-protection` (`e11971c`) — merge первым (build-граф).
- iam branch `rbac-p6-owner-deletion-protection`.
- api-gateway branch `rbac-p6-accessbinding-update`: Update на PUBLIC mux (allowlist + REST PATCH /iam/v1/accessBindings/{id} + перегенерён permission_catalog); TDD RED→GREEN. CI ref-pin proto→feature до merge.

## DoD
- [x] migration forward-only idempotent (`IF NOT EXISTS` + `ON CONFLICT DO NOTHING`).
- [x] CAS-guard (не TOCTOU) + concurrent тест (delete-vs-delete + delete-vs-rearm).
- [x] co-commit ВЗ-3 (account+binding атомарно) + rollback-тест.
- [x] unit + integration + newman в том же PR.
- [x] db-architect + system-design + go-style review ✅ (proto-api in-flight).
- [x] DIST-1 by-design doc + DIST-2 concurrent test.
- [ ] merge (proto → iam → api-gateway) + deploy P10 + ui P11.
