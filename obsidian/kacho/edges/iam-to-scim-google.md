---
title: "iam ← google-workspace: inbound SCIM 2.0"
aliases:
  - google scim
  - workspace scim
  - iam scim google
category: edge
caller_repo: google-workspace
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

# google-workspace → iam: inbound SCIM 2.0

**Caller**: Google Workspace Identity Platform (Cloud Identity premium).
**Callee**: `kacho-iam` SCIM endpoint `https://api.kacho.cloud/scim/v2/{org_id}/...` (port 9093).
**Protocol**: REST/JSON per RFC 7644.
**Status**: **Phase 6 planned**.

## Setup

1. Создать SCIM secret в kacho-iam admin UI.
2. Google Admin → Apps → Web apps → Add custom SAML+SCIM app:
   - SCIM Base URL: `https://api.kacho.cloud/scim/v2/{org_id}/`
   - Auth: Bearer token.
3. Attribute mapping (Google → kacho):
   - `primaryEmail` → `userName`
   - `name.givenName` / `name.familyName` → name traits
   - `id` (Google directory id) → `externalId`
   - `suspended` (boolean inverted) → `active`

## Quirks vs Okta/Entra

- Google использует `urn:ietf:params:scim:schemas:extension:google:2.0:User` extension с `customSchemas`, `organizations[]` (job title, department).
- Group provisioning через `Groups[]` arrays — kacho поддерживает batch member changes.
- Google `delete` отправляется как PATCH `active=false` + scheduled hard-delete (kacho mirror — Phase 7 GDPR erasure pipeline).
- Realtime sync optional (push); polling default 30min.

## Inbound calls

RFC 7644 standard — см. [[iam-to-scim-okta]].

## Notes

- Google Cloud Identity Premium / Workspace Enterprise tier required.
- Multi-OU sync supported (Google OU hierarchy → kacho Groups).

## See also

[[iam-to-scim-okta]] [[iam-to-scim-azure]] [[../rpc/iam-scim-v2]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-organization]] [[../packages/iam-service-scim]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #scim #sso
