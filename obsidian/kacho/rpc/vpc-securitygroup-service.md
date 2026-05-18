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
methods_count: 9
async_methods: 6
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
| Create | CreateSecurityGroupRequest | operation.Operation | **async** | network_id required |
| Update | UpdateSecurityGroupRequest | operation.Operation | **async** | OCC (xmin) |
| UpdateRules | UpdateSecurityGroupRulesRequest | operation.Operation | **async** | bulk add/remove (KAC-71 partial) |
| UpdateRule | UpdateSecurityGroupRuleRequest | operation.Operation | **async** | mutate single rule |
| Delete | DeleteSecurityGroupRequest | operation.Operation | **async** | FailedPrecondition если в use на NI |
| Move | MoveSecurityGroupRequest | operation.Operation | **async** | cross-folder |
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
| `POST /vpc/v1/securityGroups/{security_group_id}:move` | Move |
| `GET /vpc/v1/securityGroups/{security_group_id}/operations` | ListOperations |

## OCC

Update'ы используют `xmin::text` snapshot из `Get` → `UPDATE ... WHERE xmin::text = $expected`. Concurrent writers — второй получает `Aborted` (см. integration_test `security_group_occ_integration_test.go`).

## See also

[[../packages/vpc-apps-kacho-api-securitygroup]] [[../resources/vpc-securitygroup]]

#rpc #kacho-vpc #securitygroup
