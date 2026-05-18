---
title: ProjectService
aliases:
  - ProjectService (iam)
proto_file: kacho/cloud/iam/v1/project_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-project]]"
methods_count: 7
async_methods: 4
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# ProjectService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/project_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]]; proto-stubs смержены в E0 ([[KAC-105]]).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetProjectRequest | Project | sync | |
| List | ListProjectsRequest | ListProjectsResponse | sync | filter, page_token |
| Create | CreateProjectRequest | operation.Operation | **async** | account_id required |
| Update | UpdateProjectRequest | operation.Operation | **async** | UpdateMask; `account_id` immutable через Update |
| Delete | DeleteProjectRequest | operation.Operation | **async** | RESTRICT через FK от vpc/compute resources (E1+) |
| **Move** | MoveProjectRequest | operation.Operation | **async** | cross-account; атомарный CAS на `account_id` |
| ListOperations | ListProjectOperationsRequest | ListProjectOperationsResponse | sync | |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/projects/{id}` | Get |
| `GET /iam/v1/projects` | List |
| `POST /iam/v1/projects` | Create |
| `PATCH /iam/v1/projects/{id}` | Update |
| `DELETE /iam/v1/projects/{id}` | Delete |
| `POST /iam/v1/projects/{id}:move` | Move |
| `GET /iam/v1/projects/{id}/operations` | ListOperations |

## Notes

- **Move** — спец-семантика: `UPDATE projects SET account_id=$new WHERE id=$id AND account_id=$expected RETURNING ...` (CAS, запрет #10), плюс UNIQUE (account_id, name) ловит конфликт по new (account_id, name).
- E1 ([[KAC-106]]) переключит `folder_id → project_id` в kacho-vpc/compute/loadbalancer (через peer `ProjectService.Get` — см. [[../edges/vpc-to-iam-project-exists]]).

## See also

[[../packages/iam-domain]] [[../resources/iam-project]] [[../edges/vpc-to-iam-project-exists]] [[../KAC/KAC-105]] [[../KAC/KAC-112]]

#rpc #kacho-iam #iam
