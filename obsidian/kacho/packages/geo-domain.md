---
title: geo-domain
category: package
repo: kacho-geo
layer: domain
status: in-progress
tags:
  - packages
  - kacho-geo
  - domain
  - geo
  - geography
---

# kacho-geo/internal/domain

**Path**: `kacho-geo/internal/domain/`
**Imports**: stdlib + `kacho-proto/gen/go/kacho/cloud/geo/v1` (clean-arch: domain без pgx/grpc).
**Imported by**: use-case (`internal/apps`/`internal/service`), repo, handler.

Self-validating domain-entities leaf-сервиса Geography (вынесен из `kacho-compute` эпиком #82).

## Entities

- `Region` — id (admin-assigned литерал, immutable), name, created_at.
- `Zone` — id (литерал), region_id, status (`UP`/`DOWN`/`UNSPECIFIED`), name, created_at.

## Invariants (DB-уровень — repo, не domain-software-check)

- `zones.region_id` FK → `regions(id)` ON DELETE RESTRICT (регион с зонами не удалить, ban #10).
- id immutable после Create; catalog-семантика (admin задаёт id явно).

## Layering

Leaf-сервис: `go.mod` имеет **только** `replace ../kacho-corelib` + `replace ../kacho-proto`
(НЕ зависит от iam/vpc/compute/nlb по build — как iam). Composition root — `cmd/geo/main.go`;
миграции — `cmd/migrator`. Audit admin-мутаций — `geo_outbox` в writer-TX.

## See also

[[proto-geo]] [[../resources/geo-region]] [[../resources/geo-zone]] [[iam-domain]]

#packages #kacho-geo #domain #geo #geography
