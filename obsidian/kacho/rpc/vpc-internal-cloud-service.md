---
title: InternalCloudService
aliases:
  - InternalCloudService (vpc)
proto_file: kacho/cloud/vpc/v1/internal_cloud_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
related_resource: "[[resources/vpc-addresspool]]"
methods_count: 3
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
---

# InternalCloudService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/internal_cloud_service.proto`
**Backend**: `kacho-vpc:9091`
**Public/Internal**: **cluster-internal-only**

Cloud-level admin: привязка AddressPool selector'а к Cloud → resolution chain для IPAM (per-Cloud default pool).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| SetPoolSelector | SetCloudPoolSelectorRequest | SetCloudPoolSelectorResponse | sync | назначить default-pool для cloud |
| UnsetPoolSelector | UnsetCloudPoolSelectorRequest | UnsetCloudPoolSelectorResponse | sync | сбросить |
| GetPoolSelector | GetCloudPoolSelectorRequest | GetCloudPoolSelectorResponse | sync | читать |

## REST mapping

| HTTP | Method |
|---|---|
| `POST /vpc/v1/clouds/{cloud_id}/poolSelector` | SetPoolSelector |
| `DELETE /vpc/v1/clouds/{cloud_id}/poolSelector` | UnsetPoolSelector |
| `GET /vpc/v1/clouds/{cloud_id}/poolSelector` | GetPoolSelector |

(Все только на internal-listener.)

## See also

[[vpc-internal-address-pool-service]] [[../resources/vpc-addresspool]]

#rpc #kacho-vpc #internal
