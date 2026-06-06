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
**Imports**: kacho-proto stubs (`iam/v1`, `compute/v1`), [[corelib-retry]]
**Imported by**: [[vpc-cmd-vpc]] (wiring), service-layer через port-интерфейсы

Peer-service gRPC clients для cross-service validation (CLAUDE.md «Кросс-доменные ссылки на ресурсы»).

## Files

| File | Содержание |
|---|---|
| `builder.go` | factory: dial peer service, applies retry-interceptor, exposes typed clients |
| `builder_test.go` | |
| `iam_client.go` | wraps `iamv1.ProjectServiceClient` — `ProjectClient.Exists(ctx, id)` + `GetCloudIDFromProject(ctx, id)` (read `Project.account_id`). Renamed from `resourcemanager_client.go`/`FolderClient` в KAC-106. |
| `project_cache.go` | short-TTL LRU cache для project-existence (positive 30s; NotFound не кешируется). См. [[../edges/vpc-to-iam-project-exists]]. Renamed from `folder_cache.go`. |
| `project_cache_test.go` | |
| `compute_client.go` | wraps `computepb.ZoneServiceClient` (post-KAC-15) — `ZoneExists(ctx, id)`, `GetZone(ctx, id)` |
| `openfga_write_client.go` | OpenFGA/Keto tuple write (authz) |

## Pattern

Service-layer определяет port-интерфейс (`ProjectClient interface { Exists(ctx, id) (bool, error); GetCloudIDFromProject(ctx, id) (string, error) }`); adapter в `clients/` реализует, оборачивая typed gRPC-stub + `retry.OnUnavailable`. DB-колонка `folder_id` = id владельца-проекта (legacy-имя, source of truth = `ProjectService`).

## See also

[[../edges/vpc-to-iam-project-exists]] [[../edges/vpc-to-compute-zone-validate]] [[corelib-retry]]

#packages #kacho-vpc #clients #cross-service
