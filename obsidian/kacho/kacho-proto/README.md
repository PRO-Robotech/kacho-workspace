---
title: kacho-proto
aliases:
  - kacho-proto
category: repo
repo: kacho-proto
go_module: github.com/PRO-Robotech/kacho-proto
service_type: proto-stubs
status: stable
tags:
  - kacho
  - proto
  - grpc
---

# kacho-proto

Центральная директория **всех** `.proto`-определений Kachō + сгенерированные Go-stubs.

- Repo: `github.com/PRO-Robotech/kacho-proto`
- Структура: `proto/kacho/cloud/<domain>/v1/*.proto`
- Generated Go: `gen/go/kacho/cloud/<domain>/v1/*.pb.go` (commit'ятся в repo)
- Import path: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1`

## Domains (proto-файлы)

| Domain | Proto-файлов | Назначение |
|---|---|---|
| `vpc` | 22 | Network, Subnet, Address, RouteTable, SecurityGroup, Gateway, PrivateEndpoint, NetworkInterface + Internal* (AddressPool, Region, Zone, Network, Watch, Cloud, NetworkInterface) |
| `compute` | 41 | Instance, Disk, Image, Snapshot, DiskType, Hypervisor, Region, Zone (Geography — owner после KAC-15) |
| `loadbalancer` | 6 | NetworkLoadBalancer, TargetGroup (frozen в 1.0) |
| `resourcemanager` | 5 | Cloud, Folder |
| `organizationmanager` | 3 | Organization (top-level) |
| `operation` | 3 | LRO envelope (`Operation` message, OperationService.Get) |
| `access` | 1 | AAA-stub (auth, access bindings) |
| `api` | 1 | api-listing (cross-domain) |
| `maintenance` | 1 | maintenance windows |
| `reference` | 1 | shared reference types |
| `validation.proto` | 1 (root) | buf.validate annotations |

## Структура одного domain

```
proto/kacho/cloud/<domain>/v1/
├── <resource>.proto                — message + service definition
├── <resource>_service.proto        — RPC list (Create/Get/Update/Delete/List + custom)
├── internal_<resource>_service.proto — admin-only / cross-service RPC
└── ...
```

Package в proto: `package kacho.cloud.<domain>.v1` (всегда `kacho`, не `yandex`).

## Generated stubs

```
gen/go/kacho/cloud/<domain>/v1/
├── *.pb.go              — message structs + getters
├── *_grpc.pb.go         — gRPC client + server interfaces
└── *.pb.gw.go           — grpc-gateway REST handlers
```

## Tooling

- `buf` — lint + breaking-change detection. Конфиг: `buf.yaml` + `buf.gen.yaml`.
- `make gen` — `buf generate` запускает protoc plugins (`protoc-gen-go`, `protoc-gen-go-grpc`, `protoc-gen-grpc-gateway`).
- Commit changes both proto AND generated Go (для удобства import без `protoc` у consumer'ов).

## Зависимости

- **Внутрь**: ни от чего (центр графа).
- **Из вне**: импортируется всеми сервисами (`kacho-corelib`, `kacho-vpc`, `kacho-compute`, `kacho-resource-manager`, `kacho-api-gateway`, `kacho-loadbalancer`).

См. [[../architecture]] для cross-repo графа.

## Конвенции

- Envelope: `metadata` (read-only) + `spec` (mutable) + `status` (computed).
- Reserved field numbers — для backward-compat.
- `buf.validate` annotations для regex/range/required.
- Standard 4 RPCs per resource: `Upsert/Delete/List/Watch` (плюс domain-specific).
- `InternalService` отдельно от public (cluster-internal-only).

#kacho #proto #grpc
