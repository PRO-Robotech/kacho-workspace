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
methods_count: 2
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

Internal-projection Network. Старое kube-ovn data-plane-id поле удалено миграцией 0023.
**CIL0 (2026-06-13)** переоткрыл инфра-проекцию — но иначе: числовой **SRv6 VRF id**
(`vrf_id`, control-plane-аллоцируемый, migration 0007), отдаётся только internal-методом
`GetNetwork`. См. [[../resources/vpc-network]], [[../edges/vpc-operator-to-cilium-realization]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| SetDefaultSecurityGroupId | SetDefaultSecurityGroupIdRequest | SetDefaultSecurityGroupIdResponse | sync | связать default-SG с Network |
| GetNetwork | GetInternalNetworkRequest | GetInternalNetworkResponse{network, vrf_id} | sync | **CIL0**: Network + инфра vrf_id; REST `GET /vpc/v1/networks/{id}:internal` (internal mux only); authz `vpc.networks.get_internal`/system_admin/acr≥2 |

> [!note] Internal-only RPC
> vrf_id — числовой инфра-идентификатор (security.md §«Инфра-чувствительные данные») →
> ТОЛЬКО на этом сервисе (:9091), никогда на public NetworkService.Get/List и не на
> external TLS edge. Регистрируется в api-gateway только в `vpcInternalAddr`-блоке.

## See also

[[vpc-network-service]] [[../packages/vpc-apps-kacho-services-networkinternal]] [[../resources/vpc-network]]

#rpc #kacho-vpc #internal #network
