---
title: vpc-apps-kacho-api-network
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - network
---

# kacho-vpc/internal/apps/kacho/api/network

**Path**: `kacho-vpc/internal/apps/kacho/api/network/`
**Implements**: [[../rpc/vpc-network-service|NetworkService]]
**Imports**: [[vpc-domain]], [[vpc-repo-kacho]], [[corelib-operations]], [[corelib-outbox]], [[vpc-clients]] (project existence check)

Use-case slice per Network — Clean Architecture: handler.go (gRPC adapter) + use-case go-файлы (бизнес-логика).

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter; parse req → useCase.Run → format resp |
| `iface.go` | port-интерфейсы для use-case (Repo, `ProjectClient`) |
| `helpers.go` | shared validation helpers |
| `create.go` | `CreateNetworkUseCase` — project existence check (async, KAC-94 I.4; через `ProjectClient.Exists`) + inline default-SG (если `KACHO_VPC_DEFAULT_SG_INLINE=true`) + outbox.Emit |
| `delete.go` | check empty (no subnets/RT/SG) → soft-or-hard delete + outbox |
| `update.go` | update_mask discipline + OCC если нужно |
| `get.go` | sync read (no Operation) |
| `list.go` | filter + pagination |
| `move.go` | cross-project — re-validate target project (через [[vpc-clients]] `ProjectClient`; колонка `folder_id` = id владельца-проекта) |
| `default_sg.go` | helper для inline default-SG flow (Network.Create) |
| `usecase_test.go` | unit-тесты против [[vpc-repo-kacho-kachomock]] |

## See also

[[../rpc/vpc-network-service]] [[../resources/vpc-network]] [[vpc-clients]] [[../edges/vpc-to-iam-project-exists]]

#packages #kacho-vpc #handler #network
