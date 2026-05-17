---
title: "vpc → rm: folder existence check (DEPRECATED)"
aliases:
  - vpc to rm folder check
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-resource-manager
sync_async: async
protocol: grpc-cluster-internal
status: deprecated
related_tickets:
  - "[[KAC/KAC-94]]"
  - "[[KAC/KAC-106]]"
tags:
  - edge
  - cross-service
  - kacho-vpc
  - kacho-rm
  - deprecated
---

> [!warning] Deprecated by KAC-106 (E1) — 2026-05-17
> kacho-vpc больше не зовёт `kacho-resource-manager.FolderService.Get`. Owner-scope ресурсы валидируются через `kacho-iam.ProjectService.Get`. См. [[vpc-to-iam-project-exists]] и [[KAC/KAC-106]].
>
> Этот файл оставлен как исторический след — edge **больше не существует в runtime'е**.

# vpc → rm: folder existence check (DEPRECATED)

**Caller**: `kacho-vpc` (`internal/clients/resourcemanager_client.go` + `folder_cache.go`)
**Callee**: `kacho-resource-manager` (FolderService.Get → mapped к "Exists")
**Protocol**: gRPC cluster-internal (direct dial, не через api-gateway)
**Sync/Async**: **async** (внутри Operation worker'а) — sync precheck удалён.

## When invoked

- На request-path: `Network.Create`, `Subnet.Create`, `Address.Create`, любая мутация, принимающая `folder_id` — внутри Operation worker'а, после возврата proto-`Operation` клиенту.
- Также при `Move` (cross-folder).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| folder OK | (continue) | cache TTL — `folder_cache.go` |
| folder not found | `NotFound "Folder <id> not found"` | operation.Update(done=true, error) |
| rm недоступен | `Unavailable "folder check: <err>"` | retry через [[../packages/corelib-retry]] OnUnavailable |

## History

- Раньше был **sync precheck** в handler — удалён в KAC-94 I.4 (skill `evgeniy`): «request-path не должен зависеть от peer-сервиса, валидация — в worker'е».
- `folder_cache.go` — короткий TTL-кэш, чтобы повторные мутации в том же folder не били rm каждый раз.

## See also

[[../rpc/rm-folder-service]] [[../packages/vpc-clients]] [[../packages/corelib-retry]]

#edge #cross-service #kacho-vpc #kacho-rm
