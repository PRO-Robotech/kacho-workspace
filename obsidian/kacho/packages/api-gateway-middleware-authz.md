---
title: "api-gateway internal/middleware/authz"
aliases:
  - apigw authz middleware
  - per-rpc authz
category: packages
repo: kacho-api-gateway
layer: middleware
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-api-gateway
  - middleware
  - authz
  - fga
---

# api-gateway `internal/middleware/authz`

Phase 3 — per-RPC authorization-gate middleware. Extracts caller identity from DPoP-bound JWT, calls iam.AuthorizeService.Check, enforces deny.

## Exported API

```go
type AuthzMiddleware struct {
    Client       authz.AuthorizeServiceClient   // → kacho-iam:9090
    Cache        *Cache                          // 5s TTL LRU
    FailPolicy   FailPolicy                      // mutation=closed; read=open_reads (configurable)
    AuditEmitter AuditEmitter
}

func (m *AuthzMiddleware) Unary(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error)
```

## Verb extraction

Per-RPC verb derived from gRPC method full name:
```
/kacho.cloud.vpc.v1.NetworkService/Create → "vpc.networks.create"
/kacho.cloud.compute.v1.InstanceService/Get → "compute.instances.read"
/kacho.cloud.iam.v1.AccessBindingService/Create → "iam.access_bindings.create"
```

Mapping defined в `internal/middleware/authz/verb_registry.go` (generated from proto descriptor + acceptance §"Verb taxonomy").

## Object resolution

Object id для Check — extracted from request:
- `GetXxxRequest{id}` → object = `<type>:{id}`.
- `CreateXxxRequest{folder_id|project_id|account_id}` → object = `<parent_type>:{parent_id}` (нельзя check самого ресурса — он ещё не существует).
- `ListXxxRequest{folder_id}` → object = `project:{folder_id}` (для top-level list permission; per-item filtering — отдельно через ListObjects [[corelib-authz-listobjects]]).

## Fail policy

```go
type FailPolicy struct {
    MutationFailMode FailMode  // closed
    ReadFailMode     FailMode  // open_reads or closed (configurable)
}
type FailMode int
const (
    FailClosed FailMode = iota  // return Unavailable
    FailOpenLogged              // proceed but audit-log (reads only)
)
```

## Implementation snippet

```go
func (m *AuthzMiddleware) Unary(ctx, req, info, next) (interface{}, error) {
    subject := callerSubject(ctx)  // extracted from JWT cnf claim
    verb := verbForMethod(info.FullMethod)
    object := m.resolveObject(req, info)
    
    cacheKey := hashKey(subject, verb, object, callerFreshness(ctx))
    if v, ok := m.Cache.Get(cacheKey); ok {
        return m.dispatch(v, ctx, req, next)
    }
    
    resp, err := m.Client.Check(ctx, &authz.CheckRequest{
        Subject: subject,
        Relation: verb,
        Object: object,
    })
    if err != nil {
        return m.handleAuthzError(err, info, ctx, req, next)
    }
    m.Cache.Set(cacheKey, resp.Allowed, 5*time.Second)
    if !resp.Allowed {
        m.AuditEmitter.Emit(ctx, "iam.authz.denied", subject, verb, object)
        return nil, status.Error(codes.PermissionDenied, "")
    }
    return next(ctx, req)
}
```

## Configuration

| ENV | Default | Description |
|---|---|---|
| `KACHO_API_GATEWAY_AUTHZ_ENABLED` | `true` (Phase 3+) | feature toggle |
| `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN_READS` | `false` | enable fail-open для read RPCs |
| `KACHO_API_GATEWAY_AUTHZ_CACHE_TTL_MS` | 5000 | per-entry TTL |
| `KACHO_API_GATEWAY_AUTHZ_CACHE_SIZE` | 10000 | LRU |
| `KACHO_API_GATEWAY_AUTHZ_IAM_ADDR` | `kacho-iam:9090` | target |
| `KACHO_API_GATEWAY_AUTHZ_IAM_TIMEOUT_MS` | 30 | hard per-call timeout |

## Imports

- `google.golang.org/grpc`, `google.golang.org/grpc/codes/status`
- `github.com/hashicorp/golang-lru/v2`
- `kacho-proto/.../iam/v1` — Authorize stubs

## Imported by

- `cmd/kacho-api-gateway/main.go` — registered as `grpc.ChainUnaryInterceptor(..., authzMiddleware.Unary, ...)`

## See also

[[api-gateway-middleware-dpop]] [[corelib-authz-listobjects]] [[../rpc/iam-authorize-service]] [[../edges/api-gateway-to-iam-authorize]] [[../KAC/KAC-127]]

#packages #kacho-api-gateway #middleware #authz #fga
