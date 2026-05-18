---
title: OrganizationService
aliases:
  - OrganizationService (rm)
  - OrganizationService (organizationmanager)
proto_file: kacho/cloud/organizationmanager/v1/organization_service.proto
category: rpc
backend: kacho-resource-manager
backend_port: 9090
visibility: public
domain: organizationmanager
related_resource: "[[resources/rm-organization]]"
methods_count: 13
async_methods: 5
tags:
  - rpc
  - kacho-rm
  - organization
---

# OrganizationService (organizationmanager)

**Proto**: `kacho-proto/proto/kacho/cloud/organizationmanager/v1/organization_service.proto`
**Backend**: `kacho-resource-manager:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetOrganizationRequest | Organization | sync | |
| List | ListOrganizationsRequest | ListOrganizationsResponse | sync | |
| Create | CreateOrganizationRequest | operation.Operation | **async** | |
| Update | UpdateOrganizationRequest | operation.Operation | **async** | |
| Delete | DeleteOrganizationRequest | operation.Operation | **async** | RESTRICT если есть Cloud |
| ListOperations | ListOrganizationOperationsRequest | ListOrganizationOperationsResponse | sync | |
| ListAccessBindings | (access.) | (access.) | sync | IAM — placeholder |
| SetAccessBindings | (access.) | operation.Operation | **async** | IAM — placeholder |
| UpdateAccessBindings | (access.) | operation.Operation | **async** | IAM — placeholder |
| ListAccessPolicyBindings / BindAccessPolicy / UnbindAccessPolicy / UpdateAccessPolicyBindingParameters | (access.) | sync/async | placeholders для `kacho-iam` (blocked) |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /organization-manager/v1/organizations/{organization_id}` | Get |
| `GET /organization-manager/v1/organizations` | List |
| `POST /organization-manager/v1/organizations` | Create |
| `PATCH /organization-manager/v1/organizations/{organization_id}` | Update |
| `DELETE /organization-manager/v1/organizations/{organization_id}` | Delete |
| `GET /organization-manager/v1/organizations/{organization_id}/operations` | ListOperations |
| `GET /organization-manager/v1/organizations/{resource_id}:listAccessBindings` | ListAccessBindings |
| `POST /organization-manager/v1/organizations/{resource_id}:setAccessBindings` | SetAccessBindings |
| `POST /organization-manager/v1/organizations/{resource_id}:updateAccessBindings` | UpdateAccessBindings |

## See also

[[../packages/rm-service]] [[../resources/rm-organization]]

#rpc #kacho-rm #organization
