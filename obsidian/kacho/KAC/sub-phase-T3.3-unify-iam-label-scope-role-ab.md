---
title: sub-phase T3.3 — unify IAM label-scope (role + access_binding, chunk 2)
status: done
type: feature
repos:
  - kacho-iam
  - kacho-proto
tags:
  - kac
  - kacho-iam
  - feature
  - done
---

# sub-phase T3.3 — unify IAM label-scope (chunk 2: role + access_binding)

> [!note] Sub-record. Сводный trail и merge-статус — [[DIVERGENCE-A-unify-iam-label-scope]]
> (MERGED proto#89 / iam#249 `b4164e0f` / api-gateway#102 / deploy#135). Этот файл —
> узкая запись chunk-2 реализации (Role + AccessBinding).

Branch `unify-iam-label-scope` (kacho-iam). Acceptance:
`docs/specs/sub-phase-T3.3-unify-iam-label-scope-acceptance.md`.
Делает **Role** и **AccessBinding** label-selectable (own-resource `labels`),
вслед за уже-сделанными ServiceAccount (chunk-0) и User (chunk-1) на той же ветке.

## Что и зачем

Единая модель видимости для всех iam-типов: каждый несёт own-resource `labels`
(tenant-facing метки), делающие ресурс label-selectable наравне с account/project
(label-грант на `iam.<type>` материализует `v_list` по `labels @> matchLabels`).
Role.labels ≠ Rule.matchLabels (object-selector внутри грант-правила) — разные концепты.

## Реализация (chunk 2)

- **Role**: `roles.labels` round-trip (`roleCols` + scan + Insert + `roleUpdateSet`
  mutable `labels`); `UpdateRoleRequest.labels` mutable через `update_mask`; co-commit
  reconcile-event `iam.role` при label-change. Create/Update handler маппят
  `req.GetLabels()`. List уже `viewer ∪ v_list` (эталон #193, не тронут).
- **AccessBinding**: `access_bindings.labels` round-trip + `abWriter.UpdateLabels`
  (single-statement CAS, row-lock); **mutable set расширен до `{deletion_protection,
  labels}`** (T3.3-IMM-01) — иной mask путь → `INVALID_ARGUMENT`; co-commit
  reconcile-event `iam.accessBinding`. **List `viewer ∪ v_list ∪ self/granted-floor`**
  (D-6): `ListByScope`/`ListByAccount` — authority → all; не-authority → v_list-subset,
  пустой → `PermissionDenied` (anti-leak); `Get` — self ∪ grant-authority ∪ v_list.
  `WithRelationQueries(relationStore)` wired в composition root.
- migration 0041 (labels jsonb + CHECK + GIN) уже на ветке (chunk-0); feed_registry +
  reconciler iam-direct (scan-specs + `IAMDirectSelectorBindingsMatchingObject
  hasLabels=true`) уже покрывают `iam.role`/`iam.accessBinding`.

## AB.Get authz-модель (для system-design review)

AB.Get/List оставлены на `self ∪ requireGrantAuthority`, **дополнены** D-6 label-путём
(`viewer ∪ v_list` на `iam_access_binding`) — НЕ заменены. requireGrantAuthority
сохраняет cluster-admin short-circuit + owner/FGA-admin. Это additive (union floor),
согласуется с gateway, который уже Check'ает v_get на AB.Get; existing anti-leak
(`ListBySubject` self-floor, ungranted-stranger → PermissionDenied) сохранён.

## Тесты (RED→GREEN, ban #12)

- integration (testcontainers): `role_labels_integration_test.go` +
  `access_binding_labels_integration_test.go` — round-trip, label-grant → matching set,
  foreign-account containment REJECTED, eager fall-out, concurrent UpdateLabels. 8/8 GREEN.
- unit: `role/update_labels_test.go`, `access_binding/update_labels_test.go` (IMM-01),
  `access_binding/list_vlist_floor_test.go` (D-6 union + AUTHZ-02 Unavailable).
- newman: `iam-role.py` (+labels Update/List, +bad-labels neg), `iam-access-binding.py`
  (+Create/Update labels, +roleId-immutable neg).

## Затронутые сущности vault

- [[resources/iam-role]] · [[resources/iam-access-binding]]
- [[rpc/iam-role-service]] · [[rpc/iam-access-binding-service]]
- **НЕ** заводится `edges/iam-to-iam` (iam-direct same-DB, нет self-ребра, ацикличность).

## Остаётся

- api-gateway: публичная регистрация `UserService.Update` (chunk-1 D-1a) —
  отдельный шаг `api-gateway-registrar`.
- Полный e2e (newman через стенд); ревью ролями (db-architect / go-style /
  system-design / proto-api).
