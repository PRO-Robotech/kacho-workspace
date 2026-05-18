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
tags:
  - resource
  - kacho-iam
  - iam
---

# AccessBinding

**Domain**: iam — связь `(subject) ↔ role ↔ (resource)`. E0 **хранит**, не проверяет authz.
**ID prefix**: `acb` (20 chars)
**Owner table**: `kacho_iam.access_bindings`
**Status (E0)**: backend в [[KAC-112]]. Authz-check появится в E3 ([[KAC-108]], [[../edges/iam-to-openfga-check]]).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("acb")` | |
| `subject_type` | TEXT | CHECK `IN ('user','service_account','group')` | |
| `subject_id` | TEXT | **soft-ref** — без FK (полиморфно) | E3 синк → OpenFGA |
| `role_id` | TEXT | FK → roles(id) RESTRICT | |
| `resource_type` | TEXT | CHECK `^[a-z][a-z0-9_]*$` или `*` | whitelisted enum (см. acceptance §2.5) |
| `resource_id` | TEXT | **soft-ref** — cross-DB (запрет #8) | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `access_bindings_pkey` PRIMARY KEY (id)
- `access_bindings_role_fk` FK → `roles(id)` ON DELETE RESTRICT
- `access_bindings_subject_ck` / `access_bindings_resource_ck` — enum/regex CHECK
- `access_bindings_unique` UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) — **идемпотентность Create**
- Indexes: `access_bindings_subject_idx`, `access_bindings_resource_idx`, `access_bindings_role_idx`

## Polymorphic refs (важно)

- `subject_id` ссылается полиморфно на `users` / `service_accounts` / `groups` — **без FK** (PostgreSQL FK не поддерживает alternation). E0 хранит as-is; E3 OpenFGA-sync будет валидировать через peer-lookup в `InternalIAMService.LookupSubject`.
- `resource_id` ссылается на ресурс **другого сервиса** (cross-DB; запрет #8) — software-validation отложена, E3 будет sync в OpenFGA tuples + lazy check.

## Lifecycle

- **Create** — async; UNIQUE → идемпотентный (повторный Create на тот же (subject, role, resource) → возвращает existing, без 23505 наружу — спец-маппинг в `maperr.go`, см. acceptance §6). **KAC-108**: в той же writer-TX enqueue'ит `fga_outbox` row (`event_type='fga.tuple.write'`) + `subject_change_outbox` row → atomic с AccessBinding INSERT.
- **Delete** — async; по id. **KAC-108**: enqueue'ит `fga_outbox` (`event_type='fga.tuple.delete'`) + `subject_change_outbox` row перед commit'ом.
- **ListByResource** / **ListBySubject** — sync read.

## Gotchas

- Удаление Role с активным AccessBinding → `FailedPrecondition "Role <id> is in use by access bindings"` (FK RESTRICT).
- Удаление User/SA/Group **не cascades** в AccessBinding (полиморфно, без FK) — оператор должен почистить вручную либо ждать E3 cascade-cleanup через OpenFGA.
- E0 НЕ читает / НЕ enforce'ит binding'и в interceptor-ах — это E3 (KAC-108). На E0 любой запрос проходит без auth (`principal=system`).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-access-binding-service]] [[iam-role]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam
