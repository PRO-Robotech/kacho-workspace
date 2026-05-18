---
title: apigw-allowlist
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - security
---

# kacho-api-gateway/internal/allowlist

**Path**: `kacho-api-gateway/internal/allowlist/`

Allowlist для public TLS endpoint — какие RPC'ы могут попадать на edge. Защита от случайного засвечивания `Internal*` методов наружу (CLAUDE.md «Запреты» #6).

## Files

- `list.go` — allowed proto-method strings (например `/kacho.cloud.vpc.v1.NetworkService/Create`); deny-by-default.
- `list_test.go`.

## Pattern

При получении requests на TLS-listener — director проверяет method-string vs allowlist. Если нет — `Unimplemented` (или 404 на REST).

## See also

[[apigw-proxy]] [[apigw-restmux]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #security
