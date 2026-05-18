---
title: CloudService
aliases:
  - CloudService (rm)
  - CloudService (resourcemanager)
proto_file: kacho/cloud/resourcemanager/v1/cloud_service.proto
category: rpc
backend: kacho-resource-manager
backend_port: 9090
visibility: public
domain: resourcemanager
related_resource: "[[resources/rm-cloud]]"
methods_count: 13
async_methods: 5
tags:
  - rpc
  - kacho-rm
  - cloud
---

# CloudService (resourcemanager)

**Proto**: `kacho-proto/proto/kacho/cloud/resourcemanager/v1/cloud_service.proto`
**Backend**: `kacho-resource-manager:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetCloudRequest | Cloud | sync | |
| List | ListCloudsRequest | ListCloudsResponse | sync | |
| Create | CreateCloudRequest | operation.Operation | **async** | organization_id required |
| Update | UpdateCloudRequest | operation.Operation | **async** | |
| Delete | DeleteCloudRequest | operation.Operation | **async** | RESTRICT если есть Folder |
| ListOperations | ListCloudOperationsRequest | ListCloudOperationsResponse | sync | |
| Access* (Set/List/Update/Bind/Unbind/UpdateAccessPolicyBindingParameters) | access.* | access.*/operation.Operation | mixed | IAM placeholders (blocked) |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /resource-manager/v1/clouds/{cloud_id}` | Get |
| `GET /resource-manager/v1/clouds` | List |
| `POST /resource-manager/v1/clouds` | Create |
| `PATCH /resource-manager/v1/clouds/{cloud_id}` | Update |
| `DELETE /resource-manager/v1/clouds/{cloud_id}` | Delete |
| `GET /resource-manager/v1/clouds/{cloud_id}/operations` | ListOperations |
| `GET /resource-manager/v1/clouds/{resource_id}:listAccessBindings` | ListAccessBindings |
| `POST /resource-manager/v1/clouds/{resource_id}:setAccessBindings` | SetAccessBindings |
| ... | ... |

## See also

[[../packages/rm-service]] [[../resources/rm-cloud]]

#rpc #kacho-rm #cloud
