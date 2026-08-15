---
title: vpc-apps-kacho-shared-pbconv
category: packages
repo: kacho-vpc
layer: handler
tags:
  - packages
  - kacho-vpc
  - shared
  - handler
  - dto
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/shared/pbconv

**Каталог**: `services/vpc/internal/apps/kacho/shared/pbconv/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/shared/pbconv/`)

Shared proto-conversion хелперы для transport-слоя (создан KAC-261 при дедупе).

## Exported API

- `OperationToProto(op *operations.Operation) *operationpb.Operation` — domain Operation → proto
  (id/description/created_at/created_by/modified_at/done/metadata/principal_*/result oneof).
  `nil`-guard (returns nil). Заменил 9 byte-identical копий `operationToProto` (8 `api/<resource>/handler.go`
  + удалённый `internal/handler/mapping.go`).
- `SubjectFromContext(ctx) string` — FGA-subject (`user:usr_x` / `service_account:sva_x`) из
  `operations.PrincipalFromContext`; `""` для system-principal (no-auth dev). Заменил 8 копий
  (`fgaSubjectFromCtx`×7 + `subjectFromCtx` в network).

## Imports

`context`, `corelib/operations`, `kacho-proto/.../operation` (operationpb), `protobuf/timestamppb`.

## See also

[[vpc-apps-kacho-shared-serviceerr]] [[vpc-handler]] [[../KAC/KAC-261]]

#packages #kacho-vpc #shared #handler #dto
