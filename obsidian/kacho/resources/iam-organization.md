---
title: Organization
aliases:
  - Organization (iam)
  - iam Organization
category: resource
domain: iam
id_prefix: org
owner_table: kacho_iam.organizations
owner_db: kacho_iam
folder_level: false
status: planned
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

# Organization

**Domain**: iam — optional B2B tier between Cluster и Account (Phase 6 SSO target).
**ID prefix**: `org_` + 17-char crockford-base32 → `^org_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.organizations` (Phase 1 / migration 0011).
**Status (Phase 1)**: schema-only — RPC layer появится Phase 6 SCIM/SAML SSO.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^org_[0-9a-hjkmnp-tv-z]{17}$` | |
| `cluster_id` | TEXT | FK → clusters(id) RESTRICT | NOT NULL |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE globally |
| `display_name` | TEXT | length <=128 | optional |
| `description` | TEXT | length <=256 | |
| `domain` | TEXT NULL | RFC 1035 (3..253) | partial UNIQUE WHERE NOT NULL — domain claim |
| `scim_endpoint_url` | TEXT | `^https://` или empty | inbound SCIM (Phase 6) |
| `saml_metadata_url` | TEXT | `^https://` или empty | SAML IdP (Phase 6) |
| `saml_idp_entity_id` | TEXT | length <=512 | |
| `labels` | JSONB | `kacho_labels_valid` | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `organizations_pkey` PRIMARY KEY (id)
- `organizations_name_unique` UNIQUE (name) — глобальная уникальность
- `organizations_domain_unique` partial UNIQUE (domain) WHERE `domain IS NOT NULL` — domain claim
- `organizations_cluster_fk` FK → `clusters(id)` ON DELETE RESTRICT
- CHECK: id-regex, name-regex, length, domain-regex, scim/saml `https://` prefix, labels-valid

## FK contract (in-bound)

- `accounts.organization_id → organizations(id) ON DELETE RESTRICT` (nullable — personal-account NULL)
- `roles.organization_id → organizations(id) ON DELETE RESTRICT` (org-scoped custom roles; см. [[iam-role]])
- `scim_user_mappings.organization_id → organizations(id) ON DELETE CASCADE` (см. [[iam-scim-user-mapping]])

## Lifecycle

- **Create / Update / Delete** — Phase 6 (async через `Operation`).
- **Phase 1**: schema-ready, но RPC handler ещё не реализован.
- Domain-claim — установка `domain` claim'ит email-namespace для JIT-provisioning через SCIM/SAML.

## Gotchas

- `cluster_id` immutable (вся иерархия привязана к singleton).
- `domain` нельзя поменять после установки на другой уже-занятый — partial UNIQUE.
- В personal-account deployments (`organization_id IS NULL`) org-scope features (SCIM/SAML/domain-claim) недоступны.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-organization-service]] [[iam-cluster]] [[iam-account]] [[iam-scim-user-mapping]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
