---
title: apigw-proxy
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - proxy
  - grpc
---

# kacho-api-gateway/internal/proxy

**Path**: `kacho-api-gateway/internal/proxy/`

Generic gRPC reverse-proxy для бинарных gRPC-клиентов (помимо grpc-gateway REST из [[apigw-restmux]]).

## Files

| File | Содержание |
|---|---|
| `server.go` | proxy gRPC server — принимает client connections, передаёт upstream через director |
| `director.go` | per-RPC routing logic — выбирает backend (vpc/compute/rm/internal) по proto-method или path |
| `director_test.go` | |

## Routing logic

Director смотрит на RPC method-string (`/kacho.cloud.vpc.v1.NetworkService/Create`) → выбирает upstream (vpc public 9090).
Для internal RPC'ов (`/kacho.cloud.vpc.v1.InternalAddressPoolService/*`) — vpcInternal addr — но **только если** заявка пришла на cluster-internal listener (не на TLS edge); см. [[../edges/apigw-internal-vs-tls]].

## See also

[[apigw-restmux]] [[apigw-cmd]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #proxy #grpc
