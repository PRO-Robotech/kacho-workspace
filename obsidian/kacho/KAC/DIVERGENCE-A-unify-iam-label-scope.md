---
title: DIVERGENCE-A — unify IAM label-scope (all iam-types label-selectable)
status: done
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-deploy
prs:
  - "PRO-Robotech/kacho-proto#89"
  - "PRO-Robotech/kacho-iam#249"
  - "PRO-Robotech/kacho-api-gateway#102"
  - "PRO-Robotech/kacho-deploy#135"
tags:
  - kac
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-deploy
  - feature
  - done
---

# DIVERGENCE-A — unify IAM label-scope

Acceptance (APPROVED): `docs/specs/sub-phase-T3.3-unify-iam-label-scope-acceptance.md`.
**MERGED** to main: kacho-proto#89 · kacho-iam#249 (squash `b4164e0f`) ·
kacho-api-gateway#102 · kacho-deploy#135.

## Что и зачем

Владелец потребовал **единую модель видимости для ВСЕХ iam content-типов**
(`iam.user`/`iam.serviceAccount`/`iam.group`/`iam.role`/`iam.accessBinding`) — такую же,
как у эталона `iam.account`/`iam.project`:

1. **Все 5 типов label-selectable** — own-table `labels @> matchLabels`, материализация
   **iam-direct same-DB** (НЕ через `resource_mirror`). Это **реверс решения O-4**
   (`feed_registry.go` ранее держал iam content-типы в `iamContentMaterializableTypes`
   как НЕ label-selectable). Типы перенесены в `labelSelectableTypes`.
2. **Новый публичный `UpdateUser` RPC** (D-1a) — `UserService` ранее не имел публичного
   write. `PATCH /iam/v1/users/{user_id}`, async → `Operation`, flat request
   `{user_id, update_mask, labels}`. `labels` — единственное mutable; `external_id`
   (IdP `sub`) и иные IdP-mirror — hard-immutable (→ `INVALID_ARGUMENT
   "external_id is immutable after User.Create"`). AuthZ — `v_update` + cluster-admin short-circuit.
3. **membership-over-show удалён** — `List` для user/SA/group/role = `viewer ∪ v_list`
   (эталон role.List). AccessBinding `List` = `viewer ∪ v_list ∪ self/granted-floor`
   (D-6 — self `ListBySubject` + owner/FGA-admin `ListByScope` остаются как union-floor).
   Раньше любой член аккаунта видел всех user/SA — теперь только себя + viewer/v_list-видимых.
   Admin/owner visibility loss **нет** (видят всех через FGA viewer tier-cascade).

## Backend (схема / контракт)

- migration **0041**: `labels jsonb NOT NULL DEFAULT '{}'` + CHECK `kacho_labels_valid`
  + GIN `jsonb_path_ops` на `users`/`service_accounts`/`roles`/`access_bindings`;
  GIN на `groups.labels` (колонка была, индекса не было).
- Request-`labels` всех Create/Update несут полный `kacho.cloud` annotation-set
  (sync `INVALID_ARGUMENT` на request-layer; SA request-`labels` доведены до паритета,
  раньше были голые). DB CHECK — async backstop.
- `Role.labels` ≠ `Rule.matchLabels` — два РАЗНЫХ концепта (метки самого ресурса Role vs
  object-selector внутри грант-правила).
- AB mutable set расширен до `{deletion_protection, labels}` (T3.3-IMM-01); иной mask путь
  (`role_id`/subject/scope/`resource_*`) → `INVALID_ARGUMENT`.
- Label-change co-commit'ит reconcile-event own-resource в writer-tx (ban #10 / SEC-D,
  нет dual-write) → eager re-материализация / revoke membership.

## Граф / ацикличность

- iam-типы материализуются **iam-direct same-DB** — **НЕТ self-ребра `iam→iam`**, НЕТ
  нового cross-domain ребра, НЕТ `resource_mirror` для собственных iam-ресурсов. Ацикличность
  графа (`polyrepo.md`) сохранена.

## Gotcha — async v_update/v_list материализация (iam #232-класс)

После `Create`/`UpdateUser`/`Update`-label-change membership-пересчёт **async**
(reconcile-event drain ≤2s + sweep-backstop), хоть источник и same-DB (нет `PENDING_VERIFICATION`).
Read-after-write на свежий грант eventually-consistent → e2e/newman поллят `Check`/`ListObjects`/`List`
до сходимости с таймаутом (`retry_on=(403,404)` — тот же паттерн iam #232). Не ассертить мгновенно.

## Тех-долг (follow-up)

- **iam#251** — `AccessBinding.Get` self-floor покрывает только single-subject binding'и.
- **iam#252** — CQRS Writer-per-field для SA/Role `Update` (label-write обособить от прочих mutable-полей).

## Затронутые сущности vault

- [[../resources/iam-user]] · [[../resources/iam-service-account]] · [[../resources/iam-group]] ·
  [[../resources/iam-role]] · [[../resources/iam-access-binding]]
- [[../rpc/iam-user-service]] (новый `Update`) · [[../rpc/iam-service-account-service]] ·
  [[../rpc/iam-group-service]] · [[../rpc/iam-role-service]] · [[../rpc/iam-access-binding-service]]
- [[../edges/api-gateway-to-iam-authorize]] (public-регистрация `UserService.Update` route)
- **НЕ** заводится `edges/iam-to-iam` (iam-direct same-DB, нет self-ребра, ацикличность).
- Chunk-2 sub-record: [[sub-phase-T3.3-unify-iam-label-scope-role-ab]].
- Read-authz контекст: [[rbac-explicit-model-2026]].

#kac #kacho-proto #kacho-iam #kacho-api-gateway #kacho-deploy #feature #done
