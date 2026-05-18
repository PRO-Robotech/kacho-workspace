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
| `auth_noop.go` | placeholder для будущей JWT/auth-shim (blocked:kacho-iam) — сейчас no-op |
| `idempotency.go` | `Idempotency-Key` header handling — каш ответ при retry с тем же ключом |
| `request_id.go` | inject `X-Request-Id` header (use upstream или generate) |
| `recovery.go` | panic-recovery middleware |
| `middleware_test.go` | |

## Order (LIFO)

Обычно: recovery → request_id → access_log → idempotency → auth_noop → handler.

## See also

[[apigw-cmd]] [[apigw-restmux]] [[apigw-allowlist]]

#packages #kacho-apigw #middleware
