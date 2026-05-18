---
title: corelib-retry
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - retry
  - grpc
---

# corelib/retry

**Path**: `kacho-corelib/retry/`
**Imports**: `corelib/backoff`, `grpc/codes`, `grpc/status`, `context`, `errors`, `time`
**Imported by**: `kacho-vpc` (3 files — peer-clients)

Retry-helpers для gRPC-вызовов peer-сервисам.

## Exported

- `OnUnavailable(ctx, fn func(ctx) error) error` — повторяет `fn` пока status-code = `Unavailable`; exponential backoff из [[corelib-backoff]].
- `OnAborted(ctx, fn) error` — то же для `Aborted` (CAS-conflicts на CAS-paths).
- `OnCodes(ctx, fn, codes ...codes.Code) error` — общая форма.
- `var Defaults = struct{ InitialInterval, MaxInterval, MaxElapsedTime, Multiplier ... }` — настройки backoff'а (override через builder).

## Usage

```go
err := retry.OnUnavailable(ctx, func(ctx context.Context) error {
    return folderClient.Exists(ctx, folderID)
})
```

## See also

[[corelib-backoff]] [[vpc-clients]] [[../edges/vpc-to-rm-folder-exists]]

#packages #kacho-corelib #retry #grpc
