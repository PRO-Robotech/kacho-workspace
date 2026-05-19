---
title: GDPRErasureRequest
aliases:
  - GDPRErasureRequest (iam)
  - gdpr_erasure_request
  - right-to-be-forgotten
category: resource
domain: iam
id_prefix: gdpr
owner_table: kacho_iam.gdpr_erasure_requests
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
---

# GDPRErasureRequest

**Domain**: iam — GDPR Art. 17 «right to erasure» request с 30-day cool-off pipeline. State machine: `cool_off` → `in_progress` → `completed` (или `cancelled`).
**ID prefix**: `gdpr_` + `[a-z0-9_]{1,40}` → `^gdpr_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.gdpr_erasure_requests` (migration 0014).
**Phase 1**: schema-only. Erasure pipeline + worker — Phase 7.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^gdpr_[a-z0-9_]{1,40}$` | |
| `user_id` | TEXT | FK → users(id) RESTRICT | NOT NULL — erasure target |
| `status` | TEXT | CHECK enum | 4-state machine |
| `requested_at` | TIMESTAMPTZ | server-set | |
| `cool_off_until` | TIMESTAMPTZ | NOT NULL, `> requested_at` | typically requested_at + 30d |
| `processed_at` | TIMESTAMPTZ NULL | | set когда status → completed/cancelled |
| `rationale` | TEXT | length <=2048 | |
| `requested_by_user_id` | TEXT | FK → users(id) RESTRICT | initiator (self или admin) |

## State machine (4-state)

```
cool_off → in_progress → completed (terminal)
                       → cancelled (terminal)
```

DB CHECK `status IN ('cool_off','in_progress','completed','cancelled')`.

## Constraints / indexes

- `gdpr_erasure_requests_pkey` PRIMARY KEY (id)
- 2× FK → `users(id)` (user_id, requested_by_user_id) — RESTRICT
- CHECK: id-regex, status-enum, `cool_off_until > requested_at`, rationale-length

## Lifecycle (Phase 7)

1. **Submit**: user или admin → INSERT (status=`cool_off`, cool_off_until = now + 30d).
2. **Cancel (during cool-off)**: атомарный CAS UPDATE (status `cool_off → cancelled`, processed_at=now).
3. **Process (after cool_off_until)**: worker picks up row → CAS UPDATE (status `cool_off → in_progress`) → scrub PII в users / accounts / projects / audit (на уровне content, не структуры — Merkle chain audit-batch остаётся для tamper-evidence) → CAS UPDATE (status `in_progress → completed`, processed_at=now).
4. **Audit trail остаётся** — GDPR-compliant (legal-basis для audit retention).

## Gotchas

- 30-day cool-off — DB-enforced minimum (production policy в OPA Phase 3 может поставить шире).
- Erasure scope включает: PII в `users.email/name`, mirrored fields в audit log content (заменяется на `gdpr-erased-{id}` token), session_revocations (delete), refresh tokens.
- НЕ удаляет audit_signing_batches и не модифицирует Merkle chain — tamper-evidence важнее PII (legal basis Art. 17(3)(b)/(e)).
- `processed_at` обязателен для terminal states (completed/cancelled) — Phase 7 service-CHECK.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-user]] [[iam-audit-signing-batch]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
