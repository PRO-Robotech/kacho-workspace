---
title: geo-domain
category: packages
repo: kacho-geo
layer: domain
status: in-progress
tags:
  - packages
  - kacho-geo
  - domain
  - geo
  - geography
verified_against: "координаты записки (composition root, каталог миграций, раскладка модуля) сверены с деревом продукта 1653387b (2026-08-06); состав сущностей и инварианты построчно не пересматривались"
---

# kacho-geo/internal/domain

**Каталог**: `services/geo/internal/domain/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-geo/internal/domain/`)
**Imports**: stdlib + `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/geo/v1` (clean-arch: domain без pgx/grpc).
**Imported by**: use-case (`internal/apps`/`internal/service`), repo, handler.

Self-validating domain-entities leaf-сервиса Geography (вынесен из `kacho-compute` эпиком #82).

## Entities

- `Region` — id (admin-assigned литерал, immutable), name, created_at.
- `Zone` — id (литерал), region_id, status (`UP`/`DOWN`/`UNSPECIFIED`), name, created_at.

## Invariants (DB-уровень — repo, не domain-software-check)

- `zones.region_id` FK → `regions(id)` ON DELETE RESTRICT (регион с зонами не удалить, ban #10).
- id immutable после Create; catalog-семантика (admin задаёт id явно).

## Layering

Leaf-сервис: по build не зависит от iam/vpc/compute/nlb (как iam). Composition root —
`services/geo/cmd/kacho-geo/main.go` — прежняя координата называла каталог бинаря коротким
именем домена, которого в дереве нет: каталог назван по имени сервиса целиком (сам мёртвый
адрес здесь не воспроизводится, иначе разбор снова читался бы как живое утверждение).
Миграции — `services/geo/cmd/migrator/main.go`. Audit admin-мутаций — `geo_outbox` в writer-TX.

> [!note] Подстановок модулей больше нет — предмета у прежней формулировки нет (1653387b, 2026-08-06)
> Она описывала раскладку полирепо, где у geo был собственный модуль с подстановками на
> соседние. Сегодня на всю платформу **один** Go-модуль
> (`github.com/PRO-Robotech/kacho`), поэтому подстановок нет ни одной, и «зависит только
> от двух соседей» выражается не файлом модуля, а графом импортов. Канон — `polyrepo.md`
> §«Build-граф — ОДИН Go-модуль».

## See also

[[proto-geo]] [[../resources/geo-region]] [[../resources/geo-zone]] [[iam-domain]]

#packages #kacho-geo #domain #geo #geography
