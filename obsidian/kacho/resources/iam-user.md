---
title: User
aliases:
  - User (iam)
  - iam User
category: resource
domain: iam
id_prefix: usr
owner_table: kacho_iam.users
owner_db: kacho_iam
folder_level: false
visibility: mirror
status: done
related_rpc:
  - "[[rpc/iam-user-service]]"
  - "[[rpc/iam-internal-user-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - resource
  - kacho-iam
  - iam
  - mirror
---

# User

**Domain**: iam (mirror identity из Zitadel — local denormalised copy, source-of-truth снаружи)
**ID prefix**: `usr` (20 chars)
**Owner table**: `kacho_iam.users`
**Folder-level**: no
**Status (E0)**: backend в [[KAC-112]]; реальный заполнятель — OIDC-callback E2 ([[../edges/iam-to-zitadel-oidc]]).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("usr")` | |
| `external_id` | TEXT | length 1-256 | **UNIQUE** — Zitadel `sub` claim; IdP-mirror, **immutable** локально |
| `email` | TEXT | RFC 5321 lite regex, length 3-254 | indexed `lower(email)`; IdP-mirror |
| `display_name` | TEXT | `<=128` chars | IdP-mirror |
| `labels` | JSONB | `kacho_labels_valid` (mig 0041) | tenant-facing метки; **mutable** через `UpdateUser`; делают User label-selectable |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `users_pkey` PRIMARY KEY (id)
- `users_external_id_unique` UNIQUE (external_id) — upsert-семантика
- `users_email_check`, `users_display_name_check`, `users_external_id_check`
- `users_email_idx` (lower(email))
- **`labels` jsonb** (migration 0041): `NOT NULL DEFAULT '{}'` + CHECK `kacho_iam.kacho_labels_valid(labels)` + GIN `jsonb_path_ops` (под `labels @> matchLabels` containment-probe).

## FK contract (in-bound)

- `accounts.owner_user_id → users(id) ON DELETE RESTRICT` — User не удалить пока владеет Account-ом.
- `group_members.member_id` (when `member_type='user'`) — soft-ref через триггер `group_members_member_exists`.
- `access_bindings.subject_id` (when `subject_type='user'`) — soft-ref (полиморфно, без FK).

## Lifecycle

- **Public RPC**: `Get`, `List`, **`Update`** (label-write, см. ниже), `Delete` (admin-only на E0). **НЕТ публичного Create** — User создаётся только через OIDC.
- **`Update` (public, label-write)** — единственный mutable-путь tenant-данных User: `labels` через `update_mask`. `external_id`/`email`/`display_name` остаются IdP-mirror'ом (immutable локально) → их наличие в `update_mask` → `INVALID_ARGUMENT "<field> is immutable after User.Create"`. async → `Operation`. Подробности — [[../rpc/iam-user-service]].
- **Internal**: `InternalUserService.UpsertFromIdentity` — UPSERT по `external_id`; на E0 вызывается через gRPC direct (admin), в E2 — из OIDC-callback в api-gateway.

## Label-selectability + List-видимость (DIVERGENCE-A / T3.3)

- **Label-selectable** (наравне с account/project): label-грант `Role.rule{module:iam, resources:["user"], matchLabels:{…}}` материализует `v_list` на matching-user'ов (`users.labels @> matchLabels`). Источник — **own-table same-DB** (iam-direct, НЕ `resource_mirror` — нет self-ребра `iam→iam`); containment по iam-hierarchy (`users.account_id ⊑ scope`). Реверс решения O-4 (раньше iam content-типы НЕ были label-selectable).
- **`List` = `viewer ∪ v_list`** (эталон role.List): anonymous → empty (default-deny до FGA-call); FGA error → `Unavailable` (fail-closed, никогда unfiltered leak); self-floor (user видит себя через self-tuple); admin/owner/cluster-admin — через FGA viewer tier-cascade. **`Get == List` resolver** (тот же путь).
- **membership-over-show устранён** — обычный член аккаунта больше НЕ видит всех user'ов автоматически; только себя (self) + тех, на кого есть `viewer`/`v_list`. Admin/owner visibility loss нет (видят всех через viewer-tier).

## Gotchas

- Полиморфная ссылка `group_members.member_id` — без FK, защищается триггером (см. [[iam-group]]).
- `email` хранится case-preserve, но `users_email_idx` lowercases; lookup-by-email — через `lower()`.
- На E0 `external_id` может быть admin-stub (пустой/локальный) для bootstrap; E2 переключит на реальный Zitadel `sub`.
- **get-self под flat-моделью (Contract-A)**: FGA `iam_user.viewer = subject or editor`. User видит сам себя ТОЛЬКО через self-tuple `iam_user:<U>#subject@user:<U>`. Это D-4-класс — НЕ восстановим reconciler'ом, эмитится явно при создании user (bootstrap `bootstrapTuples` + invite-path). См. [[../KAC/rbac-2026-contract-a-flat-bootstrap-fallout]].
- **bootstrap signup → owner-binding**: signup-юзер получает **owner**-binding (не admin) на свой personal account + post-commit `ReconcileBinding` (forward-mat per-object owner-доступ на project/iam-native/cross-service). Под flat hierarchy-pointer'ы доступа не дают.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-user-service]] [[../rpc/iam-internal-user-service]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam #mirror
