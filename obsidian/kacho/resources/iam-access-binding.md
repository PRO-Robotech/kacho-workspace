---
title: AccessBinding
aliases:
  - AccessBinding (iam)
  - iam AccessBinding
  - ACB
category: resource
domain: iam
id_prefix: acb
owner_table: kacho_iam.access_bindings
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-access-binding-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-108]]"
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# AccessBinding

**Domain**: iam — связь `(subject) ↔ role ↔ (resource)`.
**ID prefix**: `acb` (20 chars).
**Owner table**: `kacho_iam.access_bindings`.
**Status**: KAC-105 базовый + **KAC-127 Phase 1** extension: lifecycle-поля (`status`, `condition_id`, `expires_at`, `granted_by_user_id`, `revoked_at`, `revoked_by_user_id`).

## Fields (KAC-127 extended)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("acb")` | |
| `subject_type` | TEXT | CHECK `IN ('user','service_account','group')` | |
| `subject_id` | TEXT | **soft-ref** — без FK (полиморфно) | Phase 3 синк → OpenFGA |
| `role_id` | TEXT | FK → roles(id) RESTRICT | |
| `resource_type` | TEXT | CHECK `^[a-z][a-z0-9_]*$` или `*` | whitelisted enum |
| `resource_id` | TEXT | **soft-ref** — cross-DB (запрет #8) | opaque id (любой prefix) |
| `status` | TEXT | CHECK enum (KAC-127) | `PENDING` (initial) / `ACTIVE` / `REVOKED` |
| `condition_id` | TEXT NULL | FK → access_binding_conditions(id) RESTRICT (KAC-127) | 1:1 overlay condition |
| `expires_at` | TIMESTAMPTZ NULL | CHECK `IS NULL OR > created_at` (KAC-127) | TTL — JIT-bindings expire |
| `granted_by_user_id` | TEXT | length <=64 (KAC-127) | audit — кто выдал |
| `revoked_at` | TIMESTAMPTZ NULL | (KAC-127) | set когда status → REVOKED |
| `revoked_by_user_id` | TEXT NULL | length <=64 (KAC-127) | audit — кто отозвал |
| `created_at` | TIMESTAMPTZ | server-set | |

## State machine (KAC-127 Phase 1)

```
PENDING → ACTIVE → REVOKED (terminal)
```

DB CHECK `status IN ('PENDING','ACTIVE','REVOKED')`. Transitions через atomic CAS-style UPDATE (workspace §запрет #10):
- `WHERE status='PENDING'` → ACTIVE (auto on conditions-satisfied)
- `WHERE status IN ('PENDING','ACTIVE')` → REVOKED (idempotent revoke)

## Constraints / indexes

- `access_bindings_pkey` PRIMARY KEY (id)
- `access_bindings_role_fk` FK → `roles(id)` ON DELETE RESTRICT
- `access_bindings_condition_fk` FK → `access_binding_conditions(id)` RESTRICT (KAC-127)
- `access_bindings_subject_ck` / `access_bindings_resource_ck` — enum/regex CHECK
- `access_bindings_status_ck` CHECK (KAC-127): `status IN ('PENDING','ACTIVE','REVOKED')`
- `access_bindings_revoked_consistency_ck` CHECK (KAC-127): `(status='REVOKED' AND revoked_at IS NOT NULL) OR (status IN ('PENDING','ACTIVE') AND revoked_at IS NULL)`
- `access_bindings_expires_ck` CHECK (KAC-127): `expires_at IS NULL OR expires_at > created_at`
- `access_bindings_unique` UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) — **идемпотентность Create**
- Indexes: subject, resource, role, `(status, expires_at)` для expiry-cron

## Polymorphic refs

- `subject_id` ссылается полиморфно на `users` / `service_accounts` / `groups` — **без FK** (PostgreSQL FK не поддерживает alternation). Phase 3 OpenFGA-sync будет валидировать через peer-lookup в `InternalIAMService.LookupSubject`.
- `resource_id` ссылается на ресурс **другого сервиса** (cross-DB; запрет #8) — software-validation в Phase 3 OpenFGA tuples + lazy check.

## Lifecycle

- **Create** — async; UNIQUE → идемпотентный (повторный Create на тот же (subject, role, resource) → возвращает existing). KAC-108: в той же writer-TX enqueue'ит `fga_outbox` row (`event_type='fga.tuple.write'`) + `subject_change_outbox` row → atomic с AccessBinding INSERT.
- **Activate (KAC-127 Phase 7)**: PENDING → ACTIVE через CAS UPDATE (conditions met / JIT activate / approver-grant).
- **Revoke (KAC-127)**: idempotent CAS UPDATE (`WHERE status IN ('PENDING','ACTIVE')` → REVOKED). KAC-108: enqueue'ит `fga_outbox` (`fga.tuple.delete`) + `subject_change_outbox` + audit + CAEP push.
- **Expire (KAC-127 Phase 7 worker)**: scan `WHERE status='ACTIVE' AND expires_at < now()` → CAS UPDATE → REVOKED.
- **ListByResource** / **ListBySubject** — sync read.

## Gotchas

- KAC-127: `condition_id` 1:1 UNIQUE — попытка attach двух conditions на одну binding → `23505`.
- Удаление Role с активным AccessBinding → `FailedPrecondition` (FK RESTRICT).
- Удаление User/SA/Group **не cascades** в AccessBinding (полиморфно, без FK) — оператор должен почистить через AccessReview либо ждать Phase 3 cascade-cleanup через OpenFGA.
- Phase 1 НЕ читает / НЕ enforce'ит binding'и в interceptor-ах — это Phase 3 (KAC-108). На E0 любой запрос проходит без auth (`principal=system`).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-access-binding-service]] [[iam-role]] [[iam-access-binding-condition]] [[iam-jit-eligibility]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
