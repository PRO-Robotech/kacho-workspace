---
title: SCIMUserMapping
aliases:
  - SCIMUserMapping (iam)
  - scim_user_mapping
category: resource
domain: iam
id_prefix: scim
owner_table: kacho_iam.scim_user_mappings
owner_db: kacho_iam
folder_level: false
status: deprecated
related_rpc:
  - "[[rpc/iam-organization-service]]"
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

# SCIMUserMapping

**Domain**: iam — Phase 6 SCIM endpoint mapping: `(organization_id, scim_external_id)` → `user_id`. Используется при inbound SCIM provisioning (Okta/Azure/Google IDP).
**ID prefix**: `scim_` + `[a-z0-9_]{1,40}` → `^scim_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.scim_user_mappings` (migration 0014).
**Phase 1**: schema-only. SCIM 2.0 endpoint — Phase 6.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^scim_[a-z0-9_]{1,40}$` | |
| `organization_id` | TEXT | FK → organizations(id) CASCADE | NOT NULL |
| `user_id` | TEXT | FK → users(id) CASCADE | NOT NULL |
| `scim_external_id` | TEXT | length 1..256 | external IdP user id (e.g. Okta `id`) |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `scim_user_mappings_pkey` PRIMARY KEY (id)
- `scim_user_mappings_unique` **UNIQUE (organization_id, scim_external_id)** — один внешний id → один user в этой Org
- `scim_user_mappings_org_fk` FK → `organizations(id)` ON DELETE CASCADE
- `scim_user_mappings_user_fk` FK → `users(id)` ON DELETE CASCADE
- CHECK: id-regex, length

## Lifecycle (Phase 6)

- **SCIM POST /Users** → create or update kacho User → INSERT mapping. Идемпотентно: повтор → `ON CONFLICT (organization_id, scim_external_id) DO UPDATE SET user_id=excluded.user_id`.
- **SCIM PATCH/PUT /Users/{id}** → lookup mapping by scim_external_id → update User row.
- **SCIM DELETE /Users/{id}** → set User.disabled=true (soft-delete) либо удалить (per Org policy) → mapping каскадно удаляется.
- **JIT provisioning at SAML login** ([[iam-organization]] `domain` claim): IdP-token contains email с claimed domain → auto-create User + INSERT mapping.

## Gotchas

- `scim_external_id` opaque — каждый IDP имеет свой формат (UUID / numeric / email).
- UNIQUE per organization, не глобально: один и тот же external_id из разных Orgs → разные kacho Users.
- CASCADE FK от User: удаление User автоматически удаляет mappings (cleanup).
- Phase 6 политика soft-delete vs hard-delete — настройка per Org (SCIM `userManagement` config).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-organization-service]] [[iam-organization]] [[iam-user]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
