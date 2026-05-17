---
title: "vpc → iam: project existence check (replaces folder_id check)"
aliases:
  - vpc to iam project check
  - project_id validate
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-106]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
---

> [!success] Active since 2026-05-17 (KAC-106 E1)
> Edge активен; kacho-vpc зовёт `kacho-iam.ProjectService.Get` для валидации `project_id` на request-path. Replaces deprecated [[vpc-to-rm-folder-exists]]. См. [[KAC/KAC-106]].

# vpc → iam: project existence check

**Caller**: `kacho-vpc` (`internal/clients/iam_client.go` — renamed from `resourcemanager_client.go` в KAC-106)
**Callee**: `kacho-iam.ProjectService.Get` (mapped к "Exists" сценарию через NotFound)
**Protocol**: gRPC cluster-internal (direct dial, не через api-gateway; см. §«Кросс-доменные ссылки на ресурсы»)
**Sync/Async**: **async** (внутри Operation worker'а на request-path Create/Update/Move с `project_id`)

## When invoked

- На request-path: `Network.Create`, `Subnet.Create`, `Address.Create`, любая мутация, принимающая `project_id` — внутри Operation worker'а, после возврата proto-`Operation`.
- При `Move` (cross-project).

## Implementation

```go
// internal/clients/iam_client.go (KAC-106)
import iamv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1"

type ProjectClient struct {
    cli iamv1.ProjectServiceClient
    // ... TTL+LRU cache: positive 30s, NotFound NOT cached
}

func (c *ProjectClient) Exists(ctx, projectID) (bool, error) {
    _, err := c.cli.Get(ctx, &iamv1.GetProjectRequest{ProjectId: projectID})
    if status.Code(err) == codes.NotFound { return false, nil }
    return err == nil, err
}
```

`GetCloudIDFromProject(ctx, projectID)` оставлен (read `Project.account_id` — IAM-analog «cloud_id»), используется в IPAM cascade Step 3 (cloud-pool-selector lookup).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| project OK | (continue) | TTL-кэш positive 30s в `project_cache.go` |
| project not found | `NotFound "Folder with id <id> not found"` | Текст ошибки оставлен `"Folder"` для verbatim YC parity (acceptance §1: "стилистика остаётся") |
| iam недоступен | `Unavailable "folder check: <err>"` | retry через [[../packages/corelib-retry]] OnUnavailable |

## Configuration

```yaml
# kacho-vpc deploy/values.yaml
iamAddr: "kacho-iam.kacho.svc.cluster.local:9090"

# configmap.yaml render:
extapi:
  iam:
    endpoint: "kacho-iam.kacho.svc.cluster.local:9090"
    tls:
      enable: false
```

Transitional fallback: если `extapi.iam.endpoint` пуст — main.go берёт `extapi.resource-manager.endpoint`.

## History

- **2026-05-17 (KAC-106 E1)**: edge created; replaces vpc→rm folder check ([[vpc-to-rm-folder-exists]] deprecated).
- File `internal/clients/resourcemanager_client.go` → `iam_client.go`; type `FolderClient` → `ProjectClient`; same TTL+LRU cache pattern preserved.

## See also

[[../rpc/iam-project-service]] [[../resources/iam-project]] [[vpc-to-rm-folder-exists]] [[../KAC/KAC-104]] [[../KAC/KAC-106|KAC-106 (E1)]]

#edge #kacho-vpc #kacho-iam #cross-service
