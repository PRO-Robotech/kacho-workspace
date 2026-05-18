---
title: vpc-clients
category: package
repo: kacho-vpc
layer: clients
tags:
  - packages
  - kacho-vpc
  - clients
  - cross-service
---

# kacho-vpc/internal/clients

**Path**: `kacho-vpc/internal/clients/`
**Imports**: kacho-proto stubs (`resourcemanager/v1`, `compute/v1`), [[corelib-retry]]
**Imported by**: [[vpc-cmd-vpc]] (wiring), service-layer через port-интерфейсы

Peer-service gRPC clients для cross-service validation (CLAUDE.md «Кросс-доменные ссылки на ресурсы»).

## Files

| File | Содержание |
|---|---|
| `builder.go` | factory: dial peer service, applies retry-interceptor, exposes typed clients |
| `builder_test.go` | |
| `resourcemanager_client.go` | wraps `rmpb.FolderServiceClient` + `CloudServiceClient` — `FolderExists(ctx, id)` helper |
| `folder_cache.go` | short-TTL cache (LRU?) для folder-existence (см. [[../edges/vpc-to-rm-folder-exists]]) |
| `folder_cache_test.go` | |
| `compute_client.go` | wraps `computepb.ZoneServiceClient` (post-KAC-15) — `ZoneExists(ctx, id)`, `GetZone(ctx, id)` |

## Pattern

Service-layer определяет port-интерфейс (`FolderClient interface { Exists(ctx, id) (bool, error) }`); adapter в `clients/` реализует, оборачивая typed gRPC-stub + `retry.OnUnavailable`.

## See also

[[../edges/vpc-to-rm-folder-exists]] [[../edges/vpc-to-compute-zone-validate]] [[corelib-retry]]

#packages #kacho-vpc #clients #cross-service
