---
title: "Explicit RBAC model 2026 (epic)"
aliases:
  - rbac-explicit-model-2026
  - explicit-rbac-epic
ticket_id: "(epic — acceptance-anchored, MCP youtrack unavail)"
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-deploy
  - kacho-ui
tags:
  - kac
  - epic
  - feature
  - kacho-iam
  - kacho-proto
  - kacho-api-gateway
  - security
  - architecture
---

# Explicit RBAC model 2026 (epic)

> [!note] Anchor
> Design+acceptance: `docs/specs/rbac-explicit-model-2026-acceptance.md` (43 сценария, D-1..D-18, 12 под-фаз). Re-touch эпика #109 (RBAC-rules-model). KAC-номер не заводился (MCP youtrack недоступен) — док + этот trail = anchor.

**Status**: 🔧 in-progress — **acceptance ✅ APPROVED (round-2, 2026-06-24)**. Merged: P1 proto deletion_protection (`6171077`), P2 FGA v_* (proto `6171077` + deploy #121), P3 authzmap verb-bearing (`e4fa354f`, #218), **P4 unified reconciler — ядро (`0ab8d20f`, #219)**: единый материализатор all/names/labels + выпил scope_grant-emit + scope-self tier + lock-ordering + grant-propagation; 4 ревью ✅, integration+newman зелёные (newman поймал реальный no-access-loss gap — scope-self tier на якоре). **P5 (Check flat + cluster-admin short-circuit + A-05 GLOBAL+all guard) — PR open, ждёт system-design + go-style ревью**.
**Type**: feature (foundational, cross-repo)

## Что и зачем
Переход kacho-iam authz с ReBAC-каскадной модели (FGA `<rel> from account/project/cluster` + scope_grant computed-usersets) на **явную RBAC с per-object материализацией**. Причина: implicit hierarchy-каскад = непредсказуемый over-grant (live-находки на fe3455) + тяжёлый аудит. Цель — топ-2026: явность, аудируемость, масштаб.

## Требования владельца (нормативно)
1. Семантика ролей сохраняется (rules: module/resources/verbs/selector).
2. Доступ выдаётся ЯВНО (per-object материализация, без implicit-каскада в семантике).
3. Селекторы сохраняются: all / names / labels.
4. Scope: GLOBAL / ACCOUNT / PROJECT (folder/organization — НЕТ, удалить).

## Ключевые design-решения
- **Грант = (subject, role, scope)**; scope = ГРАНИЦА материализации, не корень наследования.
- **Энфорс = единый reconciler-движок** (расширение T3.1) материализует прямые per-object FGA-tuple для all/names/labels × scope. `scope_grant`-эмиссия удаляется (КФ-3).
- **FGA = плоский индекс**: убрать `<rel> from …`-каскады + scope_grant.
- **account/project — verb-bearing** (v_get/v_list/…); tier только для membership-write-authz, без down-cascade доступа → «видно в селекторе без контента» выпадает само.
- **owner** = net-new системная cluster-роль `*.*.* selector=all @ ACCOUNT`, авто-binding на Account.Create (forward-материализация, пустой аккаунт на Create), **deletion_protection** (как vpc.address).
- **cluster super-admin** = единственное cluster-relation + Check short-circuit (исключение из per-object); применяется и к write-authz (КФ-2). Bootstrap — InternalClusterService (KAC-196); далее public binding@GLOBAL (requireGrantAuthority=cluster-admin).
- **GLOBAL+all** валиден только для cluster-admin; прочим на GLOBAL — names/labels обязательны (иначе InvalidArgument).
- **organization** — full-removal (proto OrganizationService + account/Role.organization_id + compliance/hooks/seed).
- **Миграция** = expand→migrate→contract, forward-only/idempotent, **singleton backfill под `pg_advisory_xact_lock`** (КФ-1), continuous forward-aware verify-gate (КФ-4), no-access-loss на проде fe3455. 63 system-роли re-seed.

## Декомпозиция (12 под-фаз, build-граф)
P1 proto (scope/deletion_protection, drop org) → P1b iam org-decommission → P2 FGA-модель flat (drop cascade+scope_grant+org) → P3 authzmap verb-bearing account/project → P4 reconciler all-selectors (drop scope_grant emit) → P5 Check flat + cluster-admin short-circuit (incl write-authz) → P6 owner + deletion_protection → P7 list-filter → P8 migration re-seed+backfill → P9 api-gateway → P10 deploy → P11 ui → P12 docs.

## Затронутые сущности vault
[[../resources/iam-role]] [[../resources/iam-access-binding]] [[../resources/iam-resource-mirror]] [[../rpc/iam-access-binding-service]] [[../rpc/iam-internal-iam-service]] [[sub-phase-T3.1-cross-service-label-revoke]] [[sub-phase-1.5-assignable-roles]]

## DoD (верхнеуровневый)
- [x] acceptance APPROVED (round-2 gate, оба ревьюера)
- [ ] P1..P12 под-фазы (каждая — свой acceptance + TDD + ревью + merge по build-графу)
- [ ] migration backfill 63 ролей + bindings + owner на существующие аккаунты (no-access-loss verify)
- [ ] deploy fe3455 + live-верификация (account/project в селекторе без контента; owner; cluster-admin; org отсутствует)
- [ ] vault trail per-под-фаза + закрытие

## P3 trail (authzmap verb-bearing account/project — expand)
- PR [kacho-iam#218](https://github.com/PRO-Robotech/kacho-iam/pull/218), ветка `rbac-p3-authzmap-verb-bearing`.
- `authzmap.TypeHasVerbRelations(account|project)` → true (D-6); drift-gate сверяет с моделью (P2 `6171077`); catalog отдаёт `hasVerbRelations=true`.
- **Insulation (#177 guard)**: emitter `scope_grant_tuples.go` ветка scope_grant гейтится на `tierScopeTypes`, НЕ на verb-bearing флаге — иначе dangling-write `sg_account@account:…` (модель не имеет sg_account/sg_project carrier). Прямая per-object v_* материализация (B-01/B-02) отложена в P4; binding-time scope_grant путь удаляется в P4 (КФ-3). Виалидировано system-design-reviewer.
- Файлы: `internal/authzmap/fga_types.go`, `internal/authzmap/fga_model_drift_test.go`, `internal/authzmap/verb_bearing_account_project_test.go` (new), `internal/apps/kacho/api/access_binding/scope_grant_tuples.go` (insulation), `internal/apps/kacho/api/permission_catalog/usecase_test.go`.
- Каскад / viewer-tier-эмиссия / scope_grant — **НЕ тронуты** (P-contract / P4).

## P4 trail (unified reconciler — ядро / КФ-3, D-4)
- PR [kacho-iam#219](https://github.com/PRO-Robotech/kacho-iam/pull/219), ветка `rbac-p4-unified-reconciler`. **PR open** — ждёт db-architect + system-design ревью.
- **Единый материализатор**: reconciler материализует прямые per-object FGA-tuple (`<type>:<id> # v_*/tier @ subj`) для ВСЕХ селекторов — ARM_ANCHOR(all)+ARM_NAMES+ARM_LABELS × scope-границу. `desiredMembers` диспетчеризует по арму (all→`MatchAllInScope`, names→`MatchByIDs`, labels→`MatchSelector`); containment re-verify по scope.
- **scope_grant emit удалён ЦЕЛИКОМ** (D-4): `scope_grant_tuples.go` удалён; `buildBindingTuples` rules-ветка → только hierarchy parent-pointer (membership-write-authz, D-7). Obsolete scope_grant unit/FGA-тесты удалены, FGA-harness → `fga_test_helpers_test.go`. **FGA-модель-каскад НЕ тронут** (contract-фаза §9).
- **forward-materialization** (C-01b): `role_rule_selectors` (mig **0034** += `arm`+`resource_names`, arm-aware shape CHECK) хранит ВСЕ армы → fast-path `SelectorBindingsMatchingObject` arm-aware (anchor→type, names→type+id, labels→type+labels) → ресурс, созданный ПОСЛЕ гранта, материализуется на mirror-change event.
- **КФ-1**: `pg_advisory_xact_lock(hashtext(binding_id))` (xact-scoped) первым стейтментом reconcile-tx + SELECT FOR UPDATE + ledger PK backstop → exactly-once под N репликами (H-05).
- **ВЗ-3 co-commit**: материализация + ledger + outbox + advisory-lock — одна reconcile writer-tx.
- TDD: `reconcile_unified_p4_integration_test.go` (8 testcontainers: A-01/A-02/A-04/C-01b×2/E-03/H-05) RED→GREEN; unit anchor/names/labels+lock. Регрессия C-22..C-26/DB1/DB2 зелёные.
- Файлы: `internal/domain/rule_fingerprint.go` (`MaterializingSelectors`/`RuleSelector`), `internal/apps/kacho/api/access_binding/reconcile/reconcile.go`, `internal/repo/kacho/pg/reconcile_adapter.go`, `internal/repo/kacho/pg/resource_mirror/reader.go`, `internal/repo/kacho/pg/role_repo.go` (`ReplaceRuleSelectors([]RuleSelector)`), `internal/repo/kacho/role/iface.go`, `internal/migrations/0034_role_rule_selectors_all_arms.sql`, `internal/apps/kacho/api/{role,access_binding}/*.go`.
- **Отложено в follow-up**: A-05 GLOBAL+all sync INVALID_ARGUMENT (требует sync role-read в Create.Execute — отдельная request-path-поверхность). → **закрыто в P5**.

## P5 trail (Check flat + cluster-admin short-circuit + A-05 — D-9/D-06/D-07/КФ-2)
- Ветка `rbac-p5-check-shortcircuit` от `0ab8d20f`. PR open — ждёт system-design + go-style.
- **Плоский super-gate `authzguard.IsClusterAdmin`/`SubjectIsClusterAdmin`** (`internal/authzguard/cluster_admin_shortcircuit.go`): одна relation-Check `cluster:cluster_kacho_root#system_admin@subj` (НЕ `<rel> from cluster`-каскад). fail-closed (nil checker/anon/empty/Check-err → false). ctx-вариант (write-authz) + subject-string-вариант (Check).
- **Check + write-authz применение (КФ-2)**:
  - `authorize_service.Check` + `CheckRelation` → short-circuit ALLOW до per-object резолва (D-02); `AuthorizeServiceConfig.ClusterAdminChecker` (nil-safe, additive); wired `relationStore` в `cmd/kacho-iam/wiring.go`.
  - `requireGrantAuthority` (Path 0) + `fgaHoldsAdmin` (`helpers.go`) → cluster-admin проходит на чужой account (D-06) и над `iam_access_binding`-объектами (D-07). Additive РЯДОМ с owner/FGA-admin путями (каскад не тронут — expand §9).
- **A-05/A-05b/A-05c sync-валидация** (`CreateAccessBindingUseCase.validateGlobalAllSelector`, `create.go` request-path до Operation): GLOBAL(=cluster scope) + ARM_ANCHOR(selector all) + роль НЕ `*.*.*` → sync `INVALID_ARGUMENT` «GLOBAL scope requires names or labels selector for non-cluster-admin roles». GLOBAL+names/labels (A-05b) OK; GLOBAL+all для `*.*.*` cluster-admin роли (A-05c) OK. Domain-предикаты `Rules.HasAnchorRule()` + `Role.IsClusterAdminRole()` (`internal/domain/role_cluster_admin.go`, system-gated). NB: в proto/domain **нет GLOBAL-tier** — GLOBAL == cluster scope (`resource_type=="cluster"`, `cluster_kacho_root`).
- **Guard-test dead cluster scope-self** (scope item 5): `scopeSelfTuples` cluster-ветка была недостижима (gated на `iam.cluster` ∉ objectTypes) → ветка удалена с явным комментарием «cluster обслуживается D-9», добавлен guard-тест `scope_self_cluster_guard_test.go` (cluster scope-self не эмитит per-object — страхует Q-2/D-9 от регрессии при будущем `iam.cluster`).
- **Expand-дисциплина**: FGA-модель-каскад НЕ тронут (contract §9); short-circuit additive.
- TDD RED→GREEN: unit `role_cluster_admin_test.go`, `cluster_admin_shortcircuit_test.go` (authzguard + access_binding), `authorize_shortcircuit_test.go` (service), `create_global_all_validation_test.go` (A-05/A-05b/A-05c), guard-test reconcile. newman A-05 negative `IAM-ACB-CR-GLOBAL-ALL-NONADMIN-REJECT` (cluster GLOBAL+all с ROLE_VIEW `*.*.{get,list,read}` → 400); A-05c happy = существующий `IAM-ACB-CR-CLUSTER-OK` (ROLE_ADMIN `*.*.*`). build/vet/gofmt + `-race` зелёные; access_binding+cluster integration (testcontainers) зелёные.
- Файлы: `internal/domain/role_cluster_admin.go`(+test), `internal/authzguard/cluster_admin_shortcircuit.go`(+test), `internal/service/authorize_service.go`(+test), `internal/apps/kacho/api/access_binding/{helpers,create}.go`(+tests), `internal/apps/kacho/api/access_binding/reconcile/tuples.go`(+guard-test), `cmd/kacho-iam/wiring.go`, `tests/newman/cases/iam-access-binding.py`.

## Связанные
- [[sub-phase-T3.1-cross-service-label-revoke]] — materialization-движок (фундамент)
- [[sub-phase-1.5-assignable-roles]] — assignability
- эпик #109 (RBAC-rules-model) — этот эпик его re-touch
- follow-up: api-gateway#96 (поглощается), kacho-iam#217, kacho-vpc#165

#kac #epic #feature #kacho-iam #security #architecture
