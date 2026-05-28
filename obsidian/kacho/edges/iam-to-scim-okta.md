---
title: "iam ← okta: inbound SCIM 2.0 (Okta SCIM 2.0 Test App)"
aliases:
  - okta scim
  - iam scim okta
category: edge
caller_repo: okta
callee_repo: kacho-iam
sync_async: sync
protocol: REST/JSON (RFC 7644)
status: deprecated
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - scim
  - sso
---

# okta → iam: inbound SCIM 2.0

**Caller**: Okta SCIM 2.0 Test App / Provisioning Service.
**Callee**: `kacho-iam` SCIM endpoint `https://api.kacho.cloud/scim/v2/{org_id}/...` (port 9093 dedicated).
**Protocol**: REST/JSON per RFC 7644 (SCIM 2.0).
**Sync/Async**: sync per Okta push.
**Status**: **Phase 6 planned**.

## Setup (Phase 6 admin UI)

1. Organization admin создаёт SCIM secret в kacho-iam admin UI → returns:
   - Endpoint: `https://api.kacho.cloud/scim/v2/{org_id}/`
   - Token: `Bearer <opaque>` (one-time displayed; stored hashed `organizations.scim_secret_hash`).
2. В Okta admin → Provisioning → SCIM 2.0:
   - SCIM connector base URL: `https://api.kacho.cloud/scim/v2/{org_id}/`
   - Unique identifier: `userName`
   - Authentication Mode: HTTP Header → `Authorization: Bearer <token>`
   - Supported Provisioning Actions: Create / Update / Deactivate / Push Groups.
3. Test connection → Okta makes `GET /ServiceProviderConfig` → success.

## Inbound calls (Okta → kacho-iam)

| Okta action | HTTP | Endpoint |
|---|---|---|
| Push User | POST | `/Users` |
| Update User | PATCH | `/Users/{id}` |
| Deactivate User | PATCH (`active=false`) | `/Users/{id}` |
| Push Group | POST | `/Groups` |
| Add member | PATCH | `/Groups/{id}` (op `add`) |
| Remove member | PATCH | `/Groups/{id}` (op `remove`) |
| Sync test | GET | `/ServiceProviderConfig` / `/Schemas` |

## Provisioning flow (Phase 6)

1. Okta `POST /Users` (Okta event "User assigned to app").
2. kacho-iam verifies Bearer token → matches `org_id`.
3. Maps Okta `externalId` → kacho user via `scim_user_mappings` ([[../resources/iam-scim-user-mapping]]).
4. New user: create row + bootstrap Kratos identity ([[iam-to-kratos-admin]]).
5. Add to Organization → Account binding.
6. Return SCIM 2.0 Response с `meta.created`.
7. Emit audit + optional CAEP push.

## Deactivation (`active=false`)

1. PATCH op `replace active=false`.
2. kacho-iam soft-disable user.
3. Revoke all sessions (CAEP `session.revoked` ≤10s).
4. Revoke pending SA OAuth clients owned by user (if any).
5. Schedule GDPR cool-off (Phase 7 erasure-pipeline 30d).

## Errors

| kacho response | Meaning |
|---|---|
| 401 | Bearer invalid / org_id mismatch |
| 409 | duplicate externalId (idempotent recover via upsert) |
| 400 | malformed schema |
| 5xx | retry advised |

## Notes

- Okta provisioning interval — configurable (5min default).
- kacho-iam rate-limit per-org (token bucket; configurable).
- All inbound SCIM logged audit-pipeline (Phase 9, Kafka + ClickHouse).

## See also

[[iam-to-scim-azure]] [[iam-to-scim-google]] [[iam-to-kratos-admin]] [[../rpc/iam-scim-v2]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-organization]] [[../packages/iam-service-scim]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #scim #sso
