---
title: FederationService
aliases:
  - FederationService (iam)
  - Token Exchange
proto_file: kacho/cloud/iam/v1/federation_service.proto (planned)
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-federation-trust-policy]]"
methods_count: 0
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - federation
---

# FederationService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/federation_service.proto` (Phase 5).
**Backend**: `kacho-iam:9090`.
**Visibility**: **public** — Exchange endpoint требует internet-reachable URL (для GitHub Actions / AWS / GCP / GitLab CI / CircleCI / Buildkite / Bitbucket OIDC providers).
**Status**: **Phase 1 — schema only** ([[../resources/iam-federation-trust-policy]] table). Exchange RPC + trust-policy CRUD — Phase 5 (Workload Identity Federation).

## Planned methods (Phase 5)

| Method | Sync/Async | Note |
|---|---|---|
| CreateTrustPolicy | async | INSERT federation_trust_policy (admin-only) |
| GetTrustPolicy | sync | |
| UpdateTrustPolicy | async | mutable: audience, conditions, enabled, expires_at (NOT issuer/subject_pattern) |
| DeleteTrustPolicy | async | |
| ListTrustPolicies | sync | filter by service_account_id |
| **Exchange** | sync | **RFC 8693 Token Exchange** — accept external JWT, return kacho JWT |

## Exchange endpoint (Phase 5 — RFC 8693)

```
POST /iam/v1/federation/exchange
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:token-exchange
subject_token=<external_oidc_jwt>
subject_token_type=urn:ietf:params:oauth:token-type:jwt
audience=https://api.kacho.cloud
requested_token_type=urn:ietf:params:oauth:token-type:access_token
```

Flow:
1. Parse `subject_token`: header.kid → resolve external IdP JWKS by issuer.
2. Verify signature, parse claims.
3. Lookup `federation_trust_policies WHERE issuer=$iss AND enabled=true AND now() < expires_at`.
4. Match `subject_token.sub` против `subject_pattern` (regex).
5. Apply `additional_claims_filter` + `conditions` (CEL evaluator).
6. Match `audience=$aud`.
7. Issue kacho access_token (DPoP-bound, JWT) с TTL ≤ `max_token_ttl` (max 15min), subject = `service_account_id`.
8. Return RFC 8693 response.

## REST mapping (public mux, Phase 5)

| HTTP | Method |
|---|---|
| `POST /iam/v1/federation/trustPolicies` | CreateTrustPolicy |
| `GET /iam/v1/federation/trustPolicies/{id}` | GetTrustPolicy |
| `PATCH /iam/v1/federation/trustPolicies/{id}` | UpdateTrustPolicy |
| `DELETE /iam/v1/federation/trustPolicies/{id}` | DeleteTrustPolicy |
| `GET /iam/v1/federation/trustPolicies` | ListTrustPolicies |
| `POST /iam/v1/federation/exchange` | Exchange (RFC 8693) |

## Notes (Phase 1)

- Phase 1 не реализует RPC, только schema (`federation_trust_policies` table).
- `subject_pattern` запрещает `*` wildcard — confused-deputy mitigation.
- `max_token_ttl ≤ 15min` — DB-enforced; production принцип short-lived federation tokens.
- Class A (static client_credentials) — отдельный flow через [[../resources/iam-service-account-oauth-client]] на Hydra.
- Class C (SPIFFE/SPIRE in-cluster) — отдельный flow, Phase 10.

## See also

[[../resources/iam-federation-trust-policy]] [[../resources/iam-service-account]] [[../resources/iam-service-account-oauth-client]] [[../resources/iam-oidc-jwks-key]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #federation
