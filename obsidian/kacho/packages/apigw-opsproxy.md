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
  - `enp...` → vpc backend.
  - `b1g...` → rm backend.
  - `epd...` → compute backend.
- `proxy_test.go`.

## Why local impl

`RegisterOperationServiceHandlerServer` (а не `HandlerFromEndpoint`) — потому что **per-domain routing** не делается grpc-gateway автоматически: gw регистрирует один URL → один backend. Локальная реализация смотрит id, дёрнет правильный grpc-stub upstream.

## See also

[[apigw-restmux]] [[../rpc/operation-service]] [[corelib-ids]] (prefix-determinism)

#packages #kacho-apigw #operation
