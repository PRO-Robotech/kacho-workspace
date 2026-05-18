---
title: GroupService
aliases:
  - GroupService (iam)
proto_file: kacho/cloud/iam/v1/group_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-group]]"
methods_count: 9
async_methods: 5
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# GroupService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/group_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]].

## Methods

| Method           | Request                    | Response                    | Sync/Async | Note                             |
| ---------------- | -------------------------- | --------------------------- | ---------- | -------------------------------- |
| Get              | GetGroupRequest            | Group                       | sync       |                                  |
| List             | ListGroupsRequest          | ListGroupsResponse          | sync       |                                  |
| Create           | CreateGroupRequest         | operation.Operation         | **async**  |                                  |
| Update           | UpdateGroupRequest         | operation.Operation         | **async**  | UpdateMask; account_id immutable |
| Delete           | DeleteGroupRequest         | operation.Operation         | **async**  | CASCADE по `group_members`       |
| **AddMember**    | AddGroupMemberRequest      | operation.Operation         | **async**  | проверка member через триггер    |
| **RemoveMember** | RemoveGroupMemberRequest   | operation.Operation         | **async**  | idempotent                       |
| ListMembers      | ListGroupMembersRequest    | ListGroupMembersResponse    | sync       | filter by member_type            |
| ListOperations   | ListGroupOperationsRequest | ListGroupOperationsResponse | sync       |                                  |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/groups/{id}` | Get |
| `GET /iam/v1/groups` | List |
| `POST /iam/v1/groups` | Create |
| `PATCH /iam/v1/groups/{id}` | Update |
| `DELETE /iam/v1/groups/{id}` | Delete |
| `POST /iam/v1/groups/{id}:addMember` | AddMember |
| `POST /iam/v1/groups/{id}:removeMember` | RemoveMember |
| `GET /iam/v1/groups/{id}/members` (alias `:listMembers`) | ListMembers |

## Notes

- AddMember идемпотентен (PRIMARY KEY (group_id, member_type, member_id) на `group_members`).
- Member existence — через триггер `group_members_member_exists` (BEFORE INSERT): несуществующий user/sa → `FailedPrecondition "<member_type> <member_id> not found"`.
- **Auth-matrix (KAC-123)** — default-deny через Keto Check на `account:<group.account_id>`:
  - Create — `admin` на `req.account_id`.
  - Get / List / ListMembers — `viewer` на ассоциированном account.
  - Update / Delete / AddMember / RemoveMember — `admin` на ассоциированном account.
  - List без `account_id` → empty (если не system-admin через `kacho_system:root#admin`).
  - service_account principal с непустым id → bypass; anonymous → empty/PermissionDenied.

## See also

[[../packages/iam-domain]] [[../resources/iam-group]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
