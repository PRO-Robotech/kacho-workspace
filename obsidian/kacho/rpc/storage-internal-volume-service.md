---
title: InternalVolumeService
aliases:
  - InternalVolumeService (storage)
  - storage InternalVolumeService
proto_file: kacho/cloud/storage/v1/internal_volume_service.proto
category: rpc
backend: kacho-storage
backend_port: 9091
visibility: internal
domain: storage
methods_count: 4
async_methods: 0
status: stable
verified_against: "перечень RPC сверен с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-storage
  - storage
  - internal
---

# InternalVolumeService (storage)

**Контракт**: `proto/kacho/cloud/storage/v1/internal_volume_service.proto`
**Backend**: сервис `kacho-storage`, **cluster-internal** листенер **:9091**
**Public/Internal**: внутрикластерно, никогда на внешнем TLS-крае (ban #6)

Здесь живёт **привязка тома к машине** — несущая часть ребра
[[edges/compute-to-storage-volume-resolve]]. REST-маршрутов у этих RPC нет вовсе:
`google.api.http` в proto не объявлен ни у одного из четырёх.

## Методы (4)

| Метод | Ответ | Sync/Async | отношение |
|---|---|---|---|
| `Attach` | `AttachVolumeResponse{Volume}` | **sync** | `editor` на `storage_volume:<id>` + вопрос про машину |
| `Detach` | `DetachVolumeResponse{Volume}` | **sync** | `editor` на `storage_volume:<id>` + вопрос про машину |
| `ListAttachments` | `ListAttachmentsResponse` | sync | отбор по данным (`ScopeFiltered`) |
| `GetInternal` | `VolumeInternal` | sync | `viewer` на `storage_volume:<id>` |

> [!important] Ответ синхронный — и это НЕ нарушение «мутации возвращают Operation»
> Правило про `Operation` — про **публичную** границу, обращённую к арендатору. Она
> здесь и есть: арендатор зовёт `AttachDisk` у compute, тот возвращает `Operation`, и
> внутри своего воркера синхронно дёргает это ребро. Второй асинхронный конверт поверх
> первого не добавил бы ничего, кроме второй очереди для одного намерения.

## Attach — самоописывающийся запрос и один CAS

Запрос несёт **всё** нужное storage, чтобы решить самому: `volume_id`, `instance_id`,
`instance_name`, `instance_zone_id`, `project_id`, `device_name`, `is_boot`, `mode`,
`auto_delete`. Размещение и владелец машины **приезжают в запросе**, а не запрашиваются
обратным вызовом.

> [!important] Ацикличность держится именно на этом
> storage **никогда не зовёт compute**. Если бы он проверял зону машины обращением к
> её владельцу, между двумя доменами появился бы цикл. Вместо этого он валидирует
> **свою** строку одним `INSERT … SELECT … WHERE` с предикатами по своим колонкам, а
> `instance_name` сохраняет как снимок на момент привязки и обратно никогда не
> перечитывает.

Запись — атомарный CAS в одну таблицу привязок с `ON CONFLICT DO NOTHING`, а не
«прочитал → проверил → записал» (ban #10). Ноль строк на выходе разбирается **в той же
транзакции**, и от этого зависит, какой из текстов вернётся:

| Ситуация | Исход |
|---|---|
| повтор той же машиной | **OK**, идемпотентно |
| том занят другой машиной | `FAILED_PRECONDITION` `"Volume <id> is in use"` |
| тома нет / не `READY` | `FAILED_PRECONDITION` `"Volume is not available for attachment"` |
| зона тома ≠ зона машины | `FAILED_PRECONDITION` `"Volume and Instance must be in the same zone"` |
| проект тома ≠ проект машины | `FAILED_PRECONDITION` `"Volume and Instance must be in the same project"` |
| имя устройства занято | `"device <n> is already in use on Instance <id>"` |
| свободных имён устройств нет | `"no free device name on Instance <id>"` |
| второй загрузочный том у машины | отвергается на уровне БД |

**Зона и проект — два РАЗНЫХ предиката с двумя разными текстами.** Свести их в один
общий («не подходит») значило бы отдать вызывающему ответ, по которому нельзя понять,
что чинить.

Пустое `device_name` → назначается первое свободное из ограниченного ряда с ограниченным
числом попыток. `Detach` — удаление строки по паре (том, машина); ноль строк → **OK**,
тоже идемпотентно.

**Второй адресат проверяется отдельно.** У `Attach`/`Detach` два объекта с **разными
владельцами**: том (storage) и машина (compute). Per-RPC проверка покрывает только том,
поэтому право на машину спрашивается в use-case, **до** записи: `Attach` требует права
на правку машины, `Detach` — на правку либо на удаление (удаляющий машину вправе снять
её тома).

## ListAttachments — отбор по данным, а не один вопрос

Единого объекта у метода нет by construction: **машины называет сам вызывающий**.
Поэтому метод помечен `ScopeFiltered`, per-RPC проверка на нём не стоит, а решение
принимается на уровне данных — по видимости **названных машин**.

- неопознанный вызывающий → **`PERMISSION_DENIED`**, а не пустая страница. Пустая
  прочиталась бы как «привязок нет» тем, кто собирается удалять;
- отбор **всё-или-ничего в пределах машины**: это намеренно, иначе поток удаления увидел
  бы не все тома машины, которую ему разрешено снести, и оставил бы висяки;
- строки читаются одним пакетным запросом, порядок — по машине, затем по имени
  устройства. Ответ несёт `VolumeAttachmentInfo`, у которого в отличие от вложенной
  публичной привязки есть `volume_id`.

> [!warning] Комментарии proto и карты прав описывают сужение по ТОМУ — код сужает по МАШИНЕ
> Оба текста на сверенной ревизии говорят про видимость `storage_volume:<id>`, тогда как
> реализация сужает по `compute_instance`; собственная шапка use-case прямо говорит, что
> попытка сужать по тому была откачена. Верно поведение, а не комментарий. Класс —
> `architecture.md` §doc-truthfulness: следующий контрибьютор «чинит» код под неверный
> комментарий. Зафиксировано как факт дерева; правка — на стороне продукта.

## GetInternal — вторая проекция объявлена, но пока пуста

`VolumeInternal` сегодня несёт **только** публичный `Volume`; инфра-поля (адресация в
бэкенде, узел хранения, идентификатор пула, числовой инфра-id) стоят в сообщении
**зарезервированным диапазоном** и намеренно вне области работы до появления data-plane.

**Сам метод пока не реализован** — репозиторий отвечает `UNIMPLEMENTED`. Это объявленный
контракт без реализации, а не сломанная реализация: отличие важно, потому что зелёный
`GetInternal` в наборе проб означал бы не то, что кажется.

## См. также

[[storage-volume-service]] · [[storage-internal-image-service]] ·
[[storage-internal-disktype-service]] · [[edges/compute-to-storage-volume-resolve]] ·
[[rpc/compute-instance-service]] · [[resources/compute-instance]] ·
[[edges/storage-to-iam-fgaproxy]]

#rpc #kacho-storage #storage #internal
