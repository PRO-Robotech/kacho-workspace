---
title: "iam → jackson: SAML bridge"
aliases:
  - iam to jackson
  - saml jackson
category: edge
caller_repo: kacho-iam
callee_repo: boxyhq-jackson
sync_async: sync
protocol: REST/JSON + browser-redirect XML
status: deprecated
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - saml
  - sso
---

# iam → jackson: SAML bridge

**Caller**: `kacho-iam` (port 9094 SAML SP endpoints — [[../rpc/iam-saml-sp]]).
**Callee**: Boxyhq Jackson sidecar (`jackson:5225` cluster-internal).
**Protocol**: REST/JSON + browser-redirect XML.
**Sync/Async**: sync (browser-driven flow).
**Status**: **Phase 6 planned**.

## Why Jackson

SAML 2.0 (OASIS) — XML / DSIG / EncryptedAssertion / SLO — heavy spec. Jackson — open-source bridge:
- Implements SP role correctly (xml-signature verify, cert chain, NameIDFormat).
- Convert SAMLResponse → OIDC ID-token (JWT) внутрь kacho.
- Multi-tenant config (per-org IdP metadata).

## Calls (Phase 6)

| Endpoint | Description |
|---|---|
| `POST /api/v1/saml/config` | upload per-org IdP metadata XML; returns `tenant`/`product`. |
| `GET /api/v1/saml/config/{tenant}` | read SP-side config. |
| `DELETE /api/v1/saml/config/{tenant}` | revoke. |
| `POST /api/oauth/saml` | inbound SAMLResponse → exchange к OIDC code. |
| `POST /api/oauth/token` | code → JWT (Jackson internal OAuth dance). |
| `POST /api/v1/saml/idp/profile/redirect/sso` | SP-init redirect. |

## Configuration data flow

1. Organization admin uploads IdP metadata через kacho-iam admin UI.
2. kacho-iam forwards JSON config → Jackson `POST /api/v1/saml/config`.
3. Jackson stores per-tenant (`{org_id}`, `kacho-cloud`) — config persisted в kacho_iam.organizations.saml_config redundantly.

## Authentication flow (SP-init)

1. Browser → `https://api.kacho.cloud/saml/{org}/sso?RelayState=<...>`.
2. kacho-iam SAML SP listener (port 9094) forwards to Jackson.
3. Jackson generates AuthnRequest → 302 to IdP.
4. IdP user logs in → POST signed SAMLResponse → `https://api.kacho.cloud/saml/{org}/acs`.
5. Jackson verifies signature + extracts assertions.
6. kacho-iam: JIT-create kacho User + scim_user_mappings ([[../resources/iam-scim-user-mapping]]).
7. Kratos session creation → 302 RelayState.

## Error handling

| Jackson response | kacho action |
|---|---|
| 200 + valid assertion | JIT-provision + session |
| 400 (signature fail) | 401 + audit `iam.saml.signature.fail` |
| 5xx | retry init flow; circuit-break |

## Notes

- Encryption assertions опционально per-org (organizations.saml_config.want_assertions_encrypted).
- Jackson — отдельный pod / Docker container в kacho-deploy Phase 11 Helm chart.
- НЕ для machine workloads — those — federation Exchange ([[../rpc/iam-federation-exchange-service]]).

## See also

[[iam-to-kratos-admin]] [[../rpc/iam-saml-sp]] [[../resources/iam-organization]] [[../packages/iam-clients-jackson]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #saml #sso
