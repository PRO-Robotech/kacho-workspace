---
title: SessionRevocation
aliases:
  - SessionRevocation (iam)
  - session_revocation
  - token_jti_blocklist
category: resource
domain: iam
id_prefix: (token_jti)
owner_table: kacho_iam.session_revocations
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc: []
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
---

# SessionRevocation

**Domain**: iam — fast lookup blocklist для revoked tokens (by `token_jti`). Используется в authn-interceptor (Phase 2) для проверки «is this token revoked?».
**ID**: `token_jti` (PK; opaque JWT-id из issuer Hydra) — без префикса.
**Owner table**: `kacho_iam.session_revocations` (migration 0013).
**Phase 1**: schema-only. Revocation flow + cron-cleanup — Phase 2 AuthN + Phase 8 cleanup-cron.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `token_jti` | TEXT PK | length 1..128 | JWT `jti` claim verbatim |
| `revoked_at` | TIMESTAMPTZ | server-set | |
| `reason` | TEXT | length <=256 | `'logout'` / `'admin-revoke'` / `'caep-push'` / ... |
| `user_id` | TEXT | FK → users(id) RESTRICT | для audit |
| `ttl_expires_at` | TIMESTAMPTZ | NOT NULL, **`> revoked_at`** | row TTL — после expiry token уже не валиден через `exp` claim |

## Constraints / indexes

- `session_revocations_pkey` PRIMARY KEY (token_jti)
- `session_revocations_user_fk` FK → `users(id)` ON DELETE RESTRICT
- `session_revocations_ttl_idx` (`ttl_expires_at`) — для Phase 8 cleanup-cron `DELETE WHERE ttl_expires_at < now()`
- CHECK: token_jti-length, reason-length, `ttl_expires_at > revoked_at`

## Lifecycle

- **Revoke (Phase 2)**: на logout / admin-revoke / CAEP-trigger → INSERT row с `ttl_expires_at = now() + remaining_token_ttl`.
- **AuthN-interceptor (Phase 2)**: на каждом request looked up by `jti`; если есть row → reject с `Unauthenticated`.
- **Cleanup (Phase 8 cron)**: периодически `DELETE WHERE ttl_expires_at < now()`. Row жил столько, сколько токен валиден (после `exp` claim сам по себе невалиден).

## Gotchas

- `token_jti` — PK, не префиксованный id. Зависит от issuer Hydra (UUID/ULID).
- TTL обязателен — без него blocklist неограниченно растёт. После expiry token уже не валиден через standard JWT `exp` — row безопасно удалить.
- Production hot-path: read-only lookup в Redis-cache (Phase 2), DB fallback на miss. Cache invalidate через CAEP push.
- LISTEN/NOTIFY на `session_revocations` для invalidate всех replicas (Phase 2 wiring).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-user]] [[iam-caep-subscriber]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
