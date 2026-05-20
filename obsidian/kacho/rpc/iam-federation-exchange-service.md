---
title: FederationExchangeService
aliases:
  - FederationExchange (iam)
  - RFC 8693 Token Exchange
proto_file: kacho/cloud/iam/v1/federation_exchange_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-federation-trust-policy]]"
methods_count: 1
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

# FederationExchangeService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/federation_exchange_service.proto` (Phase 5).
**Backend**: `kacho-iam:9090` — public (internet-reachable необходимо для GitHub Actions / AWS / GCP / GitLab CI / CircleCI / Buildkite / Bitbucket OIDC).
**Status**: **Phase 5 planned**. Реализует RFC 8693 Token Exchange. Trust-policy CRUD — отдельно [[iam-trust-policy-service]].

## Method

| Method | Sync/Async |
|---|---|
| **Exchange** | sync — RFC 8693 single-call exchange (external JWT → kacho DPoP-bound access_token) |

## Exchange flow (Phase 5)

Endpoint: `POST /iam/v1/federation/exchange` (Content-Type `application/x-www-form-urlencoded`).

```
grant_type=urn:ietf:params:oauth:grant-type:token-exchange
subject_token=<external_oidc_jwt>
subject_token_type=urn:ietf:params:oauth:token-type:jwt
audience=https://api.kacho.cloud
requested_token_type=urn:ietf:params:oauth:token-type:access_token
```

1. Parse external JWT: header.`kid` → resolve issuer JWKS (cached, см. [[../packages/iam-clients-idp-jwks-cache]]).
2. Verify signature, parse claims.
3. Lookup `federation_trust_policies WHERE issuer=$iss AND enabled=true AND now() < expires_at`.
4. Match `subject_token.sub` regex против `subject_pattern` (**no `*` wildcard** — confused-deputy mitigation).
5. Apply `additional_claims_filter` + linked condition (`condition_id` → CEL evaluate, [[iam-conditions-service]]).
6. Match `audience=$aud`.
7. Sign kacho access_token (DPoP-bound JWT) с TTL ≤ `max_token_ttl` (DB-enforced ceiling 15min). Subject = `service_account_id`.
8. Return RFC 8693 envelope: `{access_token, token_type=DPoP, expires_in, issued_token_type=…access_token}`.

## Supported external IdPs (Phase 5, 8 providers)

GitHub Actions / AWS STS / GCP / GitLab CI / CircleCI / Buildkite / Bitbucket Pipelines / generic OIDC.

## Errors

- `InvalidArgument` — malformed grant_type / subject_token.
- `Unauthenticated` — signature verify failed / `kid` not in cached JWKS.
- `PermissionDenied` — no matching trust-policy / regex mismatch / condition false / audience mismatch.
- `Unavailable` — issuer JWKS endpoint недоступен (fail-closed).

## Notes

- Class A (static client_credentials) — НЕ через Exchange; через [[iam-sa-key-service]] + Hydra `/oauth2/token`.
- Class C (SPIFFE/SPIRE in-cluster) — НЕ через Exchange; см. [[../edges/iam-to-spire]].
- Issued tokens **bound** DPoP/mTLS — replay protection (см. [[../packages/api-gateway-middleware-dpop]]).

## See also

[[iam-trust-policy-service]] [[iam-sa-key-service]] [[../resources/iam-federation-trust-policy]] [[../resources/iam-service-account]] [[../resources/iam-jwks-key]] [[../packages/iam-service-federation]] [[../packages/iam-clients-idp-jwks-cache]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #federation
