---
title: SCIM 2.0 (RFC 7644)
aliases:
  - SCIM
  - SCIM v2
  - SCIM 2.0
proto_file: (none — REST/JSON per RFC 7644)
category: rpc
backend: kacho-iam
backend_port: 9093
visibility: public
domain: iam
related_resource: "[[resources/iam-scim-user-mapping]]"
methods_count: 8
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - scim
  - sso
---

# SCIM 2.0 (iam)

**Spec**: RFC 7644 (SCIM 2.0 Protocol) + RFC 7643 (Core Schema). **Not gRPC** — REST/JSON, dedicated port `9093` (отдельный listener — отлично изолируется от main gRPC API).
**Backend**: `kacho-iam:9093`. Public — каждый Organization имеет endpoint URL `https://api.kacho.cloud/scim/v2/<org_id>/`.
**Status**: **Phase 6 planned** (Enterprise SSO + Organization tier). Inbound SCIM: Okta / Azure AD / Google Workspace / Onelogin / JumpCloud / generic SCIM 2.0 IdP push'ит users/groups.

## Endpoints (RFC 7644)

| HTTP | Resource | Notes |
|---|---|---|
| `GET /scim/v2/{org}/Users` | search users (filter + pagination) | |
| `GET /scim/v2/{org}/Users/{id}` | fetch | |
| `POST /scim/v2/{org}/Users` | provision | JIT-create kacho user + map в `scim_user_mappings` ([[../resources/iam-scim-user-mapping]]). |
| `PUT /scim/v2/{org}/Users/{id}` | full replace | |
| `PATCH /scim/v2/{org}/Users/{id}` | partial update | RFC 7644 op-array |
| `DELETE /scim/v2/{org}/Users/{id}` | deprovision | → soft-disable user + revoke sessions (Phase 8 CAEP push) |
| `GET/POST/PATCH/DELETE /scim/v2/{org}/Groups` | groups CRUD | links via Group → ServiceAccount/User |
| `GET /scim/v2/{org}/ServiceProviderConfig` | discovery | RFC 7644 §4 |
| `GET /scim/v2/{org}/Schemas` | schema discovery | |
| `GET /scim/v2/{org}/ResourceTypes` | type discovery | |

## Authentication

- Bearer token per Organization (`scim_secret` — opaque random, stored hashed в `organizations.scim_secret_hash`).
- mTLS опционально (Phase 11 production deployment).
- Каждый запрос на `/scim/v2/{org}/...` — token belongs к org_id или 401.

## JIT user provisioning flow

1. SCIM `POST /Users` → kacho extract `userName`, `emails[primary]`, `name`, `externalId`.
2. Lookup `scim_user_mappings WHERE (org_id, scim_external_id) = (?, externalId)`.
3. Match → update existing user (idempotent).
4. No match → create user + map row + add user to org account.
5. Sync с Kratos identity ([[../edges/iam-to-kratos-admin]]).
6. Emit audit `iam.scim.user.provisioned` + CAEP optional.

## Notes

- SCIM `externalId` unique per (org_id, externalId) — partial UNIQUE в DB.
- Не overlap'ает с api-gateway public listener (отдельный port 9093) → не показывается на api.kacho.cloud root.
- Bridge `kacho-iam` → Kratos: пользователь существует в обоих системах синхронно.

## See also

[[iam-saml-sp]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-organization]] [[../resources/iam-user]] [[../packages/iam-service-scim]] [[../edges/iam-to-scim-okta]] [[../edges/iam-to-scim-azure]] [[../edges/iam-to-scim-google]] [[../edges/iam-to-kratos-admin]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #scim #sso
