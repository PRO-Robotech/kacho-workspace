---
title: SnapshotService
aliases:
  - SnapshotService (storage)
  - storage SnapshotService
proto_file: kacho/cloud/storage/v1/snapshot_service.proto
category: rpc
backend: kacho-storage
backend_port: 9090
visibility: public
domain: storage
methods_count: 5
async_methods: 3
status: stable
verified_against: "перечень RPC и REST-маршруты сверены с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-storage
  - storage
---

# SnapshotService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/snapshot_service.proto`
**Backend**: сервис `kacho-storage`, публичный листенер **:9090**
**Ресурс**: `Snapshot` — записки в `resources/` нет

Точечный слепок тома. Владелец — storage; compute своих снимков **не** держит
(про незавершённый раскол см. §«Чужой снимок»).

## Методы (7)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Get` | `Snapshot` | sync | `GET /storage/v1/snapshots/{snapshot_id}` |
| `List` | `ListSnapshotsResponse` | sync | `GET /storage/v1/snapshots` |
| `Create` | `Operation` | async | `POST /storage/v1/snapshots` |
| `Update` | `Operation` | async | `PATCH /storage/v1/snapshots/{snapshot_id}` |
| `Delete` | `Operation` | async | `DELETE /storage/v1/snapshots/{snapshot_id}` |
| `Copy` | `Operation` | async | `POST …/{snapshot_id}:copy` |
| `ListOperations` | `ListSnapshotOperationsResponse` | sync | `GET …/{snapshot_id}/operations` |

> [!note] Здесь стояло «`ListOperations` у снимка НЕТ» — утверждение пережило свой предмет
> Оно было верным и объясняло, что паритета между ресурсами storage ожидать нельзя. Целевой
> вид API (2026-08-13) паритет **ввёл**: у снимка появились и `ListOperations`, и `Copy`.
> Совет, ради которого абзац написан, остаётся в силе и потому сохранён: **сверяйтесь с
> proto, а не с соседом** — теперь по обратной причине.

Метаданные — `CreateSnapshotMetadata{snapshot_id, source_volume_id}` (несёт **оба** id,
в отличие от соседей), `Update/DeleteSnapshotMetadata{snapshot_id}`.

**`Copy` переносит снимок в ДРУГУЮ зону и гейтится `editor` на проекте** (копия — новый
ресурс, а не чтение источника). `targetZoneId` и `projectId` обязательны.

**Копия называет родителя** — `sourceSnapshotId` (output-only, ставит только `Copy`,
неизменяемо), взаимоисключающий с `sourceVolumeId`: снимок либо снят с тома, либо скопирован
со снимка. До 2026-08-13 второй вид происхождения не был признан, и глагол не работал ни разу.

## Ресурс

Префикс id — **`snp`**. Отдельный от снимка compute намеренно: два разных типа не
должны делить префикс, иначе тип ресурса перестаёт читаться по id.

| Свойство | Значение |
|---|---|
| Статусы | `CREATING` · `READY` · `DELETING` · `ERROR` |
| Размещение | **собственной колонки размещения НЕТ** — наследуется от исходного тома |
| Неизменяемы | `project_id`, `source_volume_id` |
| Мутабельны | `name`, `description`, `labels` |
| Выведено при создании | `size_bytes` — копируется с исходного тома, вызывающим не задаётся |

Полей `updated_at` и `zone_id` у снимка нет вовсе.

> [!important] У снимка нет своего размещения — и это меняет проверку когерентности
> Единственное свидетельство о зоне снимка — его `source_volume_id`. Ссылка снимается по
> `ON DELETE SET NULL` (происхождение, а не живая зависимость), поэтому у снимка с
> удалённым исходным томом зоны нет ни в каком виде. Тогда полоса зональной проверки
> при создании тома из такого снимка **проходит**, а не выдумывает зону. Это осознанный
> размен: зона, которой нет, не сочиняется из соседних полей.

## Создание

Один INSERT с выборкой: исходный том обязан быть **в том же проекте** и в состоянии
`READY`. Кросс-проектный источник отвечает `FAILED_PRECONDITION` с текстом настоящего
отсутствия — существование чужой строки не раскрывается.

Синхронная фаза каждой мутации: валидация домена → границы значений (`description` ≤256,
`labels` ≤64) → сверка с соседями (существование проекта у iam, fail-closed
`UNAVAILABLE`) → чеканка id → строка операции (`done=false`) → фоновый воркер.

## Список и авторизация

Порядок и механика те же, что у [[storage-volume-service]] (обязательный `project_id`
первым стейтментом → `page_size` → `filter` → страница курсором → пакетная проверка прав
по id страницы; отношение видимости `v_get`; ошибка модели fail-closed). Здесь не
пересказывается — предмет один, и разъехаться двум описаниям нельзя.

`Get`/`Update`/`Delete` — глагол объекта на `storage_snapshot:<id>`; `List`/`Create` —
ярус на родительском проекте.

## Владелец у снимка теперь ОДИН — раскол compute→storage завершён

Долгое время `Snapshot` был задвоен: storage числился владельцем, а compute держал
вторую, независимую копию — свои таблицы, свой gRPC-сервис, свои REST-маршруты, свой
префикс id. **На сверенной ревизии этого больше нет.** Копия compute снята целиком:
контрактов `Disk`/`Image`/`Snapshot`/`DiskType` в `proto/kacho/cloud/compute/v1/` нет,
REST-маршрутов блочного хранения под доменом compute край не обслуживает, а таблицы
дропнуты миграциями `0021_drop_block_storage_duplicates` и `0022_drop_disk_types`.
(Сами снятые адреса здесь не воспроизводятся: цитата мёртвого маршрута в обратных
кавычках читается как живое утверждение о дереве — хук свежести справедливо считает
её находкой, и за один ход поймал этот класс трижды, включая правку правил.)
Данные при этом не переносились и не должны были: ни одна миграция никогда не сеяла ни
тома, ни образа, ни снимка, а связующая таблица привязок была дропнута, а не скопирована,
ещё на раннем шаге — раскол с самого начала спроектирован без переноса.

> [!warning] Правила рабочего пространства об этом ещё НЕ знают
> `data-integrity.md` §карта владельцев несёт предупреждение «раскол compute→storage НЕ
> завершён» с замером 2026-07-25 и называет дубль **живым**; таблица доменов в
> `polyrepo.md` описывает `services/compute/` как «+ живой дубль Disk/Image/Snapshot/
> DiskType». Оба утверждения пережили свой предмет. Расхождение зафиксировано здесь
> **как факт дерева**, а не исправлено по месту: правила — предмет отдельного решения,
> и чинить их из записки хранилища значило бы завести третье место об одном предмете.
> Класс — [[lessons/checks-with-form-but-no-substance]] в его документальном изводе.

Что от прежней двойственности **осталось и осталось намеренно**: префиксы id остаются
разными (`snp` у storage), и снятые compute-префиксы всё ещё объявлены в общем каталоге
идентификаторов — id, выданные до снятия, обязаны оставаться разбираемыми.

## Соседи по рантайму

`storage → geo`, `storage → iam` ([[edges/storage-to-iam-fgaproxy]]). Обратно storage
никого не зовёт.

## См. также

[[storage-volume-service]] · [[storage-image-service]] · [[storage-disktype-service]] ·
[[storage-internal-volume-service]] · [[rpc/operation-service]]

#rpc #kacho-storage #storage
