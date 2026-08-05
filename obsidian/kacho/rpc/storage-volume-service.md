---
title: VolumeService
aliases:
  - VolumeService (storage)
  - storage VolumeService
proto_file: kacho/cloud/storage/v1/volume_service.proto
category: rpc
backend: kacho-storage
backend_port: 9090
visibility: public
domain: storage
methods_count: 6
async_methods: 3
status: stable
verified_against: "перечень RPC и REST-маршруты сверены с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-storage
  - storage
---

# VolumeService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/volume_service.proto`
**Backend**: сервис `kacho-storage`, публичный листенер **:9090**
**Ресурс**: `Volume` — записки в `resources/` нет (домен storage там не представлен вовсе)

Арендаторский CRUD блочного тома. **Привязка тома к машине здесь не живёт** — она у
[[storage-internal-volume-service]] на :9091 и инициируется compute.

## Методы (6)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Get` | `Volume` | sync | `GET /storage/v1/volumes/{volume_id}` |
| `List` | `ListVolumesResponse` | sync | `GET /storage/v1/volumes` |
| `Create` | `Operation` | async | `POST /storage/v1/volumes` |
| `Update` | `Operation` | async | `PATCH /storage/v1/volumes/{volume_id}` |
| `Delete` | `Operation` | async | `DELETE /storage/v1/volumes/{volume_id}` |
| `ListOperations` | `ListVolumeOperationsResponse` | sync | `GET …/{volume_id}/operations` |

Метаданные операций — `Create/Update/DeleteVolumeMetadata{volume_id}`.
Префикс операции storage — **`sop`** (по нему край маршрутизирует `OperationService.Get`).

## Ресурс

`Volume` — **зональный** постоянный блочный диск, префикс id **`vol`**.
Гостевая ОС на нём не лежит: она приезжает образом на старте машины, том — чистое
персистентное блочное состояние, и может неограниченно долго жить без единой привязки.

| Свойство | Значение |
|---|---|
| Статусы | `CREATING` · `AVAILABLE` · `IN_USE` · `DELETING` · `ERROR` |
| Размещение | **ZONAL** — `zone_id` |
| Неизменяемы | `project_id`, `zone_id`, `disk_type_id`, `block_size`, `source_snapshot_id`, `source_image_id` |
| Мутабельны | `name`, `description`, `labels`, `size_bytes` — **только в сторону увеличения** |
| Output-only | `attachments` · `used_by` (обобщённая проекция тех же привязок) |

**`AVAILABLE` и `IN_USE` — выведенные значения**, а не хранимая колонка: они читаются из
наличия строки привязки и поэтому разъехаться с ней не могут. `used_by` на вход
`Create`/`Update` не принимается.

## Что проверяется при создании — и где

Все проверки происхождения и размещения стоят **внутри одного INSERT**, а не «прочитал →
сверил → записал» (ban #10). Отсюда их наблюдаемые тексты:

| Проверка | Исход |
|---|---|
| зона тома ∈ регион образа | `FAILED_PRECONDITION` `"Volume and Image must be in the same region"` |
| зона тома = зона снимка | `FAILED_PRECONDITION` `"Volume and Snapshot must be in the same zone"` |
| тип диска предлагается в этой зоне | `FAILED_PRECONDITION` `"DiskType <id> is not offered in zone <zone>"` |
| размер ≥ минимума образа | `INVALID_ARGUMENT` `"Volume size %d is less than image min_disk_bytes %d"` |
| источник принадлежит тому же проекту | `FAILED_PRECONDITION` `"<Resource> <id> not found"` |

> [!important] Регион зоны берётся резолвом у geo, НИКОГДА не выводится из имени
> Связка «зона → её регион» приходит из `geo` на пути запроса
> ([[edges/compute-to-geo-zone-validate]] — то же правило для соседнего домена).
> Пустой резолв региона означает, что полоса образа не сойдётся, — то есть отказ, а не
> тождественно-истинное сравнение с пустой строкой. Почему это non-negotiable, а не
> вкусовщина, — `data-integrity.md` §Placement-coherence.

**Порядок ответа на кросс-проектный источник стоит понимать.** Полоса проекта отвечает
**первой** и байт-в-байт тем же текстом, что настоящее отсутствие. Следствие для чтения
диагностики: несовпадение размещения называется вслух только для источника, который
вызывающий и так вправе видеть.

## Список: порядок проверок — часть контракта

`project_id` обязателен (пустой → `INVALID_ARGUMENT` `"projectId is required"` первым
стейтментом) → `page_size` → `filter` (белый список — сейчас только `name=`) → чтение
страницы курсором → **и только потом** отбор по видимости. То есть мусорный курсор даёт
`400` независимо от того, какие права у вызывающего, а не пустую страницу
(`api-conventions.md` §Gotcha про List).

Отбор идёт **по данным**: страница читается из своей БД, затем задаётся пакетный вопрос
модели прав по id этой страницы (партии ≤100). Перечисление вселенной разрешённых
объектов не используется намеренно — у такого перечисления жёсткий серверный предел без
продолжения. Отношение видимости — **`v_get`**, ровно то, что энфорсит `Get`; значит
«видно в списке» ⟺ «`Get` разрешён». Ошибка модели — fail-closed, страница не отдаётся
неотфильтрованной. Страница может вернуться **частичной**: `next_page_token` идёт за
последней **просмотренной** строкой, поэтому обход полон и ни одна строка не
пропускается.

## Кто авторизуется

`Get`/`Update`/`Delete`/`ListOperations` — глагол **самого объекта**
(`v_get`/`v_update`/`v_delete`/`v_list` на `storage_volume:<id>`);
`List`/`Create` — ярус на родительском проекте (`viewer`/`editor`).

> [!note] Это состояние дерева, которое ОПЕРЕЖАЕТ ствол
> На ревизии, по которой сверена записка, чтение и мутации гейтятся глаголом объекта;
> на стволе `redesign/integration@50e5e624` те же четыре RPC несли ярусы `viewer`/`editor`
> на объекте. Разница видна прямо в proto. Читая записку против ствола, сверьтесь с
> `volume_service.proto` — расхождение ожидаемо и не является ошибкой записки.

## Соседи по рантайму

`storage → geo` (существование зоны, резолв региона зоны), `storage → iam`
(существование проекта, per-RPC Check, регистрация владельца —
[[edges/storage-to-iam-fgaproxy]]). Резолв источника загрузки инициирует **compute**
([[edges/compute-to-storage-volume-resolve]]); обратно storage compute не зовёт —
ацикличность держится.

## См. также

[[storage-internal-volume-service]] · [[storage-snapshot-service]] ·
[[storage-image-service]] · [[storage-disktype-service]] · [[rpc/operation-service]] ·
[[resources/compute-instance]] · [[resources/geo-zone]]

#rpc #kacho-storage #storage
