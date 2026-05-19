---
title: AccessBindingJITEligibility
aliases:
  - JITEligibility
  - iam JIT Eligibility
  - PIM eligibility
category: resource
domain: iam
id_prefix: jite
owner_table: kacho_iam.access_bindings_jit_eligibility
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-access-binding-service]]"
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

# AccessBindingJITEligibility

**Domain**: iam — JIT/PIM eligibility row: «кто может self-activate какую role на каком resource, как долго, нужен ли approver». Phase 7 PIM/JIT engine.
**ID prefix**: `jite_` + `[a-z0-9_]{1,40}` → `^jite_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.access_bindings_jit_eligibility` (migration 0012).
**Phase 1**: schema-only. ActivateJIT RPC + worker — Phase 7.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^jite_[a-z0-9_]{1,40}$` | |
| `user_id` | TEXT | FK → users(id) RESTRICT | eligibility subject |
| `role_id` | TEXT | FK → roles(id) RESTRICT | role, который можно активировать |
| `resource_type` | TEXT | regex `^[a-z][a-z0-9_]*$` или `*` | per-resource scope |
| `resource_id` | TEXT | length 1..64 | opaque id |
| `max_duration` | INTERVAL | **(0s, 8h]** CHECK | JIT activation max-TTL |
| `approval_required` | BOOL | | true → approver_user_id ОБЯЗАН быть set |
| `approver_user_id` | TEXT NULL | FK → users(id) RESTRICT | approver (NULL = auto-approve если approval_required=false) |
| `enabled` | BOOL | | |
| `expires_at` | TIMESTAMPTZ NULL | | optional eligibility window |
| `created_at` | TIMESTAMPTZ | server-set | |
| `created_by` | TEXT | length <=64 | user_id grantor'а |

## Constraints / indexes

- `access_bindings_jit_eligibility_pkey` PRIMARY KEY (id)
- 2× FK → `users(id)` (user_id, approver_user_id) — RESTRICT
- FK → `roles(id)` — RESTRICT
- CHECK: id-regex, `max_duration ∈ (0, '8 hours')`, `(approval_required=false) OR (approver_user_id IS NOT NULL)` (Phase 7 проверит логику auto-approve / required-approver)
- Index: `(user_id, role_id)` для lookup при ActivateJIT.

## Lifecycle (Phase 7)

- **Create**: admin grants eligibility (acceptance §2.1 + §6.8).
- **ActivateJIT** (Phase 7): user requests activation → если `approval_required=true` → ждём approver decision → создаём temporary `AccessBinding` со `status=ACTIVE` и `expires_at=now+requested_ttl` (где requested_ttl ≤ max_duration).
- **Delete / Disable**: enabled=false → ActivateJIT блокируется.

## Gotchas

- `max_duration ≤ 8h` — DB-enforced (acceptance §2.1 + §6.8). Production принцип: JIT-grants short-lived.
- `approver_user_id` валидируется domain.Validate (если `approval_required=false`, то approver должен быть NULL).
- Активация создаёт **новый** `AccessBinding` с TTL — не модифицирует eligibility row.
- Audit-trail на каждую activation (Phase 7 audit pipeline).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-access-binding-service]] [[iam-access-binding]] [[iam-role]] [[iam-user]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
