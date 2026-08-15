---
title: ImageService
aliases:
  - ImageService (storage)
  - storage ImageService
proto_file: kacho/cloud/storage/v1/image_service.proto
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

# ImageService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/image_service.proto`
**Backend**: сервис `kacho-storage`, публичный листенер **:9090**
**Ресурс**: `Image` — записки в `resources/` нет

Загрузочный образ блочного хранения. **Не путать с OCI-образом реестра**: тот живёт в
домене registry, адресуется натуральным ключом и к этому контракту отношения не имеет
(см. [[registry-registry-service]]).

## Методы (7)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Get` | `Image` | sync | `GET /storage/v1/images/{image_id}` |
| `List` | `ListImagesResponse` | sync | `GET /storage/v1/images` |
| `Create` | `Operation` | async | `POST /storage/v1/images` |
| `Update` | `Operation` | async | `PATCH /storage/v1/images/{image_id}` |
| `Delete` | `Operation` | async | `DELETE /storage/v1/images/{image_id}` |
| `Copy` | `Operation` | async | `POST …/{image_id}:copy` |
| `ListOperations` | `ListImageOperationsResponse` | sync | `GET …/{image_id}/operations` |

Метаданные — `Create/Update/Delete/CopyImageMetadata{image_id}`.

**`Copy` переносит образ в ДРУГОЙ регион и гейтится `editor` на проекте**, а не чтением
источника: копия — новый ресурс (квота, имя, деньги), и гейт на чтение отдал бы наблюдателю
право порождать ресурсы. `targetRegionId` обязателен, `projectId` обязателен.

**Копия называет своего родителя** — поле `sourceImageId` (output-only, ставит только `Copy`,
неизменяемо). Происхождение образа — РОВНО ОДНО из трёх: снимок либо том (снятие, вход
`Create`) либо образ (копирование). До 2026-08-13 третий вид не признавали ни домен, ни
контракт, ни путь чтения, и глагол не работал ни разу с момента заведения.

## Ресурс

Префикс id — **`img`**, отдельный от снятого образа compute.

| Свойство | Значение |
|---|---|
| Статусы | `CREATING` · `READY` · `DELETING` · `ERROR` |
| Размещение | **REGIONAL / anycast** — `region_id`, `placement_type` всегда `REGIONAL` |
| Неизменяемы | `project_id`, `region_id`, `source_snapshot_id` / `source_volume_id` |
| Мутабельны | `name`, `description`, `labels` |
| Output-only | `size_bytes`, `min_disk_bytes`, `format` (единственное значение — `STANDARD`) |

> [!important] Образ РЕГИОНАЛЬНЫЙ — зоны не несёт by construction
> Из **зональной** проверки когерентности он исключён: сравнивать не с чем. Остаётся
> региональная — зона тома обязана лежать **в регионе образа**. Это и есть «исключение
> эникаст» из `data-integrity.md` §Placement-coherence, и именно поэтому у `Image` есть
> `region_id`, но нет `zone_id`.

## Создание

Источник — снимок **либо** том (взаимоисключающе), и зона источника обязана лежать в
регионе образа. Перечень зон региона резолвится у geo **на пути запроса** и только когда
источник действительно назван. Принадлежность источника тому же проекту проверяется тем
же INSERT'ом; кросс-проектный источник отвечает текстом настоящего отсутствия.

На уровне БД взаимоисключение выражено как `CHECK (NOT (source_snapshot_id IS NOT NULL
AND source_volume_id IS NOT NULL))` — **именно «не оба», а не «ровно один»**: обе ссылки
снимаются по `ON DELETE SET NULL`, поэтому пустыми они могут оказаться законно, и
требование «ровно один» ломало бы уже существующие строки. Это происхождение, а не живая
зависимость: удаление источника стирает родословную, блочные данные остаются.

## Список и авторизация

Порядок и механика — как у [[storage-volume-service]] (обязательный `project_id` первым
стейтментом → `page_size` → `filter` → страница курсором → пакетная проверка прав;
отношение видимости `v_get`; ошибка модели fail-closed). Здесь не пересказывается.

`Get`/`Update`/`Delete`/`ListOperations` — глагол объекта на `storage_image:<id>`;
`List`/`Create` — ярус на родительском проекте. Внутренняя проекция образа —
[[storage-internal-image-service]] на :9091.

> [!note] Это состояние дерева, которое ОПЕРЕЖАЕТ ствол
> На сверенной ревизии `Get`/`Update`/`Delete`/`ListOperations` гейтятся глаголом
> объекта; на стволе `redesign/integration@50e5e624` те же четыре несли ярусы
> `viewer`/`editor`. Разница видна прямо в `image_service.proto`.

## Кто потребляет образ

Резолв загрузочного источника инициирует **compute** на создании машины
([[edges/compute-to-storage-volume-resolve]]); том, материализованный из образа, обязан
лежать в зоне, входящей в регион образа — проверка стоит внутри вставки тома
([[storage-volume-service]] §что проверяется).

## См. также

[[storage-volume-service]] · [[storage-snapshot-service]] · [[storage-disktype-service]] ·
[[storage-internal-image-service]] · [[resources/geo-region]] · [[rpc/operation-service]] ·
[[registry-registry-service]]

#rpc #kacho-storage #storage
