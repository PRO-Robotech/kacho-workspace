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
methods_count: 11
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
| Create | CreateAddressPoolRequest | AddressPool | sync | CIDR-list (v4/v6 split, KAC-71); overlap per kind → FailedPrecondition (KAC-272) |
| Get | GetAddressPoolRequest | AddressPool | sync | |
| List | ListAddressPoolsRequest | ListAddressPoolsResponse | sync | |
| Update | UpdateAddressPoolRequest | AddressPool | sync | **FieldMask `update_mask`** (unify, evgeniy AP-13): name/desc/labels/is_default/selector_labels/selector_priority. immutable (kind/zone_id/CIDR) в mask → InvalidArgument; пустой mask → full-PATCH. **НЕ CIDR** (KAC-269) |
| Delete | DeleteAddressPoolRequest | DeleteAddressPoolResponse | sync | RESTRICT если связан |
| AddCidrBlocks | AddAddressPoolCidrBlocksRequest | AddressPool | sync | KAC-269: append v4/v6 + dedup + freelist-дельта; KAC-272: overlap per kind → FailedPrecondition |
| RemoveCidrBlocks | RemoveAddressPoolCidrBlocksRequest | AddressPool | sync | KAC-269: use-guard (allocated IP → FailedPrecondition) + free_ips cleanup |
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
| `POST /vpc/v1/addressPools/{address_pool_id}:addCidrBlocks` | AddCidrBlocks |
| `POST /vpc/v1/addressPools/{address_pool_id}:removeCidrBlocks` | RemoveCidrBlocks |
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

> [!note] KAC-269 — CIDR-управление как у Subnet
> Proto убрал `replace_v4/v6_cidr_blocks` + `v4/v6_cidr_blocks` из `UpdateAddressPoolRequest` —
> CIDR через Update больше **не меняется**. Добавлены `AddCidrBlocks` / `RemoveCidrBlocks`
> (sync, parity с Subnet `:addCidrBlocks`/`:removeCidrBlocks`). Add: append + dedup +
> `AddCidrToFreelist` только для новой v4-дельты + init v6-cursor если v6 впервые. Remove:
> use-guard `CountAllocatedInCidrs` (выделенный external-IP в CIDR → FailedPrecondition,
> verbatim "address pool CIDR <cidr> has allocated addresses"), `DeleteFreelistForCidrs`,
> запрет опустошить пул (InvalidArgument). Атомарность remove vs alloc: DELETE free_ips
> (row-lock) → use-check в одной writer-TX. См. [[../KAC/KAC-269]].

> [!note] Unify partial-update → FieldMask (skill evgeniy AP-13)
> `UpdateAddressPoolRequest` переведён с per-field флагов (`update_is_default` /
> `replace_labels` / `replace_selector_labels` / `update_selector_priority`,
> tags 4/7/9/11 → `reserved`) на единый `google.protobuf.FieldMask update_mask`
> (tag 17) — паритет со всеми прочими VPC Update-RPC. Дисциплина как у Subnet
> (§4.4): immutable (kind/zone_id/CIDR) в mask → InvalidArgument, unknown →
> InvalidArgument (`corevalidate.UpdateMask`), пустой mask → full-PATCH мутабельных
> полей. Поведение «один default на (zone, kind)» не изменилось (второй default →
> AlreadyExists). Причина: две конвенции partial-update в одном API дали
> silent-no-op в UI (форма слала `update_mask`, бэкенд молча игнорировал
> `is_default` без `update_is_default`). См. skill `evgeniy` AP-13.

> [!note] KAC-272 — DB-level CIDR overlap prevention
> `Create` / `AddCidrBlocks` нормализуют CIDR-блоки в child-таблицу `address_pool_cidrs`
> (`EXCLUDE USING gist (kind WITH =, block && )`, миграция 0004) в той же writer-TX. CIDR пулов
> одного `kind` не пересекаются (внутри пула И между пулами) — иначе IPAM аллоцирует один
> external-IP дважды. 23P01 → `FailedPrecondition` «address pool CIDRs can not overlap»; sync
> within-request precheck → `InvalidArgument` тем же текстом. `RemoveCidrBlocks` освобождает
> диапазон (`DeleteCidrBlocks`). См. [[../KAC/KAC-272]].

## See also

[[../packages/vpc-apps-kacho-api-addresspool]] [[../resources/vpc-addresspool]]

#rpc #kacho-vpc #internal #addresspool
