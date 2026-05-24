---
title: nlb-clients-iam
category: packages
repo: kacho-nlb
layer: clients
tags:
  - packages
  - kacho-nlb
  - clients
  - cross-service
  - iam
---

# kacho-nlb/internal/clients/iam

**Path**: `kacho-nlb/internal/clients/iam/`
**Imports**: `kacho-proto/gen/go/kacho/cloud/iam/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]] (Project check), [[nlb-internal-check]] (Check client), [[nlb-internal-fgawrite]] (WriteCreatorTuple)

Typed peer-service gRPC client adapters для kacho-iam.

## Files

| File | Содержание |
|---|---|
| `project_client.go` | wraps `iamv1.ProjectServiceClient` — `Exists(ctx, projectID)` helper; TTL+LRU cache (positive 30s, NotFound NOT cached) |
| `project_cache.go` | LRU cache impl |
| `iam_internal_client.go` | wraps `iamv1.InternalIAMServiceClient.Check` + `WriteCreatorTuple` (used by check/ + fgawrite/ packages) |
| `*_test.go` | unit-tests (cache hit/miss + retry + timeout) |

## Pattern

Service-layer определяет port-interface (`ProjectClient`, `IAMCheckClient`, `CreatorTupleWriter`); adapter в `clients/iam/` реализует, оборачивая typed gRPC-stub + `corelib/retry.OnUnavailable`.

## Project.Exists usage

```go
exists, err := iamClient.Exists(ctx, projectID)
if !exists { return status.Error(codes.NotFound, "Project ... not found") }
```

Cache TTL 30s (projects редко создаются/удаляются), positive-only — NotFound каждый раз ходит за свежим ответом (anti-staleness).

## Imports

- `kacho-proto/gen/go/kacho/cloud/iam/v1`
- `kacho-corelib/retry`

## See also

[[../edges/nlb-to-iam-check]] [[../edges/nlb-to-iam-creator-tuple]] [[nlb-internal-check]] [[nlb-internal-fgawrite]]

#packages #kacho-nlb #clients #cross-service #iam
