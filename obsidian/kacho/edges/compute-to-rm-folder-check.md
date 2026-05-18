---
title: "compute → rm: folder existence check"
aliases:
  - compute to rm folder check
category: edge
caller_repo: kacho-compute
callee_repo: kacho-resource-manager
sync_async: async
protocol: grpc-cluster-internal
status: active
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-rm
---

# compute → rm: folder existence check

**Caller**: `kacho-compute` (мутации Instance/Disk/Image/...)
**Callee**: `kacho-resource-manager` (`FolderService.Get`)
**Protocol**: gRPC cluster-internal
**Sync/Async**: async (внутри Operation worker'а)

## When invoked

- На любой Create мутации, принимающей `folder_id`: `Instance.Create`, `Disk.Create`, `Image.Create`, `Snapshot.Create`, и т.п.
- `Move` (cross-folder).

## Pattern

Identичен [[vpc-to-rm-folder-exists]]: cache TTL + retry на Unavailable + dangling-ref грациозен на чтении.

## See also

[[../rpc/rm-folder-service]] [[vpc-to-rm-folder-exists]]

#edge #cross-service #kacho-compute #kacho-rm
