---
title: apigw-cmd
category: package
repo: kacho-api-gateway
layer: cmd
tags:
  - packages
  - kacho-apigw
  - cmd
  - composition-root
---

# kacho-api-gateway/cmd/api-gateway

**Path**: `kacho-api-gateway/cmd/api-gateway/main.go`

Composition root для api-gateway binary.

## Responsibilities

1. [[corelib-config]] `Load` → [[apigw-config]].
2. Init slogger (без OTEL в gw обычно, или минимально).
3. Build addr-map (`addrs["rm"]`, `addrs["vpc"]`, `addrs["vpcInternal"]`, `addrs["compute"]`, `addrs["computeInternal"]`).
4. Build [[apigw-restmux]] (grpc-gateway REST mux, регистрация HandlerFromEndpoint).
5. Build [[apigw-proxy]] (gRPC pass-through proxy для бинарных клиентов).
6. Build [[apigw-opsproxy]] (per-domain operation routing).
7. Wrap middleware-chain ([[apigw-middleware]]).
8. Start 2 listeners: TLS edge (public) + cluster-internal listener.
9. [[corelib-shutdown]] graceful.

## See also

[[apigw-config]] [[apigw-restmux]] [[apigw-proxy]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #cmd #composition-root
