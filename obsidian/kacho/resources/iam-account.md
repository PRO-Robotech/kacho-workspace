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
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# Account

**Domain**: iam (new tenant top-level — заменяет связку Organization+Cloud из `kacho-resource-manager`)
**ID prefix**: `acc` (20 chars, crockford-base32)
**Owner table**: `kacho_iam.accounts`
**Folder-level**: no (Account — сам top-level; B2B-tier wrapper — optional `organization_id` см. ниже)
**Status**: KAC-105 базовый; **KAC-127 Phase 1** добавил `organization_id` (optional FK → Organization для B2B).
**KAC-117 (2026-05-18)**: auto-create personal Account при первой регистрации user через Kratos — см. lifecycle ниже.

## Lifecycle

При первой регистрации user через Kratos `InternalUserService.UpsertFromIdentity`
lazy-upsert worker auto-создаёт personal Account:
- `name` = email-local + 6-char hash от external_id (для глобальной уникальности).
- `description` = "Personal account for <email>".
- `owner_user_id` = новый User.id.
- `organization_id` = NULL (KAC-127; personal account — нет org-tier).

Плюс default Project внутри Account (см. [[iam-project]]). Идемпотентно:
existing user не получает дубликаты (UNIQUE на accounts.name +
accounts_owner_fk; повторный INSERT молча игнорится — non-fatal).

## Tenant isolation (KAC-118)

`AccountService.List` фильтрует через `WHERE owner_user_id = principal.id`,
если в ctx principal с type=`user`. System/service_account — видят всё.
`AccountService.Get` возвращает NotFound для чужого Account (не leak'ает
существование).

## Fields (KAC-127 extended)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("acc")` | |
| `cluster_id` | TEXT | FK → clusters(id) RESTRICT (KAC-127) | NOT NULL — singleton |
| `organization_id` | TEXT NULL | FK → organizations(id) RESTRICT (KAC-127) | NULL для personal-account; B2B-tier wrapper |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | **UNIQUE globally** (не per-Org) |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` (<=64 pairs) | CHECK constraint |
| `owner_user_id` | TEXT | FK → users(id) RESTRICT | NOT NULL |
| `created_at` | TIMESTAMPTZ | server-set | truncate-to-seconds (YC parity) |

## Constraints / indexes

- `accounts_pkey` PRIMARY KEY (id)
- `accounts_name_unique` UNIQUE (name) — глобальная уникальность
- `accounts_cluster_fk` FK → `clusters(id)` ON DELETE RESTRICT (KAC-127)
- `accounts_organization_fk` FK → `organizations(id)` ON DELETE RESTRICT (KAC-127)
- `accounts_owner_fk` FK → `users(id)` ON DELETE RESTRICT
- CHECK: `accounts_name_check`, `accounts_description_check`, `accounts_labels_valid`
- `accounts_owner_idx` (owner_user_id), `accounts_org_idx` (organization_id) (KAC-127)

## FK contract (in-bound: что ссылается на Account)

- `projects.account_id → accounts(id) ON DELETE RESTRICT`
- `service_accounts.account_id → accounts(id) ON DELETE RESTRICT`
- `groups.account_id → accounts(id) ON DELETE RESTRICT`
- `roles.account_id → accounts(id) ON DELETE RESTRICT` (legacy account-scoped custom-role; KAC-127 добавляет organization/project scope)
- `caep_subscribers.account_id → accounts(id) ON DELETE CASCADE` (KAC-127)
- `access_reviews.account_id → accounts(id) ON DELETE RESTRICT` (KAC-127)

→ Delete Account → `FailedPrecondition "Account <id> contains <projects|service accounts|groups|custom roles|access reviews>"` (CAEP subscribers cascade'ятся).

## Lifecycle

Single state — нет provisioning. Сразу ACTIVE после `Create`. Все мутации async через `operation.Operation` (запрет #9).

## Gotchas

- `owner_user_id` immutable после Create (UpdateMask ловит как InvalidArgument).
- `cluster_id` / `organization_id` immutable (вся иерархия attached на create-time).
- User не может быть удалён, пока владеет Account-ом (`accounts_owner_fk` RESTRICT → FailedPrecondition).
- На E0 `principal_*` в operations = `('system','bootstrap','kacho-iam-bootstrap')`; Phase 2 заменит реальным JWT principal.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-account-service]] [[../rpc/iam-internal-iam-service]] [[iam-cluster]] [[iam-organization]] [[iam-project]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
