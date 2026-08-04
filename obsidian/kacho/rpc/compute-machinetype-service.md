---
title: MachineTypeService + InternalMachineTypeService
aliases:
  - MachineTypeService (compute)
  - InternalMachineTypeService
proto_file: kacho/cloud/compute/v1/machine_type_service.proto
category: rpc
backend: kacho-compute
backend_port: 9090
visibility: mixed
domain: compute
related_resource: "[[resources/compute-machinetype]]"
methods_count: 5
async_methods: 3
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
tags:
  - rpc
  - kacho-compute
  - compute
  - internal
---

# MachineTypeService (compute) — публичное чтение + админский CRUD на :9091

Каталог типоразмеров: **единственный** канал sizing для Instance. Две поверхности,
намеренно разделённые (ban #6).

**Контракты**:
`proto/kacho/cloud/compute/v1/machine_type_service.proto` (публичный) ·
`proto/kacho/cloud/compute/v1/internal_machine_type_service.proto` (админский)
**Ресурс**: [[../resources/compute-machinetype]]

Записка заведена 2026-08-05: ссылка на неё существовала раньше самой записки.

## Публичная поверхность — `MachineTypeService` (:9090)

| Метод | Ответ | Sync/Async | REST | Отношение |
|---|---|---|---|---|
| `Get` | `MachineType` | sync | `GET /compute/v1/machineTypes/{machine_type_id}` | `viewer` (`compute.machineTypes.get`) |
| `List` | `ListMachineTypesResponse` | sync | `GET /compute/v1/machineTypes` | `viewer` (`compute.machineTypes.list`) |

Мутаций на публичной поверхности нет вовсе — каталог курируется администратором.

> [!note] Отношение `viewer` на каталоге — та же полоса, что у geo
> Глобальный курируемый справочник обязан читаться каждым аутентифицированным
> арендатором, иначе он не сможет запустить ни один размещаемый ресурс. Условие
> применимости этой полосы (`security.md` §«Отношение, выполнимое подстановочным знаком»):
> **ответ обязан быть справочником** — единым объектом с одним владельцем, а не выборкой
> по объектам с индивидуальными владельцами. Каталог типоразмеров это условие выполняет;
> списки тенантских ресурсов — нет, и им такая запись не полагается.

## Админская поверхность — `InternalMachineTypeService` (:9091)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Create` | `Operation` | async | `POST /compute/v1/internal/machineTypes` |
| `Update` | `Operation` | async | `PATCH /compute/v1/internal/machineTypes/{machine_type_id}` |
| `Delete` | `Operation` | async | `DELETE /compute/v1/internal/machineTypes/{machine_type_id}` |

Паритет по форме с `geo` (`/geo/v1/internal/…`): админский CRUD **никогда** не выставляется
на внешний mux. Мутации async через `Operation` — в отличие от админского
[[vpc-internal-address-pool-service]], который отдаёт ресурс синхронно.

## Gotcha

- **`id` в hyphen-каноне**: `mt-<17-crockford-base32>` (`ids.PrefixMachineTypeHyphen`).
  Malformed id → `INVALID_ARGUMENT` первым стейтментом; well-formed-но-нет → `NOT_FOUND`.
- **`name` — тоже стабильный кластерный slug** с `UNIQUE`, но адресация ресурса и его
  ссылки — по `id` (ban #15).
- **RETIRED-типоразмер отвергается на `Instance.Create`** (`FAILED_PRECONDITION`),
  DEPRECATED — принимается.
- Ссылка `instances.machine_type_id` — **within-service FK** (миграция
  `0017_instances_machine_type_fk.sql`), а не peer-вызов: обе строки в одной БД.

## См. также

[[../resources/compute-machinetype]] · [[../resources/compute-instance]] · [[compute-instance-service]] · [[geo-region-service]]

#rpc #kacho-compute #compute #internal
