---
title: PrivateEndpointService
aliases:
  - PrivateEndpointService (vpc)
proto_file: kacho/cloud/vpc/v1/privatelink/private_endpoint_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-privateendpoint]]"
methods_count: 6
async_methods: 3
tags:
  - rpc
  - kacho-vpc
  - privateendpoint
---

# PrivateEndpointService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/privatelink/private_endpoint_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetPrivateEndpointRequest | PrivateEndpoint | sync | |
| List | ListPrivateEndpointsRequest | ListPrivateEndpointsResponse | sync | |
| Create | CreatePrivateEndpointRequest | operation.Operation | **async** | subnet_id + service kind |
| Update | UpdatePrivateEndpointRequest | operation.Operation | **async** | description, labels, address |
| Delete | DeletePrivateEndpointRequest | operation.Operation | **async** | RESTRICT-FK на Address |
| ListOperations | ListPrivateEndpointOperationsRequest | ListPrivateEndpointOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/endpoints/{private_endpoint_id}` | Get |
| `GET /vpc/v1/endpoints` | List |
| `POST /vpc/v1/endpoints` | Create |
| `PATCH /vpc/v1/endpoints/{private_endpoint_id}` | Update |
| `DELETE /vpc/v1/endpoints/{private_endpoint_id}` | Delete |
| `GET /vpc/v1/endpoints/{private_endpoint_id}/operations` | ListOperations |

## See also

[[../packages/vpc-apps-kacho-api-privateendpoint]] [[../resources/vpc-privateendpoint]]

#rpc #kacho-vpc #privateendpoint
