---
title: AccessBindingCondition
aliases:
  - AccessBindingCondition (iam)
  - iam AccessBindingCondition
  - binding condition
category: resource
domain: iam
id_prefix: cond
owner_table: kacho_iam.access_binding_conditions
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

# AccessBindingCondition

**Domain**: iam — CEL-like overlay условия на AccessBinding (mfa_fresh / source_ip_in_range / business_hours / jit_window / break_glass_window / device_compliant / non_expired). 1:1 c AccessBinding.
**ID prefix**: `cond_` + `[a-z0-9_]{1,40}` → `^cond_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.access_binding_conditions` (migration 0012).
**Phase 1**: schema-only. CEL evaluator — Phase 3 OpenFGA Conditions.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^cond_[a-z0-9_]{1,40}$` | |
| `binding_id` | TEXT | FK → access_bindings(id) CASCADE | **UNIQUE** — 1:1 |
| `expression` | TEXT | CHECK whitelist enum (7 values) | predicate name |
| `params` | JSONB | object (per-predicate schema) | params для CEL evaluator |
| `created_at` | TIMESTAMPTZ | server-set | |
| `created_by` | TEXT | length <=64 | user_id grantor'а |

## Expression whitelist (7 values, DB CHECK)

| Value | Semantic |
|---|---|
| `mfa_fresh` | MFA проверка ≤N min от now (params: `{max_age_seconds: int}`) |
| `non_expired` | binding не expired (auto-evaluated by expires_at) |
| `source_ip_in_range` | source IP в CIDR (params: `{cidrs: [...]}`) |
| `break_glass_window` | active внутри break-glass окна (Phase 7) |
| `jit_window` | active внутри JIT-activation окна (Phase 7) |
| `business_hours` | business-hours filter (params: `{tz, hours}`) |
| `device_compliant` | device-posture compliance check |

## Constraints / indexes

- `access_binding_conditions_pkey` PRIMARY KEY (id)
- `access_binding_conditions_binding_fk` FK → `access_bindings(id)` ON DELETE CASCADE
- `access_binding_conditions_binding_unique` **UNIQUE (binding_id)** — 1:1 enforced на DB-уровне
- `access_binding_conditions_expression_whitelist_ck` CHECK — exact whitelist set

## Lifecycle

- **Create** — atomic с AccessBinding (либо вторым INSERT в одной TX). Условие применяется на authz-check (Phase 3).
- **Delete** — каскадно через AccessBinding.Delete (CASCADE FK).
- **Update**: запрещён (immutable — Delete + Create новый).

## Gotchas

- 1:1 invariant жёсткий: попытка повторного INSERT на тот же `binding_id` → `23505` → `AlreadyExists`.
- `params` schema валидируется CEL-evaluator Phase 3 (НЕ на INSERT — JSONB сюда хранится opaque).
- `expression` — strict whitelist, без custom expressions: добавление нового predicate требует миграции и обновления CHECK.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-access-binding-service]] [[iam-access-binding]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
