---
title: apigw-middleware
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - middleware
---

# kacho-api-gateway/internal/middleware

**Path**: `kacho-api-gateway/internal/middleware/`

HTTP / gRPC middleware-chain для api-gateway.

## Files

| File | Содержание |
|---|---|
| `access_log.go` | request-log: method, path, status, duration, request-id |
| `auth.go` | `AuthInterceptor`: parse Bearer → JWT validate → SubjectLookup → inject `x-kacho-principal-*` (заменил `auth_noop.go`). **Две стратегии** (SEC-J): HMAC-dev (`devSecret`) И Hydra JWKS RS256/ES256/EdDSA (`WithVerifier(TokenVerifier)`). Детект по `alg` в JWT-хедере (`isAsymmetricJWT`). RS256 → JWKS-verify; principal из `kacho_principal_*` (top-level/`ext_claims`), SubjectLookuper — fallback. Bad token / JWKS unreachable → reject Unauthenticated, никогда anonymous. gRPC `authorize` + REST `HTTP` parity. |
| `jwt_verifier.go`+`jwk.go` | RFC 8725 Hydra JWKS verifier (`NewJWTVerifier`, alg-whitelist, kid-pin, iss/aud/exp/nbf, TTL-cache). Реализует `TokenVerifier` port; один инстанс — и principal-path, и DPoP. |
| `kratos_session.go` | Kratos `/whoami` session (cookie `ory_kratos_session`) → principal до JWT-path. |
| `idempotency.go` | `Idempotency-Key` header handling — каш ответ при retry с тем же ключом |
| `request_id.go` | inject `X-Request-Id` header (use upstream или generate) |
| `recovery.go` | panic-recovery middleware |
| `auth_jwks_test.go` | SEC-J: RS256 principal-from-claims, SA, ext_claims, fallback, HMAC coexistence, bad-token reject, JWKS fail-closed, REST parity. |

## Order (LIFO)

Обычно: recovery → request_id → access_log → idempotency → auth (principal) → [dpop] → [authz] → handler.

## See also

[[apigw-cmd]] [[apigw-restmux]] [[apigw-allowlist]] [[SEC-J-gateway-hydra-jwks-authn]] [[api-gateway-to-iam-authorize]]

#packages #kacho-apigw #middleware
