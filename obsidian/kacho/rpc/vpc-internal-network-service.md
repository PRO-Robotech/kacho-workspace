---
title: InternalNetworkService
aliases:
  - InternalNetworkService (vpc)
proto_file: kacho/cloud/vpc/v1/internal_network_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
related_resource: "[[resources/vpc-network]]"
methods_count: 1
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - network
---

# InternalNetworkService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/internal_network_service.proto`
**Backend**: `kacho-vpc:9091`
**Public/Internal**: **cluster-internal-only**

Internal-projection Network — раньше нёс инфра-поле data-plane id (kube-ovn-эпоха). **Удалено миграцией 0023** (эпики KAC-36/79/80) — в `networks` этого поля больше нет.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| SetDefaultSecurityGroupId | SetDefaultSecurityGroupIdRequest | SetDefaultSecurityGroupIdResponse | sync | связать default-SG с Network |

> [!note] Internal-only RPC
> Сохраняется для admin-операций над Network, недоступных tenant'у (default-SG management). Прежних data-plane-id-related RPC'ов больше нет.

## See also

[[vpc-network-service]] [[../packages/vpc-apps-kacho-services-networkinternal]] [[../resources/vpc-network]]

#rpc #kacho-vpc #internal #network
