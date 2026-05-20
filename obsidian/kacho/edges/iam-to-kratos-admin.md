---
title: "iam → kratos-admin: Identity / Session lifecycle"
aliases:
  - iam to kratos
  - kratos admin
category: edge
caller_repo: kacho-iam
callee_repo: ory-kratos
sync_async: sync
protocol: REST/JSON (Kratos Admin API v1)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - identity
---

# iam → kratos-admin: Identity / Session lifecycle

**Caller**: `kacho-iam` (SCIM provisioner + invite + admin handler + session-revoke).
**Callee**: ORY Kratos (`kratos-admin:4434` cluster-internal listener).
**Protocol**: REST/JSON (Kratos Admin API v1).
**Sync/Async**: sync per-call.
**Status**: **Phase 2 (Passkey / WebAuthn + recovery) implemented**; **Phase 6 (SCIM JIT) planned**.

## Calls (Phase 2 + Phase 6)

### Phase 2 (implemented)

- `POST /admin/identities` — INSERT identity (signup → invite flow + admin tool).
- `GET /admin/identities/{id}` — fetch.
- `PUT /admin/identities/{id}` — update traits (`email`, `name`, `groups`, `mfa_enrolled`).
- `DELETE /admin/identities/{id}` — destroy (Phase 7 GDPR erasure pipeline).
- `DELETE /admin/identities/{id}/sessions` — force-logout (session-revoke ≤10s).
- `GET /admin/sessions?identity_id={id}` — list active sessions (admin UI).

### Phase 6 (planned — SCIM bridge)

- Same identity endpoints, batched через `internal/service/scim` worker ([[../packages/iam-service-scim]]).
- Sync inbound SCIM → Kratos identity → kacho-iam User row → scim_user_mappings.

## Authentication

- Kratos Admin port `4434` cluster-internal only.
- Service-account token (rotated 90d) via Kratos `JsonWebTokenAuthorization`.

## Identity schema v2 (Phase 2)

```yaml
$id: https://kacho.cloud/schemas/identity.schema.json
title: Person v2
type: object
properties:
  traits:
    type: object
    properties:
      email:        { type: string, format: email, "ory.sh/kratos": { credentials: { password: { identifier: true }, webauthn: { identifier: true } }, verification: { via: email }, recovery: { via: email } } }
      name:         { type: object, properties: { first: { type: string }, last: { type: string } } }
      account_id:   { type: string }
      organization_id: { type: string, default: "" }
      mfa_enrolled: { type: boolean, default: false }
      provisioning_source: { type: string, enum: ["self", "invite", "scim"], default: "self" }
```

## Error handling

| Kratos response | kacho action |
|---|---|
| 200/201/204 | success |
| 404 | recover-by-create OR propagate `NotFound` |
| 409 (duplicate email) | `AlreadyExists` |
| 4xx | propagate `InvalidArgument` |
| 5xx | retry; circuit-break |

## History

- 2026-05-19 — Phase 2 (KAC-127): WebAuthn/Passkey config + recovery + admin sessions (commit `be3a9713` kacho-deploy + commit `da2d627e` kacho-iam).
- Phase 6 (planned) — SCIM JIT provisioning.

## See also

[[iam-to-hydra-admin]] [[iam-to-scim-okta]] [[iam-to-scim-azure]] [[iam-to-scim-google]] [[iam-to-jackson-saml]] [[../packages/iam-service-scim]] [[../resources/iam-user]] [[../resources/iam-scim-user-mapping]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #identity
