---
title: SubnetService
aliases:
  - SubnetService (vpc)
proto_file: kacho/cloud/vpc/v1/subnet_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-subnet]]"
methods_count: 9
async_methods: 5
tags:
  - rpc
  - kacho-vpc
  - subnet
---

# SubnetService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/subnet_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetSubnetRequest | Subnet | sync | |
| List | ListSubnetsRequest | ListSubnetsResponse | sync | |
| Create | CreateSubnetRequest | operation.Operation | **async** | EXCLUDE constraint check |
| Update | UpdateSubnetRequest | operation.Operation | **async** | name/labels/desc; CIDR — отдельно |
| AddCidrBlocks | AddSubnetCidrBlocksRequest | operation.Operation | **async** | расширить v4/v6 list (KAC-71) |
| RemoveCidrBlocks | RemoveSubnetCidrBlocksRequest | operation.Operation | **async** | сужение, проверка no-used |
| Delete | DeleteSubnetRequest | operation.Operation | **async** | RESTRICT если есть Address |
| ListUsedAddresses | ListUsedAddressesRequest | ListUsedAddressesResponse | sync | IPAM-utilization |
| ListOperations | ListSubnetOperationsRequest | ListSubnetOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/subnets/{subnet_id}` | Get |
| `GET /vpc/v1/subnets` | List |
| `POST /vpc/v1/subnets` | Create |
| `PATCH /vpc/v1/subnets/{subnet_id}` | Update |
| `POST /vpc/v1/subnets/{subnet_id}:add-cidr-blocks` | AddCidrBlocks |
| `POST /vpc/v1/subnets/{subnet_id}:remove-cidr-blocks` | RemoveCidrBlocks |
| `DELETE /vpc/v1/subnets/{subnet_id}` | Delete |
| `GET /vpc/v1/subnets/{subnet_id}/addresses` | ListUsedAddresses |
| `GET /vpc/v1/subnets/{subnet_id}/operations` | ListOperations |

> [!note] Move + Relocate удалены в KAC-266
> RPC `Move` (`:move`) и `Relocate` (`:relocate`) сняты (contract-removal). См. [[../KAC/KAC-266]].

## See also

[[../packages/vpc-apps-kacho-api-subnet]] [[../resources/vpc-subnet]]

#rpc #kacho-vpc #subnet
