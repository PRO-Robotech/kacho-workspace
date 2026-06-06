---
title: InternalAddressPoolService
aliases:
  - InternalAddressPoolService (vpc)
proto_file: kacho/cloud/vpc/v1/internal_address_pool_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
related_resource: "[[resources/vpc-addresspool]]"
methods_count: 9
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - addresspool
---

# InternalAddressPoolService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto`
**Backend**: `kacho-vpc:9091`
**Public/Internal**: **cluster-internal-only** (admin); kacho-only ресурс (нет в YC).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Create | CreateAddressPoolRequest | AddressPool | sync | CIDR-list (v4/v6 split, KAC-71) |
| Get | GetAddressPoolRequest | AddressPool | sync | |
| List | ListAddressPoolsRequest | ListAddressPoolsResponse | sync | |
| Update | UpdateAddressPoolRequest | AddressPool | sync | replace_cidrs семантика |
| Delete | DeleteAddressPoolRequest | DeleteAddressPoolResponse | sync | RESTRICT если связан |
| BindAsNetworkDefault | BindAsNetworkDefaultRequest | BindResponse | sync | per-Network pool default |
| UnbindNetworkDefault | UnbindNetworkDefaultRequest | BindResponse | sync | |
| ListAddresses | ListAddressPoolAddressesRequest | ListAddressPoolAddressesResponse | sync | какие Address выделены |
| GetUtilization | GetAddressPoolUtilizationRequest | AddressPoolUtilization | sync | free/used per-CIDR |

## REST mapping

| HTTP | Method |
|---|---|
| `POST /vpc/v1/addressPools` | Create |
| `GET /vpc/v1/addressPools/{pool_id}` | Get |
| `GET /vpc/v1/addressPools` | List |
| `PATCH /vpc/v1/addressPools/{pool_id}` | Update |
| `DELETE /vpc/v1/addressPools/{pool_id}` | Delete |
| `POST /vpc/v1/networks/{network_id}/addressPoolBinding` | BindAsNetworkDefault |
| `DELETE /vpc/v1/networks/{network_id}/addressPoolBinding` | UnbindNetworkDefault |
| `GET /vpc/v1/addressPools/{pool_id}/addresses` | ListAddresses |
| `GET /vpc/v1/addressPools/{pool_id}/utilization` | GetUtilization |

> [!warning] Internal-only
> Маршруты `/vpc/v1/addressPools/*` зарегистрированы **только** на internal-listener api-gateway (см. [[apigw-restmux]] vpcInternalAddr блок).

> [!note] Упрощено в KAC-266
> Удалены RPC `BindAsAddressOverride` / `UnbindAddressOverride` (per-Address override),
> `Check`, `ExplainResolution` + соответствующие REST-маршруты. IPAM-cascade сведён к трём шагам
> (`network_default` → `zone_default` → `global_default`; override/selector сняты). `InternalCloudService`
> (Set/Get/UnsetPoolSelector) удалён целиком — см. [[vpc-internal-cloud-service]]. **KEEP**:
> `BindAsNetworkDefault` / `UnbindNetworkDefault`. См. [[../KAC/KAC-266]].

## See also

[[../packages/vpc-apps-kacho-api-addresspool]] [[../resources/vpc-addresspool]]

#rpc #kacho-vpc #internal #addresspool
