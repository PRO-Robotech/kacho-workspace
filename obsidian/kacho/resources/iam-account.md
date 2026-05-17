---
title: Account
aliases:
  - Account (iam)
  - iam Account
category: resource
domain: iam
id_prefix: acc
owner_table: kacho_iam.accounts
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-account-service]]"
  - "[[rpc/iam-internal-iam-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# Account

**Domain**: iam (new tenant top-level — заменяет связку Organization+Cloud из `kacho-resource-manager`)
**ID prefix**: `acc` (20 chars, crockford-base32)
**Owner table**: `kacho_iam.accounts`
**Folder-level**: no (Account — сам top-level)
**Status (E0)**: реализован в [[KAC-105]] (PR `kacho-iam` main).
**KAC-117 (2026-05-18)**: auto-create personal Account при первой регистрации
user через Kratos — см. lifecycle ниже.

## Lifecycle

При первой регистрации user через Kratos `InternalUserService.UpsertFromIdentity`
lazy-upsert worker auto-создаёт personal Account:
- `name` = email-local + 6-char hash от external_id (для глобальной уникальности).
- `description` = "Personal account for <email>".
- `owner_user_id` = новый User.id.

Плюс default Project внутри Account (см. [[iam-project]]). Идемпотентно:
existing user не получает дубликаты (UNIQUE на accounts.name +
accounts_owner_fk; повторный INSERT молча игнорится — non-fatal).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("acc")` | |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | **UNIQUE globally** (не per-Org) |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` (<=64 pairs) | CHECK constraint |
| `owner_user_id` | TEXT | FK → users(id) RESTRICT | NOT NULL |
| `created_at` | TIMESTAMPTZ | server-set | truncate-to-seconds (YC parity) |

## Constraints / indexes

- `accounts_pkey` PRIMARY KEY (id)
- `accounts_name_unique` UNIQUE (name) — глобальная уникальность
- `accounts_owner_fk` FK → `users(id)` ON DELETE RESTRICT
- CHECK: `accounts_name_check`, `accounts_description_check`, `accounts_labels_valid`
- `accounts_owner_idx` (owner_user_id)

## FK contract (in-bound: что ссылается на Account)

- `projects.account_id → accounts(id) ON DELETE RESTRICT`
- `service_accounts.account_id → accounts(id) ON DELETE RESTRICT`
- `groups.account_id → accounts(id) ON DELETE RESTRICT`
- `roles.account_id → accounts(id) ON DELETE RESTRICT` (custom-role only; system-role NULL)

→ Delete Account → `FailedPrecondition "Account <id> contains <projects|service accounts|groups|custom roles>"`.

## Lifecycle

Single state — нет provisioning. Сразу ACTIVE после `Create`. Все мутации async через `operation.Operation` (запрет #9).

## Gotchas

- `owner_user_id` immutable после Create (UpdateMask ловит как InvalidArgument).
- User не может быть удалён, пока владеет Account-ом (`accounts_owner_fk` RESTRICT → FailedPrecondition).
- На E0 `principal_*` в operations = `('system','bootstrap','kacho-iam-bootstrap')`; E2 заменит реальным JWT principal.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-account-service]] [[../rpc/iam-internal-iam-service]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam
