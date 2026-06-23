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

**Status**: 🔧 in-progress — **acceptance ✅ APPROVED (round-2, оба ревьюера, 2026-06-24)**. P1 (proto expand `6171077`) + P2 (FGA-модель v_* на account/project) merged; **P3 (authzmap verb-bearing account/project) — PR [kacho-iam#218](https://github.com/PRO-Robotech/kacho-iam/pull/218), expand**.
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

## Связанные
- [[sub-phase-T3.1-cross-service-label-revoke]] — materialization-движок (фундамент)
- [[sub-phase-1.5-assignable-roles]] — assignability
- эпик #109 (RBAC-rules-model) — этот эпик его re-touch
- follow-up: api-gateway#96 (поглощается), kacho-iam#217, kacho-vpc#165

#kac #epic #feature #kacho-iam #security #architecture
