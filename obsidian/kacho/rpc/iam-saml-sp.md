---
title: SAML SP endpoints
aliases:
  - SAML
  - SAML SP
  - SAML 2.0 bridge
proto_file: (none — SAML 2.0 XML, REST/HTML endpoints)
category: rpc
backend: kacho-iam
backend_port: 9094
visibility: public
domain: iam
related_resource: "[[resources/iam-organization]]"
methods_count: 6
async_methods: 0
status: deprecated
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - saml
  - sso
---

# SAML SP endpoints (iam)

**Spec**: SAML 2.0 Web Browser SSO Profile (OASIS). Дeлегируется в **Boxyhq Jackson** — open-source SAML/OIDC bridge. **Not gRPC**: REST/XML + browser redirects, dedicated port `9094`.
**Backend**: `kacho-iam:9094` (proxy → Jackson sidecar). Public.
**Status**: **Phase 6 planned**. SAML — second-class citizen vs SCIM (Phase 6 priority — SCIM JIT primary; SAML — для legacy enterprise IdP).

## Endpoints

| HTTP | Resource | Notes |
|---|---|---|
| `GET /saml/{org}/metadata` | SP metadata XML | published per-Organization |
| `POST /saml/{org}/acs` | AssertionConsumerService | accepts IdP SAMLResponse (Base64 + signed) |
| `GET /saml/{org}/sso` | SP-init redirect | redirect → IdP SSO endpoint |
| `POST /saml/{org}/sso` | SP-init POST | for POST-binding |
| `GET /saml/{org}/slo` | SP-init SingleLogout | propagate logout to IdP + Kratos session-revoke |
| `POST /saml/{org}/slo` | IdP-init SLO | inbound logout |

## Configuration per Organization

`organizations.saml_config` (JSONB, Phase 6 migration):
```json
{
  "idp_metadata_url": "https://idp.example.com/metadata",
  "idp_metadata_xml": "<EntityDescriptor>...</EntityDescriptor>",
  "name_id_format": "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
  "binding": "HTTP-POST",
  "sign_requests": true,
  "want_assertions_signed": true,
  "want_assertions_encrypted": false,
  "attr_mapping": {
    "email": "user.email",
    "given_name": "user.firstName",
    "family_name": "user.lastName",
    "groups": "user.groups"
  }
}
```

## Authentication flow (SP-init Phase 6)

1. User → `/saml/{org}/sso?RelayState=<return-url>`.
2. SP (Jackson) generates AuthnRequest → redirect к IdP.
3. IdP authenticates → POST signed SAMLResponse на `/saml/{org}/acs`.
4. SP verifies signature + extract assertions.
5. JIT: lookup user by `name_id` или `email` → create/update + map в `scim_user_mappings` (reuse Phase 6 mapping table).
6. Issue kacho session via Kratos → 302 RelayState.

## Notes

- Jackson sidecar — отдельный container (`boxyhq/jackson:latest`) в kacho-deploy Phase 11 Helm chart.
- Encryption assertions опционально (per-org config).
- DoS-defense: rate-limit `/saml/{org}/acs` (Cloudflare WAF Phase 11).
- Не overlap'ает с api-gateway public mux (отдельный port 9094).

## See also

[[iam-scim-v2]] [[../resources/iam-organization]] [[../resources/iam-scim-user-mapping]] [[../edges/iam-to-jackson-saml]] [[../packages/iam-clients-jackson]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #saml #sso
