---
title: Role
aliases:
  - Role (iam)
  - iam Role
category: resource
domain: iam
id_prefix: rol
owner_table: kacho_iam.roles
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-role-service]]"
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
---

# Role

**Domain**: iam — bundle of permissions для AccessBinding.
**ID prefix**: `rol` (20 chars; system-роли имеют детерминированные id вида `rol00000000000000iamad`)
**Owner table**: `kacho_iam.roles`
**Status (E0)**: 12 system-default seed-роль создаются миграцией `0001_initial.sql`; custom-CRUD — в [[KAC-112]].

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("rol")` | |
| `account_id` | TEXT NULL | FK → accounts(id) RESTRICT | **NULL для system-роли**; NOT NULL для custom |
| `name` | TEXT | regex (см. ниже) | UNIQUE per (account_id) custom / per name system |
| `description` | TEXT | `<=256` chars | |
| `permissions` | JSONB | `iam_permissions_valid` (regex per item + cardinality 1-256) | array of strings `<module>.<resource>.<verb>` |
| `is_system` | BOOL | | seed-only, immutable |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `roles_account_fk` FK → `accounts(id)` RESTRICT
- `roles_system_xor_account` CHECK: `(is_system=true AND account_id IS NULL) OR (is_system=false AND account_id IS NOT NULL)`
- `roles_custom_unique` partial UNIQUE (account_id, name) WHERE `is_system=false`
- `roles_system_unique` partial UNIQUE (name) WHERE `is_system=true`
- `roles_custom_name_check` — custom: `^[a-z][a-z0-9_]{0,40}$`
- `roles_system_name_check` — system: `^roles/[a-z]+\.[a-z]+$`
- `roles_permissions_valid` CHECK — pgPL/SQL func, regex per item

## Permission string

Format: `<module>.<resource>.<verb>` (`*` wildcard на отдельных позициях). См. acceptance §2.3.
Examples: `vpc.networks.*`, `iam.*.read`, `*.*.*` (admin).

## Default system-roles (12, seed via `0001_initial.sql`)

- `roles/iam.{admin,editor,viewer}`
- `roles/vpc.{admin,editor,viewer}`
- `roles/compute.{admin,editor,viewer}`
- `roles/loadbalancer.{admin,editor,viewer}`

## Lifecycle

- **Custom**: Create/Update/Delete async; system-role попытка Update/Delete → `FailedPrecondition`.
- **System-role**: immutable seed; добавление новой system-роли — только новой миграцией (запрет #5).

## Gotchas

- Wildcards в permissions **не разворачиваются** при INSERT — хранятся as-is; expansion — в OpenFGA Check на E3.
- System-role id — детерминированный (stable across re-seeds), чтобы OpenFGA-tuples могли ссылаться по id.
- `roles_custom_name_check` запрещает `roles/...` для custom — исключает коллизию с system-namespace.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-role-service]] [[iam-access-binding]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam
