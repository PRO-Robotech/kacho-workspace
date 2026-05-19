---
title: OrganizationService
aliases:
  - OrganizationService (iam)
proto_file: kacho/cloud/iam/v1/organization_service.proto (planned)
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-organization]]"
methods_count: 0
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# OrganizationService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/organization_service.proto` (Phase 6).
**Backend**: `kacho-iam:9090` (public + `:9091` internal for SCIM endpoints).
**Visibility**: public CRUD; SCIM endpoints — internal-only.
**Status**: **Phase 1 — schema only** ([[../resources/iam-organization]] + [[../resources/iam-scim-user-mapping]] + [[../resources/iam-caep-subscriber]] tables). RPC handlers — Phase 6 (Enterprise SSO).

## Planned methods (Phase 6)

| Method | Sync/Async | Note |
|---|---|---|
| Create | async | new B2B Organization tier |
| Get | sync | |
| Update | async | name/display_name/description/labels (immutable: id, cluster_id, domain) |
| Delete | async | RESTRICT FK from accounts/roles/scim mappings |
| List | sync | filter by cluster_id |
| ClaimDomain | async | partial UNIQUE protection on `domain` column |
| RegisterSCIMSubscriber | async | INSERT caep_subscriber row |

## SCIM 2.0 endpoints (internal mux, Phase 6)

| HTTP | Spec |
|---|---|
| `GET /iam/v1/scim/v2/{organizationId}/ServiceProviderConfig` | SCIM service-provider metadata |
| `GET /iam/v1/scim/v2/{organizationId}/Users` | List users |
| `POST /iam/v1/scim/v2/{organizationId}/Users` | Create user + INSERT scim_user_mapping |
| `GET /iam/v1/scim/v2/{organizationId}/Users/{id}` | Get user via mapping |
| `PATCH /iam/v1/scim/v2/{organizationId}/Users/{id}` | Partial update |
| `PUT /iam/v1/scim/v2/{organizationId}/Users/{id}` | Replace |
| `DELETE /iam/v1/scim/v2/{organizationId}/Users/{id}` | Soft-delete или delete (per Org policy) |
| `GET /iam/v1/scim/v2/{organizationId}/Groups` | Group provisioning (Phase 6 stretch) |

## REST mapping (public mux, Phase 6)

| HTTP | Method |
|---|---|
| `POST /iam/v1/organizations` | Create |
| `GET /iam/v1/organizations/{organization_id}` | Get |
| `PATCH /iam/v1/organizations/{organization_id}` | Update |
| `DELETE /iam/v1/organizations/{organization_id}` | Delete |
| `GET /iam/v1/organizations` | List |

## Notes (Phase 1)

- Phase 1 не реализует RPC, только schema (организации Phase 6 будут INSERT'ить rows).
- Domain claim partial UNIQUE — обеспечивает «one Org per domain» globally.
- CAEP subscriber registration — отдельный stub `RegisterSCIMSubscriber` или internal `RegisterCAEPSubscriber` (Phase 8 may split).
- SAML 2.0 — через Boxyhq Jackson bridge (Phase 6); `saml_metadata_url` / `saml_idp_entity_id` поля используются для tenant IdP config.

## See also

[[../resources/iam-organization]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-caep-subscriber]] [[../resources/iam-account]] [[../resources/iam-cluster]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam
