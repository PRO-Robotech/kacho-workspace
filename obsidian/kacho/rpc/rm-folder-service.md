---
title: FolderService
aliases:
  - FolderService (rm)
  - FolderService (resourcemanager)
proto_file: kacho/cloud/resourcemanager/v1/folder_service.proto
category: rpc
backend: kacho-resource-manager
backend_port: 9090
visibility: public
domain: resourcemanager
related_resource: "[[resources/rm-folder]]"
methods_count: 11
async_methods: 4
tags:
  - rpc
  - kacho-rm
  - folder
  - leaf-owner
---

# FolderService (resourcemanager)

**Proto**: `kacho-proto/proto/kacho/cloud/resourcemanager/v1/folder_service.proto`
**Backend**: `kacho-resource-manager:9090`
**Public/Internal**: public

Folder — leaf-owner в edge-графе: его зовут все доменные сервисы (`vpc/compute/nlb`) для folder-validation, он сам никуда не зовёт. См. [[../edges/vpc-to-rm-folder-exists]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetFolderRequest | Folder | sync | используется peer-сервисами как validation |
| List | ListFoldersRequest | ListFoldersResponse | sync | |
| Create | CreateFolderRequest | operation.Operation | **async** | cloud_id required |
| Update | UpdateFolderRequest | operation.Operation | **async** | |
| Delete | DeleteFolderRequest | operation.Operation | **async** | best-effort dangling check — peer-сервисы могут продолжать reference deleted folder |
| ListOperations | ListFolderOperationsRequest | ListFolderOperationsResponse | sync | |
| Access* | access.* | access.*/operation.Operation | mixed | IAM placeholders |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /resource-manager/v1/folders/{folder_id}` | Get |
| `GET /resource-manager/v1/folders` | List |
| `POST /resource-manager/v1/folders` | Create |
| `PATCH /resource-manager/v1/folders/{folder_id}` | Update |
| `DELETE /resource-manager/v1/folders/{folder_id}` | Delete |
| `GET /resource-manager/v1/folders/{folder_id}/operations` | ListOperations |
| `GET /resource-manager/v1/folders/{resource_id}:listAccessBindings` | ListAccessBindings |
| `POST /resource-manager/v1/folders/{resource_id}:setAccessBindings` | SetAccessBindings |
| `POST /resource-manager/v1/folders/{resource_id}:bindAccessPolicy` | BindAccessPolicy |

## See also

[[../packages/rm-service]] [[../resources/rm-folder]] [[../edges/vpc-to-rm-folder-exists]] [[../edges/compute-to-rm-folder-check]]

#rpc #kacho-rm #folder #leaf-owner
