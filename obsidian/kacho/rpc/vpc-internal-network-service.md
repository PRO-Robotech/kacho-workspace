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

Internal-projection Network — раньше нёс инфра-поле `vpn_id` (24-bit data-plane id, KAC-2). **Удалено миграцией 0023** (KAC-79/KAC-36 post-kube-ovn) — underlay теперь управляется kube-ovn, в `networks` нет `vpn_id`.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| SetDefaultSecurityGroupId | SetDefaultSecurityGroupIdRequest | SetDefaultSecurityGroupIdResponse | sync | связать default-SG с Network |

> [!note] Internal-only RPC
> Сохраняется для admin-операций над Network, недоступных tenant'у (default-SG management). Поверх `vpn_id`-related RPC'ов больше нет.

## See also

[[vpc-network-service]] [[../packages/vpc-apps-kacho-services-networkinternal]] [[../resources/vpc-network]]

#rpc #kacho-vpc #internal #network
