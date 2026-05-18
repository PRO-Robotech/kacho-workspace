---
title: "kacho-corelib/authz"
aliases:
  - corelib authz
  - authz interceptor
category: packages
repo: kacho-corelib
layer: corelib
tags:
  - packages
  - kacho-corelib
  - authz
  - cross-service
  - e3
---

# kacho-corelib/authz

Cross-cutting authz пакет: gRPC unary+stream interceptor поверх внешнего
`CheckClient`-port'а (реализуется per-service adapter'ом к
`kacho-iam.InternalIAMService.Check`).

**Layer:** corelib (shared across kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-iam).

## Файлы

| Файл | Назначение |
|---|---|
| `doc.go` | overview + ASCII-схема pipeline. |
| `types.go` | `RPCMap`, `RPCEntry`, `ObjectExtractor`, `StaticExtractor`, `Decision`, sentinel-errors, `FormatObject`, `FormatSubject`, `methodIsInternal`. |
| `cache.go` | `Cache` — TTL=5s positive-only кеш + `InvalidateBySubject` + `InvalidateAll` + thread-safe. |
| `check_client.go` | port `CheckClient`, helper `CheckClientFunc`, port `CreatorTupleWriter` (D-11). |
| `subject_extract.go` | `defaultSubjectExtractor` через `operations.PrincipalFromContext` (E2). |
| `interceptor.go` | `Interceptor` + `NewInterceptor` + `Unary()` / `Stream()` + lock-free Metrics + `EvictInactiveSubjects`. |
| `rate_limiter.go` | token-bucket per-principal на denied-storm (I10). |
| `listen_invalidate.go` | `ListenInvalidator.Run(ctx)` — pgx LISTEN-loop `kacho_iam_subjects` → `Cache.InvalidateBySubject`. |

## API (порты, экспортируется наружу)

```go
type CheckClient interface {
    Check(ctx, subjectID, relation, object) (bool, error)
}
type CreatorTupleWriter interface {
    WriteCreatorTuple(ctx, subjectID, relation, object) error
}
type ObjectExtractor func(req any) (objectType, objectID string, err error)
func StaticExtractor(objectType string, extractID func(req any) (string, error)) ObjectExtractor
type RPCMap map[string]RPCEntry
type RPCEntry struct { Relation string; Extract ObjectExtractor; Public bool }
```

## Decision pipeline (interceptor.authorize)

1. Breakglass=true → `Allowed` + WARN.
2. RPCMap lookup; not found:
   - `methodIsInternal(fullMethod)` → `Internal` (bypass);
   - иначе → `Unmapped` → `PermissionDenied` (fail-closed).
3. Principal extract; пусто → `Denied`.
4. Object extract; ошибка → `Denied`.
5. Cache lookup (positive-only); hit → `Allowed`/`Denied`.
6. Rate-limit per-principal (denied-storm).
7. `Client.Check(subject, relation, object)`; err → `Unavailable` (fail-closed).
8. allowed → cache positive + `Allowed`; иначе `Denied`.

## Fail modes (acceptance D-6)

- FGA/kacho-iam недоступен → fail-closed `PermissionDenied`.
- `KACHO_<SVC>_AUTHZ__BREAKGLASS=true` → bypass + WARN (dev/emergency).

## Cache invalidation (≤10s revoke, NFR-5)

- TTL=5s positive-only.
- Push-invalidate через `pg_notify('kacho_iam_subjects', subject_id)` →
  `Cache.InvalidateBySubject` (dedicated pgx-conn в `ListenInvalidator.Run`).
- Reconnect → conservative `Cache.InvalidateAll`.

## Decoupling

corelib НЕ импортирует kacho-proto stubs — adapter (`<service>/internal/.../check_client.go`)
живёт в сервисе и импортирует `iamv1.InternalIAMServiceClient`.

## Used by

- [[vpc-apps-kacho-check]] (kacho-vpc)
- [[compute-internal-check]] (kacho-compute)
- kacho-loadbalancer (TODO, KAC-108)
- kacho-iam (self-check для AccessBindingService action)

## See also

[[../edges/iam-to-openfga-check]] [[../edges/vpc-to-iam-check]] [[../edges/compute-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-corelib #authz #cross-service #e3
