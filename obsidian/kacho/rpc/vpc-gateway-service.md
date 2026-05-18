---
title: GatewayService
aliases:
  - GatewayService (vpc)
proto_file: kacho/cloud/vpc/v1/gateway_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-gateway]]"
methods_count: 7
async_methods: 4
tags:
  - rpc
  - kacho-vpc
  - gateway
---

# GatewayService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/gateway_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetGatewayRequest | Gateway | sync | |
| List | ListGatewaysRequest | ListGatewaysResponse | sync | |
| Create | CreateGatewayRequest | operation.Operation | **async** | shared_egress_gateway type |
| Update | UpdateGatewayRequest | operation.Operation | **async** | name/labels/desc |
| Delete | DeleteGatewayRequest | operation.Operation | **async** | FailedPrecondition если в use в RouteTable |
| Move | MoveGatewayRequest | operation.Operation | **async** | cross-folder |
| ListOperations | ListGatewayOperationsRequest | ListGatewayOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/gateways/{gateway_id}` | Get |
| `GET /vpc/v1/gateways` | List |
| `POST /vpc/v1/gateways` | Create |
| `PATCH /vpc/v1/gateways/{gateway_id}` | Update |
| `DELETE /vpc/v1/gateways/{gateway_id}` | Delete |
| `POST /vpc/v1/gateways/{gateway_id}:move` | Move |
| `GET /vpc/v1/gateways/{gateway_id}/operations` | ListOperations |

## See also

[[../packages/vpc-apps-kacho-api-gateway]] [[../resources/vpc-gateway]]

#rpc #kacho-vpc #gateway
