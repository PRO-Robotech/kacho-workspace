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
| `external_id` | TEXT | length 1-256 | **UNIQUE** — Zitadel `sub` claim |
| `email` | TEXT | RFC 5321 lite regex, length 3-254 | indexed `lower(email)` |
| `display_name` | TEXT | `<=128` chars | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `users_pkey` PRIMARY KEY (id)
- `users_external_id_unique` UNIQUE (external_id) — upsert-семантика
- `users_email_check`, `users_display_name_check`, `users_external_id_check`
- `users_email_idx` (lower(email))

## FK contract (in-bound)

- `accounts.owner_user_id → users(id) ON DELETE RESTRICT` — User не удалить пока владеет Account-ом.
- `group_members.member_id` (when `member_type='user'`) — soft-ref через триггер `group_members_member_exists`.
- `access_bindings.subject_id` (when `subject_type='user'`) — soft-ref (полиморфно, без FK).

## Lifecycle

- **Public RPC**: `Get`, `List`, `Delete` (admin-only на E0). **НЕТ Create/Update** публично — User создаётся только через OIDC.
- **Internal**: `InternalUserService.UpsertFromIdentity` — UPSERT по `external_id`; на E0 вызывается через gRPC direct (admin), в E2 — из OIDC-callback в api-gateway.

## Gotchas

- Полиморфная ссылка `group_members.member_id` — без FK, защищается триггером (см. [[iam-group]]).
- `email` хранится case-preserve, но `users_email_idx` lowercases; lookup-by-email — через `lower()`.
- На E0 `external_id` может быть admin-stub (пустой/локальный) для bootstrap; E2 переключит на реальный Zitadel `sub`.
- **get-self под flat-моделью (Contract-A)**: FGA `iam_user.viewer = subject or editor`. User видит сам себя ТОЛЬКО через self-tuple `iam_user:<U>#subject@user:<U>`. Это D-4-класс — НЕ восстановим reconciler'ом, эмитится явно при создании user (bootstrap `bootstrapTuples` + invite-path). См. [[../KAC/rbac-2026-contract-a-flat-bootstrap-fallout]].
- **bootstrap signup → owner-binding**: signup-юзер получает **owner**-binding (не admin) на свой personal account + post-commit `ReconcileBinding` (forward-mat per-object owner-доступ на project/iam-native/cross-service). Под flat hierarchy-pointer'ы доступа не дают.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-user-service]] [[../rpc/iam-internal-user-service]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam #mirror
