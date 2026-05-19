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
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# ServiceAccount

**Domain**: iam (machine-identity, account-scoped + optional project_id since KAC-127).
**ID prefix**: `sva` (20 chars).
**Owner table**: `kacho_iam.service_accounts`.
**Status**: KAC-105 базовый, **KAC-127 Phase 1** добавил `project_id` (optional, preferred над account-scope) + `enabled` flag.

## Fields (KAC-127 extended)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("sva")` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL |
| `project_id` | TEXT NULL | FK → projects(id) RESTRICT (KAC-127) | optional, preferred scope |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE (account_id, name) |
| `description` | TEXT | `<=256` chars | |
| `enabled` | BOOL | default `true` (KAC-127) | false → SA не может authenticate |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `service_accounts_pkey` PRIMARY KEY (id)
- `service_accounts_account_fk` FK → `accounts(id)` ON DELETE RESTRICT
- `service_accounts_project_fk` FK → `projects(id)` ON DELETE RESTRICT (KAC-127)
- `service_accounts_account_name_unique` UNIQUE (account_id, name)
- CHECK: `service_accounts_name_check`, `service_accounts_description_check`

## FK contract (in-bound)

- `service_account_oauth_clients.sva_id → service_accounts(id) ON DELETE CASCADE` (KAC-127; 1:1)
- `federation_trust_policies.service_account_id → service_accounts(id) ON DELETE CASCADE` (KAC-127)
- `group_members.member_id` (when `member_type='service_account'`) — soft-ref через триггер.
- `access_bindings.subject_id` (when `subject_type='service_account'`) — soft-ref.

## Lifecycle

- **Create / Update / Delete** — все async через `Operation`.
- **Disable (KAC-127)**: `enabled=false` → AuthN-interceptor (Phase 2) запретит `client_credentials` grant; existing tokens продолжают работать до natural `exp` (или revoke через [[iam-session-revocation]]).
- **Key-credentials** — KAC-127 Phase 5 через [[iam-service-account-oauth-client]] (Class A static Hydra client).
- **Federation** — KAC-127 Phase 5 через [[iam-federation-trust-policy]] (Class B OIDC federation).

## Gotchas

- `account_id` immutable.
- `project_id` — optional (KAC-127); если задан, должен принадлежать SAME `account_id` (Phase 1 service-CHECK).
- KAC-127: удаление SA каскадно удаляет `service_account_oauth_clients` + `federation_trust_policies` (CASCADE). НЕ каскадит на GroupMember/AccessBinding (soft-ref).
- На KAC-105: SA без OAuthClient не может «логиниться» — только хранится как identity-stub. KAC-127 Phase 5 включает реальный workload identity flow.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-service-account-service]] [[iam-account]] [[iam-project]] [[iam-service-account-oauth-client]] [[iam-federation-trust-policy]] [[../KAC/KAC-105]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
