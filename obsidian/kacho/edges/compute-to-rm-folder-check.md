---
title: "compute → rm: folder existence check"
aliases:
  - compute to rm folder check
category: edge
caller_repo: kacho-compute
callee_repo: kacho-resource-manager
sync_async: async
protocol: grpc-cluster-internal
status: removed
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-rm
  - deprecated
---

> [!warning] Removed by KAC-124 (E5 sub-phase 2.0)
> `kacho-resource-manager` упразднён; `FolderService.Get` больше не существует. kacho-compute валидирует owner-scope через `kacho-iam.ProjectService.Get` (project existence). DB-колонка `folder_id` сохранила legacy-имя (= id владельца-проекта, source of truth = ProjectService). Этот файл оставлен как исторический след — ребро на rm **больше не существует**.

# compute → rm: folder existence check — REMOVED

**Caller**: `kacho-compute` (мутации Instance/Disk/Image/...)
**Callee**: ~~`kacho-resource-manager` (`FolderService.Get`)~~ → теперь `kacho-iam` (`ProjectService.Get`)
**Protocol**: gRPC cluster-internal
**Sync/Async**: async (внутри Operation worker'а)

## When invoked (исторически)

- На любой Create мутации, принимавшей `folder_id`: `Instance.Create`, `Disk.Create`, `Image.Create`, `Snapshot.Create`, и т.п.
- `Move` (cross-project).

## Pattern

Был identичен vpc→rm folder check: cache TTL + retry на Unavailable + dangling-ref грациозен на чтении. Заменён на project existence check через `kacho-iam.ProjectService.Get` (тот же паттерн).

## See also

[[vpc-to-iam-project-exists]] [[../rpc/iam-project-service]]

#edge #cross-service #kacho-compute #kacho-rm #deprecated
