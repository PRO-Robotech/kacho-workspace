---
title: "api-gateway: TLS edge vs cluster-internal listener"
aliases:
  - apigw listener split
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-api-gateway
sync_async: sync
protocol: http-listener
status: active
related_tickets:
  - "[[KAC/KAC-94]]"
tags:
  - edge
  - kacho-apigw
  - internal
  - security
---

# api-gateway: listener split (TLS edge vs cluster-internal)

**Repo**: `kacho-api-gateway`
**File**: `internal/restmux/mux.go` + `internal/proxy/director.go`
**KAC**: KAC-50 (initial split), KAC-15 (Geography move)

## Why two listeners

CLAUDE.md «Запреты» #6: `Internal*` методы **никогда** не должны попадать на публичный TLS edge (`api.kacho.local:443`). Они нужны admin-UI / impl-controllers / port-forward — отдельный cluster-internal listener.

## Two endpoints

| Listener | Network exposure | Регистрируется |
|---|---|---|
| **public** (TLS) | `api.kacho.local:443` | tenant-facing RPCs (Network, Subnet, Address, …, RouteTable, SG, Gateway, PE, NI, + Folder/Cloud/Org/Operation/Instance/Disk/…) |
| **internal** (cluster) | `api-gateway.kacho.svc.cluster.local:80` или alias | + `Internal*` RPCs (AddressPool, InternalNetwork, InternalDiskType/Zone/Region для KAC-15; `InternalCloud` удалён KAC-266) |

## Routing logic (director.go)

REST path → выбор backend addr (`vpcAddr` vs `vpcInternalAddr`):
1. `/vpc/v1/addressPools[/...|:...]` → internal.
2. `/vpc/v1/networks/{id}/addressPoolBinding` → internal.
3. Всё остальное `/vpc/v1/...` → public vpc (9090).

(`/vpc/v1/addresses/{id}/addressPoolOverride` + `/vpc/v1/clouds/{cloud_id}/poolSelector` удалены в [[../KAC/KAC-266]].)

Аналогично для compute: `/compute/v1/regions`, `/compute/v1/zones`, `/compute/v1/diskTypes` админ-RPC → computeInternalAddr; остальные `/compute/v1/...` → computeAddr (9090).

## Operation proxy

`/operations/{operation_id}` — local handler ([[../packages/apigw-opsproxy]]) определяет по prefix-у id (vpc=enp, rm=b1g, compute=epd) backend и проксирует туда.

## See also

[[../packages/apigw-restmux]] [[../packages/apigw-proxy]] [[apigw-to-vpc]] [[apigw-to-compute]] [[apigw-to-rm]]

#edge #kacho-apigw #internal #security
