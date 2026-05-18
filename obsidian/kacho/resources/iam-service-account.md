---
title: ServiceAccount
aliases:
  - ServiceAccount (iam)
  - iam ServiceAccount
  - SA
category: resource
domain: iam
id_prefix: sva
owner_table: kacho_iam.service_accounts
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-service-account-service]]"
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

# ServiceAccount

**Domain**: iam (machine-identity, account-scoped)
**ID prefix**: `sva` (20 chars)
**Owner table**: `kacho_iam.service_accounts`
**Folder-level**: no (account-scoped)
**Status (E0)**: backend в [[KAC-112]]. Key-credentials (client_credentials grant) — отложено на E2 (через Zitadel).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("sva")` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE (account_id, name) |
| `description` | TEXT | `<=256` chars | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `service_accounts_pkey` PRIMARY KEY (id)
- `service_accounts_account_fk` FK → `accounts(id)` ON DELETE RESTRICT
- `service_accounts_account_name_unique` UNIQUE (account_id, name)
- CHECK: `service_accounts_name_check`, `service_accounts_description_check`

## FK contract (in-bound)

- `group_members.member_id` (when `member_type='service_account'`) — soft-ref через триггер.
- `access_bindings.subject_id` (when `subject_type='service_account'`) — soft-ref.

## Lifecycle

- **Create / Update / Delete** — все async через `Operation`.
- **Key-credentials**: НЕ в E0. E2 добавит `CreateKey/ListKeys/DeleteKey` поверх Zitadel `client_credentials` grant.

## Gotchas

- `account_id` immutable.
- Удаление SA, у которого есть GroupMember/AccessBinding — на E0 sentinel `FailedPrecondition` от service-слоя; E3 + OpenFGA добавит cascade-cleanup tuples.
- Без E2 SA не может «логиниться» — только хранится как identity-stub.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-service-account-service]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam
