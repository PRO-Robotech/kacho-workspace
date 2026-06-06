---
title: "api-gateway → rm (proxy)"
aliases:
  - apigw to rm
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-resource-manager
sync_async: sync
protocol: grpc-gateway
status: removed
tags:
  - edge
  - cross-service
  - kacho-apigw
  - kacho-rm
  - deprecated
---

> [!warning] Removed by KAC-124 (E5 sub-phase 2.0)
> `kacho-resource-manager` упразднён — backend, proto-пакеты `resourcemanager.v1` / `organizationmanager.v1` и эти REST-маршруты удалены. Account/Project живут в `kacho-iam`; api-gateway проксирует их через `ProjectService` / `AccountService`. Этот файл оставлен как исторический след — ребро **больше не существует**.

# api-gateway → rm (proxy) — REMOVED

**Caller**: `kacho-api-gateway` (`internal/restmux/mux.go`)
**Callee**: ~~`kacho-resource-manager:9090`~~ (сервис удалён)
**Protocol**: grpc-gateway HandlerFromEndpoint

## Registered services (исторические — удалены)

| Proto service | REST префикс | Status |
|---|---|---|
| `CloudService` | `/resource-manager/v1/clouds` | removed (KAC-124) |
| `FolderService` | `/resource-manager/v1/folders` | removed (KAC-124) |
| `OrganizationService` (organizationmanager) | `/organization-manager/v1/organizations` | removed (KAC-124) |

## Notes

- rm-сервис целиком удалён в KAC-124; Organization/Cloud/Folder заменены на Account/Project в `kacho-iam`.
- Текущий аналог: api-gateway проксирует `kacho-iam` (`ProjectService` / `AccountService`).

## See also

[[../packages/apigw-restmux]] [[../rpc/rm-folder-service]]

#edge #cross-service #kacho-apigw #kacho-rm
