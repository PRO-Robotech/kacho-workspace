---
title: kacho-api-gateway
aliases:
  - kacho-apigw
  - kacho-api-gateway
category: repo
repo: kacho-api-gateway
go_module: github.com/PRO-Robotech/kacho-api-gateway
service_type: edge
status: stable
related_packages:
  - "[[packages/apigw-restmux]]"
  - "[[packages/apigw-proxy]]"
  - "[[packages/apigw-opsproxy]]"
tags:
  - kacho
  - kacho-apigw
  - grpc
  - rest
  - edge
---

# kacho-api-gateway

Edge-сервис Kachō — **gRPC-proxy + grpc-gateway REST mux** перед back-end сервисами.

- Repo: `github.com/PRO-Robotech/kacho-api-gateway`
- Тип: edge (stateless).

## Назначение

1. **gRPC proxy** — клиент → api-gateway → backend (vpc/compute/rm) по prefix-routing id.
2. **REST mux** через `grpc-gateway` — REST → gRPC проброс с `:verb` action-suffixes (YC-style).
3. **Listener split** (KAC-50):
   - `:8080` plain HTTP/gRPC (cluster-internal + UI + admin tooling — admin paths exposed)
   - TLS listener (optional) для `yc` CLI compat (admin paths filtered out)
4. **Operation routing** — `OperationService.Get(id)` маршрутизируется по первым 3 chars id'а в правильный backend.

## Структура пакетов

```
cmd/
└── api-gateway/main.go        — bootstrap + listener-split

internal/
├── config/                  — viper YAML config.
├── proxy/                   — gRPC-proxy (Unknown service handler передаёт unknown methods в backend).
├── restmux/                 — grpc-gateway REST mux registration:
│   ├── mux.go                  registers VPC/Compute/RM services + Internal* under vpcInternalAddr block.
│   └── mux_test.go             contract tests для allowlist.
├── opsproxy/                — OperationService.Get prefix-routing logic.
├── allowlist/               — public RPC allowlist (НЕ публиковать Internal.* на TLS endpoint).
├── middleware/              — gRPC/HTTP interceptors:
│   ├── access_log.go           structured access log.
│   ├── recovery.go             panic recovery → INTERNAL.
│   ├── request_id.go           per-request UUID + propagation.
│   ├── idempotency.go          Idempotency-Key support.
│   ├── auth_noop.go            placeholder AAA (always allow).
│   └── middleware_test.go
├── health/                  — `/healthz` endpoint.
└── gateway_test/            — integration tests.
```

## Routing

| HTTP path | gRPC method | Backend |
|---|---|---|
| `/vpc/v1/networks` | `kacho.cloud.vpc.v1.NetworkService` | vpc:9090 |
| `/vpc/v1/networks/{id}:move` | `NetworkService.Move` | vpc:9090 |
| `/vpc/v1/addressPools` | `InternalAddressPoolService` | vpc:9091 (internal) |
| `/compute/v1/instances` | `kacho.cloud.compute.v1.InstanceService` | compute:9090 |
| `/compute/v1/regions` | `RegionService` (после KAC-15) | compute:9091 |
| `/resource-manager/v1/folders` | `FolderService` | resource-manager:9090 |
| `/organization-manager/v1/organizations` | `OrganizationService` | resource-manager:9090 |
| `/operations/{id}` | `OperationService.Get` (proxy by prefix) | by id-prefix |

## Internal mux block

`internal/restmux/mux.go::if vpcInternalAddr != ""` — регистрирует Internal RPC только если задан адрес internal-listener'а (9091). Эти paths exposed на **cluster-internal listener** (для UI/admin), но **НЕ** на external TLS (для `yc` CLI).

Текущие internal paths:
- `/vpc/v1/addressPools*` (InternalAddressPoolService)
- `/vpc/v1/networks/*/addressPoolBinding`
- `/vpc/v1/addresses/*/addressPoolOverride`
- `/vpc/v1/clouds/*/poolSelector`
- `/vpc/v1/addressPools:explainResolution`, `:check`
- (после KAC-15) `/compute/v1/regions*`, `/compute/v1/zones*`

См. [[../kacho-vpc/README#admin-paths|kacho-vpc/README]] §16.x для полного списка admin paths.

## Build-зависимости

- `kacho-proto` — все proto-stubs services которые проксирует.
- `kacho-corelib` — `grpcsrv`, `observability`.

## Cross-repo runtime edges

```
client (yc CLI / curl / UI)
  → api-gateway:8080
    → vpc:9090 / vpc:9091
    → compute:9090 / compute:9091
    → resource-manager:9090
```

См. [[../architecture]] для полного графа.

## Эпики

- **KAC-50** — listener split (public/TLS vs cluster-internal).
- **api-gateway-registrar** агент — регистрирует новые RPC в restmux после rpc-implementer.

#kacho #kacho-apigw #grpc #rest #edge
