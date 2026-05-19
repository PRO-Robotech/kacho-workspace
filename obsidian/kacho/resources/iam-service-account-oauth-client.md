---
title: ServiceAccountOAuthClient
aliases:
  - SAOAuthClient
  - SA-key
  - iam SA OAuth Client
category: resource
domain: iam
id_prefix: soc
owner_table: kacho_iam.service_account_oauth_clients
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-service-account-service]]"
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

# ServiceAccountOAuthClient

**Domain**: iam — Class A Workload Identity (static OAuth2 client_credentials через ORY Hydra). 1:1 на Phase 1 (один SA → один hydra client).
**ID prefix**: `soc_` + 17-char crockford → `^soc_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.service_account_oauth_clients` (migration 0012).
**Phase 1**: schema-only. Hydra-client provisioning + key-rotation RPC — Phase 5.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^soc_[0-9a-hjkmnp-tv-z]{17}$` | |
| `sva_id` | TEXT | FK → service_accounts(id) CASCADE | **UNIQUE** — 1:1 SA→client |
| `hydra_client_id` | TEXT | `[A-Za-z0-9._:-]+`, length 1..128 | **UNIQUE** — opaque Hydra id |
| `description` | TEXT | length <=256 | |
| `created_by_user_id` | TEXT | length 1..64 | grantor |
| `created_at` | TIMESTAMPTZ | server-set | |
| `expires_at` | TIMESTAMPTZ NULL | > created_at | optional rotation deadline |
| `last_used_at` | TIMESTAMPTZ NULL | | updated by Hydra-event listener (Phase 5) |

## Constraints / indexes

- `service_account_oauth_clients_pkey` PRIMARY KEY (id)
- `service_account_oauth_clients_sva_unique` **UNIQUE (sva_id)** — 1:1 (Phase 1 design choice)
- `service_account_oauth_clients_hydra_unique` **UNIQUE (hydra_client_id)** — Hydra-side id uniqueness mirror
- `service_account_oauth_clients_sva_fk` FK → `service_accounts(id)` CASCADE
- CHECK: id-regex, hydra_client_id-regex, length

## Lifecycle (Phase 5)

- **Create**: admin / SA-owner runs `CreateOAuthClient` → atomic: INSERT row + provision Hydra client through admin API (outbox-pattern для idempotency).
- **Rotate**: Phase 5+ — Delete + Create новый (1:1 invariant breaks → нужна миграция к 1:N).
- **Delete**: cascade — удаление SA автоматически удалит OAuth client (CASCADE FK + Hydra-side cleanup через worker).
- `last_used_at`: opportunistic update от Hydra (token-issuance event).

## Gotchas

- 1:1 на Phase 1 — намеренный simplification. Phase 5/6 может перейти к 1:N (multiple keys per SA для rotation).
- `hydra_client_id` UNIQUE гарантирует mirror Hydra-side consistency. Side-effect: пересоздание Hydra-client с тем же id → `AlreadyExists`.
- CASCADE FK от ServiceAccount: удаление SA + Hydra cleanup нужно делать атомарно через outbox/worker (Phase 5).
- НЕ хранит секрет client_secret — он только в Hydra (HSM/encrypted-at-rest).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-service-account-service]] [[iam-service-account]] [[iam-federation-trust-policy]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
