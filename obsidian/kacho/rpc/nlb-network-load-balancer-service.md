---
title: NetworkLoadBalancerService
aliases:
  - NetworkLoadBalancerService (nlb)
  - NLB service
proto_file: kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto
category: rpc
backend: kacho-nlb
backend_port: 9090
visibility: public
domain: nlb
related_resource: "[[resources/nlb-load-balancer]]"
methods_count: 12
async_methods: 8
tags:
  - rpc
  - kacho-nlb
  - loadbalancer
---

# NetworkLoadBalancerService (nlb)

**Proto**: `kacho-proto/proto/kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto`
**Backend**: `kacho-nlb:9090` (public gRPC)
**Public/Internal**: public

## Methods (12)

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetNetworkLoadBalancerRequest | NetworkLoadBalancer | sync | NotFound → 404 |
| List | ListNetworkLoadBalancersRequest | ListNetworkLoadBalancersResponse | sync | filter `name=`, page_token, page_size |
| Create | CreateNetworkLoadBalancerRequest | operation.Operation | **async** | metadata: CreateNetworkLoadBalancerMetadata{network_load_balancer_id} |
| Update | UpdateNetworkLoadBalancerRequest | operation.Operation | **async** | UpdateMask; immutable: type/region_id/project_id |
| Delete | DeleteNetworkLoadBalancerRequest | operation.Operation | **async** | sync precheck: deletion_protection, has listeners, has attached TG |
| Start | StartNetworkLoadBalancerRequest | operation.Operation | **async** | precondition: status ∈ {STOPPED, INACTIVE} |
| Stop | StopNetworkLoadBalancerRequest | operation.Operation | **async** | precondition: status ∈ {ACTIVE, INACTIVE} |
| Move | MoveNetworkLoadBalancerRequest | operation.Operation | **async** | cross-project, same-region; blocked if attached TG present |
| AttachTargetGroup | AttachTargetGroupRequest | operation.Operation | **async** | same-region check; M:N pivot ON CONFLICT idempotent |
| DetachTargetGroup | DetachTargetGroupRequest | operation.Operation | **async** | respects `deregistration_delay_seconds` |
| GetTargetStates | GetTargetStatesRequest | GetTargetStatesResponse | sync | computed runtime (deterministic ramp INITIAL→HEALTHY) |
| ListOperations | ListNetworkLoadBalancerOperationsRequest | ListNetworkLoadBalancerOperationsResponse | sync | per-resource history |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Get |
| `GET /nlb/v1/networkLoadBalancers` | List |
| `POST /nlb/v1/networkLoadBalancers` | Create |
| `PATCH /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Update |
| `DELETE /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Delete |
| `POST /nlb/v1/networkLoadBalancers/{id}:start` | Start |
| `POST /nlb/v1/networkLoadBalancers/{id}:stop` | Stop |
| `POST /nlb/v1/networkLoadBalancers/{id}:move` | Move |
| `POST /nlb/v1/networkLoadBalancers/{id}:attachTargetGroup` | AttachTargetGroup |
| `POST /nlb/v1/networkLoadBalancers/{id}:detachTargetGroup` | DetachTargetGroup |
| `GET /nlb/v1/networkLoadBalancers/{id}/targetStates` | GetTargetStates |
| `GET /nlb/v1/networkLoadBalancers/{id}/operations` | ListOperations |

## FGA Permissions

- `Get` / `List` → `viewer` on `project:<project_id>` или `nlb_load_balancer:<id>`
- `Create` → `editor` on `project:<project_id>`
- `Update` / `Delete` / `Start` / `Stop` / `AttachTargetGroup` / `DetachTargetGroup` → `editor` on `nlb_load_balancer:<id>`
- `Move` → `editor` on src + dst `project`
- `GetTargetStates` / `ListOperations` → `viewer` on `nlb_load_balancer:<id>`

См. [[../packages/nlb-internal-check]] permission_map + [[../packages/nlb-permissions-catalog]].

## See also

[[../packages/nlb-apps-kacho-api-loadbalancer]] [[../resources/nlb-load-balancer]] [[nlb-listener-service]] [[nlb-target-group-service]]

#rpc #kacho-nlb #loadbalancer
