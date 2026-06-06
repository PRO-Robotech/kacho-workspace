---
title: RouteTableService
aliases:
  - RouteTableService (vpc)
proto_file: kacho/cloud/vpc/v1/route_table_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-routetable]]"
methods_count: 6
async_methods: 3
tags:
  - rpc
  - kacho-vpc
  - routetable
---

# RouteTableService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/route_table_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetRouteTableRequest | RouteTable | sync | |
| List | ListRouteTablesRequest | ListRouteTablesResponse | sync | |
| Create | CreateRouteTableRequest | operation.Operation | **async** | static_routes inline |
| Update | UpdateRouteTableRequest | operation.Operation | **async** | replace или add/remove routes via update_mask |
| Delete | DeleteRouteTableRequest | operation.Operation | **async** | FailedPrecondition если ассоциирован с Subnet |
| ListOperations | ListRouteTableOperationsRequest | ListRouteTableOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/routeTables/{route_table_id}` | Get |
| `GET /vpc/v1/routeTables` | List |
| `POST /vpc/v1/routeTables` | Create |
| `PATCH /vpc/v1/routeTables/{route_table_id}` | Update |
| `DELETE /vpc/v1/routeTables/{route_table_id}` | Delete |
| `GET /vpc/v1/routeTables/{route_table_id}/operations` | ListOperations |

> [!note] Move удалён в KAC-266
> RPC `Move` + `POST /vpc/v1/routeTables/{route_table_id}:move` сняты (contract-removal). См. [[../KAC/KAC-266]].

## See also

[[../packages/vpc-apps-kacho-api-routetable]] [[../resources/vpc-routetable]]

#rpc #kacho-vpc #routetable
