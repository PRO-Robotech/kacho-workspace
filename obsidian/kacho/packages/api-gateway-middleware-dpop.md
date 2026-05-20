---
title: "api-gateway internal/middleware/dpop"
aliases:
  - apigw dpop middleware
  - dpop verifier
category: packages
repo: kacho-api-gateway
layer: middleware
status: done
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-api-gateway
  - middleware
  - dpop
  - oauth
---

# api-gateway `internal/middleware/dpop`

Phase 2 implemented (KAC-127 commit `d9796c8`). RFC 9449 DPoP proof verification + RFC 8705 mTLS-bound JWT + RFC 9470 step-up + RFC 7517/7638 JWK thumbprint cnf.

## Files

- `internal/middleware/dpop/dpop.go` — DPoP proof structure parse + per-request verify
- `internal/middleware/dpop/dpop_replay_cache.go` — in-process sharded LRU
- `internal/middleware/dpop/dpop_http_middleware.go` — REST handler wrapper
- `internal/middleware/dpop/jwt_verifier.go` — JWT validate + cnf binding check
- `internal/middleware/dpop/jwk.go` — RFC 7517 JWK parse / RFC 7638 thumbprint
- `internal/middleware/dpop/mtls_bound.go` — RFC 8705 cert-bound (`x5t#S256` claim)
- `internal/middleware/dpop/stepup_gate.go` — RFC 9470 ACR step-up
- `internal/middleware/dpop/introspection_cache.go` — Hydra introspect responses cached
- `internal/handler/logout_handler.go` — Back-Channel Logout endpoint
- `internal/clients/session_revocations_client.go` — query kacho-iam blocklist

## Verification flow (per-request)

```
1. Extract Authorization header → "DPoP <token>"
2. Extract DPoP header → "<dpop-proof-jwt>"
3. Parse DPoP-proof JWT (signed by client; header.alg = ES256/EdDSA)
4. Verify proof signature against header.jwk (public)
5. Verify proof claims:
     - htm == HTTP method
     - htu == request URI (sans query)
     - iat fresh (≤30s)
     - jti not in DPoP replay cache (insert + 5min TTL)
6. Compute jkt = thumbprint(header.jwk)
7. Parse access-token JWT (RFC 8725 hardened — alg pin, kid required)
8. Verify access-token signature against kacho JWKS
9. Verify access-token.cnf.jkt == computed jkt → bound
10. If RPC requires step-up: verify access-token.acr satisfies (e.g., aal2)
11. If TLS-bound (mTLS): verify access-token.cnf.x5t#S256 == hashedClientCert
12. Forward to authz middleware ([[api-gateway-middleware-authz]])
```

## Sharded DPoP replay cache (Phase 2)

```go
type ReplayCache struct {
    shards [64]*shard
}
type shard struct {
    mu  sync.RWMutex
    lru *simplelru.LRU
}

// Hash(jti) % 64 → shard → lock-free per-shard
// Persisted backstop via Postgres dpop_replay_jti (Phase 2 migration 0016)
```

→ Single-instance: ≥100k jti/s throughput. Multi-instance: Postgres backstop covers cross-replica replay.

## Configuration (KAC-127 Phase 2 adds 12 env vars)

| ENV | Default | Description |
|---|---|---|
| `KACHO_API_GATEWAY_AUTHN_ENABLE_DPOP` | `true` | feature toggle |
| `KACHO_API_GATEWAY_DPOP_PROOF_TTL_S` | 30 | proof iat tolerance |
| `KACHO_API_GATEWAY_DPOP_REPLAY_TTL_S` | 300 | jti cache TTL |
| `KACHO_API_GATEWAY_JWT_ISSUER` | (configurable from `ResolvedHydraIssuer()`) | trusted JWT iss |
| `KACHO_API_GATEWAY_JWT_AUDIENCE` | `https://api.kacho.cloud` | configurable |
| `KACHO_API_GATEWAY_JWKS_URI` | `https://api.kacho.cloud/.well-known/jwks.json` | configurable |
| `KACHO_API_GATEWAY_JWKS_CACHE_TTL_S` | 300 | JWKS refresh |
| `KACHO_API_GATEWAY_STEPUP_REQUIRED_RPCS` | (list) | comma-separated proto methods |
| `KACHO_API_GATEWAY_INTROSPECTION_CACHE_TTL_S` | 60 | Hydra introspect cache |
| `KACHO_API_GATEWAY_MTLS_BOUND_ENABLED` | `false` | toggle RFC 8705 |
| `KACHO_API_GATEWAY_BCL_ENABLED` | `true` | Back-Channel Logout |
| `KACHO_API_GATEWAY_DPOP_FAIL_CLOSED` | `true` | reject on verify fail |

## Test coverage (Phase 2)

99 tests passing под `-race` (KAC-127 acceptance `d9796c8`):
- Unit: each proof verify scenario (alg confusion, htm mismatch, iat skew, jti duplicate, etc.)
- Concurrent replay race (100 goroutines → exactly 1 success).
- E2E Hydra testcontainer — real token verify roundtrip.
- DPoP-bound JWT: cnf.jkt validation.
- mTLS-bound: x5t#S256 claim.
- Step-up: ACR enforcement per RPC.
- BCL: logout propagation.

## Imports

- `gopkg.in/go-jose/go-jose.v3`
- `github.com/hashicorp/golang-lru/v2`
- `github.com/PRO-Robotech/kacho-corelib/observability`
- `kacho-proto/.../iam/v1` — session_revocations client

## Imported by

- `cmd/kacho-api-gateway/main.go`

## See also

[[api-gateway-middleware-authz]] [[../resources/iam-session-revocation]] [[../resources/iam-jwks-key]] [[../edges/iam-to-hydra-admin]] [[../KAC/KAC-127]]

#packages #kacho-api-gateway #middleware #dpop #oauth
