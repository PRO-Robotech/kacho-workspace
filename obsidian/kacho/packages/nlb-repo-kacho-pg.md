---
title: nlb-repo-kacho-pg
aliases:
  - nlb CQRS repository
category: packages
repo: kacho-nlb
layer: repo
tags:
  - packages
  - kacho-nlb
  - repo
  - cqrs
  - pg
---

# kacho-nlb/internal/repo/kacho/pg

**Path**: `kacho-nlb/internal/repo/kacho/pg/`
**Imports**: pgx/v5, [[nlb-domain]], [[nlb-dto]], [[corelib-db]]
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]], [[nlb-apps-kacho-api-listener]], [[nlb-apps-kacho-api-targetgroup]], [[nlb-apps-kacho-api-operation]], [[nlb-apps-kacho-api-internal-lifecycle]]

CQRS Repository implementation (evgeniy §G — Reader/Writer split). pgx-based, no ORM. Per-resource sub-packages: `loadbalancer/`, `listener/`, `targetgroup/`, `outbox/`.

## Layout

```
repo/kacho/
├── iface.go                    # top-level Repository / Reader / Writer interfaces
├── entity_*.go                 # per-resource entity transforms (proto/domain ↔ DB row)
├── errors.go                   # SQLSTATE → service.Err mapping
├── iface_load_balancer.go      # LBReader / LBWriter ports
├── iface_listener.go           # ListenerReader / ListenerWriter ports
├── iface_target_group.go       # TGReader / TGWriter ports
├── iface_attached_target_group.go
├── iface_outbox.go             # OutboxWriter (Emit in writer-tx)
└── pg/
    ├── repo.go                 # `Repository{ Read(ctx, fn) / Write(ctx, fn) }` — TX-wrapped
    ├── loadbalancer/           # pg impl per port
    ├── listener/
    ├── targetgroup/
    └── outbox/
```

## CQRS pattern (evgeniy §G)

```go
type Repository interface {
    Read(ctx context.Context, fn func(Reader) error) error
    Write(ctx context.Context, fn func(Writer) error) error
}

type Reader interface {
    LoadBalancers() LBReader
    Listeners() ListenerReader
    TargetGroups() TGReader
    Operations() corelib_ops.Reader
}

type Writer interface {
    Reader   // composition
    LoadBalancers() LBWriter
    Listeners() ListenerWriter
    TargetGroups() TGWriter
    AttachedTargetGroups() AttachedTGWriter
    Outbox() OutboxWriter
    Operations() corelib_ops.Writer
}
```

Read TX — read-only (no DML); Writer TX — full SERIALIZABLE для atomic outbox-in-tx.

## SQLSTATE error mapping

```go
// errors.go
func MapErr(err error) error {
    switch pgErrCode(err) {
    case "23503": return service.ErrFailedPrecondition  // FK violation
    case "23505": return service.ErrAlreadyExists       // UNIQUE
    case "23514": return service.ErrInvalidArgument     // CHECK
    case "23P01": return service.ErrAlreadyExists       // EXCLUDE
    }
    if errors.Is(err, pgx.ErrNoRows) { return service.ErrNotFound }
    return err
}
```

## ExecAbstract pattern (evgeniy §G + §J)

Single TX manager `corelib/db.ExecAbstract(ctx, pool, fn)` wraps `Repository.Write`. Гарантирует commit/rollback одним кодпатом.

## Integration tests

`*_integration_test.go` в каждом sub-package — testcontainers Postgres, covers race-cases (concurrent INSERT/UPDATE на partial UNIQUE + CAS-update).

## See also

[[corelib-db]] [[nlb-domain]] [[nlb-dto]] [[../resources/nlb-load-balancer]]

#packages #kacho-nlb #repo #cqrs #pg
