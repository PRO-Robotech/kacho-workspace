---
title: SecurityGroupService
aliases:
  - SecurityGroupService (vpc)
proto_file: kacho/cloud/vpc/v1/security_group_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-securitygroup]]"
methods_count: 8
async_methods: 5
tags:
  - rpc
  - kacho-vpc
  - securitygroup
---

# SecurityGroupService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/security_group_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetSecurityGroupRequest | SecurityGroup | sync | |
| List | ListSecurityGroupsRequest | ListSecurityGroupsResponse | sync | |
| Create | CreateSecurityGroupRequest | operation.Operation | **async** | network_id **required** (KAC-243); rule_specs SG-target → same-network |
| Update | UpdateSecurityGroupRequest | operation.Operation | **async** | mask {name,description,labels,rule_specs}; network_id **НЕ** в маске (immutable, [[KAC-243]]); без OCC |
| UpdateRules | UpdateSecurityGroupRulesRequest | operation.Operation | **async** | bulk add/remove (KAC-71 partial); SG-target → same-network (KAC-243); xmin-OCC |
| UpdateRule | UpdateSecurityGroupRuleRequest | operation.Operation | **async** | mutate single rule (description/labels); xmin-OCC |
| Delete | DeleteSecurityGroupRequest | operation.Operation | **async** | FailedPrecondition если в use на NI |
| ListOperations | ListSecurityGroupOperationsRequest | ListSecurityGroupOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /vpc/v1/securityGroups/{security_group_id}` | Get |
| `GET /vpc/v1/securityGroups` | List |
| `POST /vpc/v1/securityGroups` | Create |
| `PATCH /vpc/v1/securityGroups/{security_group_id}` | Update |
| `PATCH /vpc/v1/securityGroups/{security_group_id}/rules` | UpdateRules |
| `PATCH /vpc/v1/securityGroups/{security_group_id}/rules/{rule_id}` | UpdateRule |
| `DELETE /vpc/v1/securityGroups/{security_group_id}` | Delete |
| `GET /vpc/v1/securityGroups/{security_group_id}/operations` | ListOperations |

## OCC (только UpdateRules/UpdateRule)

`UpdateRules`/`UpdateRule` используют `xmin::text` snapshot из `Get` → `UPDATE ... WHERE xmin::text = $expected`; concurrent writer (0 rows) → `FAILED_PRECONDITION` (НЕ `Aborted` — маппится через `helpers.ErrFailedPrecondition`; см. `security_group_occ_integration_test.go`). Общий `Update` — **без OCC** (bare `WHERE id=$1`).

## SG↔Network инвариант (KAC-243)

`network_id` обязателен при Create + immutable (нет в Update mask). SG→SG-правило (`rule.security_group_id`) валидно только если target-SG в той же Network — иначе `INVALID_ARGUMENT`+`field_violations` (Create/UpdateRules, service-layer). Миграция `0004` backfill'ит orphan-SG. См. [[../resources/vpc-securitygroup]].

> [!note] Move удалён в KAC-266
> RPC `Move` + `POST /vpc/v1/securityGroups/{security_group_id}:move` сняты (contract-removal).
> Раньше Move network-bound SG отбивался `FAILED_PRECONDITION` (KAC-243); теперь сам RPC отсутствует. См. [[../KAC/KAC-266]].

## See also

[[../packages/vpc-apps-kacho-api-securitygroup]] [[../resources/vpc-securitygroup]]

#rpc #kacho-vpc #securitygroup
