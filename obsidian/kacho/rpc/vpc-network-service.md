---
title: NetworkService
aliases:
  - NetworkService (vpc)
proto_file: kacho/cloud/vpc/v1/network_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-network]]"
methods_count: 10
async_methods: 4
tags:
  - rpc
  - kacho-vpc
  - network
---

# NetworkService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/network_service.proto`
**Backend**: `kacho-vpc:9090` (public gRPC)
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetNetworkRequest | Network | sync | NotFound → 404 |
| List | ListNetworksRequest | ListNetworksResponse | sync | filter + page_token |
| Create | CreateNetworkRequest | operation.Operation | **async** | metadata: CreateNetworkMetadata{network_id} |
| Update | UpdateNetworkRequest | operation.Operation | **async** | UpdateMask discipline |
| Delete | DeleteNetworkRequest | operation.Operation | **async** | `FailedPrecondition "network is not empty"` если subnets есть |
| ListSubnets | ListNetworkSubnetsRequest | ListNetworkSubnetsResponse | sync | nav-helper |
| ListSecurityGroups | ListNetworkSecurityGroupsRequest | ListNetworkSecurityGroupsResponse | sync | nav |
| ListRouteTables | ListNetworkRouteTablesRequest | ListNetworkRouteTablesResponse | sync | nav |
| ListOperations | ListNetworkOperationsRequest | ListNetworkOperationsResponse | sync | per-resource ops history |
| Move | MoveNetworkRequest | operation.Operation | **async** | cross-folder move |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/networks/{network_id}` | Get |
| `GET /vpc/v1/networks` | List |
| `POST /vpc/v1/networks` | Create |
| `PATCH /vpc/v1/networks/{network_id}` | Update |
| `DELETE /vpc/v1/networks/{network_id}` | Delete |
| `GET /vpc/v1/networks/{network_id}/subnets` | ListSubnets |
| `GET /vpc/v1/networks/{network_id}/security_groups` | ListSecurityGroups |
| `GET /vpc/v1/networks/{network_id}/route_tables` | ListRouteTables |
| `GET /vpc/v1/networks/{network_id}/operations` | ListOperations |
| `POST /vpc/v1/networks/{network_id}:move` | Move |

## See also

[[../packages/vpc-apps-kacho-api-network]] [[../resources/vpc-network]] [[vpc-internal-network-service]]

#rpc #kacho-vpc #network
