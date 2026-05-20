---
title: "corelib authz/listobjects"
aliases:
  - corelib listobjects
  - authz listobjects shared
category: packages
repo: kacho-corelib
layer: service
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-corelib
  - authz
  - fga
---

# corelib `authz/listobjects`

Phase 4 — shared client + cache + cursor utility для AuthorizeService.ListObjects, переиспользуемое kacho-vpc / kacho-compute / kacho-loadbalancer (когда появится).

## Exported API

```go
package authz

type ListObjectsClient interface {
    ListObjects(ctx context.Context, req ListObjectsRequest) (ListObjectsResult, error)
}

type ListObjectsRequest struct {
    Subject     string             // user:usr_xxx или service_account:sva_xxx
    Relation    string             // "vpc.network.read"
    ObjectType  string             // "network"
    Parent      *ParentFilter      // {Type: "project", ID: "prj_xxx"} — optional
    Cursor      string             // opaque pagination cursor
    PageSize    int                // default 1000, max 10000
}

type ListObjectsResult struct {
    IDs       []string             // visible object IDs
    NextCursor string              // empty = exhausted
    Cardinality int64              // total est (для page-size hint)
}

type ParentFilter struct {
    Type string  // "project", "account", "organization"
    ID   string
}
```

## Cache layer

```go
type CachedListObjects struct {
    Inner   ListObjectsClient
    TTL     time.Duration         // default 5s
    MaxSize int                   // default 1000 entries
}

// Key: hash(subject || relation || object_type || parent || cursor)
// Storage: github.com/hashicorp/golang-lru/v2
// LISTEN-invalidate hook: subscribe pg_notify('kacho_iam_fga_outbox') → on event, clear cache
```

## Pagination cursor format

Opaque signed:
```
<base64(payload).<hmac-sha256>>
payload = { last_id, page_n, issued_at }
```

- HMAC key: per-instance random (rotated на restart) — cursors not portable across instances → forces re-list on instance switch (acceptable cost для consistency).
- TTL within cursor: 5min → expired → invalid_cursor → restart from beginning.

## Helper: filter SQL set

```go
func FilterIDs(ctx context.Context, repo Repo, visible []string, parentID string) ([]Resource, error) {
    if len(visible) == 0 { return nil, nil }
    return repo.ListByIDs(ctx, parentID, visible)
}
```

## Fail policy

```go
type FailPolicy int
const (
    FailClosed FailPolicy = iota  // return Unavailable
    FailOpenReads                 // proceed without filter (audit-logged)
)
```

## Configuration

| ENV | Default | Description |
|---|---|---|
| `KACHO_AUTHZ_LISTOBJECTS_CACHE_TTL_MS` | 5000 | per-entry TTL |
| `KACHO_AUTHZ_LISTOBJECTS_CACHE_SIZE` | 1000 | LRU entries |
| `KACHO_AUTHZ_LISTOBJECTS_PAGE_DEFAULT` | 1000 | default PageSize |
| `KACHO_AUTHZ_LISTOBJECTS_PAGE_MAX` | 10000 | server-enforced cap |
| `KACHO_AUTHZ_LISTOBJECTS_FAIL_POLICY` | `closed` | `closed` / `open_reads` |

## Imports

- `github.com/hashicorp/golang-lru/v2`
- `crypto/hmac`, `crypto/sha256`, `encoding/base64`
- `kacho-proto/.../iam/v1` — AuthorizeService gRPC stubs

## Imported by

- `kacho-vpc/internal/apps/kacho/api/*` — List handlers
- `kacho-compute/internal/apps/kacho/api/*`
- `kacho-loadbalancer/...` (Phase 4 follow-up, blocked by baseline service — KAC-127 "Out of scope")

## See also

[[../edges/vpc-to-iam-listobjects]] [[../edges/compute-to-iam-listobjects]] [[../rpc/iam-authorize-service]] [[../KAC/KAC-127]]

#packages #kacho-corelib #authz #fga
