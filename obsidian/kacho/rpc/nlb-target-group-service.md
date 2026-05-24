---
title: TargetGroupService
aliases:
  - TargetGroupService (nlb)
proto_file: kacho/cloud/loadbalancer/v1/target_group_service.proto
category: rpc
backend: kacho-nlb
backend_port: 9090
visibility: public
domain: nlb
related_resource: "[[resources/nlb-target-group]]"
methods_count: 9
async_methods: 6
tags:
  - rpc
  - kacho-nlb
  - targetgroup
---

# TargetGroupService (nlb)

**Proto**: `kacho-proto/proto/kacho/cloud/loadbalancer/v1/target_group_service.proto`
**Backend**: `kacho-nlb:9090` (public gRPC)
**Public/Internal**: public

## Methods (9)

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetTargetGroupRequest | TargetGroup | sync | |
| List | ListTargetGroupsRequest | ListTargetGroupsResponse | sync | filter, page_token |
| Create | CreateTargetGroupRequest | operation.Operation | **async** | inline `targets[]`, `health_check`, `deregistration_delay_seconds`, `slow_start_seconds` allowed |
| Update | UpdateTargetGroupRequest | operation.Operation | **async** | mutable: name/desc/labels/HC/dereg/slow_start. Immutable: project_id/region_id. Targets — separate Add/Remove |
| Delete | DeleteTargetGroupRequest | operation.Operation | **async** | sync precheck: no attached LB, no targets remaining |
| Move | MoveTargetGroupRequest | operation.Operation | **async** | cross-project; blocked if attached |
| AddTargets | AddTargetsRequest | operation.Operation | **async** | idempotent `ON CONFLICT DO NOTHING` per partial UNIQUE identity-key. Per-target peer-validate в worker |
| RemoveTargets | RemoveTargetsRequest | operation.Operation | **async** | 2-phase: Phase A mark DRAINING, Phase B drain-runner DELETE |
| ListOperations | ListTargetGroupOperationsRequest | ListTargetGroupOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /nlb/v1/targetGroups/{target_group_id}` | Get |
| `GET /nlb/v1/targetGroups` | List |
| `POST /nlb/v1/targetGroups` | Create |
| `PATCH /nlb/v1/targetGroups/{target_group_id}` | Update |
| `DELETE /nlb/v1/targetGroups/{target_group_id}` | Delete |
| `POST /nlb/v1/targetGroups/{id}:move` | Move |
| `POST /nlb/v1/targetGroups/{id}:addTargets` | AddTargets |
| `POST /nlb/v1/targetGroups/{id}:removeTargets` | RemoveTargets |
| `GET /nlb/v1/targetGroups/{id}/operations` | ListOperations |

## AddTargets idempotency

`INSERT ... ON CONFLICT (target_group_id, <identity-key>) DO NOTHING` per target. Каждая identity-type (instance_id / nic_id / ip_ref / external_ip) — отдельный partial UNIQUE (GWT-DB-008). Duplicate target → silent skip.

## RemoveTargets 2-phase drain

- **Phase A** (Worker, immediate): `UPDATE targets SET status='DRAINING', drain_started_at=now() WHERE target_group_id=$1 AND identity-key IN (...)` → `ops.MarkDone` (fast `done=true`).
- **Phase B** (`jobs/target_drain_runner.go`, periodic ~5s): `DELETE FROM targets WHERE status='DRAINING' AND drain_started_at < now() - deregistration_delay::interval` → `outbox.Emit (UPDATED)`.

См. [[../packages/nlb-apps-kacho-jobs]] и [[../resources/nlb-target]].

## FGA Permissions

- `Get` / `List` → `viewer` on `nlb_target_group:<id>` или `project`
- `Create` → `editor` on `project:<project_id>`
- `Update` / `Delete` / `Move` / `AddTargets` / `RemoveTargets` → `editor` on `nlb_target_group:<id>`

## See also

[[../packages/nlb-apps-kacho-api-targetgroup]] [[../resources/nlb-target-group]] [[../resources/nlb-target]] [[../packages/nlb-apps-kacho-jobs]]

#rpc #kacho-nlb #targetgroup
