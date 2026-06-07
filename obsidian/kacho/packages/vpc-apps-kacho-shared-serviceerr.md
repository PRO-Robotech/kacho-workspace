---
title: vpc-apps-kacho-shared-serviceerr
category: package
repo: kacho-vpc
layer: service
tags:
  - packages
  - kacho-vpc
  - shared
  - errors
---

# kacho-vpc/internal/apps/kacho/shared/serviceerr

**Path**: `kacho-vpc/internal/apps/kacho/shared/serviceerr/`

Единая точка трансляции repo-ошибок → gRPC status + error-builders (shared-leaf, skill evgeniy §1 A.3).

## Exported API

- `MapRepoErr(err) error` — repo-sentinel → gRPC code + verbatim-YC текст (`stripSentinel` снимает sentinel-префикс; неклассифицированный err → `Internal "internal database error"`, no-leak).
- `InvalidArg(field, desc string) error` — `InvalidArgument` + `BadRequest.field_violations` (verbatim-YC parity). **Добавлено KAC-261** при дедупе 8 локальных `invalidArg`-копий из `api/<resource>/`.
- Sentinel re-export через `var`-alias `repo.ErrX`: `ErrNotFound` / `ErrAlreadyExists` / `ErrInvalidArg` / `ErrFailedPrecondition` / `ErrInternal` / `ErrPoolNotResolved` / `ErrInvalidIPv4` / `ErrMacCollision` / `ErrPoolExhausted` (так `errors.Is(err, serviceerr.ErrX)` работает на ошибке из repo).

## KAC-261 dedup

8 локальных `mapRepoErr`/`stripSentinel` копий из `api/<resource>/helpers.go` заменены на `serviceerr.MapRepoErr`; 8 `invalidArg` → `serviceerr.InvalidArg`. Byte-identical — verbatim-YC текст сохранён. См. [[../KAC/KAC-261]], [[vpc-apps-kacho-shared-pbconv]].

## See also

[[corelib-errors]] [[vpc-repo-helpers]]

#packages #kacho-vpc #shared #errors
