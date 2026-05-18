---
title: corelib-errors
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - errors
  - grpc
---

# corelib/errors

**Path**: `kacho-corelib/errors/`
**Imports**: `google.golang.org/genproto/googleapis/rpc/errdetails`, `google.golang.org/grpc/codes`, `google.golang.org/grpc/status`
**Imported by**: `kacho-resource-manager` (11), `kacho-vpc` (5), `kacho-corelib/validate`

YC-style typed error builder → gRPC `status.Status` + `google.rpc.errdetails.BadRequest`.

## Builders (return `*Builder`)

- `NotFound(kind, id string)` → gRPC `NotFound`, message `"<Kind> <id> not found"`.
- `AlreadyExists(kind, id string)` → `AlreadyExists`.
- `InvalidArgument()` → `InvalidArgument` (chain `.Field("name", "<reason>")`).
- `FailedPrecondition(msg string)` → `FailedPrecondition`.
- `Aborted(msg string)` → `Aborted` (для CAS-conflicts).
- `Unavailable(msg string)` → `Unavailable` (peer-service down).
- `Internal(msg string)` → `Internal`.
- `Gone(msg string)` → 410 (RPC-mapped).

## Builder methods

- `.Field(name, reason)` — добавляет `errdetails.BadRequest_FieldViolation`.
- `.Build() error` — финальная конверсия в `error`.
- `.Status() *status.Status` — без .Err() для inspection.

## YC parity (style only — не структура)

Текст сообщений и regex error-format остаются YC-совместимыми: `<Resource> %s not found`, `<field> is immutable after <Resource>.Create`, `Illegal argument <thing>`, etc. См. workspace CLAUDE.md «YC-стилистика — да, структура методов 1-в-1 — нет».

## See also

[[corelib-validate]] [[vpc-apps-kacho-shared-serviceerr]]

#packages #kacho-corelib #errors #grpc
