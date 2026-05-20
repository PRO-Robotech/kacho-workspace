---
title: "iam ← azure-ad: inbound SCIM 2.0 (Microsoft Entra ID)"
aliases:
  - azure scim
  - entra scim
  - iam scim azure
category: edge
caller_repo: microsoft-entra-id
callee_repo: kacho-iam
sync_async: sync
protocol: REST/JSON (RFC 7644)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - scim
  - sso
---

# azure-ad → iam: inbound SCIM 2.0

**Caller**: Microsoft Entra ID (Azure AD) Enterprise Apps SCIM provisioning.
**Callee**: `kacho-iam` SCIM endpoint `https://api.kacho.cloud/scim/v2/{org_id}/...` (port 9093).
**Protocol**: REST/JSON per RFC 7644 (SCIM 2.0 + Microsoft extensions).
**Sync/Async**: sync per Entra push (40-min default sync interval).
**Status**: **Phase 6 planned**.

## Setup (Phase 6)

1. В kacho-iam admin UI создать SCIM secret (per-org).
2. Entra Admin Center → Enterprise applications → New application → Non-gallery SCIM 2.0:
   - Tenant URL: `https://api.kacho.cloud/scim/v2/{org_id}/`
   - Secret Token: `<bearer>`
   - Click Test Connection → Entra makes `GET /ServiceProviderConfig` → success.
3. Map attributes (Entra → kacho):
   - `userPrincipalName` → `userName`
   - `displayName` → `displayName`
   - `mail` → `emails[primary].value`
   - `objectId` → `externalId`
   - `accountEnabled` → `active`

## Quirks vs Okta

- Entra send'ит `PATCH` operations с пустым `value` для `replace active=false` → нормально, поддерживается.
- Entra иногда передаёт `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User` extension с `department`, `manager` — kacho мапит `manager` → kacho `Group` membership (optional, configurable).
- Entra group provisioning — full sync each cycle (vs incremental Okta).
- Entra `meta.location` REQUIRED в response — kacho возвращает абсолютный URL.

## Inbound calls (same SCIM 2.0 contract — см. [[iam-to-scim-okta]])

Endpoints idential — RFC 7644 standard.

## Notes

- Default Entra provisioning cycle: 40 минут (not configurable in free tier).
- Group nesting (Entra-side) — flattened by Entra before push (transitively expanded).
- Entra может отправлять `meta.resourceType` = `User`/`Group` — used for routing.

## See also

[[iam-to-scim-okta]] [[iam-to-scim-google]] [[../rpc/iam-scim-v2]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-organization]] [[../packages/iam-service-scim]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #scim #sso
