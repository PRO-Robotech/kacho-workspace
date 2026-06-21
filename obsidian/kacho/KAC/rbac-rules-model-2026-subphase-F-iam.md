---
title: RBAC rules-model 2026 — sub-phase F clean-cut (iam + proto)
ticket_id: rbac-rules-model-2026-F-iam
status: test
type: feature
repos:
  - kacho-proto
  - kacho-iam
prs:
  - https://github.com/PRO-Robotech/kacho-proto/pull/77
  - https://github.com/PRO-Robotech/kacho-iam/pull/200
yt_url: https://github.com/PRO-Robotech/kacho-iam/pull/200
opened: 2026-06-21
tags:
  - kac
  - kacho-iam
  - kacho-proto
  - feature
  - usecase
  - repo
  - proto
  - migrations
  - handler
  - breaking
---

# RBAC rules-model 2026 — sub-phase F clean-cut (iam + proto)

**Status**: test (branches `rbac-rules-f-cleancut` in kacho-proto + kacho-iam; PRs proto#77 / iam#200)
**Type**: feature — epic «RBAC rules-model 2026», sub-phase F = **clean-cut / hard-cut (O-9)**, pre-prod, no live data
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` §«ПОД-ФАЗА F» F-50..F-54 (APPROVED 2026-06-21)

## Что и зачем

`role.rules[]` (sub-phases A–C) становится **единственным источником истины** для object-selection.
Весь legacy AccessBinding target/selector аппарат (epic-100 α/γ) удалён целиком в один проход.
A–E (rules[]/scope_grant/per-object List/subjects[]/ExpandAccess/ListByRole) НЕ затронуты.

## proto (kacho-proto#77 — НАМЕРЕННЫЙ buf breaking, F-54)

- **Remove RPC** `AddTargetResources`/`RemoveTargetResources`/`ReplaceTargetSelector`/`ListGrantableResources` (+ req/resp messages).
- **Rename** `ListByResource`→`ListByScope` (RPC + `ListAccessBindingsByScopeRequest` + REST `:listByScope` + permission key).
- **Remove fields** `AccessBinding.target=16`/`target_ref=18`, `CreateAccessBindingRequest.target=9`/`target_ref=11` → `reserved` tombstone (tags + names `target`/`target_ref`/`selector`).
- **Remove messages** `AccessTarget`/`AccessTargetRef`/`TargetResourceRef`/`TargetResourceRefList`/`ResourceSelector`/`AllInScope`/`GrantableResource`.
- `Role.permissions=5` остаётся `[deprecated=true]` (read-empty + write-reject в iam; колонка пишется внутренне для FGA-эмиссии).
- buf lint/generate зелёные; `buf breaking` СИГНАЛИТ (документированный override в `buf.yaml` + CI `continue-on-error`); `scripts/tombstone_enforce.sh` (CI) — reserved tag/name reuse FAILS `buf lint`.

## iam (kacho-iam#200)

- **migration 0030** — DROP `access_binding_targets` (0018) + `access_binding_selector` (0022); KEEP `access_binding_target_members` (rules-reconciler ARM_LABELS membership). access_bindings.scope (0005) KEPT (backs scope_ref).
- **migration 0031** — re-seed `rules[]` ВСЕХ system-ролей (58 catalog + 5 SEC-C module-SA mig 0009 = 63) через **идемпотентный keyed UPDATE** — НЕ DELETE, НЕ трогает permissions[], id 1:1 стабилен. Сохраняет FK-child (cluster-admin 0004 / module-SA 0009) + tuple-based (operator-SA 0010 / reader-SA 0014).
- удалены target-мутатор handlers/use-cases/repo; `ListByResource`→`ListByScope`; excise legacy target/selector arms из create/reconcile/reconcile_adapter (legacy `access_binding_selector` UNION-arm убран, `role_rule_selectors` оставлен)/role_tuple_reconciler/dto/domain.AccessBinding.Target.
- nlb verb-tier fix (`domain.rule_verbs`): `listOperations`/`getTargetStates`→viewer (parity с `authzmap.verbClass` + consumer authz-gate; убирает editor-over-viewer escalation, найденный tier-parity тестом).
- оба `permission_catalog.json` (internal_iam/embedded + seed/embedded) синканы из proto.

## tier-parity (F-53, load-bearing)

Для каждой system-роли: `domain.ResolveVerbsAndTier(rule.Verbs)` per (module,resource) == legacy `authzmap.verbClass`/`PermissionsToRelations` tier. Параметризован по фактическим seeded-строкам (`tier_parity_integration_test.go`), все 63 проходят.

## RED→GREEN

- F-51: tables-present (RED) → mig 0030 → dropped, `_target_members` survives (GREEN).
- F-53 tier-parity: RED поймал 5 пропущенных module-SA ролей + 3 nlb tier-escalation → fix re-seed + nlb verb tier → GREEN (все system-роли).
- F-53 access-not-severed: count system-ролей + FK-child bindings стабилен на idempotent re-apply; det. id стабильны.
- F-52: DTO empty-permissions GREEN.
- scope_grant real-OpenFGA F-53 Check (allow in-rules / deny outside) GREEN.
- newman F-50..F-53 + legacy cases removed/renamed + регенерены.

## Затронутые сущности vault

- [[iam-access-binding-service]] — RPC: -4 target-мутатора, ListByResource→ListByScope.
- [[iam-access-binding]] — поля target/target_ref удалены (reserved tombstone); selection целиком в role.rules.
- [[iam-role]] — system-роли несут rules[]; permissions[] internal-only (read empty).
- [[rbac-rules-model-2026-subphase-A-iam]], [[rbac-rules-model-2026-subphase-C-iam]], [[rbac-rules-model-2026-subphase-E-iam]] (предшествующие, не сломаны).

## Осталось (НЕ в этих PR)

- api-gateway: снять target-мутатор-роуты + register `ListByScope` (`api-gateway-registrar`).
- kacho-ui: rules-editor + subjects[]-форма (F-22) — отдельная ветка (trail [[rbac-rules-model-2026-subphase-F-ui]]).
- kacho-deploy: FGA re-bootstrap + fe3455 rollout (без flag-flip).
- После merge proto#77 → revert CI pin kacho-proto на `main` в iam workflows.

## DoD

- [x] proto buf lint/generate зелёные, breaking-override задокументирован, tombstone-enforce CI.
- [x] iam go build/vet/gofmt clean; unit -short green; targeted integration (Postgres + real OpenFGA, colima) green.
- [x] migration 0030/0031 forward-only (ban #5); idempotent UPSERT без DELETE.
- [x] newman F-cases gen.
- [x] 2 PR (proto#77, iam#200), CI pin kacho-proto→F.
- [ ] api-gateway / ui / deploy (отдельные).
- [ ] reviewer gates (proto-api-reviewer / db-architect-reviewer / go-style-reviewer / system-design-reviewer).
