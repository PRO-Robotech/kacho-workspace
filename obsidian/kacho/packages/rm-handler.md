---
title: rm-handler
category: package
repo: kacho-resource-manager
layer: handler
tags:
  - packages
  - kacho-rm
  - handler
---

# kacho-resource-manager/internal/handler

**Path**: `kacho-resource-manager/internal/handler/`
**Implements**: gRPC services из [[../packages/proto-rm|proto-resourcemanager]] и [[../packages/proto-organizationmanager|proto-organizationmanager]]

Thin transport-слой: parse request → useCase → format response.

## Files

| File | Содержание |
|---|---|
| `organization_handler.go` | [[../rpc/rm-organization-service]] adapter |
| `cloud_handler.go` | [[../rpc/rm-cloud-service]] adapter |
| `folder_handler.go` | [[../rpc/rm-folder-service]] adapter |
| `operation_handler.go` | [[../rpc/operation-service]] adapter — Get/Cancel |
| `mapping.go` | proto ↔ domain conversion helpers |

## See also

[[rm-service]] [[rm-domain]]

#packages #kacho-rm #handler
