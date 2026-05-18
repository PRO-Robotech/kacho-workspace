---
title: corelib-grpcsrv
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - grpc
---

# corelib/grpcsrv

**Path**: `kacho-corelib/grpcsrv/`
**Imports**: `google.golang.org/grpc`, `.../health`, `.../health/grpc_health_v1`, `.../reflection`
**Imported by**: `kacho-vpc/cmd/vpc`, `kacho-resource-manager/cmd/resource-manager`

Bootstrap-helper для gRPC-server с дефолтным набором: health-service (`grpc.health.v1.Health`), server reflection, recovery interceptor.

## Exported functions

- `NewServer(opts ...grpc.ServerOption) *grpc.Server` — создаёт `*grpc.Server`, регистрирует health-svc (`SERVING`) и reflection. Принимает доп. `ServerOption` (TLS creds, interceptor chains).

## Convention

- Каждый сервис в `cmd/<svc>/main.go` зовёт `grpcsrv.NewServer(...)` для public-listener (9090) и отдельно для internal-listener (9091).
- Interceptor chain (UnaryInterceptor) дополняется в самом сервисе: `recovery`, `logging`, `validate`, `auth` (если есть).

## See also

[[vpc-cmd-vpc]] [[rm-cmd]]

#packages #kacho-corelib #grpc
