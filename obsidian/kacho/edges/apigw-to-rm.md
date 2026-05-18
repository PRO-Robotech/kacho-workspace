---
title: "api-gateway → rm (proxy)"
aliases:
  - apigw to rm
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-resource-manager
sync_async: sync
protocol: grpc-gateway
status: active
tags:
  - edge
  - cross-service
  - kacho-apigw
  - kacho-rm
---

# api-gateway → rm (proxy)

**Caller**: `kacho-api-gateway` (`internal/restmux/mux.go`)
**Callee**: `kacho-resource-manager:9090`
**Protocol**: grpc-gateway HandlerFromEndpoint

## Registered services

| Proto service | REST префикс |
|---|---|
| `CloudService` | `/resource-manager/v1/clouds` |
| `FolderService` | `/resource-manager/v1/folders` |
| `OrganizationService` (organizationmanager) | `/organization-manager/v1/organizations` |

## Notes

- rm не имеет internal-listener-only методов сейчас — все RPC публичные (Organization/Cloud/Folder + IAM placeholders).
- rm — leaf-owner (Folder), не делает out-bound calls в Kachō-stack (см. CLAUDE.md «Карта владельцев доменов»).

## See also

[[../packages/apigw-restmux]] [[../rpc/rm-folder-service]]

#edge #cross-service #kacho-apigw #kacho-rm
