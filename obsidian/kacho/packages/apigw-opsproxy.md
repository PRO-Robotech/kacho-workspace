---
title: apigw-opsproxy
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - operation
---

# kacho-api-gateway/internal/opsproxy

**Path**: `kacho-api-gateway/internal/opsproxy/`

Per-domain OperationService proxy — `/operations/{id}` приходит на gw, надо понять, в какой backend проксировать.

## Files

- `proxy.go` — gRPC handler, который реализует `OperationServiceServer` локально и роутит `Get`/`Cancel` по prefix-у operation-id:
  - `enp...`, `e9b...` → vpc backend.
  - `epd...` → compute backend.
  - `iop...` → iam backend (KAC-105).
  - `nlp...` → nlb backend (KAC-161).
  - legacy `vpc_...` → vpc backend.
  - (KAC-124: `b1g`/`bpf`/`rm_` префиксы удалены — resource-manager retire.)
- `proxy_test.go`.

## Why local impl

`RegisterOperationServiceHandlerServer` (а не `HandlerFromEndpoint`) — потому что **per-domain routing** не делается grpc-gateway автоматически: gw регистрирует один URL → один backend. Локальная реализация смотрит id, дёрнет правильный grpc-stub upstream.

## Metadata propagation (KAC-169)

`Get`/`Cancel` обязаны конвертировать **incoming** gRPC metadata → **outgoing** перед вызовом backend через helper `propagateMetadata(ctx)`. Без этого `x-kacho-principal-{type,id,display-name}` (set by `restmux.WithMetadata`) теряются — backend видит анонимный principal и его per-RPC authz возвращает NotFound/PermissionDenied. Тот же pattern что в [[apigw-proxy]] (`director.go` / `shimproxy.go`). См. KAC-169.

## See also

[[apigw-restmux]] [[../rpc/operation-service]] [[corelib-ids]] (prefix-determinism)

#packages #kacho-apigw #operation
